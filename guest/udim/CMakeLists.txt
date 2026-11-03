# udim.elf: the UDIM unpack algorithm of V-Sekai/fbx-udim-unpack as a godot-sandbox guest. Independent of usd.elf.
cmake_minimum_required(VERSION 3.16)
project(udim_guest C CXX)
set(SANDBOX_API "" CACHE PATH "godot-sandbox guest API checkout (contract-guest-runtime's sandbox-api)")
set(DOWNLOAD_RUNTIME_API OFF CACHE BOOL "" FORCE)
set(SANDBOX_RISCV_EXT_V OFF CACHE BOOL "" FORCE)
add_subdirectory(${SANDBOX_API}/cmake sandbox_api)
add_sandbox_program(udim main.cpp)
target_link_libraries(udim PRIVATE -lm -lstdc++)
