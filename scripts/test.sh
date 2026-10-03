#!/bin/sh
# Runs `swift test`, forwarding all arguments.
# With REMINDERS_MCP_INTEGRATION=1, builds the binaries first for the integration tests.
#
# With only the Command Line Tools installed, Swift Testing ships in the CLT
# but isn't on SwiftPM's default search paths, so add them. With Xcode selected
# this is a plain `swift test`.
set -eu

# Integration tests drive the built launcher and server binaries, so make sure they're current
# and signed (see scripts/build.sh).
if [ "${REMINDERS_MCP_INTEGRATION:-}" = "1" ]; then
  "$(dirname "$0")/build.sh"
fi

dev_dir="$(xcode-select -p)"
case "$dev_dir" in
  */CommandLineTools)
    fw="$dev_dir/Library/Developer/Frameworks"
    lib="$dev_dir/Library/Developer/usr/lib"
    exec swift test \
      -Xswiftc -F"$fw" \
      -Xlinker -F"$fw" \
      -Xlinker -rpath -Xlinker "$fw" \
      -Xlinker -rpath -Xlinker "$lib" \
      "$@"
    ;;
  *)
    exec swift test "$@"
    ;;
esac
