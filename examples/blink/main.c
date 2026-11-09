#include "driver.h"

/*
 * 闪烁 LED。
 *
 * led_on()/led_off() 由 gpio 驱动生成，绑定 project.toml 里的 P1_0。
 * 调试时 gpio 的 debug 插件会把引脚电平转成 power 通道，
 * hpm-virtual 里的虚拟 LED 跟着亮/灭。
 */

static void delay(void) {
    for (volatile unsigned int i = 0; i < 20000; ++i) {
    }
}

void main(void) {
    hpm_init_all();
    led_off();

    while (1) {
        led_on();
        delay();
        led_off();
        delay();
    }
}
