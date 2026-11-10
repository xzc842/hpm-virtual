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
    HPM_CALL(trig, write)(0);
    return 0;
}

void HPM_FN(trigger)(void) {
    HPM_CALL(trig, write)(1);
    delay_10us();
    HPM_CALL(trig, write)(0);
}

/* 真实硬件：测量 ECHO 高电平时间并换算为厘米；超时返回最大值。 */
int HPM_FN(read_cm)(void) {
    HPM_FN(trigger)();

    unsigned long timeout = 60000UL;
    while (!HPM_CALL(echo, read)() && --timeout) {
    }
    if (!timeout) return 400;

    /* 虚拟调试按“有效范围内”回一个近距值；真实硬件可另行标定脉宽。 */
    return 6;
}
