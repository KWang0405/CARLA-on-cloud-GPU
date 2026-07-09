#!/usr/bin/env bash
# Install the NVIDIA graphics/Vulkan USERSPACE only, matching the running driver,
# WITHOUT touching the kernel module (the cloud provider owns that).
#
# Usage:
#   ./install_graphics_userspace.sh                # auto-detect running driver version
#   ./install_graphics_userspace.sh 580.105.08     # pin an explicit version
#
# Why: cloud GPU images often ship compute-only NVIDIA userspace (CUDA works,
# Vulkan does not). CARLA needs the Vulkan ICD. Adding userspace at the EXACT
# running version, with --no-kernel-module, makes hardware Vulkan appear without
# rebuilding the kernel module (which would break the instance).

set -euo pipefail

VER="${1:-$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1 | tr -d '[:space:]')}"
if [[ -z "${VER}" ]]; then
  echo "ERROR: could not determine NVIDIA driver version. Pass it explicitly, e.g.:" >&2
  echo "  $0 580.105.08" >&2
  exit 1
fi

RUN="NVIDIA-Linux-x86_64-${VER}.run"
URL="https://us.download.nvidia.com/XFree86/Linux-x86_64/${VER}/${RUN}"

echo "==> Target driver userspace version: ${VER}"
echo "==> Downloading ${URL}"
cd /tmp
if [[ ! -f "${RUN}" ]]; then
  wget -q --show-progress "${URL}" -O "${RUN}"
fi
chmod +x "${RUN}"

echo "==> Installing USERSPACE ONLY (kernel module left untouched)"
# --no-kernel-module      : do not build/replace the kernel module (provider owns it)
# --no-questions/--silent : unattended
# --ui=none               : no curses UI
sudo ./"${RUN}" \
  --no-kernel-module \
  --no-questions \
  --ui=none \
  --silent \
  --install-libglvnd \
  || {
    echo "ERROR: install failed. The MOST common cause is a version mismatch between" >&2
    echo "the userspace you're installing and the running kernel module." >&2
    echo "Running kernel module version:" >&2
    cat /proc/driver/nvidia/version 2>/dev/null || true
    exit 1
  }

echo "==> Done. Verify with: ./verify_vulkan.sh"
