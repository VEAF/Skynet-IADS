#!/usr/bin/env python3
"""Run Skynet's in-sim smoke checks against a mission open in DCS.

The standalone suite proves that a function does what it says. It cannot prove that the simulator
ever calls it, that the artifact loads in the real engine, or that the mission somebody downloads
still demonstrates what it claims. That is what this does: it sends small pieces of Lua into a
running DCS through VEAF's dcs-bridge, reads back one tagged word per check, and prints a verdict.

**This is not a CI gate and cannot become one.** GitHub runners have no DCS, no licence and no GPU.
Both sibling projects reached the same conclusion and wrote it down -- CTLD_Next's
`tools/integration-runner/` and VMCT's `veaf-tools dcs smoke-test` are local tools too. So is this
one, and it is *consultative*: David's call on 2026-09-21, it informs a release rather than blocking
one. When there is nothing to talk to it says so and exits 0, rather than failing for the absence of
a simulator.

Prerequisites, on the machine running DCS:

  * `MissionScripting.lua` not sanitised, or the bridge cannot open its socket;
  * `dcs-serve` running, with `dcs-bridge.lua` loaded by the mission;
  * the mission built **with the bridge in it** and open:
    `python build-tools/miz-suite.py build --with-bridge`. The archives in git hold placeholders,
    and only `last-line-of-defence` carries dcs-bridge.lua of its own -- the demos are release
    assets and must not ship a socket, so the bridge is injected into the git-ignored build only.

Usage, from anywhere (paths resolve from this file):

    python build-tools/run-smoke.py --list
    python build-tools/run-smoke.py --target demo
    python build-tools/run-smoke.py --target lastline --tier slow

The token is read from `--token`, else `$DCS_BRIDGE_API_KEY`, else the `api_key` line of a
`dcs-client.yaml` beside the dcs-bridge checkout. `exec` is gated to the `superuser` role, so an
operator token is refused with 403 and this says so rather than reporting every check as failed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

REPO_ROOT = Path(__file__).resolve().parents[1]

#: What the bridge gives back when it cannot give back what the Lua returned.
#:
#: `handleExec` in dcs-bridge.lua ends on `tostring(result ~= nil and result or "")`. That idiom is
#: the classic Lua trap: when the Lua returns `false`, `result ~= nil` is true, `true and false` is
#: `false`, and `false or ""` is `""`. So **a boolean `false` arrives as the empty string**, exactly
#: like a `nil` -- and a table arrives as `table: 0x...`, which is truthy and says nothing.
#:
#: VMCT hit the same wall from the other side and paid for it twice: a check whose answer was a
#: boolean came back empty and could not tell "DCS said no" from "the reply was destroyed", which is
#: worse than a wrong answer because it is quiet. Hence the house rule, which CTLD reached
#: independently: **a check returns a word, never a boolean, never a table.**
#:
#: Tracked upstream as VEAF/VEAF-dcs-bridge#35, which proves all four cases against a live DCS:
#: `true` gives `"true"`, and `false`, `nil` and no return at all are indistinguishable. Until that
#: lands, the rule below is the workaround, and it stays worth keeping afterwards -- a word says more
#: at a glance than a boolean.
#:
#: `_expectations_reject_transport_loss` in the tests sweeps every expectation below against this.
#: An expectation that `""` can satisfy is an expectation that cannot tell success from a value the
#: transport threw away.
TRANSPORT_LOSS: frozenset[str] = frozenset({""})

#: Verdicts that mean "ask me again", for checks that watch something unfold.
PENDING: frozenset[str] = frozenset({"RUNNING", "STARTED"})


@dataclass(frozen=True)
class Check:
    """One question put to the running mission.

    Attributes:
        name: Short identifier, printed and used by `--only`.
        target: Which mission has to be open for this check to mean anything.
        tier: `fast` answers immediately; `slow` watches something fly and takes minutes.
        lua: The code sent to DCS. Must return a word -- see :data:`TRANSPORT_LOSS`.
        expect: Predicate over the returned word.
        why: What this check is for. Printed on failure, so it has to be worth reading then.
        arm: Optional code run once before polling starts, for a check that sets something going.
        poll: Whether to re-send `lua` while the answer is in :data:`PENDING`.
    """

    name: str
    target: str
    tier: str
    lua: str
    expect: Callable[[str], bool]
    why: str
    arm: str | None = None
    poll: bool = False


def _pcall(body: str) -> str:
    """Wrap a Lua body so a raise comes back as a readable word rather than a bridge error.

    The bridge would report a raise correctly through its `error` field, but the message it carries
    is then all we get. Catching it here lets a check say which of its own steps blew up.
    """
    return f"local ok, verdict = pcall(function() {body} end) if not ok then return 'raised: ' .. tostring(verdict) end return verdict"


# --- the checks -------------------------------------------------------------------------------
#
# Deliberately few. Each one has to be able to fail, and to fail for a reason worth a release being
# held up over. A check that cannot go red is a line of output, not a test.

CHECKS: tuple[Check, ...] = (
    Check(
        name="artifact-loaded",
        target="demo",
        tier="fast",
        lua=_pcall("if type(SkynetIADS) ~= 'table' then return 'skynet-absent' end return tostring(SkynetIADS.version)"),
        # Pinned to the shape of a version rather than to "not one of the sentinels". The first
        # draft was the latter, and the transport-loss sweep caught it going green on '' -- which is
        # what the bridge returns for a boolean, and for a `nil` the tostring() above cannot reach.
        # An allow-list of shapes cannot make that mistake; a deny-list of known-bad values can.
        expect=lambda v: bool(re.fullmatch(r"\d+\.\d+\.\d+[\w.+-]*", v)),
        why="The build proves the sources concatenate and check-artifact.lua proves the result runs "
        "under a stub. Neither proves it loads in the real engine, which is where DCS's own Lua "
        "5.1 and its sanitisation live. Prints the version, so a stale mission shows up as the "
        "wrong number rather than as a pass.",
    ),
    Check(
        name="networks-built",
        target="demo",
        tier="fast",
        lua=_pcall(
            "if type(redIADS) ~= 'table' then return 'no-red-iads' end "
            "local sam = #redIADS:getSAMSites() local ewr = #redIADS:getEarlyWarningRadars() "
            "return string.format('sam:%d ewr:%d', sam, ewr)"
        ),
        expect=lambda v: bool(re.fullmatch(r"sam:[1-9]\d* ewr:[1-9]\d*", v)),
        why="Prefix discovery is how every mission maker wires a network, and it is the step that "
        "silently finds nothing when a group is renamed. Non-zero on both counts only -- the "
        "exact figures are not pinned here until a run has measured them, rather than guessed.",
    ),
    Check(
        name="named-elements-found",
        target="demo",
        tier="fast",
        lua=_pcall(
            "if type(redIADS) ~= 'table' then return 'no-red-iads' end "
            "local missing = {} "
            "local sites = { 'SAM-SA-2', 'SAM-SA-6', 'SAM-SA-11', 'SAM-SA-11-2' } "
            "for i = 1, #sites do "
            "if redIADS:getSAMSiteByGroupName(sites[i]) == nil then missing[#missing + 1] = sites[i] end end "
            "local radars = { 'EW-Center3', 'AWACS-K-50' } "
            "for i = 1, #radars do "
            "if redIADS:getEarlyWarningRadarByUnitName(radars[i]) == nil then missing[#missing + 1] = radars[i] end end "
            "if #missing > 0 then return 'missing: ' .. table.concat(missing, ',') end "
            "return 'all-found'"
        ),
        expect=lambda v: v == "all-found",
        why="These six are named by the demo's own setup script, which configures each one "
        "individually. Asserting the network can hand them back proves prefix discovery reached "
        "them and the lookups work -- and unlike a count, it is not derived from the same table "
        "the network read.",
    ),
    Check(
        name="jammer-alive",
        target="demo",
        tier="fast",
        lua=_pcall(
            "local emitter = Unit.getByName('jammer-emitter') "
            "if emitter == nil then return 'emitter-gone' end "
            "if not emitter:isExist() then return 'emitter-dead' end "
            "return 'alive'"
        ),
        expect=lambda v: v == "alive",
        why="FIX-DEMO-DESTROYS-ITS-JAMMER: a guard of walder's destroyed this aircraft at t=0 on "
        "every single load from 2020 to 2026, because it tested a client slot before any client "
        "could occupy it. Nothing went red -- no test looked, and the jammer disarmed in silence. "
        "This is the check that would have caught it, and the reason it exists.",
    ),
    Check(
        name="no-mist",
        target="demo",
        tier="fast",
        lua=_pcall("return type(mist)"),
        expect=lambda v: v == "nil",
        why="fe40c4a took MiST out of Skynet on 2026-08-30 and FIX-DEMO-MISSIONS-SHIP-A-2023-SKYNET "
        "took it out of the archives. If it comes back, MiST installs its own event handler and a "
        "DEAD event for an object it does not know puts a popup on the player's screen -- which is "
        "how we found it the first time, by flying the demo.",
    ),
    Check(
        name="last-line-of-defence",
        target="lastline",
        tier="slow",
        arm="return SKYNET_TEST.launchIntruder()",
        lua=_pcall("return SKYNET_TEST.verdict()"),
        expect=lambda v: v == "PASS",
        poll=True,
        why="A battery the network holds dark has to wake on proximity alone, and fall silent again "
        "once the intruder leaves. Both halves, because a run that only ever shows one proves "
        "nothing. This is the mechanism FEAT-LAST-LINE-OF-DEFENSE added and the one no stub test "
        "can reach: the failure that matters is code that is perfectly tested and never called.",
    ),
    Check(
        name="coverage-follows-what-moves",
        target="lastline",
        tier="slow",
        arm="return SKYNET_TEST.startCoverageRun()",
        lua=_pcall("return SKYNET_TEST.coverageVerdict()"),
        expect=lambda v: v == "PASS",
        poll=True,
        why="A battery whose only parent is an AWACS must be held non-autonomous while that AWACS "
        "covers it, and handed back once it leaves. The incremental rebuild never purged, so an "
        "aircraft in transit used to accumulate every battery it had flown near and hold them all.",
    ),
)

TARGETS: dict[str, str] = {
    "demo": "demo-missions/skynet-test-persian-gulf.miz",
    "lastline": "unit-tests/last-line-of-defence/skynet-insim-last-line-of-defence.miz",
}


# --- talking to the bridge --------------------------------------------------------------------


class NotReady(Exception):
    """DCS is not connected to dcs-serve. The reason to skip, not to fail."""


class BridgeRefused(Exception):
    """dcs-serve answered, and said no -- a bad token, or a role below superuser."""


@dataclass
class Bridge:
    """A thin client over `POST /api/exec`.

    Deliberately `urllib` rather than `requests`: this repository's Python tooling carries no
    dependencies, and `miz-suite.py` sets that precedent.
    """

    url: str
    token: str
    timeout: float = 30.0

    def exec_lua(self, code: str) -> str:
        """Send Lua, return what it returned.

        Raises:
            NotReady: DCS is not connected (HTTP 503).
            BridgeRefused: the token was rejected, or lacks the superuser role.
            RuntimeError: the Lua raised, or the command timed out.
        """
        body = json.dumps({"code": code, "timeout": self.timeout}).encode()
        request = urllib.request.Request(
            f"{self.url}/api/exec",
            data=body,
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {self.token}"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout + 10) as response:
                payload = json.loads(response.read())
        except urllib.error.HTTPError as error:
            if error.code == 503:
                raise NotReady("dcs-serve is up but DCS is not connected") from error
            if error.code in (401, 403):
                raise BridgeRefused(
                    f"dcs-serve refused the token (HTTP {error.code}). /api/exec needs the superuser role."
                ) from error
            if error.code == 504:
                raise RuntimeError("the command timed out inside DCS") from error
            raise RuntimeError(f"dcs-serve answered HTTP {error.code}") from error
        except urllib.error.URLError as error:
            raise NotReady(f"no dcs-serve at {self.url} ({error.reason})") from error

        # A Lua error comes back as HTTP **200** with an `error` field. Reading the status code alone
        # would take it for an answer -- which is the shape of the trap VMCT documented, arriving
        # here by a different road.
        if payload.get("ready") is False:
            raise NotReady("dcs-serve reports DCS not connected")
        if payload.get("error"):
            raise RuntimeError(str(payload["error"]))
        return str(payload.get("result", ""))


# --- running ----------------------------------------------------------------------------------


@dataclass
class Outcome:
    """What became of one check."""

    check: Check
    verdict: str
    passed: bool
    detail: str = ""


def select(target: str | None, tier: str | None, only: list[str] | None) -> list[Check]:
    """The checks a given invocation should run, in declaration order."""
    chosen = list(CHECKS)
    if target:
        chosen = [c for c in chosen if c.target == target]
    if tier and tier != "all":
        chosen = [c for c in chosen if c.tier == tier]
    if only:
        wanted = set(only)
        chosen = [c for c in chosen if c.name in wanted]
    return chosen


def run_check(bridge: Bridge, check: Check, poll_timeout: float, sleep: Callable[[float], None]) -> Outcome:
    """Run one check, polling it to a terminal verdict when it asks to be.

    `sleep` is injected so the tests can drive a polled check without waiting for real seconds.
    """
    if check.arm:
        try:
            bridge.exec_lua(check.arm)
        except RuntimeError as error:
            return Outcome(check, "ABORT", False, f"arming failed: {error}")

    waited = 0.0
    interval = 5.0
    while True:
        try:
            verdict = bridge.exec_lua(check.lua)
        except RuntimeError as error:
            return Outcome(check, "ABORT", False, str(error))

        if verdict in TRANSPORT_LOSS:
            # Not a failure of the thing under test. The check returned something the transport
            # cannot carry, and saying "failed" here would send somebody hunting a phantom.
            return Outcome(
                check,
                "ABORT",
                False,
                "empty reply -- the check returned a boolean, a nil or a table. It must return a word.",
            )
        if not (check.poll and verdict in PENDING):
            return Outcome(check, verdict, check.expect(verdict))
        if waited >= poll_timeout:
            return Outcome(check, verdict, False, f"still {verdict} after {poll_timeout:.0f}s")
        sleep(interval)
        waited += interval


def report(outcomes: list[Outcome], out=sys.stdout) -> int:
    """Print the table and return the exit code."""
    if not outcomes:
        print("no check matched the selection", file=out)
        return 0

    width = max(len(o.check.name) for o in outcomes)
    failed = [o for o in outcomes if not o.passed]
    for outcome in outcomes:
        mark = "PASS" if outcome.passed else "FAIL"
        detail = outcome.detail or outcome.verdict
        print(f"  {mark}  {outcome.check.name:<{width}}  {detail}", file=out)

    print(f"\n{len(outcomes) - len(failed)}/{len(outcomes)} passed", file=out)
    for outcome in failed:
        print(f"\n{outcome.check.name}: {outcome.check.why}", file=out)
    return 1 if failed else 0


# --- configuration ----------------------------------------------------------------------------


def find_token(explicit: str | None) -> str:
    """The bearer token, from the flag, the environment, or a dcs-client.yaml next door.

    The last one is a convenience for the common layout where dcs-bridge is checked out beside this
    repository; it is a one-line parse on purpose, not a YAML dependency.
    """
    if explicit:
        return explicit
    from_env = os.environ.get("DCS_BRIDGE_API_KEY")
    if from_env:
        return from_env
    candidate = REPO_ROOT.parent / "VEAF-dcs-bridge" / "dcs-client.yaml"
    if candidate.is_file():
        for line in candidate.read_text(encoding="utf-8").splitlines():
            match = re.match(r'\s*api_key\s*:\s*["\']?([^"\'#\s]+)', line)
            if match:
                return match.group(1)
    return ""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run Skynet's in-sim smoke checks against a mission open in DCS.",
        epilog="Consultative, not a gate: no simulator means skipped, not failed.",
    )
    parser.add_argument("--list", action="store_true", help="print the checks and exit")
    parser.add_argument("--target", choices=sorted(TARGETS), help="only checks for this mission")
    parser.add_argument("--tier", choices=["fast", "slow", "all"], default="fast", help="default: fast")
    parser.add_argument("--only", nargs="+", metavar="NAME", help="run these checks by name")
    parser.add_argument("--url", default="http://127.0.0.1:8080", help="dcs-serve base URL")
    parser.add_argument("--token", help="bearer token; else $DCS_BRIDGE_API_KEY, else dcs-client.yaml")
    parser.add_argument("--timeout", type=float, default=30.0, help="per-command timeout, seconds")
    parser.add_argument("--poll-timeout", type=float, default=600.0, help="how long a slow check may run")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    checks = select(args.target, args.tier, args.only)

    if args.list:
        for check in CHECKS:
            print(f"  {check.tier:<5} {check.target:<9} {check.name}")
        print("\nMissions these need open in DCS:")
        for name, path in sorted(TARGETS.items()):
            print(f"  {name:<9} {path}")
        return 0

    if not checks:
        print("no check matched the selection")
        return 0

    token = find_token(args.token)
    if not token:
        # Said here rather than left to a 403, which would blame the role when the truth is that
        # nothing was sent at all.
        print("no token: pass --token, set $DCS_BRIDGE_API_KEY, or put api_key in dcs-client.yaml")
        return 2

    print(f"{len(checks)} check(s) against {args.url}\n")
    bridge = Bridge(args.url, token, args.timeout)

    outcomes: list[Outcome] = []
    for check in checks:
        try:
            outcomes.append(run_check(bridge, check, args.poll_timeout, time.sleep))
        except NotReady as error:
            # The self-skipping stance, borrowed from VMCT: the absence of a simulator is not a
            # result about Skynet, and reporting it as one trains people to ignore the output.
            print(f"skipped: {error}")
            print("\nNothing was measured. Start DCS with the mission open and dcs-serve running.")
            return 0
        except BridgeRefused as error:
            print(f"refused: {error}")
            return 2

    return report(outcomes)


if __name__ == "__main__":
    sys.exit(main())
