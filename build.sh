#!/usr/bin/env bash

set -eu

# ci redefined
BUILD_DIR=${BUILD_DIR:-build}
OUTPUT_DIR=${OUTPUT_DIR:-output}
VENV_DIR=${VENV_DIR:-venv}
ABI=${ABI:-rv64ilp32} # rv64 or rv64ilp32
BOARD=${BOARD:-canmv}
ARCH=${ARCH:-riscv}
CROSS_COMPILE=${CROSS_COMPILE:-riscv64-unknown-linux-gnu-}
RV64ILP32_TOOLCHAIN_HOME=${RV64ILP32_TOOLCHAIN_HOME:-"/opt/rv64ilp32/"}
UBOOT_RV64_REVERT_COMMIT=${UBOOT_RV64_REVERT_COMMIT:-"05c93ec8ffeeb5461f6c06b1f56b52607a699e19"}
TIMESTAMP=${TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}

CHROOT_TARGET=${CHROOT_TARGET:-target}
ROOTFS_IMAGE_SIZE=2G
ROOTFS_IMAGE_FILE="k230_root.ext4"

LINUX_BUILD=${LINUX_BUILD:-build}
OPENSBI_BUILD=${OPENSBI_BUILD:-build}
UBOOT_BUILD=${UBOOT_BUILD:-build-uboot}

mkdir -p ${BUILD_DIR} ${OUTPUT_DIR} ${CHROOT_TARGET}

OUTPUT_DIR=$(readlink -f ${OUTPUT_DIR})
SCRIPT_DIR=$(readlink -f $(dirname $0))

function build_linux() {
  OLD_PATH=$PATH
  OLD_CROSS_COMPILE=${CROSS_COMPILE}
  if [ "${ABI}" = "rv64ilp32" ]; then
    export PATH="${RV64ILP32_TOOLCHAIN_HOME}/riscv/bin:$PATH"
    export CROSS_COMPILE=riscv64-unknown-elf-
  fi
  pushd linux
  {
    if [ "${ABI}" = "rv64ilp32" ]; then
      make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${LINUX_BUILD} k230_evb_linux_enable_vector_defconfig 64ilp32.config
    else
      make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${LINUX_BUILD} k230_evb_linux_enable_vector_defconfig
    fi

    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${LINUX_BUILD} -j$(nproc) dtbs
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${LINUX_BUILD} -j$(nproc)

    cp -v ${LINUX_BUILD}/vmlinux ${OUTPUT_DIR}/vmlinux_${ABI}
    cp -v ${LINUX_BUILD}/arch/riscv/boot/Image ${OUTPUT_DIR}/Image_${ABI}
    cp -v Documentation/admin-guide/kdump/gdbmacros.txt ${OUTPUT_DIR}/gdbmacros_${ABI}.txt
    cp -v ${LINUX_BUILD}/arch/riscv/boot/dts/canaan/k230_evb.dtb ${OUTPUT_DIR}/k230_evb_${ABI}.dtb
    cp -v ${LINUX_BUILD}/arch/riscv/boot/dts/canaan/k230_canmv.dtb ${OUTPUT_DIR}/k230_canmv_${ABI}.dtb
  }
  popd
  export PATH=$OLD_PATH
  export CROSS_COMPILE=${OLD_CROSS_COMPILE}
}

function build_opensbi() {
  OLD_PATH=$PATH
  OLD_CROSS_COMPILE=${CROSS_COMPILE}
  if [ "${ABI}" = "rv64ilp32" ]; then
    export PATH="${RV64ILP32_TOOLCHAIN_HOME}/riscv/bin:$PATH"
    export CROSS_COMPILE=riscv64-unknown-elf-
  fi
  pushd opensbi
  {
    make \
      ARCH=${ARCH} \
      CROSS_COMPILE=${CROSS_COMPILE} \
      O=${OPENSBI_BUILD} \
      PLATFORM=generic \
      FW_PAYLOAD=y \
      FW_FDT_PATH=${OUTPUT_DIR}/k230_${BOARD}_${ABI}.dtb \
      FW_PAYLOAD_PATH=${OUTPUT_DIR}/Image_${ABI} \
      FW_TEXT_START=0x0 \
      -j $(nproc)
    cp -v ${OPENSBI_BUILD}/platform/generic/firmware/fw_payload.bin ${OUTPUT_DIR}/k230_${BOARD}_${ABI}.bin
  }
  popd
  export PATH=$OLD_PATH
  export CROSS_COMPILE=${OLD_CROSS_COMPILE}
}

function build_uboot() {
  python3 -m venv ${VENV_DIR}
  source ${VENV_DIR}/bin/activate
  pip install gmssl
  pushd uboot
  {
    if [ "${ABI}" = "rv64" ]; then
      sed -i "s/run rv64ilp32_k230/run rv64_k230/g" include/configs/k230_evb.h
    fi
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${UBOOT_BUILD} k230_${BOARD}_defconfig
    make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE} O=${UBOOT_BUILD} -j$(nproc)
    cp -av ${UBOOT_BUILD}/u-boot-spl-k230.bin ${OUTPUT_DIR}/u-boot-spl-k230_${BOARD}.bin
    cp -av ${UBOOT_BUILD}/fn_u-boot.img ${OUTPUT_DIR}/fn_u-boot_${BOARD}.img
    if [ "${ABI}" = "rv64" ]; then
      rm -rf include/configs/k230_evb.h
      git checkout include/configs/k230_evb.h
    fi
  }
  popd
  deactivate
}

function build_rootfs() {
  curl -o ${OUTPUT_DIR}/${ROOTFS_IMAGE_FILE} \
    https://openkoji.iscas.ac.cn/repos/fc38-rv32/qemu/root.ext4
}

function build_img() {
  genimage --config configs/${BOARD}_${ABI}.cfg \
    --inputpath "${OUTPUT_DIR}" \
    --outputpath "${OUTPUT_DIR}" \
    --rootpath="$(mktemp -d)"
}

function fix_permissions() {
  chown -R $USER ${OUTPUT_DIR}
}

function cleanup_build() {
  pushd ${SCRIPT_DIR}
  {
    mountpoint -q ${CHROOT_TARGET} && umount -l ${CHROOT_TARGET}
    rm -rvf ${OUTPUT_DIR} ${BUILD_DIR} ${CHROOT_TARGET}
    rm -rvf uboot/${UBOOT_BUILD} opensbi/${OPENSBI_BUILD} linux/${LINUX_BUILD}
    rm -rvf ${VENV_DIR}
  }
  popd
}

function usage() {
  echo "Usage: $0 build <target>"
  echo "Usage: $0 clean"
  echo "Here <target> can be: linux, opensbi, uboot, rootfs, img, linux_opensbi_uboot, all"
}

function fault() {
  usage
  exit 1
}

function main() {
  if [[ $# < 1 ]]; then
    fault
  fi

  if [ "$1" = "build" ]; then
    if [ "$2" = "linux" ]; then
      build_linux
    elif [ "$2" = "opensbi" ]; then
      build_opensbi
    elif [ "$2" = "uboot" ]; then
      build_uboot
    elif [ "$2" = "rootfs" ]; then
      build_rootfs
    elif [ "$2" = "img" ]; then
      build_img
    elif [ "$2" = "linux_opensbi_uboot" ]; then
      build_linux
      build_opensbi
      build_uboot
    elif [ "$2" = "all" ]; then
      build_linux
      build_opensbi
      build_uboot
      build_rootfs
      build_img
    else
      fault
    fi
  elif [ "$1" = "clean" ]; then
    cleanup_build
  else
    fault
  fi
}

main $@
