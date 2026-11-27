#!/usr/bin/env bash
# Phase 4c, step 2: build ASPIRE's environments on the Google Cloud L4 machine, inside the jail:
#   ~/aspire-setup/aspire-sandbox.sh ~/aspire-setup/run_bootstrap.sh   (from a tmux pane)
# Usage: run_bootstrap.sh [providers-csv]; set SKIP_LIBERO=1 to skip the simulator environment.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
cd "$HOME/ASPIRE"
export CAP_HARNESS_PROFILE=rtx4090   # the authors' profile for one 24 GB Ada GPU: the L4
export CAP_HARNESS_PYTHON="$(uv python find 3.12)"
export CAP_HARNESS_CUROBO_GPU=0      # cuRobo's post-build check defaults to GPU 3; this machine has GPU 0
PROVIDERS="${1:-sam3,contact_graspnet,pyroki,curobo}"
ts=$(date +%Y%m%d-%H%M%S)
log="$HOME/ASPIRE/validation-artifacts/bootstrap-$ts.log"
mkdir -p "$HOME/ASPIRE/validation-artifacts"
{
  echo "== host $(hostname), gcc $(gcc -dumpversion), providers $PROVIDERS, $(date)"
  if [ "${SKIP_LIBERO:-0}" != 1 ]; then echo "== bootstrap_libero"; scripts/bootstrap_libero.sh; fi
  echo "== bootstrap_providers"
  scripts/bootstrap_providers.sh --providers "$PROVIDERS" --profile rtx4090
  echo "== done $(date)"
} 2>&1 | tee "$log"
