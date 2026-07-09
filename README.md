# Running CARLA headless on a cloud GPU (the Vulkan fix)

CARLA 0.9.14+ renders with **Vulkan**. Most cloud GPU instances (Lambda, RunPod,
GCP, ...) ship with the NVIDIA **compute** stack (CUDA works, `nvidia-smi` works) but
**not** the **graphics / Vulkan userspace** libraries. So CARLA's renderer fails at
Vulkan ICD negotiation and the server never comes up — even though the GPU is clearly
present and healthy.

This is the one-page fix that got CARLA 0.9.15 booting headless with **hardware**
Vulkan on a **Lambda Cloud A10** VM. The same approach applies to any cloud GPU box
where `nvidia-smi` works but `vulkaninfo` can't see the GPU.

---

## Symptom

`nvidia-smi` is happy, but CARLA hangs at startup or exits immediately, and one of these
is true:

```text
# vulkaninfo can't find the NVIDIA GPU:
vulkaninfo | grep deviceName
# -> only "llvmpipe (LLVM ...)"  — software rasterizer, no NVIDIA device

# or CARLA's log shows:
VK_ERROR_INITIALIZATION_FAILED
VK_ERROR_INCOMPATIBLE_DRIVER
```

If Vulkan only enumerates **`llvmpipe`** (Mesa's CPU rasterizer), CARLA *can* fall back
to it — but software rendering is far too slow for closed-loop evaluation (it burns
minutes compiling shaders per frame and never opens the RPC port in practice). You need
the real hardware path.

## Root cause

The container / VM image installed the NVIDIA driver with **compute-only** userspace.
The Vulkan ICD (`libGLX_nvidia`, `libEGL_nvidia`, `nvidia_icd.json`, ...) that CARLA
needs is missing. On containers this is often because `NVIDIA_DRIVER_CAPABILITIES` was
left at its default (`compute,utility`) instead of `all` / `...,graphics`, so the
NVIDIA container runtime never injected the graphics libraries.

## The fix

**Install the matching NVIDIA graphics userspace with `--no-kernel-module`.** The trick
is to add *only the userspace libraries*, at the **exact version already loaded**, and
to **not** touch the kernel module (the cloud provider owns that — rebuilding it breaks
the instance).

1. **Read the exact driver version that is already running:**

   ```bash
   nvidia-smi --query-gpu=driver_version --format=csv,noheader
   # e.g. 580.105.08
   ```

2. **Download that exact `.run` installer from NVIDIA and install userspace only:**

   ```bash
   ./scripts/install_graphics_userspace.sh            # auto-detects the running version
   # or pin explicitly:
   ./scripts/install_graphics_userspace.sh 580.105.08
   ```

   The load-bearing flags are `--no-kernel-module` (leave the provider's kernel module
   alone) and `--no-questions --ui=none --silent` (unattended). The version **must**
   match the running kernel module — a mismatch fails at library load.

3. **Verify hardware Vulkan is now visible:**

   ```bash
   ./scripts/verify_vulkan.sh
   # expect: deviceName = NVIDIA A10  (NOT llvmpipe)
   ```

4. **Launch CARLA headless on the GPU:**

   ```bash
   ./scripts/launch_carla_headless.sh /path/to/CARLA_0.9.15 22000
   ```

   Key flags: `-RenderOffScreen` (no display needed), `-nosound`, an explicit
   `-carla-rpc-port`, and `-graphicsadapter=0` to pin GPU 0.

## How to confirm it's really on the GPU (not silently on CPU)

The failure mode that wastes the most time is *thinking* you fixed it while CARLA
quietly fell back to `llvmpipe`. Check both:

```bash
# 1) CARLA's RPC port is open (server actually came up)
ss -ltnp | grep 22000

# 2) the GPU is doing render work while CARLA runs
nvidia-smi          # expect a CarlaUE4 process, ~5-6 GB VRAM, high GPU-util
```

A hardware-Vulkan CARLA server shows a `CarlaUE4-Linux-Shipping` process holding
several GB of VRAM at high utilization. If VRAM use is ~0 and CPU is pinned at 100%,
you are still on `llvmpipe` — recheck step 3.

---

## Client-side gotcha (Python API)

CARLA's bundled `.egg` client targets an older Python. The 0.9.15 egg won't import
under a system Python 3.10+. Use a **dedicated conda env on Python 3.8 and install the
matching `carla` wheel from PyPI** instead of the egg:

```bash
conda create -n carla-client python=3.8 -y
conda activate carla-client
pip install carla==0.9.15
python -c "import carla; print(carla.__version__)"
```

## Notes / other pitfalls

- **Persistent vs ephemeral storage.** On some cloud VMs the home directory is
  ephemeral and only a mounted network volume survives a stop/restart. Install CARLA,
  conda, and checkpoints on the **persistent mount**, not `~`.
- **`set -e` and `pkill`.** In job wrappers, a cleanup `pkill -f CarlaUE4` returns
  non-zero when there's nothing to kill, which aborts the whole script under `set -e`.
  Append `|| true`.
- **Orphaned servers.** A job that hits its wall-clock cap can leave an in-flight
  CARLA + evaluator orphaned. Kill by PID (`ps -eo pid,etimes,cmd | grep CarlaUE4`),
  not a blanket `pkill`, so you don't also kill a fresh run.
- **Container route (if you control the runtime).** If you're on a container platform
  rather than a bare VM, the cleaner fix is to launch with
  `NVIDIA_DRIVER_CAPABILITIES=all` (or `compute,utility,graphics`) and
  `NVIDIA_VISIBLE_DEVICES=all` so the NVIDIA container runtime injects the graphics
  libraries for you — no manual userspace install needed. The `--no-kernel-module`
  install above is the fix for when you *can't* change the runtime (bare VM, or a
  platform that ignores the capability flag).

---

*Written while reproducing a closed-loop autonomous-driving VLA (SimLingo / CARLA
0.9.15) headless on a Lambda A10. Verified path: hardware Vulkan render + closed-loop
leaderboard eval, ~10 min/route on an A10.*
