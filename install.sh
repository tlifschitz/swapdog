#!/bin/bash
# Installs swapdog for the current user and starts it.
set -euo pipefail

cd "$(dirname "$0")"
LABEL=com.github.tlifschitz.swapdog
PLIST=$HOME/Library/LaunchAgents/$LABEL.plist

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/swapdog" "$HOME/.local/state/swapdog" "$HOME/Library/LaunchAgents"
install -m 755 swapdog.sh "$HOME/.local/bin/swapdog"
install -m 644 swapdog.png "$HOME/.local/share/swapdog/swapdog.png"
sed "s|__HOME__|$HOME|g" "$LABEL.plist" > "$PLIST"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "swapdog is on duty. Check its notes with: cat ~/.local/state/swapdog/state"
