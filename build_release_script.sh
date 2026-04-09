#!/bin/bash

DEVICE_MODEL="SM-G9910"
DEVICE_NAME="o1q"
DEFCONFIG_NAME="o1q_chn_hkx_defconfig"
DEFCONFIG_PATH="arch/arm64/configs/vendor/$DEFCONFIG_NAME"

SRC_DIR=$(pwd)
TC_DIR=${CLANG_PATH:-$SRC_DIR/clang}
JOBS="$(nproc --all)"

MAKE_PARAMS="-j$JOBS -C $SRC_DIR O=$SRC_DIR/out ARCH=arm64 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-"
export PATH="$TC_DIR/bin:$PATH"

find "$SRC_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} +
[ -f "$SRC_DIR/scripts/secgetspf" ] && chmod +x "$SRC_DIR/scripts/secgetspf"

if [[ "$*" == *"--ksu"* ]]; then
    KSU=true
    ZIP_NAME="Midori_KSU_${DEVICE_NAME}_$(date +%d%m%y-%H%M)"
    
    if [ ! -d "KernelSU" ]; then
        curl -LSs "https://raw.githubusercontent.com/backslashxx/KernelSU/master/kernel/setup.sh" | bash -s master
    fi

    for cfg in CONFIG_KSU CONFIG_KSU_EXTRAS CONFIG_KSU_TAMPER_SYSCALL_TABLE \
               CONFIG_KSU_LSM_SECURITY_HOOKS CONFIG_KSU_THRONE_TRACKER_ALWAYS_THREADED; do
        sed -i "/$cfg/d" "$DEFCONFIG_PATH"
        echo "$cfg=y" >> "$DEFCONFIG_PATH"
    done
else
    KSU=false
    ZIP_NAME="Midori_${DEVICE_NAME}_$(date +%d%m%y-%H%M)"
    git checkout "$DEFCONFIG_PATH" 2>/dev/null
fi

mkdir -p "$SRC_DIR/out"

make $MAKE_PARAMS "vendor/$DEFCONFIG_NAME" || exit 1
make $MAKE_PARAMS || exit 1
make $MAKE_PARAMS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install || exit 1

if [ ! -d "AnyKernel3" ]; then
    git clone https://github.com/LucasBlackLu/AnyKernel3 -b samsung
else
    cd AnyKernel3 && git reset HEAD --hard && cd ..
fi

MODULES_STAGING="AnyKernel3/modules/vendor/lib/modules"
rm -rf AnyKernel3/modules/
mkdir -p "$MODULES_STAGING"

find "$SRC_DIR/out/modules" -type f -iname "*.ko" -exec cp {} "$MODULES_STAGING/" \;
cp out/arch/arm64/boot/Image AnyKernel3/
[ -f out/arch/arm64/boot/dtbo.img ] && cp out/arch/arm64/boot/dtbo.img AnyKernel3/

cd AnyKernel3
rm -rf Midori*
zip -r9 "../${ZIP_NAME}.zip" . -x '*.git*' '*patch*' '*ramdisk*' 'LICENSE' 'README.md'
cd ..
