cmake_minimum_required(VERSION 3.20)
project(engine_sim LANGUAGES CXX)

# Builds the engine_sim extension: the native Cylinder kernel (src/cylinder_kernel.cpp).
# Windows:  build_win.bat [template_debug|template_release]
# Android:  build_android.bat   (needs the Android NDK)
# src/cylinder.cpp and src/exhaust_gas.cpp are an older, unfinished port and are not built.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The template_debug library is what the editor and the headless tests load, and the simulation must not run at /Od there:
# optimise it too (this drops MSVC's run-time checks, which cannot be combined with /O2).
if(MSVC)
    string(REPLACE "/RTC1" "" CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}")
    string(REPLACE "/Od" "/O2" CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}")
endif()

add_subdirectory(godot-cpp)

add_library(engine_sim SHARED
    src/register_types.cpp
    src/cylinder_kernel.cpp
)
target_include_directories(engine_sim PRIVATE include)
target_link_libraries(engine_sim PRIVATE godot-cpp)

if(ES_TARGET_OVERRIDE)
    set(ES_TARGET "${ES_TARGET_OVERRIDE}")
elseif(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(ES_TARGET "template_release")
else()
    set(ES_TARGET "template_debug")
endif()

if(ANDROID)
    set(ES_PLATFORM "android")
    set(ES_ARCH "arm64")
else()
    set(ES_PLATFORM "windows")
    set(ES_ARCH "x86_64")
endif()

# Names match the paths in engine_sim.gdextension.
set_target_properties(engine_sim PROPERTIES
    PREFIX ""
    OUTPUT_NAME "libengine_sim.${ES_PLATFORM}.${ES_TARGET}.${ES_ARCH}"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin"
)
