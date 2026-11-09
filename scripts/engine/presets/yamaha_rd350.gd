class_name PresetYamahaRD350
extends RefCounted

## Yamaha RD350LC (1983) - 347 cc parallel-twin two-stroke
## Liquid-cooled with YPVS exhaust valve, reed valve intake
## Bore x stroke: 64.0 x 54.0 mm = 347 cc
## Primary 2.571 (36/14), final 2.812 (45/16)
## Gear ratios from service manual
## Oil injection 50:1 variable, YPVS exhaust valve
static var DATA := {
	"display_name": "Yamaha RD350LC (1983)",
	"cylinders": 2,
	"displacement_cc": 347.0,
	"bore_mm": 64.0,
	"stroke_mm": 54.0,
	"rod_ratio": 1.5,
	"compression_ratio": 6.8,
	"layout": "inline",
	"header": "expansion",
	"fuel": "ron95",
	"redline_rpm": 9500.0,
	"fire_deg": [0.0, 180.0],
	"flywheel_kg": 1.2,
	"flywheel_radius_mm": 60.0,
	"primary_ratio": 2.571,
	"final_drive": 2.812,
	"gear_ratios": [2.714, 1.750, 1.333, 1.090, 0.954, 0.863],
	"vehicle_kg": 165.0,
	"wheel_radius_m": 0.305,
	"stroke_type": "two_stroke",
	"crankcase_compression_ratio": 1.4,
	"transfer_port_open_deg": 120.0,
	"transfer_port_close_deg": 150.0,
	"exhaust_port_open_deg": 95.0,
	"exhaust_port_close_deg": 95.0,
	"intake_port_type": "reed",
	"intake_port_open_deg": 60.0,
	"intake_port_close_deg": 60.0,
	"reed_stiffness": 40000.0,
	"reed_damping": 0.4,
	"expansion_chamber": true,
	"expansion_chamber_length_m": 1.1,
	"expansion_chamber_volume_cc": 600.0,
	"oil_injection_ratio": 50.0,
	"oil_pump_type": "variable",
	"crankcase_volume_cc": 0.0,
	"transfer_port_area_mm2": 450.0,
	"exhaust_port_area_mm2": 380.0,
	"intake_port_area_mm2": 320.0
}
