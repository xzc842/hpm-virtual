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

"""Blender 3D 视图侧栏面板。"""

from __future__ import annotations

import json

import bpy

from . import scene, state




class HPM_UL_key_values(bpy.types.UIList):
    bl_idname = "HPM_UL_key_values"

    def draw_item(self, context, layout, data, item, icon, active_data,
                  active_propname, index):
        row = layout.row(align=True)
        row.label(text=str(item.key or ""), icon="KEY_HLT")
        row.label(text=str(item.value_type or ""))
        row.label(text=str(item.value or ""))


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
        if not scene_data.hpm_project_path:
            legacy_path = state.get_project_path(context)
            if legacy_path:
                layout.label(text="旧文件项目：" + legacy_path, icon="INFO")
                layout.label(text="点“加载项目”迁移到新属性")
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
            root = scene.find_device_root(name) or scene.find_object(name)
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
    bl_label = "物体物理"
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
        owner = "设备" if scene.get_prop(obj, "hpm_physics_owner", "") == "device" else "环境"
        layout.label(text=f"归属：{owner}")
        column = layout.column(align=True)
        column.prop(obj, "hpm_friction", text="摩擦系数")
        column.prop(obj, "hpm_mass", text="质量 (kg)")
        column.prop(obj, "hpm_rough", text="Rough")
        column.prop(obj, "hpm_bounce", text="弹性")
        column.prop(obj, "hpm_physics_enabled", text="启用碰撞")
        _draw_kv(column, obj, "hpm_config_items", "hpm_config_index", "config",
                 object_mode=True)
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


class HPM_PT_virtual_devices(bpy.types.Panel):
    bl_label = "虚拟设备"
    bl_idname = "HPM_PT_virtual_devices"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "HPM"
    bl_parent_id = "HPM_PT_project"

    def draw(self, context):
        layout = self.layout
        scene_data = context.scene
        row = layout.row()
        row.template_list(
            "UI_UL_list", "hpm_virtual_devices",
            scene_data, "hpm_virtual_devices",
            scene_data, "hpm_virtual_device_index",
        )
        column = row.column(align=True)
        add = column.operator("hpm_virtual.add_virtual_device", text="", icon="ADD")
        add = column.operator("hpm_virtual.remove_virtual_device", text="", icon="REMOVE")
        layout.prop(scene_data, "hpm_new_virtual_name", text="新设备名")
        items = scene_data.hpm_virtual_devices
        index = scene_data.hpm_virtual_device_index
        if not (0 <= index < len(items)):
            layout.label(text="选中物体后点 + 添加虚拟设备")
            return
        item = items[index]
        box = layout.box()
        box.prop(item, "name", text="设备名")
        box.prop(item, "object_name", text="场景物体")
        box.prop(item, "package", text="包名")
        box.prop(item, "version", text="版本")
        box.prop(item, "override_path", text="override 路径")
        _draw_kv(box, item, "config_items", "config_index", "config",
                 virtual_index=index)
        _draw_kv(box, item, "physics_items", "physics_index", "physics",
                 virtual_index=index)


def _draw_kv(layout, owner, collection_name: str, index_name: str,
             kind: str, virtual_index: int = -1,
             object_mode: bool = False) -> None:
    box = layout.box()
    box.label(text="config" if kind == "config" else "physics")
    header = box.row(align=True)
    first = header.split(factor=0.38)
    first.label(text="键")
    middle = first.split(factor=0.35)
    middle.label(text="类型")
    middle.label(text="值")
    row = box.row()
    row.template_list("HPM_UL_key_values", collection_name, owner, collection_name,
                      owner, index_name)
    column = row.column(align=True)
    add = column.operator("hpm_virtual.add_kv", text="", icon="ADD")
    add.kind = kind
    add.virtual_index = virtual_index
    add.object_mode = object_mode
    remove = column.operator("hpm_virtual.remove_kv", text="", icon="REMOVE")
    remove.kind = kind
    remove.virtual_index = virtual_index
    remove.object_mode = object_mode
    collection = getattr(owner, collection_name)
    index = int(getattr(owner, index_name, 0))
    if 0 <= index < len(collection):
        item = collection[index]
        sub = box.row(align=True)
        sub.prop(item, "key", text="键")
        sub.prop(item, "value_type", text="")
        box.prop(item, "value", text="值")
