extends SceneTree

# Reports whether the native cylinder kernel is available and used.
func _init() -> void:
	print("native_available=%s use_native=%s" % [str(Cylinder.native_available), str(Cylinder.use_native)])
	quit(0)
