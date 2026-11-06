class_name Presets
extends RefCounted

# TRX520 values come from engine-sim (MIT, Copyright 2022 Ange Yaghi):
# assets/engines/atg-video-1/01_honda_trx520.mr. Its 96 mm bore and 71.5 mm stroke
# give 517.4 cc, matching the published 518 cc engine.
const PRESETS := {
	"Honda CBR150R (K45N)": {
		"cylinders": 1, "displacement_cc": 149.2, "bore_mm": 57.3, "stroke_mm": 57.8,
		"rod_ratio": 1.6, "layout": "inline", "header": "stock", "fuel": "ron95",
		"fire_deg": [0.0], # engine-sim cbr150.mr: one cylinder, wire at 0
		"redline_rpm": 10600.0, # limiter near 10,600 rpm from a press dyno test (Otomotifnet, 2021), not Honda
		"flywheel_kg": 2.5, # estimate, no source found yet
		"flywheel_radius_mm": 75.0, # estimate, see engine_spec.gd
	},
	# CBR250RR 2017 (MC51): bore, stroke and displacement from Webike Japan spec (62.0 x 41.3 mm, 249.7 cc, 2 cylinders).
	# Rod ratio, redline, flywheel, gears and final drive follow engine-sim's cbr250rr.mr (MIT, Copyright 2022 Ange Yaghi).
	# engine-sim has no separate primary drive: its gear ratios are written as value * 2 and its final drive is diff_ratio 4.7,
	# so crank-to-wheel is gear * 2 * 4.7. Primary is 1.0 so the total is that, not Webike's 2.781 on top.
	"Honda CBR250RR (2017, MC51)": {
		"cylinders": 2, "displacement_cc": 249.3, "bore_mm": 62.0, "stroke_mm": 41.3,
		"rod_ratio": 2.0, "compression_ratio": 12.0, "vehicle_kg": 165.0, "layout": "inline", "header": "stock", "fuel": "ron95",
		"redline_rpm": 14000.0, # engine-sim rpm_v; its note says the limiter sits 500 rpm above redline
		"twin_pin_deg": 180.0, # crank-pin angle, as stated for this model
		"fire_deg": [0.0, 180.0], # engine-sim cbr250rr.mr: wires at 0 and 180
		"flywheel_kg": 3.6, "flywheel_radius_mm": 103.2, # engine-sim flywheel_mass and flywheel_radius
		"primary_ratio": 1.0, "final_drive": 4.7,
		"gear_ratios": [6.362, 4.918, 3.934, 3.152, 2.530, 2.136],
	},
	# Kawasaki ZX-25R (2020 on): bore, stroke, compression and redline from Otomotifnet MY2022 and Autocar India.
	# Primary 2.900 (87/30) and final 3.429 (48/14) from the same sheet. Gear ratios, rod ratio and flywheel from engine-sim's zx_25r.mr
	# (MIT, Copyright 2022 Ange Yaghi). Its own gearing gives a 6th-gear total of 5.4 against 10.3 here, so this set is not engine-sim's.
	"Kawasaki ZX-25R (2020)": {
		"cylinders": 4, "displacement_cc": 249.6, "bore_mm": 50.0, "stroke_mm": 31.8,
		"rod_ratio": 2.0, "compression_ratio": 11.5, "layout": "inline", "header": "stock", "fuel": "ron95",
		"redline_rpm": 17000.0,
		"fire_deg": [0.0, 180.0, 540.0, 360.0], # engine-sim zx_25r.mr: wires 1 to 4 in cylinder order, firing 1-2-4-3 as Kawasaki's inline four
		"flywheel_kg": 1.0, "flywheel_radius_mm": 53.2,
		"primary_ratio": 2.9, "final_drive": 3.429,
		"gear_ratios": [2.929, 2.056, 1.619, 1.333, 1.154, 1.037],
	},
	# Ducati Panigale V4 (1,103 cc): bore, stroke, redline, rod length, flywheel and the 90 degree V with a 70 degree split crank pin
	# from engine-sim's panigale_v4.mr (MIT, Copyright 2022 Ange Yaghi). Firing is the reference's ignition wiring. Compression is
	# worked out from its 20 cc chamber and 30.5 mm compression height. The intake, exhaust and cam timing are the simulator's own.
	"Ducati Panigale V4 (1,103 cc)": {
		"cylinders": 4, "displacement_cc": 1102.7, "bore_mm": 81.0, "stroke_mm": 53.5,
		"rod_ratio": 2.06, "compression_ratio": 14.8, "layout": "V", "bank_angle": 90.0, "split_pin_v4": true,
		"header": "stock", "fuel": "ron95",
		"redline_rpm": 14250.0,
		"fire_deg": [0.0, 630.0, 480.0, 390.0], # engine-sim panigale_v4.mr: wire 1 at 0, wire 2 at -90, wire 3 at -240, wire 4 at -330
		"flywheel_kg": 2.5, "flywheel_radius_mm": 60.0,
		"vehicle_kg": 200.0,
	},
	# Yamaha YZF-R1M (2015): bore and stroke from motodealers.co.uk and Ultimate Motorcycling, compression 13.0 from the same sources.
	# Gear ratios, redline (limiter 14,600), flywheel, rod ratio and 200 kg mass from engine-sim's yzf_r1.mr (MIT, Copyright 2022 Ange Yaghi).
	# That file gives the total ratio with a 4.7 final drive and no separate primary, so primary is 1.0 here. Not verified against a service manual.
	"Yamaha YZF-R1M (2015)": {
		"cylinders": 4, "displacement_cc": 998.0, "bore_mm": 79.0, "stroke_mm": 50.9,
		"rod_ratio": 2.0, "compression_ratio": 13.0, "crossplane": true, "layout": "inline", "header": "stock", "fuel": "ron95",
		"redline_rpm": 14600.0,
		"fire_deg": [0.0, 450.0, 270.0, 540.0], # engine-sim yzf_r1.mr: the same sequence with its cylinders numbered from the other end
		"flywheel_kg": 5.2, "flywheel_radius_mm": 103.2,
		"primary_ratio": 1.0, "final_drive": 4.7,
		"gear_ratios": [2.600, 2.176, 1.842, 1.579, 1.381, 1.250],
		"vehicle_kg": 200.0,
	},
	"Honda TRX520 (engine-sim)": {
		"cylinders": 1, "displacement_cc": 517.4, "bore_mm": 96.0, "stroke_mm": 71.5,
		"rod_ratio": 2.13, "layout": "inline", "header": "stock", "fuel": "ron95",
		"redline_rpm": 5000.0, # from engine-sim redline: 5000 * units.rpm
		"fire_deg": [0.0], # engine-sim 01_honda_trx520.mr: one cylinder, wire at 0
		"flywheel_kg": 2.27, # from engine-sim flywheel_mass: 5 * units.lb
		"flywheel_radius_mm": 96.0, # estimate, same as the bore as before
	},
}
