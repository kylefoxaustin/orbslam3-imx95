# SPDX-License-Identifier: GPL-3.0-or-later
# ORB-SLAM3 i.MX95 port (Step 2) — aarch64 cross toolchain against the Yocto imx95 sysroot
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER   aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_SYSROOT      ${CMAKE_CURRENT_LIST_DIR}/sysroot)
set(CMAKE_FIND_ROOT_PATH ${CMAKE_CURRENT_LIST_DIR}/sysroot)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
# Eigen headers are arch-independent — reuse host's
include_directories(SYSTEM /usr/include/eigen3)
include_directories(SYSTEM /home/kyle/Documents/GitHub/orbslam3-imx95/qemu_work/boost_1_74_0)
# GCC-13-era target libstdc++; carry the same defensive flags as the x86 build
set(CMAKE_CXX_FLAGS_INIT "-include cstdint -Wno-error=array-bounds -Wno-array-bounds")
