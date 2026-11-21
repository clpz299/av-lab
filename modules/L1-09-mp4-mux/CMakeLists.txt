cmake_minimum_required(VERSION 3.15)

# 模块：L1-09 MP4 文件生成与封装入门
# 产出：端到端封装/解封装脚本 + MP4 box 结构查看（无 C 工具，纯 ffmpeg/ffprobe 链路）

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-09.mp4_mux_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/mp4_mux_practice.ps1"
)
set_tests_properties(L1-09.mp4_mux_practice PROPERTIES TIMEOUT 300)
