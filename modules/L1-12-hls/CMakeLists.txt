cmake_minimum_required(VERSION 3.15)

# 模块：L1-12 HLS 切片与 m3u8 播放实验
# 产出：HLS 切片脚本 + m3u8 解析小工具（无 C 工具，纯 ffmpeg/ffprobe 链路）

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-12.hls_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/hls_practice.ps1"
)
set_tests_properties(L1-12.hls_practice PROPERTIES TIMEOUT 300)
