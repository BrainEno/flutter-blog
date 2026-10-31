#!/bin/bash
# Run a debug build on an existing or automatically started iOS simulator.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/run_ios.sh [--config env.json] [--device SIMULATOR_UDID_OR_NAME] [--boot-timeout SECONDS]
Starts/uses an iOS simulator and runs the Flutter debug app. No simulator is erased or shut down.
EOF
}

config=env.json
device=''
boot_timeout=300
while (($#)); do
  case "$1" in
    --config|--device|--boot-timeout)
      [[ $# -ge 2 ]] || fail "Missing value for $1."
      case "$1" in
        --config) config="$2" ;;
        --device) device="$2" ;;
        --boot-timeout) boot_timeout="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done
[[ "$boot_timeout" =~ ^[0-9]+$ ]] && ((boot_timeout >= 1 && boot_timeout <= 1800)) || fail 'Boot timeout must be 1–1800 seconds.'
require_macos
require_command open
check_flutter_version
resolve_config "$config"
validate_config ios debug
cd "$PROJECT_ROOT"

selection="$(xcrun simctl list devices available -j | python3 "$SCRIPT_DIR/select_ios_simulator.py" --device "$device")" || fail 'Could not select an iOS simulator.'
IFS=$'\t' read -r udid state <<< "$selection"
[[ -n "$udid" ]] || fail 'The simulator did not have a UDID.'
printf 'Using iOS simulator %s (%s).\n' "$udid" "$state"
if [[ "$state" != Booted ]]; then
  xcrun simctl boot "$udid" || fail 'Could not boot the selected simulator.'
fi
open -a Simulator
python3 "$SCRIPT_DIR/wait_for_ios_simulator.py" "$udid" "$boot_timeout"
flutter pub get
flutter run --debug -d "$udid" --dart-define-from-file="$CONFIG_PATH" --dart-define=BELOG_DEV_BACKEND_CHECK=true
