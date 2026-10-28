#!/bin/bash
# swapdog: asks you to restart your Mac when memory pressure has been high for too
# long, or when it has simply been up for too many days. launchd runs it every 10
# minutes (see com.github.tlifschitz.swapdog.plist). `swapdog status` explains what
# it has seen without changing anything.
set -euo pipefail

PLIST=${PLIST:-$HOME/Library/LaunchAgents/com.github.tlifschitz.swapdog.plist}

# launchd passes the settings as environment variables; from a terminal they're read
# from the installed plist instead, so `swapdog status` sees the same values.
setting() {  # setting <name> <default>
  local value=${!1:-}
  if [[ -z $value && -f $PLIST ]]; then
    value=$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:$1" "$PLIST" 2>/dev/null) || true
  fi
  echo "${value:-$2}"
}

INTERVAL=600                                          # must match StartInterval in the plist
PRESSURE_LIMIT_SECS=$(( $(setting SWAPDOG_PRESSURE_LIMIT_MIN 60) * 60 ))
UPTIME_DAYS=$(setting SWAPDOG_UPTIME_DAYS 14)
UPTIME_REPEAT_DAYS=$(setting SWAPDOG_UPTIME_REPEAT_DAYS 7)
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

duration() {  # duration <minutes>
  local m=$1
  if (( m == 1 )); then echo "1 minute"
  elif (( m < 60 )); then echo "$m minutes"
  elif (( m < 120 )); then echo "1 hour"
  else echo "$((m / 60)) hours"
  fi
}

status() {
  local -a colors=([1]=green [2]=yellow [4]=red)
  local checks=0 high=0 peak=0
  if [[ -f $HISTORY ]]; then
    checks=$(wc -l < "$HISTORY" | tr -d ' ')
    high=$(grep -vc pressure=1 "$HISTORY" || true)
    peak=$(sed -E 's/.*acc=//' "$HISTORY" | sort -n | tail -1)
  fi
  local limit_min=$((PRESSURE_LIMIT_SECS / 60)) high_min=$((high * 10)) peak_min=$((peak / 60))
  local next_uptime=$UPTIME_DAYS
  [[ -z $last_uptime_bark_days ]] || next_uptime=$((last_uptime_bark_days + UPTIME_REPEAT_DAYS))

  echo "🐶 swapdog"
  echo
  echo "Memory pressure: ${colors[$pressure]:-unknown} right now, bucket at $((acc / 60)) of $limit_min minutes"
  if (( uptime_days == 0 )); then
    echo "Uptime:          just restarted, $(duration $(( ($(date +%s) - boot) / 60 ))) ago. Good human 🦴"
  elif (( uptime_days >= next_uptime )); then
    echo "Uptime:          $uptime_days days, restart reminder due once memory pressure is green"
  else
    echo "Uptime:          $uptime_days days, next restart reminder at $next_uptime days"
  fi
  echo "Watched:         $(duration $((checks * 10))) awake, $(duration "$high_min") of it in yellow or red, bucket peaked at $(duration "$peak_min")"
  echo

  if [[ -n $last_pressure_bark ]]; then
    echo "It barked on $last_pressure_bark because memory pressure stayed high for $limit_min minutes."
    echo "See how the bucket filled up with: grep -v pressure=1 $HISTORY"
  elif (( checks == 0 )); then
    echo "swapdog hasn't sniffed anything yet. It checks every 10 minutes."
  elif (( checks < 144 )); then
    echo "swapdog is new here: it started watching on $(head -1 "$HISTORY" 2>/dev/null | cut -d' ' -f1-2)."
    echo "Give it a day of use before judging your Mac."
  elif (( high == 0 )); then
    echo "Your Mac hasn't struggled with memory all week. Good machine, nothing to tune."
  else
    echo "It saw some yellow or red, but the bucket never got past $peak_min of $limit_min minutes."
    echo "If your Mac felt slow at those times, lower SWAPDOG_PRESSURE_LIMIT_MIN in the plist."
  fi
}

case ${1:-} in
  "") ;;
  status) status; exit 0 ;;
  *) echo "usage: swapdog [status]" >&2; exit 2 ;;
esac

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
