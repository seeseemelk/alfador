local pageHandler = require("page")
local statusCodes = require("status")

local requestN = 0

sessions = {}

-- This is the main handler that will take over once the client is conencted
function initialHandler(client)
	local connectionTerminated = true

	repeat
		local forceCode

		local requestType, URL, version = getRequest(client)
		local httpHeaders = getHeaders(client)
		requestN = requestN + 1
		print("Request number " .. requestN)
		
		if version ~= "HTTP/1.1" then
			forceCode = 505
		end

		-- Process GET
		local GET = {}
		if URL:find("%?") then
			local requestLine = URL:match("%?(.*)$")

			if not requestLine:find("&$") then
				requestLine = requestLine .. "&"
			end

			for name, value in requestLine:gmatch("(.-)=(.-)&") do
				value = isNumber(value) or value
				GET[name] = value
			end
		end

		-- Process POST
		local POST = {}
		if requestType == "POST" then
			print("Got POST request")
			local data = client:receive(httpHeaders["Content-Length"])
			if data then
				print("Data: " .. data)
			end
			forceCode = forceCode or 415
		end

		-- Load cookies
		local receivedCookies = {}
		local cookies = class(receivedCookies)
		if httpHeaders["Cookie"] then
			for name, value in httpHeaders["Cookie"]:gmatch("(%w+)=(%w+)") do
				print("Found cookie: " .. name .. "=" .. value)
				receivedCookies[name] = value
			end
		end

		-- Load session
		local session, sessionStarted, sessionID = loadSessionCookies(cookies)

		-- Process page and send data
		local handler = coroutine.wrap(pageHandler)
		local firstLoop = true
		repeat
			local code, responseHeader, responseData, continue = handler(client, {
				URL = URL,
				GET = GET,
				POST = POST,
				header = httpHeaders,
				version = version,
				cookies = cookies,
				sessionID = sessionID,
				session = session
			})
			code = forceCode or code

			if firstLoop then
				-- Send status code
				--[[if code == 200 then
					client:send(version .. " 200 OK\n")
				elseif code == 404 then
					client:send(version .. " 404 Not Found\n")
				elseif code == 418 then
					client:send(version .. " 418 Unsupported Media Type\n")
				elseif code == 500 then
					client:send(version .. " 500 Internal Server Error\n")
				else
					print("Unknown code " .. code)
					client:send(version .. " " .. code)
				end--]]
				client:send(version .. " " .. code .. " " .. statusCodes[code])

				-- Send header fields
				print("Response headers:")
				for name, value in pairs(responseHeader) do
					print(name .. " = " .. value)
					client:send(name .. ": " .. value .. "\n")
				end

				-- Send new cookies or changed cookies
				for i, v in pairs(cookies) do
					if receivedCookies[i] ~= v then
						client:send("Set-Cookie: " .. i .. "=" .. v .. "\n")
					end
				end

				-- Send removed cookies
				for i, v in pairs(receivedCookies) do
					if v and not cookies[i] then
						client:send("Set-Cookie: " .. i ..
							"=nil; expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0\n")
					end
				end

				client:send("\n")
				firstLoop = false
			end

			client:send(responseData)
			coroutine.yield()
		until not continue
	until connectionTerminated

	client:close()

	return
end

-- This function will return true when value is a number
function isNumber(value)
	if type(value) == "number" then
		return true
	elseif type(value) == "string" then
		if tonumber(value) then
			return true 
		else
			return false
		end
	else
		return false
	end
end

-- Receive and parse the request line
function getRequest(client)
	local data = client:receive("*l")

	return data:match("^(.-) (.-) (.-)$")
end

-- Receive the headers and returns a table
function getHeaders(client)
	local headers = {}

	repeat
		local data = client:receive("*l")
		if data and data:find(": ") then
			local name, value = data:match("^(.-): (.-)$")
			headers[name] = value
		end
	until not data or data:find("^%s*$")

	return headers
end

-- This function mill return a table with session cookies
function loadSessionCookies(cookies)
	if cookies["session"] and sessions[cookies["session"]] then
		return sessions[cookies["session"]], true, cookies["session"]
	else
		return nil, false, cookies["session"]
	end
end

-- This function will start the session
function startSession(cookies)
	if cookies["session"] and sessions[tostring(cookies["session"])] then
		-- Stop session or just return?
		return sessions[tostring(cookies["session"])], cookies["session"]
	end

	local ID = math.random(0, 2^32)

	cookies["session"] = tostring(ID)
	sessions[tostring(ID)] = {}

	local session = sessions[tostring(ID)]

	return session, ID
end

-- This function will stop the session
function stopSession(cookies)
	local ID = cookies["session"]
	sessions[ID] = nil
	cookies["session"] = nil
end

return initialHandler