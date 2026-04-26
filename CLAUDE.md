# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A MATLAB project containing educational DSP and utility applications: a 5-band parametric equalizer GUI (`EqParametrico.m`), a simplified equalizer variant (`EqParametrico2.m`), a Koch snowflake fractal generator (`koch.m`), and a Morse code encoder (`morse_encoder.m`).

## Running

There is no build system. Open MATLAB, navigate to this directory, and call functions directly in the command window:

```matlab
EqParametrico          % launch the main parametric equalizer GUI
EqParametrico2         % launch the simplified equalizer
koch(3)                % Koch snowflake at iteration order 3
morse_encoder('HELLO') % encode text as Morse (returns binary vector if assigned)
```

`morse_encoder` requires `morse.mat` (Morse dictionary) to be present in the working directory.

## Architecture

### EqParametrico.m — 5-band parametric equalizer

The main application is a single MATLAB script that builds a `uifigure`-based GUI and wires callbacks. All state lives in a `props` struct captured in closures.

**State flow:**
1. `loadAudio()` reads a WAV file, converts stereo to mono, stores in `props.AudioData` / `props.Fs`
2. Slider/knob callbacks (`onFreqSlider`, `onGainKnob`, `onQSlider`) update `props.bands(i)` fields
3. Every change calls `updateEQ()`, which recomputes the combined frequency response and redraws the log-scale magnitude plot
4. `toggleAudio()` → `applyEQ()` chains all 5 biquad filters with `filter()` sequentially, then plays the result via `audioplayer`

**Filter math:** Second-order IIR (RBJ peaking EQ coefficients). `A = 10^(gain_dB/40)`, `wc = 2π·f/Fs`, `alpha = sin(wc)/(2Q)`. High-pass and Low-pass types use standard Butterworth biquad coefficients instead.

**UI layout:** `uigridlayout` with one frequency response axes at the top and 5 band panels below. Each band panel contains a type dropdown, a log-scale frequency slider (mapped via `10^(val/100 * range)`), a gain knob (−15 to +15 dB), and a Q slider.

### EqParametrico2.m — simplified equalizer

Earlier version (~138 lines). No log-scale slider mapping, no playback-stop callback, no Q slider, no audio normalization. Frequency is controlled directly via knob value. Useful as a reference for the simpler callback/filter wiring pattern.

### koch.m

Iterative Koch snowflake. Starts from an equilateral triangle and in each order applies an affine subdivision that replaces each segment with 4 segments (inserts a triangular peak at the midpoint). Each iteration is plotted with a vertical offset.

### morse_encoder.m

Loads `morse.mat` (contains `Alpha` char array and `Morse` cell array of dot/dash strings), maps each input character to its Morse sequence, and converts `.` → `1`, `-` → `111`, with inter-symbol `0`, inter-character `000`, and inter-word `0000` gaps.
