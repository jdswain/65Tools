# CMakeLists.txt - em16's native library, libem16.so: the Oberon modules
# that build-oberon.sh compiled for Android (OBERON_OBJ_DIR, the Gradle
# task compileOberon), the oc runtime's C (the ARC core, POSIX Files,
# Env's arguments), em16's host C shared with the Mac (../../../../../src:
# disks, clock, network and NAT, font) and the Android front end
# (EmAndroid.c, on the NDK's native_app_glue).

cmake_minimum_required(VERSION 3.22.1)
project(em16 LANGUAGES C)

set(EM16_SRC "${CMAKE_SOURCE_DIR}/../../../../../src")
set(OC_REPO "${CMAKE_SOURCE_DIR}/../../../../../../../../oc" CACHE PATH "the oc checkout")
set(OBERON_OBJ_DIR "" CACHE PATH "build-oberon.sh's objects")

file(GLOB OBERON_OBJS "${OBERON_OBJ_DIR}/*.o")
if(NOT OBERON_OBJS)
  message(FATAL_ERROR "no Oberon objects in ${OBERON_OBJ_DIR}: the compileOberon task runs first")
endif()

add_library(native_app_glue STATIC ${ANDROID_NDK}/sources/android/native_app_glue/android_native_app_glue.c)
target_include_directories(native_app_glue PUBLIC ${ANDROID_NDK}/sources/android/native_app_glue)

add_library(em16 SHARED
  EmAndroid.c
  ${EM16_SRC}/EmHost_rt.c
  ${EM16_SRC}/EmNet_rt.c
  ${EM16_SRC}/EmNat.c
  ${EM16_SRC}/EmFont.c
  ${OC_REPO}/runtime/android/runtime.c
  ${OC_REPO}/runtime/android/Files_rt.c
  ${OC_REPO}/runtime/posix/Env_rt.c
  ${OBERON_OBJS})

target_compile_options(em16 PRIVATE -O2 -Wall -Wno-unused-parameter)
# ANativeActivity_onCreate is the glue's, and must be exported
set_target_properties(em16 PROPERTIES LINK_FLAGS "-u ANativeActivity_onCreate")
target_link_libraries(em16 native_app_glue android log m)
