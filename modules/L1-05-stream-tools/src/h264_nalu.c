/*
 * h264_nalu.c —— H.264 Annex-B 裸流 NALU 列表工具
 *
 * 素材依据：article/022（NALU 解析原理）、article/041、article/042（码流分析工具）
 *
 * 功能：
 *   扫描 Annex-B 起始码（00 00 01 / 00 00 00 01），分离出每个 NALU，
 *   列出其字节偏移、nal_ref_idc（IDC）、nal_unit_type（TYPE）与长度（LEN），
 *   并汇总 NALU 总数与 I 帧（IDR）数量。
 *
 * 用法：
 *   h264_nalu <annexb.h264>
 *
 * 退出码：
 *   0  成功列出 NALU
 *   1  参数/文件错误
 *   2  未发现 Annex-B 起始码（输入可能是 AVCC/长度前缀格式，或不是 H.264）
 *
 * 说明：
 *   本工具是 L1-05 的“口袋分析器”，用于在没有 GUI 工具（Elecard / CodecVisa /
 *   H.264 分析器）的环境里快速确认：码流是否为 Annex-B、包含哪些 NALU、I 帧在哪。
 *   更深入的 SPS/PPS 字段（宽高、帧率）解析见 L2-01。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *type_name(int t)
{
    switch (t) {
        case 1:  return "SLICE";
        case 2:  return "DPA";
        case 3:  return "DPB";
        case 4:  return "DPC";
        case 5:  return "IDR";
        case 6:  return "SEI";
        case 7:  return "SPS";
        case 8:  return "PPS";
        case 9:  return "AUD";
        case 10: return "EOSEQ";
        case 11: return "EOSTREAM";
        case 12: return "FILL";
        default: return "UNKNOWN";
    }
}

static const char *idc_name(int idc)
{
    switch (idc) {
        case 0:  return "DISPOS";
        case 1:  return "LOW";
        case 2:  return "HIGH";
        case 3:  return "HIGHEST";
        default: return "?";
    }
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: h264_nalu <annexb.h264>\n");
        return 1;
    }

    FILE *fp = fopen(argv[1], "rb");
    if (!fp) {
        fprintf(stderr, "open failed: %s\n", argv[1]);
        return 1;
    }
    if (fseek(fp, 0, SEEK_END) != 0) { fclose(fp); return 1; }
    long size = ftell(fp);
    if (fseek(fp, 0, SEEK_SET) != 0) { fclose(fp); return 1; }
    if (size <= 0) {
        fprintf(stderr, "empty file: %s\n", argv[1]);
        fclose(fp);
        return 1;
    }

    unsigned char *buf = (unsigned char *)malloc((size_t)size);
    if (!buf) {
        fprintf(stderr, "out of memory\n");
        fclose(fp);
        return 1;
    }
    if (fread(buf, 1, (size_t)size, fp) != (size_t)size) {
        fprintf(stderr, "read failed: %s\n", argv[1]);
        free(buf);
        fclose(fp);
        return 1;
    }
    fclose(fp);

    /* 1) 扫描起始码：记录每个 0x000001 中 0x01 的下标 */
    long *sc = (long *)malloc(sizeof(long) * ((size_t)size / 3 + 2));
    if (!sc) {
        fprintf(stderr, "out of memory\n");
        free(buf);
        return 1;
    }
    long nsc = 0;
    for (long i = 2; i < size; i++) {
        if (buf[i] == 1 && buf[i - 1] == 0 && buf[i - 2] == 0) {
            sc[nsc++] = i;
        }
    }

    if (nsc == 0) {
        fprintf(stderr,
                "ERROR: no Annex-B start code found in %s\n"
                "       输入可能是 AVCC/长度前缀格式（如 MP4 中的 extradata），\n"
                "       请先用 -bsf:v h264_mp4toannexb 转成 Annex-B 裸流。\n",
                argv[1]);
        free(sc);
        free(buf);
        return 2;
    }

    /* 2) 逐 NALU 打印 */
    printf("-----+-------- NALU Table ------+---------\n");
    printf(" NUM |    POS  |    IDC |  TYPE |   LEN   |\n");
    printf("-----+---------+--------+-------+---------+\n");

    long idr = 0, sps = 0, pps = 0, sei = 0, slice = 0, unknown = 0;
    int any_forbidden = 0;

    for (long k = 0; k < nsc; k++) {
        long payload_start = sc[k] + 1;
        long payload_end   = (k + 1 < nsc) ? (sc[k + 1] - 2) : size;
        long len = payload_end - payload_start;
        if (len < 0) len = 0;

        /* 起始码长度：若 0x01 前还有第三个 0x00，则为 4 字节 00 00 00 01 */
        int prefix = (sc[k] - 3 >= 0 && buf[sc[k] - 3] == 0) ? 4 : 3;
        long pos = sc[k] - prefix + 1;

        int first = (len > 0) ? buf[payload_start] : 0;
        int forbidden = (first >> 7) & 1;
        int idc = (first >> 5) & 0x03;
        int type = first & 0x1f;

        if (forbidden) any_forbidden = 1;
        switch (type) {
            case 1:  slice++;   break;
            case 5:  idr++;     break;
            case 6:  sei++;     break;
            case 7:  sps++;     break;
            case 8:  pps++;     break;
            default: unknown++; break;
        }

        printf("%5ld| %8ld| %7s| %6s| %8ld|\n",
               k, pos, idc_name(idc), type_name(type), len);
    }

    printf("\n");
    printf("Total NALUs: %ld\n", nsc);
    printf("I/IDR frames: %ld\n", idr);
    printf("SPS=%ld PPS=%ld SEI=%ld SLICE=%ld UNKNOWN=%ld\n",
           sps, pps, sei, slice, unknown);
    printf("forbidden_zero_bit: %s\n", any_forbidden ? "VIOLATED" : "OK");

    free(sc);
    free(buf);
    return 0;
}
