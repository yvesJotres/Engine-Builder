extends RefCounted
## Windows only: stops a second copy of the game from running. The running copy writes its process ID to
## user://instance.lock. A copy that starts while that process is still running (and is this exe) shows a
## message and closes. A restart from an update waits here, because the old copy ends within about a second.
## The lock is not deleted on exit: a dead process ID does not count, so a crash cannot lock the player out.

const LOCK_FILE := "user://instance.lock"
const WAIT_TRIES := 8  # about 3.5 s of waiting before the second copy gives up
const WAIT_STEP := 0.5


# True when this copy must close. Call first thing in a scene's _ready and return if it is true.
static func guard(tree: SceneTree) -> bool:
	if OS.get_name() != "Windows" or OS.has_feature("editor"):
		return false
	for attempt in WAIT_TRIES:
		if not _other_copy_running():
			break
		if attempt == WAIT_TRIES - 1:
			OS.alert("Engine Builder is already running.", "Engine Builder")
			tree.quit()
			return true
		await tree.create_timer(WAIT_STEP, true).timeout
	var file := FileAccess.open(LOCK_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(str(OS.get_process_id()))
	return false


static func _other_copy_running() -> bool:
	var pid := _lock_pid()
	return pid > 0 and pid != OS.get_process_id() and _is_this_game(pid)


static func _lock_pid() -> int:
	if not FileAccess.file_exists(LOCK_FILE):
		return 0
	var file := FileAccess.open(LOCK_FILE, FileAccess.READ)
	if file == null:
		return 0
	return int(file.get_as_text().strip_edges())  # not a number gives 0, which means no copy


# tasklist names the program in its output, so a reused process ID for another program does not count
static func _is_this_game(pid: int) -> bool:
	var out: Array = []
	OS.execute("tasklist", ["/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"], out, true)
	if out.is_empty():
		return false
	return str(out[0]).to_lower().contains(OS.get_executable_path().get_file().to_lower())
