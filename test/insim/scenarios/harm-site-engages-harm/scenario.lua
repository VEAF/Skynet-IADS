return {
	mission = "insim-ca-main",
	tags = { "tier-full", "harm" },
	-- the run waits at most 300 (woken) + 20 (holding fire) + 180 (shot) + 180 (HARM) + 180 (forgotten) + 10
	timeout = 900,
}
