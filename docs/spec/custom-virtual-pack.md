# 自定义虚拟包规范（v1）

“自定义虚拟包”（custom virtual pack）用于在**不改动设备包**的前提下，
替换某个设备实例的 3D 模型、`device.json` 和 `virtual.gd`。
典型场景：同一个 `pwm` 舵机，项目 A 用默认模型，项目 B 换成金属舵机模型和自定义动画脚本。

Blender 插件负责选择和打包；Godot 运行时按本规范加载。

## 1. 目录结构

自定义包是一个普通目录，可以只提供需要覆盖的文件：

```text
<custom-pack>/
  model.gltf/.glb      # 必需，覆盖 3D 模型（Blender 导入用）
  device.json          # 可选，覆盖物理/通道描述
  virtual.gd           # 可选，覆盖运行脚本
  manifest.json        # 可选，缺省时导出自动生成
  preview.png          # 可选，Blender 面板缩略图
```

未提供的文件回退到基础设备包（`~/.hpm/packages/<pkg>/debug/`）。

## 2. manifest.json

```json
{
  "type": "hpm-virtual-pack",
  "name": "blue-led",
  "version": "1.0.0",
  "target": "gpio",
  "description": "蓝色 LED + 柔光效果",
  "author": "xzc"
}
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `type` | 否 | 固定 `hpm-virtual-pack`，缺省按该类型处理。 |
| `name` | 否 | 包名；缺省用文件夹名。 |
| `version` | 否 | 语义化版本；缺省 `1.0.0`。 |
| `target` | 否 | 目标设备类型：设备包 manifest 的 `name`（如 `gpio`、`pwm-stc90c51`），也接受 `project.json` 的 `driver`；缺省不做校验。 |
| `description` / `author` | 否 | 面板展示。 |

导出复制到项目时，如果源目录没有 `manifest.json`，插件会按文件夹名、`1.0.0`、
设备 driver 生成一份。

`target` 不匹配时 Blender 给出警告，用户仍可强制使用；Godot 运行时记录警告但不阻止。

## 3. virtual.json 中的引用

```json
{
  "name": "servo",
  "node": "Devices/servo",
  "package": "pwm-stc90c51",
  "version": "1.0.0",
  "override": { "name": "metal-servo", "version": "1.0.0" }
}
```

也允许简写：

```json
"override": "metal-servo"
```

`override` 字段：

| 字段 | 说明 |
| --- | --- |
| `name` | 自定义包 manifest 的 `name`。 |
| `version` | 可选；缺省取最高版本，多个同名时给出警告。 |
| `path` | 可选；绝对路径或相对项目根目录，优先级最高。 |

Blender 导出时把选中的包复制到 `<项目>/virtual/packages/<name>-<version>/`，
并写入 `override`。这样项目自包含，换机器不丢资产。

## 4. 查找顺序

运行时依次查找：

1. `override.path`（存在即用）；
2. `<项目>/virtual/packages/<name>-<version>/`；
3. `<项目>/virtual/packages/<name>/`；
4. `$HPM_VIRTUAL_PACKAGES`（冒号分隔）；
5. `~/.hpm/virtual/<name>-<version>/`。

## 5. 加载优先级

对每个设备实例：

| 内容 | 优先级 |
| --- | --- |
| 模型 | Blender 已把最终模型写进 `virtual.glb`；`model` 仅用于 Blender 重新编辑 |
| 物理/通道 | 自定义包 `device.json` → 设备包 `debug/device.json` → 默认值 |
| 脚本 | 自定义包 `virtual.gd` → 设备包 `debug/virtual.gd` |
| 实例参数 | `virtual.json.devices[].props`，始终最优先（传给脚本） |

自定义脚本仍必须 `extends "res://sdk/virtual_device.gd"`，并遵守
[virtual-gd.md](virtual-gd.md)。脚本按可信代码执行。

## 6. Blender 插件交互

1. 插件有一个**模型列表**（project.json 中的设备），每行有“拖入场景”和“编辑”。
2. 点“编辑”弹出窗口：
   - “使用自定义虚拟包”开关；
   - 打开后显示文件夹路径输入；
   - 保存只修改该模型的默认设置，**不改场景里已有的实例**。
3. 之后拖入的模型在放置时读取设置并记录到实例根节点的 `hpm_override`：
   - 有覆盖：导入自定义模型，使用自定义 `device.json`/`virtual.gd`；
   - 无覆盖：使用设备包默认资产。
4. 关闭开关后，再拖入的模型恢复默认；之前放下的实例仍保留各自的覆盖。
5. 同一个模型可以先拖默认、再改设置拖覆盖，场景里两种实例共存；导出时按实例
   分别写 `virtual.json`。
6. 导出：
   - 复制每个实例用到的 override 包到 `<项目>/virtual/packages/`；
   - 缺 `manifest.json` 时自动生成；
   - `virtual.json` 按实例写 `override`；
   - 模型统一烘焙进 `virtual.glb`。

## 7. 校验与错误

- 文件夹里没有 `model.gltf` / `model.glb`：Blender 拒绝保存设置。
- 缺 `manifest.json`：允许，导出时自动生成。
- 缺 `virtual.gd` 且基础包也没有：报告“设备无脚本”，模型仍显示。
- 脚本加载失败：记录错误，不回退到基础脚本（避免行为悄悄改变）。
- 版本冲突：同时存在多个版本时选最高版本，并在报告里提示。

## 8. 示例

```text
examples/project2/virtual/packages/
  metal-servo-1.0.0/
    manifest.json
    device.json
    model.gltf
    virtual.gd
```

```json
{
  "type": "hpm-virtual-pack",
  "name": "metal-servo",
  "version": "1.0.0",
  "target": "pwm-stc90c51"
}
```
