# virtual.json 规范（v1）

`<项目>/virtual/virtual.json` 是虚拟场景的**运行时权威描述**，由 Blender 插件导出，
Godot 打开项目时读取。`virtual.glb` 里同一场景的节点名必须与这里的 `node` 对应。

## 完整示例

```json
{
  "version": 1,
  "scene": "virtual.glb",
  "physics": { "friction": 0.75, "rough": true },
  "objects": [
    { "node": "Environment/Floor", "physics": { "friction": 0.9, "rough": true } }
  ],
  "devices": [
    {
      "name": "led",
      "title": "演示 LED",
      "node": "Devices/led",
      "package": "led-demo",
      "version": "1.0.0",
      "script": "debug/virtual.gd",
      "props": { "color": "green" }
    }
  ],
  "environment": { "gravity": -9.81 }
}
```

## 字段

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `version` | int | 是 | 目前为 `1`。 |
| `scene` | string | 否 | GLB 文件名，默认 `virtual.glb`，相对 `virtual/`。 |
| `physics` | object | 否 | 场景内所有网格的默认物理参数。 |
| `objects` | array | 否 | 按节点覆盖物理参数。 |
| `devices` | array | 否 | 虚拟设备实例。 |
| `environment` | object | 否 | 预留：重力等全局参数。 |

### physics

```json
{ "friction": 0.8, "rough": true, "bounce": 0.0, "absorbent": false, "enabled": true }
```

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `friction` | `0.8` | 0–1，按物体生效。 |
| `rough` | `true` | Godot `PhysicsMaterial.rough`。为 `false` 时引擎按双方材质合成摩擦。 |
| `bounce` | `0.0` | 0–1。 |
| `absorbent` | `false` | Godot `PhysicsMaterial.absorbent`。 |
| `enabled` | `true` | 为 `false` 时该物体不生成碰撞体。 |

### objects[]

```json
{ "node": "Environment/Floor", "physics": { ... } }
```

- `node` 相对 GLB 根节点；找不到时按节点名递归查找。
- 规则对匹配节点本身及其所有子网格生效；更深的覆盖优先。
- 未匹配的网格使用 `physics`，再没有就用 `0.8`。

### devices[]

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `name` | 是 | 对应 `project.json` 的 `devices` key；调试服务按它识别设备。 |
| `node` | 是 | 设备模型在 GLB 里的节点路径，相对根节点。 |
| `package` | 是 | 设备包 manifest 的 `name`。 |
| `version` | 否 | 期望版本；缺失时取最高版本并提示。 |
| `script` | 否 | 覆盖 `device.json` 的 `script`。 |
| `model` | 否 | 覆盖 `device.json` 的 `model`（给 Blender 插件用）。 |
| `props` | 否 | 传给脚本 `_on_bind(ctx.props)` 的实例参数。 |
| `title` | 否 | 显示名；运行时会被调试服务返回的 `title` 覆盖。 |

## 加载规则

1. 读 `virtual/virtual.json` 和 `virtual/virtual.glb`；GLB 缺失时进入占位环境并给出警告。
2. 先按 `devices[].node` 找设备节点，找不到再按 `name` 递归找；仍找不到记入报告。
3. 场景物理跳过所有设备子树，设备摩擦由 `device.json` 决定，避免双重覆盖。
4. 每个设备实例独立解析包、脚本和物理；单个设备失败不影响其它设备。
5. 设备节点缺失或包缺失只报告，不阻止场景打开。

## 与 project.json 的关系

- `project.json`：MCU 与设备驱动配置（`driver`、`pin`、`config`），调试服务的设备清单来源。
- `virtual.json`：模型、节点、包版本、脚本、物理，只描述“长什么样、怎么动”。
- 两份都用 `devices.<name>` 作为设备实例的 key，不重复保存 `driver/pin/config`。
