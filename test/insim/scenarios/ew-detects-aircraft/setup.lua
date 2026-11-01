local ctx = ...

ctx:add("EW")
ctx:add("TARGET")
ctx.state.iads = Hotload.load("insim-skynet").iads(ctx)
