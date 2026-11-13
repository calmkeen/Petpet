#!/usr/bin/env python3
"""Verify remaining community screens in platform batches after a full journey.

The watch upload and phone read are separate batches: the phone must display the
watch image before any phone upload. Only XCTest performs mutations.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import time

import test_debug_flow as flow
import test_integrated_api_flow as api

GROUPS = [
    ("watch", ["WatchCommunityUITests/test30PictureUploadAndRelaunch"], 1),
    ("phone", ["PhoneAPIParityUITests/test31WatchPictureAndNicknameAreVisibleWithoutPhoneUpload"], 1),
    ("watch", ["WatchCommunityUITests/test10CumulativeStepsPageForwardBackAndRefresh",
               "WatchCommunityUITests/test20ShootingRangePages", "WatchCommunityUITests/test21StarStairRangePages",
               "WatchCommunityUITests/test40LargeTextRankingAndPictureControls"], 4),
    ("phone", ["PhoneAPIParityUITests/test10StepRankingPagesAndServerOutput",
               "PhoneAPIParityUITests/test20ShootingRangePages",
               "PhoneAPIParityUITests/test21StairsRangePagesAndComboOutput",
               "PhoneAPIParityUITests/test30PictureUpdatePersistsAcrossRelaunch",
               "PhoneAPIParityUITests/test40LargeDarkStepRankingAndPictureControls"], 5),
    ("watch", ["WatchSmallScreenUITests/testDateSelectionReturnsToCalendar",
               "WatchSmallScreenUITests/testYearAndMonthSelectionReturnAndRespectLeapDay",
               "WatchPetTouchUITests/test00SingleTouch"], 3),
]


def snapshot(args):
    baseline = flow.read(args.previous, "baseline.json")
    state = api.verify(args, baseline, 0)
    server = flow.read(flow.store(args.phone, flow.PHONE_BUNDLE), "mock-backend-v1.json")
    if server.get("image"):
        data = base64.b64decode(server["image"]["data"], validate=True)
        assert 0 < len(data) <= 32000
        state["profileImageSHA256"] = hashlib.sha256(data).hexdigest()
        state["pictureURL"] = server["pictureUrl"]
    return state


def run(args, index):
    side, tests, expected = GROUPS[index]
    other = "watch" if side == "phone" else "phone"
    peer = flow.WATCH_BUNDLE if other == "watch" else flow.PHONE_BUNDLE
    flow.launch_app(getattr(args, other), peer)
    scheme = "PetPet" if side == "phone" else "PetPet Watch App"
    sdk = "iphonesimulator" if side == "phone" else "watchsimulator"
    platform = "iOS Simulator" if side == "phone" else "watchOS Simulator"
    templates = list((args.build / "Build/Products").glob(f"{scheme}_{scheme}_{sdk}*-arm64.xctestrun"))
    assert len(templates) == 1, templates
    target = "PetPetUITests" if side == "phone" else "PetPet Watch AppUITests"
    result = args.artifacts / f"group-{index:02d}-{int(time.time())}.xcresult"
    log = result.with_suffix(".log")
    cmd = ["xcodebuild", "-xctestrun", str(templates[0]), "-destination",
           f"platform={platform},id={getattr(args, side)},arch=arm64", "-parallel-testing-enabled", "NO",
           "-resultBundlePath", str(result)]
    cmd += [f"-only-testing:{target}/{test}" for test in tests]
    cmd += ["test-without-building"]
    print(f"API group {index}: {side}, {expected} tests, log={log}", flush=True)
    with log.open("w") as output:
        process = subprocess.Popen(cmd, cwd=flow.ROOT, stdout=output, stderr=subprocess.STDOUT)
        started, peer_restarted = time.monotonic(), False
        bundle = flow.PHONE_BUNDLE if side == "phone" else flow.WATCH_BUNDLE
        while process.poll() is None:
            ready = f"Wait for {bundle} to idle" in log.read_text(errors="replace")
            if not ready and time.monotonic() - started > 120:
                process.terminate(); process.wait(timeout=30)
                raise RuntimeError(f"Simulator startup timed out: {log}")
            if ready and not peer_restarted:
                flow.command("xcrun", "simctl", "terminate", getattr(args, other), peer, check=False)
                flow.launch_app(getattr(args, other), peer); peer_restarted = True
            time.sleep(.5)
    assert process.returncode == 0, f"Native API group failed: {log}"
    summary = json.loads(flow.command("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result), "--compact"))
    assert (summary["passedTests"], summary["failedTests"], summary["skippedTests"]) == (expected, 0, 0)
    device = summary["devicesAndConfigurations"][0]["device"]
    assert device["deviceId"] == getattr(args, side) and device["platform"].endswith("Simulator")
    state = snapshot(args)
    if index == 1:
        previous = flow.read(args.artifacts, "state-00.json")
        assert state["profileImageSHA256"] == previous["profileImageSHA256"]
        assert state["pictureURL"] == previous["pictureURL"], "Phone read replaced the watch upload"
    state.update(group=index, tests=tests, passedTests=expected, failedTests=0, skippedTests=0,
                 resultBundle=str(result), device=device)
    flow.write(args.artifacts / f"state-{index:02d}.json", state)
    print(f"API group {index} passed; progression and phone snapshot unchanged", flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--phone", required=True); p.add_argument("--watch", required=True)
    p.add_argument("--build", type=Path, required=True)
    p.add_argument("--previous", type=Path, required=True)
    p.add_argument("--artifacts", type=Path, required=True)
    p.add_argument("--from-group", type=int, choices=range(len(GROUPS)), default=0)
    args = p.parse_args()
    prior = flow.read(args.previous, "state-00.json")
    assert prior and prior["passed"] and prior["nickname"].startswith("FinalWatch")
    assert prior["device"]["deviceId"] == args.watch
    args.artifacts.mkdir(parents=True, exist_ok=True)
    for index in range(args.from_group, len(GROUPS)):
        run(args, index)
    states = [flow.read(args.artifacts, f"state-{i:02d}.json") for i in range(len(GROUPS))]
    assert all(states)
    flow.write(args.artifacts / "result.json", dict(simulatorOnly=True, mockAccountOnly=True,
        passedUIExecutions=1+sum(s["passedTests"] for s in states), failedUIExecutions=0, skippedUIExecutions=0,
        nicknameResult=prior, groups=states))


if __name__ == "__main__": main()
