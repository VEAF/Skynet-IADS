local ctx = ...
ctx.state.order = {}
ctx:onCleanup(function()
	error("a broke")
end)
ctx:onCleanup(function()
	table.insert(ctx.state.order, "B")
end)
