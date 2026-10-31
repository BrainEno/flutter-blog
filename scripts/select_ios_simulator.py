#!/usr/bin/env python3
"""Select an available iOS simulator from `simctl list ... -j` on stdin."""

import argparse
import json
import re
import sys


def choose(devices, requested):
    candidates = []
    for runtime, entries in devices.items():
        if ".iOS-" not in runtime:
            continue
        version = tuple(int(n) for n in re.findall(r"\d+", runtime))
        for device in entries:
            if device.get("isAvailable") and device.get("udid") and device.get("name"):
                candidates.append((version, device))
    if requested:
        matches = [(v, d) for v, d in candidates if requested in (d["udid"], d["name"])]
        if len(matches) != 1:
            raise ValueError("Device name/UDID is missing or ambiguous. List devices with xcrun simctl list devices available and pass a UDID.")
        return matches[0][1]
    phones = [(v, d) for v, d in candidates if d["name"].startswith("iPhone")]
    if not phones:
        raise ValueError("No iPhone simulator is available. Install an iOS runtime and create a simulator in Xcode.")
    # Prefer a running iPhone. Otherwise use the newest installed iOS runtime;
    # sort by name/UDID to make the choice stable without prompting.
    phones.sort(key=lambda item: (item[1]["name"], item[1]["udid"]))
    phones.sort(key=lambda item: (item[1].get("state") == "Booted", item[0]), reverse=True)
    return phones[0][1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="")
    args = parser.parse_args()
    try:
        data = json.load(sys.stdin)
        selected = choose(data["devices"], args.device)
    except (ValueError, KeyError, TypeError) as error:
        print(f"Simulator error: {error}", file=sys.stderr)
        return 1
    print(f'{selected["udid"]}\t{selected.get("state", "Unknown")}')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
