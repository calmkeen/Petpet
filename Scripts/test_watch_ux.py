#!/usr/bin/env python3
"""Check watch layouts and navigation on a paired simulator, without seeding data.

Uses the same companion restart handling as the Debug journey. The xxxLarge
launch argument changes presentation only and is compiled out of Release.
"""
import argparse
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
]


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
    known = {d["udid"] for runtime in devices["devices"].values() for d in runtime}
    assert args.phone != args.watch and args.phone in known and args.watch in known, "Both targets must be simulators"
    assert args.from_stage <= args.through_stage
    args.artifacts.mkdir(parents=True, exist_ok=True)
    if not args.skip_build:
        flow.xcode(args, "watch", "build-for-testing", "build-watch")
    for index in range(args.from_stage, args.through_stage + 1):
        suite, test = PHASES[index]
        companion = (args.phone, flow.PHONE_BUNDLE)
        flow.launch_app(*companion)
        flow.xcode(args, "watch", "test-without-building", f"ux-{index:02d}", test=test,
                   suite=f"PetPet Watch AppUITests/{suite}", companion=companion)
        record = {"stage": index, "suite": suite, "test": test, "passed": True,
                  "watchSimulator": args.watch, "phoneSimulator": args.phone,
                  "verifiedAt": dt.datetime.now(dt.timezone.utc).isoformat()}
        flow.write(args.artifacts / f"stage-{index:02d}.json", record)
        print(f"UX stage {index} passed: {test}", flush=True)


if __name__ == "__main__":
    main()
