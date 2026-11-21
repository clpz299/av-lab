cmake_minimum_required(VERSION 3.15)

# 模块：L1-14 微信小程序音视频能力初探
# 产出：小程序 demo 工程（miniprogram/）+ 工程结构与配置契约校验脚本
# 依赖：PowerShell；不需要 ffmpeg / Node（真机推拉流需人工，详见 README）
# 说明：本模块没有 C/C++ 目标，测试为「工程结构 + 配置契约」级静态校验。

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-14.miniprogram_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/miniprogram_practice.ps1"
)
set_tests_properties(L1-14.miniprogram_practice PROPERTIES TIMEOUT 120)
