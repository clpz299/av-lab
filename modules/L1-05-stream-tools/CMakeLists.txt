cmake_minimum_required(VERSION 3.15)

# 模块：L1-05 视频码流分析工具入门
# 产出：单文件工具 h264_nalu（列出 Annex-B 裸流的 NALU）+ 端到端验证脚本

add_executable(h264_nalu src/h264_nalu.c)

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-05.stream_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/stream_practice.ps1"
            "$<TARGET_FILE:h264_nalu>"
)
set_tests_properties(L1-05.stream_practice PROPERTIES TIMEOUT 300)
