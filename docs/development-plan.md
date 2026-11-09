# hpm-virtual 开发方案与进度

## 1. 目标与已确定的决策

- Godot 4.7 独立程序：欢迎页打开 HPM 项目 → 加载 `virtual/` → 连接 hpm-gui 调试服务 → 由设备包的外部脚本驱动 3D 模型。
- **摩擦按物体**：每个网格节点一个 `StaticBody3D + PhysicsMaterial`，参数写在 `device.json`（设备）或 `virtual.json`（场景）。
- **外部脚本可信**：`debug/virtual.gd` 直接加载执行，不做沙箱。
- **长连接**：检测到调试开始后连 `GET /outputs/stream`（SSE），断线重连；设备输出按设备名分发给对应脚本。
- 规范：[virtual.json](spec/virtual-json.md)、[device.json](spec/device-json.md)、[virtual.gd](spec/virtual-gd.md)。

## 2. 当前实现

```
res://
  app/main.tscn|gd          # 启动、欢迎页、HUD、项目打开流程
  app/sim_view.gd           # 场景加载、摩擦、设备绑定、信号分发
  core/project_context.gd   # Autoload App：项目/最近项目/virtual.json
  core/package_resolver.gd  # 包扫描与设备解析
  core/script_host.gd       # debug/ 缓存到 user://pkg_cache 后加载
  core/model_loader.gd      # GLTFDocument 运行时读绝对路径
  core/physics_builder.gd   # 按物体生成静态碰撞与摩擦
  core/debug_service.gd     # Autoload Bridge：会话探测、SSE、输入
  core/sse_parser.gd        # text/event-stream 解析
  sdk/virtual_device.gd     # 外部脚本基类
  examples/demo-project/    # 可直接运行的演示工程 + 演示设备包
  tools/build_demo_assets.gd# 无 Blender 生成演示 GLB/glTF
  tests/smoke_test.gd       # 43 项无头检查
```

### 运行

```bash
# 编辑器
godot --path .
# 无头测试
godot --headless --path . --script res://tests/smoke_test.gd
# 直接打开演示项目（-- 之后是用户参数）
godot --path . -- --project=examples/demo-project
```

演示工程使用项目内 `packages/`，因此不依赖 `~/.hpm/packages` 也能测试。

## 3. 数据流

```
project.json ── 设备名/driver/pin ──┐
virtual/virtual.json ── 设备实例 → 包/节点/脚本
virtual/virtual.glb ───────────────┘
        │
        ▼
  SimView 加载 GLB → 按物体建摩擦 → 解析包 → 挂载 virtual.gd
        │
        ▼
  Bridge 每 1.5s GET /debugger
        │ active && project 匹配
        ▼
  GET /outputs/stream (SSE)  ── snapshot + device 事件
        │
        ▼
  device_values(device, values) → 对应脚本 _on_values()
        │
        ▼
  修改 3D 节点（材质/旋转/骨骼）

脚本 send()/invoke() → POST /devices/input → 固件仿真
```

### 会话状态

| 状态 | 含义 |
| --- | --- |
| `offline` | 调试服务不可达 |
| `idle` | 服务可达，但没有调试会话 |
| `running` | 会话 active 且项目路径匹配，输出流连接/重连中 |
| `other_project` | 调试器正在调试别的项目，不接管 |

## 4. 已完成（M0–M3 核心）

- [x] 欢迎页、打开目录、最近项目、缺少 `virtual/` 的引导（占位环境 / 启动 Blender）。
- [x] GLB 运行时加载（支持用户目录绝对路径）。
- [x] 按物体摩擦：`physics` 默认值 + `objects` 覆盖；场景物理跳过设备子树。
- [x] 包解析（`$HPM_PACKAGES_DIR`、项目内 `packages/`、`~/.hpm/packages`）。
- [x] `virtual.gd` 缓存加载，生命周期回调与 `send/invoke`。
- [x] `/debugger` 探测、项目路径校验、SSE 输出流、自动重连、输入队列。
- [x] 演示工程 + 演示包 + 无头测试 + 模拟服务端到端验证。

## 5. 下一步（按优先级）

1. **Blender 插件**（M4）：读项目/包列表、放置设备、编辑每个物体摩擦、导出 `virtual.glb + virtual.json`。
   - 自定义面板不支持原生拖拽，采用 Asset Browser + 模态放置算子。
   - `device.json` 的 `objects` 由对象自定义属性/材质面板生成。
2. **真实设备包**：给 `~/.hpm/packages/*/debug/` 补 `device.json`、`device.gltf`、`virtual.gd`；先做 LED、按键、串口、舵机。
3. **交互输入**：3D 点击/拖拽 → `send()/invoke()`；HUD 按 `/devices` 的 `channels` 生成控件。
4. **动画/物理细化**：带骨骼设备的 `_on_tick`，摩擦系数实测标定（`rough` 组合规则），刚体/关节场景。
5. **健壮性**：SSE `reset`/缺口、会话中断重连、包版本不匹配提示、日志面板。
6. **打包**：Linux/Windows 导出模板，插件 zip，演示视频/文档。

## 6. 验证

- 无头冒烟：43 项（SSE 分块/CRLF、项目解析、包解析、GLB、摩擦数值、脚本加载与发光）。
- 端到端：[tools/mock_debug_service.py](../tools/mock_debug_service.py) 模拟 `/debugger`、`/devices`、`/outputs/stream`，
  运行后能看到 `调试会话开始` 和 `LED 亮`。
- 待补：真实 hpm-gui 会话、输入 POST 的自动化断言、Blender 导出回读。

## 7. 已知限制

- 当前 Blender 只做到“启动程序”，插件本身尚未实现。
- 设备模型动画节点如果有骨骼，按物体生成的静态碰撞不会跟随骨骼，需要后续改成动态碰撞。
- 输出流只处理 `snapshot/device/reset`；`/events/stream` 的日志/断点事件未接入。
- 没有多板卡/多项目并行，一个进程同时只打开一个项目。
