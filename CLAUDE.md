# keyfinder-cli-windows

Windows build + binary distribution of [keyfinder-cli](https://github.com/evanpurkhiser/keyfinder-cli) (wraps libkeyfinder for musical key detection). Upstream's CI only builds Ubuntu/macOS, so this repo compiles it for Windows and publishes the result as a GitHub Release — used by [mp3redactor](https://github.com/Erlbon/mp3redactor) as an external tool it shells out to. Standalone repo, not part of the redactor_common family (no shared library dependency, no `APP_VERSION`/`bump_version.py` pipeline) — kept separate specifically to keep ~120MB of FFmpeg DLLs out of mp3redactor's own history.

## Commands
- Build: `powershell -ExecutionPolicy Bypass -File build.ps1`, run from a path with **no spaces** (vcpkg's ffmpeg-family tooling refuses otherwise)
- Requires (one-time): Visual Studio with the Desktop C++ workload, Git, 7-Zip
- Output: `dist\keyfinder-cli.exe` + `dist\avformat-*.dll` + `dist\avcodec-*.dll` + `dist\avutil-*.dll` + `dist\swresample-*.dll`

## Domain notes
- vcpkg (bootstrapped by the script) builds only the small native deps from source — `libkeyfinder` and `getopt-win32` (MSVC's CRT has no `getopt_long()`) — triplet `x64-windows-static`. FFmpeg itself comes from a **prebuilt** dev package (gyan.dev's `ffmpeg-release-full-shared.7z`) rather than vcpkg's own `ffmpeg` port, which builds from source and takes 20-40+ minutes for no benefit here.
- `src/` is upstream's 1.2.0 release with two small `if(WIN32)`-guarded changes to `src/CMakeLists.txt` (still builds unmodified on Linux/macOS): link `getopt-win32` via vcpkg, and link FFmpeg via explicit `-DFFMPEG_ROOT=<path>` instead of pkg-config (no FFmpeg pkg-config setup exists on Windows). Also `cmake_minimum_required` bumped 3.10→3.15, and `CMAKE_MSVC_RUNTIME_LIBRARY` set explicitly to `MultiThreaded...` — without it, linking fails with `LNK2038` CRT mismatch against libkeyfinder's `/MT` build.
- All 5 output files must ship together (dynamically linked) — a bare `keyfinder-cli.exe` with no DLLs fails at launch with a "code execution cannot proceed" error. The release zip bundles all 5 plus `LICENSE`/`NOTICE.txt`; the individually-uploaded files on the same release are for projects that fetch just one or two programmatically.
- Licensing: `keyfinder-cli`/`libkeyfinder` are GPL-3.0-or-later, `getopt-win32` is LGPL-3.0, the bundled FFmpeg build is GPL-licensed. `NOTICE.txt` breaks this down per binary with source links — keep it in sync with `LICENSE` if the build's dependencies ever change.

## Known build gotchas (worth knowing before touching `build.ps1`)
- `cmake.exe` isn't on PATH by default — located via `vswhere`, which needs `-requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64` (a bare `-products *` can match an unrelated VS-installer-registered product).
- PowerShell silently does not expand an unquoted `-DFOO=$var` argument (a bareword starting with `-`) — quote the whole token, e.g. `"-DFOO=$var"`.
- Publishing a large release asset: GitHub lets you attach files to an *already-published* release via its edit page, so publishing early isn't fatal. `avcodec-*.dll` (~98MB) exceeds automated upload tooling limits in some setups — may need a manual drag-and-drop for the largest DLLs.

See [redactor-family-cross-platform-port] in project memory: this whole Windows fork exists only because upstream targets Linux/Mac natively — if the Redactor family is ever ported there, this repo becomes unnecessary.
