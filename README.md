# MatlabParametricEQ — 5-Band Parametric Equalizer

A fully interactive **5-band parametric EQ** built with MATLAB's `uifigure` GUI framework. Load a WAV file, sculpt its frequency response across five independent filter bands, and play back the processed audio — all inside a dark-themed, studio-inspired interface.

<img width="1917" height="1119" alt="image" src="https://github.com/user-attachments/assets/a55fa658-7359-491b-b477-a9624b51951c" />

---

## Features

- **5 independent EQ bands** — each with its own frequency, gain, and Q controls
- **3 filter types per band** — switch between Peaking, High-Pass, and Low-Pass per band
- **Live frequency response plot** — logarithmic display that updates in real time as you adjust parameters, with no flicker (handle-based rendering)
- **Live spectrum overlay** — real-time FFT spectrum displayed as a filled curve under the EQ during playback
- **Mouse drag on band nodes** — click and drag directly on the plot to move a band's frequency and gain
- **Scroll wheel Q control** — hover near a band and scroll to widen or narrow it
- **WAV file playback** — load any `.wav` file and audition the EQ'd result in real time
- **Debounced playback restart** — playback seamlessly restarts 150 ms after the last parameter change, so tweaking a knob never stutters
- **Bypass toggle** — instantly compare processed vs. dry signal
- **Output normalization** — automatic gain scaling and clip protection
- **Dark UI** — clean, minimal interface built entirely with MATLAB `uifigure` components

---

## Band Controls

| Control | Range | Description |
|---|---|---|
| **Type** | Peaking / High-Pass / Low-Pass | Filter topology for this band |
| **Frequency** | 20 Hz – 20 kHz | Log-scale slider for center/cutoff frequency |
| **Gain** | −15 dB to +15 dB | Boost or cut (Peaking bands only) |
| **Q** | 0.1 – 10 | Bandwidth / selectivity (also adjustable via scroll wheel) |

---

## Interaction

| Action | Effect |
|---|---|
| Adjust any slider / knob | EQ curve updates instantly |
| Click and drag a band dot on the plot | Move frequency and gain together |
| Scroll wheel over the plot | Adjust Q of the nearest band |
| **BYPASS** | Toggle EQ on/off for A/B comparison |
| **▶ PLAY / ■ STOP** | Start or stop playback of the loaded WAV |
| **⏏ LOAD** | Open a WAV file |

---

## DSP Implementation

Filters are implemented as **second-order IIR (biquad) filters** following the RBJ Audio EQ Cookbook formulas. The five stages are applied sequentially to the signal before playback.

```
H(z) = (b0 + b1·z⁻¹ + b2·z⁻²) / (a0 + a1·z⁻¹ + a2·z⁻²)
```

### Peaking EQ

```
A     = 10^(gain_dB / 40)
wc    = 2π · f / Fs
alpha = sin(wc) / (2Q)

b = [1 + alpha·A,  −2·cos(wc),  1 − alpha·A]
a = [1 + alpha/A,  −2·cos(wc),  1 − alpha/A]
```

### High-Pass / Low-Pass

Standard Butterworth biquad coefficients derived from `wc` and `alpha`.

The combined frequency response is computed by evaluating all five biquads on the unit circle (`z = e^{jω}`) and multiplying the transfer functions.

---

## Getting Started

### Requirements

- MATLAB R2019b or later
- No additional toolboxes required

### Run

1. Copy `EqParametrico.m` to your MATLAB working directory (or add it to the path).
2. In the MATLAB Command Window, run:

```matlab
app = EqParametrico();
```

3. Click **⏏ LOAD** to select a `.wav` file.
4. Adjust the band controls — the frequency response plot updates live.
5. Click **▶ PLAY** to audition the result. Use **BYPASS** to compare.

---

## Project Structure

```
EqParametrico.m     ← Single-file MATLAB classdef (all UI + DSP logic)
House raro.wav      ← Sample WAV file for testing
```

---

## Architecture Notes

- Inherits from `matlab.apps.AppBase` — compatible with MATLAB's App Designer class hierarchy.
- UI is built programmatically using `uifigure`, `uigridlayout`, `uipanel`, `uiknob`, `uislider`, and `uidropdown` — no `.mlapp` file needed.
- **Handle-based plot rendering:** all graphic objects (`HEQCurve`, `HSpecFill`, `HBandDot`, etc.) are created once in `initPlot` and updated with `set()`, avoiding `cla` and the flicker it causes.
- **Chunked audio processing:** audio is processed and played in 10-second chunks. Each chunk's `StopFcn` chains the next one, so the UI is never blocked by a long `filter()` call.
- **Single debounce timer:** a 50 ms polling timer fires `debouncePoll()` for the app's lifetime. Parameter changes only set a dirty flag and a timestamp; the actual playback restart happens 150 ms after the last change. This avoids the stop/delete/create/start timer anti-pattern.
- **Spectrum overlay:** a separate 80 ms timer computes a windowed 8192-point FFT of the last played samples and displays it as a filled area on the plot.
- Stereo files are mixed to mono on load.

---

## License

MIT License. Free to use, modify, and distribute.
