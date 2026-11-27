#!/bin/bash
# Builds Smolix, replaces /Applications/Smolix.app and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

DEST="/Applications/Smolix.app"

if pgrep -x Smolix >/dev/null; then
    echo "▸ Quitting running Smolix"
    pkill -x Smolix || true
    for _ in {1..20}; do pgrep -x Smolix >/dev/null || break; sleep 0.1; done
fi

echo "▸ Installing to $DEST"
rm -rf "$DEST"
ditto build/Smolix.app "$DEST"

open "$DEST"
echo "✓ Smolix installed and launched"
