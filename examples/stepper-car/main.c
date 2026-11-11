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

#define NEAR_CM 25

/* 上电后等待约 1 秒，让调试虚拟设备和超声波 ECHO 电平稳定。 */
static void delay_1s(void) {
    for (volatile unsigned int i = 0; i < 1000; ++i) {
        for (volatile unsigned int j = 0; j < 1000; ++j) {
        }
    }
}

static void set_dirs(int left_dir, int right_dir) {
    stepper_fl_set_dir(left_dir);
    stepper_rl_set_dir(left_dir);
    stepper_fr_set_dir(right_dir);
    stepper_rr_set_dir(right_dir);
    for (volatile unsigned int d = 0; d < 50; ++d) {
    }
}

static void pulse_all(unsigned int steps) {
    while (steps--) {
        stepper_fl_pulse(1);
        stepper_rl_pulse(1);
        stepper_fr_pulse(1);
        stepper_rr_pulse(1);
    }
}



void main(void) {
    hpm_init_all();
    /* 等虚拟超声和调试服务完成第一次距离同步，避免上电默认高电平误判近距。 */
    for (volatile unsigned long warmup = 0; warmup < 200UL; ++warmup) {
    }

    /* 启动先给一个明确的前进状态，避免上电时 ECHO 尚未稳定导致
     * 第一次测距误判为近距而立刻倒车。 */
    set_dirs(1, 1);
    pulse_all(10);

    unsigned char near_checks = 0;
    unsigned char startup_checks = 0;
    while (1) {
        int cm = 400;
        if (startup_checks < 100) {
            startup_checks++;
        } else {
            cm = sonar_read_cm();
        }
        if (cm < NEAR_CM) {
            if (near_checks < 5) {
                near_checks++;
                cm = 400;  /* 需要连续多次近距才倒车，过滤毛刺 */
            }
        } else {
            near_checks = 0;
        }
        if (cm < NEAR_CM) {
            /* 先停一下让车身惯性消失，再后退。 */
            for (volatile unsigned int wait = 0; wait < 20000; ++wait) {
            }
            /* 先后退，再原地转弯，最后继续前进。 */
            set_dirs(0, 0);
            pulse_all(180);
            set_dirs(0, 1);
            pulse_all(150);
        } else {
            /* 小步前进，频繁检查，避免冲过墙。 */
            set_dirs(1, 1);
            pulse_all(10);
        }
    }
}
