cmake_minimum_required(VERSION 3.15)

# 模块：L1-02 ffmpeg / ffplay / ffprobe 命令行实战
# 产出（均为脚本类测试，无 C 目标）：
#   1) L1-02.cli_practice —— 生成测试源 -> ffprobe 探测 -> 分离提取 -> 缩放 -> 复核
#   2) L1-02.cheatsheet   —— 打印高频命令速查并正常退出

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

set(SCRIPTS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/scripts")

add_test(
    NAME L1-02.cli_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass -File "${SCRIPTS_DIR}/cli_practice.ps1"
)
set_tests_properties(L1-02.cli_practice PROPERTIES TIMEOUT 300)

add_test(
    NAME L1-02.cheatsheet
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass -File "${SCRIPTS_DIR}/cheatsheet.ps1"
)
