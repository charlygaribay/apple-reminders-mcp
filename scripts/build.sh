#!/bin/sh
# Runs `swift build` (forwarding all arguments), then signs both binaries with a stable
# identity so the Reminders grant survives rebuilds (see scripts/sign.sh).
set -eu

swift build "$@"
"$(dirname "$0")/sign.sh" "$(swift build "$@" --show-bin-path)"
