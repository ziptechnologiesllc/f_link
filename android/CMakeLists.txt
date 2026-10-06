cmake_minimum_required(VERSION 3.10)
project(abl_link_library LANGUAGES CXX)

set (LINK_DIR ${CMAKE_CURRENT_LIST_DIR}/../macos/link)

# For abl_link:
add_library(abl_link SHARED ${LINK_DIR}/extensions/abl_link/src/abl_link.cpp ${LINK_DIR}/extensions/abl_link/include/abl_link.h)
include(${LINK_DIR}/AbletonLinkConfig.cmake)
target_include_directories(abl_link PUBLIC ${LINK_DIR}/extensions/abl_link/include)
set_property(TARGET abl_link PROPERTY C_STANDARD 11)
target_link_libraries(abl_link Ableton::Link)

# ### Android specific: (These definitions could still be tweaked) ###
target_compile_definitions(abl_link PRIVATE ANDROID=1 LINK_PLATFORM_LINUX=1 PD=1 ABL_LINK_OFFSET_MS=23)
# ################################################################################


target_compile_definitions(abl_link PUBLIC DART_SHARED_LIB)

# ### Google Play 16 KB page-size requirement ###
# Play requires every native library in an app targeting Android 15+ to have
# PT_LOAD segments aligned to 16 KB (0x4000); this library was linking with
# align 0x1000. Applies to the 64-bit ABIs (arm64-v8a, x86_64) - the only ones
# where 16 KB devices exist - and is harmless for the others. NDK r28+ already
# defaults to this, but pin it explicitly so older/other NDKs can't regress it.
# Verify: llvm-readelf -lW libabl_link.so | grep LOAD   (Align must be 0x4000)
target_link_options(abl_link PRIVATE
  "-Wl,-z,max-page-size=16384"
  "-Wl,-z,common-page-size=16384")
