#!/usr/bin/env bash
# Phase 4c, step 1: create the Google Cloud L4 machine for ASPIRE.
# Usage: PROJECT=<project-id> KEY_PUB=~/.ssh/aspire_gcp.pub [SSH_USER=aspire] [NAME=aspire-l4] create_vm.sh
# - g2-standard-16: 1 NVIDIA L4 (24 GB, Ada sm_89, ASPIRE's rtx4090 profile), 16 vCPUs, 64 GB RAM.
# - Deep Learning VM image with NVIDIA driver 580 preinstalled; 200 GB balanced disk.
# - No service account: AI-written code on the machine can't act on the project.
# - L4 capacity is often exhausted, so zones are tried in turn.
# - SSH: one key in this instance's metadata, with the project's own keys blocked. (Where your
#   account can use OS Login on the project, that works too.)
set -euo pipefail
: "${PROJECT:?set PROJECT to your Google Cloud project id}"
: "${KEY_PUB:?set KEY_PUB to the public key for SSH, e.g. ~/.ssh/aspire_gcp.pub}"
NAME="${NAME:-aspire-l4}"
SSH_USER="${SSH_USER:-aspire}"
ZONES="${ZONES:-us-east4-a us-east4-c us-east1-b us-east1-c us-east1-d us-central1-a us-central1-b us-central1-c us-west1-a us-west1-b us-west4-a europe-west4-a europe-west4-b europe-west4-c europe-west1-b europe-west1-c}"

created=""
for zone in $ZONES; do
  if out=$(gcloud compute instances create "$NAME" --project "$PROJECT" --zone "$zone" \
      --machine-type g2-standard-16 --maintenance-policy TERMINATE \
      --image-family common-cu129-ubuntu-2204-nvidia-580 --image-project deeplearning-platform-release \
      --boot-disk-size 200GB --boot-disk-type pd-balanced \
      --no-service-account --no-scopes \
      --metadata enable-oslogin=FALSE,block-project-ssh-keys=TRUE,install-nvidia-driver=True \
      --labels purpose=aspire 2>&1); then
    created="$zone"; echo "$out" | tail -2; break
  fi
  if echo "$out" | grep -qE "ZONE_RESOURCE_POOL_EXHAUSTED|STOCKOUT|does not have enough resources"; then
    echo "$zone: no L4 capacity, trying the next zone"; continue
  fi
  echo "$out" >&2; exit 1
done
[ -n "$created" ] || { echo "no zone had capacity; try again later or add zones to ZONES" >&2; exit 1; }

keyfile=$(mktemp)
printf '%s:%s\n' "$SSH_USER" "$(cat "$KEY_PUB")" > "$keyfile"
gcloud compute instances add-metadata "$NAME" --project "$PROJECT" --zone "$created" --metadata-from-file ssh-keys="$keyfile"
rm -f "$keyfile"
ip=$(gcloud compute instances describe "$NAME" --project "$PROJECT" --zone "$created" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
echo "created $NAME in $created; ssh -i ${KEY_PUB%.pub} $SSH_USER@$ip"
echo "stop it when idle: gcloud compute instances stop $NAME --project $PROJECT --zone $created"
