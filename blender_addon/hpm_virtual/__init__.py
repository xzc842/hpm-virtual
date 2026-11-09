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

"""HPM Virtual Blender 插件：打开项目、放置设备、编辑摩擦、导出自定义虚拟包。"""

from __future__ import annotations

import bpy

from . import data, exporter, operators, panels, scene, state

bl_info = {
    "name": "HPM Virtual",
    "author": "HPM",
    "version": (1, 0, 5),
    "blender": (4, 2, 0),
    "location": "3D 视图 > 侧栏 > HPM",
    "description": "HPM 虚拟环境编辑与导出",
    "category": "3D View",
}

_CLASSES = (
    operators.HPM_OT_load_project,
    operators.HPM_OT_refresh_project,
    operators.HPM_OT_place_device,
    operators.HPM_OT_remove_device,
    operators.HPM_OT_add_floor,
    operators.HPM_OT_edit_device,
    operators.HPM_OT_export_project,
    panels.HPM_PT_project,
    panels.HPM_PT_devices,
    panels.HPM_PT_friction,
    panels.HPM_PT_packs,
)


def _on_load_post(_filepath=None) -> None:
    try:
        scene.migrate_legacy_props()
        state.recover_entries(bpy.context, persist=True)
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

    bpy.types.Object.hpm_device = bpy.props.StringProperty(default="")
    bpy.types.Object.hpm_props = bpy.props.StringProperty(default="")
    bpy.types.Object.hpm_override = bpy.props.StringProperty(default="")
    bpy.types.Object.hpm_friction = bpy.props.FloatProperty(
        name="摩擦系数", min=0.0, max=1.0, default=0.8, precision=3
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
        "hpm_custom_packs", "hpm_last_export",
    ):
        if hasattr(bpy.types.Scene, prop_name):
            delattr(bpy.types.Scene, prop_name)
    for prop_name in (
        "hpm_device", "hpm_props", "hpm_override", "hpm_friction", "hpm_rough",
        "hpm_bounce", "hpm_physics_enabled", "hpm_physics_owner",
    ):
        if hasattr(bpy.types.Object, prop_name):
            delattr(bpy.types.Object, prop_name)
    for cls in reversed(_CLASSES):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
