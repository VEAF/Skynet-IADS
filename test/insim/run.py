"""The one command: python test/insim/run.py [--tier minimal|full] [--skynet FILE] [--resume] [--verify] [--lua PATH] [NAME ...]"""

import argparse
import sys
import uuid
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import json  # noqa: E402

import skynet_script  # noqa: E402
from engine import mission, suite, verify  # noqa: E402
from engine.driver import Driver  # noqa: E402
from engine.mailbox import Mailbox  # noqa: E402

REPO = HERE.parent.parent
STALE = "the mission runs an older Skynet script: restart the mission"
PROBE_CODE = 'return Hotload.load("insim").status()'
CHECK_CODE = 'return Hotload.load("insim-skynet").scriptIsCurrent()'
CHECK_TIMEOUT = 30.0


def _parser():
    p = argparse.ArgumentParser(prog="run.py", description="Run the in-sim test suite.")
    p.add_argument("--tier", choices=("minimal", "full"), default="minimal")
    p.add_argument("--skynet", metavar="FILE", help="load this Skynet script instead of the repository's build")
    p.add_argument("--resume", action="store_true", help="continue the latest run")
    p.add_argument("--verify", action="store_true", help="judge the latest run's recorded results again, send nothing")
    p.add_argument("--lua", metavar="PATH", help="the Lua 5.1 interpreter")
    p.add_argument("names", nargs="*", metavar="NAME")
    return p


def _latest(results):
    folders = sorted(p for p in results.iterdir() if p.is_dir()) if results.is_dir() else []
    return folders[-1] if folders else None


def _finish(verdicts, folder, repo, report="report.md"):
    print(suite.summary(verdicts))
    suite.write_report(verdicts, folder / report)
    path = folder / report
    try:
        path = path.relative_to(repo)
    except ValueError:
        pass
    print("report: " + path.as_posix())
    return suite.exit_code(verdicts)


def main(argv=None, repo=REPO, now=datetime.now):
    args = _parser().parse_args(argv)
    repo = Path(repo)
    insim = repo / "test" / "insim"
    scenarios_dir = insim / "scenarios"
    results = repo / "build" / "insim" / "results"
    try:
        lua = verify.find_lua(args.lua)
        scenarios = suite.discover(scenarios_dir)

        def judge(scenario, result):
            return verify.judge(lua, scenarios_dir / scenario.name, result, folder / (scenario.name + ".result.lua"))

        if args.verify:
            folder = _latest(results)
            if folder is None:
                print("no results folder to verify in " + str(results))
                return 2
            run = json.loads((folder / "run.json").read_text(encoding="utf-8"))
            chosen = suite.select(scenarios, run["tier"], run["names"])
            print("verify: re-judging %s from %s" % (", ".join(s.name for s in chosen) or "nothing", (folder / "journal.jsonl").as_posix()))
            verdicts = suite.rejudge(folder / "journal.jsonl", chosen, judge)
            for s in chosen:
                if s.name not in [v.name for v in verdicts]:
                    print("verify: %s has no recorded result to re-judge" % s.name)
            return _finish(verdicts, folder, repo, "report-verify.md")

        forced = Path(args.skynet) if args.skynet else None
        _, done = skynet_script.prepare(repo, forced)
        print("Skynet script: " + {"up to date": "up to date (built from the current sources)", "rebuilt": "rebuilt", "forced": "forced from %s" % forced}[done])
        mailbox = Mailbox(insim / "dcs-hotload")
        mailbox.ensure()
        names = []
        for template in sorted((insim / "miz").glob("*.template.miz")):
            name = template.name[: -len(".template.miz")]
            written = mission.prepare(template, template.with_name(name + ".miz"), insim / "dcs-hotload")
            print("mission %s: working copy %s" % (name, "written" if written else "up to date"))
            names.append(name)

        if args.resume:
            folder = _latest(results)
            if folder is None:
                print("no run to resume in " + str(results))
                return 2
            run = json.loads((folder / "run.json").read_text(encoding="utf-8"))
        else:
            folder = results / now().strftime("%Y%m%d-%H%M%S")
            run = {"tier": args.tier, "names": args.names}
        chosen = suite.select(scenarios, run["tier"], run["names"])  # refused before anything is sent
        for s in chosen:
            if s.mission not in names:
                raise suite.SuiteError("scenario %s: mission %r is not one of the missions in test/insim/miz (%s)" % (s.name, s.mission, ", ".join(names)))
        if not args.resume:
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "run.json").write_text(json.dumps(run), encoding="utf-8")

        console = suite.Console(lambda text: (sys.stdout.write(text), sys.stdout.flush()), len(chosen))
        driver = Driver(mailbox, folder / "journal.jsonl", PROBE_CODE, say=console.say)
        hint = "run %s in DCS (missions: %s)" % (" or ".join("test/insim/miz/%s.miz" % n for n in names), ", ".join(names))
        open_mission = driver.wait_for_mission(hint)["mission"]
        print("mission %s is running" % open_mission)
        check = driver.run("check/" + uuid.uuid4().hex, "check", CHECK_CODE, CHECK_TIMEOUT)
        if not (check.status == "done" and check.result is True):
            print(STALE)
            return 2

        verdicts = []
        for s in chosen:
            verdicts.append(suite.run_scenario(driver, judge, s, open_mission, console))
        return _finish(verdicts, folder, repo)
    except (suite.SuiteError, verify.VerifyError, mission.MissionError) as e:
        print(e)
        return 2


if __name__ == "__main__":
    sys.exit(main())
