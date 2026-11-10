# 示例工程

`project1` / `project2` 硬件相同，区别在 `led2` 是否使用自定义虚拟包。

| 工程 | 固件 | 虚拟场景 | 自定义包 |
| --- | --- | --- | --- |
| `project1` | 舵机 P1_0，LED1 P1_1，LED2 P1_2 | 舵机 + 两个 LED | 无 |
| `project2` | 与 project1 相同 | 同 project1 | `led2` 覆盖为 `clickable-led`：点击切换红/蓝 |
| `ultrasonic` | 通用超声驱动 | 传感器 + 可移动目标 | `target_distance` 输入 → 射线测量 → 标尺 |
| `servo-arm` | 舵机 + 长杆 + 超声 + LED | 舵机、右侧超声、LED | 长杆扫到右侧遮挡超声 → 实测 `<= 10 cm` → LED 亮 |

## 构建

```bash
cd project1        # 或 project2
hpm sync --offline
hpm build
./run.sh           # mcus 模拟器里验证
```

`project1` / `project2` 的 `debug.toml` 已提供，不需要再生成。

## 在 Godot 里运行

hpm-gui 打开对应目录并「启动调试」，然后：

在仓库根目录：

```bash
godot --path . -- --project=examples/project1
godot --path . -- --project=examples/project2
godot --path . -- --project=examples/ultrasonic
godot --path . -- --project=examples/servo-arm
```

## Blender

每个示例目录下都有：

```
virtual/virtual.blend
```

安装 hpm-virtual Blender 插件后直接打开即可编辑。场景里的设备根节点
（`led1`、`led2`、`servo`）保存了 `hpm_device` 元数据，能直接导出。

重新生成：

在仓库根目录：

```bash
godot --headless --path . --script res://tools/build_example_scenes.gd
godot --headless --path . --script res://tools/build_ultrasonic_assets.gd
blender --background --factory-startup --python tools/build_example_blends.py
```

## ultrasonic

设备包：`~/.hpm/packages/ultrasonic-*-1.0.0`（MIT）。

- 通用驱动，包名芯片字段为 `*`。
- `project.json` 的 `trig` / `echo` 绑定 P1_0 / P1_1。
- `config.effective_distance` 默认 30 cm。
- `debug.c` 是 `bidirectional` 设备：`target_distance` 输入目标距离，`distance` 接收实测值。
- `virtual.gd` 收到 `target_distance` 后移动目标，用射线在 3D 场景里测量，再 `send("distance", cm)` 回写模拟器；实测 `< 有效距离` 时更新标尺，离开后清除。

```bash
cd examples/ultrasonic
hpm sync --offline
hpm build
./run.sh
```

## servo-arm

- 舵机 P1_0，超声 TRIG/ECHO P1_1/P1_2，LED P1_3。
- 固件让舵机 0°→180°→0°，长杆从左侧扫到右侧。
- 主循环轮询超声波；到达右端附近时调用 `sonar_read_cm()`，实测 `<= 10 cm` 时 LED 亮。
- 超声 `virtual.gd` 使用 `auto_measure=true`，每 0.1s 对场景做射线测量并回写 `distance`。

```bash
cd examples/servo-arm
hpm sync --offline
hpm build
./run.sh
```

## project2 的自定义包

```
project2/virtual/packages/clickable-led-1.0.0/
  manifest.json
  device.json     # 按物体摩擦
  model.gltf      # Blender 用
  virtual.gd      # 点击切换颜色
```

`project2/virtual/virtual.json` 的 `led2`：

```json
{
  "name": "led2",
  "node": "Devices/led2",
  "package": "gpio",
  "override": { "name": "clickable-led", "version": "1.0.0" }
}
```

运行时优先使用覆盖包的 `virtual.gd` 和 `device.json`；模型已在 `virtual.glb` 中，
所以无需再实例化 `model.gltf`。
