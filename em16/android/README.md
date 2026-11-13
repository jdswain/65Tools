# em16 on Android

OS16 on the emulated PC16 SoC, on an Android phone or tablet: the
1024 x 768 framebuffer, booted from a SCSI disk with no floppy, a
keyboard and a mouse as the SoC's ADB keyboard and mouse, and the
network through em16's own NAT (`-net nat`, `../src/EmNat.c`). What
`../mac/` is on the Mac.

    make scsidisk           in OS16: build/scsidisk.img, the whole system
    ./gradlew assembleDebug app/build/outputs/apk/debug/app-debug.apk
    adb install -r app/build/outputs/apk/debug/app-debug.apk

Gradle needs a JDK 17 or later (`JAVA_HOME`, Android Studio's
`Contents/jbr/Contents/Home`) and the SDK in `local.properties`
(`sdk.dir=`), with the NDK of `app/build.gradle.kts`' `ndkVersion`.

- `build-oberon.sh` compiles em16's modules (`../src`) and the oc
  runtime's that they import for `aarch64-linux-android26` with oc
  (`../../../oc/bin/oc`, or `OC=`), and the LLVM that oc writes with
  the NDK's clang at -O2, as the Mac's Makefile does. Gradle runs it
  (`compileOberon`) before CMake.
- `app/src/main/cpp/CMakeLists.txt` links them into `libem16.so` with
  em16's C in `../src` (the host, the network and the NAT), the oc
  runtime's C (its ARC core, POSIX Files, Env's arguments) and the front
  end, `EmAndroid.c`, a NativeActivity on the NDK's native_app_glue.
- The APK carries the boot ROM and the disk from an OS16 build
  (`-Pos16Build=DIR`, by default `../../../OS16/build`) and the SoC's
  text-mode font from the Verilog repository (`-PverilogRom=DIR`). The
  first start copies them into the app's files; the disk is kept from
  then on, the guest's writes with it. Clearing the app's storage gives
  a new disk.

## The front end

`EmAndroid.c` runs em16 as `em16 -fpga -video -bootrom boot.rom -scsi
scsidisk.img -net nat -font font_st8x16.hex`: Em16 on a thread of its
own, whose `EmHost.RunVideo` runs the CPU there, paced to real time. The
activity's thread draws the framebuffer when the guest has changed it,
4 bits a pixel through the palette (or text mode's cells), letterboxed to
the screen's shape.

- Keys: a physical keyboard's, as an ADB keyboard's codes (an extended
  keyboard's right-hand modifiers); Meta is Command, Alt Option; F12 is
  the power key, as on the Mac. Back is taken, so that the machine is
  not left by accident; Home leaves it running.
- A mouse: captured while the window has the focus (`Em16Activity`,
  `View.requestPointerCapture`), its moves the device's own as an ADB
  mouse's (the guest's InputManager accelerates), its primary button
  the mouse's button.
- A finger: a trackpad. Moved, it moves the pointer; tapped, it clicks;
  held still for 0.4 s, the button is held until it is lifted, and the
  finger's moves meanwhile drag (a menu pulled down, a window moved).
- Standard output and error go to the log: `adb logcat -s em16`.

The activity's end ends the process, so a new start is a new machine
(Em16's modules initialised afresh); the disk's writes are in the file
already.
