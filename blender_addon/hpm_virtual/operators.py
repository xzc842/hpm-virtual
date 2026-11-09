# Copyright (C) 2026 XueZicheng <xuezicheng842@outlook.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

"""Blender 操作符：加载项目、拖入设备、编辑模型设置、导出。"""

from __future__ import annotations

import json
import os

import bpy
from bpy_extras import view3d_utils
from mathutils import Vector

from . import data, exporter, scene, state


class HPM_OT_load_project(bpy.types.Operator):
    bl_idname = "hpm_virtual.load_project"
    bl_label = "加载 HPM 项目"
    bl_description = "读取 project.json、设备包和自定义虚拟包"

    def execute(self, context):
        scene.migrate_legacy_props()
        path = state.get_project_path(context).strip()
        if not path:
            self.report({"ERROR"}, "请先选择项目目录")
            return {"CANCELLED"}

        auto_opened = False
        blend_path = os.path.join(path, "virtual", "virtual.blend")
        if os.path.isfile(blend_path) and not _same_file(bpy.data.filepath, blend_path):
            try:
                bpy.ops.wm.open_mainfile(filepath=blend_path)
            except RuntimeError as exc:
                self.report({"ERROR"}, f"打开 {blend_path} 失败：{exc}")
                return {"CANCELLED"}
            auto_opened = True
            context = bpy.context
            scene.migrate_legacy_props()
            if not context.scene.hpm_project_path:
                context.scene.hpm_project_path = path

        overrides = {}
        for name, setting in state.get_model_settings(context).items():
            if setting.get("use_custom_pack") and setting.get("custom_pack_path"):
                overrides[name] = {"path": setting["custom_pack_path"]}
        try:
            project = data.load_project(path, overrides)
        except ValueError as exc:
            self.report({"ERROR"}, str(exc))
            return {"CANCELLED"}
        state.store_project(context, project)
        if not auto_opened and not scene.device_roots():
            _import_project_models(context, path, project)
        errors = [entry["name"] for entry in project["devices"] if entry.get("error")]
        if errors:
            self.report({"WARNING"}, "部分设备有问题：" + ", ".join(errors))
        self.report({"INFO"}, f"已加载 {len(project['devices'])} 个设备")
        return {"FINISHED"}


class HPM_OT_refresh_project(bpy.types.Operator):
    bl_idname = "hpm_virtual.refresh_project"
    bl_label = "刷新项目"
    bl_description = "重新扫描设备包和自定义虚拟包，保留已放置对象"

    def execute(self, context):
        scene.migrate_legacy_props()
        return bpy.ops.hpm_virtual.load_project()


class HPM_OT_place_device(bpy.types.Operator):
    bl_idname = "hpm_virtual.place_device"
    bl_label = "拖入场景"
    bl_description = "导入设备模型；移动鼠标确定位置，左键放置，右键取消"
    bl_options = {"REGISTER", "UNDO"}

    device_name: bpy.props.StringProperty()

    _root: bpy.types.Object | None = None
    _region = None
    _rv3d = None

    def execute(self, context):
        entry = state.resolve_entry(context, self.device_name)
        if entry is None:
            self.report({"ERROR"}, f"未知设备：{self.device_name}")
            return {"CANCELLED"}
        if entry.get("error") and not entry.get("model_path"):
            self.report({"ERROR"}, entry["error"])
            return {"CANCELLED"}
        project = state.get_project(context)
        try:
            scene.place_device(context, project, entry,
                               location=context.scene.cursor.location.copy())
        except (OSError, RuntimeError) as exc:
            self.report({"ERROR"}, str(exc))
            return {"CANCELLED"}
        return {"FINISHED"}

    def invoke(self, context, event):
        if context.area is None or context.area.type != "VIEW_3D":
            return self.execute(context)
        entry = state.resolve_entry(context, self.device_name)
        if entry is None:
            self.report({"ERROR"}, f"未知设备：{self.device_name}")
            return {"CANCELLED"}
        project = state.get_project(context)
        try:
            self._root = scene.place_device(context, project, entry,
                                            location=context.scene.cursor.location.copy())
        except (OSError, RuntimeError) as exc:
            self.report({"ERROR"}, str(exc))
            return {"CANCELLED"}
        self._region = context.region
        self._rv3d = context.region_data
        context.window_manager.modal_handler_add(self)
        return {"RUNNING_MODAL"}

    def modal(self, context, event):
        if event.type == "MOUSEMOVE" and self._region is not None and self._rv3d is not None:
            location = self._ground_location(event)
            if location is not None and self._root is not None:
                self._root.location = location
            return {"RUNNING_MODAL"}
        if event.type in {"LEFTMOUSE", "RET", "NUMPAD_ENTER"} and event.value == "RELEASE":
            return {"FINISHED"}
        if event.type in {"RIGHTMOUSE", "ESC"} and event.value == "PRESS":
            if self._root is not None:
                scene.remove_hierarchy(self._root)
            return {"CANCELLED"}
        return {"RUNNING_MODAL"}

    def _ground_location(self, event) -> Vector | None:
        coord = (event.mouse_region_x, event.mouse_region_y)
        origin = view3d_utils.region_2d_to_origin_3d(self._region, self._rv3d, coord)
        direction = view3d_utils.region_2d_to_vector_3d(self._region, self._rv3d, coord)
        if abs(direction.z) < 1e-6:
            return None
        t = -origin.z / direction.z
        if t < 0:
            return None
        return origin + direction * t


class HPM_OT_remove_device(bpy.types.Operator):
    bl_idname = "hpm_virtual.remove_device"
    bl_label = "从场景移除"
    bl_description = "删除该设备实例"
    bl_options = {"REGISTER", "UNDO"}

    device_name: bpy.props.StringProperty()

    def execute(self, context):
        scene.remove_device(self.device_name)
        return {"FINISHED"}


class HPM_OT_add_floor(bpy.types.Operator):
    bl_idname = "hpm_virtual.add_floor"
    bl_label = "添加地板"
    bl_description = "添加一块 4x4 米、摩擦 0.9 的地板"
    bl_options = {"REGISTER", "UNDO"}

    def execute(self, context):
        scene.add_floor(context)
        return {"FINISHED"}


class HPM_OT_edit_device(bpy.types.Operator):
    bl_idname = "hpm_virtual.edit_device"
    bl_label = "模型设置"
    bl_description = "设置该模型拖入场景时使用的自定义虚拟包"
    bl_options = {"REGISTER"}

    device_name: bpy.props.StringProperty()
    use_custom_pack: bpy.props.BoolProperty(
        name="使用自定义虚拟包", default=False,
    )
    custom_pack_path: bpy.props.StringProperty(
        name="文件夹", subtype="DIR_PATH", default="",
    )

    def invoke(self, context, event):
        setting = state.get_setting(context, self.device_name)
        self.use_custom_pack = bool(setting.get("use_custom_pack", False))
        self.custom_pack_path = str(setting.get("custom_pack_path", ""))
        return context.window_manager.invoke_props_dialog(self, width=520)

    def draw(self, context):
        layout = self.layout
        layout.prop(self, "use_custom_pack")
        if self.use_custom_pack:
            layout.prop(self, "custom_pack_path")
            box = layout.box()
            box.label(text="文件夹内提供：", icon="INFO")
            box.label(text="model.gltf / model.glb（必需）")
            box.label(text="device.json（可选，按物体摩擦）")
            box.label(text="virtual.gd（可选，设备脚本）")
        else:
            layout.label(text="关闭后，新拖入的模型恢复为设备包默认资产")

    def execute(self, context):
        path = self.custom_pack_path.strip()
        if self.use_custom_pack and not path:
            self.report({"ERROR"}, "请填写自定义虚拟包文件夹")
            return {"CANCELLED"}
        if self.use_custom_pack:
            if not os.path.isdir(path):
                self.report({"ERROR"}, f"文件夹不存在：{path}")
                return {"CANCELLED"}
            if not _folder_has_model(path):
                self.report({"ERROR"}, "文件夹里没有找到 model.gltf / model.glb")
                return {"CANCELLED"}
        state.set_setting(context, self.device_name, {
            "use_custom_pack": self.use_custom_pack,
            "custom_pack_path": path,
        })
        self.report({"INFO"}, "已保存；只影响之后拖入的模型")
        return {"FINISHED"}


def _folder_has_model(path: str) -> bool:
    for entry in os.listdir(path):
        if entry.lower().endswith((".gltf", ".glb")) and os.path.isfile(os.path.join(path, entry)):
            return True
    return False


class HPM_OT_export_project(bpy.types.Operator):
    bl_idname = "hpm_virtual.export_project"
    bl_label = "导出虚拟场景"
    bl_description = "写出 virtual/virtual.glb 与 virtual/virtual.json"
    bl_options = {"REGISTER"}

    def execute(self, context):
        project = state.get_project(context)
        if not project["root"]:
            self.report({"ERROR"}, "请先加载项目")
            return {"CANCELLED"}
        try:
            result = exporter.export_project(project)
        except Exception as exc:  # Blender 导出异常类型不稳定
            self.report({"ERROR"}, f"导出失败：{exc}")
            return {"CANCELLED"}
        context.scene.hpm_last_export = json.dumps(result, ensure_ascii=False)
        for warning in result.get("warnings", []):
            self.report({"WARNING"}, warning)
        self.report({"INFO"}, f"已导出 {len(result['devices'])} 个设备：{result['glb']}")
        return {"FINISHED"}


def _import_project_models(context, project_dir: str, project: dict) -> None:
    glb_path = os.path.join(project_dir, "virtual", "virtual.glb")
    if not os.path.isfile(glb_path):
        return
    virtual = data.read_json(os.path.join(project_dir, "virtual", "virtual.json"))
    instances = {item.get("name"): item for item in virtual.get("devices", [])}
    bpy.ops.import_scene.gltf(filepath=glb_path)
    for entry in project.get("devices", []):
        name = entry["name"]
        root = scene.find_object(name)
        if root is None:
            continue
        inst = instances.get(name, {})
        root.hpm_device = json.dumps({
            "name": name,
            "driver": entry.get("driver", ""),
            "package": entry.get("package", ""),
            "version": entry.get("version", ""),
        }, ensure_ascii=False)
        root.hpm_props = json.dumps(inst.get("props", {}), ensure_ascii=False)
        override = entry.get("override") or {}
        if override:
            root.hpm_override = json.dumps({
                "name": override.get("name", ""),
                "version": override.get("version", ""),
                "path": override.get("path", ""),
            }, ensure_ascii=False)
        base = entry.get("device_json", {})
        merged_objects = list(inst.get("objects", [])) + list(base.get("objects", []))
        merged_physics = dict(base.get("physics", {}))
        merged_physics.update(inst.get("physics", {}))
        scene.apply_device_physics(root, {"physics": merged_physics, "objects": merged_objects})


def _same_file(a: str, b: str) -> bool:
    return bool(a) and bool(b) and os.path.abspath(a) == os.path.abspath(b)
