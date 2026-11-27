#!/usr/bin/env bash
# Start ASPIRE's four model services in tmux session "aspire-providers", inside both sandbox layers:
# the outer jail (aspire-sandbox.sh) and the inner layer (aspire-inner), so that code from ~/ASPIRE,
# which AI-written programs can change, never runs where the Claude login is visible.
# The jail is the pane's direct command (no shell behind it).
set -euo pipefail
tmux has-session -t aspire-providers 2>/dev/null && { echo "aspire-providers already running"; exit 0; }
mkdir -p "$HOME/ASPIRE/validation-artifacts"
tmux new-session -d -s aspire-providers \
  "$HOME/aspire-setup/aspire-sandbox.sh /run/aspire/aspire-inner 'cd ~/ASPIRE && scripts/supervise_services.sh --profile rtx4090 --providers sam3,contact_graspnet,pyroki,curobo 2>&1 | tee validation-artifacts/providers-supervisor.log'"
echo "started tmux session aspire-providers"
