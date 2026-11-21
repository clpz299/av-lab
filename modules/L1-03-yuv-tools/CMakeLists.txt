cmake_minimum_required(VERSION 3.15)

# 模块：L1-03 RGB / YUV 像素数据处理工具集
# 产出：单文件命令行工具 yuv_tools（11 个子命令）+ 端到端验证脚本

add_executable(yuv_tools src/yuv_tools.c)
# log10 / pow 在 mingw 下需要显式链接 libm
target_link_libraries(yuv_tools m)

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-03.yuv_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/yuv_practice.ps1"
            "$<TARGET_FILE:yuv_tools>"
)
set_tests_properties(L1-03.yuv_practice PROPERTIES TIMEOUT 300)
