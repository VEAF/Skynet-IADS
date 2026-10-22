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


def _finish(verdicts, folder):
    print(suite.summary(verdicts))
    suite.write_report(verdicts, folder / "report.md")
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
            return _finish(suite.rejudge(folder / "journal.jsonl", chosen, judge), folder)

        skynet_script.prepare(repo, Path(args.skynet) if args.skynet else None)
        mailbox = Mailbox(insim / "dcs-hotload")
        mailbox.ensure()
        names = []
        for template in sorted((insim / "miz").glob("*.template.miz")):
            name = template.name[: -len(".template.miz")]
            mission.prepare(template, template.with_name(name + ".miz"), insim / "dcs-hotload")
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
        if not args.resume:
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "run.json").write_text(json.dumps(run), encoding="utf-8")

        driver = Driver(mailbox, folder / "journal.jsonl")
        hint = "open %s in DCS (missions: %s)" % (" or ".join("test/insim/miz/%s.miz" % n for n in names), ", ".join(names))
        open_mission = driver.wait_for_mission(hint)["mission"]
        check = driver.run("check/" + uuid.uuid4().hex, "check", CHECK_CODE, CHECK_TIMEOUT)
        if not (check.status == "done" and check.result is True):
            print(STALE)
            return 2

        verdicts = []
        for s in chosen:
            v = suite.run_scenario(driver, judge, s, open_mission)
            print("%s: %s%s" % (v.name, v.verdict, " - " + v.message if v.message else ""))
            verdicts.append(v)
        return _finish(verdicts, folder)
    except (suite.SuiteError, verify.VerifyError, mission.MissionError) as e:
        print(e)
        return 2


if __name__ == "__main__":
    sys.exit(main())
