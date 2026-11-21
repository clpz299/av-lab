/*
 * yuv_tools.c —— L1-03 RGB / YUV 像素数据处理工具集
 *
 * 单文件实现，依据素材 article/020《视音频数据处理：RGB、YUV像素数据处理》整理，
 * 共 11 个处理函数 + 命令行分发。像素采样位数固定 8bit（1 分量 = 1 Byte）。
 *
 * 设计约束：
 *   - 存储布局：YUV420P / YUV444P 为 Planar（Y 后跟 U、V），RGB24 为 Packed（R,G,B 连续）；
 *   - YUV420P 一帧 = w*h*3/2；YUV444P 一帧 = w*h*3；RGB24 一帧 = w*h*3；
 *   - 所有输出路径由命令行显式给出，避免污染当前工作目录。
 *
 * 用法： yuv_tools <command> [args...]
 *   split420    <in.yuv> <w> <h> <num> <outdir>
 *   split444    <in.yuv> <w> <h> <num> <outdir>
 *   gray420     <in.yuv> <w> <h> <num> <out.yuv>
 *   half420     <in.yuv> <w> <h> <num> <out.yuv>
 *   border420   <in.yuv> <w> <h> <border> <num> <out.yuv>
 *   graybar420  <w> <h> <ymin> <ymax> <barnum> <out.yuv>
 *   psnr420     <a.yuv> <b.yuv> <w> <h> <num>
 *   splitrgb24  <in.rgb> <w> <h> <num> <outdir>
 *   rgb24tobmp  <in.rgb> <w> <h> <out.bmp>
 *   rgb24toyuv  <in.rgb> <w> <h> <num> <out.yuv>
 *   colorbar24  <w> <h> <out.rgb>
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

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

/* 将值裁剪到 [min_val, max_val]，用于 RGB->YUV 计算越界保护 */
static unsigned char clip_value(int x, int min_val, int max_val) {
    if (x > max_val) return (unsigned char)max_val;
    if (x < min_val) return (unsigned char)min_val;
    return (unsigned char)x;
}

/* 拼接 "<dir>/<name>"，返回静态分配的字符串（调用点各自提供缓冲） */
static void join_path(char *buf, size_t n, const char *dir, const char *name) {
    snprintf(buf, n, "%s/%s", dir, name);
}

/* ---------- 1.1 分离 YUV420P 的 Y / U / V ---------- */

static int yuv420_split(const char *url, int w, int h, int num, const char *outdir) {
    char py[1024], pu[1024], pv[1024];
    join_path(py, sizeof py, outdir, "output_420_y.y");
    join_path(pu, sizeof pu, outdir, "output_420_u.y");
    join_path(pv, sizeof pv, outdir, "output_420_v.y");

    FILE *fp  = open_r(url);
    FILE *fp1 = open_w(py);
    FILE *fp2 = open_w(pu);
    FILE *fp3 = open_w(pv);

    size_t frame = (size_t)w * h * 3 / 2;
    unsigned char *pic = (unsigned char *)malloc(frame);
    if (!pic) die("内存不足", NULL);

    for (int i = 0; i < num; i++) {
        if (fread(pic, 1, frame, fp) != frame) break;
        fwrite(pic, 1, (size_t)w * h, fp1);                 /* Y */
        fwrite(pic + (size_t)w * h, 1, (size_t)w * h / 4, fp2);            /* U */
        fwrite(pic + (size_t)w * h + (size_t)w * h / 4, 1, (size_t)w * h / 4, fp3); /* V */
    }

    free(pic);
    fclose(fp); fclose(fp1); fclose(fp2); fclose(fp3);
    printf("split420: Y/U/V -> %s\n", outdir);
    return 0;
}

/* ---------- 1.2 分离 YUV444P 的 Y / U / V ---------- */

static int yuv444_split(const char *url, int w, int h, int num, const char *outdir) {
    char py[1024], pu[1024], pv[1024];
    join_path(py, sizeof py, outdir, "output_444_y.y");
    join_path(pu, sizeof pu, outdir, "output_444_u.y");
    join_path(pv, sizeof pv, outdir, "output_444_v.y");

    FILE *fp  = open_r(url);
    FILE *fp1 = open_w(py);
    FILE *fp2 = open_w(pu);
    FILE *fp3 = open_w(pv);

    size_t plane = (size_t)w * h;
    size_t frame = plane * 3;
    unsigned char *pic = (unsigned char *)malloc(frame);
    if (!pic) die("内存不足", NULL);

    for (int i = 0; i < num; i++) {
        if (fread(pic, 1, frame, fp) != frame) break;
        fwrite(pic, 1, plane, fp1);              /* Y */
        fwrite(pic + plane, 1, plane, fp2);      /* U */
        fwrite(pic + plane * 2, 1, plane, fp3);  /* V */
    }

    free(pic);
    fclose(fp); fclose(fp1); fclose(fp2); fclose(fp3);
    printf("split444: Y/U/V -> %s\n", outdir);
    return 0;
}

/* ---------- 1.3 YUV420P 去色 -> 灰度图 ---------- */

static int yuv420_gray(const char *url, int w, int h, int num, const char *out) {
    FILE *fp  = open_r(url);
    FILE *fp1 = open_w(out);
    size_t frame = (size_t)w * h * 3 / 2;
    unsigned char *pic = (unsigned char *)malloc(frame);
    if (!pic) die("内存不足", NULL);

    for (int i = 0; i < num; i++) {
        if (fread(pic, 1, frame, fp) != frame) break;
        /* 无色 = U/V 取 128（偏置后色度的中性值） */
        memset(pic + (size_t)w * h, 128, (size_t)w * h / 2);
        fwrite(pic, 1, frame, fp1);
    }

    free(pic);
    fclose(fp); fclose(fp1);
    printf("gray420 -> %s\n", out);
    return 0;
}

/* ---------- 1.4 YUV420P 亮度减半 ---------- */

static int yuv420_halfy(const char *url, int w, int h, int num, const char *out) {
    FILE *fp  = open_r(url);
    FILE *fp1 = open_w(out);
    size_t frame = (size_t)w * h * 3 / 2;
    unsigned char *pic = (unsigned char *)malloc(frame);
    if (!pic) die("内存不足", NULL);

    for (int i = 0; i < num; i++) {
        if (fread(pic, 1, frame, fp) != frame) break;
        for (size_t j = 0; j < (size_t)w * h; j++) {
            pic[j] = (unsigned char)(pic[j] / 2);
        }
        fwrite(pic, 1, frame, fp1);
    }

    free(pic);
    fclose(fp); fclose(fp1);
    printf("half420 -> %s\n", out);
    return 0;
}

/* ---------- 1.5 YUV420P 加边框 ----------
 * 说明：保留素材的边界判定（右/下各少 1 像素），作为「边框不对称」踩坑点。 */
static int yuv420_border(const char *url, int w, int h, int border, int num, const char *out) {
    FILE *fp  = open_r(url);
    FILE *fp1 = open_w(out);
    size_t frame = (size_t)w * h * 3 / 2;
    unsigned char *pic = (unsigned char *)malloc(frame);
    if (!pic) die("内存不足", NULL);

    for (int i = 0; i < num; i++) {
        if (fread(pic, 1, frame, fp) != frame) break;
        for (int j = 0; j < h; j++) {
            for (int k = 0; k < w; k++) {
                if (k < border || k >(w - border) || j < border || j >(h - border)) {
                    pic[(size_t)j * w + k] = 255;
                }
            }
        }
        fwrite(pic, 1, frame, fp1);
    }

    free(pic);
    fclose(fp); fclose(fp1);
    printf("border420 -> %s\n", out);
    return 0;
}

/* ---------- 1.6 生成 YUV420P 灰阶测试图 ---------- */

static int yuv420_graybar(int width, int height, int ymin, int ymax, int barnum, const char *out) {
    int barwidth = width / barnum;
    float lum_inc = ((float)(ymax - ymin)) / ((float)(barnum - 1));
    int uv_width = width / 2, uv_height = height / 2;

    unsigned char *data_y = (unsigned char *)malloc((size_t)width * height);
    unsigned char *data_u = (unsigned char *)malloc((size_t)uv_width * uv_height);
    unsigned char *data_v = (unsigned char *)malloc((size_t)uv_width * uv_height);
    if (!data_y || !data_u || !data_v) die("内存不足", NULL);

    FILE *fp = open_w(out);

    printf("Y,U,V from left to right:\n");
    for (int t = 0; t < barnum; t++) {
        int lum = ymin + (int)(t * lum_inc);
        printf("%3d, 128, 128\n", lum);
    }

    for (int j = 0; j < height; j++) {
        for (int i = 0; i < width; i++) {
            int t = i / barwidth;
            data_y[(size_t)j * width + i] = (unsigned char)(ymin + (int)(t * lum_inc));
        }
    }
    for (int j = 0; j < uv_height; j++)
        for (int i = 0; i < uv_width; i++)
            data_u[(size_t)j * uv_width + i] = 128;
    for (int j = 0; j < uv_height; j++)
        for (int i = 0; i < uv_width; i++)
            data_v[(size_t)j * uv_width + i] = 128;

    fwrite(data_y, (size_t)width * height, 1, fp);
    fwrite(data_u, (size_t)uv_width * uv_height, 1, fp);
    fwrite(data_v, (size_t)uv_width * uv_height, 1, fp);

    fclose(fp);
    free(data_y); free(data_u); free(data_v);
    printf("graybar420 -> %s\n", out);
    return 0;
}

/* ---------- 1.7 计算两张 YUV420P 的 Y 分量 PSNR ---------- */

static int yuv420_psnr(const char *url1, const char *url2, int w, int h, int num) {
    FILE *fp1 = open_r(url1);
    FILE *fp2 = open_r(url2);
    size_t plane = (size_t)w * h;
    unsigned char *pic1 = (unsigned char *)malloc(plane);
    unsigned char *pic2 = (unsigned char *)malloc(plane);
    if (!pic1 || !pic2) die("内存不足", NULL);

    for (int i = 0; i < num; i++) {
        if (fread(pic1, 1, plane, fp1) != plane) break;
        if (fread(pic2, 1, plane, fp2) != plane) break;

        double mse_sum = 0.0;
        for (size_t j = 0; j < plane; j++) {
            double d = (double)((int)pic1[j] - (int)pic2[j]);
            mse_sum += d * d;
        }
        double mse = mse_sum / (double)plane;
        double psnr = 10.0 * log10(255.0 * 255.0 / mse);
        printf("%5.3f\n", psnr);

        /* 跳过本帧的 U/V 分量 */
        fseek(fp1, (long)(plane / 2), SEEK_CUR);
        fseek(fp2, (long)(plane / 2), SEEK_CUR);
    }

    free(pic1); free(pic2);
    fclose(fp1); fclose(fp2);
    return 0;
}

/* ---------- 1.8 分离 RGB24 的 R / G / B ---------- */

static int rgb24_split(const char *url, int w, int h, int num, const char *outdir) {
    char pr[1024], pg[1024], pb[1024];
    join_path(pr, sizeof pr, outdir, "output_r.y");
    join_path(pg, sizeof pg, outdir, "output_g.y");
    join_path(pb, sizeof pb, outdir, "output_b.y");

    FILE *fp  = open_r(url);
    FILE *fp1 = open_w(pr);
    FILE *fp2 = open_w(pg);
    FILE *fp3 = open_w(pb);

    size_t frame = (size_t)w * h * 3;
    unsigned char *pic = (unsigned char *)malloc(frame);
    if (!pic) die("内存不足", NULL);

    for (int i = 0; i < num; i++) {
        if (fread(pic, 1, frame, fp) != frame) break;
        for (size_t j = 0; j < frame; j += 3) {
            fwrite(pic + j, 1, 1, fp1);      /* R */
            fwrite(pic + j + 1, 1, 1, fp2);  /* G */
            fwrite(pic + j + 2, 1, 1, fp3);  /* B */
        }
    }

    free(pic);
    fclose(fp); fclose(fp1); fclose(fp2); fclose(fp3);
    printf("splitrgb24: R/G/B -> %s\n", outdir);
    return 0;
}

/* ---------- 1.9 RGB24 封装为 BMP ---------- */

static int rgb24_to_bmp(const char *rgb24path, int width, int height, const char *bmppath) {
    FILE *fpr = open_r(rgb24path);
    FILE *fpb = open_w(bmppath);

    size_t img = (size_t)width * height * 3;
    unsigned char *buf = (unsigned char *)malloc(img);
    if (!buf) die("内存不足", NULL);
    if (fread(buf, 1, img, fpr) != img) die("RGB24 数据不足", rgb24path);

    /* BMP 文件头（14 字节）+ 信息头（40 字节），均小端存储 */
    unsigned char fileHeader[14] = {0};
    unsigned char infoHeader[40] = {0};
    unsigned int fileSize = (unsigned int)(14 + 40 + img);
    unsigned int dataOffset = 14 + 40;

    fileHeader[0] = 'B'; fileHeader[1] = 'M';
    memcpy(&fileHeader[2], &fileSize, 4);
    memcpy(&fileHeader[10], &dataOffset, 4);

    unsigned int biSize = 40;
    int biWidth = width;
    int biHeight = -height;              /* 负值 = 自顶向下存储 */
    unsigned short planes = 1, bitCount = 24;
    unsigned int biSizeImage = (unsigned int)img;
    memcpy(&infoHeader[0], &biSize, 4);
    memcpy(&infoHeader[4], &biWidth, 4);
    memcpy(&infoHeader[8], &biHeight, 4);
    memcpy(&infoHeader[12], &planes, 2);
    memcpy(&infoHeader[14], &bitCount, 2);
    memcpy(&infoHeader[20], &biSizeImage, 4);

    fwrite(fileHeader, 1, sizeof fileHeader, fpb);
    fwrite(infoHeader, 1, sizeof infoHeader, fpb);

    /* RGB24(R,G,B) -> BMP(B,G,R)：交换 R 与 B */
    for (size_t idx = 0; idx < img; idx += 3) {
        unsigned char t = buf[idx];
        buf[idx] = buf[idx + 2];
        buf[idx + 2] = t;
    }
    fwrite(buf, 1, img, fpb);

    free(buf);
    fclose(fpr); fclose(fpb);
    printf("rgb24tobmp -> %s\n", bmppath);
    return 0;
}

/* ---------- 1.10 RGB24 -> YUV420P ---------- */

static void rgb24_to_yuv420(unsigned char *rgb, int w, int h, unsigned char *yuv) {
    unsigned char *ptrY = yuv;
    unsigned char *ptrU = yuv + (size_t)w * h;
    unsigned char *ptrV = ptrU + (size_t)w * h / 4;
    memset(yuv, 0, (size_t)w * h * 3 / 2);

    for (int j = 0; j < h; j++) {
        unsigned char *ptrRGB = rgb + (size_t)w * j * 3;
        for (int i = 0; i < w; i++) {
            int r = *ptrRGB++;
            int g = *ptrRGB++;
            int b = *ptrRGB++;
            int y = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
            int u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
            int v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
            *ptrY++ = clip_value(y, 0, 255);
            if (j % 2 == 0 && i % 2 == 0) {
                *ptrU++ = clip_value(u, 0, 255);
            } else if (i % 2 == 0) {
                *ptrV++ = clip_value(v, 0, 255);
            }
        }
    }
}

static int rgb24_to_yuv420_file(const char *in, int w, int h, int num, const char *out) {
    FILE *fp  = open_r(in);
    FILE *fp1 = open_w(out);
    size_t rgbSize = (size_t)w * h * 3;
    size_t yuvSize = (size_t)w * h * 3 / 2;
    unsigned char *rgb = (unsigned char *)malloc(rgbSize);
    unsigned char *yuv = (unsigned char *)malloc(yuvSize);
    if (!rgb || !yuv) die("内存不足", NULL);

    for (int i = 0; i < num; i++) {
        if (fread(rgb, 1, rgbSize, fp) != rgbSize) break;
        rgb24_to_yuv420(rgb, w, h, yuv);
        fwrite(yuv, 1, yuvSize, fp1);
    }

    free(rgb); free(yuv);
    fclose(fp); fclose(fp1);
    printf("rgb24toyuv -> %s\n", out);
    return 0;
}

/* ---------- 1.11 生成 RGB24 彩条测试图 ---------- */

static int rgb24_colorbar(int width, int height, const char *out) {
    size_t img = (size_t)width * height * 3;
    unsigned char *data = (unsigned char *)malloc(img);
    if (!data) die("内存不足", NULL);

    int barwidth = width / 8;
    for (int j = 0; j < height; j++) {
        for (int i = 0; i < width; i++) {
            int barnum = i / barwidth;
            unsigned char r = 0, g = 0, b = 0;
            switch (barnum) {
                case 0: r = 255; g = 255; b = 255; break; /* 白 */
                case 1: r = 255; g = 255; b = 0;   break; /* 黄 */
                case 2: r = 0;   g = 255; b = 255; break; /* 青 */
                case 3: r = 0;   g = 255; b = 0;   break; /* 绿 */
                case 4: r = 255; g = 0;   b = 255; break; /* 品红 */
                case 5: r = 255; g = 0;   b = 0;   break; /* 红 */
                case 6: r = 0;   g = 0;   b = 255; break; /* 蓝 */
                case 7: r = 0;   g = 0;   b = 0;   break; /* 黑 */
            }
            size_t off = ((size_t)j * width + i) * 3;
            data[off] = r; data[off + 1] = g; data[off + 2] = b;
        }
    }

    FILE *fp = open_w(out);
    fwrite(data, 1, img, fp);
    fclose(fp);
    free(data);
    printf("colorbar24 -> %s\n", out);
    return 0;
}

/* ---------- 命令行分发 ---------- */

static void usage(const char *prog) {
    printf(
        "yuv_tools —— L1-03 RGB/YUV 像素数据处理工具集\n\n"
        "用法: %s <command> [args...]\n\n"
        "  split420    <in.yuv> <w> <h> <num> <outdir>\n"
        "  split444    <in.yuv> <w> <h> <num> <outdir>\n"
        "  gray420     <in.yuv> <w> <h> <num> <out.yuv>\n"
        "  half420     <in.yuv> <w> <h> <num> <out.yuv>\n"
        "  border420   <in.yuv> <w> <h> <border> <num> <out.yuv>\n"
        "  graybar420  <w> <h> <ymin> <ymax> <barnum> <out.yuv>\n"
        "  psnr420     <a.yuv> <b.yuv> <w> <h> <num>\n"
        "  splitrgb24  <in.rgb> <w> <h> <num> <outdir>\n"
        "  rgb24tobmp  <in.rgb> <w> <h> <out.bmp>\n"
        "  rgb24toyuv  <in.rgb> <w> <h> <num> <out.yuv>\n"
        "  colorbar24  <w> <h> <out.rgb>\n",
        prog);
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(argv[0]); return 1; }

    const char *cmd = argv[1];

    if (!strcmp(cmd, "split420") && argc == 7)
        return yuv420_split(argv[2], atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), argv[6]);
    if (!strcmp(cmd, "split444") && argc == 7)
        return yuv444_split(argv[2], atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), argv[6]);
    if (!strcmp(cmd, "gray420") && argc == 7)
        return yuv420_gray(argv[2], atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), argv[6]);
    if (!strcmp(cmd, "half420") && argc == 7)
        return yuv420_halfy(argv[2], atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), argv[6]);
    if (!strcmp(cmd, "border420") && argc == 8)
        return yuv420_border(argv[2], atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), atoi(argv[6]), argv[7]);
    if (!strcmp(cmd, "graybar420") && argc == 8)
        return yuv420_graybar(atoi(argv[2]), atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), atoi(argv[6]), argv[7]);
    if (!strcmp(cmd, "psnr420") && argc == 7)
        return yuv420_psnr(argv[2], argv[3], atoi(argv[4]), atoi(argv[5]), atoi(argv[6]));
    if (!strcmp(cmd, "splitrgb24") && argc == 7)
        return rgb24_split(argv[2], atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), argv[6]);
    if (!strcmp(cmd, "rgb24tobmp") && argc == 6)
        return rgb24_to_bmp(argv[2], atoi(argv[3]), atoi(argv[4]), argv[5]);
    if (!strcmp(cmd, "rgb24toyuv") && argc == 7)
        return rgb24_to_yuv420_file(argv[2], atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), argv[6]);
    if (!strcmp(cmd, "colorbar24") && argc == 5)
        return rgb24_colorbar(atoi(argv[2]), atoi(argv[3]), argv[4]);

    usage(argv[0]);
    return 1;
}
