# PyroWave on the Steam Deck (this fork)

PyroWave is an intra-only, Vulkan-compute wavelet codec by Hans-Kristian Arntzen
([Themaister/pyrowave](https://github.com/Themaister/pyrowave)). Every frame stands
alone, so encode and decode take a fraction of a millisecond and a lost packet only
blurs part of one frame. In exchange it needs several times the bandwidth of HEVC.

In this fork it is **opt-in**: HEVC stays the default, and *Automatic* never picks
PyroWave. It is built into the Linux AppImage only.

## Building

The AppImage CI builds everything. To do the same by hand:

```sh
git submodule update --init --recursive
pyrowave/build-pyrowave.sh "$PREFIX" "$PWD"/app/deploy/linux/appimage/pyrowave-*.patch
PYROWAVE_LIBRARY="$PREFIX/lib/libpyrowave-shared.so.0" scripts/build-appimage.sh
```

- `pyrowave/pyrowave` is pinned to Themaister/pyrowave `89f7e47d` (C API 0.6.0).
  `build-pyrowave.sh` fetches Granite at exactly the commit that pyrowave's own
  `checkout_granite.sh` pins (`1b2d1801`) and applies the parser hang fix from
  dimizago/pyrowave@9f2ab7c2.
- `PYROWAVE_LIBRARY` turns on `CONFIG+=pyrowave` and bundles the library. Without
  it, `build-appimage.sh` builds exactly as upstream does.
- Moonlight `dlopen()`s `libpyrowave-shared.so.0` only when a PyroWave stream is
  requested, and checks its API version. A missing or incompatible library can't
  stop Moonlight from starting, and it never affects HEVC.
- `scripts/check-appimage.sh <AppImage> --pyrowave` and
  `scripts/smoke-appimage.sh <AppImage>` run the same static checks and UI smoke
  test as CI. Neither needs a GPU. They unpack the AppImage with
  `--appimage-extract`, because `strings` on the AppImage itself misses everything
  inside its compressed payload.

`moonlight-common-c` points at
[naireet/moonlight-common-c@pyrowave](https://github.com/naireet/moonlight-common-c/tree/pyrowave).
That branch is upstream plus the PyroWave protocol definitions, partial-frame
delivery, and a UDP receive-buffer log line. It includes a standalone test harness
(`tests/`).

## Installing next to the normal Deck build (A/B)

Moonlight uses portable mode when `portable.dat` exists in its **working
directory**, not next to the binary. It then keeps settings, pairing, logs, the
box-art cache and the QML cache in that directory. That lets the PyroWave build run
beside the normal one without the two touching each other:

1. Make a folder, e.g. `~/Applications/moonlight-pyrowave/`, and put the PyroWave
   AppImage and an empty `portable.dat` in it.
2. Linux builds only log to stderr, so add a launcher script `run.sh` in the same
   folder to capture a log:

   ```sh
   #!/bin/bash
   cd "$(dirname "$(readlink -f "$0")")"
   { date; env | grep -E '^(GAMESCOPE_WAYLAND_DISPLAY|WAYLAND_DISPLAY|DISPLAY|ENABLE_GAMESCOPE_WSI|XDG_RUNTIME_DIR)='; } > moonlight.log
   exec ./Moonlight-*-x86_64.AppImage "$@" >> moonlight.log 2>&1
   ```

   Then run `chmod +x run.sh`.
3. In Steam, add a non-Steam game with `run.sh` as the target and **Start In** set
   to that folder.
4. Because this is a fresh portable profile, pair with the host again. The host
   will list it as a separate client.

The existing Deck build and its shortcut stay untouched.

## Using it

- **Settings → Video codec → PyroWave (experimental).** A hint under the list
  shows the bitrate PyroWave needs at the current resolution and frame rate: a
  starting point of 100 Mbps at 1280×800@60, scaled with pixel rate.
- **HDR** and **YUV 4:4:4** use the existing toggles. With HDR on, the stream is
  10-bit and becomes BT.2020/PQ whenever the host display is in HDR mode.
- If the host doesn't advertise PyroWave, or this device can't start the decoder,
  you get a warning at launch and the stream falls back to HEVC. You also get a
  warning when the bitrate is below the recommendation.
- CLI: `moonlight stream <host> <app> --video-codec PyroWave`.

Environment variables (set them in `run.sh`):

| Variable | Default | Meaning |
|---|---|---|
| `PYROWAVE_MIN_BLOCK_RATIO` | `0.5` | Show an incomplete frame if its two coarsest wavelet bands are intact and more than this fraction of blocks arrived; otherwise repeat the previous frame. `0.9` is PyroWave's own default. |
| `PYROWAVE_LIBRARY` | bundled | Load a different `libpyrowave-shared.so.0`. |
| `PLVK_LOG_LEVEL` | `2` (warn) | libplacebo log level; `4` is debug. |

## Host contract

Protocol values are byte-identical to the azafrob, andygrundman and dimizago
`moonlight-common-c` forks. The table lists what this client expects on top of
them.

| Item | This client |
|---|---|
| Codec IDs / masks | `VIDEO_FORMAT_PYROWAVE{,_444,10_420,10_444}` = `0x10/0x20/0x40/0x80` |
| Capability bits | `SCM_PYROWAVE{,_444,10_420,10_444}` = `0x00800000..0x04000000` |
| SDP | `x-nv-vqos[0].bitStreamFormat=3`, `x-nv-clientSupportHevc=0` |
| When it's offered | Only when the user selects PyroWave. Hosts should advertise the SCM bits only when PyroWave is enabled. |
| Frame payload | Little-endian `[u32 count] { [u32 size][PyroWave packet] }*`, packets in encoder order (coarsest first) |
| Frame type | Every frame flagged IDR |
| Colour | Honour `encoderCscMode`. This client asks for **BT.709, full range**; in HDR, BT.2020 NCL + PQ, full range. 4:2:0 chroma centre-sited. |
| 10-bit planes | Normalized values in 16-bit UNORM planes |
| Loss feedback | Salvaged partial frames send no loss report; fully lost frames still request IDR/RFI, which a PyroWave host can ignore. |
| FEC | Any per-block FEC percentage works. For Wi-Fi, protect the coarse head and give the tail some parity too. |

Packet-aligned framing (one PyroWave packet per RTP shard, so every received shard
is decodable) would help Wi-Fi a lot. It needs a new capability bit on both ends
and is deliberately **not** implemented yet.

## What to check in the log

With the launcher above, `moonlight.log` should contain:

- `PyroWave: loaded libpyrowave-shared.so.0 (API version 0.6.0)`
- `PyroWave: Vulkan device ...`, then `PyroWave: decoding with the compute path`
- `PyroWave decoder ready: 1280x800 4:2:0 10-bit, 3 slots`
- `PyroWave output: source BT.2020/PQ (...) -> swapchain BT.2020/PQ (...): HDR10
  passthrough, no libplacebo tone mapping`. If it says `libplacebo tone maps PQ to
  the SDR swapchain`, then gamescope didn't offer an HDR10 surface.
- Gamescope's own lines: `[Gamescope WSI] Made gamescope surface for xid`,
  `server hdr output enabled: true` and `hdr formats exposed to client: true`.
  `Failed to connect to gamescope socket` or a *"non-Gamescope swapchain"* popup
  means HDR can't work. That affects HEVC HDR just the same.
- `PyroWave: bitstream colorimetry ... differs from the negotiated ...` means the
  host is signalling different colours from what was agreed.
- `Actual receive buffer size: N`. Linux reports double the usable size. Values
  around 425984 mean `net.core.rmem_max` is at the stock 212992, which can drop
  packets on large PyroWave frames.

## A/B recipe

Run the normal build and the PyroWave build (see above) against the same host, the
same game scene and the same network position. Turn on the performance overlay
(Select+L1+R1+X) and **write down the effective settings from the overlay before
every run**: the codec line (e.g. `PyroWave 10-bit 4:2:0 HDR` or `HEVC 10-bit HDR`),
resolution, FPS, bitrate, and for PyroWave the `HDR:` line. Settings that fell back
silently are the most common reason an A/B doesn't mean what you think it does.

### Headline comparison

**PyroWave 10-bit 4:2:0 against HEVC Main10 4:2:0 at the same bitrate**, HDR on for
both, YUV 4:4:4 off for both. Repeat at two bitrates: the HEVC setting you normally
use, and the PyroWave recommendation from the settings hint.

**4:4:4 is a separate, labelled comparison**: PyroWave 10-bit 4:4:4 against HEVC
10-bit 4:4:4, if the host offers it. Don't mix it into the headline numbers.

For each run, record from the overlay:

- the frame rates (network / decode / render);
- "Frames dropped by your network connection";
- for PyroWave, "Frames replaced before display" and the "Partial frames" line;
- the average times and network latency.

### HDR checks (Deck OLED, HDR enabled in Deck display settings)

1. **Black level:** a dark scene or a black loading screen should be true black,
   not grey, and match HEVC. Raised blacks point to a range mismatch.
2. **Dark-gradient banding:** a dark sky or fog gradient. Compare the steps and
   blockiness between the two codecs at matched bitrate.
3. **Small bright highlights, 1% and 10% windows:** a small bright object (~1% of
   the screen: sun, lamp, muzzle flash) and a larger one (~10%: a window, a bright
   UI panel) on dark surroundings. Check peak brightness, clipping, and whether the
   whole picture dims when the highlight appears (tone-mapping pumping). Compare
   with HEVC.
4. **Red/blue text fringing:** saturated red and blue text or thin UI lines on a
   dark background (4:2:0 chroma). Colour bleeding or a shifted colour edge points
   to chroma siting; compare with HEVC, then with 4:4:4.
5. The overlay's `HDR:` line should say `output BT.2020/PQ (HDR10 passthrough)`,
   with the host's mastering values.

### Wi-Fi checks

1. Stand where you normally play. Run 5 minutes of each codec and compare dropped
   frames, "Frames replaced before display" and the "Partial frames" line.
2. Move to a weaker spot (another room, or behind a wall) and repeat. PyroWave
   should turn soft rather than freeze; the partial-frame counts show how often
   that happens.
3. If PyroWave repeats frames a lot ("held back" is high), try
   `PYROWAVE_MIN_BLOCK_RATIO=0.3` for more but blurrier partial frames. If partial
   frames look too broken, try `0.7`.
4. Try a lower bitrate: smaller frames are fewer packets per frame, so fewer
   chances to lose one.
5. Note the `Actual receive buffer size` log line (see the log section above).
