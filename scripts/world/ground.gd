class_name Ground
extends MeshInstance3D

# Grid floor. The tyre rests on it.

const Y := -2.0 # scene units, floor height


func _ready() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
void fragment() {
	vec2 g = abs(fract(UV * 40.0 - 0.5) - 0.5) / fwidth(UV * 40.0);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	ALBEDO = mix(vec3(0.12), vec3(0.35), line);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	mesh = plane
	material_override = mat
	position = Vector3(0, Y, 0)
