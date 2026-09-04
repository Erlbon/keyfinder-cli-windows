#Requires -Version 5.1
<#
Builds keyfinder-cli.exe from source on Windows.

There is no prebuilt Windows binary for keyfinder-cli (upstream's CI only
builds Ubuntu/macOS: https://github.com/evanpurkhiser/keyfinder-cli/blob/main/.github/workflows/main.yml)
so it has to be compiled locally. This script automates that end-to-end:

  1. Clones + bootstraps a classic vcpkg checkout (skipped if already done --
     safe to re-run).
  2. Installs the small native deps via vcpkg: libkeyfinder (statically
     linked, only depends on fftw3) and getopt-win32 (MSVC's CRT has no
     getopt_long(), which keyfinder_cli.cpp needs -- see CMakeLists.txt).
     Deliberately does NOT use vcpkg's ffmpeg port -- that compiles ffmpeg
     from source, which is a 20-40+ minute build. Instead:
  3. Downloads (if not already present) gyan.dev's prebuilt FFmpeg "shared"
     dev package -- ships MSVC-compatible .lib import libs + headers + DLLs
     ready to link against, no compiling required. Extracted to .\ffmpeg-shared.
  4. Configures + builds keyfinder-cli with CMake, statically linked against
     libkeyfinder/getopt (x64-windows-static) and dynamically against the
     FFmpeg DLLs.
  5. Copies the built exe + the FFmpeg DLLs it needs (avformat/avcodec/
     avutil/swresample) to .\dist\.

Requires: Visual Studio (Desktop C++ workload), git, and 7-Zip, all already
on this machine. First run needs a few minutes to build libkeyfinder
(small) and download FFmpeg (~59MB); re-runs are fast since both are cached.

IMPORTANT: this whole build must run from a path with NO SPACES --
vcpkg's toolchain (and some of its ports) refuse to build otherwise. That's
why this lives under C:\Temp\kfcli-build rather than under "_AI Coding".

Usage:  powershell -ExecutionPolicy Bypass -File build.ps1
#>

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$vcpkgDir = Join-Path $root "vcpkg"
$srcDir = Join-Path $root "src"
$buildDir = Join-Path $root "cmake-build"
$distDir = Join-Path $root "dist"
$ffmpegDir = Join-Path $root "ffmpeg-shared"
$ffmpegArchive = Join-Path $root "ffmpeg-full-shared.7z"
$ffmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full-shared.7z"
$triplet = "x64-windows-static"

if ($root -match '\s') {
    throw "This script's own path ('$root') contains a space -- vcpkg will fail to build. Move this whole folder to a path with no spaces (e.g. C:\Temp\kfcli-build) and re-run from there."
}

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Find-Cmake {
    $onPath = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        # -requires the VC tools component -- without it, -products * can
        # match an unrelated VS-installer-registered product (e.g. SQL
        # Server Management Studio) that has no C++/CMake tooling at all.
        $vsInstall = & $vswhere -latest -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath
        if ($vsInstall) {
            $candidate = Join-Path $vsInstall "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
            if (Test-Path $candidate) { return $candidate }
        }
    }
    throw "cmake.exe not found on PATH or via a Visual Studio install. Install CMake (or the VS 'C++ CMake tools' component) and re-run."
}

$cmakeExe = Find-Cmake
Write-Step "Using cmake: $cmakeExe"
$env:PATH = (Split-Path $cmakeExe) + ";" + $env:PATH

# -- 1. vcpkg -----------------------------------------------------------

if (-not (Test-Path (Join-Path $vcpkgDir "vcpkg.exe"))) {
    if (-not (Test-Path $vcpkgDir)) {
        Write-Step "Cloning vcpkg"
        git clone --depth 1 https://github.com/microsoft/vcpkg $vcpkgDir
        if ($LASTEXITCODE -ne 0) { throw "git clone vcpkg failed" }
    }
    Write-Step "Bootstrapping vcpkg"
    & (Join-Path $vcpkgDir "bootstrap-vcpkg.bat") -disableMetrics
    if ($LASTEXITCODE -ne 0) { throw "vcpkg bootstrap failed" }
} else {
    Write-Step "vcpkg already bootstrapped, skipping clone/bootstrap"
}
$vcpkgExe = Join-Path $vcpkgDir "vcpkg.exe"

# -- 2. small native deps via vcpkg (libkeyfinder, getopt) ----------------

Write-Step "vcpkg install libkeyfinder getopt-win32 (triplet $triplet)"
& $vcpkgExe install "libkeyfinder:$triplet" "getopt-win32:$triplet"
if ($LASTEXITCODE -ne 0) { throw "vcpkg install failed" }

# -- 3. prebuilt FFmpeg dev package (skips compiling ffmpeg) --------------

if (-not (Test-Path (Join-Path $ffmpegDir "lib\avformat.lib"))) {
    if (-not (Test-Path $ffmpegArchive)) {
        Write-Step "Downloading FFmpeg shared dev package ($ffmpegUrl)"
        curl.exe -L -C - -o $ffmpegArchive $ffmpegUrl
        if ($LASTEXITCODE -ne 0) { throw "FFmpeg download failed" }
    }
    Write-Step "Extracting FFmpeg dev package"
    $sevenZip = "${env:ProgramFiles}\7-Zip\7z.exe"
    if (-not (Test-Path $sevenZip)) { throw "7-Zip not found at $sevenZip" }
    $extractTmp = Join-Path $root "ffmpeg-extract-tmp"
    Remove-Item -Recurse -Force $extractTmp -ErrorAction SilentlyContinue
    & $sevenZip x -y $ffmpegArchive "-o$extractTmp" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z extract failed" }
    $inner = Get-ChildItem $extractTmp -Directory | Select-Object -First 1
    Remove-Item -Recurse -Force $ffmpegDir -ErrorAction SilentlyContinue
    Move-Item $inner.FullName $ffmpegDir
    Remove-Item -Recurse -Force $extractTmp -ErrorAction SilentlyContinue
} else {
    Write-Step "FFmpeg dev package already extracted, skipping download"
}

# -- 4. configure + build keyfinder-cli -----------------------------------

Write-Step "CMake configure"
$toolchain = Join-Path $vcpkgDir "scripts\buildsystems\vcpkg.cmake"
# -A x64 matters: the VS generator defaults to Win32 unless told otherwise,
# which would silently look for packages under vcpkg's x86 triplet instead
# of the x64-windows-static one we actually installed to.
Remove-Item -Recurse -Force $buildDir -ErrorAction SilentlyContinue
& $cmakeExe -S $srcDir -B $buildDir -A x64 `
    "-DCMAKE_TOOLCHAIN_FILE=$toolchain" `
    "-DVCPKG_TARGET_TRIPLET=$triplet" `
    "-DFFMPEG_ROOT=$ffmpegDir" `
    "-DCMAKE_BUILD_TYPE=Release"
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

Write-Step "CMake build (Release)"
& $cmakeExe --build $buildDir --config Release
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

# -- 5. collect output: exe + the FFmpeg DLLs it actually links against ---

$exe = Get-ChildItem -Path $buildDir -Recurse -Filter "keyfinder-cli.exe" -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $exe) { throw "keyfinder-cli.exe not found in build output" }

New-Item -ItemType Directory -Force -Path $distDir | Out-Null
Copy-Item $exe (Join-Path $distDir "keyfinder-cli.exe") -Force

# Only avformat/avcodec/avutil/swresample are linked (not avdevice/
# avfilter/swscale) -- copy whichever versioned DLL of each is present.
foreach ($lib in @("avformat", "avcodec", "avutil", "swresample")) {
    $dll = Get-ChildItem -Path (Join-Path $ffmpegDir "bin") -Filter "$lib-*.dll" | Select-Object -First 1
    if (-not $dll) { throw "Could not find $lib-*.dll in $ffmpegDir\bin" }
    Copy-Item $dll.FullName $distDir -Force
}

Write-Step "Done: $distDir"
Get-ChildItem $distDir | Format-Table Name, Length
& (Join-Path $distDir "keyfinder-cli.exe") --help
