#!/usr/bin/env python3
"""Run the final Android parity audit on a dedicated, already paired simulator.

Requires Debug apps, simulator fitness permission and at least two milk portions.
Uses native UI actions; no pet, score, step or credential fixtures are injected.
After five watch-focused stages, runs the existing 13-stage game/chat journey.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess
import sys
import time

import test_debug_flow as flow

PHASES = [
    ("phone", "PhoneGameFlowUITests", "test00EnsureDevelopmentLogin"),
    ("watch", "WatchFinalAuditUITests", "test10FeedPersistsAndRepeatedWatchBackupCompletes"),
    ("watch", "WatchFinalAuditUITests", "test20WatchNicknameChangeSurvivesRelaunch"),
    ("watch", "WatchSmallScreenUITests", "testDateSelectionReturnsToCalendar"),
    ("watch", "WatchSmallScreenUITests", "testYearAndMonthSelectionReturnAndRespectLeapDay"),
]


def read_state(args):
    watch = flow.store(args.watch, flow.WATCH_BUNDLE)
    phone = flow.store(args.phone, flow.PHONE_BUNDLE)
    return flow.read(watch, "game-state-v1.json"), flow.read(phone, "mock-backend-v1.json"), flow.read(watch, "cloud-account-v1.json")


def verify(args, index, baseline):
    game, server, account = read_state(args)
    progress = game["game"]["progress"]
    old = baseline["progress"]
    pet = progress["pet"]
    foods = {row["foodID"]: row["quantity"] for row in progress["inventory"]}
    if index >= 1:
        exp, level, points = old["pet"]["experience"] + 1, old["pet"]["level"], old["pet"]["statPoints"]
        while exp >= level * 2:
            exp -= level * 2; level += 1; points += 2
        assert (pet["experience"], pet["level"], pet["statPoints"]) == (exp, level, points)
        for key in ("attack", "defense", "health", "affection"):
            assert pet[key] == old["pet"][key]
        previous_foods = {row["foodID"]: row["quantity"] for row in old["inventory"]}
        today = dt.date.today().isoformat()
        before_claim = old["rewardClaims"].get(today, {})
        claim = progress["rewardClaims"][today]
        milk = max(0, claim["milkUnits"] - before_claim.get("milkUnits", 0))
        apple = int(claim["appleClaimed"] and not before_claim.get("appleClaimed", False))
        assert foods.get(1, 0) == previous_foods.get(1, 0) - 1 + milk
        assert foods.get(2, 0) == previous_foods.get(2, 0) + apple
        assert len(game["appliedBackups"]) == baseline["backups"] + 2 and not game["pending"]
        for key in ("experience", "level", "attack", "defense", "health"):
            assert server["pet"][key] == pet[key]
        cached = {}
        phone = flow.store(args.phone, flow.PHONE_BUNDLE)
        for _ in range(40):
            cached = flow.read(phone, "watch-snapshot-v1.json", {}).get("cached", {}).get("snapshot", {})
            if cached.get("pet") == pet and sorted(cached.get("inventory", []), key=lambda row: row["foodID"]) == sorted(progress["inventory"], key=lambda row: row["foodID"]):
                break
            time.sleep(0.25)
        assert cached.get("pet") == pet
        assert sorted(cached["inventory"], key=lambda row: row["foodID"]) == sorted(progress["inventory"], key=lambda row: row["foodID"])
    assert account and account["id"] == "900000001"
    if index >= 2:
        assert account["displayName"].startswith("FinalWatch") and server["nickname"] == account["displayName"]
    value = {"stage": index, "test": PHASES[index][2], "passed": True,
             "verifiedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
             "pet": pet, "inventory": progress["inventory"], "steps": game["game"]["records"],
             "appliedBackups": len(game["appliedBackups"]), "nickname": account["displayName"]}
    flow.write(args.artifacts / f"state-{index:02d}.json", value)
    print(f"audit stage {index} verified: watch/server/phone state matches", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--watch", required=True)
    parser.add_argument("--build", type=Path, default=Path("/private/tmp/petpet-flow-build"))
    parser.add_argument("--artifacts", type=Path, default=Path("/private/tmp/petpet-final-audit"))
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--skip-games", action="store_true")
    parser.add_argument("--from-stage", type=int, choices=range(len(PHASES)), default=0)
    args = parser.parse_args()
    devices = json.loads(flow.command("xcrun", "simctl", "list", "devices", "--json"))
    known = {device["udid"] for runtime in devices["devices"].values() for device in runtime}
    assert args.phone in known and args.watch in known and args.phone != args.watch, "Only simulator targets are allowed"
    args.artifacts.mkdir(parents=True, exist_ok=True)
    if not args.skip_build:
        for side in ("phone", "watch"):
            flow.xcode(args, side, "build-for-testing", "build-" + side)
    baseline_file = args.artifacts / "audit-baseline.json"
    if args.from_stage == 0:
        assert not baseline_file.exists(), "Use a new artifact directory for a new run"
        game, _, _ = read_state(args)
        flow.write(baseline_file, {"progress": game["game"]["progress"], "backups": len(game["appliedBackups"])})
    baseline = json.loads(baseline_file.read_text())
    for index in range(args.from_stage, len(PHASES)):
        side, suite, test = PHASES[index]
        other = "watch" if side == "phone" else "phone"
        bundle = flow.WATCH_BUNDLE if other == "watch" else flow.PHONE_BUNDLE
        flow.launch_app(getattr(args, other), bundle)
        target = "PetPetUITests" if side == "phone" else "PetPet Watch AppUITests"
        flow.xcode(args, side, "test-without-building", f"audit-{index:02d}-{test}", test,
                   companion=(getattr(args, other), bundle), suite=f"{target}/{suite}")
        verify(args, index, baseline)
    if not args.skip_games:
        subprocess.run([sys.executable, "-B", str(flow.ROOT / "Scripts/test_games_flow.py"),
                        "--phone", args.phone, "--watch", args.watch, "--build", str(args.build),
                        "--artifacts", str(args.artifacts / "games"), "--skip-build"], check=True, cwd=flow.ROOT)


if __name__ == "__main__":
    main()
