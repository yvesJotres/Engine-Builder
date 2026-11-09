"""Plot source-simulation curves against manufacturer rated points only."""
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

root = Path(__file__).resolve().parents[2]
data = json.loads((root / 'build/accuracy/current.json').read_text())
engines = [(key, result) for key, result in data['results'].items() if 'curve' in result]
fig, axes = plt.subplots(len(engines), 2, figsize=(12, 3.3 * len(engines)), squeeze=False)
for row, (key, result) in enumerate(engines):
    ref = result['reference']
    for col, (quantity, unit, fraction, rpm_key, ref_key) in enumerate([
        ('power_kw', 'Power (kW)', .03, 'power_rpm', 'power_kw'),
        ('torque_nm', 'Torque (Nm)', .05, 'torque_rpm', 'torque_nm'),
    ]):
        ax = axes[row, col]
        ax.plot([s['target_rpm'] for s in result['curve']], [s[quantity] for s in result['curve']], color='#186c97', label='Source simulation')
        ax.errorbar([ref[rpm_key]], [ref[ref_key]], yerr=[ref[ref_key] * fraction], fmt='s', color='#c13d32', capsize=6, label=f'Manufacturer point ±{fraction:.0%}')
        ax.set(title=ref['variant'], xlabel='Engine speed (RPM)', ylabel=unit)
        ax.grid(alpha=.2)
        ax.legend(fontsize=8)
fig.suptitle('Current simulation vs published crankshaft output — accuracy NOT yet validated', fontsize=13)
fig.text(.5, .008, 'Manufacturer full curves are unavailable here. Markers are rated points; no road-speed or transient validation is implied.', ha='center', fontsize=9)
fig.tight_layout(rect=(0, .025, 1, .96))
out = root / 'reports/engine_accuracy_curves.png'
fig.savefig(out, dpi=150)
print(out)
