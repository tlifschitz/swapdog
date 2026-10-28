#!/bin/bash
# Stops swapdog and removes everything install.sh put in place.
set -euo pipefail

LABEL=com.github.tlifschitz.swapdog

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/swapdog"
rm -rf "$HOME/.local/share/swapdog" "$HOME/.local/state/swapdog"

echo "swapdog went to live on a farm upstate. Remember to restart once in a while."
