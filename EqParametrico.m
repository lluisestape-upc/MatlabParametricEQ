classdef EqParametrico < handle
% EqParametrico  –  5-band parametric equaliser (MATLAB uifigure app)
%
% Usage:
%   app = EqParametrico();

    % ------------------------------------------------------------------ %
    %  PUBLIC PROPERTIES  (UI components)                                 %
    % ------------------------------------------------------------------ %
    properties (Access = public)
        UIFigure      matlab.ui.Figure
        UIAxes        matlab.ui.control.UIAxes
        Grid          matlab.ui.container.GridLayout
        BypassBtn     matlab.ui.control.StateButton
        LoadBtn       matlab.ui.control.Button
        PlayBtn       matlab.ui.control.Button
    end

    % ------------------------------------------------------------------ %
    %  PRIVATE PROPERTIES  (DSP state)                                    %
    % ------------------------------------------------------------------ %
    properties (Access = private)
        Fs        = 44100;
        NumBands  = 5;
        Gains     = zeros(1, 5);
        Freqs     = [100, 500, 1000, 5000, 10000];
        Qs        = ones(1, 5) * 0.707;
        Tipos     = {'Peaking', 'Peaking', 'Peaking', 'Peaking', 'Peaking'};
        AudioData = [];
        PlayerObj = [];
        IsPlaying = false;

        FreqSliders = cell(1, 5);
        FreqLabels  = cell(1, 5);
        QLabels     = cell(1, 5);
    end

    % ------------------------------------------------------------------ %
    %  PRIVATE HELPERS                                                     %
    % ------------------------------------------------------------------ %
    methods (Access = private)

        % ---------- EQ frequency-response plot ----------
        function updateEQ(app)
            if isempty(app.UIAxes), return; end
            f = logspace(log10(20), log10(app.Fs/2), 500);
            z = exp(1j * 2 * pi * f / app.Fs);
            TotalResponse = ones(size(f));

            if ~app.BypassBtn.Value
                for i = 1:app.NumBands
                    wc    = 2 * pi * app.Freqs(i) / app.Fs;
                    wc    = max(0.005, min(pi - 0.01, wc));
                    alpha = sin(wc) / (2 * app.Qs(i));
                    cosw  = cos(wc);

                    switch app.Tipos{i}
                        case 'Peaking'
                            A = 10^(app.Gains(i) / 40);
                            b = [1 + alpha*A,  -2*cosw,  1 - alpha*A];
                            a = [1 + alpha/A,  -2*cosw,  1 - alpha/A];
                        case 'High-Pass'
                            b = [(1 + cosw)/2, -(1 + cosw), (1 + cosw)/2];
                            a = [1 + alpha,    -2*cosw,      1 - alpha  ];
                        case 'Low-Pass'
                            b = [(1 - cosw)/2,  (1 - cosw), (1 - cosw)/2];
                            a = [1 + alpha,    -2*cosw,      1 - alpha  ];
                    end

                    H = (b(1) + b(2).*z.^-1 + b(3).*z.^-2) ./ ...
                        (a(1) + a(2).*z.^-1 + a(3).*z.^-2);
                    TotalResponse = TotalResponse .* H;
                end
            end

            magdB = 20 * log10(abs(TotalResponse) + eps);
            plot(app.UIAxes, f, magdB, 'LineWidth', 2, 'Color', [0, 0.7, 1]);
            app.UIAxes.XScale = 'log';
            app.UIAxes.YLim   = [-25 25];
            app.UIAxes.XLim   = [20 20000];
            grid(app.UIAxes, 'on');
        end

        % ---------- Apply EQ filters to a signal ----------
        function out = applyEQ(app, in)
            out = in;
            if app.BypassBtn.Value, return; end

            for i = 1:app.NumBands
                wc    = 2 * pi * app.Freqs(i) / app.Fs;
                wc    = max(0.005, min(pi - 0.01, wc));
                alpha = sin(wc) / (2 * app.Qs(i));
                cosw  = cos(wc);

                switch app.Tipos{i}
                    case 'Peaking'
                        A = 10^(app.Gains(i) / 40);
                        b = [1 + alpha*A,  -2*cosw,  1 - alpha*A];
                        a = [1 + alpha/A,  -2*cosw,  1 - alpha/A];
                    case 'High-Pass'
                        b = [(1 + cosw)/2, -(1 + cosw), (1 + cosw)/2];
                        a = [1 + alpha,    -2*cosw,      1 - alpha  ];
                    case 'Low-Pass'
                        b = [(1 - cosw)/2,  (1 - cosw), (1 - cosw)/2];
                        a = [1 + alpha,    -2*cosw,      1 - alpha  ];
                end
                b = b / a(1);
                a = a / a(1);
                out = filter(b, a, out);
            end
        end

        % ---------- Play / Stop toggle ----------
        function toggleAudio(app)
            if isempty(app.AudioData), return; end

            if app.IsPlaying
                if ~isempty(app.PlayerObj) && isvalid(app.PlayerObj)
                    stop(app.PlayerObj);
                end
                app.IsPlaying    = false;
                app.PlayBtn.Text = '▶  PLAY';
            else
                processed = applyEQ(app, app.AudioData);
                maxVal = max(abs(processed(:)));
                if maxVal > 0, processed = processed / maxVal * 0.99; end

                app.PlayerObj = audioplayer(processed, app.Fs);
                app.PlayerObj.StopFcn = @(~,~) app.onPlaybackStop();

                play(app.PlayerObj);
                app.IsPlaying    = true;
                app.PlayBtn.Text = '■  STOP';
            end
        end

        function onPlaybackStop(app)
            app.IsPlaying    = false;
            app.PlayBtn.Text = '▶  PLAY';
        end

        % ---------- Load WAV file ----------
        function loadAudio(app)
            [file, path] = uigetfile('*.wav', 'Select a WAV file');
            if isequal(file, 0), return; end

            try
                [data, fs] = audioread(fullfile(path, file));
                app.Fs = fs;
                if size(data, 2) > 1
                    data = mean(data, 2);
                end
                app.AudioData        = data;
                app.UIFigure.Name    = ['Equalizer  —  ' file];
            catch ME
                uialert(app.UIFigure, ME.message, 'Load Error');
            end
        end

        % ---------- Generic property updater ----------
        function updateProp(app, propName, idx, val)
            if iscell(app.(propName))
                app.(propName){idx} = val;
            else
                app.(propName)(idx) = val;
            end
            app.updateEQ();
        end

        % ---------- Gain knob callback ----------
        function onGainKnob(app, idx, val, pnl)
            app.Gains(idx) = val;
            lbl = findobj(pnl, 'Tag', sprintf('GainLbl%d', idx));
            if ~isempty(lbl)
                if val >= 0
                    lbl.Text = sprintf('+%.1f dB', val);
                else
                    lbl.Text = sprintf('%.1f dB', val);
                end
            end
            app.updateEQ();
        end

        % ---------- Q slider callback ----------
        function onQSlider(app, idx, val)
            app.Qs(idx)           = val;
            app.QLabels{idx}.Text = sprintf('%.2f', val);
            app.updateEQ();
        end

        % ---------- Hz formatting helper ----------
        function s = hzStr(~, hz)
            if hz >= 1000
                s = sprintf('%.1f kHz', hz / 1000);
            else
                s = sprintf('%d Hz', round(hz));
            end
        end

        % ---------- Log-scale frequency slider callback ----------
        function onFreqSlider(app, idx, sliderVal)
            logMin = log10(20);
            logMax = log10(20000);
            freqHz = 10 .^ (logMin + sliderVal * (logMax - logMin));
            freqHz = round(freqHz);

            app.Freqs(idx)            = freqHz;
            app.FreqLabels{idx}.Text  = app.hzStr(freqHz);
            app.updateEQ();
        end

        % ---------- Build UI ----------
        function setup(app)
            % ---- Figure ----
            app.UIFigure = uifigure( ...
                'Name',     'Equalizer', ...
                'Position', [100 100 1100 720], ...
                'Color',    [0.12 0.12 0.12]);

            % ---- Main grid:  rows = [plot | bands | buttons] ----
            app.Grid = uigridlayout(app.UIFigure, [3, 5]);
            app.Grid.RowHeight       = {'1x', 320, 46};
            app.Grid.ColumnWidth     = {'1x','1x','1x','1x','1x'};
            app.Grid.BackgroundColor = [0.12 0.12 0.12];
            app.Grid.Padding         = [12 12 12 12];
            app.Grid.RowSpacing      = 10;
            app.Grid.ColumnSpacing   = 8;

            % ---- Frequency-response axes ----
            app.UIAxes = uiaxes(app.Grid);
            app.UIAxes.Layout.Row    = 1;
            app.UIAxes.Layout.Column = [1 5];
            app.UIAxes.BackgroundColor  = [0.05 0.05 0.05];
            app.UIAxes.Color            = [0.05 0.05 0.05];
            app.UIAxes.XColor           = [0.6 0.6 0.6];
            app.UIAxes.YColor           = [0.6 0.6 0.6];
            app.UIAxes.GridColor        = [0.3 0.3 0.3];
            app.UIAxes.GridAlpha        = 0.5;
            app.UIAxes.FontSize         = 10;
            app.UIAxes.Title.String     = 'Frequency Response';
            app.UIAxes.Title.Color      = [0.9 0.9 0.9];
            app.UIAxes.Title.FontSize   = 12;
            app.UIAxes.XLabel.String    = 'Frequency (Hz)';
            app.UIAxes.XLabel.Color     = [0.7 0.7 0.7];
            app.UIAxes.YLabel.String    = 'Gain (dB)';
            app.UIAxes.YLabel.Color     = [0.7 0.7 0.7];

            % ---- Band panels ----
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

                % -- Filter-type dropdown --
                uidropdown(pnl, ...
                    'Items',           {'Peaking', 'High-Pass', 'Low-Pass'}, ...
                    'Value',           app.Tipos{i}, ...
                    'Position',        [8 278 154 24], ...
                    'FontSize',        10, ...
                    'ValueChangedFcn', @(dd,~) app.updateProp('Tipos', i, dd.Value));

                % ---- FREQ section ----
                uilabel(pnl, ...
                    'Text',      'FREQ', ...
                    'Position',  [8 253 40 16], ...
                    'FontSize',  9, ...
                    'FontColor', [0.55 0.55 0.55]);

                logMin = log10(20);
                logMax = log10(20000);
                initT  = (log10(app.Freqs(i)) - logMin) / (logMax - logMin);

                app.FreqLabels{i} = uilabel(pnl, ...
                    'Text',                app.hzStr(app.Freqs(i)), ...
                    'Position',            [50 253 114 16], ...
                    'FontSize',            10, ...
                    'FontWeight',          'bold', ...
                    'FontColor',           [0.15 0.75 1], ...
                    'HorizontalAlignment', 'right');

                app.FreqSliders{i} = uislider(pnl, ...
                    'Limits',          [0 1], ...
                    'Value',           initT, ...
                    'MajorTicks',      [], ...
                    'MinorTicks',      [], ...
                    'Position',        [8 236 154 3], ...
                    'ValueChangedFcn', @(sl,~) app.onFreqSlider(i, sl.Value));

                % -- separator --
                uilabel(pnl, 'Text', '', 'Position', [8 224 154 1], ...
                    'BackgroundColor', [0.30 0.30 0.30]);

                % ---- GAIN section ----
                uilabel(pnl, ...
                    'Text',      'GAIN', ...
                    'Position',  [8 210 40 16], ...
                    'FontSize',  9, ...
                    'FontColor', [0.55 0.55 0.55]);

                uilabel(pnl, ...
                    'Text',                '0 dB', ...
                    'Tag',                 sprintf('GainLbl%d', i), ...
                    'Position',            [50 210 114 16], ...
                    'FontSize',            10, ...
                    'FontWeight',          'bold', ...
                    'FontColor',           [1 0.65 0.1], ...
                    'HorizontalAlignment', 'right');

                uiknob(pnl, ...
                    'Limits',          [-15 15], ...
                    'Value',           app.Gains(i), ...
                    'MajorTicks',      [-15 0 15], ...
                    'MinorTicks',      [-10 -5 5 10], ...
                    'FontSize',        9, ...
                    'FontColor',       [0.65 0.65 0.65], ...
                    'Position',        [42 112 86 86], ...
                    'ValueChangedFcn', @(kn,~) app.onGainKnob(i, kn.Value, pnl));

                % -- separator --
                uilabel(pnl, 'Text', '', 'Position', [8 100 154 1], ...
                    'BackgroundColor', [0.30 0.30 0.30]);

                % ---- Q section ----
                uilabel(pnl, ...
                    'Text',      'Q', ...
                    'Position',  [8 82 15 16], ...
                    'FontSize',  9, ...
                    'FontColor', [0.55 0.55 0.55]);

                app.QLabels{i} = uilabel(pnl, ...
                    'Text',                sprintf('%.2f', app.Qs(i)), ...
                    'Position',            [26 82 138 16], ...
                    'FontSize',            10, ...
                    'FontWeight',          'bold', ...
                    'FontColor',           [0.5 1 0.5], ...
                    'HorizontalAlignment', 'right');

                uislider(pnl, ...
                    'Limits',          [0.1 10], ...
                    'Value',           app.Qs(i), ...
                    'MajorTicks',      [], ...
                    'MinorTicks',      [], ...
                    'Position',        [8 65 154 3], ...
                    'ValueChangedFcn', @(sl,~) app.onQSlider(i, sl.Value));
            end

            % ---- Bottom buttons ----
            btnStyle = {'FontSize', 11, 'FontWeight', 'bold', ...
                        'BackgroundColor', [0.25 0.25 0.25], ...
                        'FontColor', [0.9 0.9 0.9]};

            app.LoadBtn = uibutton(app.Grid, ...
                'Text',            '⏏  LOAD', ...
                btnStyle{:}, ...
                'ButtonPushedFcn', @(~,~) app.loadAudio());
            app.LoadBtn.Layout.Row    = 3;
            app.LoadBtn.Layout.Column = 1;

            app.BypassBtn = uibutton(app.Grid, 'state', ...
                'Text',            'BYPASS', ...
                btnStyle{:}, ...
                'ValueChangedFcn', @(~,~) app.updateEQ());
            app.BypassBtn.Layout.Row    = 3;
            app.BypassBtn.Layout.Column = 3;

            app.PlayBtn = uibutton(app.Grid, ...
                'Text',            '▶  PLAY', ...
                btnStyle{:}, ...
                'ButtonPushedFcn', @(~,~) app.toggleAudio());
            app.PlayBtn.Layout.Row    = 3;
            app.PlayBtn.Layout.Column = 5;

            % ---- Initial plot ----
            app.updateEQ();
        end

    end % private methods

    % ------------------------------------------------------------------ %
    %  CONSTRUCTOR                                                         %
    % ------------------------------------------------------------------ %
    methods (Access = public)
        % FIX: constructor name must match the class name exactly
        function app = EqParametrico()
            setup(app);
        end
    end

end
