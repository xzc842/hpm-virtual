# virtual.gd 规范（v1）

设备包在 `debug/virtual.gd` 提供的外部脚本，负责把调试输出映射成 3D 动作。
主程序负责网络、会话和节点生命周期，脚本只做“设备行为”。

> 外部脚本被视为可信代码：GDScript 权限等同于主程序本身，没有沙箱。

## 最小示例

```gdscript
extends "res://sdk/virtual_device.gd"

var _lamp: MeshInstance3D

func _on_bind(_ctx: Dictionary) -> void:
    _lamp = get_model_node("Lamp") as MeshInstance3D

func _on_values(values: Dictionary) -> void:
    if _lamp == null:
        return
    var on := bool(values.get("power", false))
    var material := StandardMaterial3D.new()
    material.emission_enabled = true
    material.emission = Color(0.2, 1.0, 0.3)
    material.emission_energy_multiplier = 1.6 if on else 0.0
    _lamp.material_override = material

func _on_session_start() -> void:
    log_info("调试开始")
```

## 生命周期

| 回调 | 时机 | 说明 |
| --- | --- | --- |
| `_on_bind(ctx)` | 模型加载、脚本挂载后 | 取节点引用、建灯光/材质；`ctx` 见下。 |
| `_on_session_start()` | 检测到调试开始 | 重置显示、准备动画。 |
| `_on_values(values)` | 该设备输出值变化 | `values` 是通道字典，例如 `{"power": true}`。 |
| `_on_session_stop()` | 调试结束/断线 | 复位到安全状态。 |
| `_on_tick(delta)` | 每帧 | 做平滑动画；**不要覆写 `_process`**。 |
| `_on_unbind()` | 场景销毁 | 释放自己创建的资源。 |

`ctx` 字段：`name`、`title`、`package`、`version`、`node_path`、`props`、`device`（`project.json` 里的设备配置）、`model`（设备根节点）。

## API

| 成员 | 说明 |
| --- | --- |
| `device_name` / `device_title` | 设备实例名/显示名。 |
| `model: Node3D` | 设备模型根节点。 |
| `props: Dictionary` | `virtual.json` 的实例参数。 |
| `active: bool` | 调试会话是否运行。 |
| `values: Dictionary` | 最近一次输出值。 |
| `send(channel, value)` | 写输入通道，内部 `POST /devices/input`。 |
| `invoke(channel)` | 触发按钮/动作通道。 |
| `get_value(channel, default)` | 读最近值。 |
| `get_model_node(path := "")` | 取模型下节点；为空返回模型根节点。 |
| `log_info/warn/error(message)` | 带设备前缀的日志。 |

## 数据流

```
hpm-gui 调试服务
  GET /debugger             ← 主程序每 1.5s 探测会话
  GET /outputs/stream (SSE) ← 会话开始后长连接，snapshot + 变化推送
        │
        ▼
   Bridge（Autoload） 按 device 名分发
        │
        ▼
   virtual.gd._on_values({"power": true})
        │
        ▼
   修改 3D 节点（材质、旋转、骨骼……）
```

反向输入：

```
3D 交互 / 脚本
  → send("tx", "hello") / invoke("send")
  → POST /devices/input
  → 固件/设备仿真
```

主程序只在调试会话 active 且 `/debugger.project` 与当前项目一致时连接输出流；
输出流的 `snapshot` 在连接时给出全量初值，之后只在变化时推送，断线 1 秒后重连。

## 约束

1. 必须 `extends "res://sdk/virtual_device.gd"`。
2. 不要自己发 HTTP 请求，统一用 `send()` / `invoke()`，便于主程序做会话判断和排队。
3. 只依赖 `res://sdk/` 和自身目录内的文件；脚本会被复制到 `user://pkg_cache/` 后加载。
4. 不要 `queue_free()` 模型节点；设备生命周期由主程序管理。
5. 设备节点/子节点可能因 GLB 命名变化而不同，优先用 `get_model_node()` 并判空。
6. 通道名与调试服务 `/devices` 返回的 `channels[].id` 一致。
