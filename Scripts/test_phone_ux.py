#!/usr/bin/env python3
"""Run small-iPhone layout and interaction checks on a paired Debug simulator.

Use an existing mock login and backup; restore previews are cancelled. No
physical devices or artificial health/step fixtures are used.
"""
import argparse
from contextlib import contextmanager
import subprocess
import datetime as dt
import json
from pathlib import Path

import test_debug_flow as flow

PHASES = [
    ("PhoneUXUITests", "test00HomeLight"),
    ("PhoneUXUITests", "test01HomeLargeLight"),
    ("PhoneUXUITests", "test02HomeDark"),
    ("PhoneUXUITests", "test03HomeLargeDark"),
    ("PhoneUXUITests", "test10DetailsLight"),
    ("PhoneUXUITests", "test11DetailsLargeLight"),
    ("PhoneUXUITests", "test12DetailsDark"),
    ("PhoneUXUITests", "test20RankingsLight"),
    ("PhoneUXUITests", "test21RankingsLargeDark"),
    ("PhoneUXUITests", "test30QuestionDraftLimitAndCancel"),
    ("PhoneGameFlowUITests", "test40PhoneChatRepeatsAndCancels"),
    ("PhoneGameFlowUITests", "test41LargeDarkPhoneChatRepeatsAndCancels"),
    ("PhoneUXUITests", "test50LargeLoginAndReconnect"),
    ("PhoneUXUITests", "test60UnpairedLargeDark"),
    ("PhoneUXUITests", "test70LargeSoftwareKeyboardLayout"),
]


@contextmanager
def phone_ui_settings(args, index):
    previous_size = flow.command("xcrun", "simctl", "ui", args.phone, "content_size")
    previous_keyboard = subprocess.run(["defaults", "read", "com.apple.iphonesimulator", "ConnectHardwareKeyboard"], text=True, capture_output=True)
    keyboard_value = previous_keyboard.stdout.strip() if previous_keyboard.returncode == 0 else None
    size = "accessibility-extra-large" if index in {1, 3, 5, 8, 9, 11, 12, 13, 14} else "large"
    settings = {"originalContentSize": previous_size, "testContentSize": size, "restored": False}
    try:
        flow.command("xcrun", "simctl", "ui", args.phone, "content_size", size)
        assert flow.command("xcrun", "simctl", "ui", args.phone, "content_size") == size
        flow.command("defaults", "write", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", "-bool", "false")
        yield settings
    finally:
        flow.command("xcrun", "simctl", "ui", args.phone, "content_size", previous_size)
        if keyboard_value is None:
            flow.command("defaults", "delete", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", check=False)
        else:
            flow.command("defaults", "write", "com.apple.iphonesimulator", "ConnectHardwareKeyboard", "-bool", "true" if keyboard_value == "1" else "false")
        current_keyboard = subprocess.run(["defaults", "read", "com.apple.iphonesimulator", "ConnectHardwareKeyboard"], text=True, capture_output=True)
        current_value = current_keyboard.stdout.strip() if current_keyboard.returncode == 0 else None
        settings["restored"] = flow.command("xcrun", "simctl", "ui", args.phone, "content_size") == previous_size and current_value == keyboard_value
        assert settings["restored"], "Restore simulator text size and keyboard preferences after testing"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--watch", required=True)
    parser.add_argument("--unpaired-phone", help="Optional dedicated iOS 27.2+ iPhone simulator for empty-state and visible software-keyboard checks")
    parser.add_argument("--build", type=Path, default=Path("/private/tmp/petpet-watch-ux-272"))
    parser.add_argument("--artifacts", type=Path, default=Path("/private/tmp/petpet-phone-ux"))
    parser.add_argument("--from-stage", type=int, choices=range(len(PHASES)), default=0)
    parser.add_argument("--through-stage", type=int, choices=range(len(PHASES)), default=None)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    devices = json.loads(flow.command("xcrun", "simctl", "list", "devices", "--json"))
    known = {d["udid"]: d for runtime in devices["devices"].values() for d in runtime}
    assert args.phone != args.watch and args.phone in known and args.watch in known, "Both targets must be simulators"
    assert "iPhone" in known[args.phone]["deviceTypeIdentifier"] and "Apple-Watch" in known[args.watch]["deviceTypeIdentifier"]
    if args.through_stage is None:
        args.through_stage = len(PHASES) - 1
    if args.unpaired_phone:
        assert args.unpaired_phone in known and args.unpaired_phone != args.phone
        assert "iPhone" in known[args.unpaired_phone]["deviceTypeIdentifier"]
    assert args.from_stage <= args.through_stage
    args.artifacts.mkdir(parents=True, exist_ok=True)
    baseline = args.artifacts / "initial-watch.json"
    if not baseline.exists():
        root = flow.store(args.watch, flow.WATCH_BUNDLE)
        flow.write(baseline, {"game": flow.read(root, "game-state-v1.json"), "account": flow.read(root, "cloud-account-v1.json")})
    if not args.skip_build:
        flow.xcode(args, "phone", "build-for-testing", "build-phone")
    for index in range(args.from_stage, args.through_stage + 1):
        if index in {13, 14} and not args.unpaired_phone:
            continue
        suite, test = PHASES[index]
        path = args.artifacts / f"stage-{index:02d}.json"
        path.unlink(missing_ok=True)
        target = argparse.Namespace(**vars(args))
        companion = None if index in {13, 14} else (args.watch, flow.WATCH_BUNDLE)
        if index in {13, 14}:
            target.phone = args.unpaired_phone
        if companion:
            flow.launch_app(*companion)
        with phone_ui_settings(target, index) as settings:
            flow.xcode(target, "phone", "test-without-building", f"phone-ux-{index:02d}", test=test,
                       suite=f"PetPetUITests/{suite}", companion=companion)
        flow.write(path, {"stage": index, "suite": suite, "test": test, "passed": True,
                         "phoneSimulator": target.phone, "watchSimulator": args.watch if companion else None,
                         "verifiedAt": dt.datetime.now(dt.timezone.utc).isoformat(), "uiSettings": settings})
        print(f"Phone UX stage {index} passed: {test}", flush=True)


if __name__ == "__main__":
    main()
