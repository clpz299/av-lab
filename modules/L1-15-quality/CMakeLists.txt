cmake_minimum_required(VERSION 3.15)

# 模块：L1-15 客观质量指标计算：PSNR / SSIM / SNR
# 产出：单文件指标计算工具 quality_tools + 多码率评测 / 曲线脚本
# 依赖：ffmpeg/ffprobe（生成素材、转码与交叉验证）；C 工具本身只读 YUV420P

add_executable(quality_tools src/quality_tools.c)
# log10 在 mingw 下需要显式链接 libm
target_link_libraries(quality_tools m)

find_program(PWSH_EXE NAMES pwsh powershell)
if(NOT PWSH_EXE)
    message(WARNING "未找到 PowerShell，跳过脚本类测试")
    return()
endif()

add_test(
    NAME L1-15.quality_practice
    COMMAND ${PWSH_EXE} -NoProfile -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/scripts/quality_practice.ps1"
            "$<TARGET_FILE:quality_tools>"
)
set_tests_properties(L1-15.quality_practice PROPERTIES TIMEOUT 300)
