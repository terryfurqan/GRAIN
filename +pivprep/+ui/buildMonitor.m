function monitor = buildMonitor(nFrames, useStab)
%BUILDMONITOR  Bangun jendela monitor real-time untuk batch PIVPrep.
%
%   monitor = pivprep.ui.buildMonitor(nFrames, useStab)
%
%   INPUT:
%       nFrames  jumlah total frame yang akan diproses
%       useStab  logical; true jika stabilisasi aktif (kurva jitter
%                akan ditampilkan), false untuk progress saja
%
%   OUTPUT:
%       monitor struct dengan handle figure, axes, line, dan state:
%           .fig          handle figure
%           .axInst       handle axes instantaneous (jika useStab)
%           .axCum        handle axes cumulative   (jika useStab)
%           .axProg       handle axes progress bar
%           .lineInstX    handle plot dx instantaneous
%           .lineInstY    handle plot dy instantaneous
%           .lineCumX     handle plot dx cumulative (running sum)
%           .lineCumY     handle plot dy cumulative (running sum)
%           .lineMagInst  handle plot magnitude instantaneous (overlay)
%           .barProgress  handle horizontal bar progress
%           .txtStatus    handle text status (ETA, fps, dll.)
%           .nFrames      total frame
%           .useStab      flag stabilisasi
%           .frames       vektor indeks frame yang sudah diproses
%           .instX, .instY  vektor dx, dy signed per frame
%           .cumX, .cumY    vektor running sum dx, dy
%           .magInst        vektor magnitude jitter per frame
%           .sumX, .sumY    skalar accumulator running sum
%
%   PENGGUNAAN:
%       monitor = pivprep.ui.buildMonitor(nFrames, useStab);
%       for k = 1:nFrames
%           ...  % proses
%           monitor = pivprep.ui.updateMonitor(monitor, k, dx, dy, jit, elapsed);
%       end

    if nargin < 2 || isempty(useStab); useStab = true; end

    figW = 980;
    figH = 620;

    % Posisi awal di kanan layar agar tidak menutupi waitbar
    screenSz = get(0, 'ScreenSize');
    x0 = max(20, screenSz(3) - figW - 40);
    y0 = max(60, round((screenSz(4) - figH) / 2));

    fig = figure( ...
        'Name', 'PIVPrep Monitor - Real-time Jitter and Progress', ...
        'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'figure', ...
        'Color', [0.97 0.97 0.97], ...
        'Units', 'pixels', 'Position', [x0 y0 figW figH]);

    monitor = struct();
    monitor.fig     = fig;
    monitor.nFrames = nFrames;
    monitor.useStab = useStab;
    monitor.frames  = [];
    monitor.instX   = [];
    monitor.instY   = [];
    monitor.cumX    = [];
    monitor.cumY    = [];
    monitor.magInst = [];
    monitor.sumX    = 0;
    monitor.sumY    = 0;

    if useStab
        % --- Panel 1: Instantaneous (signed dx, dy per frame) ---
        monitor.axInst = subplot(3, 1, 1, 'Parent', fig);
        hold(monitor.axInst, 'on');
        grid(monitor.axInst, 'on');
        box(monitor.axInst, 'on');

        monitor.lineInstX = plot(monitor.axInst, NaN, NaN, '-', ...
            'Color', [0.10 0.45 0.80], 'LineWidth', 1.3, ...
            'DisplayName', 'dx (signed, px)');
        monitor.lineInstY = plot(monitor.axInst, NaN, NaN, '-', ...
            'Color', [0.85 0.35 0.25], 'LineWidth', 1.3, ...
            'DisplayName', 'dy (signed, px)');
        monitor.lineMagInst = plot(monitor.axInst, NaN, NaN, ':', ...
            'Color', [0.35 0.35 0.35], 'LineWidth', 1.0, ...
            'DisplayName', '|jitter| (magnitude)');

        yline(monitor.axInst, 0, 'k-', 'LineWidth', 0.4, ...
            'HandleVisibility', 'off');

        title(monitor.axInst, ...
            'Instantaneous Jitter per Frame (signed)', ...
            'FontWeight', 'bold');
        ylabel(monitor.axInst, 'pixels');
        legend(monitor.axInst, 'Location', 'best', 'FontSize', 8);
        xlim(monitor.axInst, [1 max(nFrames, 2)]);

        % --- Panel 2: Cumulative (running sum signed) ---
        monitor.axCum = subplot(3, 1, 2, 'Parent', fig);
        hold(monitor.axCum, 'on');
        grid(monitor.axCum, 'on');
        box(monitor.axCum, 'on');

        monitor.lineCumX = plot(monitor.axCum, NaN, NaN, '-', ...
            'Color', [0.10 0.45 0.80], 'LineWidth', 1.5, ...
            'DisplayName', 'cumulative dx');
        monitor.lineCumY = plot(monitor.axCum, NaN, NaN, '-', ...
            'Color', [0.85 0.35 0.25], 'LineWidth', 1.5, ...
            'DisplayName', 'cumulative dy');

        yline(monitor.axCum, 0, 'k-', 'LineWidth', 0.4, ...
            'HandleVisibility', 'off');

        title(monitor.axCum, ...
            'Cumulative Jitter Drift (running sum, signed)', ...
            'FontWeight', 'bold');
        ylabel(monitor.axCum, 'pixels');
        legend(monitor.axCum, 'Location', 'best', 'FontSize', 8);
        xlim(monitor.axCum, [1 max(nFrames, 2)]);

        % --- Panel 3: Progress ---
        monitor.axProg = subplot(3, 1, 3, 'Parent', fig);
    else
        % Tanpa stabilisasi: hanya progress, tampilkan besar
        monitor.axInst      = [];
        monitor.axCum       = [];
        monitor.lineInstX   = [];
        monitor.lineInstY   = [];
        monitor.lineCumX    = [];
        monitor.lineCumY    = [];
        monitor.lineMagInst = [];
        monitor.axProg      = axes('Parent', fig, ...
            'Units', 'normalized', 'Position', [0.08 0.30 0.88 0.45]);
    end

    % --- Progress bar (horizontal) ---
    hold(monitor.axProg, 'on');
    box(monitor.axProg, 'on');

    % Background bar (capacity)
    fill(monitor.axProg, [0 nFrames nFrames 0], [0.6 0.6 1.4 1.4], ...
        [0.88 0.88 0.88], 'EdgeColor', [0.7 0.7 0.7], ...
        'HandleVisibility', 'off');

    % Foreground bar (progress)
    monitor.barProgress = fill(monitor.axProg, ...
        [0 0 0 0], [0.6 0.6 1.4 1.4], [0.25 0.65 0.35], ...
        'EdgeColor', 'none');

    xlim(monitor.axProg, [0 max(nFrames, 1)]);
    ylim(monitor.axProg, [0.4 1.6]);
    monitor.axProg.YTick = [];
    title(monitor.axProg, ...
        sprintf('Progress  |  0 / %d frames', nFrames), ...
        'FontWeight', 'bold');
    xlabel(monitor.axProg, 'Frame index');

    % Text status di bawah bar
    monitor.txtStatus = text(monitor.axProg, ...
        nFrames / 2, 1, 'Initializing...', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 11, 'FontWeight', 'bold', ...
        'Color', [0.15 0.15 0.15]);

    drawnow;
end
