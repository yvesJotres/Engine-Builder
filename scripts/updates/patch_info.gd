extends RefCounted
## Which patch the player is running, for the launcher and the main menu. It reads the state the Patcher
## saved (user://patch/state.json) instead of asking the Patcher, so it also works in a patch.
## No class_name on purpose: a patch cannot add a new class name, but it can add a script like this one.

const STATE_FILE := "user://patch/state.json"


# "PATCH 66" for a downloaded patch (a delta counts as the newer number), or "BUILT-IN" for the version in the install
static func label() -> String:
	if not FileAccess.file_exists(STATE_FILE):
		return "BUILT-IN"
	var state = JSON.parse_string(FileAccess.get_file_as_string(STATE_FILE))
	if not (state is Dictionary):
		return "BUILT-IN"
	var number := int(state.get("version", 0))
	var delta = state.get("delta")
	if delta is Dictionary and int(delta.get("base_version", -1)) == number:
		number = int(delta.get("version", number))
	return "PATCH %d" % number if number > 0 else "BUILT-IN"
