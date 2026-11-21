/* quality_tools.c —— L1-15 客观质量指标计算：PSNR / SSIM / SNR
 *
 * 输入：两个同分辨率、同像素格式（YUV420P）的原始视频文件
 * 输出：逐帧指标 + 汇总（算术平均），以及一行机器可读的 RESULT JSON
 *
 * 用法：
 *   quality_tools <ref.yuv> <test.yuv> <width> <height> [max_frames]
 *   max_frames 缺省为 0，表示比较全部帧。
 *
 * 公式（8bit，MAX = 255）：
 *   MSE  = (1/N) * Σ (x_i - y_i)^2
 *   PSNR = 10 * log10( MAX^2 / MSE )
 *   SNR  = 10 * log10( Σ x_i^2 / Σ (x_i - y_i)^2 )
 *   SSIM = ( (2·μx·μy + C1)(2·σxy + C2) ) / ( (μx^2 + μy^2 + C1)(σx^2 + σy^2 + C2) )
 *          C1 = (0.01·MAX)^2, C2 = (0.03·MAX)^2
 *          本工具在 Y 平面按 8x8 块（边缘块取剩余尺寸）计算后取平均
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

static long file_size(FILE *f) {
    long cur = ftell(f);
    fseek(f, 0, SEEK_END);
    long end = ftell(f);
    fseek(f, cur, SEEK_SET);
    return end;
}

/* 计算一个块（bw x bh）的 SSIM */
static double ssim_block(const unsigned char *a, const unsigned char *b, int stride,
                         int bx, int by, int bw, int bh) {
    const double MAX = 255.0;
    const double C1 = (0.01 * MAX) * (0.01 * MAX);
    const double C2 = (0.03 * MAX) * (0.03 * MAX);
    int n = bw * bh;
    double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
    for (int y = 0; y < bh; y++) {
        const unsigned char *pa = a + (size_t)(by + y) * stride + bx;
        const unsigned char *pb = b + (size_t)(by + y) * stride + bx;
        for (int x = 0; x < bw; x++) {
            double va = pa[x], vb = pb[x];
            sx += va; sy += vb;
            sxx += va * va; syy += vb * vb; sxy += va * vb;
        }
    }
    double mx = sx / n, my = sy / n;
    double vx = sxx / n - mx * mx;
    double vy = syy / n - my * my;
    double cxy = sxy / n - mx * my;
    double num = (2 * mx * my + C1) * (2 * cxy + C2);
    double den = (mx * mx + my * my + C1) * (vx + vy + C2);
    if (den == 0) return 1.0;
    return num / den;
}

/* 人类可读格式：inf 或 4 位小数 */
static void fmt_val(char *buf, size_t n, double v) {
    if (isinf(v)) snprintf(buf, n, "inf");
    else if (isnan(v)) snprintf(buf, n, "nan");
    else snprintf(buf, n, "%.4f", v);
}
/* JSON 格式：inf/nan 用 null 表示，便于脚本解析 */
static void fmt_json(char *buf, size_t n, double v) {
    if (isinf(v) || isnan(v)) snprintf(buf, n, "null");
    else snprintf(buf, n, "%.4f", v);
}

int main(int argc, char **argv) {
    if (argc < 5) {
        fprintf(stderr, "用法: %s <ref.yuv> <test.yuv> <width> <height> [max_frames]\n"
                        "  两个文件须为同分辨率 YUV420P 原始视频\n", argv[0]);
        return 2;
    }

    const char *refPath  = argv[1];
    const char *testPath = argv[2];
    int  w = atoi(argv[3]);
    int  h = atoi(argv[4]);
    long maxFrames = (argc >= 6) ? atol(argv[5]) : 0;

    if (w <= 0 || h <= 0 || (w % 2) || (h % 2)) {
        fprintf(stderr, "错误: 宽高必须为正偶数（YUV420P 要求），当前 %dx%d\n", w, h);
        return 2;
    }

    size_t ySize = (size_t)w * h;
    size_t cSize = (size_t)(w / 2) * (h / 2);
    size_t frameSize = ySize + 2 * cSize;

    FILE *fr = fopen(refPath, "rb");
    if (!fr) { fprintf(stderr, "错误: 打不开参考文件 %s\n", refPath); return 2; }
    FILE *ft = fopen(testPath, "rb");
    if (!ft) { fprintf(stderr, "错误: 打不开待测文件 %s\n", testPath); fclose(fr); return 2; }

    size_t refBytes  = (size_t)file_size(fr);
    size_t testBytes = (size_t)file_size(ft);
    size_t nRef  = refBytes / frameSize;
    size_t nTest = testBytes / frameSize;

    if (nRef == 0 || nTest == 0) {
        fprintf(stderr, "错误: 帧数为 0 —— 文件大小(ref=%zu / test=%zu 字节)与单帧大小(%zu 字节, %dx%d YUV420P)不匹配\n",
                refBytes, testBytes, frameSize, w, h);
        fprintf(stderr, "      常见原因：分辨率填错，或拿不同像素格式(420p vs 444p)的文件来比\n");
        fclose(fr); fclose(ft);
        return 3;
    }
    if (nRef != nTest)
        fprintf(stderr, "警告: 帧数不一致(ref=%zu, test=%zu)，取较小值比较\n", nRef, nTest);

    long frames = (long)(nRef < nTest ? nRef : nTest);
    if (maxFrames > 0 && maxFrames < frames) frames = maxFrames;

    unsigned char *ra = malloc(frameSize);
    unsigned char *rb = malloc(frameSize);
    if (!ra || !rb) { fprintf(stderr, "错误: 内存不足\n"); fclose(fr); fclose(ft); return 2; }

    double sumPsnrY = 0, sumPsnrU = 0, sumPsnrV = 0, sumSsim = 0, sumSnr = 0;
    long finiteY = 0, finiteU = 0, finiteV = 0, used = 0;
    double sseTotalY = 0, sseTotalU = 0, sseTotalV = 0;

    for (long f = 0; f < frames; f++) {
        if (fread(ra, 1, frameSize, fr) != frameSize) break;
        if (fread(rb, 1, frameSize, ft) != frameSize) break;

        double sseY = 0, sseU = 0, sseV = 0, sigY = 0;
        for (size_t i = 0; i < ySize; i++) {
            double d = (double)ra[i] - rb[i];
            sseY += d * d;
            sigY += (double)ra[i] * ra[i];
        }
        const unsigned char *ua1 = ra + ySize, *ub1 = rb + ySize;
        const unsigned char *ua2 = ua1 + cSize,  *ub2 = ub1 + cSize;
        for (size_t i = 0; i < cSize; i++) { double d = (double)ua1[i] - ub1[i]; sseU += d * d; }
        for (size_t i = 0; i < cSize; i++) { double d = (double)ua2[i] - ub2[i]; sseV += d * d; }

        double psnrY = (sseY > 0) ? 10 * log10(255.0 * 255.0 * (double)ySize / sseY) : INFINITY;
        double psnrU = (sseU > 0) ? 10 * log10(255.0 * 255.0 * (double)cSize / sseU) : INFINITY;
        double psnrV = (sseV > 0) ? 10 * log10(255.0 * 255.0 * (double)cSize / sseV) : INFINITY;
        double snr   = (sseY > 0) ? 10 * log10(sigY / sseY) : INFINITY;

        double ssimSum = 0; int ssimBlk = 0;
        for (int by = 0; by < h; by += 8) {
            int bh = (h - by < 8) ? (h - by) : 8;
            for (int bx = 0; bx < w; bx += 8) {
                int bw = (w - bx < 8) ? (w - bx) : 8;
                ssimSum += ssim_block(ra, rb, w, bx, by, bw, bh);
                ssimBlk++;
            }
        }
        double ssim = ssimBlk ? ssimSum / ssimBlk : 1.0;

        sseTotalY += sseY; sseTotalU += sseU; sseTotalV += sseV;
        if (!isinf(psnrY)) { sumPsnrY += psnrY; finiteY++; }
        if (!isinf(psnrU)) { sumPsnrU += psnrU; finiteU++; }
        if (!isinf(psnrV)) { sumPsnrV += psnrV; finiteV++; }
        sumSsim += ssim;
        sumSnr  += snr;
        used++;

        char b1[32], b2[32], b3[32], b4[32], b5[32], b6[32];
        fmt_val(b1, sizeof b1, psnrY);
        fmt_val(b2, sizeof b2, psnrU);
        fmt_val(b3, sizeof b3, psnrV);
        fmt_val(b4, sizeof b4, (psnrY + psnrU + psnrV) / 3.0);
        fmt_val(b5, sizeof b5, ssim);
        fmt_val(b6, sizeof b6, snr);
        printf("frame=%ld psnr_y=%s psnr_u=%s psnr_v=%s psnr_avg=%s ssim_y=%s snr_y=%s\n",
               f + 1, b1, b2, b3, b4, b5, b6);
    }

    double avgY = finiteY ? sumPsnrY / finiteY : INFINITY;
    double avgU = finiteU ? sumPsnrU / finiteU : INFINITY;
    double avgV = finiteV ? sumPsnrV / finiteV : INFINITY;
    double avgAvg = (avgY + avgU + avgV) / 3.0;
    double avgSsim = used ? sumSsim / used : 0.0;
    double avgSnr  = used ? sumSnr / used : INFINITY;
    int identical = (sseTotalY == 0 && sseTotalU == 0 && sseTotalV == 0) ? 1 : 0;

    char h1[32], h2[32], h3[32], h4[32], h5[32], h6[32];
    fmt_val(h1, sizeof h1, avgY);
    fmt_val(h2, sizeof h2, avgU);
    fmt_val(h3, sizeof h3, avgV);
    fmt_val(h4, sizeof h4, avgAvg);
    fmt_val(h5, sizeof h5, avgSsim);
    fmt_val(h6, sizeof h6, avgSnr);
    printf("summary frames=%ld psnr_y=%s psnr_u=%s psnr_v=%s psnr_avg=%s ssim=%s snr=%s\n",
           used, h1, h2, h3, h4, h5, h6);

    char j1[32], j2[32], j3[32], j4[32], j5[32], j6[32];
    fmt_json(j1, sizeof j1, avgY);
    fmt_json(j2, sizeof j2, avgU);
    fmt_json(j3, sizeof j3, avgV);
    fmt_json(j4, sizeof j4, avgAvg);
    fmt_json(j5, sizeof j5, avgSsim);
    fmt_json(j6, sizeof j6, avgSnr);
    printf("RESULT {\"frames\":%ld,\"psnr_y\":%s,\"psnr_u\":%s,\"psnr_v\":%s,\"psnr_avg\":%s,\"ssim\":%s,\"snr\":%s,\"identical\":%s}\n",
           used, j1, j2, j3, j4, j5, j6, identical ? "true" : "false");

    free(ra); free(rb);
    fclose(fr); fclose(ft);
    return 0;
}
