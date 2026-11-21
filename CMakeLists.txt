cmake_minimum_required(VERSION 3.15)
project(av_lab LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 统一输出目录，避免每个模块内部散落
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

enable_testing()

# 各选题模块（每新增一个模块在此注册）
add_subdirectory(modules/L1-01-env)
add_subdirectory(modules/L1-02-cli)
add_subdirectory(modules/L1-03-yuv-tools)
add_subdirectory(modules/L1-04-pcm-tools)
add_subdirectory(modules/L1-05-stream-tools)
add_subdirectory(modules/L1-06-media-convert)
add_subdirectory(modules/L1-07-filters)
add_subdirectory(modules/L1-08-concepts)
add_subdirectory(modules/L1-09-mp4-mux)
add_subdirectory(modules/L1-10-format)
add_subdirectory(modules/L1-11-rtmp)
add_subdirectory(modules/L1-12-hls)
add_subdirectory(modules/L1-13-webrtc)
add_subdirectory(modules/L1-14-miniprogram)
add_subdirectory(modules/L1-15-quality)
