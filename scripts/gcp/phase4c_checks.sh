#!/bin/bash
# Phase 4c checks on the Google Cloud L4, run inside both sandbox layers:
#   ~/aspire-setup/aspire-sandbox.sh /run/aspire/aspire-inner 'bash ~/phase4c_checks.sh'
# (this file lives in the private home). Needs the four services running (start_providers.sh).
set -u
cd ~/ASPIRE && source .venv-libero/bin/activate
export LIBERO_CONFIG_PATH="$PWD/.libero" TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD=1 MUJOCO_GL=egl PYOPENGL_PLATFORM=egl \
  EGL_PLATFORM=device CUDA_VISIBLE_DEVICES=0 MUJOCO_EGL_DEVICE_ID=0 MPLCONFIGDIR=/tmp/mpl
OUT=validation-artifacts/phase4c
mkdir -p "$OUT"

echo "== doctor with all four services"
cap-harness doctor --reset --providers sam3,contact_graspnet,pyroki,curobo --output "$OUT/doctor.json" > "$OUT/doctor.log" 2>&1
echo "doctor exit $?"; grep -E "^(PASS|FAIL|WARN)" "$OUT/doctor.log"

run() {  # run <label> <suite> <task> <program>
  cap-harness run --benchmark libero-pro --suite "$2" --task-id "$3" --seed 1 --program "$4" \
    --output-root "$OUT/$1" --max-steps 2000 --camera-width 800 --camera-height 512 > "$OUT/$1.log" 2>&1
  grep -E "^run:|program_ok=" "$OUT/$1.log" | tail -2
}
echo "== object-swap smoke example, seed 1, twice"
run smoke_a libero_object_swap 0 examples/libero/object_swap_seed1.py
run smoke_b libero_object_swap 0 examples/libero/object_swap_seed1.py
a=$(ls -d "$OUT"/smoke_a/libero-pro/*/*/0001/run-* | tail -1); b=$(ls -d "$OUT"/smoke_b/libero-pro/*/*/0001/run-* | tail -1)
if cmp -s "$a/episode/steps.jsonl" "$b/episode/steps.jsonl"; then echo "per-step records: byte-identical"; else echo "per-step records: DIFFER"; fi
echo "call records differing (ignoring durations): $(diff -rq "$a/trace/calls" "$b/trace/calls" | wc -l) files differ before filtering"

echo "== cuRobo smoke example, seed 1"
run curobo libero_object_swap 0 examples/libero/object_swap_curobo_seed1.py
c=$(ls -d "$OUT"/curobo/libero-pro/*/*/0001/run-* | tail -1)
for f in "$c"/trace/calls/*curobo*; do echo "  $(basename "$f"): $(grep -oE "\"ok\": (true|false)" "$f/output.json" | head -1)"; done
