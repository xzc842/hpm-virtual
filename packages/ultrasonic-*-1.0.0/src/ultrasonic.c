/*
 * MIT License
 *
 * Copyright (c) 2026 XueZicheng <xuezicheng842@outlook.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include "ultrasonic.h"
#include "config.h"

#define HPM_CAT_(a, b) a##b
#define HPM_CAT(a, b)  HPM_CAT_(a, b)
#define HPM_FN(name)   HPM_CAT(DEVICE_NAME, HPM_CAT(_, name))
#define HPM_CALL(prefix, method) HPM_CAT(prefix, HPM_CAT(_, method))

static void delay_10us(void) {
    for (volatile unsigned int i = 0; i < 18; ++i) {
    }
}

int HPM_FN(init)(void) {
    HPM_CALL(trig, init)();
    HPM_CALL(echo, init)();
    HPM_CALL(echo, write)(0);
    HPM_CALL(trig, write)(0);
    return 0;
}

void HPM_FN(trigger)(void) {
    HPM_CALL(trig, write)(1);
    delay_10us();
    HPM_CALL(trig, write)(0);
}

/* 通用 GPIO 超声测距：只使用 trig/echo 的 HPM API，不依赖任何架构寄存器。
 * loops_per_cm 由平台/编译器标定，配置在 manifest 中。 */
int HPM_FN(read_cm)(void) {
    HPM_FN(trigger)();

    unsigned long timeout = 200000UL;
    while (!HPM_CALL(echo, read)()) {
        if (--timeout == 0UL) return max_distance;
    }

    unsigned long loops = 0;
    timeout = 200000UL;
    while (HPM_CALL(echo, read)()) {
        ++loops;
        if (--timeout == 0UL) return max_distance;
    }

    unsigned long cm = loops / (unsigned long)loops_per_cm;
    if (cm < 2UL) return max_distance;
    if (cm > (unsigned long)max_distance) return max_distance;
    return (int)cm;
}
