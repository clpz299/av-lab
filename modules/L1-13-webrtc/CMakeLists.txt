cmake_minimum_required(VERSION 3.15)

# 模块：L1-13 WebRTC 快速上手：浏览器 1v1 通话 Demo
# 产出：零依赖信令服务器(signal_server.js) + 前端 demo(web/) + Node 测试
# 依赖：Node.js（内置 WebSocket 客户端）；端到端测试另需 Chromium 系浏览器（缺失则跳过）
# 说明：本模块没有 C/C++ 目标，测试全部由 PowerShell 驱动 Node 脚本完成。

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

find_program(NODE_EXE NAMES node)
if(NOT NODE_EXE)
    message(WARNING "未找到 Node.js，跳过 L1-13 WebRTC 测试")
    return()
endif()

add_test(
    NAME L1-13.webrtc_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/webrtc_practice.ps1"
)
set_tests_properties(L1-13.webrtc_practice PROPERTIES TIMEOUT 300)
