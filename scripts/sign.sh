#!/bin/sh
# Signs the launcher and server binaries in the given build directory with a stable identity.
#
# macOS ties the Reminders grant to the binary's code signature. The linker's ad-hoc
# signature changes on every build, so the grant would be lost (and macOS would re-prompt)
# after each rebuild. A fixed signing identity keeps the grant across rebuilds and upgrades.
# Create the identity once in Keychain Access; see README.md.
set -eu

bin_dir="$1"
identity="${REMINDERS_MCP_SIGNING_IDENTITY:-apple-reminders-mcp dev}"

if ! security find-certificate -c "$identity" >/dev/null 2>&1; then
  echo "warning: signing identity '$identity' not found; binaries stay ad-hoc signed" \
    "and Reminders access will be re-requested after every rebuild" >&2
  exit 0
fi

for name in apple-reminders-mcp apple-reminders-mcp-launch; do
  codesign --force --sign "$identity" --identifier "com.charlygaribay.$name" "$bin_dir/$name"
done
