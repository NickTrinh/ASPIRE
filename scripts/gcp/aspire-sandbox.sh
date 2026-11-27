#!/usr/bin/env bash
# Run a shell or a command inside a bubblewrap jail for ASPIRE (Google Cloud L4 machine version of
# the node002 launcher). Inside the jail: system folders read-only, the GPU, the network, ~/ASPIRE
# writable, and a private home (~/aspire-home) shown at the real home path. The rest of the real
# home (~/.ssh, the setup scripts) is hidden.
# Start it as the direct command of a tmux pane, not from a shell you keep using, so keystrokes
# injected into the terminal have no shell to land in.
# Changes from node002: profile rtx4090 (one 24 GB Ada GPU, the L4), the system git, no cluster-only
# folders (/cm, the conda devtools env), and GPU device nodes mounted only if they exist.
set -euo pipefail

REAL_HOME="$HOME"
HOMES_ROOT="$(dirname "$REAL_HOME")"
SETUP="$REAL_HOME/aspire-setup"
PRIVATE_HOME="$REAL_HOME/aspire-home"
REPO="$REAL_HOME/ASPIRE"
SCRATCH="/tmp/${USER}-aspire-tmp"             # mounted as /tmp inside
# The agent controls ~/aspire-home from inside the jail. The lines below write there from outside
# the jail, so refuse to follow any symlink it may have planted on those paths.
for d in "$PRIVATE_HOME" "$PRIVATE_HOME/.local" "$PRIVATE_HOME/.local/bin"; do
  if [ -L "$d" ]; then echo "refusing to start: $d is a symlink" >&2; exit 1; fi
done
mkdir -p "$PRIVATE_HOME/.local/bin" "$SCRATCH" "$SETUP/sandbox-etc"

{ cat /etc/passwd; getent passwd "$USER" || true; } > "$SETUP/sandbox-etc/passwd"
{ cat /etc/group; getent group "$(id -g)" || true; } > "$SETUP/sandbox-etc/group"

# The private home's claude command points at the read-only versions folder bound below.
ln -sfn "$(readlink -f "$REAL_HOME/.local/bin/claude")" "$PRIVATE_HOME/.local/bin/claude"

args=(
  --unshare-pid --unshare-ipc --unshare-uts --hostname aspire-sandbox --die-with-parent
  --ro-bind /usr /usr --ro-bind /etc /etc
  --ro-bind "$SETUP/sandbox-etc/passwd" /etc/passwd --ro-bind "$SETUP/sandbox-etc/group" /etc/group
  --symlink usr/bin /bin --symlink usr/sbin /sbin --symlink usr/lib /lib --symlink usr/lib64 /lib64
  --ro-bind /sys /sys --proc /proc --dev /dev --tmpfs /dev/shm --tmpfs /run --tmpfs /var
  --bind "$SCRATCH" /tmp
  --tmpfs "$HOMES_ROOT"
  --bind "$PRIVATE_HOME" "$REAL_HOME"
  --bind "$REPO" "$REPO" --chdir "$REPO"
  --ro-bind "$SETUP/empty-AGENTS.md" "$REPO/AGENTS.md"
  --ro-bind "$REAL_HOME/.local/share/uv/python" "$REAL_HOME/.local/share/uv/python"
  --ro-bind "$REAL_HOME/.local/share/claude/versions" "$REAL_HOME/.local/share/claude/versions"
  --ro-bind "$REAL_HOME/.local/bin/uv" "$REAL_HOME/.local/bin/uv"
  --ro-bind "$SETUP/aspire-inner.sh" /run/aspire/aspire-inner
)
[ -d /opt ] && args+=(--ro-bind /opt /opt)
# Ubuntu's /etc/resolv.conf is a symlink into /run/systemd/resolve, which the /run tmpfs above
# would hide (no DNS inside: "Could not resolve host"). Show that folder read-only.
[ -d /run/systemd/resolve ] && args+=(--ro-bind /run/systemd/resolve /run/systemd/resolve)
for dev in /dev/nvidia* /dev/dri; do [ -e "$dev" ] && args+=(--dev-bind "$dev" "$dev"); done

PY312="$("$REAL_HOME/.local/bin/uv" python find 3.12)"
[ "$#" -gt 0 ] || set -- /bin/bash -l
# ASPIRE's skill docs run their scripts with `python3`; inside the jail it is uv's 3.12. AGENTS.md
# (real-robot rules) is replaced by an empty file: the Quick Start prompt forbids it, but Claude Code
# loads it on its own.
ln -sfn "$PY312" "$PRIVATE_HOME/.local/bin/python3"
ln -sfn "$PY312" "$PRIVATE_HOME/.local/bin/python"
: > "$SETUP/empty-AGENTS.md"
# ENABLE_CLAUDEAI_MCP_SERVERS=false keeps the account's claude.ai connectors off; settings.json in
# the private home also sets disableClaudeAiConnectors and turns off plugin and skill sync.
# The login token (~/.claude/.credentials.json) is kept from AI-written code by the second layer:
# CLAUDE_CODE_SHELL_PREFIX runs every Bash command Claude Code starts through aspire-inner, which
# hides ~/.claude. CLAUDE_CODE_SUBPROCESS_ENV_SCRUB is deliberately not set: it forces Claude Code
# into its default permission mode, and env -i leaves no secrets to strip.
# GIT_CONFIG_* settings beat every git config file, so git anywhere in the jail ignores fsmonitor
# commands, hooks and submodules that AI-written code could plant.
exec env -i HOME="$REAL_HOME" USER="$USER" LOGNAME="$USER" SHELL=/bin/bash \
  TERM="${TERM:-xterm-256color}" LANG="${LANG:-C.UTF-8}" TMPDIR=/tmp DISABLE_AUTOUPDATER=1 CLAUDE_CODE_EFFORT_LEVEL=max ENABLE_CLAUDEAI_MCP_SERVERS=false CAP_HARNESS_PYTHON="$PY312" \
  CLAUDE_CODE_SHELL_PREFIX=/run/aspire/aspire-inner CAP_HARNESS_PROFILE=rtx4090 \
  GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null GIT_CONFIG_KEY_2=diff.ignoreSubmodules GIT_CONFIG_VALUE_2=all \
  PATH="$REAL_HOME/.local/bin:/run/aspire:/usr/local/bin:/usr/bin:/usr/sbin" \
  /usr/bin/bwrap "${args[@]}" "$@"
