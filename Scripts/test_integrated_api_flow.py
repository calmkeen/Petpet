#!/usr/bin/env python3
"""Continue a completed fresh-pair Debug journey through community API screens.

All mutations use XCTest UI. The script only reads simulator stores to compare
phone/watch state and verifies that the watch stays in companion mode. Run after
test_full_debug_flow.py; resume a failed stage without repeating feeding.
"""
import argparse
import base64
import datetime as dt
import hashlib
import json
from pathlib import Path
import time

import test_debug_flow as flow
import test_games_flow as games

PHASES = [
    ("watch", "WatchFinalAuditUITests", "test20WatchNicknameChangeSurvivesRelaunch"),
    ("watch", "WatchCommunityUITests", "test10CumulativeStepsPageForwardBackAndRefresh"),
    ("watch", "WatchCommunityUITests", "test20ShootingRangePages"),
    ("watch", "WatchCommunityUITests", "test21StarStairRangePages"),
    ("watch", "WatchCommunityUITests", "test30PictureUploadAndRelaunch"),
    ("phone", "PhoneAPIParityUITests", "test31WatchPictureAndNicknameAreVisibleWithoutPhoneUpload"),
    ("phone", "PhoneAPIParityUITests", "test10StepRankingPagesAndServerOutput"),
    ("phone", "PhoneAPIParityUITests", "test20ShootingRangePages"),
    ("phone", "PhoneAPIParityUITests", "test21StairsRangePagesAndComboOutput"),
    ("phone", "PhoneAPIParityUITests", "test30PictureUpdatePersistsAcrossRelaunch"),
    ("phone", "PhoneAPIParityUITests", "test40LargeDarkStepRankingAndPictureControls"),
    ("watch", "WatchCommunityUITests", "test40LargeTextRankingAndPictureControls"),
    ("watch", "WatchSmallScreenUITests", "testDateSelectionReturnsToCalendar"),
    ("watch", "WatchSmallScreenUITests", "testYearAndMonthSelectionReturnAndRespectLeapDay"),
    ("watch", "WatchPetTouchUITests", "test00SingleTouch"),
]


def verify(args, baseline, stage):
    watch = flow.store(args.watch, flow.WATCH_BUNDLE)
    phone = flow.store(args.phone, flow.PHONE_BUNDLE)
    current = games.state(args)
    for key in ("pet", "inventory", "localRecords", "serverRecords"):
        assert current[key] == baseline[key], f"Community screens changed {key}"
    assert current["watchHasAccount"]
    assert not flow.read(watch, "standalone-mode-v1.json", {}).get("selected", False), "Unexpected switch to standalone"
    account = flow.read(watch, "cloud-account-v1.json")
    server = flow.read(phone, "mock-backend-v1.json")
    assert account["displayName"] == server["nickname"] and server["nickname"].startswith("FinalWatch")
    game = flow.read(watch, "game-state-v1.json")
    assert game["game"]["records"] == baseline["steps"]
    assert len(game["appliedBackups"]) == baseline["appliedBackups"]
    assert len(game["appliedRestores"]) == baseline["appliedRestores"]
    cached = flow.read(phone, "watch-snapshot-v1.json", {}).get("cached", {}).get("snapshot", {})
    assert cached.get("pet") == game["game"]["progress"]["pet"]
    assert {r["date"]: r["stepCount"] for r in cached["steps"]} == game["game"]["records"]
    assert not game["pending"]
    image_hash = None
    if stage >= 4:
        image = base64.b64decode(server["image"]["data"], validate=True)
        assert 0 < len(image) <= 32000 and server["pictureUrl"].startswith("https://debug.petpet.invalid/avatars/")
        image_hash = hashlib.sha256(image).hexdigest()
        if 5 <= stage < 9:
            assert image_hash == flow.read(args.artifacts, "state-04.json")["profileImageSHA256"], "Reading rankings/profile replaced the watch-uploaded image"
        elif stage >= 10:
            assert image_hash == flow.read(args.artifacts, "state-09.json")["profileImageSHA256"], "Reading profile replaced the phone-uploaded image"
    return dict(pet=current["pet"], inventory=current["inventory"], nickname=account["displayName"],
                profileImageSHA256=image_hash, phoneSnapshotMatchesWatch=True, stayedInCompanionMode=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--watch", required=True)
    parser.add_argument("--build", type=Path, default=Path("/private/tmp/petpet-watch-ux-272"))
    parser.add_argument("--journey", type=Path, required=True, help="Completed full_debug_flow artifacts")
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--from-stage", type=int, choices=range(len(PHASES)), default=0)
    parser.add_argument("--through-stage", type=int, choices=range(len(PHASES)), default=len(PHASES)-1)
    args = parser.parse_args()
    completed = flow.read(args.journey, "full-flow-result.json")
    assert completed and completed["phoneSimulator"] == args.phone and completed["watchSimulator"] == args.watch
    assert completed["passedUIExecutions"] == 22 and completed["failedUIExecutions"] == 0
    pairs = json.loads(flow.command("xcrun", "simctl", "list", "pairs", "--json"))["pairs"]
    assert any(p["phone"]["udid"] == args.phone and p["watch"]["udid"] == args.watch
               and p["state"].startswith("(active,") for p in pairs.values())
    assert args.from_stage <= args.through_stage
    args.artifacts.mkdir(parents=True, exist_ok=True)
    baseline_file = args.artifacts / "baseline.json"
    if args.from_stage == 0 and not baseline_file.exists():
        baseline = games.state(args)
        game = flow.read(flow.store(args.watch, flow.WATCH_BUNDLE), "game-state-v1.json")
        baseline.update(steps=game["game"]["records"], appliedBackups=len(game["appliedBackups"]), appliedRestores=len(game["appliedRestores"]))
        flow.write(baseline_file, baseline)
    elif args.from_stage == 0:
        assert not (args.artifacts / "state-00.json").exists(), "Stage zero already passed; resume the next stage"
    baseline = json.loads(baseline_file.read_text())
    for index in range(args.from_stage, args.through_stage + 1):
        side, suite, test = PHASES[index]
        other = "watch" if side == "phone" else "phone"
        bundle = flow.WATCH_BUNDLE if other == "watch" else flow.PHONE_BUNDLE
        flow.launch_app(getattr(args, other), bundle)
        target = "PetPetUITests" if side == "phone" else "PetPet Watch AppUITests"
        result = flow.xcode(args, side, "test-without-building", f"stage-{index:02d}-{test}", test,
                   companion=(getattr(args, other), bundle), suite=f"{target}/{suite}")
        summary = json.loads(flow.command("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result), "--compact"))
        assert (summary["passedTests"], summary["failedTests"], summary["skippedTests"]) == (1, 0, 0)
        device = summary["devicesAndConfigurations"][0]["device"]
        assert device["deviceId"] == getattr(args, side) and device["platform"].endswith("Simulator")
        for attempt in range(40):
            try:
                state = verify(args, baseline, index)
                break
            except AssertionError:
                if attempt == 39: raise
                time.sleep(.25)
        state.update(stage=index, suite=suite, test=test, side=side, passed=True, resultBundle=str(result), device=device,
                     verifiedAt=dt.datetime.now(dt.timezone.utc).isoformat())
        flow.write(args.artifacts / f"state-{index:02d}.json", state)
        print(f"API stage {index} passed: UI, unchanged progression, synced profile and companion mode", flush=True)
    if args.through_stage == len(PHASES) - 1:
        states = [flow.read(args.artifacts, f"state-{index:02d}.json") for index in range(len(PHASES))]
        assert all(s and s["passed"] for s in states)
        flow.write(args.artifacts / "result.json", dict(verifiedAt=dt.datetime.now(dt.timezone.utc).isoformat(),
            simulatorOnly=True, mockAccountOnly=True, phoneSimulator=args.phone, watchSimulator=args.watch,
            passedUIExecutions=len(states), failedUIExecutions=0, skippedUIExecutions=0,
            priorFullJourney=str(args.journey / "full-flow-result.json"), results=states))


if __name__ == "__main__":
    main()
