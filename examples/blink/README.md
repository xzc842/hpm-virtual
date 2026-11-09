# Blink 示例：LED 闪烁

一个可以直接构建、调试、并接入 hpm-virtual 的完整 HPM 工程。

```text
blink/
├── project.toml      # mcu + led(gpio, P1_0)
├── project.json      # hpm-gui 读取的项目清单
├── main.c            # 闪烁固件
├── debug.toml        # mcus 运行配置
├── driver.json       # hpm sync 生成的驱动锁文件
└── virtual/
    ├── virtual.glb   # 地板 + LED 模型
    └── virtual.json  # LED 实例与摩擦参数
```

## 1. 构建

```bash
cd examples/blink
hpm sync --offline     # 生成 driver/，离线使用 ~/.hpm/packages
hpm build              # 产出 build/firmware.hex
```

## 2. 在模拟器里验证闪烁

```bash
./run.sh
# 或手动：
hpm debug --run
```

`gpio` 包的 `debug/debug.c` 会把 P1.0 的电平转成 `power` 通道：

```json
{"device":"led","message":"power=on","type":"log"}
{"device":"led","state":{"power":true},"type":"state"}
```

## 3. 在 hpm-virtual 里看 LED 闪烁

1. 启动 hpm-gui 并打开本项目：
   ```bash
   cd ~/桌面/项目/hpm-gui
   python3 main.py
   ```
   顶栏「打开项目」选择 `examples/blink`，进入「虚拟化测试」→「启动调试」。
2. 启动 Godot 虚拟环境：
   ```bash
   cd ~/桌面/项目/hpm-virtual
   godot --path . -- --project=examples/blink
   ```
3. Godot 检测到调试会话后连接 `GET /outputs/stream`，把 `power` 变化转发给
   `packages/gpio/debug/virtual.gd`，LED 模型亮/灭。

> 不需要 Godot 也能用 `./run.sh` 验证固件；Godot 只读取 hpm-gui 的调试服务。

## 固件

```c
#include "driver.h"

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
```

`led_on()` / `led_off()` 由 `gpio` 驱动按 `project.toml` 的 `P1_0` 生成。
`delay()` 是粗略软件延时；要精确周期可以给项目加 `time` 驱动：

```toml
[devices.app_delay]
driver = "time"

[devices.app_delay.config]
timer_id   = "1"
osc_hz     = "11059200"
clock_mode = "12"
```

然后调用 `app_delay_delay_ms(500)`。

## 常见问题

- `error 配置文件不存在 ... debug.toml`：确保 `examples/blink/debug.toml` 存在（本仓库已提供）。
- `hpm sync` 报找不到包：确认 `~/.hpm/packages` 里有 `stc90c51-*` 与 `gpio-*`，或去掉 `--offline`。
- Godot 一直显示“调试服务未连接”：hpm-gui 的「启动调试」还没开始，或服务端口不是 17321。
