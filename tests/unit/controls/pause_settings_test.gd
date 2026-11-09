extends SceneTree

const PATH := "user://pause_settings_test.cfg"


func _init() -> void:
	var menu := PauseMenu.new()
	menu.settings_path = PATH
	root.add_child(menu)
	await process_frame
	menu._quality.item_selected.emit(0)
	menu._accuracy.item_selected.emit(3)
	menu._blur_box.button_pressed = true
	menu._sound_box.button_pressed = false
	menu._fps_box.button_pressed = true
	menu._hud_mode.item_selected.emit(1)
	menu.set_fullscreen_checked(false)
	menu.free()
	var restored := PauseMenu.new()
	restored.settings_path = PATH
	root.add_child(restored)
	var ok := restored._quality.selected == 0 and restored._accuracy.selected == 3
	ok = ok and restored._blur_box.button_pressed and not restored._sound_box.button_pressed
	ok = ok and restored._fps_box.button_pressed and not restored._fullscreen_box.button_pressed
	ok = ok and restored._hud_mode.selected == 1
	var applied := [false, false]
	restored.accuracy_changed.connect(func(index: int) -> void: applied[0] = index == 3)
	restored.sound_toggled.connect(func(on: bool) -> void: applied[1] = not on)
	restored.apply_settings()
	ok = ok and applied[0] and applied[1]
	restored.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("PASS settings saved, restored and applied" if ok else "FAIL settings persistence")
	quit(0 if ok else 1)
