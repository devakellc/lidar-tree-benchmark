#!/bin/bash
# Container entry for the ForestMamba arm. run_docker_arm passes no environment
# into the container, so every path arrives positionally (input and output
# first, then the `extra` arguments) and is identity-mounted:
#   bash fm_entry.sh <in_laz> <out_laz> <ckpt> <workspace> <driver> [<seed>]
# The workspace is a copy of the pinned ForestMamba checkout; the driver stages
# data/ and work_dirs/ inside it.
set -euo pipefail
in_laz="$1"; out_laz="$2"; ckpt="$3"; workspace="$4"; driver="$5"; seed="${6:-0}"
cd "$workspace"
export WANDB_MODE=disabled PYTHONHASHSEED=0
exec python "$driver" "$in_laz" "$out_laz" "$ckpt" "$seed"
