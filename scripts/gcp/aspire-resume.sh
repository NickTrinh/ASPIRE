#!/usr/bin/env bash
# Auto-resume for the Phase 5 campaign (Nick's OK on 2026-11-27: "Pro + resume"). Runs on the
# cloud machine, outside the jail, in tmux session "aspire-resume", so it keeps working when the
# laptop sleeps or the laptop's Claude session is itself rate-limited.
# Every 10 minutes it reads the agent's pane (tmux session "aspire-agent"). Only when the agent is
# idle AND its last lines show a usage-limit message does it act:
#   - a limit menu offering "Stop and wait" gets that option's number (never any other option);
#   - otherwise it types "continue". While the limit still holds, Claude Code just shows the limit
#     message again, which costs nothing.
# It never types anything when the agent is busy or idle for another reason.
set -u
LOG="$HOME/aspire-setup/logs/resume.log"
while tmux has-session -t aspire-agent 2>/dev/null; do
  pane=$(tmux capture-pane -p -J -t aspire-agent)
  tail=$(printf '%s\n' "$pane" | grep -v '^[[:space:]]*$' | tail -25)
  busy=0
  printf '%s\n' "$pane" | grep -qE '… \([0-9]+[smh]|Waiting for [0-9]+ background' && busy=1
  limit=0
  printf '%s\n' "$tail" | grep -qiE 'limit reached|hit your limit|usage limit|limit will reset|resets [0-9]' && limit=1
  if [ "$busy" = 0 ] && [ "$limit" = 1 ]; then
    option=$(printf '%s\n' "$tail" | grep -oE '[0-9]\. Stop and wait' | head -1 | cut -c1)
    if [ -n "$option" ]; then
      tmux send-keys -t aspire-agent "$option"
      echo "$(date -u '+%F %T') chose option $option (Stop and wait)" >> "$LOG"
    else
      tmux send-keys -t aspire-agent -l 'continue'
      sleep 1
      tmux send-keys -t aspire-agent Enter
      echo "$(date -u '+%F %T') typed continue" >> "$LOG"
    fi
  fi
  sleep 600
done
echo "$(date -u '+%F %T') aspire-agent session gone; stopping" >> "$LOG"
