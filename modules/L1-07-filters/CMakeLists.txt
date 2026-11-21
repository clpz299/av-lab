cmake_minimum_required(VERSION 3.15)

# 模块：L1-07 FFmpeg 滤镜入门：水印 / 裁剪 / 画中画 / 多宫格
# 产出：端到端验证脚本（无 C 工具，纯 ffmpeg 滤镜命令行链路）

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-07.filter_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/filter_practice.ps1"
)
set_tests_properties(L1-07.filter_practice PROPERTIES TIMEOUT 300)
