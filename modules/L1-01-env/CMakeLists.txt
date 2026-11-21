cmake_minimum_required(VERSION 3.15)

# 模块：L1-01 音视频开发环境搭建
# 产出：
#   1) hello_env       —— 由本工程工具链编译运行的 C 程序（验证编译器可用）
#   2) L1-01.env_check —— 校验 gcc/cmake/ffmpeg 三件套版本
#   3) L1-01.convert   —— 首个转换实验：ffmpeg 生成测试 MP4 -> 转 GIF -> ffprobe 校验

add_executable(hello_env src/hello_env.c)
add_test(NAME L1-01.hello_env COMMAND hello_env)

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

set(SCRIPTS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/scripts")

add_test(
    NAME L1-01.env_check
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass -File "${SCRIPTS_DIR}/env_check.ps1"
)

add_test(
    NAME L1-01.convert
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass -File "${SCRIPTS_DIR}/first_conversion.ps1"
)
set_tests_properties(L1-01.convert PROPERTIES TIMEOUT 300)

# L1-01 扩展：从零编译 FFmpeg 的脚本契约 + 本机环境自检（不做真正编译）
add_test(
    NAME L1-01.srcbuild_check
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass -File "${SCRIPTS_DIR}/srcbuild_check.ps1"
)
set_tests_properties(L1-01.srcbuild_check PROPERTIES TIMEOUT 60)
