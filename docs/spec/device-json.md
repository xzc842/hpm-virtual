# device.json 规范（v1）

设备包在 `debug/` 下提供的设备描述文件：`<pkg>/debug/device.json`。
Blender 插件用它加载模型并摆放；Godot 运行时用它加载外部脚本和**按物体的摩擦参数**。

## 完整示例

```json
{
  "name": "led",
  "display_name": "演示 LED",
  "version": "1.0.0",
  "model": "device.gltf",
  "script": "virtual.gd",
  "physics": { "friction": 0.6, "rough": true, "bounce": 0.05 },
  "objects": [
    { "node": "Body", "physics": { "friction": 0.6 } },
    { "node": "Lamp", "physics": { "friction": 0.3, "bounce": 0.2 } }
  ],
  "defaults": { "power": false },
  "channels": {
    "power": { "title": "电源", "type": "bool", "widget": "checkbox" }
  },
  "mount": { "type": "board" }
}
```

## 字段

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `name` | 是 | 设备类型名，通常与 `project.json` 的 `driver` 对应。 |
| `display_name` | 否 | 界面显示名，缺省用 `name`。 |
| `version` | 否 | 资产版本；包版本以 `manifest.json` 为准。 |
| `model` | 否 | 模型文件，相对 `debug/`，默认 `device.gltf`。 |
| `script` | 否 | 外部脚本，相对 `debug/`，默认 `virtual.gd`。 |
| `physics` | 否 | 设备模型的默认摩擦参数。 |
| `objects` | 否 | 按物体覆盖摩擦参数。 |
| `defaults` | 否 | 脚本 `_on_bind` 时的初始 props（预留）。 |
| `channels` | 否 | 控件描述；运行时以调试服务 `/devices` 为准。 |
| `mount` | 否 | 预留：`board` / `free`，供 Blender 插件决定吸附方式。 |

### physics / objects

与 `virtual.json` 完全一致，见 [virtual-json.md](virtual-json.md#physics)。
自定义虚拟包可以提供自己的 `device.json`，覆盖这里的默认值。

- `physics` 是该设备所有网格的默认值，未写时用 `0.8`。
- `objects[].node` 相对设备模型根节点（如 `Body`、`Lamp`）。
- 匹配规则对节点及其子网格生效；更深层覆盖优先。
- 摩擦按**物体**（网格节点）生成 `StaticBody3D + PhysicsMaterial`，不按面拆分。

### 模型与脚本的目录约定

```
<pkg>/
  manifest.json
  debug/
    device.json
    device.gltf        # 纯文本，buffer 以 base64 内嵌
    virtual.gd
```

`script` / `model` 也可以写带目录的路径（相对包根），例如 `debug/virtual.gd`。

包内不允许二进制文件，`device.gltf` 的 buffer 必须用 base64 内嵌
（`uri` 为 `data:application/octet-stream;base64,...`），不要使用外部 `.bin`。
工具 [tools/gltf_embed.gd](../tools/gltf_embed.gd) / [tools/embed_gltf_buffers.py](../tools/embed_gltf_buffers.py)
可以自动完成转换。

## 包解析

Godot 依次在以下目录查找包：

1. `$HPM_PACKAGES_DIR`（冒号分隔，便于测试/本地开发）
2. `<项目>/packages/`
3. `<项目>/.hpm/packages/`
4. `~/.hpm/packages/`

匹配顺序：

1. `manifest.name == virtual.json.devices[].package`（并校验 `version`、`chip`）；
2. 失败时用 `project.json.devices.<name>.driver` 反查；
3. 都失败则记录“找不到设备包”，设备模型仍显示但不绑定脚本。

版本选择：指定 `version` 时优先精确匹配，否则按版本号从高到低取第一个。

## 与调试服务的关系

`device.json` **不保存运行时的值**。设备输出值来自
`GET /outputs/stream` 的 `snapshot` / `device` 事件，写入输入走
`POST /devices/input`；两者都由主程序转发给 `virtual.gd`。
