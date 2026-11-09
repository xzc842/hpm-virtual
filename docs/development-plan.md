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
  blender_addon/hpm_virtual/# Blender 插件：模型列表/拖入/摩擦/自定义包/导出
  examples/demo-project/    # 内嵌演示设备包，不依赖 ~/.hpm
  examples/real-project/    # 真实 gpio/pwm 设备包 + 虚拟场景
  examples/blink/           # 完整固件工程：stc90c51 + gpio LED 闪烁
  tools/build_demo_assets.gd   # 生成演示 GLB/glTF
  tools/build_device_assets.gd # 直接生成模型到已安装设备包
  tools/mock_debug_service.py  # 模拟 hpm-gui 调试服务
  tests/smoke_test.gd          # 55 项无头检查
  tests/real_packages_test.gd  # 18 项真实设备包检查
  tests/override_test.gd       # 9 项自定义虚拟包解析检查
  tests/ruler_input_test.tscn  # 标尺射线取点/右键删除
  tests/interaction_test.tscn  # 交互注册/悬停高亮/触发
  tests/blender_addon_test.py  # Blender 无头端到端测试
  tests/pwm_plugin_test.c      # pwm debug.c 单元测试
```

### 运行

```bash
# 编辑器
godot --path .
# 无头测试
godot --headless --path . --script res://tests/smoke_test.gd
# 直接打开演示项目（-- 之后是用户参数）
godot --path . -- --project=examples/demo-project
# 真实设备包工程
godot --path . -- --project=examples/real-project
# Blink 完整工程（先用 hpm build，见 examples/blink/README.md）
godot --path . -- --project=examples/blink
# 测试
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --script res://tests/real_packages_test.gd
godot --headless --path . --script res://tests/override_test.gd
tests/run_pwm_plugin_test.sh
tests/run_blender_addon_test.sh
```

演示工程使用项目内 `packages/`，因此不依赖 `~/.hpm/packages` 也能测试。
真实设备虚拟资产直接放在 `~/.hpm/packages/gpio-*/debug` 与
`~/.hpm/packages/pwm-stc90c51-*/debug`，仓库不再保留副本。

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
- [x] 真实设备包：gpio(LED) 与 pwm(舵机) 的 `device.json`、`device.gltf`、`virtual.gd` 安装进包。
- [x] pwm 的 `debug.c`：监听 PWM 引脚，高电平占空比 5%–10% 映射到 0–180°。
- [x] 模型节点按设备类型加前缀（`LedBody`、`ServoHorn`），避免 GLB 内重名重命名。
- [x] 真实设备工程、18 项包测试、PWM 插件单元测试、截图验证。
- [x] 自定义虚拟包运行时解析（`override` 字符串/对象/路径、项目内 `virtual/packages`）。
- [x] Blender 插件：模型列表、模态拖入、“编辑”弹窗（开关 + 文件夹路径）、按物体摩擦、导出。
- [x] 自定义包只影响新拖入的实例；场景里已有实例保持各自的 `hpm_override`。
- [x] 导出时复制覆盖包、缺 manifest 自动生成、GLB 节点与 `virtual.json` 对齐。
- [x] Blink 完整工程：`project.toml/json`、`main.c`、`debug.toml`、`run.sh`、虚拟场景；
  `hpm sync/build` 通过，模拟器输出 `power=on/off`。
- [x] 相机 WASD/QE/方向键控制 + 状态栏提示。
- [x] 选择/标尺工具栏、射线高亮与交互触发、透明蓝色标尺（m/cm 自适应、多条、右键删除）。
- [x] 外部脚本 API：`register_interaction()`、`draw_ruler()`、`get_scene_root()`。
- [x] `logo.png` 启动画面与欢迎页 Logo。

## 5. 下一步（按优先级）

1. **交互输入**：3D 点击/拖拽 → `send()/invoke()`；HUD 按 `/devices` 的 `channels` 生成控件。
2. **动画/物理细化**：带骨骼设备的 `_on_tick`，摩擦系数实测标定（`rough` 组合规则），刚体/关节场景。
3. **健壮性**：SSE `reset`/缺口、会话中断重连、包版本不匹配提示、日志面板。
4. **Blender 原生拖拽**：Asset Browser 资源库（当前是模态放置）。
5. **打包**：Linux/Windows 导出模板，插件 zip，演示视频/文档。

## 6. 验证

- 无头冒烟：55 项（SSE 分块/CRLF、项目解析、包解析、GLB、摩擦数值、脚本加载与发光）。
- 真实设备包：18 项（包解析、模型节点、13 个碰撞体、舵机摆臂摩擦/旋转、LED 颜色与发光、实例级物理覆盖）。
- PWM 插件：8 项（ABI、初始 90°、1ms→0°、1.5ms→90°、2ms→180°）。
- 自定义包解析：9 项（按名/路径、device.json/脚本覆盖、缺失回退）。
- 交互：注册/提示/触发/悬停高亮/射线命中设备。
- 标尺：射线取两点、单位自适应、右键命中删除。
- Blender 插件：加载真实工程 → 放置 LED/舵机 → 编辑摩擦 → 覆盖模型 → 导出 →
  自动生成 manifest；导出工程再由 Godot 打开，日志出现 `OVERRIDE LED BOUND`。
- 端到端：[tools/mock_debug_service.py](../tools/mock_debug_service.py) 同时推送 LED 与舵机值，
  截图见 [real-devices.png](images/real-devices.png)。
- Blink 固件：`hpm sync --offline && hpm build` 成功；`hpm debug --json --run` 连续输出
  `power=on/off`。
- 待补：真实 hpm-gui 会话的自动化断言、输入 POST 的自动化断言。

## 7. 已知限制

- Blender 插件用模态放置代替原生拖拽；自定义面板无法直接支持拖出到 3D 视图。
- pwm 的 `debug.c` 需要 `hpm debug` 在调试时重新编译插件；旧的已编译 `.so` 不会自动更新。
- 设备模型动画节点如果有骨骼，按物体生成的静态碰撞不会跟随骨骼，需要后续改成动态碰撞。
- 输出流只处理 `snapshot/device/reset`；`/events/stream` 的日志/断点事件未接入。
- 没有多板卡/多项目并行，一个进程同时只打开一个项目。
