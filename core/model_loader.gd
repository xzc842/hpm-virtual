# 运行时从任意绝对路径加载 glTF/GLB。
#
# 用户项目不是 res://，所以不能依赖编辑器的导入管线。
class_name ModelLoader
extends RefCounted

static func load_scene(path: String) -> Node3D:
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("模型不存在：%s" % path)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("glTF 解析失败：%s (%s)" % [path, error_string(err)])
		return null
	var scene := doc.generate_scene(state)
	if not scene is Node3D:
		push_error("模型根节点不是 Node3D：%s" % path)
		if scene != null:
			scene.queue_free()
		return null
	return scene as Node3D

## 给程序化生成的占位场景用。
static func make_material(color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat
