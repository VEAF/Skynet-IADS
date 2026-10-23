local ctx = ...

ctx:add("SAM-SA6")
ctx:add("EW")
ctx.state.iads = Hotload.load("insim-skynet").iads(ctx)
