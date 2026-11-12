class_name KeyboardControls
extends RefCounted

# Keyboard input for riding. Every function takes "typing", which is true while a text field owns the focus: naming a
# build must not open the throttle with W or shift with Q and E. Pausing is the caller's business, since it also stops
# the starter and the physics.
#
#   W / Up          throttle open (the spring returns it when let go)
#   S / Down        throttle closed by the rider
#   Shift           clutch pulled in
#   Space           brake  (B is deliberately unbound)
#   E / Q           shift up / down
#   J               starter, held to crank (same as the on-screen HOLD TO START)
#   K               kill switch,  Esc pause,  F11 fullscreen  (handled in Main's _unhandled_input)


static func throttle_open(typing: bool) -> bool:
	return not typing and (Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))


static func throttle_close(typing: bool) -> bool:
	return not typing and (Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))


static func clutch(typing: bool) -> bool:
	return not typing and Input.is_physical_key_pressed(KEY_SHIFT)


static func brake(typing: bool) -> bool:
	# Space only: B was removed from the brake on request, so it is free for typing and shortcuts
	return not typing and Input.is_physical_key_pressed(KEY_SPACE)


# -1 for a downshift, 1 for an upshift, 0 for nothing.
static func shift_force(typing: bool) -> float:
	if typing:
		return 0.0
	if Input.is_physical_key_pressed(KEY_E):
		return 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		return -1.0
	return 0.0


# J held cranks the engine, the same as holding the on-screen starter. It is a hold, not a toggle, so the starter turns
# only while the key is down - and the interlock still decides whether it is allowed to.
static func starter(typing: bool) -> bool:
	return not typing and Input.is_physical_key_pressed(KEY_J)
