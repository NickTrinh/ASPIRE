#!/usr/bin/env bash
# Auto-resume for the Phase 5 campaign (Nick's OK on 2026-11-27: "Pro + resume"). Runs on the
# cloud machine, outside the jail, in tmux session "aspire-resume", so it keeps working when the
# laptop sleeps or the laptop's Claude session is itself rate-limited.
# Every 5 minutes it reads the agent's pane (tmux session "aspire-agent"):
#   - Claude Code's limit menu ("1. Stop and wait ... 2. Wait here, then continue automatically
#     shortly 3. Switch to usage credits 4. Upgrade your plan"): it moves the cursor to "Wait here,
#     then continue automatically", checks the cursor is there, and presses Enter. It never picks
#     the credits or upgrade options and never presses Esc.
#   - "Continuing shortly" on screen: Claude Code is already waiting to continue; nothing to do.
#   - Otherwise, only when the agent is idle AND its last lines show a usage-limit message, it
#     types "continue" (a fallback; while the limit holds, Claude Code just shows it again).
# It never types anything when the agent is busy or idle for another reason.
set -u
LOG="$HOME/aspire-setup/logs/resume.log"
log() { echo "$(date -u '+%F %T') $*" >> "$LOG"; }
while tmux has-session -t aspire-agent 2>/dev/null; do
  pane=$(tmux capture-pane -p -J -t aspire-agent)
  tail=$(printf '%s\n' "$pane" | grep -v '^[[:space:]]*$' | tail -25)
  if printf '%s\n' "$tail" | grep -q 'Wait here, then continue automatically'; then
    want=$(printf '%s\n' "$tail" | grep -oE '[0-9]\. Wait here, then continue automatically' | head -1 | cut -c1)
    cur=$(printf '%s\n' "$tail" | grep -oE '❯ [0-9]\.' | head -1 | grep -oE '[0-9]')
    if [ -n "$want" ] && [ -n "$cur" ]; then
      steps=$((want - cur)); key=Down
      if [ "$steps" -lt 0 ]; then steps=$((-steps)); key=Up; fi
      for _ in $(seq 1 "$steps"); do tmux send-keys -t aspire-agent "$key"; sleep 0.5; done
      sleep 1
      if tmux capture-pane -p -J -t aspire-agent | grep -qE "❯ ${want}\. Wait here"; then
        tmux send-keys -t aspire-agent Enter
        log "chose option $want (Wait here, then continue automatically)"
      else
        log "limit menu open but the cursor did not land on Wait here; left it"
      fi
    fi
  elif printf '%s\n' "$tail" | grep -q 'Continuing shortly'; then
    :  # Claude Code waits for the reset and continues by itself
  else
    busy=0
    printf '%s\n' "$pane" | grep -qE '… \([0-9]+[smh]|Waiting for [0-9]+ background' && busy=1
    if [ "$busy" = 0 ] && printf '%s\n' "$tail" | grep -qiE 'limit reached|hit your limit|usage limit|limit will reset|resets [0-9]'; then
      tmux send-keys -t aspire-agent -l 'continue'
      sleep 1
      tmux send-keys -t aspire-agent Enter
      log "typed continue"
    fi
  fi
  sleep 300
done
log "aspire-agent session gone; stopping"
