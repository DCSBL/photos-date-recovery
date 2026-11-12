#!/usr/bin/env python3
"""Print the UDID of an available iOS simulator with the given device name on the newest iOS runtime.

Creates one when the runner image has the device type and runtime but no device yet.
Usage: pick_simulator.py "iPhone 17"
"""
import json
import subprocess
import sys


def simctl(*args):
    return json.loads(subprocess.check_output(["xcrun", "simctl", "list", *args, "-j"]))


def ios_version(runtime_id):
    # com.apple.CoreSimulator.SimRuntime.iOS-27-2 -> (27, 2)
    if "SimRuntime.iOS-" not in runtime_id:
        return None
    return tuple(int(part) for part in runtime_id.rsplit("iOS-", 1)[1].split("-"))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    name = sys.argv[1]

    best = None
    for runtime, devices in simctl("devices", "available")["devices"].items():
        version = ios_version(runtime)
        if version is None:
            continue
        for device in devices:
            if device["name"] == name and device.get("isAvailable", True):
                if best is None or version > best[0]:
                    best = (version, device["udid"])
    if best:
        print(best[1])
        return

    device_types = [t for t in simctl("devicetypes")["devicetypes"] if t["name"] == name]
    runtimes = [r for r in simctl("runtimes", "available")["runtimes"] if r.get("platform") == "iOS"]
    if not device_types or not runtimes:
        names = sorted({d["name"] for ds in simctl("devices", "available")["devices"].values() for d in ds})
        sys.exit(f"No simulator or device type named {name!r}. Available: {names}")
    runtime = max(runtimes, key=lambda r: tuple(int(p) for p in r["version"].split(".")))
    udid = subprocess.check_output(
        ["xcrun", "simctl", "create", name, device_types[0]["identifier"], runtime["identifier"]], text=True
    ).strip()
    print(udid)


if __name__ == "__main__":
    main()
