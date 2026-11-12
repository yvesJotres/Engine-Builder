class_name BikeMaterials
extends RefCounted

# The one material factory the bike's geometry uses. Split out so the modules that build parts (chassis, brakes, cockpit)
# do not each grow their own copy.


static func make(colour: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	return material
