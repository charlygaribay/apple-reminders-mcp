#!/bin/sh
# Runs `swift test`, forwarding all arguments.
#
# With only the Command Line Tools installed, Swift Testing ships in the CLT but isn't on
# SwiftPM's default search paths, so add them. With Xcode selected no extra flags are needed.
#
# With REMINDERS_MCP_INTEGRATION=1, the launcher and server binaries are signed after the
# build and before the tests run (see scripts/sign.sh). Building and testing are separate
# steps so that `swift test` can't relink, and thereby un-sign, the binaries afterwards.
set -eu

dev_dir="$(xcode-select -p)"
case "$dev_dir" in
  */CommandLineTools)
    fw="$dev_dir/Library/Developer/Frameworks"
    lib="$dev_dir/Library/Developer/usr/lib"
    # Paths under the CLT directory contain no spaces, so word splitting is safe here.
    flags="-Xswiftc -F$fw -Xlinker -F$fw -Xlinker -rpath -Xlinker $fw -Xlinker -rpath -Xlinker $lib"
    ;;
  *)
    flags=""
    ;;
esac

# shellcheck disable=SC2086
swift build --build-tests $flags
if [ "${REMINDERS_MCP_INTEGRATION:-}" = "1" ]; then
  # shellcheck disable=SC2086
  "$(dirname "$0")/sign.sh" "$(swift build $flags --show-bin-path)"
fi
# shellcheck disable=SC2086
exec swift test --skip-build $flags "$@"
