# 示例工程

两个工程硬件相同，区别在 `led2` 是否使用自定义虚拟包。

| 工程 | 固件 | 虚拟场景 | 自定义包 |
| --- | --- | --- | --- |
| `project1` | 舵机 P1_0，LED1 P1_1，LED2 P1_2 | 舵机 + 两个 LED | 无 |
| `project2` | 与 project1 相同 | 同 project1 | `led2` 覆盖为 `clickable-led`：点击切换红/蓝 |

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
```

## Blender

两个目录下都有：

```
virtual/virtual.blend
```

安装 hpm-virtual Blender 插件后直接打开即可编辑。场景里的设备根节点
（`led1`、`led2`、`servo`）保存了 `hpm_device` 元数据，能直接导出。

重新生成：

在仓库根目录：

```bash
godot --headless --path . --script res://tools/build_example_scenes.gd
blender --background --factory-startup --python tools/build_example_blends.py
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
