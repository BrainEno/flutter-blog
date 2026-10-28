#!/usr/bin/env python3
"""Expose actionable diagnostics in check annotations as well as log artifacts."""

import re
import sys
from pathlib import Path


def main() -> int:
    mode, filename = sys.argv[1:]
    lines = Path(filename).read_text(encoding="utf-8", errors="replace").splitlines()
    if mode == "analyze":
        selected = lines[-100:]
    elif mode == "android":
        # Include context around Gradle/Flutter errors without dumping the entire
        # verbose build log (which may include environment-dependent values).
        indices = set()
        for index, line in enumerate(lines):
            if re.search(r"FAILURE: Build failed|What went wrong:|Execution failed for task|^.*\berror:|^.*\bError:|Caused by:|requires.*compileSdk|Android resource linking failed", line, re.I):
                indices.update(range(max(0, index - 1), min(len(lines), index + 5)))
        selected = [lines[index] for index in sorted(indices)]
    else:
        raise ValueError(f"Unknown diagnostic mode: {mode}")

    message = "\n".join(selected)[-24000:] or "No matching diagnostics; inspect the uploaded log artifact."
    # Escape workflow command data so multi-line diagnostics remain one annotation.
    message = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error title={mode} failure diagnostics::{message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
