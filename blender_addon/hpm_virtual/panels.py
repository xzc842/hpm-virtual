"""Blender 3D 视图侧栏面板。"""

from __future__ import annotations

import json

import bpy

from . import scene, state


class HPM_PT_project(bpy.types.Panel):
    bl_label = "HPM 虚拟项目"
    bl_idname = "HPM_PT_project"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "HPM"

    def draw(self, context):
        layout = self.layout
        scene_data = context.scene
        layout.prop(scene_data, "hpm_project_path", text="项目目录")
        row = layout.row(align=True)
        row.operator("hpm_virtual.load_project", text="加载项目", icon="FILE_FOLDER")
        row.operator("hpm_virtual.refresh_project", text="", icon="FILE_REFRESH")
        row = layout.row(align=True)
        row.operator("hpm_virtual.add_floor", text="添加地板", icon="MESH_PLANE")
        row.operator("hpm_virtual.export_project", text="导出", icon="EXPORT")

        entries = state.get_entries(context)
        if entries:
            layout.label(text=f"MCU: {scene_data.hpm_mcu}  设备: {len(entries)}")
        last = str(scene_data.hpm_last_export or "")
        if last:
            try:
                result = json.loads(last)
                layout.label(text=f"已导出：{len(result.get('devices', []))} 个设备", icon="CHECKMARK")
            except ValueError:
                pass


class HPM_PT_devices(bpy.types.Panel):
    bl_label = "设备"
    bl_idname = "HPM_PT_devices"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "HPM"
    bl_parent_id = "HPM_PT_project"
    bl_options = {"DEFAULT_CLOSED"}

    def draw(self, context):
        layout = self.layout
        entries = state.get_entries(context)
        if not entries:
            layout.label(text="先加载项目")
            return
        for entry in entries:
            name = str(entry.get("name", ""))
            root = scene.find_device_root(name)
            setting = state.get_setting(context, name)
            box = layout.box()
            row = box.row()
            row.label(text=name, icon="MESH_DATA")
            row.label(text="已放置" if root else "未放置")
            row = box.row()
            row.label(text=f"{entry.get('driver', '')} · {entry.get('package', '')} {entry.get('version', '')}")
            if entry.get("error"):
                box.label(text=entry["error"], icon="ERROR")
            row = box.row(align=True)
            if root:
                row.operator("hpm_virtual.remove_device", text="移除", icon="TRASH").device_name = name
            row.operator("hpm_virtual.place_device",
                         text="拖入场景" if not root else "重新拖入",
                         icon="IMPORT").device_name = name
            row.operator("hpm_virtual.edit_device", text="编辑", icon="PREFERENCES").device_name = name

            if setting.get("use_custom_pack"):
                path = str(setting.get("custom_pack_path", ""))
                box.label(text="自定义虚拟包：" + path, icon="PACKAGE")
            else:
                box.label(text="使用设备包默认模型")


class HPM_PT_friction(bpy.types.Panel):
    bl_label = "物体摩擦"
    bl_idname = "HPM_PT_friction"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "HPM"
    bl_parent_id = "HPM_PT_project"

    def draw(self, context):
        layout = self.layout
        obj = context.active_object
        if obj is None or obj.type != "MESH":
            layout.label(text="选中一个网格物体后编辑")
            return
        layout.label(text=f"对象：{obj.name}")
        owner = "设备" if obj.hpm_physics_owner == "device" else "环境"
        layout.label(text=f"归属：{owner}")
        column = layout.column(align=True)
        column.prop(obj, "hpm_friction", text="摩擦系数")
        column.prop(obj, "hpm_rough", text="Rough")
        column.prop(obj, "hpm_bounce", text="弹性")
        column.prop(obj, "hpm_physics_enabled", text="启用碰撞")
        layout.label(text="导出时写入 virtual.json 的 objects", icon="INFO")


class HPM_PT_packs(bpy.types.Panel):
    bl_label = "自定义虚拟包"
    bl_idname = "HPM_PT_packs"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "HPM"
    bl_parent_id = "HPM_PT_project"
    bl_options = {"DEFAULT_CLOSED"}

    def draw(self, context):
        layout = self.layout
        packs = state.get_packs(context)
        if not packs:
            layout.label(text="没有发现自定义包")
            layout.label(text="放到 <项目>/virtual/packages 或 ~/.hpm/virtual")
            return
        for pack in packs:
            row = layout.row()
            row.label(text=f"{pack['name']} {pack['version']}", icon="PACKAGE")
            row.label(text=str(pack.get("target", "")))
