#!/usr/bin/env python3
"""Run the fresh-pair Debug journey, then games/chat, and verify their shared state.

Use a new dedicated simulator pair. Only the journey's two step-history records
are prepared; feeding, growth, rewards, scores and authentication use app UI.
Resume individual failed stages with the underlying drivers, then use
--from-part games or verify. Do not repeat successful feeding/restore stages.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess
import sys
import time

import test_debug_flow as flow
import test_games_flow as games


def native_results(args):
    results = []
    for part, phases in (("journey", flow.PHASES), ("games", games.PHASES)):
        for index, (side, test) in enumerate(phases):
            directory = args.artifacts / part
            state = flow.read(directory, f"state-{index:02d}.json")
            assert state and state["passed"] and state["test"] == test, (part, index)
            prefix = f"phase-{index:02d}-" if part == "journey" else f"stage-{index:02d}-{test}-"
            logs = [p for p in directory.glob(prefix + "*.log")
                    if "** TEST EXECUTE SUCCEEDED **" in p.read_text(errors="replace")]
            assert logs, (part, index, "Missing successful native test")
            result = max(logs, key=lambda p: p.stat().st_mtime).with_suffix(".xcresult")
            summary = json.loads(flow.command("xcrun", "xcresulttool", "get", "test-results", "summary",
                                              "--path", str(result), "--compact"))
            assert (summary["passedTests"], summary["failedTests"], summary["skippedTests"]) == (1, 0, 0)
            device = summary["devicesAndConfigurations"][0]["device"]
            assert device["deviceId"] == getattr(args, side) and device["platform"].endswith("Simulator")
            results.append(dict(part=part, stage=index, side=side, test=test, passedTests=1,
                                failedTests=0, skippedTests=0, resultBundle=str(result), device=device))
    return results


def verify(args):
    flow.launch_app(args.phone, flow.PHONE_BUNDLE)
    flow.launch_app(args.watch, flow.WATCH_BUNDLE)
    for attempt in range(80):
        watch = flow.store(args.watch, flow.WATCH_BUNDLE)
        phone = flow.store(args.phone, flow.PHONE_BUNDLE)
        game = flow.read(watch, "game-state-v1.json")
        cached = flow.read(phone, "watch-snapshot-v1.json", {}).get("cached", {}).get("snapshot", {})
        progress = game["game"]["progress"]
        if (cached.get("pet") == progress["pet"] and cached.get("inventory") == progress["inventory"]
                and {r["date"]: r["stepCount"] for r in cached.get("steps", [])} == game["game"]["records"]):
            break
        time.sleep(.25)
    else:
        raise AssertionError("Current phone snapshot did not converge with the watch")
    end_of_journey = flow.read(args.artifacts / "journey", "state-08.json")
    assert progress["pet"] == end_of_journey["pet"], "Games/chat changed pet progression"
    assert progress["inventory"] == end_of_journey["inventory"], "Games/chat changed food"
    assert game["game"]["records"] == end_of_journey["steps"]
    assert len(game["appliedBackups"]) == 3 and len(game["appliedRestores"]) == 1 and not game["pending"]
    account = flow.read(watch, "cloud-account-v1.json")
    assert account["id"] == game["ownerID"] == "900000001"
    server = flow.read(phone, "mock-backend-v1.json")
    assert account["displayName"] == (server.get("nickname") or "개발 테스트 계정")
    assert cached["environment"] == "development" and cached["version"] == 2
    for key in ("level", "experience", "affection", "attack", "defense", "health"):
        assert server["pet"][key] == progress["pet"][key], key
    assert server["records"] == game["game"]["records"]
    local = flow.read(watch, "minigame-records-v1.json")
    remote = server["gameScores"]
    for name in ("shooting", "starStair"):
        assert local[name]["score"] == remote[name]["score"], name
    assert local["starStair"]["score"] >= 1
    assert local["starStair"]["maxCombo"] == remote["starStair"]["maxCombo"]
    receipts = flow.read(phone, "cloud-receipts-v1.json")
    assert set(receipts["receipts"]) <= set(receipts["acknowledged"])
    assert not receipts["restores"]
    results = native_results(args)
    record = dict(verifiedAt=dt.datetime.now(dt.timezone.utc).isoformat(), simulatorOnly=True,
                  phoneSimulator=args.phone, watchSimulator=args.watch,
                  passedUIExecutions=len(results), failedUIExecutions=0, skippedUIExecutions=0,
                  uniqueUITestMethods=len({r["test"] for r in results}), results=results,
                  phoneSnapshotMatchesWatch=True, serverPetStatsStepsAndGameScoresMatchWatch=True,
                  pet=progress["pet"], inventory=progress["inventory"], steps=game["game"]["records"],
                  nickname=account["displayName"], localGameRecords=local, serverGameRecords=remote,
                  appliedBackups=3, appliedRestores=1, pendingBackups=0, pendingRestores=0)
    flow.write(args.artifacts / "full-flow-result.json", record)
    print(f"Verified {len(results)} native stages and phone/watch/mock-server state. No credentials exported.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--watch", required=True)
    parser.add_argument("--build", type=Path, default=Path("/private/tmp/petpet-watch-ux-272"))
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--from-part", choices=("journey", "games", "verify"), default="journey")
    args = parser.parse_args()
    devices = json.loads(flow.command("xcrun", "simctl", "list", "devices", "--json"))
    known = {d["udid"]: d for ds in devices["devices"].values() for d in ds}
    assert args.phone in known and "iPhone" in known[args.phone]["deviceTypeIdentifier"]
    assert args.watch in known and "Apple-Watch" in known[args.watch]["deviceTypeIdentifier"]
    pairs = json.loads(flow.command("xcrun", "simctl", "list", "pairs", "--json"))["pairs"]
    assert any(p["phone"]["udid"] == args.phone and p["watch"]["udid"] == args.watch
               and p["state"].startswith("(active,") for p in pairs.values()), "Use an active simulator pair"
    args.artifacts.mkdir(parents=True, exist_ok=True)
    common = ["--phone", args.phone, "--watch", args.watch, "--build", str(args.build)]
    if args.from_part == "journey":
        assert not (args.artifacts / "journey").exists(), "Use a new artifacts directory for a fresh journey"
        command = [sys.executable, "-B", str(flow.ROOT / "Scripts/test_debug_flow.py"), *common,
                   "--artifacts", str(args.artifacts / "journey")]
        if args.skip_build: command.append("--skip-build")
        subprocess.run(command, check=True, cwd=flow.ROOT)
    if args.from_part != "verify":
        assert all((args.artifacts / "journey" / f"state-{i:02d}.json").exists() for i in range(9))
        command = [sys.executable, "-B", str(flow.ROOT / "Scripts/test_games_flow.py"), *common,
                   "--artifacts", str(args.artifacts / "games")]
        if args.skip_build or args.from_part == "journey": command.append("--skip-build")
        subprocess.run(command, check=True, cwd=flow.ROOT)
    verify(args)


if __name__ == "__main__":
    main()
