"""Summarise measured source results; missing evidence never becomes a pass."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
run = json.loads((root / 'build/accuracy/current.json').read_text())
fine = json.loads((root / 'build/accuracy/convergence_14400.json').read_text())
lines = [
    '# Engine accuracy investigation — current source', '',
    'Status: INCOMPLETE. No vehicle has a complete real-world accuracy sign-off.', '',
    'Agreed targets: power ±3%, torque ±5%, comparable acceleration/top speed ±5%. Stock vehicles, recommended fuel, warm engine, full tank, 75 kg rider, level dry road, still air. Experimental V3R and F1 presets are deferred.', '',
    '## Current measurements', '',
    'Crank torque from the source simulation, clutch open, WOT, independently initialised at each RPM, one second warm-up followed by 32 complete engine cycles. Ambient defaults are 101325 Pa and 300 K. These imposed-speed measurements are not road top-speed tests or independent dyno measurements.', '',
    '| Vehicle/reference | Power at rated RPM | Error | Torque at rated RPM | Error |',
    '| --- | ---: | ---: | ---: | ---: |',
]
for ident, result in run['results'].items():
    if 'curve' not in result:
        continue
    ref = result['reference']
    power = next(s for s in result['curve'] if s['target_rpm'] == ref['power_rpm'])
    torque = next(s for s in result['curve'] if s['target_rpm'] == ref['torque_rpm'])
    lines.append(f"| [{ref['variant']}]({ref['source']}) | {power['power_kw']:.2f} kW / {ref['power_kw']:.2f} | {result['power_error']:+.1%} | {torque['torque_nm']:.2f} Nm / {ref['torque_nm']:.2f} | {result['torque_error']:+.1%} |")
lines += ['', 'Peak checks are separate from the rated-RPM checks. Full curves and pass/fail flags are in build/accuracy/current.json. No road acceleration, top speed or transient result is validated by this table.', '', '## Numerical evidence', '']
for ident, result in fine['results'].items():
    if 'curve' not in result or 'curve' not in run['results'][ident]:
        continue
    changes = []
    for sample in result['curve']:
        base = next(s for s in run['results'][ident]['curve'] if s['target_rpm'] == sample['target_rpm'])
        changes.append(f"{sample['target_rpm']:.0f} RPM: {sample['torque_nm'] / base['torque_nm'] - 1:+.2%}")
    lines.append(f"- {ident}, 7200 to 14400 Hz: " + '; '.join(changes))
lines += [
    '', 'Native/GDScript comparison passed all 600 frames for CBR150R, ZX-25R and Panigale V4 after the port-cap change. Native closed-cylinder energy conservation passed. Intake mass accounting, general engine regressions and preset tests passed. Android arm64 and Windows debug/release libraries rebuilt; Android runtime accuracy has not been verified.', '',
    '## Corrections made', '',
    '- Removed ve_scale from manifold mass removal: air subtracted from the manifold now matches runner flow. The legacy field remains readable for old saves.',
    '- Added explicit throttle bore/count inputs instead of imposing one 30 mm inlet on every vehicle. Honda documents 32 mm for the 2017 CBR250RR; Yamaha service-manual type codes EHDW38-1 and 45EIDW support nominal 38/45 mm throttle models for MT-07/R1 respectively (bore interpretation should be confirmed against measured parts).',
    '- Replaced fixed valve-port caps with the same two-valve head-area approximation evaluated using each engine’s valve dimensions. This remains an estimated flow-area model, not a measured flow-bench map.',
    '- Applied Yamaha service-manual nominal valve head diameters: MT-07 31.5/26.5 mm; R1 33/26.5 mm. Previous presets inherited 20/17 mm small-single estimates.',
    '- Corrected MT-07 stroke and gearing from Yamaha’s 2014 Japanese specification (68.5 mm, primary 1.925, final 2.687, ratios 2.846/2.125/1.631/1.300/1.090/0.964). Corrected R1 primary/final from Yamaha’s owner manual to 1.634/2.563.',
    '- Marked documented curb-weight presets separately and added the agreed rider mass for road calculations. Legacy combined masses retain their previous interpretation.',
    '- Tightened the CBR reference thresholds and explicitly labelled its fixed-RPM road-speed check as gearing only.', '',
    '## Primary technical references', '',
    '- [Honda CBR250RR 2017 factbook: throttle, valves and engine design](https://www.honda.co.jp/factbook/motor/CBR250RR/201704/201704_CBR250RR.pdf)',
    '- [Yamaha 2014 MT-07 service manual (redistributed manufacturer document)](https://www.endurokan.com/wp-content/uploads/2021/07/Yamaha-mt-07-Ingilizce-Servis-Klavuzu.pdf)',
    '- [Yamaha 2015 R1 service manual (redistributed manufacturer document)](https://device.report/m/ef2040103299d973724817fe4f22abd83a0d880a907afa376c0d6eaced6d8956.pdf)',
    '- [Yamaha R1/R1M owner manual: gearing and curb weight](https://www.manualslib.com/manual/1017928/Yamaha-R1-Yzf-R1.html?page=120)', '',
    '## Outstanding accuracy work', '',
    'The CBR250RR still contains old estimated heat/flow calibration inputs. Runner cross-section, port volume, variable intake geometry, valve lift/timing curves, heat transfer, friction and exhaust backpressure still need independently supported inputs and validation. Published peak figures alone do not validate full curves or transient behavior. Numerical convergence must be tightened before claiming 3% physical accuracy.', '',
    'Road validation still requires matched reference runs, rider posture/drag, gearing/limiter verification, traction and load-transfer behavior. Every other library entry remains explicitly unverified until its matching reference is registered and measured. Earlier preliminary before/after readings used a fixed sampling time; they are not an interchangeable baseline for the complete-cycle measurements above.', '',
]
for ident, result in run['results'].items():
    if 'curve' not in result:
        lines.append(f"- {ident}: {result['status']} — {result['reason']}")
out = root / 'reports/engine_accuracy_status.md'
out.write_text('\n'.join(lines) + '\n', encoding='utf-8')
print(out)
