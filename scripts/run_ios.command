#!/bin/bash
# Finder double-click entry point. Arguments can also be passed from Terminal.
exec "$(cd "$(dirname "$0")" && pwd)/run_ios.sh" "$@"
