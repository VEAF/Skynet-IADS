local ctx = ...
local watch = ctx.state.watch

watch:waitFor("autonomous", { false, true }, 570)
return watch:report()
