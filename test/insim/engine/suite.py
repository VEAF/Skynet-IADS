"""The test layer outside DCS: finds scenarios, runs each as a chain of mailbox commands, judges it.

A scenario is a folder (`scenario.lua`, `setup.lua`, `run.lua`, `verify.lua`, optional `teardown.lua`).
Its chain is setup, run (only after setup is done), teardown, cleanup, each one mailbox command sent
through the driver. The verdict comes from the first of setup and run that did not end `done`, else
from the judge on run's result.
"""

import json
from dataclasses import dataclass, field
from pathlib import Path

from . import luadata
from .driver import SILENCE, read_journal, read_outcome

__all__ = ["SuiteError", "Scenario", "Verdict", "discover", "select", "run_scenario", "summary", "write_report", "rejudge", "exit_code"]

INVALID = "INSIM-INVALID: "
REQUIRED = ("scenario", "setup", "run", "verify")
PHASES = ("setup", "run", "teardown", "cleanup")
VERDICTS = ("pass", "fail", "invalid", "crashed", "skipped")


class SuiteError(Exception):
    pass


@dataclass
class Scenario:
    name: str
    tier: str  # "minimal", "full" or None
    mission: str
    timeout: float
    has_teardown: bool


@dataclass
class Verdict:
    name: str
    verdict: str  # pass, fail, invalid, crashed, skipped
    message: str = ""
    result: object = None
    warnings: list = field(default_factory=list)


def discover(folder):
    found = []
    for path in sorted(Path(folder).iterdir()):
        if not path.is_dir():
            continue
        for part in REQUIRED:
            if not (path / (part + ".lua")).is_file():
                raise SuiteError("scenario %s has no %s.lua" % (path.name, part))
        try:
            meta = luadata.parse((path / "scenario.lua").read_text(encoding="utf-8"))
        except luadata.LuaDataError as e:
            raise SuiteError("scenario %s: scenario.lua is not a plain `return { ... }` table: %s" % (path.name, e)) from e
        for key in ("mission", "timeout"):
            if not isinstance(meta, dict) or key not in meta:
                raise SuiteError("scenario %s: scenario.lua has no %s" % (path.name, key))
        found.append(Scenario(path.name, meta.get("tier"), meta["mission"], meta["timeout"], (path / "teardown.lua").is_file()))
    return found


def select(scenarios, tier, names):
    if names:
        by_name = {s.name: s for s in scenarios}
        unknown = [n for n in names if n not in by_name]
        if unknown:
            raise SuiteError("unknown scenario: %s" % ", ".join(unknown))
        return [by_name[n] for n in names]
    wanted = {"minimal": ("minimal",), "full": ("minimal", "full")}[tier]
    return [s for s in scenarios if s.tier in wanted]


def _phase_code(name, phase):
    return 'return Hotload.load("insim").phase("%s", "%s")' % (name, phase)


def _cleanup_code(name):
    return 'return Hotload.load("insim").cleanup("%s")' % name


def _failure(name, outcome):
    """The verdict for a setup or run that did not end `done`."""
    error = outcome.error or outcome.status
    if outcome.status == "crashed":
        return Verdict(name, "crashed", error)
    if outcome.error and outcome.error.startswith(INVALID):
        return Verdict(name, "invalid", outcome.error[len(INVALID) :])
    return Verdict(name, "fail", error)


def _warning(phase, outcome):
    return "%s failed: %s — the next scenario may start from a dirty world" % (phase, outcome.error or outcome.status)


def _crashed(name, phase, outcome):
    return Verdict(name, "crashed", "%s during %s" % (outcome.error or "crashed", phase))


def run_scenario(driver, judge, s, open_mission):
    if s.mission != open_mission:
        return Verdict(s.name, "skipped", "needs " + s.mission)

    def send(phase, code):
        return driver.run("%s/%s" % (s.name, phase), "%s-%s" % (s.name, phase), code, s.timeout)

    def crashed(phase, outcome):
        # the restarted mission may have run a stale setup: cleanup removes what it left (on a clean mission it does nothing)
        if phase != "cleanup":
            send("cleanup", _cleanup_code(s.name))
        return _crashed(s.name, phase, outcome)

    ended = [(p, driver.entry("%s/%s" % (s.name, p))) for p in PHASES]
    ended = [(p, e) for p, e in ended if e and e.get("state") == "ended"]
    if ended and ended[-1][0] != "cleanup":
        # mission-side state (context, units, IADS) lives only as long as the mission instance that built it
        phase, last = ended[-1]
        if driver.wait_for_mission(SILENCE)["time"] < last["sent_at"]:
            send("cleanup", _cleanup_code(s.name))
            return Verdict(s.name, "crashed", "DCS went down after " + phase)

    setup = send("setup", _phase_code(s.name, "setup"))
    if setup.status == "crashed":
        return crashed("setup", setup)
    run = None
    if setup.status == "done":
        run = send("run", _phase_code(s.name, "run"))
        if run.status == "crashed":
            return crashed("run", run)
    warnings = []
    if s.has_teardown:
        teardown = send("teardown", _phase_code(s.name, "teardown"))
        if teardown.status == "crashed":
            return crashed("teardown", teardown)
        if teardown.status != "done":
            warnings.append(_warning("teardown", teardown))
    cleanup = send("cleanup", _cleanup_code(s.name))
    if cleanup.status == "crashed":
        return crashed("cleanup", cleanup)
    if cleanup.status != "done":
        warnings.append(_warning("cleanup", cleanup))
    verdict = _verdict(s, setup, run, judge)
    verdict.warnings = warnings
    return verdict


def _verdict(s, setup, run, judge):
    if setup.status != "done":
        return _failure(s.name, setup)
    if run.status != "done":
        return _failure(s.name, run)
    ok, message = judge(s, run.result)
    return Verdict(s.name, "pass" if ok else "fail", "" if ok else message, run.result)


def rejudge(journal, scenarios, judge):
    entries = read_journal(journal)
    verdicts = []
    for s in scenarios:
        outcomes = {}
        for phase in PHASES:
            entry = entries.get("%s/%s" % (s.name, phase))
            if entry and entry.get("state") == "ended":
                outcomes[phase] = read_outcome(entry)
        setup, run = outcomes.get("setup"), outcomes.get("run")
        crash = next((p for p in PHASES if p in outcomes and outcomes[p].status == "crashed"), None)
        if crash:
            verdicts.append(_crashed(s.name, crash, outcomes[crash]))
            continue
        if setup is None or (setup.status == "done" and run is None):
            continue
        verdict = _verdict(s, setup, run, judge)
        verdict.warnings = [_warning(p, outcomes[p]) for p in ("teardown", "cleanup") if p in outcomes and outcomes[p].status != "done"]
        verdicts.append(verdict)
    return verdicts


def summary(verdicts):
    lines = []
    for v in verdicts:
        lines.append("%s: %s%s" % (v.name, v.verdict, " - " + v.message if v.message else ""))
        lines.extend("  warning: " + w for w in v.warnings)
    counts = ", ".join("%d %s" % (sum(1 for v in verdicts if v.verdict == name), name) for name in VERDICTS)
    lines.append(counts)
    return "\n".join(lines)


def _cell(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def write_report(verdicts, path):
    lines = ["| name | verdict | message | result | warnings |", "| --- | --- | --- | --- | --- |"]
    for v in verdicts:
        result = "" if v.result is None else json.dumps(v.result, default=str)
        cells = [v.name, v.verdict, v.message, result, "; ".join(v.warnings)]
        lines.append("| " + " | ".join(_cell(c) for c in cells) + " |")
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def exit_code(verdicts):
    return 0 if all(v.verdict in ("pass", "skipped") for v in verdicts) else 1
