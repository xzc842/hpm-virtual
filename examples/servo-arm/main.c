/*
 * Copyright (C) 2026 XueZicheng <xuezicheng842@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
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

/* 与 device.json 的 effective_distance 对应；示例阈值 10 cm。 */
#define ALARM_DISTANCE_CM 10

static void delay(void) {
    for (volatile unsigned int i = 0; i < 500; ++i) {
    }
}

static void update_led(void) {
    int cm = sonar_read_cm();
    if (cm <= ALARM_DISTANCE_CM) {
        led_on();
    } else {
        led_off();
    }
}

void main(void) {
    hpm_init_all();
    servo_start();
    led_off();

    while (1) {
        led_off();
        for (unsigned int i = 0; i <= 18; ++i) {
            servo_set_duty(50 + i * 50 / 18);
            delay();
            if (i >= 14) {
                servo_stop();
                update_led();
                servo_start();
            }
        }
        for (unsigned int hold = 0; hold < 60; ++hold) {
            delay();
            if (hold % 10 == 0) {
                servo_stop();
                update_led();
                servo_start();
            }
        }
        for (unsigned int i = 18; i > 0; --i) {
            servo_set_duty(50 + i * 50 / 18);
            delay();
            if (i >= 14) {
                servo_stop();
                update_led();
                servo_start();
            }
        }
    }
}
