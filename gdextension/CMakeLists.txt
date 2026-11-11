cmake_minimum_required(VERSION 3.21)
project(engine_sim CXX)

# Build of the engine_sim GDExtension, same sources as SConstruct.
# Usage (Windows, from a Developer prompt or vcvars64):
#   cmake -S . -B build/cmake-dbg -G Ninja -DCMAKE_BUILD_TYPE=Debug
#   cmake --build build/cmake-dbg
# The DLL lands in bin/ with the name engine_sim.gdextension expects.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_subdirectory(godot-cpp)

# The exhaust convolver is a pure DSP inner loop over the whole impulse response (about 9,600 taps for
# a 219 ms recording), so it is optimised even in the Debug build: at /Od it would be the most expensive
# thing in the audio thread. MSVC refuses /O2 while /RTC1 is on, and the runtime checks are not worth an
# audio thread that cannot keep up, so the flag is dropped for this extension's debug builds only.
if(MSVC)
    string(REPLACE "/RTC1" "" CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}")
endif()
if(MSVC)
    set_source_files_properties(src/audio_convolver.cpp PROPERTIES COMPILE_OPTIONS "/O2")
endif()

add_library(engine_sim SHARED
    src/register_types.cpp
    src/cylinder_kernel.cpp
    # plain C++ physics (no Godot types)
    src/exhaust_gas.cpp
    src/intake_model.cpp
    src/turbo_model.cpp
    src/compressor_map.cpp
    src/friction_model.cpp
    src/isentropic_flow.cpp
    src/flame_model.cpp
    src/fuel_model.cpp
    src/firing_orders.cpp
    src/gearbox.cpp
    src/engine_metrics.cpp
    src/ecu_model.cpp
    # Godot wrappers
    src/exhaust_native.cpp
    src/firing_native.cpp
    src/fuel_native.cpp
    src/gearbox_native.cpp
    src/intake_native.cpp
    src/physics_misc_native.cpp
    src/ecu_native.cpp
    src/two_stroke_kernel.cpp
    src/audio_convolver.cpp
)

target_include_directories(engine_sim PRIVATE src include)
target_link_libraries(engine_sim PRIVATE godot::cpp)

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(GD_BUILD "template_debug")
else()
    set(GD_BUILD "template_release")
endif()
if(ANDROID)
    set(GD_PLATFORM "android")
    set(GD_ARCH "arm64")
else()
    set(GD_PLATFORM "windows")
    set(GD_ARCH "x86_64")
endif()

# ENGINE_SIM_OUT: where the DLL goes. Default is bin/ (what engine_sim.gdextension loads). Set it to a
# scratch folder when bin/ is in use by a running Godot process.
set(ENGINE_SIM_OUT "${CMAKE_SOURCE_DIR}/bin" CACHE PATH "DLL output folder")

set_target_properties(engine_sim PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${ENGINE_SIM_OUT}"
    LIBRARY_OUTPUT_DIRECTORY "${ENGINE_SIM_OUT}"
    OUTPUT_NAME "libengine_sim.${GD_PLATFORM}.${GD_BUILD}.${GD_ARCH}"
    PREFIX ""
)
