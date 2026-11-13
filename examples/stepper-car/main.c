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

static void set_dirs(int left_dir, int right_dir) {
    stepper_fl_set_dir(left_dir);
    stepper_rl_set_dir(left_dir);
    stepper_fr_set_dir(right_dir);
    stepper_rr_set_dir(right_dir);
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
    while (1) {
        int cm = sonar_read_cm();
        if (cm < NEAR_CM) {
            set_dirs(0, 0);
            pulse_all(180);
            set_dirs(0, 1);
            pulse_all(150);
        } else {
            set_dirs(1, 1);
            pulse_all(200);
        }
    }
}
