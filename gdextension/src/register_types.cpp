#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "audio_convolver.h"
#include "cylinder_kernel.h"
#include "ecu_native.h"
#include "exhaust_native.h"
#include "firing_native.h"
#include "fuel_native.h"
#include "gearbox_native.h"
#include "intake_native.h"
#include "physics_misc_native.h"
#include "two_stroke_kernel.h"

using namespace godot;

void initialize_engine_sim_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(AudioConvolver);
	GDREGISTER_CLASS(CylinderKernel);
	GDREGISTER_CLASS(ExhaustNative);
	GDREGISTER_CLASS(FiringNative);
	GDREGISTER_CLASS(FuelNative);
	GDREGISTER_CLASS(GearboxNative);
	GDREGISTER_CLASS(IntakeNative);
	GDREGISTER_CLASS(PhysicsMiscNative);
	GDREGISTER_CLASS(EcuNative);
	GDREGISTER_CLASS(TwoStrokeKernel);
}

void uninitialize_engine_sim_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT engine_sim_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_engine_sim_module);
	init_obj.register_terminator(uninitialize_engine_sim_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
