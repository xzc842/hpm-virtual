# Copyright (C) 2026 XueZicheng <xuezicheng842@outlook.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 3 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

"""HPM Virtual Blender 插件：打开项目、放置设备、编辑摩擦、导出自定义虚拟包。"""

from __future__ import annotations

import bpy

from . import data, exporter, operators, panels, scene, state

bl_info = {
    "name": "HPM Virtual",
    "author": "HPM",
    "version": (1, 0, 6),
    "blender": (4, 2, 0),
    "location": "3D 视图 > 侧栏 > HPM",
    "description": "HPM 虚拟环境编辑与导出",
    "category": "3D View",
}

class HPMKVItem(bpy.types.PropertyGroup):
    key: bpy.props.StringProperty(name="键", default="")
    title: bpy.props.StringProperty(name="标题", default="")
    value_type: bpy.props.EnumProperty(
        name="类型",
        items=[
            ("bool", "Bool", ""),
            ("int", "Int", ""),
            ("float", "Float", ""),
            ("string", "String", ""),
        ],
        default="string",
    )
    value: bpy.props.StringProperty(name="值", default="")


class HPMVirtualDevice(bpy.types.PropertyGroup):
    name: bpy.props.StringProperty(name="设备名", default="")
    object_name: bpy.props.StringProperty(name="场景物体", default="")
    package: bpy.props.StringProperty(name="包名", default="")
    version: bpy.props.StringProperty(name="版本", default="")
    config: bpy.props.StringProperty(name="config JSON", default="{}")
    physics: bpy.props.StringProperty(name="physics JSON", default="{}")
    override_path: bpy.props.StringProperty(name="override 路径", default="")
    config_items: bpy.props.CollectionProperty(type=HPMKVItem)
    physics_items: bpy.props.CollectionProperty(type=HPMKVItem)
    config_index: bpy.props.IntProperty(default=0)
    physics_index: bpy.props.IntProperty(default=0)

_CLASSES = (
    HPMKVItem,
    HPMVirtualDevice,
    operators.HPM_OT_load_project,
    operators.HPM_OT_refresh_project,
    operators.HPM_OT_place_device,
    operators.HPM_OT_remove_device,
    operators.HPM_OT_add_floor,
    operators.HPM_OT_edit_device,
    operators.HPM_OT_refresh_virtual_schema,
    operators.HPM_OT_add_kv,
    operators.HPM_OT_remove_kv,
    operators.HPM_OT_add_virtual_device,
    operators.HPM_OT_remove_virtual_device,
    operators.HPM_OT_export_project,
    panels.HPM_UL_key_values,
    panels.HPM_PT_project,
    panels.HPM_PT_devices,
    panels.HPM_PT_friction,
    panels.HPM_PT_packs,
    panels.HPM_PT_virtual_devices,
)


def _on_load_post(_filepath=None) -> None:
    try:
        scene.migrate_legacy_props()
        state.recover_entries(bpy.context, persist=True)
        state.recover_virtual_devices(bpy.context)
    except Exception as exc:  # 打开旧文件时不要让插件崩溃
        print(f"[hpm_virtual] 恢复场景状态失败: {exc}")


def register() -> None:
    for cls in _CLASSES:
        bpy.utils.register_class(cls)
    if _on_load_post not in bpy.app.handlers.load_post:
        bpy.app.handlers.load_post.append(_on_load_post)

    bpy.types.Scene.hpm_project_path = bpy.props.StringProperty(
        name="项目目录", subtype="DIR_PATH", default=""
    )
    bpy.types.Scene.hpm_mcu = bpy.props.StringProperty(name="MCU", default="")
    bpy.types.Scene.hpm_device_entries = bpy.props.StringProperty(default="")
    bpy.types.Scene.hpm_model_settings = bpy.props.StringProperty(default="")
    bpy.types.Scene.hpm_custom_packs = bpy.props.StringProperty(default="")
    bpy.types.Scene.hpm_last_export = bpy.props.StringProperty(default="")
    bpy.types.Scene.hpm_virtual_devices = bpy.props.CollectionProperty(
        type=HPMVirtualDevice
    )
    bpy.types.Scene.hpm_virtual_device_index = bpy.props.IntProperty(default=0)
    bpy.types.Scene.hpm_new_virtual_name = bpy.props.StringProperty(
        name="新虚拟设备名", default="device"
    )
    bpy.types.Scene.hpm_virtual_list_ready = bpy.props.BoolProperty(default=False)

    bpy.types.Object.hpm_device = bpy.props.StringProperty(default="")
    bpy.types.Object.hpm_props = bpy.props.StringProperty(default="")
    bpy.types.Object.hpm_override = bpy.props.StringProperty(default="")
    bpy.types.Object.hpm_config = bpy.props.StringProperty(
        name="HPM 虚拟设备 config", default="{}"
    )
    bpy.types.Object.hpm_config_items = bpy.props.CollectionProperty(type=HPMKVItem)
    bpy.types.Object.hpm_config_index = bpy.props.IntProperty(default=0)
    bpy.types.Object.hpm_friction = bpy.props.FloatProperty(
        name="摩擦系数", min=0.0, max=1.0, default=0.8, precision=3
    )
    bpy.types.Object.hpm_mass = bpy.props.FloatProperty(
        name="质量 (kg)", min=0.001, max=100000.0, default=1.0, precision=3
    )
    bpy.types.Object.hpm_rough = bpy.props.BoolProperty(name="Rough", default=True)
    bpy.types.Object.hpm_bounce = bpy.props.FloatProperty(
        name="弹性", min=0.0, max=1.0, default=0.0, precision=3
    )
    bpy.types.Object.hpm_physics_enabled = bpy.props.BoolProperty(
        name="启用碰撞", default=True
    )
    bpy.types.Object.hpm_physics_owner = bpy.props.StringProperty(default="environment")


def unregister() -> None:
    if _on_load_post in bpy.app.handlers.load_post:
        bpy.app.handlers.load_post.remove(_on_load_post)
    for prop_name in (
        "hpm_project_path", "hpm_mcu", "hpm_device_entries", "hpm_model_settings",
        "hpm_custom_packs", "hpm_last_export", "hpm_virtual_devices",
        "hpm_virtual_device_index", "hpm_new_virtual_name", "hpm_virtual_list_ready",
    ):
        if hasattr(bpy.types.Scene, prop_name):
            delattr(bpy.types.Scene, prop_name)
    for prop_name in (
        "hpm_device", "hpm_props", "hpm_override", "hpm_config",
        "hpm_config_items", "hpm_config_index", "hpm_friction",
        "hpm_mass", "hpm_rough", "hpm_bounce", "hpm_physics_enabled", "hpm_physics_owner",
    ):
        if hasattr(bpy.types.Object, prop_name):
            delattr(bpy.types.Object, prop_name)
    for cls in reversed(_CLASSES):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
