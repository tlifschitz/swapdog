#!/bin/bash
# swapdog: nudges you to restart your Mac once swap or memory pressure has stayed
# high for 4 hours of accumulated awake time. launchd runs it every 10 minutes
# (see com.github.tlifschitz.swapdog.plist).
set -euo pipefail

INTERVAL=600                          # must match StartInterval in the plist
HIGH_MB=6144                          # count time while swap is above 6 GB...
LOW_MB=5120                           # ...and reset once it drops below 5 GB (hysteresis)
LIMIT_SECS=${LIMIT_SECS:-14400}       # 4 hours
STATE_DIR=${STATE_DIR:-$HOME/.local/state/swapdog}
STATE=$STATE_DIR/state
ICON=${ICON:-$HOME/.local/share/swapdog/swapdog.png}

mkdir -p "$STATE_DIR"

boot=$(sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+).*/\1/')
swap_mb=$(sysctl -n vm.swapusage | awk '{
  for (i = 1; i <= NF; i++) if ($i == "used") {
    v = $(i + 2); unit = substr(v, length(v)); v = substr(v, 1, length(v) - 1)
    if (unit == "G") v *= 1024
    printf "%d", v
  }
}')
pressure=$(sysctl -n kern.memorystatus_vm_pressure_level)  # 1 normal, 2 warning, 4 critical

acc=0
last_boot=$boot
last_notified=""
[[ -f $STATE ]] && source "$STATE"

# A restart wipes the slate clean.
if [[ $last_boot != "$boot" ]]; then
  acc=0
  last_notified=""
fi

# Add a fixed interval (not wall-clock time since the last run) so only awake time
# counts: launchd doesn't run the script while the Mac is asleep.
if (( swap_mb > HIGH_MB || pressure >= 2 )); then
  acc=$((acc + INTERVAL))
elif (( swap_mb < LOW_MB )); then
  acc=0
fi

today=$(date +%F)
bark=false
if (( acc >= LIMIT_SECS )) && [[ $last_notified != "$today" ]]; then
  bark=true
  last_notified=$today
fi

# Save before barking: the dialog blocks until it's answered (or gives up after an
# hour), and launchd skips runs while this one is still going.
printf 'acc=%d\nlast_boot=%s\nlast_notified=%s\n' "$acc" "$boot" "$last_notified" > "$STATE"

if $bark; then
  osascript - "Woof! Swap has been at $((swap_mb / 1024)) GB for $((acc / 3600)) h. Save your stuff and restart. Good human." "$ICON" <<'EOF'
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
