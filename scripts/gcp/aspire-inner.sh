#!/bin/bash
# aspire-inner: the second sandbox layer (unchanged from node002). The outer jail
# (aspire-sandbox.sh) sets CLAUDE_CODE_SHELL_PREFIX to this script (bound read-only at
# /run/aspire/aspire-inner), so the sandboxed Claude Code runs every Bash command as
# `aspire-inner '<command>'`. The command, and any program it starts (AI-written robot programs
# included), runs in a nested bubblewrap sandbox where:
#   - the Claude login is hidden: ~/.claude becomes an empty tmpfs and ~/.claude.json reads empty;
#   - Claude Code's own process is invisible (new PID namespace and /proc);
#   - files that code outside this layer later runs or trusts are read-only: the private home
#     (shell rc files, ~/.local/bin, ~/.config), the repo's whole .git directory (git history can
#     be read but not committed to), and Claude Code's project settings files;
#   - the rest matches the outer jail: ~/ASPIRE, ~/.cache, ~/.nv and /tmp writable, the GPU, and
#     the network (shared, so the provider services on 127.0.0.1 stay reachable).
# Background children outlive the command: bubblewrap's PID-1 helper waits for all of them.
# Not covered: Claude Code's own tools run outside this layer (its Read tool can still open the
# token file), and files the agent reads, such as skills and run outputs, can still try to steer it.
# Manual use inside the jail: aspire-inner '<command>'.
set -euo pipefail
if [ "$#" -ne 1 ]; then echo "usage: aspire-inner '<command>'" >&2; exit 2; fi
H="$HOME"
R="$H/ASPIRE"
args=(
  --bind / / --dev-bind /dev /dev
  --unshare-pid --proc /proc
  --ro-bind "$H" "$H"
  --bind "$R" "$R"
  --tmpfs "$H/.claude"
  --ro-bind "$R/.git" "$R/.git"
  --ro-bind "$R/.claude/settings.json" "$R/.claude/settings.json"
  --ro-bind "$R/.claude/settings.local.json" "$R/.claude/settings.local.json"
)
if [ -e "$H/.claude.json" ]; then args+=(--ro-bind /dev/null "$H/.claude.json"); fi
for d in .cache .nv; do
  if [ -d "$H/$d" ]; then args+=(--bind "$H/$d" "$H/$d"); fi
done
# Claude Code may source a shell snapshot from ~/.claude/shell-snapshots before each command.
if [ -d "$H/.claude/shell-snapshots" ]; then
  args+=(--bind "$H/.claude/shell-snapshots" "$H/.claude/shell-snapshots")
fi
# Claude Code's local session sockets (messages into the running session) stay out of reach.
if [ -d /tmp/cc-socks ]; then args+=(--tmpfs /tmp/cc-socks); fi
# Claude Code hands its commands a token for messaging the running session; nothing in here needs it.
exec /usr/bin/env -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_MESSAGING_SOCKET \
  /usr/bin/bwrap "${args[@]}" /bin/bash -c "$1"
