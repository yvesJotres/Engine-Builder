extends Node
## The first scene, and the only one that never changes with a patch. Godot loads the main scene before the
## Patcher autoload has mounted a downloaded patch, so anything the main scene loads is the copy built into the
## app. This scene does nothing but start the real game scene; that one is loaded after the patch is mounted,
## so the game's scripts and scenes come from the patch. The launcher opens first on every platform, which
## checks for an update and then waits for PLAY.

const GAME_SCENE := "res://scenes/main.tscn"
const LAUNCHER_SCENE := "res://scenes/launcher.tscn"
# The version code of this APK. Keep it equal to version/code in export_presets.cfg when you build an APK.
const APK_VERSION_CODE := 4


func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred(LAUNCHER_SCENE if Patcher.launcher_mode else GAME_SCENE)
