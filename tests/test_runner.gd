extends SceneTree

# Runs tests under tests/unit and tests/integration, each in its own Godot process, because each test ends by calling
# quit(): a crash, an infinite loop or a leaked singleton in one test cannot smear into the next. That isolation is why
# the sweep is slow, so this runner:
#   - runs TEST_JOBS tests at a time (default 3, never more than the machine has cores minus one)
#   - gives every test a wall-clock deadline, TEST_TIMEOUT_S (default 240). Past it the process tree is killed and the
#     test is reported TIMEOUT. That is what an infinite loop inside _init looks like, and it used to look like nothing:
#     exhaust_options_test sat for 18 minutes and the sweep printed no line at all.
#   - passes --quit-after 3000, which bounds the other hang: an assert that fires before the test reaches its own
#     quit() aborts the function but leaves the scene tree running for ever.
#   - writes each test's output to user://test_logs through --log-file. The verdict is read from that log: a failure
#     always prints one of FAIL_MARKERS, which is what lets the child be started detached (needed so the deadline can
#     kill it) even though a detached process reports no exit code.
#
# Run them all:   godot --headless --path . -s res://tests/test_runner.gd
# Only some:      TEST_FILTER=controls/ godot ... (matches anywhere in the path: "engine/", "two_stroke", "panel")
# Tuning:         TEST_JOBS=1 for a serial run, TEST_TIMEOUT_S=600 for a slow machine
# One test alone: godot --headless --path . -s res://tests/unit/controls/panel_defaults_test.gd

const FOLDERS := ["res://tests/unit", "res://tests/integration"]
const QUIT_AFTER := "3000" # scene-tree iterations before an aborted test is forced out
const LOG_DIR := "user://test_logs"
const DEFAULT_TIMEOUT_S := 600.0
const DEFAULT_JOBS := 3
# What a failing child leaves in its log. Every test in the repo prints one of these on its way out (checked: all 90
# files that call quit(1) also print FAIL, PASS or RESULT), so the log is enough to classify a run started detached,
# which OS.create_process needs in order to know the pid and therefore be able to kill a hung test.
const FAIL_MARKERS := ["SCRIPT ERROR", "Assertion failed", "Result: FAIL", "RESULT: FAIL", " FAIL",
	"Program crashed", "handle_crash", "signal 11", "Cannot open file"]

var _exe := ""
var _project := ""
var _log_dir := ""
var _jobs := DEFAULT_JOBS
var _timeout_ms := int(DEFAULT_TIMEOUT_S * 1000.0)
var _failed: Array[String] = []
var _count := 0


func _init() -> void:
	_exe = OS.get_executable_path()
	# A quoted argument ending in a backslash breaks the child's command line, so the project path loses its trailing
	# separator before it is ever quoted.
	_project = ProjectSettings.globalize_path("res://").rstrip("/\\")
	_log_dir = ProjectSettings.globalize_path(LOG_DIR).rstrip("/\\")
	if OS.get_name() != "Windows":
		_fail_no_platform()
		return
	var jobs_env := OS.get_environment("TEST_JOBS")
	_jobs = maxi(1, int(jobs_env)) if jobs_env != "" else DEFAULT_JOBS
	_jobs = clampi(_jobs, 1, maxi(1, OS.get_processor_count() - 1))
	var timeout_env := OS.get_environment("TEST_TIMEOUT_S")
	if timeout_env != "":
		_timeout_ms = int(maxf(30.0, timeout_env.to_float()) * 1000.0)
	_prepare_logs()
	var filter := OS.get_environment("TEST_FILTER").strip_edges()
	var tests: Array[String] = []
	for folder in FOLDERS:
		for path in _scripts(folder):
			if filter == "" or path.contains(filter):
				tests.append(path)
	if tests.is_empty():
		print("RESULT: no test matches TEST_FILTER=%s" % filter)
		quit(2)
		return
	_count = tests.size()
	print("sweep: %d test(s), %d at a time, %d s deadline each" % [_count, _jobs, _timeout_ms / 1000])
	_run_all(tests)
	var scope := " (%s)" % filter if filter != "" else ""
	print("RESULT: %d of %d failed%s" % [_failed.size(), _count, scope])
	if _failed.is_empty():
		print("logs: %s" % _log_dir)
	else:
		for path in _failed:
			print("failed log: %s" % _log_for(path))
	quit(1 if not _failed.is_empty() else 0)


# The scheduler: keep up to _jobs children running, reap the finished ones, kill the ones past their deadline, and
# sleep briefly between checks rather than busy-waiting on any single test.
func _run_all(tests: Array[String]) -> void:
	var pending := tests.duplicate()
	var running: Array = []
	while not pending.is_empty() or not running.is_empty():
		while running.size() < _jobs and not pending.is_empty():
			running.append(_start(pending.pop_front()))
		var still: Array = []
		for job in running:
			if not OS.is_process_running(int(job["pid"])):
				_report(job, _classify(job))
			elif Time.get_ticks_msec() - int(job["started"]) > _timeout_ms:
				_kill_tree(int(job["pid"]))
				_report(job, "TIMEOUT")
			else:
				still.append(job)
		running = still
		OS.delay_msec(40)


# Starts one test detached, with its output going to its own log file. No shell is involved: cmd.exe mangles a quoted
# batch path followed by more arguments ("C:\Users\Yves" is not recognized), so the child is the Godot binary itself.
func _start(path: String) -> Dictionary:
	var log := _log_for(path)
	# Printed before the child is spawned: if one hangs, the log names it immediately instead of going quiet until the
	# deadline. Lines interleave across the workers, so each one carries its own test name.
	print("run       %s" % path.trim_prefix("res://tests/"))
	var pid := OS.create_process(_exe, ["--headless", "--path", _project, "--quit-after", QUIT_AFTER,
		"--log-file", log, "-s", path])
	return {"path": path, "log": log, "pid": pid, "started": Time.get_ticks_msec()}


func _classify(job: Dictionary) -> String:
	var log := str(job["log"])
	if not FileAccess.file_exists(log):
		return "NO LOG"
	var text := FileAccess.get_file_as_string(log)
	for marker in FAIL_MARKERS:
		if marker in text:
			return "FAIL"
	return "ok"


func _report(job: Dictionary, verdict: String) -> void:
	var path := str(job["path"])
	var seconds := (Time.get_ticks_msec() - int(job["started"])) / 1000.0
	print("%-7s %6.1fs  %s" % [verdict if verdict != "ok" else "ok", seconds, path.trim_prefix("res://tests/")])
	if verdict != "ok":
		_failed.append(path)


# taskkill /T takes the whole tree: the pid we hold is cmd.exe, and killing only it would leave Godot running.
func _kill_tree(pid: int) -> void:
	var out: Array = []
	OS.execute("taskkill.exe", ["/F", "/T", "/PID", str(pid)], out, true)


func _log_for(path: String) -> String:
	var leaf := path.trim_prefix("res://tests/").replace("/", "_").replace(".gd", "")
	return "%s/%s.log" % [_log_dir, leaf]


# Fresh log directory. Each test's log lands here through --log-file, so a killed or crashed test still has one.
func _prepare_logs() -> void:
	DirAccess.make_dir_recursive_absolute(_log_dir)
	for file in DirAccess.get_files_at(_log_dir):
		DirAccess.remove_absolute("%s/%s" % [_log_dir, file])


func _fail_no_platform() -> void:
	print("RESULT: this runner needs Windows: it starts each test through a .bat wrapper to capture the exit code.")
	quit(2)


# Every .gd file under dir, including subfolders, in a stable order.
func _scripts(dir: String) -> Array[String]:
	var found: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_scripts(dir + "/" + sub))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			found.append(dir + "/" + file)
	found.sort()
	return found
