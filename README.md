# keyfinder-cli-windows

Windows build + binary distribution of [keyfinder-cli](https://github.com/evanpurkhiser/keyfinder-cli),
a small CLI wrapper around [libkeyfinder](https://github.com/mixxxdj/libkeyfinder)
that estimates the musical key of an audio file.

**Why this repo exists:** there is no prebuilt Windows binary upstream --
[keyfinder-cli's own CI](https://github.com/evanpurkhiser/keyfinder-cli/blob/main/.github/workflows/main.yml)
only builds Ubuntu and macOS. This repo has a `build.ps1` that compiles it
on Windows end to end, and publishes the result as a
[Release](../../releases) so other projects can just download it instead
of repeating the build.

## Download

Grab **`keyfinder-cli-<version>-windows.zip`** from the
[latest release](../../releases/latest) and extract it -- it bundles
`keyfinder-cli.exe` with the 4 `.dll` files it dynamically links against
FFmpeg with, all in one download, so there's no way to end up with the
exe but not its DLLs.

(The 5 files are also uploaded individually on the same release page,
for projects that fetch just one or two of them programmatically -- but
grabbing those by hand one at a time is exactly how you can end up with
`keyfinder-cli.exe` sitting alone, no DLLs, which fails at launch with
a "The code execution cannot proceed because avformat-*.dll was not
found" system error. Use the zip unless you have a specific reason not
to.)

Either way, all 5 files need to end up in the same folder:

- `keyfinder-cli.exe`
- `avformat-*.dll`, `avcodec-*.dll`, `avutil-*.dll`, `swresample-*.dll`

Usage: `keyfinder-cli.exe [-n key-notation] file.mp3` -- see upstream's
[README](https://github.com/evanpurkhiser/keyfinder-cli#readme) for the
`-n` notation options (standard/openkey/camelot).

## Building it yourself

```
powershell -ExecutionPolicy Bypass -File build.ps1
```

Requires (all one-time, already on a typical dev box): Visual Studio
with the Desktop C++ workload, Git, and 7-Zip. First run takes a few
minutes -- [vcpkg](https://github.com/microsoft/vcpkg) builds the small
native deps (`libkeyfinder`, `getopt-win32`) from source, and a ~59MB
prebuilt FFmpeg "shared" dev package is downloaded from
[gyan.dev](https://www.gyan.dev/ffmpeg/builds/) rather than compiling
FFmpeg itself (vcpkg's own `ffmpeg` port does that from source, 20-40+
minutes for no benefit here). Re-runs are fast, everything's cached.

Must run from a path with **no spaces** -- vcpkg's `ffmpeg`-family
tooling refuses to build otherwise.

Output: `dist\keyfinder-cli.exe` + `dist\av{format,codec,util}-*.dll` +
`dist\swresample-*.dll`.

## What's patched vs. upstream

`src/` is upstream's [1.2.0 release](https://github.com/evanpurkhiser/keyfinder-cli/releases/tag/1.2.0),
with two small changes to `src/CMakeLists.txt` for the Windows/MSVC
build (both guarded `if(WIN32)`, so this still builds unmodified on
Linux/macOS the way upstream intends):

- Link [`getopt-win32`](https://github.com/ludvikjerabek/getopt-win) (via
  vcpkg) -- MSVC's CRT has no `getopt_long()`, which `keyfinder_cli.cpp`
  needs.
- Link FFmpeg via an explicit `-DFFMPEG_ROOT=<path>` (headers + `.lib` +
  DLLs from the prebuilt package above) instead of pkg-config -- there's
  no FFmpeg pkg-config setup on Windows out of the box.

Also: `cmake_minimum_required` bumped from upstream's 3.10 to 3.15, plus
an explicit `set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreaded...)` -- needed
so this target's CRT matches libkeyfinder's (`/MT`, from vcpkg's
`x64-windows-static` triplet); without it the linker fails with
`LNK2038 RuntimeLibrary mismatch`.

## Licensing

`keyfinder-cli` and `libkeyfinder` are GPL-3.0-or-later (see
[`LICENSE`](LICENSE)); this repo, being a build wrapper around them, is
released the same way. `getopt-win32` is LGPL-3.0. The FFmpeg build
linked in the release binaries (gyan.dev's default "full" package) is
GPL-licensed.

[`NOTICE.txt`](NOTICE.txt) breaks that down per binary (keyfinder-cli,
libkeyfinder, FFmpeg) with source links for each -- the release zip
bundles both `LICENSE` and `NOTICE.txt` alongside the exe/DLLs so
anyone redistributing this build downstream (as e.g. mp3redactor does,
bundling it as an external tool it shells out to -- see that project's
own README) has everything GPLv3 requires them to carry along with it,
without having to hunt it down separately.

All credit for the actual key-detection logic goes to
[Ibrahim Sha'ath](http://www.ibrahimshaath.co.uk/) (original libKeyFinder
author), the [Mixxx](https://github.com/mixxxdj) project (current
libkeyfinder maintainers), and [Evan Purkhiser](https://github.com/evanpurkhiser)
(keyfinder-cli). This repo only adds a Windows build.
