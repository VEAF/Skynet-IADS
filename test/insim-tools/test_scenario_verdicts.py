"""Every scenario's verify.lua, judged against results written by hand: one that passes, and at least
one that must not. A verify.lua that cannot go red is not a check. Nothing needs DCS.

Each scenario task adds its cases to CASES: name -> [(label, result, expected_ok)].
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "test", "insim"))
from engine import verify  # noqa: E402

SCENARIOS = Path(ROOT) / "test" / "insim" / "scenarios"

IADS_BUILDS = {
    "sam": 3,
    "ew": 3,
    "samNames": ["iads-builds/SAM-SA10", "iads-builds/SAM-SA6", "iads-builds/SAM-SA8"],
    "sa10": {"nato": "SA-10", "launchers": 2, "searchRadars": 1, "trackingRadars": 1},
    "sa8": {"nato": "SA-8", "launchers": 1, "searchRadars": 1, "trackingRadars": 0},
    "sa6": {"nato": "SA-6", "launchers": 2, "searchRadars": 1, "trackingRadars": 0},
    "ew1l13": {"nato": "Box Spring", "workingRadar": True, "awacs": False},
    "awacs": {"nato": "A-50", "workingRadar": True, "awacs": True},
}

NETWORK = {name: {"held": True, "autonomous": True} for name in (
    "samConnectionNode", "ewConnectionNode", "ewPowerSource", "ewDestroyed",
    "commandCentre", "commandCentrePower", "commandCentreNode")}

MUNITIONS = {
    "bomb": {"torM2": [False, True, False], "sa10": [False], "sa6": [False]},
    "missile": {"torM2": [False, True, False], "sa10": [False, True, False], "sa6": [False]},
}

CASES = {
    "iads-builds": [
        ("as built", IADS_BUILDS, True),
        ("the static taken as a site", dict(IADS_BUILDS, samNames=IADS_BUILDS["samNames"] + ["iads-builds/SAM-STATIC"]), False),
        ("the group of trucks taken as a site", dict(IADS_BUILDS, samNames=["iads-builds/SAM-NOTSAM"] + IADS_BUILDS["samNames"]), False),
        ("a radar missing", dict(IADS_BUILDS, ew=2), False),
        ("SA-10 without its tracking radar", dict(IADS_BUILDS, sa10=dict(IADS_BUILDS["sa10"], trackingRadars=0)), False),
        ("SA-8 without its launcher", dict(IADS_BUILDS, sa8=dict(IADS_BUILDS["sa8"], launchers=0)), False),
        ("1L13 radar not working", dict(IADS_BUILDS, ew1l13=dict(IADS_BUILDS["ew1l13"], workingRadar=False)), False),
        ("A-50 not read as an AWACS", dict(IADS_BUILDS, awacs=dict(IADS_BUILDS["awacs"], awacs=False)), False),
    ],
    "sam-engages": [
        ("woke, fired, slept", {"active": [False, True, False], "firing": [False, True, False]}, True),
        ("never woke", {"active": [False], "firing": [False]}, False),
        ("woke and stayed live", {"active": [False, True], "firing": [False, True]}, False),
        ("raised and lowered every cycle", {"active": [False, True, False, True, False], "firing": [False, True, False]}, False),
        ("woke without firing", {"active": [False, True, False], "firing": [False]}, False),
    ],
    "sam-loses-power": [
        ("dark and unusable", {"powerLost": True, "dark": True, "usable": 0}, True),
        ("the event never arrived", {"powerLost": True, "dark": False, "usable": 0}, False),
        ("still usable", {"powerLost": True, "dark": True, "usable": 1}, False),
        ("power still counted", {"powerLost": False, "dark": True, "usable": 0}, False),
    ],
    "network-loses-infrastructure": [
        ("every case held, then autonomous", NETWORK, True),
        ("a case never held", dict(NETWORK, ewPowerSource={"held": False, "autonomous": True}), False),
        ("a case never autonomous", dict(NETWORK, commandCentreNode={"held": True, "autonomous": False}), False),
        ("a case missing", {k: v for k, v in NETWORK.items() if k != "ewDestroyed"}, False),
    ],
    "autonomous-site-engages": [
        ("live and fired", {"liveFirst": True, "active": [True], "firing": [False, True]}, True),
        ("dark at the start", {"liveFirst": False, "active": [False, True], "firing": [False, True]}, False),
        ("never fired", {"liveFirst": True, "active": [True], "firing": [False]}, False),
    ],
    "harm-defence": [
        ("silenced and back", {"active": [True, False, True], "harm": [False, True, False]}, True),
        ("never silenced", {"active": [True], "harm": [False, True]}, False),
        ("never back", {"active": [True, False], "harm": [False, True]}, False),
        ("no HARM identified", {"active": [True, False, True], "harm": [False]}, False),
        ("flapped after coming back", {"active": [True, False, True, False, True], "harm": [False, True, False]}, False),
    ],
    "harm-point-defence": [
        ("site live, point defence engaged", {"site": [True], "pointDefence": [False, True, False], "harm": [False, True, False]}, True),
        ("site silenced", {"site": [True, False, True], "pointDefence": [False, True, False], "harm": [False, True]}, False),
        ("point defence never woke", {"site": [True], "pointDefence": [False], "harm": [False, True]}, False),
        ("no HARM identified", {"site": [True], "pointDefence": [False, True, False], "harm": [False]}, False),
    ],
    "munitions-wake-sites": [
        ("each site as it can engage", MUNITIONS, True),
        ("every site wakes for a bomb", dict(MUNITIONS, bomb={"torM2": [False, True, False], "sa10": [False, True, False], "sa6": [False, True, False]}), False),
        ("the SA-10 sleeps through a missile", dict(MUNITIONS, missile=dict(MUNITIONS["missile"], sa10=[False])), False),
        ("the Tor M2 sleeps through a bomb", dict(MUNITIONS, bomb=dict(MUNITIONS["bomb"], torM2=[False])), False),
        ("the SA-6 wakes for a missile", dict(MUNITIONS, missile=dict(MUNITIONS["missile"], sa6=[False, True, False])), False),
    ],
    "coverage-follows-awacs": [
        ("held, then handed back", {"autonomous": [False, True]}, True),
        ("never held", {"autonomous": [True]}, False),
        ("never handed back", {"autonomous": [False]}, False),
    ],
    "last-line-of-defence": [
        ("lit, then quiet", {"active": [False, True, False], "radius": 12000}, True),
        ("never lit", {"active": [False], "radius": 12000}, False),
        ("lit and never quiet", {"active": [False, True], "radius": 12000}, False),
        ("lit again after going quiet", {"active": [False, True, False, True], "radius": 12000}, False),
    ],
    "ew-detects-aircraft": [
        ("detected", {"detected": True}, True),
        ("never detected", {"detected": False}, False),
    ],
}


class ScenarioVerdictTest(unittest.TestCase):
    def setUp(self):
        self.lua = verify.find_lua(None)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def test_each_case_is_judged_as_expected(self):
        for name, cases in CASES.items():
            for label, result, expected in cases:
                with self.subTest(scenario=name, case=label):
                    ok, message = verify.judge(self.lua, SCENARIOS / name, result, Path(self.tmp.name) / "result.lua")
                    self.assertEqual(ok, expected, message)

    def test_every_scenario_has_a_case_that_must_fail(self):
        names = sorted(p.name for p in SCENARIOS.iterdir() if p.is_dir() and not p.name.startswith("selftest-"))
        missing = [n for n in names if not any(expected is False for _, _, expected in CASES.get(n, []))]
        self.assertEqual(missing, [], "these scenarios have no case their verify.lua must fail")


if __name__ == "__main__":
    unittest.main()
