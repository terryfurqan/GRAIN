function report = piv_kymograph_fault_detection(pivMatFile, varargin)
% PIV_KYMOGRAPH_FAULT_DETECTION  Automated Spatiotemporal Fault, Scarp, and
% Detachment Detection using Multi-Line Kymograph (axPSG) & Time-Series (axPOT)
% Tomography on Sandbox Analog Modeling PIV Datasets.
%
% Pemakaian:
%   report = piv_kymograph_fault_detection(pivMatFile)
%   report = piv_kymograph_fault_detection(pivMatFile, 'NumLines', 20, 'RenderFigures', true)
%
% Argumen Nama-Nilai (Opsional):
%   'RawMatFile'     : Path ke kontainer .mat mentah (prep.raw.blobs) untuk deteksi
%                      dead-frame konsekutif via QPIV (default: '')
%   'NumLines'       : Jumlah garis scanline horizontal dari atas ke bawah (default: 20)
%   'SpacingPx'      : Jarak antar titik sampel sepanjang garis dalam piksel (default: 16)
%   'ShearDeadband'  : Ambang deadband Cleaned Shear Strain \gamma_xy (default: 0.0035)
%   'OutputDir'      : Folder tujuan penyimpanan CSV, MAT, dan JPG (default: otomatis)
%   'RenderFigures'  : true/false untuk merender dashboard JPG verifikasi (default: true)
%
% Output (struct `report`):
%   - lineTable      : Tabel 20 garis horizontal (Y_AxMain, X_Fault, PeakPosShear,
%                      PeakNegShear, MeanVelHW, X_VelDrop, VerticalZone)
%   - faultDipDeg    : Estimasi sudut kemiringan (dip angle, derajat) sesar utama
%   - detachmentY_px : Estimasi posisi vertikal bidang detachment basal (px)
%   - detachmentX_px : Rentang horizontal [X_min, X_max] bidang detachment basal (px)
%   - csvFile        : Path berkas CSV hasil deteksi
%   - matFile        : Path berkas MAT matriks kymograph 20 garis
%   - figFiles       : Cell array path berkas JPG visualisasi (bila RenderFigures=true)

    p = inputParser;
    addRequired(p, 'pivMatFile', @(x) ischar(x) || isstring(x));
    addParameter(p, 'RawMatFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'NumLines', 20, @(x) isnumeric(x) && isscalar(x) && x >= 3);
    addParameter(p, 'SpacingPx', 16, @(x) isnumeric(x) && isscalar(x) && x >= 4);
    addParameter(p, 'ShearDeadband', 0.0035, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'OutputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'RenderFigures', true, @(x) islogical(x) || isnumeric(x));
    parse(p, pivMatFile, varargin{:});
    opt = p.Results;

    pivMatFile = char(opt.pivMatFile);
    here = fileparts(mfilename('fullpath'));
    if isfile(fullfile(here, 'grain_setup.m'))
        run(fullfile(here, 'grain_setup.m'));
    end

    [pivDir, expName, ~] = fileparts(pivMatFile);
    if isempty(opt.OutputDir)
        outDir = fullfile(pivDir, sprintf('%s_Kymo_Fault_Detection', expName));
    else
        outDir = char(opt.OutputDir);
    end
    if ~isfolder(outDir), mkdir(outDir); end

    fprintf('========================================================================\n');
    fprintf('🔬 PIV KYMOGRAPH FAULT DETECTION — %s\n', expName);
    fprintf('========================================================================\n');

    S_piv = load(pivMatFile);
    dataFull = pivcore.data.buildDataset(S_piv);
    nF = dataFull.nFrames;
    x1 = pivcore.data.safeFrame(dataFull.x, 1);
    y1 = pivcore.data.safeFrame(dataFull.y, 1);
    xExt = [min(x1(:)), max(x1(:))];
    yExt = [min(y1(:)), max(y1(:))];
    yMid = (yExt(1) + yExt(2)) / 2;
    yF   = (yExt(2) + yExt(1)) - y1;

    % Precompute seluruh frame: |V|, U, V, dan Cleaned Shear Strain (Med 3x3 + Gauss 1.8)
    velStack      = cell(1, nF);
    uStack        = cell(1, nF);
    vStack        = cell(1, nF);
    shrCleanStack = cell(1, nF);
    shrDbStack    = cell(1, nF);

    for f = 1:nF
        [U, V] = pivcore.data.pickAnyVel(dataFull, f);
        uStack{f}   = U;
        vStack{f}   = -V; % Positif ke atas
        velStack{f} = hypot(U, V);
        Zraw = pivcore.data.computeShearRate(dataFull, f, 'mode', 'engineering');
        Zcln = imgaussfilt(medfilt2(Zraw, [3 3], 'symmetric'), 1.8);
        Zdb  = Zcln;
        Zdb(abs(Zdb) < opt.ShearDeadband) = 0;
        shrCleanStack{f} = Zcln;
        shrDbStack{f}    = Zdb;
    end

    % Definisi N garis horizontal dari atas (2.5%) ke bawah (97.5%)
    nLines = opt.NumLines;
    posPct = linspace(2.5, 97.5, nLines)';
    yRow   = yExt(1) + (posPct / 100) * (yExt(2) - yExt(1));
    yAx    = 2 * yMid - yRow;

    lineID     = cell(nLines, 1);
    meanVelHW  = nan(nLines, 1);
    peakPosShr = nan(nLines, 1);
    xPosShr    = nan(nLines, 1);
    peakNegShr = nan(nLines, 1);
    xNegShr    = nan(nLines, 1);
    xVelDrop   = nan(nLines, 1);
    zoneLabel  = cell(nLines, 1);

    kymoVel   = cell(nLines, 1);
    kymoShear = cell(nLines, 1);
    xSample   = [];

    fAct = max(1, round(0.1*nF)) : max(1, round(0.9*nF));

    for k = 1:nLines
        lineID{k} = sprintf('L%02d', k);
        p1 = [xExt(1), yAx(k)];
        p2 = [xExt(2), yAx(k)];
        [Mv, ~, xPts, ~] = i_sampleStackAlongImageLine(x1, y1, velStack, p1, p2, opt.SpacingPx);
        [Ms, ~, ~, ~]    = i_sampleStackAlongImageLine(x1, y1, shrCleanStack, p1, p2, opt.SpacingPx);
        kymoVel{k}   = Mv;
        kymoShear{k} = Ms;
        xSample      = xPts;

        meanV_x = mean(Mv(:, fAct), 2, 'omitnan');
        maxS_x  = prctile(Ms(:, fAct), 90, 2);
        minS_x  = prctile(Ms(:, fAct), 10, 2);

        hwMask = (xPts >= 300) & (xPts <= 900);
        meanVelHW(k) = mean(meanV_x(hwMask), 'omitnan');

        intMask = (xPts >= 550) & (xPts <= 2400);
        sPos = maxS_x; sPos(~intMask) = -Inf;
        [peakPosShr(k), idxP] = max(sPos);
        xPosShr(k) = xPts(idxP);

        detMask = (xPts >= 150) & (xPts <= 2400);
        sNeg = minS_x; sNeg(~detMask) = Inf;
        [peakNegShr(k), idxN] = min(sNeg);
        xNegShr(k) = xPts(idxN);

        if meanVelHW(k) > 0.8
            dCand = find((xPts' > 700) & (meanV_x < 0.45 * meanVelHW(k)), 1, 'first');
            if ~isempty(dCand), xVelDrop(k) = xPts(dCand); end
        end

        % Klasifikasi zona anatomi otomatis
        if meanVelHW(k) < 0.25 && posPct(k) > 78
            zoneLabel{k} = 'Base / Ruler (Stationary)';
        elseif peakNegShr(k) < -0.025 && xNegShr(k) < 1050 && posPct(k) > 68
            zoneLabel{k} = 'Basal Detachment Horizon';
        elseif peakPosShr(k) >= opt.ShearDeadband && xPosShr(k) >= 950 && xPosShr(k) <= 1650
            if peakNegShr(k) < -0.010 && xNegShr(k) > xPosShr(k)
                zoneLabel{k} = 'Upper Sand + Fore-Thrust & Toe Slump';
            else
                zoneLabel{k} = 'Active Fore-Thrust Fault Core';
            end
        elseif posPct(k) < 15
            zoneLabel{k} = 'Top Air / Fault Scarp Crest';
        else
            zoneLabel{k} = 'Sand Pack / Transition';
        end
    end

    % Regresi sudut dip sesar utama dari garis-garis di zona sesar (posPct 17%..70%)
    validFault = (posPct >= 16) & (posPct <= 70) & (peakPosShr >= 0.005) & (xPosShr >= 950) & (xPosShr <= 1600);
    if nnz(validFault) >= 2
        pFit = polyfit(yAx(validFault), xPosShr(validFault), 1); % dX / dY
        faultDipDeg = atand(1 / abs(pFit(1)));
    else
        faultDipDeg = NaN;
    end

    % Deteksi kedalaman Basal Detachment
    [~, idxDet] = min(peakNegShr);
    detachmentY_px = yAx(idxDet);
    detachmentX_px = [200, xVelDrop(idxDet)];

    T_lines = table((1:nLines)', lineID, posPct, yAx, yRow, meanVelHW, ...
        xPosShr, peakPosShr, xNegShr, peakNegShr, xVelDrop, zoneLabel, ...
        'VariableNames', {'Line_Index', 'Line_ID', 'Pos_Pct_From_Top', 'Y_AxMain_px', 'Y_GridRow_px', ...
        'Mean_Vel_HW', 'X_ForeThrust_px', 'Peak_Pos_Shear', 'X_NegShear_px', 'Peak_Neg_Shear', 'X_VelDrop_px', 'Detected_Zone'});

    disp(T_lines);
    fprintf('📐 Estimasi Sudut Kemiringan Sesar Utama (Dip) : %.1f deg\n', faultDipDeg);
    fprintf('📐 Kedalaman Bidang Detachment Basal           : Y_Ax ≈ %.1f px (Garis %s)\n', detachmentY_px, lineID{idxDet});

    outCsv = fullfile(outDir, sprintf('%s_20Lines_Spatiotemporal_Detection.csv', expName));
    writetable(T_lines, outCsv);

    outMat = fullfile(outDir, sprintf('%s_20Lines_Kymograph_Matrices.mat', expName));
    save(outMat, 'T_lines', 'kymoVel', 'kymoShear', 'xSample', 'yAx', 'yRow', 'posPct', 'faultDipDeg', 'detachmentY_px');

    figFiles = {};
    if opt.RenderFigures
        refFrame = max(1, round(nF / 2));
        bgRef  = pivcore.data.bgAt(dataFull, refFrame);
        rgbRef = pivcore.util.grayCLAHE(bgRef, true, true);
        [Uref, Vref] = pivcore.data.pickAnyVel(dataFull, refFrame);
        Zref = shrDbStack{refFrame};

        fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2300 950]);
        try, theme(fig, 'light'); catch, end
        ax = axes('Parent', fig, 'Position', [0.05 0.08 0.88 0.84]);
        hold(ax, 'on');
        imagesc(ax, xExt, [yExt(2) yExt(1)], Zref);
        colormap(ax, jet(256)); clim(ax, [-0.02 0.02]);
        image(ax, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgbRef, 'AlphaData', 0.34);
        pivcore.util.drawGlyphs(ax, x1, yF, Uref, -Vref, 12, 1.1, [1 1 1]);
        for k = 1:nLines
            plot(ax, xExt, [yAx(k) yAx(k)], '--', 'Color', [0.15 0.15 0.15 0.65], 'LineWidth', 1.1);
            if validFault(k)
                plot(ax, xPosShr(k), yAx(k), 'o', 'MarkerSize', 9, 'MarkerFaceColor', 'y', 'MarkerEdgeColor', 'k', 'LineWidth', 1.6);
            end
        end
        if any(validFault)
            plot(ax, xPosShr(validFault), yAx(validFault), '-y', 'LineWidth', 2.4);
        end
        set(ax, 'YDir', 'normal'); axis(ax, 'image'); xlim(ax, xExt); ylim(ax, yExt);
        cb = colorbar(ax, 'eastoutside'); cb.Label.String = 'Cleaned \gamma_{xy} [\pm0.02]'; cb.Color = 'k';
        title(ax, sprintf('%s (Frame %d/%d) — Spatiotemporal Kymograph Fault Detection (Dip \\approx %.1f^\\circ)', ...
            strrep(expName, '_', '\_'), refFrame, nF, faultDipDeg), 'FontWeight', 'bold', 'FontSize', 13);
        xlabel(ax, 'X (px)', 'FontWeight', 'bold'); ylabel(ax, 'Y (px)', 'FontWeight', 'bold');
        outFig = fullfile(outDir, sprintf('%s_Kymo_Fault_Detection_Map.jpg', expName));
        exportgraphics(fig, outFig, 'Resolution', 150, 'BackgroundColor', 'white');
        close(fig);
        figFiles{end+1} = outFig;
    end

    report = struct('lineTable', T_lines, 'faultDipDeg', faultDipDeg, ...
        'detachmentY_px', detachmentY_px, 'detachmentX_px', detachmentX_px, ...
        'csvFile', outCsv, 'matFile', outMat, 'figFiles', {figFiles});
end

function [M, posPx, xPts, yPts] = i_sampleStackAlongImageLine(x1, y1, stackCell, p1, p2, spacing)
    nF = numel(stackCell);
    L = hypot(p2(1) - p1(1), p2(2) - p1(2));
    nPts = max(2, floor(L / spacing) + 1);
    xPts = linspace(p1(1), p2(1), nPts);
    yPts = linspace(p1(2), p2(2), nPts);
    posPx = hypot(xPts - p1(1), yPts - p1(2));

    xv = x1(1, :);
    yv = y1(:, 1);
    yMid = (max(yv) + min(yv)) / 2;
    ys_flipped = 2 * yMid - yPts;

    ci = i_nearestIdx(xv, xPts);
    ri = i_nearestIdx(yv, ys_flipped);

    M = nan(nPts, nF);
    for f = 1:nF
        F = stackCell{f};
        if isempty(F), continue; end
        for i = 1:nPts
            M(i, f) = i_mean3x3(F, ci(i), ri(i));
        end
    end
end

function idx = i_nearestIdx(vec, q)
    vec = vec(:);
    idx = zeros(1, numel(q));
    for i = 1:numel(q)
        [~, idx(i)] = min(abs(vec - q(i)));
    end
end

function m = i_mean3x3(F, ci, ri)
    [nR, nC] = size(F);
    r1 = max(1, ri - 1); r2 = min(nR, ri + 1);
    c1 = max(1, ci - 1); c2 = min(nC, ci + 1);
    sub = F(r1:r2, c1:c2);
    sub = sub(isfinite(sub));
    if isempty(sub), m = NaN; else, m = mean(sub); end
end
