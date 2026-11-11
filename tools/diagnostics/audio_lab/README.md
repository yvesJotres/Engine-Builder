# Audio lab

Renders the engine sound offline, measures it, and plots it, so a sound change can be checked without playing the game.

Run every command from the project root.

## Commands

| Command | What it does |
|---|---|
| `render` | Renders one sound to a WAV |
| `compare` | Renders named variants and prints their measurements |
| `stats` | Measures existing WAV files and prints a table |
| `plot` | Writes a spectrogram and waveform PNG for a WAV |
| `variants` | Lists the named variants |

Every render writes to `tools/diagnostics/out/audio/`, which is gitignored.

```bash
python tools/diagnostics/audio_lab/audio_lab.py render --preset honda_cbr150r --profile idle --name cbr150r_idle
python tools/diagnostics/audio_lab/audio_lab.py plot tools/diagnostics/out/audio/cbr150r_idle.wav
python tools/diagnostics/audio_lab/audio_lab.py stats tools/diagnostics/out/audio/cbr150r_idle.wav
python tools/diagnostics/audio_lab/audio_lab.py compare --preset honda_cbr150r --profile idle --variants base,exhaust_only,intake_only,layers_off
```

## Options for `render`

- `--preset`: an engine preset id, such as `honda_cbr150r` or `yamaha_yzf_r1m`.
- `--profile`: what the engine does while it records.
  - `idle`: closed throttle.
  - `decel`: 0.8 throttle for 2.5 s, then closed.
  - `crank`: starter held, spark on, so the engine starts from off.
  - `crank_dry`: starter held, spark off, so it cranks without firing.
  - `rev`: warms up at idle, then full throttle in neutral up to the limiter.
- `--seconds`: length of the recording. Default 6.
- `--exhaust on|off`, `--intake on|off`: turn either engine path off.
- `--rasp on|off`: the rasp noise on the exhaust pulse.
- `--muffler on|off`: the muffler impulse response.
- `--layers on|off`: all procedural sound layers.
- `--gains a,b,c,d,e`: absolute gains for the layers, in the order valvetrain, mechanical, driveline, turbo, knock. These replace the defaults, so a gain of 0 mutes a layer. Starter and dynamo are not in this list.
- `--solver live|offline`: the live exhaust solver the game uses, or the offline one for comparison.
- `--raw`: also saves the raw exhaust pulses.
- `--name`: the output file name, without the extension.

## Variants for `compare`

| Variant | Setting |
|---|---|
| `base` | As shipped |
| `exhaust_only` | Intake off |
| `intake_only` | Exhaust off |
| `rasp_off` | Rasp off |
| `muffler_off` | Muffler off |
| `offline_solver` | Offline solver |
| `layers_off` | All layers off |

## Reading the output

- `stats` prints RMS and peak in dBFS, the share of energy above 1 kHz and in 1–3 kHz, the dominant tone, and the crackle rate per second.
- The spectrogram shows 0–4 kHz. A tone above 4 kHz won't appear in it, so check the full band separately.
- Each render is stereo. If you analyse a WAV yourself, read it as two channels. Reading the interleaved samples as mono halves every frequency.

## Environment

- `GODOT`: path to the Godot console executable, if it isn't at the default path in `audio_lab.py`.

## Adding a profile or variant

- A profile is set up in `render_sound.gd`, where the throttle and starter for each step are chosen. Add the name there and to the `--profile` choices in `audio_lab.py`.
- A variant is a row in the variant table in `audio_lab.py`.
