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

CASES = {
    "iads-builds": [
        ("one site and one radar", {"sam": 1, "ew": 1}, True),
        ("no site", {"sam": 0, "ew": 1}, False),
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
