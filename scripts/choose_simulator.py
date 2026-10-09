"""Choose an available iPhone on the newest installed iOS simulator runtime."""
import json
import re
import sys


def choose_device(payload):
    candidates = []
    for runtime, devices in payload.get("devices", {}).items():
        match = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
        if not match:
            continue
        version = tuple(int(part or 0) for part in match.groups())
        for device in devices:
            if device.get("isAvailable") and "iPhone" in device.get("name", ""):
                candidates.append((version, device["name"], device["udid"]))
    if not candidates:
        raise SystemExit("No available iPhone simulator. Check the runner's installed Xcode runtimes.")
    return max(candidates)[2]


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as source:
        print("SIMULATOR_ID=" + choose_device(json.load(source)))

