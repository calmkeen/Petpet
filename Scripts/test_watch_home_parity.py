#!/usr/bin/env python3
"""Check the pet-focused home and five-page navigation on a dedicated simulator pair.

Read-only UI checks: no feeding, stat allocation, login, backup or restore.
Day/night launch arguments alter Debug presentation only, never device time.
"""
import argparse
import datetime as dt
import json
from pathlib import Path

import test_debug_flow as flow

PHASES = [
    ("WatchHomeParityUITests", "test00DayHome"),
    ("WatchHomeParityUITests", "test01NightHome"),
    ("WatchHomeParityUITests", "test02LargeDayHome"),
    ("WatchHomeParityUITests", "test03LargeNightHome"),
    ("WatchHomeParityUITests", "test10FivePagesAndCareDestinations"),
    ("WatchUXUITests", "test00OverviewPages"),
    ("WatchUXUITests", "test01LargeTextOverviewPages"),
    ("WatchUXUITests", "test10DetailControls"),
    ("WatchUXUITests", "test11LargeTextDetailControls"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--watch", required=True)
    parser.add_argument("--build", type=Path, default=Path("/private/tmp/petpet-watch-ux-272"))
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--from-stage", type=int, choices=range(len(PHASES)), default=0)
    parser.add_argument("--through-stage", type=int, choices=range(len(PHASES)), default=len(PHASES)-1)
    args = parser.parse_args()
    devices = json.loads(flow.command("xcrun", "simctl", "list", "devices", "--json"))
    known = {d["udid"]: d for ds in devices["devices"].values() for d in ds}
    assert args.phone in known and "iPhone" in known[args.phone]["deviceTypeIdentifier"]
    assert args.watch in known and "Apple-Watch" in known[args.watch]["deviceTypeIdentifier"]
    assert args.from_stage <= args.through_stage
    args.artifacts.mkdir(parents=True, exist_ok=True)
    for index in range(args.from_stage, args.through_stage+1):
        suite, test = PHASES[index]
        target = args.artifacts / f"stage-{index:02d}.json"
        target.unlink(missing_ok=True)
        companion = (args.phone, flow.PHONE_BUNDLE)
        flow.launch_app(*companion)
        flow.xcode(args, "watch", "test-without-building", f"parity-{index:02d}", test=test,
                   suite=f"PetPet Watch AppUITests/{suite}", companion=companion)
        flow.write(target, dict(stage=index, suite=suite, test=test, passed=True,
                                verifiedAt=dt.datetime.now(dt.timezone.utc).isoformat(),
                                watchSimulator=args.watch, phoneSimulator=args.phone))
        print(f"Home parity stage {index} passed: {test}", flush=True)


if __name__ == "__main__":
    main()
