/*
 * L1-01 环境搭建：hello_env.c
 * 目的：验证本工程工具链可编译并运行 C 程序，同时打印编译期信息。
 */
#include <stdio.h>
#include <string.h>

int main(void)
{
    printf("=== av-lab L1-01 环境自检 ===\n");
    printf("C 标准版本 : %ld\n", __STDC_VERSION__);
    printf("编译器    : %s %s\n", __VERSION__, __DATE__);
#if defined(__MINGW32__) || defined(__MINGW64__)
    printf("目标平台  : MinGW-w64 (Windows)\n");
#endif
    printf("sizeof(ptr): %zu 字节\n", sizeof(void *));

    /* 一个最小纯 C 逻辑，证明运行期正常 */
    const char *tag = "TOOLCHAIN_OK";
    if (strcmp(tag, "TOOLCHAIN_OK") != 0) {
        fprintf(stderr, "自检失败\n");
        return 1;
    }
    printf("结果      : %s\n", tag);
    return 0;
}
