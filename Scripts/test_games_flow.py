#!/usr/bin/env python3
"""Exercise Debug games, rankings and chat on an existing dedicated simulator pair.

Uses real XCTest gameplay and system text input. No scores, pet data or account
credentials are injected. Both apps must already have been launched and the
watch's simulator fitness permission granted. See Docs/GamesAudit-2026-11-09.md.
"""
import argparse
import datetime as dt
import json
from pathlib import Path

import test_debug_flow as flow

PHASES = [
    ("phone", "test00EnsureDevelopmentLogin"),
    ("watch", "test10ShootingResultSubmitsAndReplayKeepsBest"),
    ("watch", "test11StairsResultSubmitsAndLeaderboardReloads"),
    ("watch", "test12StandaloneRankingRefresh"),
    ("phone", "test21BothRankingsShowWatchRecords"),
    ("watch", "test20ChatThroughSystemInput"),
    ("watch", "test22ChatCancellationAndReturn"),
    ("phone", "test30Logout"),
    ("watch", "test31LoggedOutGameKeepsLocalRecordAndChatRequiresLogin"),
    ("phone", "test00EnsureDevelopmentLogin"),
    ("watch", "test12StandaloneRankingRefresh"),
    ("watch", "test20ChatThroughSystemInput"),
    ("phone", "test40PhoneChatRepeatsAndCancels"),
]


def state(args):
    watch = flow.store(args.watch, flow.WATCH_BUNDLE)
    phone = flow.store(args.phone, flow.PHONE_BUNDLE)
    progress = flow.read(watch, "game-state-v1.json")["game"]["progress"]
    return {
        "pet": {key: value for key, value in progress["pet"].items() if key not in ("mood", "lastFedAt")},
        "inventory": sorted(progress["inventory"], key=lambda row: row["foodID"]),
        "localRecords": flow.read(watch, "minigame-records-v1.json", {}),
        "serverRecords": flow.read(phone, "mock-backend-v1.json", {}).get("gameScores", {}),
        "watchHasAccount": flow.read(watch, "cloud-account-v1.json") is not None,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--watch", required=True)
    parser.add_argument("--build", type=Path, default=Path("/private/tmp/petpet-flow-build"))
    parser.add_argument("--artifacts", type=Path, default=Path("/private/tmp/petpet-games-flow"))
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--from-stage", type=int, choices=range(len(PHASES)), default=0)
    parser.add_argument("--through-stage", type=int, choices=range(len(PHASES)), default=len(PHASES) - 1)
    args = parser.parse_args()
    devices = json.loads(flow.command("xcrun", "simctl", "list", "devices", "--json"))
    known = {device["udid"] for runtime in devices["devices"].values() for device in runtime}
    assert args.phone in known and args.watch in known and args.phone != args.watch, "Only simulator targets are allowed"
    assert args.from_stage <= args.through_stage
    args.artifacts.mkdir(parents=True, exist_ok=True)
    if not args.skip_build:
        for side in ("phone", "watch"):
            flow.xcode(args, side, "build-for-testing", "build-" + side)
    baseline_file = args.artifacts / "baseline.json"
    if args.from_stage == 0:
        assert not baseline_file.exists(), "Choose a new artifacts directory for a new run"
        flow.write(baseline_file, state(args))
    baseline = json.loads(baseline_file.read_text())
    for index in range(args.from_stage, args.through_stage + 1):
        side, test = PHASES[index]
        other = "watch" if side == "phone" else "phone"
        bundle = flow.WATCH_BUNDLE if other == "watch" else flow.PHONE_BUNDLE
        flow.launch_app(getattr(args, other), bundle)
        suite = "PetPetUITests/PhoneGameFlowUITests" if side == "phone" else "PetPet Watch AppUITests/WatchGameFlowUITests"
        flow.xcode(args, side, "test-without-building", f"stage-{index:02d}-{test}", test,
                   companion=(getattr(args, other), bundle), suite=suite)
        current = state(args)
        assert current["pet"] == baseline["pet"] and current["inventory"] == baseline["inventory"], "Games/chat changed pet stats or food"
        for game, record in baseline["localRecords"].items():
            assert current["localRecords"][game]["score"] >= record["score"], "A saved best score decreased"
        if index >= 1:
            for game in (("shooting",) if index == 1 else ("shooting", "starStair")):
                assert current["localRecords"][game]["score"] == current["serverRecords"][game]["score"], "Local and account best scores differ; use a pair with a single mock account"
        assert current["watchHasAccount"] == (index not in (7, 8)), "Watch account did not follow phone login/logout"
        current.update(stage=index, test=test, passed=True, verifiedAt=dt.datetime.now(dt.timezone.utc).isoformat())
        flow.write(args.artifacts / f"state-{index:02d}.json", current)
        print(f"stage {index} verified: pet/food unchanged, local/server scores consistent", flush=True)


if __name__ == "__main__":
    main()
