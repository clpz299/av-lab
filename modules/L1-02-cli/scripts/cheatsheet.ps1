# cheatsheet.ps1 —— L1-02 命令速查（ffmpeg / ffprobe / ffplay 高频命令）
# 用途：作为读者的随手速查；也是文章「20 个高频命令」小节的代码化对照。
# 本脚本只打印命令清单，不实际执行（避免依赖具体文件/网络）。

$ErrorActionPreference = 'Stop'

function Section([string]$title) {
    Write-Host ""
    Write-Host "== $title ==" -ForegroundColor Cyan
}
function Cmd([string]$c, [string]$note) {
    Write-Host ("  {0,-72} {1}" -f $c, $note)
}

Section "ffprobe 探测信息"
Cmd 'ffprobe -v error -show_format -show_streams in.mp4'                '查看容器 + 全部流信息'
Cmd 'ffprobe -v error -show_entries format=duration,size -of csv=p=0 in.mp4' '只取时长与大小'
Cmd 'ffprobe -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 in.mp4' '取分辨率与帧率'
Cmd 'ffprobe -v error -show_entries stream=codec_type -of csv=p=0 in.mp4' '列出流类型（video/audio）'

Section "ffmpeg 转封装与剪切（-c copy 免重编码，快且无损）"
Cmd 'ffmpeg -i in.mp4 -c copy out.mkv'                                 '换容器（mp4 -> mkv）'
Cmd 'ffmpeg -i in.mp4 -ss 00:00:05 -t 10 -c copy clip.mp4'             '从第 5 秒起剪切 10 秒'
Cmd 'ffmpeg -i in.mp4 -map 0:v:0 -c copy -an video_only.mp4'           '只取视频流'
Cmd 'ffmpeg -i in.mp4 -map 0:a:0 -c copy -vn audio_only.m4a'           '只取音频流'

Section "ffmpeg 转码与滤镜"
Cmd 'ffmpeg -i in.mp4 -vf scale=640:360 -c:v libx264 -crf 23 out.mp4'  '缩放到 640x360 重编码'
Cmd 'ffmpeg -i in.mp4 -vf fps=10,scale=320:-1 out.gif'                 '导出 GIF（-1 表示等比）'
Cmd 'ffmpeg -f lavfi -i testsrc2=size=640x480:rate=25 -t 10 test.mp4'  '生成测试视频（无需素材）'
Cmd 'ffmpeg -f lavfi -i sine=frequency=440:sample_rate=44100 -t 5 tone.wav' '生成 440Hz 测试音'

Section "ffplay 播放（需图形界面）"
Cmd 'ffplay in.mp4'                                                    '播放本地文件'
Cmd 'ffplay -vf scale=1280:720 in.mp4'                                 '按分辨率播放（注意 -vf 后有空格）'
Cmd 'ffplay -x 800 -y 600 in.mp4'                                      '指定窗口大小'
Cmd 'ffplay -fs in.mp4'                                               '全屏播放'
Cmd 'ffplay -loop 0 in.gif'                                            '循环播放'
Cmd 'ffplay -ss 30 -autoexit in.mp4'                                   '从 30s 起播放，播完自动退出'
Cmd 'ffplay rtmp://host/app/stream'                                    '播放 RTMP 直播流（协议由 URL 前缀决定）'

Write-Host ""
Write-Host "cheatsheet OK" -ForegroundColor Green
exit 0
