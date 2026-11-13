#!/bin/sh
# build-oberon.sh OBJDIR: em16's Oberon modules (../src) and the oc
# runtime's that they import (Errors, Env, Files), compiled for Android
# (aarch64-linux-android26) into OBJDIR: oc writes each module's LLVM,
# which the NDK's clang compiles with -O2, as the Mac's Makefile does
# (the compiler's own objects are not optimised). The sources are copied
# to OBJDIR first, so that neither the oc checkout's runtime nor ../src
# gets objects for another target.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OBJ=${1:?usage: build-oberon.sh OBJDIR}
OC=${OC:-$HERE/../../../../oc/bin/oc}
RT=$(cd "$(dirname "$OC")/../runtime/android" && pwd)
NDK=${ANDROID_NDK_HOME:-$(ls -d "$HOME"/Library/Android/sdk/ndk/* | sort -V | tail -1)}
CLANG=$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang
TRIPLE=aarch64-linux-android26
MODS="EmHost EmSym EmUART EmVIA EmFDC Em82077 EmSCSI EmEth EmL28 EmVideo EmLCD EmCore EmSDRAM EmSCC EmADB EmBlit EmSD EmPower EmRTC EmDMA EmTimer EmSoC EmMem EmCPU EmLoad EmHarte Em16"
mkdir -p "$OBJ"
cp "$RT/Errors.Mod" "$RT/Env.Mod" "$RT/Files.Mod" "$OBJ/"
for m in $MODS; do cp "$HERE/../src/$m.Mod" "$OBJ/"; done
cd "$OBJ"
for m in Errors Env Files $MODS; do
  "$OC" -target $TRIPLE -s $m.Mod > $m.log 2>&1 || { cat $m.log; exit 1; }
  "$CLANG" --target=$TRIPLE -O2 -fPIC -Wno-override-module -c $m.ll -o $m.o
done
echo "build-oberon: $(ls *.o | wc -l | tr -d ' ') objects in $OBJ"
