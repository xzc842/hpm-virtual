# HPM Virtual Blender 插件

在 Blender 3D 视图侧栏（`HPM` 标签）里打开 HPM 项目、把设备包模型拖入场景、
编辑每个物体的摩擦、选择自定义虚拟包，并导出 `virtual/virtual.glb + virtual.json`。

## 安装

打包好的 zip：

```bash
tools/package_blender_addon.sh
# dist/hpm_virtual-1.0.1.zip
```

Blender：`编辑 > 偏好设置 > 获取扩展 > 从磁盘安装`，选择该 zip，启用 “HPM Virtual”。

开发时也可以直接加载：

```bash
blender --background --factory-startup --python-expr \
  "import sys; sys.path.insert(0, '$PWD/blender_addon'); import hpm_virtual; hpm_virtual.register()"
```

## 使用

1. 在侧栏填写 **项目目录**，点 **加载项目**。插件读取 `project.json`，
   从 `~/.hpm/packages` 找到每个设备的 `debug/device.json`、`device.gltf`。
2. **设备**面板列出模型。点 **拖入场景**：
   - 模型跟随鼠标在地面移动，左键放置，右键取消；
   - 已放置的设备再拖会替换原实例。
3. 点模型行末尾的 **编辑**，弹出窗口：
   - 打开 **使用自定义虚拟包**，填写文件夹路径，保存。
   - 只影响**之后拖入**的模型；已经在场景里的实例保持原来的覆盖。
   - 关掉开关再拖入，恢复设备包默认模型。
4. 自定义包文件夹内容：
   ```
   <folder>/
     model.gltf 或 model.glb   # 必需
     device.json               # 可选，覆盖按物体摩擦/通道
     virtual.gd                # 可选，覆盖设备脚本
     manifest.json             # 可选，缺省时导出自动生成
   ```
5. 选中网格物体，在 **物体摩擦** 面板修改摩擦/弹性/是否碰撞。导出时按物体写入
   `virtual.json` 的 `objects`（设备写入 `devices[].objects`）。
6. 点 **导出**，写出：
   - `<项目>/virtual/virtual.glb`
   - `<项目>/virtual/virtual.json`
   - 自定义包复制到 `<项目>/virtual/packages/<name>-<version>/`

## 坐标与节点

- Blender 默认米制；glTF 导出时自动做 Z-up → Y-up 转换。
- 设备根节点名就是项目里的设备名（`led`、`servo`），导出后 Godot 用同名节点绑定。
- 模型内部节点名建议保持设备包里的命名（如 `LedBody`、`ServoHorn`），
  否则 `device.json` 的按物体摩擦规则会找不到目标。

## 测试

```bash
tests/run_blender_addon_test.sh
```

脚本在无头 Blender 中：加载 `examples/real-project` → 放置 LED/舵机 → 修改摩擦 →
设置自定义包 → 导出 → 检查 `virtual.json` / GLB / 自动生成 manifest；
再用 Godot 打开导出工程验证覆盖脚本生效。
