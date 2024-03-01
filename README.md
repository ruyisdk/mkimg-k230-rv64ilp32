# Introduction

This builds Linux with rv64ilp32 for trying on K230 devices.

# Preparations

Please prepare toolchain, source tree and host packages before building.

## Toolchain preparation

Please get the [rv64ilp32 toolchain](https://github.com/ruyisdk/riscv-gnu-toolchain-rv64ilp32/releases) and unpack it in a folder, let's assume environment variable `RV64ILP32_TOOLCHAIN_HOME` points to that folder:

```
$ export RV64ILP32_TOOLCHAIN_HOME=<toolchain-install-root>
$ ls -F $RV64ILP32_TOOLCHAIN_HOME
riscv/
```

Please note that the `riscv64-unknown-linux-gnu-` toolchain is needed to build U-Boot, it can be from the [mainline toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2023.10.18/riscv64-glibc-ubuntu-22.04-gcc-nightly-2023.10.18-nightly.tar.gz). Let's assume this toolchain is available at folder specified by `MAINLINE` environment variable.

## Source tree preparation

Before building, please run the following commands to fetch the submodule sources:

```
$ git submodule update --init --recursive
```

## Host packages

The following host packages are also needed on Ubuntu:

```
$ sudo apt install libssl-dev mtools python3.10-venv
```

The [genimage tool](https://github.com/pengutronix/genimage/releases) is also needed. It can be build with the host C compiler like below:

```
$ cd genimage-17
$ ./configure
$ make
$ sudo make install
$ genimage -h
```

# Build

Run `build.sh` in top folder to see the list of targets:

```
PATH=$MAINLINE/bin:$PATH ./build.sh
```

The final image will be available in `output/` folder, which can be used on CanMV-K230 device. Read `build.sh` for more usage tips.
