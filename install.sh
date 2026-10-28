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

echo "swapdog is on duty."

# `swapdog status` needs ~/.local/bin on the PATH, which a fresh Mac doesn't have.
case :$PATH: in
  *":$HOME/.local/bin:"*) echo "Ask it how things are going with: swapdog status"; exit 0 ;;
esac

case $(basename "${SHELL:-}") in
  zsh) rc=$HOME/.zshrc ;;
  bash) rc=$HOME/.bash_profile ;;
  *)
    echo "To use 'swapdog status', add ~/.local/bin to your PATH."
    exit 0
    ;;
esac

line='export PATH="$HOME/.local/bin:$PATH"'
if [[ -f $rc ]] && grep -qF "$line" "$rc"; then
  echo "Open a new terminal and ask it how things are going with: swapdog status"
  exit 0
fi

answer=""
read -r -p "~/.local/bin isn't on your PATH. Add it to ~/${rc#"$HOME"/} so 'swapdog status' works? [y/N] " answer || true
if [[ $answer == [yY]* ]]; then
  printf '\n# Added by swapdog\n%s\n' "$line" >> "$rc"
  echo "Done. Open a new terminal and ask it how things are going with: swapdog status"
else
  echo "No problem. You can always run it as: ~/.local/bin/swapdog status"
fi
