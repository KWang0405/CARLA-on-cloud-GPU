#!/usr/bin/env bash
# Confirm hardware Vulkan sees the NVIDIA GPU (not just software llvmpipe).
set -uo pipefail

echo "==> nvidia-smi driver version:"
nvidia-smi --query-gpu=driver_version,name --format=csv,noheader || true
echo

if ! command -v vulkaninfo >/dev/null 2>&1; then
  echo "vulkaninfo not found. Install the Vulkan tools:"
  echo "  sudo apt-get update && sudo apt-get install -y vulkan-tools libvulkan1"
  exit 1
fi

echo "==> Vulkan devices enumerated:"
DEVS="$(vulkaninfo 2>/dev/null | grep -i deviceName || true)"
echo "${DEVS:-<none>}"
echo

if echo "${DEVS}" | grep -qiE 'nvidia|a10|a100|rtx|tesla|h100|l4|l40'; then
  echo "OK: hardware Vulkan sees the NVIDIA GPU. CARLA can render on the GPU."
  exit 0
elif echo "${DEVS}" | grep -qi 'llvmpipe'; then
  echo "PROBLEM: only llvmpipe (CPU software rasterizer) is visible."
  echo "         CARLA will be far too slow. Run ./install_graphics_userspace.sh"
  exit 2
else
  echo "PROBLEM: no Vulkan device enumerated at all."
  echo "         Run ./install_graphics_userspace.sh, then re-run this script."
  exit 2
fi
