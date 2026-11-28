# Running ASPIRE on a Google Cloud L4

A tested recipe for one NVIDIA L4 on Google Compute Engine. The L4 is a 24 GB Ada GPU (sm_89),
which is what ASPIRE's own `rtx4090` profile describes ("all providers share GPU 0"), so the
harness itself doesn't change. The scripts are in [`scripts/gcp/`](../scripts/gcp/). This setup
was used for a ten-task `libero_goal_swap` iterative-debugging campaign with Claude Code
(`claude-opus-4-6`, max effort) starting from an empty skill library (this branch is
`paper-empty-library` plus this recipe).

The agent runs inside two bubblewrap sandbox layers. The outer one gives it a private home and
the repository and hides the rest of the machine; the inner one (every shell command Claude Code
runs, and every program the agent writes) also hides the Claude login. ASPIRE executes
model-written Python with full import access, so keep both layers.

## 1. Create the machine

```bash
PROJECT=<project-id> KEY_PUB=~/.ssh/aspire_gcp.pub scripts/gcp/create_vm.sh
```

`g2-standard-16` (1 L4, 16 vCPUs, 64 GB RAM), Google's Deep Learning image
`common-cu129-ubuntu-2204-nvidia-580` (NVIDIA driver 580 preinstalled), a 200 GB disk, and **no
service account**, so code on the machine can't act on your project. L4s are often out of stock;
the script tries a list of zones. Stop the machine whenever nothing runs (the disk is still
billed while it is stopped).

## 2. Set it up

Copy `scripts/gcp/` to `~/aspire-setup/` on the machine and run, as the login user:

```bash
~/aspire-setup/setup_vm.sh       # packages, uv + Python 3.12, Claude Code, this fork
~/aspire-setup/run_bootstrap.sh  # all environments, profile rtx4090 (a few minutes)
```

Run the bootstrap before any AI-written code exists on the machine; everything after it runs
inside the sandbox.

## 3. Sign in, inside the sandbox

```bash
tmux new-session -s aspire-shell ~/aspire-setup/aspire-sandbox.sh
```

In that shell, store a Hugging Face token for the gated SAM3 weights (request access first), then
log in to Claude Code and accept its bypass-permissions warning yourself:

```bash
mkdir -p ~/.cache/huggingface && read -rs -p "HF token: " t && printf %s "$t" > ~/.cache/huggingface/token && unset t
claude    # log in, accept the warning, then /exit
```

Start the services once (`~/aspire-setup/start_providers.sh`) so SAM3 downloads its weights,
then delete `~/aspire-home/.cache/huggingface/token`.

## 4. Check it

Copy `inner-tests.sh` and `phase4c_checks.sh` into `~/aspire-home/` and run them in both layers:

```bash
~/aspire-setup/aspire-sandbox.sh /run/aspire/aspire-inner 'bash ~/inner-tests.sh'
~/aspire-setup/aspire-sandbox.sh /run/aspire/aspire-inner 'bash ~/phase4c_checks.sh'
```

Expected: `~/.claude` empty and the protected paths read-only inside the inner layer; `doctor`
passing with all four services; the object-swap smoke example passing twice with byte-identical
per-step records; the cuRobo smoke example passing with its plans `ok`.

## 5. Run the agent

Put the campaign prompt in `~/aspire-home/phase5-prompt.txt` (see `phase5-prompt.txt`), then:

```bash
~/aspire-setup/start_agent.sh                                     # tmux session aspire-agent
tmux new-session -d -s aspire-resume ~/aspire-setup/aspire-resume.sh
```

`aspire-resume.sh` handles Claude usage limits (on a limited plan, a long campaign hits several):
when Claude Code's limit menu appears it picks "Wait here, then continue automatically" (never the
credits or upgrade options), and as a fallback it types `continue` only when the agent is idle and
shows a limit message.

## Problems this recipe already fixes

- **No EGL device display.** The image installs the driver's compute-only packages, so EGL falls
  back to Mesa and MuJoCo fails with "Cannot initialize a EGL device display". `setup_vm.sh`
  installs `libnvidia-gl-580-server` at the driver's exact version.
- **Contact-GraspNet crashes at import** (`'NoneType' object has no attribute
  'XRenderFindVisualFormat'`): pyrender's pyglet needs X11 client libraries even headless;
  `setup_vm.sh` installs them.
- **No DNS inside the sandbox.** Ubuntu's `/etc/resolv.conf` points into `/run/systemd/resolve`,
  which the sandbox's `/run` tmpfs would hide; `aspire-sandbox.sh` binds that folder read-only.
- **`~/.cache` read-only inside the inner layer** if it doesn't exist yet; `setup_vm.sh` creates it.
- **OS Login refused** in a project owned by another organization; `create_vm.sh` puts one SSH
  key in the instance's own metadata instead and blocks the project's keys.
