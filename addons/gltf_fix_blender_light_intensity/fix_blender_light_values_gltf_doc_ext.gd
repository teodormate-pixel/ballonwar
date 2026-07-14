@tool
class_name FixBlenderLightIntensityGLTFDocumentExtension
extends GLTFDocumentExtension


const LUMENS_TO_WATTS: float = 1.0 / 683.0


func _import_preflight(gltf_state: GLTFState, extensions: PackedStringArray) -> Error:
	# glTF files created by the Godot .blend importer will be placed in here - skip them.
	if gltf_state.base_path == "res://.godot/imported":
		return ERR_SKIP
	var asset: Dictionary = gltf_state.json["asset"]
	var generator: String = asset.get("generator", "")
	if "Blender" in generator:
		return OK
	return ERR_SKIP


func _import_pre_generate(gltf_state: GLTFState) -> Error:
	# Keep track of the materials we've seen before to avoid altering it twice.
	var seen_materials: Array[BaseMaterial3D] = []
	gltf_state.set_additional_data("FixBlenderLightValuesGLTFDocumentExtension_seen_materials", seen_materials)
	return OK


func _import_node(gltf_state: GLTFState, gltf_node: GLTFNode, json: Dictionary, node: Node) -> Error:
	if node is Light3D:
		var light: Light3D = node as Light3D
		light.light_energy *= LUMENS_TO_WATTS
	elif node is ImporterMeshInstance3D:
		var mesh_node: ImporterMeshInstance3D = node as ImporterMeshInstance3D
		var imp_mesh: ImporterMesh = mesh_node.mesh as ImporterMesh
		imp_mesh.get_surface_count()
		var surf_count: int = imp_mesh.get_surface_count()
		for surf_index in surf_count:
			var mat: BaseMaterial3D = imp_mesh.get_surface_material(surf_index)
			if mat != null:
				var seen_materials: Array[BaseMaterial3D] = gltf_state.get_additional_data("FixBlenderLightValuesGLTFDocumentExtension_seen_materials")
				if not seen_materials.has(mat):
					mat.emission_energy_multiplier *= LUMENS_TO_WATTS
					seen_materials.append(mat)
	return OK
