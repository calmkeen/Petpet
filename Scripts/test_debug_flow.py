#!/usr/bin/env python3
"""Run the ordered Debug journey on a dedicated, fresh simulator pair.

No physical-device commands or network clients are used. The only fixture is
step history in the new watch's Development store, after verifying it is fresh.
See Docs/DebugFlow-2026-11-08.md for preparation and prerequisites.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
PHONE_BUNDLE = "com.calmkeen.PetPet"
WATCH_BUNDLE = PHONE_BUNDLE + ".watchkitapp"
PHASES = [
    ("watch", "test00NewWatchCanPlayWithoutLogin"),
    ("phone", "test01LoginAndEmptyRestore"),
    ("watch", "test02FeedGrowAndAllocate"),
    ("phone", "test03SyncedGrowthBackupTwiceAndCancelRestore"),
    ("watch", "test04SpendAfterBackup"),
    ("phone", "test05ReconnectRestoreOlderPetAndLogout"),
    ("watch", "test06LoggedOutWatchKeepsLocalPlay"),
    ("phone", "test07ReloginKeepsBackupAndLocalProgress"),
    ("watch", "test08WatchRequestsBackupAfterRelogin"),
]


def command(*args, check=True):
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=True, check=check).stdout.strip()


def launch_app(device, bundle):
    # LaunchServices may briefly reject a just-installed paired application.
    for _ in range(6):
        result = subprocess.run(["xcrun", "simctl", "launch", device, bundle], text=True, capture_output=True)
        if result.returncode == 0:
            return
        time.sleep(0.5)
    raise RuntimeError(result.stderr.strip())


def store(device, bundle):
    return Path(command("xcrun", "simctl", "get_app_container", device, bundle, "data")) / "Library/Application Support/PetPet/Development"


def read(root, name, fallback=None):
    path = root / name
    return json.loads(path.read_text()) if path.exists() else fallback


def write(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def xcode(args, side, action, label, test=None, companion=None, suite=None):
    scheme = "PetPet" if side == "phone" else "PetPet Watch App"
    platform = "iOS Simulator" if side == "phone" else "watchOS Simulator"
    cmd = ["xcodebuild", "-project", "PetPet.xcodeproj", "-scheme", scheme,
           "-configuration", "Debug", "-destination", f"platform={platform},id={getattr(args, side)},arch=arm64",
           "-derivedDataPath", str(args.build), "-jobs", "2", "-parallel-testing-enabled", "NO",
           "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-"]
    stamp = dt.datetime.now().strftime("%H%M%S")
    log = args.artifacts / f"{label}-{stamp}.log"
    result_bundle = args.artifacts / f"{label}-{stamp}.xcresult"
    if test:
        target = suite or ("PetPetUITests/PhoneDebugFlowUITests" if side == "phone" else "PetPet Watch AppUITests/WatchDebugFlowUITests")
        cmd += [f"-only-testing:{target}/{test}", "-resultBundlePath", str(result_bundle)]
    cmd.append(action)
    print(f"{label}: {action} ({side}); log={log}", flush=True)
    with log.open("w") as output:
        process = subprocess.Popen(cmd, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
        restarted = companion is None
        started_at = time.monotonic()
        while process.poll() is None:
            # Xcode can reinstall the paired app, moving its data container.
            # Launch it after installation; an already-running process would
            # continue writing its cached URL in the retired container.
            target = PHONE_BUNDLE if side == "phone" else WATCH_BUNDLE
            app_started = f"Wait for {target} to idle" in log.read_text(errors="replace")
            if test and not app_started and time.monotonic() - started_at > 120:
                process.terminate(); process.wait(timeout=30)
                raise RuntimeError(f"Simulator test app did not start within 120 seconds; see {log}")
            if not restarted and app_started:
                device, bundle = companion
                command("xcrun", "simctl", "terminate", device, bundle, check=False)
                try:
                    launch_app(device, bundle)
                except Exception:
                    process.terminate(); process.wait(timeout=30)
                    raise
                restarted = True
                print(f"{label}: companion restarted after Xcode installation", flush=True)
            time.sleep(0.25)
    if process.returncode:
        print("\n".join(log.read_text().splitlines()[-18:]), flush=True)
        raise SystemExit(f"{label} failed; see {log}")
    if test:
        summary = json.loads(command("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_bundle), "--compact"))
        assert summary["passedTests"] == 1 and summary["failedTests"] == 0, f"Expected one passing test: {result_bundle}"
    return result_bundle if test else None


def seed_steps(args):
    for side, bundle in (("phone", PHONE_BUNDLE), ("watch", WATCH_BUNDLE)):
        command("xcrun", "simctl", "terminate", getattr(args, side), bundle, check=False)
    watch = store(args.watch, WATCH_BUNDLE)
    game = read(watch, "game-state-v1.json")
    assert game and game.get("ownerID") is None and not game["appliedBackups"] and not game["appliedRestores"], "Use a fresh dedicated simulator pair"
    assert game["game"]["progress"]["pet"]["level"] == 1
    assert game["game"]["progress"]["inventory"] == [{"id": 1, "foodID": 1, "quantity": 3}]
    write(args.artifacts / "initial-watch-game.json", game)
    today = dt.date.today()
    game["game"]["records"] = {today.isoformat(): 4321, (today - dt.timedelta(days=1)).isoformat(): 2000}
    write(watch / "game-state-v1.json", game)
    print("Seeded only the fresh simulator's two step records (today 4,321; yesterday 2,000).", flush=True)


def verify(args, phase):
    watch, phone = store(args.watch, WATCH_BUNDLE), store(args.phone, PHONE_BUNDLE)
    game = read(watch, "game-state-v1.json")
    progress = game["game"]["progress"]
    pet = progress["pet"]
    foods = {row["foodID"]: row["quantity"] for row in progress["inventory"]}
    expected_milk = {0: 3, 1: 3, 2: 1, 3: 5, 4: 4, 5: 4, 6: 3, 7: 3, 8: 3}[phase]
    assert foods.get(1, 0) == expected_milk, (phase, foods)
    if phase >= 2:
        assert pet["level"] == 2 and pet["health"] == 9, (phase, pet)
        assert pet["experience"] == (1 if phase in (4, 6, 7, 8) else 0), (phase, pet)
        assert pet["statPoints"] == (1 if phase in (2, 3) else 0), (phase, pet)
        assert pet["attack"] == (51 if phase == 4 else 50), (phase, pet)
    if phase >= 3:
        assert foods.get(2) == 1 and len(game["appliedBackups"]) == (3 if phase == 8 else 2) and not game["pending"]
        server = read(phone, "mock-backend-v1.json")
        assert server["pet"]["level"] == 2 and server["pet"]["experience"] == (1 if phase == 8 else 0) and server["pet"]["attack"] == 50
        assert len(server["records"]) == 2
        assert server["records"] == game["game"]["records"], "Server step history differs from watch"
        journal = read(phone, "cloud-receipts-v1.json")
        assert set(journal["receipts"]) <= set(journal["acknowledged"]), "Backup receipt is still pending"
    if phase >= 5:
        assert len(game["appliedRestores"]) == 1
        assert not read(phone, "cloud-receipts-v1.json")["restores"]
    account = read(watch, "cloud-account-v1.json")
    if phase in (0, 5, 6):
        assert account is None, (phase, "Watch account was not cleared")
    else:
        assert account and account["id"] == "900000001", (phase, "Watch account missing")
    if phase in (7, 8):
        for _ in range(60):
            cached = read(phone, "watch-snapshot-v1.json", {}).get("cached", {}).get("snapshot", {})
            if cached.get("pet") == pet and sorted(cached.get("inventory", []), key=lambda x: x["foodID"]) == sorted(progress["inventory"], key=lambda x: x["foodID"]):
                break
            time.sleep(0.25)
        assert cached.get("pet") == pet and cached["version"] == 2 and cached["environment"] == "development"
        assert sorted(cached["inventory"], key=lambda x: x["foodID"]) == sorted(progress["inventory"], key=lambda x: x["foodID"])
        assert {row["date"]: row["stepCount"] for row in cached["steps"]} == game["game"]["records"]
    result = {"phase": phase, "test": PHASES[phase][1], "verifiedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
              "pet": pet, "inventory": progress["inventory"], "steps": game["game"]["records"],
              "appliedBackups": len(game["appliedBackups"]), "appliedRestores": len(game["appliedRestores"]),
              "watchHasAccount": account is not None, "passed": True}
    write(args.artifacts / f"state-{phase:02d}.json", result)
    print(f"phase {phase} verified: level={pet['level']}, xp={pet['experience']}, milk={expected_milk}, account={account is not None}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phone", required=True, help="Dedicated iPhone simulator UDID")
    parser.add_argument("--watch", required=True, help="Its paired watch simulator UDID")
    parser.add_argument("--build", type=Path, default=Path("/private/tmp/petpet-flow-build"))
    parser.add_argument("--artifacts", type=Path, default=Path("/private/tmp/petpet-debug-flow"))
    parser.add_argument("--from-stage", type=int, choices=range(len(PHASES)), default=0)
    parser.add_argument("--through-stage", type=int, choices=range(len(PHASES)), default=len(PHASES) - 1)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    devices = json.loads(command("xcrun", "simctl", "list", "devices", "--json"))
    known = {device["udid"] for runtime in devices["devices"].values() for device in runtime}
    assert args.phone in known and args.watch in known and args.phone != args.watch, "Both targets must be simulators"
    assert args.from_stage <= args.through_stage
    args.artifacts.mkdir(parents=True, exist_ok=True)
    if not args.skip_build:
        for side in ("phone", "watch"):
            xcode(args, side, "build-for-testing", "build-" + side)
    if not args.skip_build or args.from_stage == 0:
        for side, product in (("phone", "Debug-iphonesimulator/PetPet.app"), ("watch", "Debug-watchsimulator/PetPet Watch App.app")):
            command("xcrun", "simctl", "install", getattr(args, side), str(args.build / "Build/Products" / product))
    for index in range(args.from_stage, args.through_stage + 1):
        side, test = PHASES[index]
        other = "watch" if side == "phone" else "phone"
        bundle = WATCH_BUNDLE if other == "watch" else PHONE_BUNDLE
        if index == 4:
            command("xcrun", "simctl", "terminate", args.phone, PHONE_BUNDLE, check=False)
            companion = None
        else:
            launch_app(getattr(args, other), bundle)
            # Prelaunch establishes the pair before target activation; restart
            # after installation handles data-container moves on either side.
            companion = (getattr(args, other), bundle)
        write(args.artifacts / f"watch-before-{index:02d}.json", read(store(args.watch, WATCH_BUNDLE), "game-state-v1.json"))
        xcode(args, side, "test-without-building", f"phase-{index:02d}", test, companion=companion)
        # Let queued account controls finish before checking their persisted state.
        for _ in range(30):
            try:
                verify(args, index)
                break
            except AssertionError:
                if _ == 29:
                    raise
                time.sleep(0.25)
        if index == 0:
            seed_steps(args)
    print("Requested Debug flow stages passed. No physical device was used.", flush=True)


if __name__ == "__main__":
    main()
