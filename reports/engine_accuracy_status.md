# Engine accuracy investigation — current source

Status: INCOMPLETE. No vehicle has a complete real-world accuracy sign-off.

Agreed targets: power ±3%, torque ±5%, comparable acceleration/top speed ±5%. Stock vehicles, recommended fuel, warm engine, full tank, 75 kg rider, level dry road, still air. Experimental V3R and F1 presets are deferred.

## Current measurements

Crank torque from the source simulation, clutch open, WOT, independently initialised at each RPM, one second warm-up followed by 32 complete engine cycles. Ambient defaults are 101325 Pa and 300 K. These imposed-speed measurements are not road top-speed tests or independent dyno measurements.

| Vehicle/reference | Power at rated RPM | Error | Torque at rated RPM | Error |
| --- | ---: | ---: | ---: | ---: |
| [2017 Japan 2BK-MC51](https://global.honda/jp/news/2017/2170418-cbr250rr.html) | 34.80 kW / 28.00 | +24.3% | 27.71 Nm / 23.00 | +20.5% |
| [2014 Japan MT-07](https://global.yamaha-motor.com/jp/news/2014/0707/mt-07.html) | 51.13 kW / 54.00 | -5.3% | 67.07 Nm / 68.00 | -1.4% |
| [2015 Europe YZF-R1M](https://global.yamaha-motor.com/news/2014/1104/yzf-r1.html) | 94.01 kW / 147.10 | -36.1% | 78.43 Nm / 112.40 | -30.2% |

Peak checks are separate from the rated-RPM checks. Full curves and pass/fail flags are in build/accuracy/current.json. No road acceleration, top speed or transient result is validated by this table.

## Numerical evidence

- honda_cbr250rr, 7200 to 14400 Hz: 11000 RPM: +2.20%; 12500 RPM: -0.28%
- yamaha_mt07, 7200 to 14400 Hz: 6500 RPM: +0.28%; 9000 RPM: -1.67%
- yamaha_yzf_r1m, 7200 to 14400 Hz: 11500 RPM: -0.06%; 13500 RPM: +0.65%

Native/GDScript comparison passed all 600 frames for CBR150R, ZX-25R and Panigale V4 after the port-cap change. Native closed-cylinder energy conservation passed. Intake mass accounting, general engine regressions and preset tests passed. Android arm64 and Windows debug/release libraries rebuilt; Android runtime accuracy has not been verified.

## Corrections made

- Removed ve_scale from manifold mass removal: air subtracted from the manifold now matches runner flow. The legacy field remains readable for old saves.
- Added explicit throttle bore/count inputs instead of imposing one 30 mm inlet on every vehicle. Honda documents 32 mm for the 2017 CBR250RR; Yamaha service-manual type codes EHDW38-1 and 45EIDW support nominal 38/45 mm throttle models for MT-07/R1 respectively (bore interpretation should be confirmed against measured parts).
- Replaced fixed valve-port caps with the same two-valve head-area approximation evaluated using each engine’s valve dimensions. This remains an estimated flow-area model, not a measured flow-bench map.
- Applied Yamaha service-manual nominal valve head diameters: MT-07 31.5/26.5 mm; R1 33/26.5 mm. Previous presets inherited 20/17 mm small-single estimates.
- Corrected MT-07 stroke and gearing from Yamaha’s 2014 Japanese specification (68.5 mm, primary 1.925, final 2.687, ratios 2.846/2.125/1.631/1.300/1.090/0.964). Corrected R1 primary/final from Yamaha’s owner manual to 1.634/2.563.
- Marked documented curb-weight presets separately and added the agreed rider mass for road calculations. Legacy combined masses retain their previous interpretation.
- Tightened the CBR reference thresholds and explicitly labelled its fixed-RPM road-speed check as gearing only.

## Primary technical references

- [Honda CBR250RR 2017 factbook: throttle, valves and engine design](https://www.honda.co.jp/factbook/motor/CBR250RR/201704/201704_CBR250RR.pdf)
- [Yamaha 2014 MT-07 service manual (redistributed manufacturer document)](https://www.endurokan.com/wp-content/uploads/2021/07/Yamaha-mt-07-Ingilizce-Servis-Klavuzu.pdf)
- [Yamaha 2015 R1 service manual (redistributed manufacturer document)](https://device.report/m/ef2040103299d973724817fe4f22abd83a0d880a907afa376c0d6eaced6d8956.pdf)
- [Yamaha R1/R1M owner manual: gearing and curb weight](https://www.manualslib.com/manual/1017928/Yamaha-R1-Yzf-R1.html?page=120)

## Outstanding accuracy work

The CBR250RR still contains old estimated heat/flow calibration inputs. Runner cross-section, port volume, variable intake geometry, valve lift/timing curves, heat transfer, friction and exhaust backpressure still need independently supported inputs and validation. Published peak figures alone do not validate full curves or transient behavior. Numerical convergence must be tightened before claiming 3% physical accuracy.

Road validation still requires matched reference runs, rider posture/drag, gearing/limiter verification, traction and load-transfer behavior. Every other library entry remains explicitly unverified until its matching reference is registered and measured. Earlier preliminary before/after readings used a fixed sampling time; they are not an interchangeable baseline for the complete-cycle measurements above.

- amg_m276_v6: unverified — No matching manufacturer performance reference registered yet
- amg_v6_w17: deferred — No matching manufacturer performance reference registered yet
- bugatti_centodieci: unverified — No matching manufacturer performance reference registered yet
- ducati_panigale_v4: unverified — No matching manufacturer performance reference registered yet
- harley_sportster_883: unverified — No matching manufacturer performance reference registered yet
- honda_cbr150r: unverified — No matching manufacturer performance reference registered yet
- honda_cbr250rr_sp_qs: unverified — No matching manufacturer performance reference registered yet
- honda_trx520: unverified — No matching manufacturer performance reference registered yet
- honda_v3r900: deferred — No matching manufacturer performance reference registered yet
- kawasaki_zx25r: unverified — No matching manufacturer performance reference registered yet
- kawasaki_zx25r_se: unverified — No matching manufacturer performance reference registered yet
- m276_de30la: unverified — No matching manufacturer performance reference registered yet
- yamaha_rd350: unverified — No matching manufacturer performance reference registered yet
