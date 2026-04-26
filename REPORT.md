# Technical Report — MatlabParametricEQ

**Project:** 5-Band Parametric Equalizer in MATLAB  
**File:** `EqParametrico.m`  
**Author:** Lluis Estape  
**Date:** April 2026

---

## 1. Introduction

This project implements a fully interactive 5-band parametric equalizer (EQ) as a standalone MATLAB GUI application. The application allows a user to load a WAV audio file, adjust the frequency response using five independently configurable filter bands, and audition the result in real time.

A parametric equalizer is a signal processing tool used in audio production to selectively boost or attenuate specific frequency regions of a signal. Unlike a graphic EQ (which has fixed frequency bands), a parametric EQ lets the user control the center frequency, the amount of boost or cut (gain), and the bandwidth (Q factor) of each band independently — hence "parametric."

---

## 2. DSP Theory

### 2.1 Biquad IIR Filters

Each EQ band is implemented as a **second-order infinite impulse response (IIR) filter**, also called a **biquad filter**. The general transfer function in the z-domain is:

```
         b0 + b1·z⁻¹ + b2·z⁻²
H(z) = ─────────────────────────
         a0 + a1·z⁻¹ + a2·z⁻²
```

In the time domain this corresponds to the difference equation:

```
y[n] = b0·x[n] + b1·x[n-1] + b2·x[n-2]
       − a1·y[n-1] − a2·y[n-2]
```

where `x[n]` is the input sample and `y[n]` is the output sample. All coefficients are normalized so `a0 = 1` before applying the filter.

Biquad filters are the industry standard building block for audio EQs because they are numerically stable at audio sample rates and can be cascaded to build higher-order responses.

### 2.2 Coefficient Derivation (RBJ Audio EQ Cookbook)

The coefficient formulas follow the widely-used **RBJ Audio EQ Cookbook** by Robert Bristow-Johnson. Three intermediate values are computed from the user-facing parameters:

```matlab
wc    = 2 * pi * f / Fs          % normalized angular frequency
alpha = sin(wc) / (2 * Q)        % bandwidth term
cosw  = cos(wc)
```

where `f` is the center frequency in Hz, `Fs` is the sample rate, and `Q` is the quality factor.

#### Peaking EQ band

A peaking filter boosts or cuts a band of frequencies centered at `f` by `gain_dB` decibels, leaving all other frequencies unaffected.

```
A = 10^(gain_dB / 40)            % linear amplitude factor (half in dB-space)

b = [1 + alpha·A,  −2·cosw,  1 − alpha·A]
a = [1 + alpha/A,  −2·cosw,  1 − alpha/A]
```

When `gain_dB = 0`, `A = 1` and `b = a`, so `H(z) = 1` (flat response). When `A > 1` the band is boosted; when `A < 1` it is cut.

#### High-Pass filter

Passes frequencies above `f` and attenuates those below.

```
b = [(1 + cosw)/2,  −(1 + cosw),  (1 + cosw)/2]
a = [1 + alpha,     −2·cosw,       1 − alpha   ]
```

#### Low-Pass filter

Passes frequencies below `f` and attenuates those above.

```
b = [(1 − cosw)/2,   (1 − cosw),  (1 − cosw)/2]
a = [1 + alpha,     −2·cosw,       1 − alpha   ]
```

### 2.3 Combined Frequency Response

The five biquad stages are **cascaded** — the output of band 1 is the input to band 2, and so on. In the z-domain this is equivalent to multiplying all five transfer functions:

```
H_total(z) = H₁(z) · H₂(z) · H₃(z) · H₄(z) · H₅(z)
```

To display the frequency response, the app evaluates each `H(z)` on the unit circle at 512 logarithmically spaced frequencies between 20 Hz and 20 kHz:

```matlab
f = logspace(log10(20), log10(20000), 512);
z = exp(1j * 2*pi*f / Fs);
H = ones(size(f));
for i = 1:5
    [b, a] = biquadCoeffs(i);
    H = H .* (b(1) + b(2).*z.^-1 + b(3).*z.^-2) ./ ...
             (a(1) + a(2).*z.^-1 + a(3).*z.^-2);
end
magdB = 20*log10(abs(H) + eps);
```

### 2.4 The Q Factor

The Q factor controls the **selectivity** (bandwidth) of the filter. High Q means a narrow, sharp peak; low Q means a wide, gentle curve. Specifically:

```
BW (octaves) ≈ 1 / Q      (approximate, valid for moderate gains)
```

The default Q of `0.707` (≈ 1/√2) gives a Butterworth-style maximally flat response when gain is 0, and a one-octave bandwidth when boosting or cutting.

---

## 3. Code Architecture

The entire application is a single MATLAB file implementing the class `EqParametrico`, which inherits from `matlab.apps.AppBase`. This gives it compatibility with MATLAB's App Designer class hierarchy without requiring an `.mlapp` project file.

### 3.1 Class Structure

```
EqParametrico (matlab.apps.AppBase)
│
├── properties (public)          % UI widget handles
│   └── UIFigure, UIAxes, Grid, BypassBtn, LoadBtn, PlayBtn
│
├── properties (private)         % application state
│   ├── Audio state              % Fs, AudioData, AudioPeak, ChunkSamples
│   ├── EQ parameters            % Gains[5], Freqs[5], Qs[5], Tipos{5}
│   ├── Playback engine          % PlayerObj, IsPlaying, PlayStartSample
│   ├── Panel widget handles     % FreqSliders, GainKnobs, QSliders, labels
│   ├── Spectrum overlay         % SpecFreqs, SpecMagdB, SpecTimer
│   ├── Debounce state           % DebounceTimer, ParamsDirty, LastChangeTime
│   ├── Mouse drag state         % DragBand
│   └── Plot handles             % HEQCurve, HSpecFill, HZeroLine, HBandDot, ...
│
└── methods (private)
    ├── biquadCoeffs(i)          % compute [b, a] for band i
    ├── updateEQ()               % recompute H(f) and refresh plot
    ├── initPlot(f, magdB)       % one-time graphics creation
    ├── applyEQ(in)              % apply all 5 biquads to a signal buffer
    ├── startChunk(absPos)       % process + play one 10-s chunk
    ├── restartPlayback()        % restart at current position
    ├── debouncePoll()           % 50 ms polling timer callback
    ├── scheduleRestart()        % mark params dirty + timestamp
    ├── updateSpectrum()         % 80 ms FFT spectrum callback
    ├── stopSpecTimer()          % stop and clear the spectrum timer
    ├── toggleAudio()            % play / stop
    ├── onPlaybackStop()         % end-of-file cleanup
    ├── loadAudio()              % WAV file dialog + audioread
    ├── onGainKnob/onQSlider/onFreqSlider()   % UI callbacks
    ├── onBypassToggle()
    ├── onAxesButtonDown/onMouseMove/onMouseUp()  % drag callbacks
    ├── onScrollWheel()          % Q adjustment via scroll
    └── onClose()               % cleanup timers + player on exit
```

### 3.2 Startup Sequence

```
EqParametrico()  →  setup()
                      ├── uifigure + grid layout
                      ├── UIAxes (frequency response plot)
                      ├── 5 × band panels (dropdown, sliders, knob)
                      ├── LOAD / BYPASS / PLAY buttons
                      ├── DebounceTimer (50 ms, fixedRate)  ← started once
                      └── updateEQ()  →  initPlot()  ← first draw
```

---

## 4. UI Design

The interface is built programmatically using MATLAB's `uifigure` API — no App Designer `.mlapp` file or code generation is involved. The layout uses a `uigridlayout` with three rows:

| Row | Content | Height |
|-----|---------|--------|
| 1 | Frequency response axes | flexible (fills remaining space) |
| 2 | Five band panels (side by side) | 320 px |
| 3 | LOAD / BYPASS / PLAY buttons | 46 px |

Each band panel (`uipanel`) contains:
- A `uidropdown` for filter type
- A `uislider` (0–1, log-mapped) for frequency
- A `uiknob` (−15 to +15 dB) for gain
- A `uislider` (0.1–10) for Q
- Dynamic `uilabel` widgets showing the current numeric value

The frequency slider operates on a normalized 0–1 range that is mapped to the logarithmic frequency axis:

```matlab
freqHz = 10^(logMin + sliderVal * (logMax - logMin))
```

where `logMin = log10(20)` and `logMax = log10(20000)`. This gives musically uniform spacing across the audio spectrum.

---

## 5. Handle-Based Plot Rendering

A key implementation detail is that the frequency response plot **never calls `cla`**. Instead, all graphic objects are created once in `initPlot()` and stored as persistent handles:

| Handle | Object | Updated by |
|--------|--------|------------|
| `HZeroLine` | 0 dB reference line | (static) |
| `HEQCurve` | Blue EQ magnitude curve | `updateEQ()` |
| `HSpecFill` | Blue filled spectrum | `updateSpectrum()` |
| `HBandDot{i}` | Colored circle for each band | `updateEQ()` |
| `HBandVLine{i}` | Dashed vertical guide per band | `updateEQ()` |
| `HBandLbl{i}` | Band number label per band | `updateEQ()` |

Every time a parameter changes, `updateEQ()` calls `set(handle, 'XData', ..., 'YData', ...)` on the existing objects. This is dramatically faster than recreating the axes contents and eliminates visual flicker.

---

## 6. Audio Engine

### 6.1 Chunked Playback

Audio is not processed all at once before playing. Instead, processing happens in **10-second chunks**:

```
loadAudio()  →  AudioData stored in memory (unprocessed)

toggleAudio()
  └── startChunk(0)
        ├── chunk = AudioData[absPos : absPos+N]
        ├── processed = applyEQ(chunk)       % biquad filter cascade
        ├── normalize to AudioPeak
        ├── audioplayer(processed, Fs)
        └── StopFcn = startChunk(absPos + N)  % chain next chunk
```

This prevents the UI from freezing: processing 10 seconds of audio at a time keeps `applyEQ()` fast, and MATLAB's `audioplayer` plays the buffer asynchronously while the UI remains responsive.

### 6.2 Normalization and Clip Protection

When a file is loaded, its peak amplitude is stored:

```matlab
app.AudioPeak = max(abs(data(:)));
```

Each chunk is normalized relative to this global peak before playback:

```matlab
processed = processed / app.AudioPeak * 0.99;
```

Using the global peak (not a per-chunk peak) prevents level jumps between chunks. A secondary clip guard catches any remaining overs from heavy boosts:

```matlab
pk = max(abs(processed(:)));
if pk > 0.99
    processed = processed * (0.99 / pk);
end
```

### 6.3 Debounced Playback Restart

When the user adjusts a parameter during playback, the EQ coefficients change and the current chunk becomes stale. Naively restarting immediately on every slider event would cause rapid, choppy restarts.

The solution is a **single persistent 50 ms polling timer** (`DebounceTimer`). Every UI callback that changes an EQ parameter calls:

```matlab
function scheduleRestart(app)
    app.ParamsDirty    = true;
    app.LastChangeTime = tic;
end
```

The polling timer's callback (`debouncePoll`) checks: if dirty and at least 150 ms have elapsed since the last change, restart playback. This fires the restart exactly once, 150 ms after the user stops moving a control:

```matlab
function debouncePoll(app)
    if ~app.ParamsDirty || ~app.IsPlaying, return; end
    if toc(app.LastChangeTime) < 0.15, return; end
    app.ParamsDirty    = false;
    app.LastChangeTime = [];
    app.restartPlayback();
end
```

This replaces the fragile stop/delete/create/start timer pattern with a single long-lived timer and a dirty flag — fewer objects, no race conditions.

---

## 7. Real-Time Spectrum Overlay

During playback, a second timer fires every **80 ms** and computes an FFT of the most recently played samples:

```matlab
N   = 8192;                               % FFT length
win = 0.5 * (1 − cos(2π·(0:N-1)/(N-1))); % Hann window
Y   = fft(chunk .* win);
fftF = (0:N/2) * Fs / N;
fftM = abs(Y(1:N/2+1));
```

The result is interpolated onto 300 logarithmically spaced frequency bins (matching the plot axis), converted to dB, normalized to 0 dB peak, and scaled to fit the ±25 dB display range:

```matlab
dB = 20*log10(dispMag + eps);
dB = dB - max(dB);      % normalize peak to 0 dB
dB = max(dB * 0.35, −25); % compress dynamic range for display
```

The spectrum is shown as a filled polygon (`fill`) that shares the plot's x-axis. It disappears when playback stops.

---

## 8. Mouse and Scroll Interaction

### 8.1 Band Drag

Clicking on the axes triggers `onAxesButtonDown`, which identifies the nearest band node using a combined distance metric in log-frequency space:

```matlab
logDist  = abs(log10(Freqs) − log10(clickF)) / (logMax−logMin);
gainDist = abs(Gains − clickG) / 30;
[~, best] = min(logDist + 0.4*gainDist);
```

The 0.4 weighting biases selection toward frequency proximity over gain proximity. If the nearest node is within 18% of the log-frequency range, `DragBand` is set and `WindowButtonMotionFcn` / `WindowButtonUpFcn` callbacks are registered on the figure.

During drag, `onMouseMove` reads `UIAxes.CurrentPoint` and updates both the band parameters and the matching slider/knob widgets in sync.

### 8.2 Scroll Wheel Q Adjustment

`onScrollWheel` adjusts the Q of the band nearest the cursor. Each scroll tick multiplies Q by `1.2` or divides by `1.2`, giving a smooth multiplicative (i.e., perceptually uniform) adjustment:

```matlab
factor    = 1.2 ^ (−evt.VerticalScrollCount);
Qs(i) = max(0.1, min(10, Qs(i) * factor));
```

---

## 9. Parameter Defaults

| Parameter | Default | Notes |
|-----------|---------|-------|
| Sample rate | 44100 Hz | Updated from file on load |
| Chunk size | 441000 samples (10 s) | Recomputed on load |
| Number of bands | 5 | Fixed |
| Center frequencies | 100, 500, 1000, 5000, 10000 Hz | Classic 5-band spacing |
| Gains | 0 dB (all) | Flat response at startup |
| Q factors | 0.707 (all) | ≈ 1-octave bandwidth |
| Filter types | Peaking (all) | |
| Debounce window | 150 ms | After last parameter change |
| Spectrum FFT size | 8192 samples | ~186 ms at 44100 Hz |
| Spectrum refresh rate | 80 ms (≈12.5 Hz) | Spectrum timer period |
| Debounce poll rate | 50 ms | Debounce timer period |

---

## 10. Limitations and Possible Extensions

| Limitation | Possible Extension |
|---|---|
| Mono-only playback (stereo mixed to mono on load) | Process left and right channels independently |
| Fixed 5-band count | Make the number of bands configurable at runtime |
| No file export | Add a "Save processed WAV" button using `audiowrite` |
| Gain knob limited to ±15 dB | Extend range; add a text entry for precise values |
| Spectrum shows pre-EQ signal | Show post-EQ spectrum by computing FFT on the processed chunk |
| No preset system | Add load/save of band configurations to `.mat` files |

---

## 11. Conclusion

`EqParametrico.m` is a complete, self-contained MATLAB application that demonstrates:

- **Parametric IIR filter design** using the RBJ Audio EQ Cookbook biquad formulas
- **Real-time GUI interaction** with handle-based, flicker-free plot updates
- **Chunked asynchronous audio playback** that keeps the UI responsive
- **Debounce architecture** using a single persistent polling timer
- **Live spectral analysis** with a windowed FFT displayed as a spectrum overlay
- **Direct manipulation** of EQ parameters via mouse drag and scroll wheel

The single-file classdef architecture keeps the codebase compact and easy to read while providing a fully professional-grade user experience.
