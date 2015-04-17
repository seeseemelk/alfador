local mimetypes = require("mimetypes")

local env = {
	tonumber = tonumber,
	tostring = tostring,
	pcall = pcall,
	xpcall = xpcall,
	ipairs = ipairs,
	pairs = pairs,
	setmetatable = setmetatable,
	getmetatable = getmetatable,
	string = class(string),
	math = class(math),
	class = class,
	global = {},
}

-- This file will handle a page
function handlePage(client, options)
	local GET = options.GET
	local POST = options.POST
	local headers = options.headers
	local httpVersion = options.version
	local URL = options.URL

	-- Responses
	local responseHeaders = {}

	-- Try and resolve the url
	local path, exists = resolveURL(URL)

	-- Return a 404 when the file is not found
	if not exists then
		return 404, {}, "", false
	end

	-- Find out the MIME type
	local mime = getMimeType(path)
	if mime then
		responseHeaders["Content-Type"] = mime
	end

	local options = {
		URL = URL,
		GET = GET,
		POST = POST,
		headers = headers,
		httpVersion = httpVersion,
		path = path,
		mime = mime,
		statusCode = 200,
		responseHeaders = responseHeaders,
		cookies = options.cookies,
		data = {},
		session = options.session,
		sessionID = options.sessionID
	}

	options.pushData = function(data)
		options.data[#options.data + 1] = data
	end

	options = executeFile(options.path, options)
	options.data = table.concat(options.data)

	options.responseHeaders["Content-Length"] = #options.data 
	options.responseHeaders["Connection"] = "close"

	return options.statusCode, options.responseHeaders,
		options.data, false
end

-- This function will resolve the url to a path
function resolveURL(url)
	-- Remove GET request
	if url:find("%?") then
		url = url:match("^(.-)%?")
	end

	-- Append www folder
	local file = "./www"

	-- Remove .. injections
	url:gsub("[/\\]%.%.", "")
	url:gsub("[/\\]%.", "")

	-- Redirects ( / --> /index.html, etc )
	if url == "/" then
		file = file .. "/index.html"
	else
		file = file .. url
	end

	-- Handle access file
	file = parseAccessFile(file, url).path

	-- Check if the file exists
	local filehandle = io.open(file)
	local hasFile = filehandle and true or false
	if filehandle then filehandle:close() end

	-- Return
	return file, hasFile
end

-- This function accepts a file path and will return a table
-- Containing info
function parseAccessFile(path, url)
	local returnOptions = {
		path = path
	}

	-- Check for a .access file in the same directory
	local directory = path:match("^(.*)/.-$") .. "/"
	print(path .. " is in " .. directory)

	local accessHandle = io.open(directory .. ".access")
	local hasAccess = accessHandle and true or false
	accessHandle:close()

	-- Only do the next part if the file access
	if hasAccess then
		-- Iterate over the lines
		for line in io.lines(directory .. ".access") do
			local lineType, value1, value2 = line:match("^(%w*): (%S*) (%S*)")
			if lineType == "redirect" and value1 == url then
				print("Redirect: " .. value1 .. " points to " .. value2)
				returnOptions.path = "./www/" .. value2
			end
		end
	end

	return returnOptions
end

-- This function will return the MIME type of a file
function getMimeType(path)
	return mimetypes.guess(path)
end

-- This function will execute a lua file
function executeFile(path, options, customEnv)
	--print("Executing " .. path)
	local fileContents = getContents(path)
	local pageParts, luaCode = prepareLuaCode(fileContents)
	luaCode = assert(loadstring(luaCode, "=" .. options.path))

	local useEnv = customEnv or class(env)
	setfenv(luaCode, useEnv)

	-- Set some global veriables
	env.GET = options.GET
	env.POST = options.POST
	env.cookies = options.cookies
	env.session = options.session

	-- Setup some extra function
	env.needPagePart = function(part)
		options.pushData(pageParts[part])
	end
	env.print = function(data)
		options.pushData(data)
	end
	env.require = function(path)
		options = executeFile("./www/" .. path, options, customEnv)
	end
	env.flush = function()
		return options.statusCode, options.responseHeaders,
			options.data, true
	end
	env.startSession = function()
		options.session, options.sessionID = startSession(options.cookies)
		env.session = options.session
	end
	env.stopSession = function()
		stopSession(options.cookies)
		options.session = nil
		env.session = nil
	end

	local success, err = pcall(luaCode)
	if not success then
		options.statusCode = 500
		env.print("\nError running lua script: " ..
			tostring(err) .. "\n")
		print("Error running script: " .. tostring(err))
	end

	return options
end

-- Thus function will get the contents of a file
function getContents(file)
	local file = assert(io.open(file, "r"))
	local data = file:read("*all")
	file:close()

	return data
end

-- This function will take all parts of lua code in a file and put
-- them together with intermidiate calls
function prepareLuaCode(page)
	local locations = getLuaLocations(page)

	-- Check if there is any lua code at all
	if #locations < 1 then
		return {page}, "needPagePart(1)"
	end

	local lastEnd = locations[#locations][2]
	locations[#locations + 1] = {#page + 1, #page + 1}

	local pageData = {}
	local luaData = {}
	local lastEnd = 1
	for i, v in ipairs(locations) do
		if not v[1] then
			error("No matching opening brackets for lua script")
		elseif not v[2] then
			error("No matching closing brackets for lua script")
		end
		pageData[#pageData + 1] = page:sub(lastEnd, v[1] - 1)
		lastEnd = v[2] + 1
		luaData[#luaData + 1] = "needPagePart(" .. #pageData .. ")"
		luaData[#luaData + 1] = page:sub(v[1]+5, v[2]-5)
	end

	return pageData, table.concat(luaData, "\n")
end

-- This function will find the locations of lua code in a html file
function getLuaLocations(page)
	local locations = {}

	local lastEnd = nil

	repeat
		local s1 = string.find(page, "<%?lua", lastEnd)
		local _, e2 = string.find(page, "lua%?>", lastEnd)
		lastEnd = e2 or #page

		if s1 then
			locations[#locations + 1] = {s1, e2}
		end

	until not s1

	return locations
end

return handlePage