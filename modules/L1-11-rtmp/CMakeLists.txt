cmake_minimum_required(VERSION 3.15)

# 模块：L1-11 直播/点播概念与推拉流初体验
# 产出：本地 RTMP 服务（ffmpeg listen 模式）+ 推流/拉流/中继脚本 + nginx-rtmp.conf 参考配置（无 C 工具）

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-11.rtmp_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/rtmp_practice.ps1"
)
set_tests_properties(L1-11.rtmp_practice PROPERTIES TIMEOUT 300)
