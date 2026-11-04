# Hardware inventory (phase 0)

Collected on 2026-10-08 over `ssh jetson`. Every value below lists the command that
produced it. Hardware constraints cited anywhere else in the project must come from
this file.

## Board and OS

| Item | Value | Source command |
|---|---|---|
| Hostname | `mgrad-desktop` | `hostname` |
| Device-tree model | `lanai-3636` | `tr -d '\0' < /proc/device-tree/model` |
| Device-tree compatible | `nvidia,p3509-0000+p3636-0001 nvidia,tegra186` | `tr '\0' ' ' < /proc/device-tree/compatible` |
| DTS source | `.../t18x/lanai/kernel-dts/tegra186-p3636-0001-p3509-0000-a01.dts` (NVIDIA reference carrier) | `strings /proc/device-tree/nvidia,dtsfilename` |
| Board IDs read by the bootloader | `3636-0003-301` (from the EEPROM at `/i2c@c250000:module@0x50`, i.e. the module) and `3636-0003-301-D`. **No carrier-board ID** was read, so the carrier is not identified by any EEPROM. It is not an NVIDIA reference carrier, and its exact model and cooling are not documented here | `ls /proc/device-tree/chosen/plugin-manager/ids`, `tr '\0' ' ' < .../ids/3636-0003-301` |
| OS | Ubuntu 18.04.6 LTS (bionic) | `cat /etc/os-release` |
| Kernel | `4.9.337-tegra` aarch64, built 2024-11-04 | `uname -a` |
| L4T | R32 revision 7.6 (`BOARD: t186ref`) | `cat /etc/nv_tegra_release` |
| L4T core package | `nvidia-l4t-core 32.7.6-20241104234601` | `dpkg -l nvidia-l4t-core` |
| JetPack meta-package | not installed (candidate `4.6.6-b24`) | `apt-cache policy nvidia-jetpack` |
| Default systemd target | `graphical.target` (gdm3, Xorg, compiz running) | `systemctl get-default`, `pgrep -a 'Xorg\|gdm3\|lightdm\|gnome-shell\|compiz'` |
| Uptime at inventory | 35 days | `uptime` |

## CPU

| Item | Value | Source command |
|---|---|---|
| Logical CPUs | 6 (0-5), all online | `lscpu`, `cat /sys/devices/system/cpu/online` |
| CPU 0, 3, 4, 5 | implementer `0x41` (ARM), part `0xd07` (Cortex-A57) | `grep -E 'processor\|CPU part\|CPU implementer' /proc/cpuinfo` |
| CPU 1, 2 | implementer `0x4e` (NVIDIA), part `0x003` (Denver; nvpmodel calls them `CPU_DENVER`) | same as above, plus `/etc/nvpmodel.conf` |
| Max frequency | 2035200 kHz on all 6 CPUs | `cat /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq` |
| Min frequency | 345.6 MHz | `lscpu` |
| ISA flags | `fp asimd evtstrm aes pmull sha1 sha2 crc32` (no `asimddp`, no `sve`, no `fphp`/`asimdhp`) | `lscpu` |
| L1d / L1i / L2 | 32K / 48K / 2048K (as reported by `lscpu`) | `lscpu` |
| **Kernel isolation** | `isolcpus=1-2` on the kernel command line | `cat /proc/cmdline` |
| Default affinity mask | `0x39` = CPUs 0, 3, 4, 5 | `taskset -p $$` |
| `nproc` | **4** (the isolated CPUs 1-2 are excluded) | `nproc` |

## Memory

| Item | Value | Source command |
|---|---|---|
| Physical RAM | 8220672K total, 7278528K available to the kernel | `dmesg \| grep 'Memory:'` |
| MemTotal | 8047900 kB (7859 MB in tegrastats) | `cat /proc/meminfo`, `tegrastats` |
| CPU/GPU sharing | unified: "Integrated GPU sharing Host Memory: Yes", GPU global memory 7859 MB | `deviceQuery` |
| CMA | 753664 kB reserved (CmaTotal), 719864 kB free | `grep Cma /proc/meminfo` |
| RAM used at idle (GUI running) | 1589 / 7859 MB | `timeout 3 tegrastats --interval 1000` |
| MemAvailable at idle | 6251900 kB | `cat /proc/meminfo` |
| Swap | 6 × 655 MB zram (lzo), 3930 MB total, no disk swap | `swapon --show`, `zramctl` |
| DRAM ECC | disabled | `dmesg \| grep dram-ecc` |
| **RAM with vs without desktop** (2026-10-17) | desktop running: tegrastats 2186 MB, MemAvailable 6489 MB. After `systemctl stop gdm3` alone: **unchanged** (2183 MB / 6492 MB), because the X11 session (Xorg, compiz, gnome-software, update-manager) survives the display manager. After `loginctl terminate-session <x11 session>` as well: **1665 MB / 7013 MB**, so the desktop costs **~520 MB**. Evolution data-server user services (calendar, address book) keep running afterwards | `tegrastats` (10 samples), `/proc/meminfo`, `pgrep -a`, `loginctl list-sessions` |
| Largest idle user-space RSS | gnome-software 450 MB, compiz 191 MB, update-manager 139 MB, evolution-calendar 2 × ~68 MB, dockerd 64 MB, deja-dup 51 MB | `ps -eo rss,comm --sort=-rss \| head` |

## GPU and CUDA

| Item | Value | Source command |
|---|---|---|
| GPU | "NVIDIA Tegra X2" (devfreq node `17000000.gp10b`) | `deviceQuery`, `ls /sys/devices/gpu.0/devfreq/` |
| **Compute capability** | **6.2** (→ `sm_62`) | `deviceQuery` |
| SMs / CUDA cores | 2 SMs × 128 = 256 cores | `deviceQuery` |
| L2 cache | 512 KB | `deviceQuery` |
| Shared memory / block | 48 KB | `deviceQuery` |
| Memory bus width | 128-bit | `deviceQuery` |
| GPU frequency steps | 114.75 to 1300.5 MHz, 13 steps (114750000 ... 1236750000 1300500000 Hz) | `cat /sys/devices/gpu.0/devfreq/17000000.gp10b/available_frequencies` |
| GPU frequency at idle | 114.75 MHz | `cat .../cur_freq` |
| CUDA toolkit | 10.2 (nvcc V10.2.300, SDK 10.2.460), `/usr/local/cuda -> cuda-10.2` | `nvcc --version`, `cat /usr/local/cuda/version.json` |
| CUDA driver / runtime | 10.2 / 10.2 | `deviceQuery` |
| cuBLAS | 10.2.3.300 (cublas + cublasLt) | `cat /usr/local/cuda/version.json`, `dpkg -l` |
| cuDNN | 8.2.1.32 (`libcudnn8`, `-dev`) | `dpkg -l \| grep cudnn`, `/usr/include/cudnn_version.h` |
| TensorRT | 8.2.1.9 (`libnvinfer8` 8.2.1, ONNX parser, Python bindings) | `dpkg -l \| grep -Ei 'tensorrt\|nvinfer'` |
| nvcc flags | does not support `--list-gpu-arch` | `nvcc --list-gpu-arch` |
| **nvcc C++ standard** | **max C++14**: `-std=c++17` → `nvcc fatal : Value 'c++17' is not defined for option 'std'` (same with `-ccbin g++` and `-ccbin g++-8`) | `nvcc -ccbin <cc> -std=c++17 -arch=sm_62 t.cu` (2026-10-15) |
| nvcc host compilers | `-ccbin g++` (7.5) and `-ccbin g++-8` (8.4) both build and run an `sm_62` kernel with `-std=c++14` | test kernel in a temp dir, built and run on the board (2026-10-15) |
| Mixed C++17 host + C++14 CUDA | works: `.cpp` built with `g++[-8] -std=c++17` (uses `std::string_view`), `.cu` built with `nvcc -std=c++14`, linked with `-lcudart`, runs correctly with both g++ 7.5 and g++-8 | same test (2026-10-15) |
| Nsight Compute | 2019.5.3.4; nvprof 10.2.300 | `cat /usr/local/cuda/version.json` |

`deviceQuery` was built from `/usr/local/cuda/samples/1_Utilities/deviceQuery` in a
temp directory on the board (`nvcc -I../../common/inc -o deviceQuery deviceQuery.cpp`),
then deleted.

## Toolchain

| Item | Value | Source command |
|---|---|---|
| gcc / g++ | 7.5.0 (`Ubuntu/Linaro 7.5.0-3ubuntu1~18.04`), the only version installed | `gcc --version`, `ls /usr/bin/gcc-* /usr/bin/g++-*` |
| Target triple | `aarch64-linux-gnu` | `gcc -dumpmachine` |
| clang | **not installed** | `clang --version` |
| CMake (system) | **not installed** | `cmake --version` |
| CMake (user-local) | 3.31.6, Kitware `cmake-3.31.6-linux-aarch64` in `~/.local/opt/`, symlinked into `~/.local/bin/` (installed 2026-10-08, tarball checked against Kitware's `cmake-3.31.6-SHA-256.txt`) | `~/.local/bin/cmake --version` |
| `~/.local/bin` on PATH | only in login shells (`bash -lc`), **not** in non-interactive `ssh jetson '...'` | `echo $PATH`, `bash -lc 'command -v cmake'` |
| gcc-8 / g++-8 | 8.4.0 (`8.4.0-1ubuntu1~18.04`), installed 2026-10-15; default `gcc`/`g++` remain 7.5.0 | `dpkg -l gcc-8 g++-8`, `gcc-8 --version`, `gcc --version` |
| `v4l-utils` | 1.14.2-1, installed 2026-10-15 | `dpkg -l v4l-utils` |
| Ninja | **not installed** | `ninja --version` |
| GNU Make | 4.1 | `make --version` |
| glibc | 2.27 (`2.27-3ubuntu1.6`) | `ldd --version` |
| Python | 3.6.9, pip 9.0.1 | `python3 --version`, `pip3 --version` |
| git | 2.17.1 | `git --version` |

## Storage

| Item | Value | Source command |
|---|---|---|
| Root filesystem | `/dev/nvme0n1p1`, ext4, 117G, **100G free** | `df -h`, `cat /proc/cmdline` (`root=/dev/nvme0n1p1`) |
| `~/lumen` | on the NVMe root | `df -h ~/lumen` |
| eMMC | `mmcblk0` 14.7G; `mmcblk0p1` (14G, 3.7G free) mounted at `/media/mgrad/1cb95ff2-...`, not the rootfs | `lsblk`, `df -h` |

## Power modes and clocks

| Item | Value | Source command |
|---|---|---|
| Current mode | **ID 0 `MAXN`** | `nvpmodel -q` |
| Default mode at boot | ID 3 (`< PM_CONFIG DEFAULT=3 >`) | `/etc/nvpmodel.conf` |
| EMC cap readout | fails without root (`Error opening /sys/kernel/nvpmodel_emc_cap/emc_iso_cap: 13`) | `nvpmodel -q` |
| Fan | "NVPM WARN: fan mode is not set!" | `nvpmodel -q` |
| `jetson_clocks --show` | collected 2026-10-15 by the user (sudo), output pasted into the session; values below. `jetson_clocks` itself had **not** been applied | `sudo jetson_clocks --show` |
| SoC / machine | `SOC family:tegra186  Machine:lanai-3636` | `sudo jetson_clocks --show` |
| CPU governor | `schedutil` on all 6 CPUs, MinFreq 345600, MaxFreq 2035200 (kHz) | `sudo jetson_clocks --show` |
| CPU current freq at the time | cpu0 960000, cpu1 345600, cpu2 345600, cpu3 652800, cpu4 806400, cpu5 1420800 (kHz) | `sudo jetson_clocks --show` |
| CPU idle states | A57 (cpu0, 3, 4, 5): `C1=1 c7=1`; Denver (cpu1, 2): `C1=1 c6=1 c7=1` | `sudo jetson_clocks --show` |
| GPU | MinFreq 114750000, MaxFreq 1300500000, CurrentFreq 114750000 (Hz) | `sudo jetson_clocks --show` |
| **EMC (memory clock)** | MinFreq 204000000, **MaxFreq 1600000000** (1600 MHz), CurrentFreq 1600000000, FreqOverride=0. In MAXN, the conf's `EMC MAX_FREQ 0` ("no cap") therefore means 1600 MHz, the same as the other modes' cap | `sudo jetson_clocks --show` |
| Fan | `PWM=0`. **Fan presence: unknown.** The user believes cooling is passive (a heatsink enclosure around the board), but is not sure, since this is not a standard NVIDIA carrier (2026-10-15). It **cannot be determined from software**: the `pwm-fan` driver is bound (DT node `status=okay`, from the reference-carrier DT), but `tach_enable=0` and `rpm_measured=0`, so no tachometer is read. `target_pwm=0`/`cur_pwm=0` are expected at idle anyway, since the fan curve (`thermal-fan-est`) only rises above 46 °C. `fan_profile=quiet`, `temp_control=1`, `pwm_cap=255`. PWM test on 2026-10-15 (`target_pwm` 255 for 5 s, then back to 0): **inconclusive**, nobody was near the board to hear it. State verified restored afterwards (`target_pwm=0`, `cur_pwm=0`, `temp_control=1`) | `sudo jetson_clocks --show`, `cat /sys/devices/pwm-fan/{target_pwm,cur_pwm,rpm_measured,tach_enable,fan_profile,temp_control,pwm_cap}`, `/proc/device-tree/pwm-fan/status` |
| tegrastats | works without root; reports RAM, SWAP, CPU, EMC_FREQ, GR3D_FREQ and temperatures. **No power rails (VDD_*) in its output.** | `timeout 3 tegrastats --interval 1000` |

### Thermal zones (2026-10-15, idle)

Source: `/sys/class/thermal/thermal_zone*/{type,temp,policy,trip_point_*}` and
`/sys/class/thermal/cooling_device*/{type,cur_state,max_state}`, readable without root.

| Zone | Idle temp | Passive trip (throttle) | Critical trip | Other trips | Policy |
|---|---|---|---|---|---|
| BCPU-therm | 30.0 °C | 95.5 °C | 100.5 °C | — | step_wise |
| MCPU-therm | 30.0 °C | 95.5 °C | 100.5 °C | — | step_wise |
| GPU-therm | 28.5 °C | 95.5 °C | 100.5 °C | active: −40, −5, 30, 65, 100 °C | step_wise |
| PLL-therm | 29.5 °C | — | — | none | step_wise |
| PMIC-Die | 50.0 °C | — | — | active: 120 °C | step_wise |
| thermal-fan-est | 29.1 °C | — | — | active: 0, 46, 60, 68, 76, 140-180 °C (fan curve; whether a fan is wired to it is unknown) | pid_thermal_gov |

Cooling devices (cur/max state at idle): `cpu-balanced` 0/66, `gpu-balanced` 0/52,
`skin-balanced` 0/66, `emergency-balanced` 0/1, the three per-domain `bcpu-/mcpu-/gpu-throttle-*` devices 0/1,
`pwm-fan` 0/10, `tegra-eqos` 3/5.

Modes defined in `/etc/nvpmodel.conf` (`-1` = no cap, `EMC MAX_FREQ 0` = no cap):

| ID | Name | Online CPUs | A57 max | Denver max | GPU max | EMC max |
|---|---|---|---|---|---|---|
| 0 | MAXN | 0-5 | no cap | no cap | no cap | no cap |
| 1 | MAXQ | 0, 3-5 | 1.2 GHz | offline | 850 MHz | 1.6 GHz |
| 2 | MAXP_CORE_ALL | 0-5 | 1.4 GHz | 1.4 GHz | 1120 MHz | 1.6 GHz |
| 3 | MAXP_CORE_ARM | 0, 3-5 | 2.0 GHz | offline | 1120 MHz | 1.6 GHz |

## Video / GStreamer

| Item | Value | Source command |
|---|---|---|
| GStreamer | 1.14.5 | `gst-inspect-1.0 --version` |
| Sources | `v4l2src`, `nvv4l2camerasrc`, `nvarguscamerasrc`, `rtspsrc` | `gst-inspect-1.0 \| grep ...` |
| Hardware decoders | `nvv4l2decoder`, `nvjpegdec` | same |
| Hardware converter | `nvvidconv` | same |
| Software decoders | `jpegdec`, `avdec_h264` | same |
| Sink | `appsink` | same |

## USB camera

Detected on 2026-10-15 09:28 (board time). The formats were first read with
`gst-device-monitor-1.0` and with direct V4L2 ioctls (`VIDIOC_QUERYCAP`,
`VIDIOC_ENUM_FMT`, `VIDIOC_ENUM_FRAMESIZES`, `VIDIOC_ENUM_FRAMEINTERVALS`) from a short
`python3` snippet. After `v4l-utils` was installed, `v4l2-ctl --list-devices` and
`v4l2-ctl -d /dev/videoN --list-formats-ext` confirmed the same results.

### Device

| Item | Value | Source command |
|---|---|---|
| Camera | Cisco Desk Camera 4K, USB ID `05a6:0023`, UVC 1.10 | `lsusb`, `dmesg \| grep uvcvideo` |
| USB link | **high-speed, 480 Mbit/s**, on `usb1-port2` (bus 1, USB 2.0 root hub); device reports USB version 2.10, so a USB 3.0 port would not change the link | `lsusb -t`, `cat /sys/bus/usb/devices/1-2/speed /sys/bus/usb/devices/1-2/version` |
| Declared power | `bMaxPower` 500 mA | `cat /sys/bus/usb/devices/1-2/bMaxPower` |
| Interfaces | 3 × Video (`uvcvideo`), 2 × Audio (`snd-usb-audio`), 1 × HID (`usbhid`) | `lsusb -t` |
| `/dev/video0` | main capture node: `VIDEO_CAPTURE`, `STREAMING` (`device_caps=0x04200001`), group `video` | V4L2 `VIDIOC_QUERYCAP`, `ls -l /dev/video*` |
| `/dev/video1` | second capture node, same caps, but its only format is a GUID unknown to this kernel's uvcvideo (`00000032-0002-0010-8000-00aa00389b71`) at 576x432@15 and 640x480@15. **Not usable** for lumen | V4L2 `VIDIOC_ENUM_FMT`, `dmesg \| grep 'Unknown video format'` |
| Kernel warnings | `Entity type for entity ... was not initialized!` (×6), `Unable to create debugfs 1-10 directory`; capture works anyway | `dmesg \| grep uvcvideo` |

### Formats on `/dev/video0`

Every size offers exactly 30 and 15 fps.

| Format | Resolutions |
|---|---|
| MJPG (Motion-JPEG) | 4096x2160, 3840x2160, 2560x1440, 1920x1080, **1280x720**, 896x480, 640x480, 640x360, 512x288, 448x240, 320x180, 256x144 |
| YUYV 4:2:2 | 896x480, 640x480, 640x360, 512x288, 448x240, 320x180, 256x144 |
| NV12 4:2:0 | 896x480, 640x480, 640x360, 512x288, 448x240, 320x180, 256x144 |

- **Above 896x480, only MJPEG is offered**, so 720p and up always need a JPEG decode.
- Current format at the time of reading: MJPG 1280x720 at 30/1 fps, `Size Image`
  1843200, colorspace sRGB, full range. Source: `v4l2-ctl -d /dev/video0 --all`.
- The camera's MJPEG frames are **4:2:2** (luma sampling 2×1 in the SOF0 header of a
  1280x720 frame). Source: parsing the JPEG SOF0 marker with `python3`.

### Controls on `/dev/video0`

Source: `v4l2-ctl -d /dev/video0 --list-ctrls-menus` (2026-10-15). Nothing has been
changed by lumen.

| Control | Range | Default | Current |
|---|---|---|---|
| brightness | 0-255 | 143 | 143 |
| contrast | 0-255 | 110 | **128** |
| saturation | 0-255 | 110 | 110 |
| sharpness | 0-255 | 80 | **128** |
| white_balance_temperature_auto | bool | 1 | 1 |
| white_balance_temperature | 2000-7500 K, step 10 | 4000 | 4000 (inactive while auto) |
| power_line_frequency | 0 Disabled, 1 50 Hz, 2 60 Hz | 0 | 0 |
| exposure_auto | 1 Manual, 3 Aperture Priority | 3 | 3 |
| exposure_absolute | 1-333 | 333 | 333 (inactive while auto) |
| exposure_auto_priority | bool | 0 | 0 (frame rate is not lowered for exposure) |
| focus_auto | bool | 1 | 1 |
| focus_absolute | 0-255 | 0 | 0 (inactive while auto) |
| zoom_absolute | 100-1000 | 100 | 100 |
| privacy | bool | 0 | 0 |

- **contrast and sharpness differ from their defaults.** The camera reported these
  values on first read; lumen never set them.
- Since auto exposure, auto white balance and autofocus are all on, the first frames
  after opening the device may still be settling. The cold first-buffer grab
  (below) looked correct this time, but that is one sample.

### Capture validation at 1280x720 MJPEG 30 fps (2026-10-15)

Conditions: nvpmodel MAXN, `jetson_clocks` **not** applied, desktop running.
Each run = 300 buffers from `v4l2src device=/dev/video0` with caps
`image/jpeg,width=1280,height=720,framerate=30/1` into `fakesink sync=false`. tegrastats
sampled every 500 ms. CPU is the per-core average summed over cores
(100% = one full core). CPUs 1-2 (isolated) stayed at 0% in every run.

| Pipeline after the caps | Wall time (300 frames) | Effective fps | CPU (sum) | RAM (tegrastats) | GR3D |
|---|---|---|---|---|---|
| idle (no pipeline, 10 s) | — | — | 4% | 1180 MB | 0% |
| none (MJPEG pass-through) | 11.0 s | ~30 | 10% | 1181-1191 MB | ~1% |
| `nvv4l2decoder mjpeg=1` | 10.9 s | ~30 | 25% | 1181-1227 MB | ~1% |
| `nvv4l2decoder mjpeg=1 enable-max-performance=1` | 10.9 s | ~30 | 19% | 1196-1230 MB | 0% |
| `nvv4l2decoder mjpeg=1 ! nvvidconv ! video/x-raw,format=RGBA` | 10.9 s | ~30 | 36% | 1196-1240 MB | ~1% |
| `jpegdec` (software) | 10.7 s | ~30 | 36% (one core at 34%) | 1181-1196 MB | ~2% |
| `nvjpegdec` (system memory out) | 22.8 s | **~13** | 96% (one core at 78%) | 1181-1196 MB | ~1% |
| `nvjpegdec ! video/x-raw(memory:NVMM)` | 23.0 s | **~13** | 95% (one core at 88%) | 1181-1198 MB | ~1% |

- EMC_FREQ read 0% in all of these runs.
- Idle RAM was 1180 MB on this boot, versus 1589 MB on 2026-10-08 (a different boot).
- Hypothesis, not verified: `nvjpegdec` is slow because of the 4:2:2 input. Either
  way, **`nvv4l2decoder mjpeg=1` is the working hardware decode path** for this camera.

Command template: `gst-launch-1.0 -q v4l2src device=/dev/video0 num-buffers=300 ! image/jpeg,width=1280,height=720,framerate=30/1 ! <pipeline> ! fakesink sync=false`,
timed with `date +%s.%N`, alongside `tegrastats --interval 500 --logfile <file>`.

### Single-frame grab to a file (1280x720)

| Method | Pipeline | Wall time incl. pipeline start | Output |
|---|---|---|---|
| cold, first buffer | `v4l2src num-buffers=1 ! image/jpeg,... ! filesink` | 1.0 s | camera JPEG, 4:2:2, ~113 KB |
| 30 buffers, keep last | `v4l2src num-buffers=30 ! image/jpeg,... ! multifilesink max-files=1` | 1.7 s | camera JPEG, 4:2:2, ~114 KB |
| 30 buffers, HW decode + re-encode | `... ! nvv4l2decoder mjpeg=1 ! nvvidconv ! video/x-raw,format=I420 ! jpegenc quality=95 ! multifilesink max-files=1` | 1.9 s | JPEG 4:2:0, ~156 KB |

All three frames were checked visually: correctly exposed and sharp, including the
cold first-buffer grab. The test frames showed the room and were deleted afterwards;
none are kept in the repo.

### Enumeration history (resolved 2026-10-15)

On 2026-10-15 at 09:28, the camera enumerated (as USB device number 10) on the first
replug after the user fitted a new cable. Before that, every attempt failed as
recorded below.

| Item | Value | Source command |
|---|---|---|
| Before the camera was plugged in (2026-10-08) | only the two root hubs, no `/dev/video*`, no USB device enumerated since boot | `lsusb`, `ls -l /dev/video*`, `dmesg` |
| UVC driver | built as a module (`CONFIG_USB_VIDEO_CLASS=m`); loaded automatically on enumeration | `zcat /proc/config.gz`, `dmesg \| grep 'registered new interface driver uvcvideo'` |

#### Diagnosis after plugging in the camera (2026-10-09)

| Item | Value | Source command |
|---|---|---|
| Connect detected | yes, on **`usb1-port2`** (USB 2.0 root hub, bus 1); nothing on bus 2 (USB 3.0) | `dmesg \| grep usb1-port` |
| Enumeration | **fails**: 4 bursts (kernel time 3074956 s, 3075130 s, 3079741 s, 3081059 s), each `Cannot enable. Maybe the USB cable is bad?` → `attempt power cycle` → `unable to enumerate USB device`; 14 `Cannot enable` lines in all | `dmesg \| grep -iE 'usb1-port2'` |
| Earlier USB errors | none from boot until the first burst | `dmesg \| grep -iE 'usb\|xusb'` |
| Over-current | no over-current message in the kernel log | `dmesg \| grep -iE 'over-?current'` |
| UVC driver | not involved yet: the failure happens before a USB device exists (`uvcvideo` not loaded) | `lsmod \| grep uvc` |
| Device tree in use | NVIDIA reference carrier: `nvidia,p3509-0000+p3636-0001`; `/boot` holds `tegra186-p3636-0001-p3509-0000-a01.dtb` and no Auvidea-specific DTB | `/proc/device-tree/compatible`, `ls /boot` |
| xHCI PHYs (DT) | `usb2-0` (otg), `usb2-1` (host), `usb2-2` (host), `usb3-1`; `usb3-0`, `usb3-2`, `hsic-0` disabled; usb2-1 and usb2-2 have a `vbus-supply` | `/proc/device-tree/xusb_padctl@3520000/ports/*`, `/proc/device-tree/xhci@3530000/phy-names` |
| Boot config | `/boot/extlinux/extlinux.conf` on the NVMe root says `root=/dev/mmcblk0p1`, but the running cmdline ends with `root=/dev/nvme0n1p1`; it is unclear which extlinux/DTB the bootloader loaded | `cat /boot/extlinux/extlinux.conf`, `cat /proc/cmdline` |
| Retest 2026-10-15 (after a reboot, uptime 4 d 20 h) | same failure on `usb1-port2`: one burst at boot (2.4-6.4 s) and one at 8493 s, then nothing since; still only root hubs, no `/dev/video*` | `lsusb`, `dmesg \| grep usb1-port2` |

Interpretation at the time (hypotheses): the host saw the device's pull-up but could
not complete the port reset. Candidates were (1) the cable or the camera, (2) not
enough VBUS current, (3) the NVIDIA reference-carrier device tree not matching the
Auvidea carrier. Since enumeration succeeded with a new cable and the device tree was
unchanged, (1) is the most likely cause. If enumeration failures come back, the same
`Cannot enable` signature in `dmesg` is the first thing to check.

## Decisions (2026-10-08)

| Topic | Decision |
|---|---|
| System packages | Approved: `sudo apt install v4l-utils gcc-8 g++-8` (installed by the user, 2026-10-15). No other system-level installs without asking. |
| sudo rule (2026-10-17) | `/etc/sudoers.d/lumen` (root:root 0440), installed by the user: NOPASSWD only for `jetson_clocks` (no args, `--show`, `--store`/`--restore /etc/lumen/l4t_dfs.conf`) and `systemctl stop gdm3` / `systemctl start gdm3`. `--restore` takes no other file, because it writes arbitrary sysfs paths read from that file. Verified: other arguments and other `systemctl` verbs still ask for a password. |
| CMake | User-local Kitware binary (`~/.local/opt/cmake-3.31.6-linux-aarch64`), not apt. Scripts take the CMake path as a parameter (default: `command -v cmake`, falling back to `~/.local/bin/cmake`), since `~/.local/bin` is not on PATH in non-interactive ssh. |
| CPU core placement | Keep the Denver cores (CPUs 1-2) isolated (`isolcpus=1-2` unchanged) for the baseline: llama.cpp runs on the A57 cores 0, 3, 4, 5. Core placement (adding the Denver cores, pinning) is a **phase 5 benchmark axis**. |
| Power measurement | External meter at the board's DC input. tegrastats keeps logging RAM, frequencies and temperatures, not power. |
| Headless mode | Temporary, per benchmark run only, never a permanent change (`graphical.target` stays the default). Benchmarks log RAM with the desktop running and with it stopped. Procedure: `sudo -n systemctl stop gdm3` **and** `loginctl terminate-session <id of the x11 session>` (the session belongs to the user, so no sudo is needed); stopping gdm3 alone frees nothing. To restore: `sudo -n systemctl start gdm3` (login screen; the user logs in again at the board). |
| Camera | Resolved 2026-10-15: enumerates after a cable change. Formats and capture validation are in the USB camera section. |

## Derived constraints (to discuss)

These are proposals based on the values above. Items marked **[decided]** are covered
in the Decisions section.

1. **Memory budget.** The GPU has no memory of its own: model weights, KV cache,
   mmproj, the GStreamer pipeline and the OS all share 7859 MB. At idle, with the GUI
   running, 1589 MB is already used. The usable budget for lumen is about
   MemAvailable ≈ 6.0 GB. Going headless should recover a few hundred MB, since
   gnome-software, compiz, update-manager and the other GUI processes alone hold about
   1 GB RSS. zram swap (3.9 GB) must not count as budget, because swapping weights
   would ruin throughput. **[decided]** Headless only temporarily during benchmark
   runs; RAM is logged both with and without the desktop.
2. **CUDA target = `sm_62` with CUDA 10.2.** This is the hardest constraint for
   llama.cpp: the toolkit is old, and building against it is the main risk in
   phase 1. The fallback path in CLAUDE.md (CPU build first, then patch ggml-cuda)
   applies. The arch must come from discovery (`deviceQuery`), not be hardcoded, so
   that the build stays portable to other NVIDIA GPUs.
3. **Host compiler = gcc 7.5, glibc 2.27, and no system CMake.** **[decided]**
   User-local CMake 3.31.6 and gcc-8/g++-8 8.4.0 are both installed. nvcc 10.2
   accepts both g++ 7.5 and g++-8 as host compiler (`-ccbin`).

   **CUDA code is limited to C++14.** nvcc 10.2 rejects `-std=c++17` outright. Host
   C++17 code (built by g++ 7.5 or 8) links fine with C++14 CUDA objects. For phase 1,
   this means any `.cu` source that requires C++17 must be patched down to C++14, or
   built with a newer toolkit, which this L4T does not have. Whether current
   llama.cpp's ggml-cuda sources (and its CMake, which may request CUDA C++17) need such
   patches is to be measured at the first CUDA build, not assumed. This is the most
   likely place for the "patch ggml-cuda" fallback to kick in.
4. **CPU threads.** The kernel isolates CPUs 1-2 (`isolcpus=1-2`), so default
   scheduling sees only the four A57 cores and `nproc` = 4. llama.cpp's thread count
   and affinity must be parameters. **[decided]** Baseline uses the 4 A57 cores, and
   Denver placement is a phase 5 axis.
5. **No dot-product or FP16 SIMD on the CPU** (`asimd` only). CPU-side quantized
   matmul will use the plain NEON paths, so the GPU should do the heavy lifting.
6. **Max-performance mode = nvpmodel ID 0 `MAXN`.** It is already active, but the
   default at boot is ID 3, so the benchmark script must check the mode (and run
   `jetson_clocks`, which needs sudo) instead of assuming it. Without `jetson_clocks`,
   the CPUs run `schedutil` and idle down to 345.6 MHz, and the GPU to 114.75 MHz. Runs
   with and without `jetson_clocks` are not comparable. The benchmark log should record
   the `jetson_clocks --show` output for each run, which needs sudo, so it has to be
   run by the user or allowed through a narrow sudoers rule.
   EMC is already at 1600 MHz, which is also its maximum. So in all four nvpmodel modes,
   memory bandwidth is the same, and that matters for decode-bound LLM inference.
   **Thermal: cooling setup unknown** (probably passive, a heatsink enclosure; fan
   presence not confirmed and not observable from software; see the Fan row). Plan
   for the passive case: it is the worst case. The software
   throttle starts at 95.5 °C (CPU and GPU zones, passive trip), and the critical trip
   is 100.5 °C. Idle is about 30 °C. How fast a sustained LLM load climbs toward
   95.5 °C with this enclosure is unknown, and must be measured in phase 2, not
   assumed. Benchmark runs must:
   (a) log temperatures (tegrastats) and the `cpu-balanced` / `gpu-balanced` cooling
   states (sysfs, no root), which show throttling directly;
   (b) start from a recorded temperature, with a cool-down between configs;
   (c) check for drift between run 1 and run 5 of the median protocol.
   `jetson_clocks` pins clocks at max, but it does not prevent thermal throttling.
7. **Power measurement.** This tegrastats build shows no power rails, which affects
   the "power" column of the benchmark protocol. **[decided]** Power comes from an
   external meter at the DC input. On-board rails are not used.
8. **Storage is not a constraint.** 100 GB free on NVMe for models, the llama.cpp
   build and bench artifacts.
9. **Capture format.** Anything above 896x480 is MJPEG only (4:2:2), so phase 3 at
   720p needs a JPEG decode. The validated hardware path is `v4l2src` →
   `image/jpeg` → **`nvv4l2decoder mjpeg=1`** (→ `nvvidconv` if RGB is needed). It
   holds 30 fps at 19-36% of one core. **Do not use `nvjpegdec`** for this camera:
   ~13 fps and a full core. Software `jpegdec` (36%, 30 fps) is an acceptable fallback,
   and it is the portable path for boards without these NVIDIA elements. The decoder
   element must be a parameter (portability, swappable `rtspsrc`).
10. **On-demand grab: cold start versus a running pipeline.** A cold single-frame grab
    costs ~1.0 s of pipeline start-up and gave a usable first frame. Keeping a pipeline
    running costs ~10% of one core plus the decode load, all the time, but grabs
    instantly. To decide in phase 3/4. The 1.0 s cold start is small next to expected
    VQA latency, but it adds directly to TTFT as the user experiences it.
11. **Possibly skip decode entirely.** The camera already delivers a JPEG. If the
    llama.cpp image path accepts a JPEG file or buffer directly (to verify in phase 2),
    the grab can be pass-through (10% CPU) and the decode happens once, inside the
    model's preprocessing. Whether that CPU decode beats `nvv4l2decoder` + handing
    over raw pixels is a phase 5 measurement.
12. **Input resolution.** Native capture sizes are fixed (list above). The mmproj
    resizes anyway, so the capture size feeding the model (720p versus 896x480 versus
    640x480, the latter two also available as raw NV12/YUYV with no decode) is a
    phase 5 axis that ties into the "input resolution" item.
13. **USB bandwidth.** The camera runs at high-speed (480 Mbit/s, USB 2.1 device). The
    4K MJPEG modes exist but are irrelevant for lumen. The RAM cost of capture is small
    (+15 to +60 MB in tegrastats during the runs).
14. **Old Python (3.6.9).** If `src/` uses Python, many current packages no longer
    support 3.6. This may push the VQA loop toward C/C++ or a shell + llama.cpp
    server design. (Python 3.6 stdlib was enough for the V4L2 ioctl queries above.)
15. **Portability.** Board identity comes from `/proc/device-tree/compatible`, CUDA
    arch from `deviceQuery`, power modes from `/etc/nvpmodel.conf`, and threads,
    affinity, capture device, format, resolution and decoder from parameters. None of
    these values should appear as literals in scripts.
