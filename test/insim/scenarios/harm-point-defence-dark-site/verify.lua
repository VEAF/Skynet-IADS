return function(result, lu)
	-- the SA-10 learnt of the HARM, and forgot it
	lu.assertEquals(result.harm, { false, true, false }, "the SA-10 never learnt of the HARM, or never forgot it")
	-- dark when told of the HARM, and dark throughout: it never had a target, nor a scan from goLive()
	lu.assertEquals(result.site, { false })
	-- live for the HARM, then released once the HARM is forgotten, rather than live for good
	lu.assertEquals(result.pointDefence, { false, true, false })
end
