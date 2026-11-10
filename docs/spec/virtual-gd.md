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

`ctx` 字段：`name`、`title`、`package`、`version`、`node_path`、`props`、`config`（已按类型转换的设备配置）、`device`（`project.json` 里的设备配置）、`model`（设备根节点）、`scene_root`（整个场景根）、`sim`（SimView）。

### 交互

```gdscript
func _on_bind(_ctx: Dictionary) -> void:
    register_interaction("toggle", _on_click, "点击切换本地高亮")

func _on_click() -> void:
    log_info("被点击了")
```

- 只有注册过交互的设备才会在“选择”模式下高亮并显示提示；没有注册则鼠标直接穿过。
- 交互回调在点击时同步执行，不要做长时间阻塞。
- 多个交互时点击触发第一个；可用 `trigger_interaction(id)` 指定。

### 标尺与场景

```gdscript
func _on_bind(_ctx: Dictionary) -> void:
    var root := get_scene_root()          # 整个 virtual.glb 场景
    var floor := get_scene_node("Environment/Floor")
    draw_ruler(Vector3(-0.2, 0, 0), Vector3(0.2, 0, 0), "宽度")
```

- 坐标是世界坐标；标尺默认透明蓝色，单位在 m/cm 之间自动切换。
- `draw_ruler()` 返回 id，可用 `update_ruler(id, from, to, label)` 原地更新，
  用 `remove_ruler(id)` 删除单条。
- 标尺不受设备生命周期限制；脚本退出时可用 `clear_rulers()` 清理。

## API

| 成员 | 说明 |
| --- | --- |
| `device_name` / `device_title` | 设备实例名/显示名。 |
| `model: Node3D` | 设备模型根节点。 |
| `props: Dictionary` | `virtual.json` 的实例参数。 |
| `config: Dictionary` | 设备包 `config` 解析后的值。 |
| `get_config(key, default)` | 读 config；number/bool/string 已转换。 |
| `active: bool` | 调试会话是否运行。 |
| `values: Dictionary` | 最近一次输出值。 |
| `register_interaction(id, callback, hint)` | 注册可点击交互；选择模式悬停高亮，左键触发。 |
| `unregister_interaction(id)` / `clear_interactions()` | 移除交互。 |
| `has_interaction()` / `get_interaction_hint()` | 查询是否可交互/提示文本。 |
| `trigger_interaction(id := "")` | 主动触发交互（默认第一个）。 |
| `get_scene_root()` / `get_scene_node(path)` | 只读访问整个虚拟场景。 |
| `draw_ruler(from, to, label := "")` | 在世界坐标画标尺，返回 id；支持多条。 |
| `update_ruler(id, from, to, label := "")` | 原地更新标尺，返回是否成功。 |
| `remove_ruler(id)` / `clear_rulers()` | 删除单条/全部标尺。 |
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
