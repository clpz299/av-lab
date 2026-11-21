cmake_minimum_required(VERSION 3.15)

# 模块：L1-06 图片与视频互转、视频转 GIF
# 产出：端到端验证脚本（无 C 工具，纯 ffmpeg 命令行链路）

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-06.image_video_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/image_video_practice.ps1"
)
set_tests_properties(L1-06.image_video_practice PROPERTIES TIMEOUT 300)
