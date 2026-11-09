#!/usr/bin/env python3
"""Check watch layouts and navigation on a paired simulator, with reversible simulator-only shooting setup.

Uses the same companion restart handling as the Debug journey. The xxxLarge
launch argument changes presentation only and is compiled out of Release.
"""
import argparse
from contextlib import contextmanager
import datetime as dt
import json
from pathlib import Path

import test_debug_flow as flow

PHASES = [
    ("WatchUXUITests", "test00OverviewPages"),
    ("WatchUXUITests", "test01LargeTextOverviewPages"),
    ("WatchUXUITests", "test10DetailControls"),
    ("WatchUXUITests", "test11LargeTextDetailControls"),
    ("WatchSmallScreenUITests", "testDateSelectionReturnsToCalendar"),
    ("WatchSmallScreenUITests", "testYearAndMonthSelectionReturnAndRespectLeapDay"),
    ("WatchSmallScreenUITests", "testShootingStartPauseFinishReplayAndSavedBest"),
    ("WatchSmallScreenUITests", "testStairsControlsTimeoutResultAndReplay"),
    ("WatchGameFlowUITests", "test12StandaloneRankingRefresh"),
    ("WatchGameFlowUITests", "test20ChatThroughSystemInput"),
    ("WatchGameFlowUITests", "test22ChatCancellationAndReturn"),
    ("WatchFinalAuditUITests", "test20WatchNicknameChangeSurvivesRelaunch"),
    ("WatchSmallScreenUITests", "testLargeTextShootingStartPauseFinishReplayAndSavedBest"),
    ("WatchSmallScreenUITests", "testLargeTextStairsControlsTimeoutResultAndReplay"),
]


@contextmanager
def shooting_health(args, enabled):
    if not enabled:
        yield None
        return
    # Crown injection waits for settling for about five seconds in Xcode 27.
    # Use a supported pet health value so random damage cannot end the control
    # check first. The production game clock, damage, and random spawns stay real.
    flow.command("xcrun", "simctl", "terminate", args.watch, flow.WATCH_BUNDLE, check=False)
    root = flow.store(args.watch, flow.WATCH_BUNDLE)
    path = root / "game-state-v1.json"
    game = flow.read(root, path.name)
    assert game and not game["pending"], "Finish pending backups before the shooting UI check"
    original = game["game"]["progress"]["pet"]["health"]
    fixture = {"originalHealth": original, "testHealth": max(99, original), "restored": False}
    game["game"]["progress"]["pet"]["health"] = fixture["testHealth"]
    flow.write(path, game)
    print(f"Shooting UI setup: health {original} -> {fixture['testHealth']}", flush=True)
    try:
        yield fixture
    finally:
        flow.command("xcrun", "simctl", "terminate", args.watch, flow.WATCH_BUNDLE, check=False)
        # Xcode may reinstall the target and move its data container.
        root = flow.store(args.watch, flow.WATCH_BUNDLE)
        path = root / "game-state-v1.json"
        latest = flow.read(root, path.name)
        latest["game"]["progress"]["pet"]["health"] = original
        flow.write(path, latest)
        fixture["restored"] = flow.read(root, path.name)["game"]["progress"]["pet"]["health"] == original
        assert fixture["restored"], "Failed to restore shooting UI setup"
        print(f"Shooting UI setup restored: health {original}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--watch", required=True)
    parser.add_argument("--build", type=Path, default=Path("/private/tmp/petpet-watch-ux-272"))
    parser.add_argument("--artifacts", type=Path, default=Path("/private/tmp/petpet-watch-ux"))
    parser.add_argument("--from-stage", type=int, choices=range(len(PHASES)), default=0)
    parser.add_argument("--through-stage", type=int, choices=range(len(PHASES)), default=len(PHASES) - 1)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    devices = json.loads(flow.command("xcrun", "simctl", "list", "devices", "--json"))
    known = {d["udid"]: d for runtime in devices["devices"].values() for d in runtime}
    assert args.phone != args.watch and args.phone in known and args.watch in known, "Both targets must be simulators"
    assert "Apple-Watch" in known[args.watch]["deviceTypeIdentifier"]
    assert "iPhone" in known[args.phone]["deviceTypeIdentifier"]
    assert args.from_stage <= args.through_stage
    args.artifacts.mkdir(parents=True, exist_ok=True)
    if not args.skip_build:
        flow.xcode(args, "watch", "build-for-testing", "build-watch")
    for index in range(args.from_stage, args.through_stage + 1):
        suite, test = PHASES[index]
        record_path = args.artifacts / f"stage-{index:02d}.json"
        record_path.unlink(missing_ok=True)
        companion = (args.phone, flow.PHONE_BUNDLE)
        flow.launch_app(*companion)
        with shooting_health(args, enabled="ShootingStartPause" in test) as fixture:
            flow.xcode(args, "watch", "test-without-building", f"ux-{index:02d}", test=test,
                       suite=f"PetPet Watch AppUITests/{suite}", companion=companion)
        record = {"stage": index, "suite": suite, "test": test, "passed": True,
                  "watchSimulator": args.watch, "phoneSimulator": args.phone,
                  "verifiedAt": dt.datetime.now(dt.timezone.utc).isoformat(), "shootingHealthSetup": fixture}
        flow.write(record_path, record)
        print(f"UX stage {index} passed: {test}", flush=True)


if __name__ == "__main__":
    main()
