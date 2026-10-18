#!/usr/bin/env bash
# The hooks example's native end-to-end suite in one command: boots the
# device, starts the showcase's backend and device control on the host, on
# ports of this suite's own (backend 5178, control 5179, proxy 5180), and
# runs `integration_test/` on the device against them. The showcase's
# `e2e-native/run.sh`, which this one follows, says more about each platform.
#
#   e2e-native/run.sh ios     [test file …]   an iOS simulator (IOS_DEVICE, default "iPhone 17 Pro")
#   e2e-native/run.sh android [test file …]   an Android emulator (AVD, default the first one listed)
#   e2e-native/run.sh macos   [test file …]   this Mac, as a desktop app: its window is sent away by
#                                             bringing Finder to the front
#   e2e-native/run.sh linux   [test file …]   a Linux desktop app, under xvfb-run when there is no
#                                             DISPLAY; nothing sends it away, so the tests that
#                                             leave the app skip themselves
#   e2e-native/run.sh web     [test file …]   Chrome, headless, through `flutter drive` and a
#                                             chromedriver (CHROMEDRIVER, default the one on PATH)
#                                             matching the installed Chrome, or the one
#                                             CHROME_EXECUTABLE names
#
# Without test files it runs the whole of `integration_test/`. MODE=profile
# runs it compiled ahead of time, as a user gets it, without the binding's
# debug-only assertions — through `flutter drive`, one file per build, and on
# Android only: an iOS simulator runs debug builds alone, and the driver
# takes a release build only in a browser (MODE=release with web). FLUTTER names
# the SDK's `flutter` (default: the one on PATH). A backend already listening
# on 5178 is reused; the device control is always this run's own. Logs land
# in `e2e-native/.logs/`. On the web the tests that need a device skip
# themselves.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$(dirname "$here")"
showcase="$(cd "$app/../../../examples/showcase" && pwd)"
platform="${1:?usage: run.sh ios|android|macos|linux|web [test file …]}"
shift
flutter="${FLUTTER:-flutter}"
logs="$here/.logs"
mkdir -p "$logs"

pids=()
cleanup() {
  for pid in "${pids[@]+"${pids[@]}"}"; do kill "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT

# Polls a URL until it answers, or gives up after thirty seconds.
wait_for() {
  for _ in $(seq 1 60); do
    curl -sf -o /dev/null "$1" && return 0
    sleep 0.5
  done
  echo "run.sh: $2 did not come up at $1 (see $logs)" >&2
  exit 1
}

case "$platform" in
  ios)
    name="${IOS_DEVICE:-iPhone 17 Pro}"
    device="$(xcrun simctl list devices available -j | node -e '
      const all = Object.values(JSON.parse(require("fs").readFileSync(0)).devices)
        .flat().filter((d) => d.name === process.argv[1])
      const pick = all.find((d) => d.state === "Booted") ?? all[0]
      if (!pick) process.exit(1)
      console.log(pick.udid)' "$name")" || {
      echo "run.sh: no available simulator named \"$name\"" >&2
      exit 1
    }
    xcrun simctl boot "$device" 2>/dev/null || true
    xcrun simctl bootstatus "$device" -b >/dev/null
    ;;
  android)
    sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
    export PATH="$sdk/platform-tools:$PATH"
    running() { adb devices | awk 'NR > 1 && $2 == "device" && $1 ~ /^emulator-/ { print $1; exit }'; }
    device="$(running)"
    if [ -z "$device" ]; then
      avd="${AVD:-$("$sdk/emulator/emulator" -list-avds | head -1)}"
      "$sdk/emulator/emulator" -avd "$avd" -no-window -no-audio -no-boot-anim \
        -no-snapshot-save >"$logs/emulator.log" 2>&1 &
      pids+=($!)
      adb wait-for-device
      until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 1; done
      device="$(running)"
    fi
    # Both survive a reboot, and an interrupted run may have left either.
    adb -s "$device" shell cmd connectivity airplane-mode disable
    adb -s "$device" shell settings put system user_rotation 0
    # A fresh boot, or a radio just switched back on, has no default network
    # for a few seconds; a test's first request would meet "Network is
    # unreachable".
    until ! adb -s "$device" shell dumpsys connectivity | grep -q 'Active default network: none'; do sleep 1; done
    ;;
  macos)
    device=macos
    ;;
  linux)
    device=linux
    # A desktop app needs a display; a headless machine lends it a virtual one.
    if [ -z "${DISPLAY:-}" ]; then exec xvfb-run -a "$0" linux "$@"; fi
    ;;
  web)
    device=web-server
    "${CHROMEDRIVER:-chromedriver}" --port=4444 >"$logs/chromedriver.log" 2>&1 &
    pids+=($!)
    wait_for http://localhost:4444/status chromedriver
    ;;
  *)
    echo "run.sh: unknown platform $platform (ios | android | macos | linux | web)" >&2
    exit 2
    ;;
esac
echo "run.sh: $platform on $device"

if ! curl -sf -o /dev/null http://localhost:5178/api/__scenario/probe/requests; then
  [ -d "$showcase/server/node_modules" ] || (cd "$showcase/server" && npm ci)
  (cd "$showcase/server" && PORT=5178 exec node server.ts) >"$logs/backend.log" 2>&1 &
  pids+=($!)
  wait_for http://localhost:5178/api/__scenario/probe/requests backend
fi

if curl -sf -o /dev/null http://localhost:5179/platform; then
  echo "run.sh: port 5179 is taken — is another device control running?" >&2
  exit 1
fi
(cd "$showcase/e2e-native" && PLATFORM="$platform" DEVICE="$device" \
  APP_ID=io.dualmeta.querykit.hooksexample CONTROL_PORT=5179 PROXY_PORT=5180 \
  BACKEND_PORT=5178 exec node device_control.ts) \
  >"$logs/device_control.log" 2>&1 &
pids+=($!)
wait_for http://localhost:5179/platform "device control"

cd "$app"
mode="${MODE:-debug}"
if [ "$mode" != debug ] && [ "$platform" = ios ]; then
  echo "run.sh: an iOS simulator runs debug builds only" >&2
  exit 2
fi
if [ "$mode" = release ] && [ "$platform" != web ]; then
  echo "run.sh: flutter drive takes a release build only on the web; use MODE=profile" >&2
  exit 2
fi
if [ "$platform" = web ] || [ "$mode" != debug ]; then
  # `flutter drive` runs one target per build.
  if [ "$#" -eq 0 ]; then set -- integration_test/*_test.dart; fi
  if [ "$platform" = web ]; then
    target_args=(-d web-server --browser-name=chrome --headless)
    # The Chrome the chromedriver matches: left to itself the driver starts
    # whichever Chrome is installed where it looks, which on a CI runner is
    # another version than the one set up beside the driver.
    if [ -n "${CHROME_EXECUTABLE:-}" ]; then
      target_args+=("--chrome-binary=$CHROME_EXECUTABLE")
    fi
  else
    target_args=(-d "$device")
  fi
  failed=()
  for target in "$@"; do
    echo "run.sh: $target ($mode)"
    "$flutter" drive "--$mode" --driver=test_driver/integration_test.dart \
      --target="$target" "${target_args[@]}" || failed+=("$target")
  done
  if [ "${#failed[@]}" -gt 0 ]; then
    echo "run.sh: failed ($platform, $mode): ${failed[*]}" >&2
    exit 1
  fi
elif [ "$platform" = macos ] || [ "$platform" = linux ]; then
  # A desktop app is not started a second time within one `flutter test`:
  # every file after the first fails with "Unable to start the app on the
  # device". One run per file.
  if [ "$#" -eq 0 ]; then set -- integration_test/*_test.dart; fi
  failed=()
  for target in "$@"; do
    echo "run.sh: $target"
    "$flutter" test "$target" -d "$device" || failed+=("$target")
  done
  if [ "${#failed[@]}" -gt 0 ]; then
    echo "run.sh: failed ($platform): ${failed[*]}" >&2
    exit 1
  fi
elif [ "$platform" = ios ]; then
  # One run per file, and a file whose app never came up ("loading … (failed)",
  # "Failed to load": the simulator did not start it, or its Dart Development
  # Service did not) once more, after the others. On a hosted runner the first
  # app after boot met "The log reader failed unexpectedly" three times in
  # three tries, on the same simulator and on one booted afresh, while every
  # file after it came up. No case of that file ran, so the second run is its
  # first; a case that ran and failed is not run again.
  if [ "$#" -eq 0 ]; then set -- integration_test/*_test.dart; fi
  failed=()
  again=()
  for target in "$@"; do
    echo "run.sh: $target"
    out="$(mktemp)"
    if "$flutter" test "$target" -d "$device" 2>&1 | tee "$out"; then
      :
    elif grep -qE 'loading .*\(failed\)$|Failed to load "' "$out"; then
      echo "run.sh: $target: the app did not come up; once more after the others"
      again+=("$target")
    else
      failed+=("$target")
    fi
    rm -f "$out"
  done
  for target in "${again[@]+"${again[@]}"}"; do
    echo "run.sh: $target, once more"
    "$flutter" test "$target" -d "$device" || failed+=("$target")
  done
  if [ "${#failed[@]}" -gt 0 ]; then
    echo "run.sh: failed ($platform): ${failed[*]}" >&2
    exit 1
  fi
else
  if [ "$#" -eq 0 ]; then set -- integration_test; fi
  "$flutter" test "$@" -d "$device"
fi
