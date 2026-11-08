local ctx = ...
local object = { alive = true }
function object:isExist()
	return self.alive
end
function object:destroy()
	self.alive = false
end
ctx.state.object = object
ctx.state.returned = ctx:track(object)
