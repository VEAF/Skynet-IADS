local ctx = ...
ctx.state.order = {}
ctx:add("SAM")
ctx:add("DEPOT")
ctx:onCleanup(function()
	table.insert(ctx.state.order, "A")
end)
ctx:onCleanup(function()
	table.insert(ctx.state.order, "B")
end)
