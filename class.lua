local class = {}

function class.make(obj)
	local meta = {
		__index = function(tbl, index)
			return obj[index]
		end
	}

	local newObj = {}
	setmetatable(newObj, meta)

	return newObj
end

return class.make