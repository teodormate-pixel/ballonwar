@tool
extends EditorPlugin


var fix_light_ext: FixBlenderLightIntensityGLTFDocumentExtension = null


func _enter_tree() -> void:
	var fix_light_ext := FixBlenderLightIntensityGLTFDocumentExtension.new()
	GLTFDocument.register_gltf_document_extension(fix_light_ext)


func _exit_tree() -> void:
	if fix_light_ext != null:
		GLTFDocument.unregister_gltf_document_extension(fix_light_ext)
