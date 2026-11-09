class_name PresetKawasakiZX25R
extends RefCounted

## Kawasaki ZX-25R (2020+) - 250 cc inline four
## Bore x stroke from Otomotifnet MY2022 and Autocar India: 50.0 x 31.8 mm = 249.6 cc
## Primary 2.900 (87/30) and final 3.429 (48/14) from same sources
## Gear ratios, rod ratio, flywheel from engine-sim zx_25r.mr (MIT, Copyright 2022 Ange Yaghi)
## Increased flywheel inertia for launch stability (was 1.0kg/53mm)
## Header: stock
## Fuel: RON 95
## Features: Quickshifter, Launch Control, Slipper Clutch, Power Modes (F/M/L), Ram-air
static var DATA := {
	"display_name": "Kawasaki ZX-25R (2020)",
	"cylinders": 4,
	"displacement_cc": 249.6,
	"bore_mm": 50.0,
	"stroke_mm": 31.8,
	"rod_ratio": 2.0,
	"compression_ratio": 11.5,
	"layout": "inline",
	"header": "stock",
	"fuel": "ron95",
	"redline_rpm": 17000.0,
	"fire_deg": [0.0, 180.0, 540.0, 360.0],
	"flywheel_kg": 2.0,
	"flywheel_radius_mm": 80.0,
	"primary_ratio": 2.9,
	"final_drive": 3.429,
	"gear_ratios": [2.929, 2.056, 1.619, 1.333, 1.154, 1.037],
	"vehicle_kg": 182.0,
	"wheel_radius_m": 0.3069,
	"slipper_clutch": true,
	"slipper_ramp": 0.5,
	"quickshifter": true,
	"quickshifter_cut_time": 0.05,
	"quickshifter_min_rpm": 3000.0,
	"power_mode": "F",
	"launch_control": true,
	"launch_rpm": 8000.0,
	"launch_throttle": 0.95,
	"launch_speed_kmh": 30.0
}