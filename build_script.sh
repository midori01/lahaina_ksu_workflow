#!/bin/bash

## DEVICE STUFF
DEVICE_MODEL="$1"
ZIP_DIR="$(pwd)/AnyKernel3"
SRC_DIR=$(pwd)
OUT_DIR=$SRC_DIR/out
TC_DIR=$SRC_DIR/clang
JOBS="$(nproc --all)"

# Environment Variables
# Note: Using llvm-ar/nm/objcopy/strip is standard for LLVM=1
MAKE_PARAMS="-j$JOBS -C $SRC_DIR O=$OUT_DIR ARCH=arm64 CC=clang \
CLANG_TRIPLE=aarch64-linux-gnu- LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- \
CROSS_COMPILE_ARM32=arm-linux-gnueabi-"

export PATH="$TC_DIR/bin:$PATH"

# Configuration Mapping
case "$DEVICE_MODEL" in
    "SM-G9910") DEVICE_NAME="o1q"; DEFCONFIG="o1q_defconfig" ;;
    "SM-G9960") DEVICE_NAME="t2q"; DEFCONFIG="t2q_defconfig" ;;
    "SM-G9980") DEVICE_NAME="p3q"; DEFCONFIG="p3q_defconfig" ;;
    "SM-G990B") DEVICE_NAME="r9q"; DEFCONFIG="r9q_defconfig" ;;
    "SM-G990B2") DEVICE_NAME="r9q2"; DEFCONFIG="r9q2_defconfig" ;;
    *) echo "Config not found for $DEVICE_MODEL"; exit 1 ;;
esac

# Handle xxKSU-Hookless
if [[ "$*" == *"--ksu"* ]]; then
    ZIP_NAME="Lavender_xxKSU_${DEVICE_NAME}_${DEVICE_MODEL}_$(date +%d%m%y-%H%M)"
    
    echo "Injecting xxKSU-Hookless configurations into $DEFCONFIG..."
    cat <<EOF >> arch/arm64/configs/$DEFCONFIG
CONFIG_KSU=y
CONFIG_KSU_EXTRAS=y
CONFIG_KSU_TAMPER_SYSCALL_TABLE=y
CONFIG_KSU_LSM_SECURITY_HOOKS=y
CONFIG_KSU_THRONE_TRACKER_ALWAYS_THREADED=y
EOF
    
    # Disable KPROBES to prevent conflicts with the hookless implementation
    sed -i 's/CONFIG_KPROBES=y/# CONFIG_KPROBES is not set/' arch/arm64/configs/$DEFCONFIG

    if [ ! -d "KernelSU" ]; then
        echo "Fetching xxKSU..."
        curl -LSs "https://raw.githubusercontent.com/backslashxx/KernelSU/master/kernel/setup.sh" | bash -s master
    fi
else
    echo "KSU disabled"
    ZIP_NAME="Lavender_${DEVICE_NAME}_${DEVICE_MODEL}_$(date +%d%m%y-%H%M)"
    if [ -d "KernelSU" ]; then
        git reset HEAD --hard
    fi
fi

# Build Kernel
echo "Starting build for $DEVICE_MODEL..."
make $MAKE_PARAMS $DEFCONFIG
make $MAKE_PARAMS
make $MAKE_PARAMS INSTALL_MOD_PATH=modules_install INSTALL_MOD_STRIP=1 modules_install

# AnyKernel3 Packaging Logic
echo "Packaging with AnyKernel3..."
if [ ! -d "AnyKernel3" ]; then
    git clone https://github.com/LucasBlackLu/AnyKernel3 -b samsung
fi

cd AnyKernel3
git reset --hard HEAD
rm -rf modules/ Image dtb dtbo.img Lavender*

# 1. Copy Kernel Image (Prefer LZ4 if exists)
if [ -f "$OUT_DIR/arch/arm64/boot/Image.lz4" ]; then
    cp "$OUT_DIR/arch/arm64/boot/Image.lz4" .
elif [ -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
    cp "$OUT_DIR/arch/arm64/boot/Image" .
fi

# 2. CONCATENATE DTBS (Critical for S21 Boot)
find "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom" -name "*.dtb" -exec cat {} + > ./dtb

# 3. Copy DTBO
if [ -f "$OUT_DIR/arch/arm64/boot/dtbo.img" ]; then
    cp "$OUT_DIR/arch/arm64/boot/dtbo.img" .
fi

# 4. Copy Modules and Dependencies
mkdir -p modules/vendor/lib/modules
# Find the actual module directory (name varies by kernel version)
MOD_PATH=$(find "$OUT_DIR/modules_install/lib/modules" -mindepth 1 -maxdepth 1 -type d)
if [ -n "$MOD_PATH" ]; then
    cp "$MOD_PATH"/*.ko modules/vendor/lib/modules/ 2>/dev/null || true
    cp "$MOD_PATH"/modules.{alias,dep,softdep,symbols} modules/vendor/lib/modules/ 2>/dev/null || true
fi

# Zip
echo "Creating flashable zip: $ZIP_NAME.zip"
zip -r9 "../$ZIP_NAME.zip" . -x '*.git*' '*patch*' '*ramdisk*' 'LICENSE' 'README.md'
cd ..
echo "Build and packaging complete!"
