#!/usr/bin/luajit

local port = 8080
local host = "*"

socket = require("socket")
class = require("class")
local clientClass = require("client")
local handler = require("handler")

local server = socket.bind(host, port)
server:settimeout(0)

math.random(os.time())

local connections = {}

while true do
	repeat
		local client = server:accept()
		if client then
			client:settimeout(0)

			local clientObject = class(clientClass)
			clientObject.socket = client

			local cor = coroutine.create(handler)
			connections[#connections + 1] = {cor, clientObject}
			--coroutine.resume(cor, clientObject)
		end
	until not client

	local i = 1
	local v

	while i <= #connections do
		v = connections[i]
		success, err = coroutine.resume(v[1], v[2])
		if coroutine.status(v[1]) == "dead" then
			if not success then
				print("Error: " .. err)
			end

			connections[i] = connections[#connections]
			connections[#connections] = nil
			i = i - 1

			v[2]:close()
		end
		i = i + 1
	end

	--[[
	local toRemove = {}

	for i, v in ipairs(connections) do
		success, err = coroutine.resume(v[1], v[2])
		if coroutine.status(v[1]) == "dead" then
			if not success then
				print("Error: " .. err)
			end

			toRemove[#toRemove + 1] = i
			v[2]:close()
		end
	end

	for i, v in ipairs(toRemove) do
		table.remove(connections, v)
	end
	--]]

	socket.sleep(0)
end