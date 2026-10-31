#!/usr/bin/env python3
"""Wait for an iOS simulator to finish booting, with a bounded timeout."""

import subprocess
import sys


def main():
    udid, timeout = sys.argv[1], int(sys.argv[2])
    try:
        subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print("Simulator boot timed out; open Xcode's Devices and Simulators window and try again.", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError:
        print("Simulator boot failed; inspect the Xcode simulator and try again.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
