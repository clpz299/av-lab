cmake_minimum_required(VERSION 3.15)

# 模块：L1-04 PCM 音频采样数据处理工具集
# 产出：单文件命令行工具 pcm_tools（6 个子命令）+ 端到端验证脚本

add_executable(pcm_tools src/pcm_tools.c)

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-04.pcm_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/pcm_practice.ps1"
            "$<TARGET_FILE:pcm_tools>"
)
set_tests_properties(L1-04.pcm_practice PROPERTIES TIMEOUT 300)
