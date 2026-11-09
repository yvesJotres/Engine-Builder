class_name PresetDucatiPanigaleV4
extends RefCounted

## Ducati Panigale V4 (1,103 cc) - 90° V4 with 70° split crank pin
## Bore x stroke, redline, rod length, flywheel, V angle, split pin from engine-sim panigale_v4.mr (MIT, Copyright 2022 Ange Yaghi)
## Compression worked out from 20 cc chamber and 30.5 mm compression height
## Intake, exhaust, cam timing from engine-sim
## Primary 1.652 (47/28.47) and final 2.206 (36/16.32) from service manual
## Gear ratios from engine-sim
## Added idle_target_rpm for V4 stability
## Increased flywheel for launch (was 2.5kg/60mm, then 4kg/80mm)
## Header: stock
## Fuel: RON 95
static var DATA := {
	"display_name": "Ducati Panigale V4 (1,103 cc)",
	"cylinders": 4,
	"displacement_cc": 1102.7,
	"bore_mm": 81.0,
	"stroke_mm": 53.5,
	"rod_ratio": 2.06,
	"compression_ratio": 14.8,
	"layout": "V",
	"bank_angle": 90.0,
	"split_pin_v4": true,
	"header": "stock",
	"fuel": "ron95",
	"redline_rpm": 14250.0,
	"idle_target_rpm": 1300.0,
	"fire_deg": [0.0, 630.0, 480.0, 390.0],
	"flywheel_kg": 5.5,
	"flywheel_radius_mm": 100.0,
	"vehicle_kg": 200.0,
	"primary_ratio": 1.652,
	"final_drive": 2.206,
	"gear_ratios": [2.588, 2.143, 1.800, 1.571, 1.381, 1.238],
}