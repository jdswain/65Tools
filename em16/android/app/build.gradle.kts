// em16's Android app. The Oberon modules are compiled for Android by
// build-oberon.sh (compileOberon) and linked by CMake with em16's host C
// and the front end into libem16.so. The boot ROM and the SCSI disk come
// from an OS16 build (`make scsidisk` there): -Pos16Build=DIR, by default
// the OS16 checkout beside 65Tools. The SoC's text-mode font comes from
// the Verilog repository's ROM (-PverilogRom=DIR).

plugins {
    id("com.android.application")
}

val os16Build: String = (project.findProperty("os16Build") as String?)
    ?: file("../../../../OS16/build").absolutePath
val verilogRom: String = (project.findProperty("verilogRom") as String?)
    ?: file("../../../../Verilog65C816/fpga/rom").absolutePath
val oberonObjs = layout.buildDirectory.dir("intermediates/oberon-objs")
val em16Assets = layout.buildDirectory.dir("generated/em16-assets")

android {
    namespace = "com.oneav.em16"
    compileSdk = 35
    ndkVersion = "30.0.14904198"

    defaultConfig {
        applicationId = "com.oneav.em16"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
        ndk { abiFilters += "arm64-v8a" }
        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=none", "-DOBERON_OBJ_DIR=" + oberonObjs.get().asFile.absolutePath)
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    sourceSets["main"].assets.srcDir(em16Assets)

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

val compileOberon by tasks.registering(Exec::class) {
    commandLine("sh", file("../build-oberon.sh").absolutePath, oberonObjs.get().asFile.absolutePath)
    inputs.dir(file("../../src"))
    outputs.dir(oberonObjs)
}

val em16Disk by tasks.registering(Copy::class) {
    from(os16Build) { include("boot.rom", "scsidisk.img") }
    from(verilogRom) { include("font_st8x16.hex") }
    into(em16Assets)
    doFirst {
        if (!file("$os16Build/scsidisk.img").exists())
            throw GradleException("no $os16Build/scsidisk.img: make scsidisk in OS16, or -Pos16Build=DIR")
    }
}

tasks.matching { it.name.startsWith("configureCMake") || it.name.startsWith("buildCMake") || it.name.startsWith("externalNativeBuild") }
    .configureEach { dependsOn(compileOberon) }
tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }
    .configureEach { dependsOn(em16Disk) }
