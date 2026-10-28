#!/bin/bash
# swapdog: asks you to restart your Mac when memory pressure has been high for too
# long, or when it has simply been up for too many days. launchd runs it every 10
# minutes (see com.github.tlifschitz.swapdog.plist).
set -euo pipefail

INTERVAL=600                                          # must match StartInterval in the plist
PRESSURE_LIMIT_SECS=$(( ${SWAPDOG_PRESSURE_LIMIT_MIN:-60} * 60 ))
UPTIME_DAYS=${SWAPDOG_UPTIME_DAYS:-14}
UPTIME_REPEAT_DAYS=${SWAPDOG_UPTIME_REPEAT_DAYS:-7}
STATE_DIR=${STATE_DIR:-$HOME/.local/state/swapdog}
STATE=$STATE_DIR/state
HISTORY=$STATE_DIR/history
HISTORY_LINES=${HISTORY_LINES:-1008}                  # a week of 10-minute checks
ICON=${ICON:-$HOME/.local/share/swapdog/swapdog.png}

mkdir -p "$STATE_DIR"

boot=$(sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+).*/\1/')
pressure=$(sysctl -n kern.memorystatus_vm_pressure_level)  # 1 normal, 2 warning, 4 critical
uptime_days=$(( ($(date +%s) - boot) / 86400 ))
today=$(date +%F)

acc=0
last_boot=$boot
last_pressure_bark=""
last_uptime_bark_days=""
[[ -f $STATE ]] && source "$STATE"

# A restart wipes the slate clean.
if [[ $last_boot != "$boot" ]]; then
  acc=0
  last_pressure_bark=""
  last_uptime_bark_days=""
fi

# Leaky bucket: high pressure fills it, normal pressure drains it at the same pace.
# A fixed interval per run (not wall-clock time) means only awake time counts:
# launchd doesn't run the script while the Mac is asleep.
if (( pressure >= 2 )); then
  acc=$((acc + INTERVAL))
elif (( acc > 0 )); then
  acc=$((acc - INTERVAL))
fi

# The uptime bark is the gentle one: only when memory is fine right now, never on a
# day the pressure bark already went off, and then once every few days.
uptime_bark_due() {
  (( pressure == 1 && uptime_days >= UPTIME_DAYS )) || return 1
  [[ $last_pressure_bark != "$today" ]] || return 1
  [[ -z $last_uptime_bark_days ]] || (( uptime_days >= last_uptime_bark_days + UPTIME_REPEAT_DAYS ))
}

message=""
if (( acc >= PRESSURE_LIMIT_SECS )) && [[ $last_pressure_bark != "$today" ]]; then
  message="Woof! Your Mac has been short on memory for $((acc / 60)) minutes. Close a few things or restart. Good human."
  last_pressure_bark=$today
elif uptime_bark_due; then
  message="Woof! Memory looks fine, but it's been $uptime_days days since your last restart. A fresh start and a walk in the park would do us both good."
  last_uptime_bark_days=$uptime_days
fi

# Save before barking: the dialog blocks until it's answered (or gives up after an
# hour), and launchd skips runs while this one is still going.
printf 'acc=%d\nlast_boot=%s\nlast_pressure_bark=%s\nlast_uptime_bark_days=%s\n' \
  "$acc" "$boot" "$last_pressure_bark" "$last_uptime_bark_days" > "$STATE"
echo "$(date '+%F %R') pressure=$pressure acc=$acc" >> "$HISTORY"
tail -n "$HISTORY_LINES" "$HISTORY" > "$HISTORY.tmp" && mv "$HISTORY.tmp" "$HISTORY"

if [[ -n $message ]]; then
  osascript - "$message" "$ICON" <<'EOF'
on run argv
  set {message, iconPath} to argv
  try
    set dogIcon to (POSIX file iconPath) as alias
  on error
    set dogIcon to note
  end try
  set answer to button returned of (display dialog message with title "swapdog" with icon dogIcon buttons {"Later", "Restart now"} default button "Later" giving up after 3600)
  if answer is "Restart now" then tell application "System Events" to restart
end run
EOF
fi
