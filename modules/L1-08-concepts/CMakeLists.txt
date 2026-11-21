cmake_minimum_required(VERSION 3.15)

# 模块：L1-08 音视频核心概念实验：帧率 / 码率 / 分辨率 / GOP
# 产出：端到端压测脚本 + 结果表格（无 C 工具，纯 ffmpeg 单变量对照实验）

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-08.concepts_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/concepts_practice.ps1"
)
set_tests_properties(L1-08.concepts_practice PROPERTIES TIMEOUT 300)
