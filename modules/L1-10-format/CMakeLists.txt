cmake_minimum_required(VERSION 3.15)

# 模块：L1-10 常见音视频格式识别与转换
# 产出：格式识别 + 无损转封装矩阵 + 三个格式坑（纯 ffmpeg/ffprobe 链路，无 C 工具）

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-10.format_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/format_practice.ps1"
)
set_tests_properties(L1-10.format_practice PROPERTIES TIMEOUT 300)
