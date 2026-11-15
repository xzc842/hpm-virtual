/*
 * Copyright (C) 2026 XueZicheng <xuezicheng842@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3 of the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include "driver.h"

/*
 * 一个舵机 + 两个 LED。
 *
 * servo：P1_0，PWM 占空比 5% / 7.5% / 10% 对应 0° / 90° / 180°。
 * led1 ：P1_1
 * led2 ：P1_2
 */

static void delay(void) {
    /* 500 次循环用于虚拟调试的可见节奏；真实板子上可改大。 */
    for (volatile unsigned int i = 0; i < 500; ++i) {
    }
}

void main(void) {
    hpm_init_all();
    servo_start();
    led1_off();
    led2_off();

    while (1) {
        servo_set_duty(50);
        led1_on();
        led2_off();
        delay();

        servo_set_duty(75);
        led1_off();
        led2_on();
        delay();

        servo_set_duty(100);
        led1_on();
        led2_on();
        delay();

        servo_set_duty(75);
        led1_off();
        led2_off();
        delay();
    }
}
