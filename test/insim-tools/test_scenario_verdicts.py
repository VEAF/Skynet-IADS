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
