# 🎚️ MatlabParametricEQ — 5-Band Parametric Equalizer

A fully interactive **5-band parametric EQ** built with MATLAB's `uifigure` GUI framework. Load a WAV file, sculpt its frequency response across five independent filter bands, and play back the processed audio — all inside a dark-themed, studio-inspired interface.

---

## ✨ Features

- **5 independent EQ bands** — each with its own frequency, gain, and Q controls
- **Filter types per band** — switch between Peaking, High-Pass, and Low-Pass
- **Live frequency response plot** — logarithmic display that updates in real time as you adjust parameters
- **WAV file playback** — load any `.wav` file and audition the EQ'd result directly
- **Bypass toggle** — instantly compare processed vs. dry signal
- **Output normalization** — automatic gain scaling to prevent clipping
- **Dark UI** — clean, minimal interface built entirely with MATLAB UI components

---

## 🎛️ Band Controls

| Control | Range | Description |
|---|---|---|
| **Frequency** | 20 Hz – 20 kHz | Log-scale slider for the filter's center/cutoff frequency |
| **Gain** | –15 dB to +15 dB | Boost or cut (Peaking mode only) |
| **Q** | 0.1 – 10 | Filter bandwidth / selectivity |
| **Type** | Peaking / High-Pass / Low-Pass | Filter topology per band |

---

## 🧮 DSP Implementation

Filters are implemented as **biquad IIR filters** following the standard Audio EQ Cookbook formulas. The five filter stages are applied sequentially to the signal before playback.

```
H(z) = (b0 + b1·z⁻¹ + b2·z⁻²) / (a0 + a1·z⁻¹ + a2·z⁻²)
```

The frequency response is computed by evaluating each biquad on the unit circle and multiplying all five responses together.

---

## 🚀 Getting Started

### Requirements

- MATLAB R2019b or later
- No additional toolboxes required

### Run

1. Copy `EqParametrico_2.m` to your MATLAB working directory (or add it to the path).
2. In the MATLAB Command Window, run:

```matlab
app = EqParametrico_2();
```

3. Click **⏏ LOAD** to select a `.wav` file.
4. Adjust the band controls — the frequency response plot updates live.
5. Click **▶ PLAY** to audition the result. Use **BYPASS** to compare.

---

## 📁 Project Structure

```
EqParametrico_2.m   ← Single-file MATLAB class (all UI + DSP logic)
```

---

## 🔧 Architecture Notes

- Inherits from `handle` — fully self-contained, no App Designer scaffolding needed.
- UI is built programmatically using `uifigure`, `uigridlayout`, `uipanel`, `uiknob`, `uislider`, and `uidropdown`.
- Audio playback uses MATLAB's built-in `audioplayer`. Stereo files are mixed to mono on load.

---

## 📄 License

MIT License. Free to use, modify, and distribute.
