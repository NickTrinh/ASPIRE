#!/usr/bin/env bash
# Start the Phase 5 agent: Claude Code inside the jail as the direct command of tmux pane
# "aspire-agent" (bash execs into claude, so no shell stays behind it), with the campaign prompt
# read from the private home (~/aspire-home/phase5-prompt.txt on the host, ~/phase5-prompt.txt
# inside). Model, effort and permission mode come from the jail's settings and environment.
set -euo pipefail
tmux has-session -t aspire-agent 2>/dev/null && { echo "aspire-agent already running"; exit 0; }
tmux new-session -d -s aspire-agent -x 220 -y 50 \
  "$HOME/aspire-setup/aspire-sandbox.sh /bin/bash -c 'exec claude \"\$(cat ~/phase5-prompt.txt)\"'"
echo "started tmux session aspire-agent"
