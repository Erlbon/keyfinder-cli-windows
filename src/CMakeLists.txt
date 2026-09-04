# 3.15, not upstream's 3.10: CMP0091 (new in 3.15) is required for the
# CMAKE_MSVC_RUNTIME_LIBRARY variable below to have any effect -- below
# 3.15 that policy defaults OLD and the variable is silently ignored.
cmake_minimum_required(VERSION 3.15)
project(keyfinder-cli)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# vcpkg's toolchain does NOT set CMAKE_MSVC_RUNTIME_LIBRARY for us (checked:
# no such logic in scripts/buildsystems/vcpkg.cmake) -- without this, this
# target links /MD (CMake's MSVC default) while our x64-windows-static
# triplet built libkeyfinder/getopt as /MT, and the linker fails with
# LNK2038 "RuntimeLibrary mismatch" + a pile of LNK2005 CRT symbol clashes.
if(WIN32)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

add_executable(${PROJECT_NAME}
    keyfinder_cli.cpp
)

# FFMPEG
#
# On Windows there's no ffmpeg-dev pkg-config setup available out of the
# box (vcpkg's ffmpeg port builds it from source, which is slow -- easier
# to point this at a prebuilt "shared" dev package, e.g. gyan.dev's
# ffmpeg-release-full-shared, which ships MSVC-compatible .lib import libs
# directly under <FFMPEG_ROOT>/lib and headers under <FFMPEG_ROOT>/include).
# Elsewhere (Linux/macOS CI, dev machines with the libs installed via the
# system package manager) pkg-config still works as upstream intended.
if(WIN32)
    if(NOT FFMPEG_ROOT)
        message(FATAL_ERROR
            "Set -DFFMPEG_ROOT=<path to an extracted FFmpeg 'shared' dev "
            "package> (e.g. gyan.dev's ffmpeg-release-full-shared) -- no "
            "pkg-config setup for FFmpeg exists on Windows."
        )
    endif()
    target_include_directories(${PROJECT_NAME} PRIVATE "${FFMPEG_ROOT}/include")
    target_link_directories(${PROJECT_NAME} PRIVATE "${FFMPEG_ROOT}/lib")
    target_link_libraries(${PROJECT_NAME} PRIVATE avformat avcodec swresample avutil)
else()
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(LIBAV REQUIRED IMPORTED_TARGET
        libavformat
        libavcodec
        libswresample
        libavutil
    )
    target_link_libraries(${PROJECT_NAME} PRIVATE
        PkgConfig::LIBAV
    )
endif()

# libkeyfinder
find_package(KeyFinder REQUIRED)
target_link_libraries(${PROJECT_NAME} PRIVATE KeyFinder::keyfinder)

# getopt_long() is POSIX and not provided by MSVC's CRT -- pull in the
# vcpkg "getopt-win32" port on Windows only (upstream project only ships
# Ubuntu/macOS CI, see https://github.com/evanpurkhiser/keyfinder-cli).
if(WIN32)
    find_package(getopt CONFIG REQUIRED)
    target_link_libraries(${PROJECT_NAME} PRIVATE
        $<IF:$<TARGET_EXISTS:getopt::getopt_shared>,getopt::getopt_shared,getopt::getopt_static>
    )
endif()

# Installation
include(GNUInstallDirs)
install(TARGETS ${PROJECT_NAME})
if(UNIX)
    install(FILES ${PROJECT_NAME}.1 DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)
endif()
