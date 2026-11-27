#!/usr/bin/env bash
# Phase 4c, step 2: prepare a fresh Google Cloud L4 machine for ASPIRE.
# Image: Google's Deep Learning VM `common-cu129-ubuntu-2204-nvidia-580` (Ubuntu 22.04, NVIDIA
# driver 580 preinstalled). Installs system packages, uv with Python 3.12, Claude Code, the fork,
# and the folders the sandbox expects. Run as the login user, before any AI-written code exists on
# the machine; everything after this runs inside the sandbox (aspire-sandbox.sh).
set -euo pipefail
FORK_URL="${FORK_URL:-https://github.com/NickTrinh/ASPIRE.git}"
BRANCH="${BRANCH:-gcp-l4}"

sudo apt-get update -qq
# bubblewrap: the sandbox; libegl1/libgl1/libglvnd0: MuJoCo offscreen rendering (docs/libero-pro.md);
# build-essential: cuRobo compiles CUDA extensions during its bootstrap.
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  bubblewrap tmux git build-essential libegl1 libgl1 libglvnd0 curl ca-certificates
# X11 client libraries: Contact-GraspNet imports pyrender, whose pyglet import needs libXrender
# even headless ("'NoneType' object has no attribute 'XRenderFindVisualFormat'" without it).
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  libx11-6 libxext6 libxrender1 libxi6 libxfixes3 libxcursor1 libxinerama1 libxrandr2 \
  libxxf86vm1 libglu1-mesa libsm6 libice6
# The image installs the driver's compute-only packages (libnvidia-compute-580-server), so EGL falls
# back to Mesa and MuJoCo fails with "Cannot initialize a EGL device display". Add the NVIDIA GL/EGL
# libraries at exactly the driver's version.
DRIVER_PKG_VERSION="$(dpkg-query -W -f='${Version}' libnvidia-compute-580-server)"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "libnvidia-gl-580-server=$DRIVER_PKG_VERSION"

# uv (every bootstrap requires it, docs/host-setup.md) and the Python 3.12 the scripts run.
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv python install 3.12

# Claude Code, native installer. The jail binds its versions folder read-only.
curl -fsSL https://claude.ai/install.sh | bash

# The fork, on the branch with the empty skill library.
[ -d "$HOME/ASPIRE/.git" ] || git clone --branch "$BRANCH" "$FORK_URL" "$HOME/ASPIRE"

# The inner sandbox layer binds Claude Code's project settings files read-only, so they must exist.
mkdir -p "$HOME/ASPIRE/.claude"
for f in settings.json settings.local.json; do
  [ -e "$HOME/ASPIRE/.claude/$f" ] || echo '{}' > "$HOME/ASPIRE/.claude/$f"
done
grep -qx '.claude/settings.json' "$HOME/ASPIRE/.git/info/exclude" 2>/dev/null ||
  printf '.claude/settings.json\n.claude/settings.local.json\n' >> "$HOME/ASPIRE/.git/info/exclude"

# The jail's private home, with the same Claude Code settings as on node002. The bypass warning is
# accepted by a person in a live session; Claude Code then records that itself.
# .cache and .nv must exist: the inner sandbox layer keeps them writable only if they do.
mkdir -p "$HOME/aspire-home/.claude" "$HOME/aspire-home/.cache" "$HOME/aspire-home/.nv" "$HOME/aspire-setup/logs"
[ -e "$HOME/aspire-home/.claude/settings.json" ] || cat > "$HOME/aspire-home/.claude/settings.json" <<'JSON'
{
  "syncClaudeAiSkills": false,
  "syncClaudeAiPlugins": false,
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
  "model": "claude-opus-4-6",
  "disableClaudeAiConnectors": true,
  "autoMemoryEnabled": false,
  "theme": "dark"
}
JSON
echo "setup_vm done: uv $(uv --version | cut -d' ' -f2), python $(uv python find 3.12), claude $($HOME/.local/bin/claude --version 2>/dev/null | head -1)"
