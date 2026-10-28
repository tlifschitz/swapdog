#!/bin/bash
# Regenerates the README screenshots with freeze (brew install charmbracelet/tap/freeze).
# Both run against the fake sysctl/date/launchctl in tests/stubs, so they come out the
# same on any Mac and never touch the real launchd.
set -euo pipefail

cd "$(dirname "$0")/.."
freeze=(
  "$(command -v freeze)" --language text --window --margin 0
  --padding 20,40,24,24 --border.radius 10 --font.size 14
)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export PATH=$PWD/tests/stubs:/usr/bin:/bin

# swapdog status: a Mac that has been up for 22 days and stayed green all week.
mkdir "$tmp/state"
for _ in $(seq 1008); do echo "2026-10-27 10:00 pressure=1 acc=0"; done > "$tmp/state/history"
printf 'acc=0\nlast_boot=1000\nlast_pressure_bark=\nlast_uptime_bark_days=22\n' > "$tmp/state/state"
{
  echo '$ swapdog status'
  STATE_DIR=$tmp/state PLIST=/nonexistent FAKE_BOOT=1000 FAKE_NOW=$((1000 + 22 * 86400 + 3600)) \
    FAKE_PRESSURE=1 FAKE_TODAY=2026-10-28 bash swapdog.sh status
} > "$tmp/status.txt"
"${freeze[@]}" "$tmp/status.txt" -o docs/status.svg < /dev/null

# ./install.sh: the real installer in an empty home, saying yes to the PATH question.
# expect waits for the question, since the installer only asks on a terminal.
mkdir "$tmp/home"
{
  echo '$ ./install.sh'
  HOME=$tmp/home SHELL=/bin/zsh expect -c '
    spawn -noecho bash ./install.sh
    expect "\[y/N\] "
    send "y\r"
    expect eof
  ' | tr -d '\r'
} > "$tmp/install.txt"
"${freeze[@]}" "$tmp/install.txt" -o docs/install.svg < /dev/null

# ./uninstall.sh: removing what the install above put in that home.
{
  echo '$ ./uninstall.sh'
  HOME=$tmp/home bash ./uninstall.sh
} > "$tmp/uninstall.txt"
"${freeze[@]}" "$tmp/uninstall.txt" -o docs/uninstall.svg < /dev/null
