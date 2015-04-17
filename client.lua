local clientClass = {}
clientClass.timeout = 5

function clientClass:settimeout(timeout)
	self.timeout = timeout
end

function clientClass:receive(amount)
	local data
	local deadline = socket.gettime() + self.timeout

	while true do
		data, err = self.socket:receive(amount)
		if data or (err and err ~= "timeout") or (self.timeout > 0 and socket.gettime() > deadline) then
			--print("Got data: " .. data)
			return data, err
		else
			coroutine.yield()
		end
	end
end

function clientClass:send(data)
	return self.socket:send(data)
end

function clientClass:close()
	return self.socket:close()
end

return clientClass