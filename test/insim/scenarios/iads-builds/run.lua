local ctx = ...
local iads = ctx.state.iads

return { sam = #iads:getSAMSites(), ew = #iads:getEarlyWarningRadars() }
