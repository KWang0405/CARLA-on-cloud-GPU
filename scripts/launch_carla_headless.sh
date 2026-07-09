#!/usr/bin/env bash
# Launch CARLA headless on the GPU (hardware Vulkan), no display required.
#
# Usage:
#   ./launch_carla_headless.sh /path/to/CARLA_0.9.15 [RPC_PORT] [GPU_INDEX]
#
# Defaults: RPC_PORT=22000, GPU_INDEX=0

set -uo pipefail

CARLA_ROOT="${1:?path to CARLA root (dir containing CarlaUE4.sh) required}"
PORT="${2:-22000}"
GPU="${3:-0}"

LAUNCH="${CARLA_ROOT}/CarlaUE4.sh"
if [[ ! -x "${LAUNCH}" && ! -f "${LAUNCH}" ]]; then
  echo "ERROR: ${LAUNCH} not found." >&2
  exit 1
fi

# Clean up any stale server on this port (|| true so an empty match doesn't
# abort the script; note we are intentionally NOT under `set -e`).
pkill -f "carla-rpc-port=${PORT}" || true
sleep 2

echo "==> Launching CARLA headless: port=${PORT} gpu=${GPU}"
# -RenderOffScreen : headless, no X display
# -nosound         : no audio device needed
# -graphicsadapter : pin GPU index (hardware Vulkan device)
"${LAUNCH}" \
  -RenderOffScreen \
  -nosound \
  -carla-rpc-port="${PORT}" \
  -graphicsadapter="${GPU}" &

CARLA_PID=$!
echo "==> CARLA pid=${CARLA_PID}; waiting for RPC port ${PORT}..."

for i in $(seq 1 60); do
  if ss -ltn 2>/dev/null | grep -q ":${PORT}\b"; then
    echo "==> OK: RPC port ${PORT} is open. CARLA is up."
    echo "    Confirm GPU render: nvidia-smi should show CarlaUE4 holding ~5-6GB VRAM."
    exit 0
  fi
  sleep 5
done

echo "ERROR: RPC port ${PORT} never opened within timeout." >&2
echo "       If CPU is pinned at 100% and VRAM ~0, you are on llvmpipe — run verify_vulkan.sh." >&2
exit 1
