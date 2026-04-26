
classdef EqParametrico < matlab.apps.AppBase

    properties (Access = public)
        UIFigure  matlab.ui.Figure
        UIAxes    matlab.ui.control.UIAxes
        Grid      matlab.ui.container.GridLayout
        BypassBtn matlab.ui.control.StateButton
        LoadBtn   matlab.ui.control.Button
        PlayBtn   matlab.ui.control.Button
    end

    properties (Access = private)
        Fs           = 44100;
        NumBands     = 5;
        Gains        = zeros(1, 5);
        Freqs        = [100, 500, 1000, 5000, 10000];
        Qs           = ones(1, 5) * 0.707;
        Tipos        = {'Peaking','Peaking','Peaking','Peaking','Peaking'};

        % Audio engine
        AudioData    = [];
        AudioPeak    = 1;       % max(abs(AudioData)), set at load time
        ChunkSamples = 441000;  % 10 s * 44100 — recomputed on load
        PlayerObj    = [];
        IsPlaying    = false;
        PlayStartSample = 0;    % absolute sample offset into AudioData

        % Panel widgets
        FreqSliders = cell(1, 5);
        FreqLabels  = cell(1, 5);
        QLabels     = cell(1, 5);
        QSliders    = cell(1, 5);
        GainKnobs   = cell(1, 5);
        GainLabels  = cell(1, 5);

        % Spectrum overlay
        SpecFreqs = [];
        SpecMagdB = [];
        SpecTimer = [];

        % Debounce: single persistent polling timer + dirty flag
        % Replaces the stop/delete/create/start timer pattern entirely.
        DebounceTimer  = [];
        ParamsDirty    = false;
        LastChangeTime = [];    % uint64 from tic(); [] = not set

        % Mouse drag
        DragBand = 0;

        % Persistent graphics handles (no cla on update)
        PlotReady  = false;
        HEQCurve   = [];
        HSpecFill  = [];
        HZeroLine  = [];
        HBandDot   = cell(1, 5);
        HBandVLine = cell(1, 5);
        HBandLbl   = cell(1, 5);

        BandColors = [1 0.65 0.1; 0.4 1 0.4; 1 0.4 0.4; 0.9 0.4 1; 1 1 0.4];
    end

    % ------------------------------------------------------------------ %
    methods (Access = private)

        % ---- Biquad coefficients ----------------------------------------
        function [b, a] = biquadCoeffs(app, i)
            wc    = 2 * pi * app.Freqs(i) / app.Fs;
            wc    = max(0.005, min(pi - 0.01, wc));
            alpha = sin(wc) / (2 * app.Qs(i));
            cosw  = cos(wc);
            switch app.Tipos{i}
                case 'Peaking'
                    A = 10^(app.Gains(i) / 40);
                    b = [1+alpha*A, -2*cosw, 1-alpha*A];
                    a = [1+alpha/A, -2*cosw, 1-alpha/A];
                case 'High-Pass'
                    b = [(1+cosw)/2, -(1+cosw), (1+cosw)/2];
                    a = [1+alpha,    -2*cosw,     1-alpha  ];
                case 'Low-Pass'
                    b = [(1-cosw)/2,  (1-cosw), (1-cosw)/2];
                    a = [1+alpha,    -2*cosw,    1-alpha   ];
            end
        end

        % ---- EQ frequency response + handle-based plot update -----------
        function updateEQ(app)
            if isempty(app.UIFigure) || ~isvalid(app.UIFigure), return; end

            f     = logspace(log10(20), log10(min(app.Fs/2 - 1, 20000)), 512);
            z     = exp(1j * 2*pi*f / app.Fs);
            H     = ones(size(f));

            if ~app.BypassBtn.Value
                for i = 1:app.NumBands
                    [b, a] = app.biquadCoeffs(i);
                    H = H .* (b(1)+b(2).*z.^-1+b(3).*z.^-2) ./ ...
                             (a(1)+a(2).*z.^-1+a(3).*z.^-2);
                end
            end
            magdB = 20*log10(abs(H) + eps);

            if ~app.PlotReady
                app.initPlot(f, magdB);
                return;
            end

            % Handle-based updates: no cla, no flicker
            set(app.HEQCurve, 'XData', f, 'YData', magdB);

            for i = 1:app.NumBands
                fi = app.Freqs(i);
                % HP/LP nodes pinned at 0 dB — their gain property is unused
                gi = app.Gains(i) * strcmp(app.Tipos{i}, 'Peaking');
                set(app.HBandVLine{i}, 'XData', [fi fi]);
                set(app.HBandDot{i},   'XData', fi, 'YData', gi);
                set(app.HBandLbl{i},   'Position', [fi, gi + 2.2, 0]);
                if i == app.DragBand
                    set(app.HBandDot{i}, 'MarkerSize', 14, 'LineWidth', 2);
                else
                    set(app.HBandDot{i}, 'MarkerSize', 10, 'LineWidth', 1.5);
                end
            end

            if ~isempty(app.SpecFreqs)
                sf = app.SpecFreqs;  sm = app.SpecMagdB;
                set(app.HSpecFill, ...
                    'XData', [sf, fliplr(sf)], ...
                    'YData', [sm, -25*ones(1, numel(sm))], ...
                    'Visible', 'on');
            else
                set(app.HSpecFill, 'Visible', 'off');
            end
        end

        % ---- One-time graphics initialisation ---------------------------
        function initPlot(app, f, magdB)
            ax = app.UIAxes;
            hold(ax, 'on');

            app.HZeroLine = plot(ax, [20 20000], [0 0], ...
                'Color', [0.38 0.38 0.38], 'LineWidth', 0.8, 'LineStyle', ':');
            app.HZeroLine.HitTest = 'off';

            % Spectrum fill — placeholder vertices, hidden until playback
            app.HSpecFill = fill(ax, [20 20000 20000 20], [-25 -25 -25 -25], ...
                [0.08 0.35 0.55], 'FaceAlpha', 0.55, ...
                'EdgeColor', [0.1 0.5 0.75], 'LineWidth', 0.5, 'Visible', 'off');
            app.HSpecFill.HitTest = 'off';

            app.HEQCurve = plot(ax, f, magdB, 'LineWidth', 2.5, 'Color', [0 0.7 1]);
            app.HEQCurve.HitTest = 'off';

            for i = 1:app.NumBands
                c    = app.BandColors(i, :);
                dimC = c * 0.3 + [0.05 0.05 0.05];

                app.HBandVLine{i} = plot(ax, [app.Freqs(i) app.Freqs(i)], [-25 25], ...
                    'Color', dimC, 'LineWidth', 0.9, 'LineStyle', '--');
                app.HBandVLine{i}.HitTest = 'off';

                app.HBandDot{i} = plot(ax, app.Freqs(i), app.Gains(i), 'o', ...
                    'MarkerSize', 10, 'MarkerFaceColor', c, ...
                    'MarkerEdgeColor', [1 1 1], 'LineWidth', 1.5);
                % HitTest off: all clicks reach the axes ButtonDownFcn,
                % which handles selection by proximity calculation.
                app.HBandDot{i}.HitTest = 'off';

                app.HBandLbl{i} = text(ax, app.Freqs(i), app.Gains(i) + 2.2, ...
                    num2str(i), 'Color', c, 'FontSize', 9, 'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                    'Clipping', 'on');
                app.HBandLbl{i}.HitTest = 'off';
            end

            ax.XScale = 'log';
            ax.YLim   = [-25 25];
            ax.XLim   = [20 20000];
            grid(ax, 'on');
            app.PlotReady = true;
        end

        % ---- Apply all biquad filters to a signal -----------------------
        function out = applyEQ(app, in)
            out = in;
            if app.BypassBtn.Value, return; end
            for i = 1:app.NumBands
                [b, a] = app.biquadCoeffs(i);
                b = b / a(1);  a = a / a(1);
                out = filter(b, a, out);
            end
        end

        % ---- Core playback primitive: process + play N samples ----------
        %
        % Processes only ChunkSamples (10 s) at a time so applyEQ never
        % blocks the UI. Each chunk's StopFcn chains the next one silently.
        % Critically: StopFcn is cleared before stop() so onPlaybackStop
        % is never called during a restart — IsPlaying stays true.
        function startChunk(app, absPos)
            if ~app.IsPlaying, return; end

            N = min(app.ChunkSamples, length(app.AudioData) - absPos);
            if N < 100, app.onPlaybackStop(); return; end

            % Stop the current player without triggering onPlaybackStop.
            % This is the fix for IsPlaying being set to false during restart.
            if ~isempty(app.PlayerObj) && isvalid(app.PlayerObj)
                app.PlayerObj.StopFcn = '';
                stop(app.PlayerObj);
            end

            chunk     = app.AudioData(absPos+1 : absPos+N);
            processed = app.applyEQ(chunk);

            % Normalize relative to the full file's peak (computed at load).
            % Per-chunk renormalization would cause level jumps between restarts.
            if app.AudioPeak > 0
                processed = processed / app.AudioPeak * 0.99;
            end
            % Clip-protect for heavy boosts that exceed the original file peak.
            pk = max(abs(processed(:)));
            if pk > 0.99
                processed = processed * (0.99 / pk);
            end

            app.PlayStartSample = absPos;
            app.PlayerObj       = audioplayer(processed, app.Fs);

            nextPos = absPos + N;
            if nextPos < length(app.AudioData) - 100
                app.PlayerObj.StopFcn = @(~,~) app.startChunk(nextPos);
            else
                app.PlayerObj.StopFcn = @(~,~) app.onPlaybackStop();
            end
            play(app.PlayerObj);
        end

        % ---- Restart at current playback position with fresh EQ ---------
        function restartPlayback(app)
            if ~app.IsPlaying, return; end
            absPos = app.PlayStartSample;
            if ~isempty(app.PlayerObj) && isvalid(app.PlayerObj)
                try
                    absPos = app.PlayStartSample + app.PlayerObj.CurrentSample;
                catch
                end
            end
            absPos = min(absPos, length(app.AudioData) - 1);
            app.startChunk(absPos);
        end

        % ---- Debounce poll (fixedRate timer, runs for app lifetime) -----
        %
        % Replaces the stop/delete/create/start timer anti-pattern.
        % scheduleRestart() only writes a flag + tic; this callback fires
        % the actual restart 150 ms after the last parameter change.
        function debouncePoll(app)
            if ~isvalid(app.UIFigure), return; end
            if ~app.ParamsDirty || ~app.IsPlaying || isempty(app.LastChangeTime)
                return;
            end
            try
                if toc(app.LastChangeTime) < 0.15, return; end
            catch
                return;
            end
            app.ParamsDirty    = false;
            app.LastChangeTime = [];
            app.restartPlayback();
        end

        % ---- Mark parameters dirty (called by every UI callback) --------
        function scheduleRestart(app)
            if ~app.IsPlaying, return; end
            app.ParamsDirty    = true;
            app.LastChangeTime = tic;
        end

        % ---- Spectrum timer callback -------------------------------------
        function updateSpectrum(app)
            if ~app.IsPlaying, return; end
            if isempty(app.PlayerObj) || ~isvalid(app.PlayerObj), return; end
            try
                pos = app.PlayStartSample + app.PlayerObj.CurrentSample;
            catch
                return;
            end

            N        = 8192;
            startIdx = max(1, pos - N + 1);
            endIdx   = min(length(app.AudioData), startIdx + N - 1);
            chunk    = app.AudioData(startIdx:endIdx);
            if numel(chunk) < 256, return; end

            chunk(N, 1) = 0;
            win  = 0.5 * (1 - cos(2*pi*(0:N-1)' / (N-1)));
            Y    = fft(chunk .* win);
            fftF = (0:N/2) * app.Fs / N;
            fftM = abs(Y(1:N/2+1));

            dispF   = logspace(log10(20), log10(min(app.Fs/2, 20000)), 300);
            dispMag = interp1(fftF, fftM, dispF, 'linear', 0);
            dB      = 20*log10(dispMag + eps);
            dB      = dB - max(dB);
            dB      = max(dB * 0.35, -25);

            app.SpecFreqs = dispF;
            app.SpecMagdB = dB;
            app.updateEQ();
        end

        % ---- Stop and delete the spectrum timer -------------------------
        function stopSpecTimer(app)
            if ~isempty(app.SpecTimer)
                try stop(app.SpecTimer);   catch, end
                try delete(app.SpecTimer); catch, end
                app.SpecTimer = [];
            end
            app.SpecFreqs = [];
            app.SpecMagdB = [];
            if app.PlotReady, app.updateEQ(); end
        end

        % ---- Play / Stop ------------------------------------------------
        function toggleAudio(app)
            if isempty(app.AudioData), return; end

            if app.IsPlaying
                app.IsPlaying    = false;
                app.PlayBtn.Text = '▶  PLAY';
                if ~isempty(app.PlayerObj) && isvalid(app.PlayerObj)
                    app.PlayerObj.StopFcn = '';
                    stop(app.PlayerObj);
                end
                app.stopSpecTimer();
            else
                app.IsPlaying    = true;
                app.PlayBtn.Text = '■  STOP';
                app.startChunk(0);
                app.SpecTimer = timer('ExecutionMode', 'fixedRate', 'Period', 0.08, ...
                    'TimerFcn', @(~,~) app.updateSpectrum());
                start(app.SpecTimer);
            end
        end

        function onPlaybackStop(app)
            app.IsPlaying    = false;
            app.PlayBtn.Text = '▶  PLAY';
            app.stopSpecTimer();
        end

        % ---- Load WAV ---------------------------------------------------
        function loadAudio(app)
            [file, path] = uigetfile('*.wav', 'Select a WAV file');
            if isequal(file, 0), return; end
            try
                [data, fs] = audioread(fullfile(path, file));
                if size(data, 2) > 1, data = mean(data, 2); end
                app.Fs           = fs;
                app.ChunkSamples = round(fs * 10);
                app.AudioData    = data;
                app.AudioPeak    = max(abs(data(:)));
                if app.AudioPeak == 0, app.AudioPeak = 1; end
                app.UIFigure.Name = ['Equalizer  —  ' file];
            catch ME
                uialert(app.UIFigure, ME.message, 'Load Error');
            end
        end

        % ---- Shared property-change callback ----------------------------
        function updateProp(app, propName, idx, val)
            if iscell(app.(propName))
                app.(propName){idx} = val;
            else
                app.(propName)(idx) = val;
            end
            app.updateEQ();
            app.scheduleRestart();
        end

        function onGainKnob(app, idx, val)
            app.Gains(idx) = val;
            if val >= 0, app.GainLabels{idx}.Text = sprintf('+%.1f dB', val);
            else,        app.GainLabels{idx}.Text = sprintf('%.1f dB',  val); end
            app.updateEQ();
            app.scheduleRestart();
        end

        function onQSlider(app, idx, val)
            app.Qs(idx) = val;
            app.QLabels{idx}.Text = sprintf('%.2f', val);
            app.updateEQ();
            app.scheduleRestart();
        end

        function s = hzStr(~, hz)
            if hz >= 1000, s = sprintf('%.1f kHz', hz/1000);
            else,          s = sprintf('%d Hz', round(hz)); end
        end

        function onFreqSlider(app, idx, sliderVal)
            logMin = log10(20); logMax = log10(20000);
            freqHz = round(10^(logMin + sliderVal*(logMax-logMin)));
            app.Freqs(idx) = freqHz;
            app.FreqLabels{idx}.Text = app.hzStr(freqHz);
            app.updateEQ();
            app.scheduleRestart();
        end

        function onBypassToggle(app)
            app.updateEQ();
            app.scheduleRestart();
        end

        % ---- Mouse drag -------------------------------------------------
        function onAxesButtonDown(app)
            cp     = app.UIAxes.CurrentPoint;
            clickF = max(cp(1,1), 1);
            clickG = cp(1,2);

            logMin   = log10(20); logMax = log10(20000);
            logDist  = abs(log10(max(app.Freqs,1)) - log10(clickF)) / (logMax-logMin);
            gainDist = abs(app.Gains - clickG) / 30;
            [~, best] = min(logDist + 0.4*gainDist);

            if logDist(best) < 0.18
                app.DragBand = best;
                app.UIFigure.WindowButtonMotionFcn = @(~,~) app.onMouseMove();
                app.UIFigure.WindowButtonUpFcn     = @(~,~) app.onMouseUp();
                app.updateEQ();
            end
        end

        function onMouseMove(app)
            if app.DragBand == 0, return; end
            cp = app.UIAxes.CurrentPoint;
            i  = app.DragBand;

            newF         = max(20, min(20000, cp(1,1)));
            app.Freqs(i) = round(newF);

            logMin = log10(20); logMax = log10(20000);
            app.FreqSliders{i}.Value = (log10(newF)-logMin) / (logMax-logMin);
            app.FreqLabels{i}.Text   = app.hzStr(round(newF));

            % Gain drag only meaningful for Peaking; HP/LP ignore gain
            if strcmp(app.Tipos{i}, 'Peaking')
                newG = max(-15, min(15, cp(1,2)));
                app.Gains(i)           = newG;
                app.GainKnobs{i}.Value = newG;
                if newG >= 0, app.GainLabels{i}.Text = sprintf('+%.1f dB', newG);
                else,         app.GainLabels{i}.Text = sprintf('%.1f dB',  newG); end
            end

            app.updateEQ();
            app.scheduleRestart();
        end

        function onMouseUp(app)
            prev = app.DragBand;
            app.DragBand = 0;
            app.UIFigure.WindowButtonMotionFcn = '';
            app.UIFigure.WindowButtonUpFcn     = '';
            if prev > 0 && app.PlotReady
                set(app.HBandDot{prev}, 'MarkerSize', 10, 'LineWidth', 1.5);
            end
            app.updateEQ();
        end

        % ---- Scroll wheel: Q adjustment for nearest band ----------------
        function onScrollWheel(app, evt)
            cp     = app.UIAxes.CurrentPoint;
            clickF = cp(1,1);
            if ~isfinite(clickF) || clickF < 15 || clickF > 25000, return; end

            if app.DragBand > 0
                i = app.DragBand;
            else
                logMin  = log10(20); logMax = log10(20000);
                logDist = abs(log10(max(app.Freqs,1)) - log10(max(clickF,1))) / (logMax-logMin);
                [minD, i] = min(logDist);
                if minD > 0.2, return; end
            end

            factor    = 1.2 ^ (-evt.VerticalScrollCount);
            app.Qs(i) = max(0.1, min(10, app.Qs(i) * factor));
            app.QSliders{i}.Value = app.Qs(i);
            app.QLabels{i}.Text   = sprintf('%.2f', app.Qs(i));
            app.updateEQ();
            app.scheduleRestart();
        end

        % ---- Window close: clean up all timers and players --------------
        function onClose(app)
            if ~isempty(app.DebounceTimer) && isvalid(app.DebounceTimer)
                try stop(app.DebounceTimer);   catch, end
                try delete(app.DebounceTimer); catch, end
            end
            if ~isempty(app.SpecTimer)
                try stop(app.SpecTimer);   catch, end
                try delete(app.SpecTimer); catch, end
            end
            if ~isempty(app.PlayerObj) && isvalid(app.PlayerObj)
                try
                    app.PlayerObj.StopFcn = '';
                    stop(app.PlayerObj);
                catch, end
            end
            delete(app.UIFigure);
        end

    end

    % ------------------------------------------------------------------ %
    methods (Access = protected)
        function setup(app)
            app.UIFigure = uifigure(...
                'Name',     'Equalizer', ...
                'Position', [100 100 1100 720], ...
                'Color',    [0.12 0.12 0.12]);
            app.UIFigure.CloseRequestFcn = @(~,~) app.onClose();

            app.Grid = uigridlayout(app.UIFigure, [3, 5]);
            app.Grid.RowHeight       = {'1x', 320, 46};
            app.Grid.ColumnWidth     = {'1x','1x','1x','1x','1x'};
            app.Grid.BackgroundColor = [0.12 0.12 0.12];
            app.Grid.Padding         = [12 12 12 12];
            app.Grid.RowSpacing      = 10;
            app.Grid.ColumnSpacing   = 8;

            app.UIAxes = uiaxes(app.Grid);
            app.UIAxes.Layout.Row    = 1;
            app.UIAxes.Layout.Column = [1 5];
            app.UIAxes.BackgroundColor = [0.05 0.05 0.05];
            app.UIAxes.Color           = [0.05 0.05 0.05];
            app.UIAxes.XColor          = [0.6 0.6 0.6];
            app.UIAxes.YColor          = [0.6 0.6 0.6];
            app.UIAxes.GridColor       = [0.3 0.3 0.3];
            app.UIAxes.GridAlpha       = 0.5;
            app.UIAxes.FontSize        = 10;
            app.UIAxes.Title.String    = 'Frequency Response';
            app.UIAxes.Title.Color     = [0.9 0.9 0.9];
            app.UIAxes.Title.FontSize  = 12;
            app.UIAxes.XLabel.String   = 'Frequency (Hz)';
            app.UIAxes.XLabel.Color    = [0.7 0.7 0.7];
            app.UIAxes.YLabel.String   = 'Gain (dB)';
            app.UIAxes.YLabel.Color    = [0.7 0.7 0.7];

            disableDefaultInteractivity(app.UIAxes);
            app.UIAxes.ButtonDownFcn          = @(~,~) app.onAxesButtonDown();
            app.UIFigure.WindowScrollWheelFcn = @(~,e)  app.onScrollWheel(e);

            for i = 1:5
                pnl = uipanel(app.Grid, ...
                    'Title',           ['  Band ' num2str(i)], ...
                    'BackgroundColor', [0.18 0.18 0.18], ...
                    'ForegroundColor', [0.85 0.85 0.85], ...
                    'FontWeight',      'bold', ...
                    'FontSize',        10, ...
                    'BorderType',      'line');
                pnl.Layout.Row    = 2;
                pnl.Layout.Column = i;

                uidropdown(pnl, ...
                    'Items',           {'Peaking','High-Pass','Low-Pass'}, ...
                    'Value',           app.Tipos{i}, ...
                    'Position',        [8 278 154 24], ...
                    'FontSize',        10, ...
                    'ValueChangedFcn', @(dd,~) app.updateProp('Tipos', i, dd.Value));

                uilabel(pnl, 'Text','FREQ','Position',[8 253 40 16],...
                    'FontSize',9,'FontColor',[0.55 0.55 0.55]);

                logMin = log10(20); logMax = log10(20000);
                initT  = (log10(app.Freqs(i)) - logMin) / (logMax - logMin);

                app.FreqLabels{i} = uilabel(pnl,...
                    'Text',               app.hzStr(app.Freqs(i)),...
                    'Position',           [50 253 114 16],...
                    'FontSize',           10,'FontWeight','bold',...
                    'FontColor',          [0.15 0.75 1],...
                    'HorizontalAlignment','right');

                app.FreqSliders{i} = uislider(pnl,...
                    'Limits',[0 1],'Value',initT,...
                    'MajorTicks',[],'MinorTicks',[],...
                    'Position',[8 236 154 3],...
                    'ValueChangedFcn',@(sl,~) app.onFreqSlider(i, sl.Value));

                uilabel(pnl,'Text','','Position',[8 224 154 1],...
                    'BackgroundColor',[0.30 0.30 0.30]);

                uilabel(pnl,'Text','GAIN','Position',[8 210 40 16],...
                    'FontSize',9,'FontColor',[0.55 0.55 0.55]);

                app.GainLabels{i} = uilabel(pnl,'Text','0 dB',...
                    'Position',[50 210 114 16],'FontSize',10,'FontWeight','bold',...
                    'FontColor',[1 0.65 0.1],'HorizontalAlignment','right');

                app.GainKnobs{i} = uiknob(pnl,...
                    'Limits',[-15 15],'Value',app.Gains(i),...
                    'MajorTicks',[-15 0 15],'MinorTicks',[-10 -5 5 10],...
                    'FontSize',9,'FontColor',[0.65 0.65 0.65],...
                    'Position',[42 112 86 86],...
                    'ValueChangedFcn',@(kn,~) app.onGainKnob(i, kn.Value));

                uilabel(pnl,'Text','','Position',[8 100 154 1],...
                    'BackgroundColor',[0.30 0.30 0.30]);

                uilabel(pnl,'Text','Q','Position',[8 82 15 16],...
                    'FontSize',9,'FontColor',[0.55 0.55 0.55]);

                app.QLabels{i} = uilabel(pnl,...
                    'Text',               sprintf('%.2f', app.Qs(i)),...
                    'Position',           [26 82 138 16],...
                    'FontSize',           10,'FontWeight','bold',...
                    'FontColor',          [0.5 1 0.5],...
                    'HorizontalAlignment','right');

                app.QSliders{i} = uislider(pnl,...
                    'Limits',[0.1 10],'Value',app.Qs(i),...
                    'MajorTicks',[],'MinorTicks',[],...
                    'Position',[8 65 154 3],...
                    'ValueChangedFcn',@(sl,~) app.onQSlider(i, sl.Value));
            end

            btnStyle = {'FontSize',11,'FontWeight','bold',...
                        'BackgroundColor',[0.25 0.25 0.25],'FontColor',[0.9 0.9 0.9]};

            app.LoadBtn = uibutton(app.Grid,'Text','⏏  LOAD',btnStyle{:},...
                'ButtonPushedFcn',@(~,~) app.loadAudio());
            app.LoadBtn.Layout.Row=3;  app.LoadBtn.Layout.Column=1;

            app.BypassBtn = uibutton(app.Grid,'state','Text','BYPASS',btnStyle{:},...
                'ValueChangedFcn',@(~,~) app.onBypassToggle());
            app.BypassBtn.Layout.Row=3; app.BypassBtn.Layout.Column=3;

            app.PlayBtn = uibutton(app.Grid,'Text','▶  PLAY',btnStyle{:},...
                'ButtonPushedFcn',@(~,~) app.toggleAudio());
            app.PlayBtn.Layout.Row=3;  app.PlayBtn.Layout.Column=5;

            % Single debounce polling timer — created once, never recreated.
            % Fires every 50 ms; triggers a restart 150 ms after last change.
            app.DebounceTimer = timer('ExecutionMode', 'fixedRate', 'Period', 0.05, ...
                'TimerFcn', @(~,~) app.debouncePoll());
            start(app.DebounceTimer);

            app.updateEQ();
        end
    end

    methods (Access = public)
        function app = EqParametrico()
            setup(app);
        end
    end

end
