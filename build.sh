#!/bin/bash

## DEVICE STUFF
DEVICE_HARDWARE="sm8350"
DEVICE_MODEL="$1"
ZIP_DIR="$(pwd)/AnyKernel3"
MOD_DIR="$ZIP_DIR/modules/vendor/lib/modules"
K_MOD_DIR="$(pwd)/out/modules"

# Enviorment Variables
SRC_DIR=$(pwd)
TC_DIR=${CLANG_PATH:-$(pwd)/clang}
JOBS="$(nproc --all)"
MAKE_PARAMS="-j$JOBS -C $SRC_DIR O=$SRC_DIR/out ARCH=arm64 CC=clang CLANG_TRIPLE=$TC_DIR/bin/aarch64-linux-gnu- LLVM=1 CROSS_COMPILE=$TC_DIR/bin/llvm-"
export PATH="$TC_DIR/bin:$PATH"

if [ "$DEVICE_MODEL" == "SM-G9910" ]; then
    DEVICE_NAME="o1q"
    DEFCONFIG=o1q_defconfig
elif [ "$DEVICE_MODEL" == "SM-G9960" ]; then
    DEVICE_NAME="t2q"
    DEFCONFIG=t2q_defconfig
elif [ "$DEVICE_MODEL" == "SM-G9980" ]; then
    DEVICE_NAME="p3q"
    DEFCONFIG=p3q_defconfig
elif [ "$DEVICE_MODEL" == "SM-G990B" ]; then
    DEVICE_NAME="r9q"
    DEFCONFIG=r9q_defconfig
elif [ "$DEVICE_MODEL" == "SM-G990B2" ]; then
    DEVICE_NAME="r9q2"
    DEFCONFIG=r9q2_defconfig # Removed the leading slash typo
else
    echo "Config not found"
    exit
fi

# Check if KSU flag is provided
if [[ "$*" == *"--ksu"* ]]; then
    KSU="true"
else
    KSU="false"
fi

# Check the value of KSU
if [ "$KSU" == "true" ]; then
    ZIP_NAME="Midori_KSU_"$DEVICE_NAME"_"$DEVICE_MODEL"_"$(date +%d%m%y-%H%M)""

    if [ -d "KernelSU" ]; then
        echo "KernelSU exists"
    else
        echo "KernelSU not found !"
        echo "Fetching ...."
        curl -LSs "https://raw.githubusercontent.com/azkx/KernelSU/main/kernel/setup.sh" | bash -s main
    fi

    # Inject xxKSU configs — pure manual hooks (KProbes disabled)
    # CONFIG_KSU_TAMPER_SYSCALL_TABLE is for <=4.14 only, not needed on sm8350 (5.4)
    # CONFIG_KSU_LSM_SECURITY_HOOKS not set — using manual hook patches instead
    echo "CONFIG_KSU=y"                                >> arch/arm64/configs/$DEFCONFIG
    echo "# CONFIG_KSU_LSM_SECURITY_HOOKS is not set"  >> arch/arm64/configs/$DEFCONFIG
    echo "CONFIG_KSU_EXTRAS=y"                         >> arch/arm64/configs/$DEFCONFIG
    echo "CONFIG_KSU_THRONE_TRACKER_ALWAYS_THREADED=y" >> arch/arm64/configs/$DEFCONFIG
    sed -i 's/CONFIG_KPROBES=y/# CONFIG_KPROBES is not set/' arch/arm64/configs/$DEFCONFIG

    # Apply xxKSU manual hook patches
    PATCH_BASE="https://raw.githubusercontent.com/yapixel/kernel_patches/dev/midorisu"
    echo "Applying xxKSU manual hook patches..."

    curl -sSL "$PATCH_BASE/manual-security-hooks-v1.8.patch" -o /tmp/manual-security-hooks-v1.8.patch
    patch -p1 -d "$SRC_DIR" --fuzz=3 --ignore-whitespace < /tmp/manual-security-hooks-v1.8.patch || {
        echo "ERROR: manual-security-hooks-v1.8.patch failed, aborting!" >&2
        exit 1
    }
    echo "Applied: manual-security-hooks-v1.8.patch"

    curl -sSL "$PATCH_BASE/scope-min-manual-hooks-v1.9.patch" -o /tmp/scope-min-manual-hooks-v1.9.patch
    patch -p1 -d "$SRC_DIR" --fuzz=3 --ignore-whitespace < /tmp/scope-min-manual-hooks-v1.9.patch || {
        echo "ERROR: scope-min-manual-hooks-v1.9.patch failed, aborting!" >&2
        exit 1
    }
    echo "Applied: scope-min-manual-hooks-v1.9.patch"

elif [ "$KSU" == "false" ]; then
    echo "KSU disabled"
    ZIP_NAME="Midori_"$DEVICE_NAME"_"$DEVICE_MODEL"_"$(date +%d%m%y-%H%M)""
    if [ -d "KernelSU" ]; then
        git reset HEAD --hard
    fi
fi

cat <<EOF >> arch/arm64/configs/$DEFCONFIG
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_IP_SET=y
CONFIG_NETFILTER_XT_SET=y
CONFIG_IP_SET_MAX=65534
CONFIG_IP_SET_BITMAP_IP=y
CONFIG_IP_SET_BITMAP_IPMAC=y
CONFIG_IP_SET_BITMAP_PORT=y
CONFIG_IP_SET_HASH_IP=y
CONFIG_IP_SET_HASH_IPMARK=y
CONFIG_IP_SET_HASH_IPPORT=y
CONFIG_IP_SET_HASH_IPPORTIP=y
CONFIG_IP_SET_HASH_IPPORTNET=y
CONFIG_IP_SET_HASH_IPMAC=y
CONFIG_IP_SET_HASH_MAC=y
CONFIG_IP_SET_HASH_NETPORTNET=y
CONFIG_IP_SET_HASH_NET=y
CONFIG_IP_SET_HASH_NETNET=y
CONFIG_IP_SET_HASH_NETPORT=y
CONFIG_IP_SET_HASH_NETIFACE=y
CONFIG_IP_SET_LIST_SET=y
EOF

make $MAKE_PARAMS $DEFCONFIG
make $MAKE_PARAMS
make $MAKE_PARAMS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install

if [ -d "AnyKernel3" ]; then
    cd AnyKernel3
    git reset HEAD --hard
    cd ..
    if [ -d "AnyKernel3/modules" ]; then
        rm -rf AnyKernel3/modules/
        mkdir AnyKernel3/modules/
        mkdir AnyKernel3/modules/vendor/
        mkdir AnyKernel3/modules/vendor/lib
        mkdir AnyKernel3/modules/vendor/lib/modules/
    else
        mkdir AnyKernel3/modules/
        mkdir AnyKernel3/modules/vendor/
        mkdir AnyKernel3/modules/vendor/lib
        mkdir AnyKernel3/modules/vendor/lib/modules/
    fi
    find "$(pwd)/out/modules" -type f -iname "*.ko" -exec cp -r {} ./AnyKernel3/modules/vendor/lib/modules/ \;
    cp ./out/arch/arm64/boot/Image ./AnyKernel3/
    cp ./out/arch/arm64/boot/dtbo.img ./AnyKernel3/
    cd AnyKernel3
    rm -rf Midori*
    zip -r9 $ZIP_NAME . -x '*.git*' '*patch*' '*ramdisk*' 'LICENSE' 'README.md'
    cd ..
else
    git clone https://github.com/midori01/AnyKernel3 -b samsung
    if [ -d "AnyKernel3/modules" ]; then
        rm -rf AnyKernel3/modules/
        mkdir AnyKernel3/modules/
        mkdir AnyKernel3/modules/vendor/
        mkdir AnyKernel3/modules/vendor/lib
        mkdir AnyKernel3/modules/vendor/lib/modules/
    else
        mkdir AnyKernel3/modules/
        mkdir AnyKernel3/modules/vendor/
        mkdir AnyKernel3/modules/vendor/lib
        mkdir AnyKernel3/modules/vendor/lib/modules/
    fi
    find "$(pwd)/out/modules" -type f -iname "*.ko" -exec cp -r {} ./AnyKernel3/modules/vendor/lib/modules/ \;
    cp ./out/arch/arm64/boot/Image ./AnyKernel3/
    cp ./out/arch/arm64/boot/dtbo.img ./AnyKernel3/
    cd AnyKernel3
    rm -rf Midori*
    zip -r9 $ZIP_NAME . -x '*.git*' '*patch*' '*ramdisk*' 'LICENSE' 'README.md'
    cd ..
fi
