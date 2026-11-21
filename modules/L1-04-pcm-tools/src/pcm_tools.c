/*
 * pcm_tools.c —— L1-04 PCM 音频采样数据处理工具集
 *
 * 单文件实现，依据素材 article/021《视音频数据处理：PCM音频采样数据处理》整理。
 * 采样格式统一为 PCM16LE（16bit、Little Endian、有符号、交错存储）。
 *
 * 用法： pcm_tools <command> [args...]
 *   split_lr    <in.pcm> <out_l.pcm> <out_r.pcm>            分离左右声道
 *   half_left   <in.pcm> <out.pcm>                          左声道音量减半
 *   doublespeed <in.pcm> <out.pcm>                          抽奇数帧 -> 速度翻倍
 *   to_pcm8     <in.pcm> <out.pcm>                          PCM16LE -> PCM8
 *   cut_mono    <in.pcm> <start> <dur> <out.pcm> <out.txt>  单声道截取 + 样值清单
 *   to_wave     <in.pcm> <channels> <sample_rate> <out.wav> 封装为 WAVE
 *
 * 与素材的差异（作为踩坑对照，实现上取正确写法）：
 *   1) 素材用 while(!feof(fp)) 读循环，会在末尾多处理一次样值；本实现改为「先读后判」；
 *   2) 素材 WAVE_FMT.dwAvgBytesPerSec = 采样率 * sizeof(short)，漏乘声道数；本实现修正为
 *      采样率 * 声道数 * 2；
 *   3) 素材截取函数每 10 个样值写一次换行时把样值也一并写进了换行语句；本实现分开写。
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------- 基础辅助 ---------- */

static void die(const char *msg, const char *path) {
    fprintf(stderr, "ERROR: %s%s%s\n", msg, path ? ": " : "", path ? path : "");
    exit(2);
}

static FILE *open_r(const char *p) {
    FILE *f = fopen(p, "rb");
    if (!f) die("无法打开输入文件", p);
    return f;
}

static FILE *open_w(const char *p) {
    FILE *f = fopen(p, "wb");
    if (!f) die("无法创建输出文件", p);
    return f;
}

/* ---------- (1) 分离 PCM16LE 双声道左右声道 ---------- */

static int pcm16le_split(const char *url, const char *outL, const char *outR) {
    FILE *fp  = open_r(url);
    FILE *fp1 = open_w(outL);
    FILE *fp2 = open_w(outR);

    short frame[2];
    long cnt = 0;
    while (fread(frame, sizeof(short), 2, fp) == 2) {
        fwrite(&frame[0], sizeof(short), 1, fp1); /* L */
        fwrite(&frame[1], sizeof(short), 1, fp2); /* R */
        cnt++;
    }

    fclose(fp); fclose(fp1); fclose(fp2);
    printf("split_lr: %ld frames -> %s | %s\n", cnt, outL, outR);
    return 0;
}

/* ---------- (2) 左声道音量减半 ---------- */

static int pcm16le_half_left(const char *url, const char *out) {
    FILE *fp  = open_r(url);
    FILE *fp1 = open_w(out);

    short frame[2];
    long cnt = 0;
    while (fread(frame, sizeof(short), 2, fp) == 2) {
        frame[0] = (short)(frame[0] / 2); /* L 减半，R 不动 */
        fwrite(frame, sizeof(short), 2, fp1);
        cnt++;
    }

    fclose(fp); fclose(fp1);
    printf("half_left: %ld frames -> %s\n", cnt, out);
    return 0;
}

/* ---------- (3) 抽奇数帧 -> 速度翻倍 ---------- */

static int pcm16le_doublespeed(const char *url, const char *out) {
    FILE *fp  = open_r(url);
    FILE *fp1 = open_w(out);

    short frame[2];
    long cnt = 0, kept = 0;
    while (fread(frame, sizeof(short), 2, fp) == 2) {
        if (cnt % 2 != 0) {              /* 保留第 1、3、5... 帧 */
            fwrite(frame, sizeof(short), 2, fp1);
            kept++;
        }
        cnt++;
    }

    fclose(fp); fclose(fp1);
    printf("doublespeed: %ld frames -> %ld frames\n", cnt, kept);
    return 0;
}

/* ---------- (4) PCM16LE -> PCM8 ---------- */

static int pcm16le_to_pcm8(const char *url, const char *out) {
    FILE *fp  = open_r(url);
    FILE *fp1 = open_w(out);

    short frame[2];
    unsigned char out8[2];
    long cnt = 0;
    while (fread(frame, sizeof(short), 2, fp) == 2) {
        /* 16bit 有符号 (-32768~32767) -> 8bit 有符号 (-128~127) -> 8bit 无符号 (0~255) */
        out8[0] = (unsigned char)((frame[0] >> 8) + 128);
        out8[1] = (unsigned char)((frame[1] >> 8) + 128);
        fwrite(out8, 1, 2, fp1);
        cnt++;
    }

    fclose(fp); fclose(fp1);
    printf("to_pcm8: %ld frames -> %s (%ld bytes)\n", cnt, out, cnt * 2);
    return 0;
}

/* ---------- (5) 单声道 PCM16LE 截取 ---------- */

static int pcm16le_cut_mono(const char *url, long start_num, long dur_num,
                            const char *outPcm, const char *outTxt) {
    FILE *fp     = open_r(url);
    FILE *fp1    = open_w(outPcm);
    FILE *fpStat = open_w(outTxt);

    short s;
    long cnt = 0, cut = 0, col = 0;
    while (fread(&s, sizeof(short), 1, fp) == 1) {
        if (cnt > start_num && cnt <= start_num + dur_num) {
            fwrite(&s, sizeof(short), 1, fp1);
            fprintf(fpStat, "%6d,", s);
            if (++col % 10 == 0) fprintf(fpStat, "\n");
            cut++;
        }
        cnt++;
    }

    fclose(fp); fclose(fp1); fclose(fpStat);
    printf("cut_mono: total=%ld cut=%ld -> %s\n", cnt, cut, outPcm);
    return 0;
}

/* ---------- (6) PCM16LE -> WAVE ---------- */

static void put_u32le(unsigned char *p, unsigned int v) {
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
    p[2] = (unsigned char)((v >> 16) & 0xFF);
    p[3] = (unsigned char)((v >> 24) & 0xFF);
}

static void put_u16le(unsigned char *p, unsigned short v) {
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
}

static int pcm16le_to_wave(const char *pcmpath, int channels, int sample_rate, const char *wavepath) {
    if (channels <= 0) channels = 2;
    if (sample_rate <= 0) sample_rate = 44100;

    FILE *fp = open_r(pcmpath);
    if (fseek(fp, 0, SEEK_END) != 0) die("无法定位文件末尾", pcmpath);
    long pcmSize = ftell(fp);
    rewind(fp);

    unsigned char hdr[44];
    memcpy(hdr + 0, "RIFF", 4);
    put_u32le(hdr + 4, (unsigned int)(36 + pcmSize));
    memcpy(hdr + 8, "WAVE", 4);
    memcpy(hdr + 12, "fmt ", 4);
    put_u32le(hdr + 16, 16);                                   /* Subchunk1Size */
    put_u16le(hdr + 20, 1);                                    /* PCM */
    put_u16le(hdr + 22, (unsigned short)channels);
    put_u32le(hdr + 24, (unsigned int)sample_rate);
    put_u32le(hdr + 28, (unsigned int)(sample_rate * channels * 2)); /* ByteRate */
    put_u16le(hdr + 32, (unsigned short)(channels * 2));       /* BlockAlign */
    put_u16le(hdr + 34, 16);                                   /* BitsPerSample */
    memcpy(hdr + 36, "data", 4);
    put_u32le(hdr + 40, (unsigned int)pcmSize);

    FILE *fpo = open_w(wavepath);
    fwrite(hdr, 1, sizeof hdr, fpo);

    unsigned char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof buf, fp)) > 0) {
        fwrite(buf, 1, n, fpo);
    }

    fclose(fp); fclose(fpo);
    printf("to_wave: ch=%d rate=%d pcm=%ld -> %s\n", channels, sample_rate, pcmSize, wavepath);
    return 0;
}

/* ---------- 命令行分发 ---------- */

static void usage(const char *prog) {
    printf(
        "pcm_tools —— L1-04 PCM 音频采样数据处理工具集（PCM16LE）\n\n"
        "用法: %s <command> [args...]\n\n"
        "  split_lr    <in.pcm> <out_l.pcm> <out_r.pcm>\n"
        "  half_left   <in.pcm> <out.pcm>\n"
        "  doublespeed <in.pcm> <out.pcm>\n"
        "  to_pcm8     <in.pcm> <out.pcm>\n"
        "  cut_mono    <in.pcm> <start> <dur> <out.pcm> <out.txt>\n"
        "  to_wave     <in.pcm> <channels> <sample_rate> <out.wav>\n",
        prog);
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(argv[0]); return 1; }

    const char *cmd = argv[1];

    if (!strcmp(cmd, "split_lr") && argc == 5)
        return pcm16le_split(argv[2], argv[3], argv[4]);
    if (!strcmp(cmd, "half_left") && argc == 4)
        return pcm16le_half_left(argv[2], argv[3]);
    if (!strcmp(cmd, "doublespeed") && argc == 4)
        return pcm16le_doublespeed(argv[2], argv[3]);
    if (!strcmp(cmd, "to_pcm8") && argc == 4)
        return pcm16le_to_pcm8(argv[2], argv[3]);
    if (!strcmp(cmd, "cut_mono") && argc == 7)
        return pcm16le_cut_mono(argv[2], atol(argv[3]), atol(argv[4]), argv[5], argv[6]);
    if (!strcmp(cmd, "to_wave") && argc == 6)
        return pcm16le_to_wave(argv[2], atoi(argv[3]), atoi(argv[4]), argv[5]);

    usage(argv[0]);
    return 1;
}
