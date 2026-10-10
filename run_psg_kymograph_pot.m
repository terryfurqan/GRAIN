function out = run_psg_kymograph_pot(rawMatFile, pivMatFile)
% RUN_PSG_KYMOGRAPH_POT  Analisis PSG (Kymograph axPSG + Time-Series axPOT)
% pada Bagian Tengah (y = 50%) dan Garis PSG Existing (y ≈ 70%) untuk:
%   1. Velocity Magnitude |V| (px/frame)
%   2. Cleaned Symmetric Shear Strain \gamma_xy (Filter Level 2: Med 3x3 + Gauss \sigma=1.8)
%
% Menjalankan:
%   A. Ekstraksi QPIV Thin-Strip langsung dari TKS-5_cm-1.mat pada Bagian Tengah (pos = 50%)
%      sesuai arsitektur GRAIN0.m + pivcore.pot.step1Collect.collectAlongLine.
%   B. Scanning PSG + POT penuh dari kontainer PIV 3-Pass (TKS-5_cm-1-OVL-S0-111-3p16px.mat)
%      pada Garis Tengah Horizontal (y = 50%) dan Garis PSG Existing (p1=[11,671]->p2=[2991,653]).

    if nargin < 1 || isempty(rawMatFile)
        rawMatFile = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm/TKS-5_cm-1.mat';
    end
    if nargin < 2 || isempty(pivMatFile)
        pivMatFile = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm/TKS_5 Compare/TKS-5_cm-1-OVL-S0-111-3p16px.mat';
    end

    % Bootstrap GRAIN
    here = fileparts(mfilename('fullpath'));
    cd(here);
    grain_setup();

    [rawDirRoot, expName, ~] = fileparts(rawMatFile);
    compareRoot = fullfile(rawDirRoot, 'TKS_5 Compare');
    if ~isfolder(compareRoot), compareRoot = rawDirRoot; end
    outDir = fullfile(compareRoot, sprintf('%s_PSG_Kymograph_POT', expName));
    if ~isfolder(outDir), mkdir(outDir); end

    fprintf('======================================================================\n');
    fprintf('📈 GRAIN PSG (KYMOGRAPH axPSG) & TIME-SERIES (axPOT) — %s\n', expName);
    fprintf('======================================================================\n');
    fprintf('📦 Sumber RAW MAT : %s\n', rawMatFile);
    fprintf('📦 Sumber PIV MAT : %s\n', pivMatFile);
    fprintf('📁 Folder Output  : %s\n', outDir);
    fprintf('======================================================================\n');

    % =====================================================================
    % BAGIAN 1: JALANKAN QPIV THIN-STRIP (GRAIN0.m) PADA BAGIAN TENGAH (50%)
    %           LANGSUNG DARI TKS-5_cm-1.mat
    % =====================================================================
    qpivCacheMat = fullfile(outDir, sprintf('%s_QPIV_mid50_cache.mat', expName));
    if ~isfile(qpivCacheMat)
        fprintf('\n[1/5] Menjalankan QPIV Thin-Strip (pos = 50%% Tengah) dari %s...\n', rawMatFile);
        t_qpiv = tic;
        S_raw = load(rawMatFile);
        blobs = S_raw.prep.raw.blobs;
        nImgs = numel(blobs);

        tmpRawDir = fullfile(tempdir, sprintf('grain_qpiv_mid_%s', char(matlab.lang.internal.uuid())));
        mkdir(tmpRawDir);
        cleanupTmp = onCleanup(@() i_cleanDir(tmpRawDir));

        for k = 1:nImgs
            fn = fullfile(tmpRawDir, sprintf('frame_%04d.jpg', k));
            fid = fopen(fn, 'wb');
            fwrite(fid, blobs{k}, 'uint8');
            fclose(fid);
        end
        im1 = imread(fullfile(tmpRawDir, 'frame_0001.jpg'));
        H_img = size(im1, 1);
        W_img = size(im1, 2);

        % Parameter QPIV bagian tengah (pos = 50%, orient = horizontal, 64->32->16 px)
        iwStrip = 64;
        stripPad = 10;
        Lwidth = iwStrip + ceil(iwStrip/2) + 2*stripPad; % 116 px
        rc = 1 + 0.50 * (H_img - 1);
        y0 = max(1, round(rc - Lwidth/2));
        hSpan = min(H_img - y0, Lwidth - 1);
        roiStrip = [1, y0, W_img - 1, hSpan];

        fprintf('      Citra %dx%d px | Strip Tengah ROI = [x=%d, y=%d, w=%d, h=%d]\n', ...
            W_img, H_img, roiStrip(1), roiStrip(2), roiStrip(3), roiStrip(4));

        resQpiv = PIVlab_automasi(tmpRawDir, ...
            'Suffix', '*.jpg', ...
            'Sequencing', 'consecutive', ...
            'Skip', 0, ...
            'NumWorkers', 8, ...
            'IntAreas', [64 32 16 16], ...
            'NumPasses', 3, ...
            'ROI', roiStrip, ...
            'PreprocROI', roiStrip, ...
            'OutputFolder', outDir, ...
            'OutputName', sprintf('%s_QPIV_mid50_cache', expName));
        qpivCacheMat = resQpiv.output_file;
        save(qpivCacheMat, 'roiStrip', 'H_img', 'W_img', '-append');
        fprintf('      QPIV Thin-Strip Bagian Tengah selesai dalam %.2f s.\n', toc(t_qpiv));
    else
        fprintf('\n[1/5] Memuat cache QPIV Thin-Strip Bagian Tengah: %s\n', qpivCacheMat);
    end

    % Muat hasil QPIV Thin-Strip Bagian Tengah
    S_qpiv = load(qpivCacheMat);
    dataQpiv = pivcore.data.buildDataset(S_qpiv);
    nF_qpiv = dataQpiv.nFrames;
    xQ = pivcore.data.safeFrame(dataQpiv.x, 1);
    yQ = pivcore.data.safeFrame(dataQpiv.y, 1);
    yMidQ = (max(yQ(:)) + min(yQ(:))) / 2;
    p1_qpiv = [min(xQ(:)), yMidQ];
    p2_qpiv = [max(xQ(:)), yMidQ];
    spacingPx = 16;

    % Scan |V| dan Cleaned Shear Strain pada QPIV Thin-Strip
    [M_vel_qpiv, ~, posPx_qpiv, xPts_qpiv]     = i_scanLineScalar(dataQpiv, p1_qpiv, p2_qpiv, spacingPx, 'vel');
    [M_shr_qpiv, M_shr_db_qpiv, ~, ~]          = i_scanLineScalar(dataQpiv, p1_qpiv, p2_qpiv, spacingPx, 'shear_clean');
    peak_vel_qpiv = max(M_vel_qpiv, [], 1, 'omitnan');
    peak_shr_qpiv = max(abs(M_shr_qpiv), [], 1, 'omitnan');
    ex_qpiv = pivprepFrameExclusion(peak_vel_qpiv, nan(1, nF_qpiv), struct('useMotion', true, 'useTime', false));

    % =====================================================================
    % BAGIAN 2: MUAT FULL-FRAME PIV (TKS-5_cm-1-OVL-S0-111-3p16px.mat)
    %           DAN SCAN PADA:
    %             1) Garis Tengah Horizontal (y = 50%)
    %             2) Garis PSG Existing (y ≈ 70%: p1=[11,671.12] -> p2=[2991,652.96])
    % =====================================================================
    fprintf('\n[2/5] Memuat Full-Frame PIV (%s)...\n', pivMatFile);
    t_load = tic;
    S_piv = load(pivMatFile);
    dataFull = pivcore.data.buildDataset(S_piv);
    nF = dataFull.nFrames;
    x1 = pivcore.data.safeFrame(dataFull.x, 1);
    y1 = pivcore.data.safeFrame(dataFull.y, 1);
    xExt = [min(x1(:)), max(x1(:))];
    yExt = [min(y1(:)), max(y1(:))];
    yMid = (yExt(1) + yExt(2)) / 2;

    totalStrainPct = -2.9377;
    if isfield(S_piv, 'experiment_geometry') && isfield(S_piv.experiment_geometry, 'strain_cumm_pct')
        totalStrainPct = S_piv.experiment_geometry.strain_cumm_pct;
    end
    strainAxisPct = linspace(0, abs(totalStrainPct), nF);

    fprintf('      Dataset termuat (%d frame pairs, grid %dx%d, X=[%.0f..%.0f], Y=[%.0f..%.0f]) dalam %.2f s.\n', ...
        nF, size(x1,1), size(x1,2), xExt(1), xExt(2), yExt(1), yExt(2), toc(t_load));

    % Definisi 2 Garis PSG (dalam koordinat axMain GRAIN3 seperti step1Collect.m):
    % Garis 1: Bagian Tengah Horizontal (y = 50% -> y = yMid)
    p1_mid50_img = [xExt(1), yMid];
    p2_mid50_img = [xExt(2), yMid];

    % Garis 2: Garis PSG Existing TKS-5_cm-1 (p1=[11, 671.12], p2=[2991, 652.96])
    p1_psg70_img = [11, 671.1236];
    p2_psg70_img = [2991, 652.9663];

    fprintf('\n[3/5] Men-scan Velocity Magnitude (|V|) & Cleaned Shear Strain (gamma_xy) sepanjang garis...\n');
    t_scan = tic;
    % Precompute seluruh 110 frame untuk |V| dan Cleaned Shear Strain (Level 2: Med 3x3 + Gauss sigma=1.8)
    velStack      = cell(1, nF);
    shrRawStack   = cell(1, nF);
    shrCleanStack = cell(1, nF);
    shrDbStack    = cell(1, nF);

    for f = 1:nF
        Vmag = pivcore.data.safeFrame(dataFull.velocity_magnitude, f);
        if isempty(Vmag)
            [U, V] = pivcore.data.pickAnyVel(dataFull, f);
            Vmag = hypot(U, V);
        end
        velStack{f} = Vmag;

        Zraw = pivcore.data.computeShearRate(dataFull, f, 'mode', 'engineering');
        Zcln = medfilt2(Zraw, [3 3], 'symmetric');
        Zcln = imgaussfilt(Zcln, 1.8);
        Zdb  = Zcln;
        Zdb(abs(Zdb) < 0.0035) = 0;

        shrRawStack{f}   = Zraw;
        shrCleanStack{f} = Zcln;
        shrDbStack{f}    = Zdb;
    end

    % Sampling sepanjang Garis Tengah Horizontal (y = 50%)
    [M_vel_mid50, posPx_mid50, x_mid50, y_mid50] = i_sampleStackAlongImageLine(x1, y1, velStack, p1_mid50_img, p2_mid50_img, spacingPx);
    [M_shr_mid50, ~, ~, ~]                       = i_sampleStackAlongImageLine(x1, y1, shrCleanStack, p1_mid50_img, p2_mid50_img, spacingPx);
    [M_shrDb_mid50, ~, ~, ~]                     = i_sampleStackAlongImageLine(x1, y1, shrDbStack, p1_mid50_img, p2_mid50_img, spacingPx);

    % Sampling sepanjang Garis PSG Existing (y ≈ 70%: [11, 671.12] -> [2991, 652.96])
    [M_vel_psg70, posPx_psg70, x_psg70, y_psg70] = i_sampleStackAlongImageLine(x1, y1, velStack, p1_psg70_img, p2_psg70_img, spacingPx);
    [M_shr_psg70, ~, ~, ~]                       = i_sampleStackAlongImageLine(x1, y1, shrCleanStack, p1_psg70_img, p2_psg70_img, spacingPx);
    [M_shrDb_psg70, ~, ~, ~]                     = i_sampleStackAlongImageLine(x1, y1, shrDbStack, p1_psg70_img, p2_psg70_img, spacingPx);

    % Hitung envelope Peak / Indenter & statistik HW vs FW
    peak_vel_mid50 = max(M_vel_mid50, [], 1, 'omitnan');
    peak_shr_mid50 = max(abs(M_shr_mid50), [], 1, 'omitnan');
    peak_vel_psg70 = max(M_vel_psg70, [], 1, 'omitnan');
    peak_shr_psg70 = max(abs(M_shr_psg70), [], 1, 'omitnan');

    fprintf('      Scanning selesai dalam %.2f s (%d titik sampel per garis x %d frame).\n', ...
        toc(t_scan), size(M_vel_mid50, 1), nF);

    % Cari lokasi X sesar utama pada Bagian Tengah (y = 50%) dan PSG (y ≈ 70%)
    % Batasi pencarian di area interior (400 <= X <= 2600 px) agar tidak terkena efek tepi indenter
    interior_mid50 = (x_mid50 >= 400) & (x_mid50 <= 2600);
    meanAbsShr_mid50 = mean(abs(M_shr_mid50(:, 15:min(60,nF))), 2, 'omitnan');
    meanAbsShr_mid50(~interior_mid50) = -Inf;
    [~, idxFault_mid50] = max(meanAbsShr_mid50);
    xFault_mid50 = x_mid50(idxFault_mid50);

    interior_psg70 = (x_psg70 >= 400) & (x_psg70 <= 2600);
    meanAbsShr_psg70 = mean(abs(M_shr_psg70(:, 15:min(60,nF))), 2, 'omitnan');
    meanAbsShr_psg70(~interior_psg70) = -Inf;
    [~, idxFault_psg70] = max(meanAbsShr_psg70);
    xFault_psg70 = x_psg70(idxFault_psg70);

    fprintf('      📍 Lokalisasi Sesar Utama pada Garis Tengah (y=50%%) : X ≈ %.0f px (posPx = %.0f px)\n', ...
        xFault_mid50, posPx_mid50(idxFault_mid50));
    fprintf('      📍 Lokalisasi Sesar Utama pada Garis PSG (y≈70%%)    : X ≈ %.0f px (posPx = %.0f px)\n', ...
        xFault_psg70, posPx_psg70(idxFault_psg70));

    % =====================================================================
    % BAGIAN 3: RENDER DASHBOARD 1 — FOKUS BAGIAN TENGAH (y = 50%)
    %           (|V| dan Cleaned Shear Strain \gamma_xy Berdampingan)
    % =====================================================================
    fprintf('\n[4/5] Merender Dashboard 1 (Bagian Tengah y=50%%) & Dashboard 2 (Perbandingan y=50%% vs y=70%%)...\n');
    refFrame = 35;
    bg35 = pivcore.data.bgAt(dataFull, refFrame);
    rgb35 = pivcore.util.grayCLAHE(bg35, true, true);
    [U35, V35] = pivcore.data.pickAnyVel(dataFull, refFrame);
    yF = (yExt(2) + yExt(1)) - y1;
    Z35_clean = shrDbStack{refFrame};
    shearLim = 0.02;
    velLim = [0, prctile(M_vel_mid50(:), 99)];
    expLabel = strrep(expName, '_', '\_');

    fig1 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2400 1650]);
    i_forceLightFig(fig1);

    % --- Panel Atas: Map View Frame 35 + Garis Scanline Bagian Tengah (y = 50%) & PSG (y ≈ 70%) ---
    axMap = axes('Parent', fig1, 'Position', [0.04 0.72 0.91 0.24]);
    hold(axMap, 'on');
    imagesc(axMap, xExt, [yExt(2) yExt(1)], Z35_clean);
    colormap(axMap, jet(256));
    clim(axMap, [-shearLim, shearLim]);
    image(axMap, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgb35, 'AlphaData', 0.32);
    pivcore.util.drawGlyphs(axMap, x1, yF, U35, -V35, 12, 1.1, [1 1 1]);

    % Gambar Garis Tengah (y = 50%) dan Garis PSG (y ≈ 70%) sesuai konvensi axMain GRAIN3
    plot(axMap, [p1_mid50_img(1) p2_mid50_img(1)], [p1_mid50_img(2) p2_mid50_img(2)], ...
        '-', 'Color', [1.0 0.90 0.0], 'LineWidth', 3.5);
    plot(axMap, [p1_mid50_img(1) p2_mid50_img(1)], [p1_mid50_img(2) p2_mid50_img(2)], ...
        '--', 'Color', [0.1 0.1 0.1], 'LineWidth', 1.4);
    plot(axMap, xFault_mid50, p1_mid50_img(2), 'o', 'MarkerSize', 13, ...
        'MarkerFaceColor', [1 0.10 0.10], 'MarkerEdgeColor', 'w', 'LineWidth', 2.2);

    plot(axMap, [p1_psg70_img(1) p2_psg70_img(1)], [p1_psg70_img(2) p2_psg70_img(2)], ...
        '--', 'Color', [1.0 0.45 0.0], 'LineWidth', 2.5);
    plot(axMap, xFault_psg70, y_psg70(idxFault_psg70), 's', 'MarkerSize', 12, ...
        'MarkerFaceColor', [1.0 0.45 0.0], 'MarkerEdgeColor', 'w', 'LineWidth', 2.0);

    text(axMap, xExt(1)+30, p1_mid50_img(2)-36, ...
        sprintf('SCANLINE TENGAH (y = 50%% = %.0f px) — Sesar Utama di X ≈ %.0f px', p1_mid50_img(2), xFault_mid50), ...
        'Color', [1 0.95 0], 'BackgroundColor', [0 0 0 0.78], 'FontWeight', 'bold', 'FontSize', 11);
    text(axMap, xExt(1)+30, p1_psg70_img(2)+36, ...
        sprintf('GARIS PSG EXISTING (y ≈ 70%%: [11, 671] -> [2991, 653]) — Sesar Utama di X ≈ %.0f px', xFault_psg70), ...
        'Color', [1 0.70 0.25], 'BackgroundColor', [0 0 0 0.78], 'FontWeight', 'bold', 'FontSize', 10.5);

    set(axMap, 'YDir', 'normal');
    axis(axMap, 'image'); xlim(axMap, xExt); ylim(axMap, yExt);
    xlabel(axMap, 'Posisi X sepanjang Sandbox (px)  [Kiri: Indenter / Hanging Wall  \rightarrow  Kanan: Foreland / Footwall]', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(axMap, 'Posisi Y (px)', 'FontWeight', 'bold', 'FontSize', 11);
    title(axMap, sprintf('axMain — %s (Frame %d/%d, Shortening %.2f%%) · Posisi Scanline Bagian Tengah (y = 50%%) & PSG (y \\approx 70%%)', ...
        expLabel, refFrame, nF, -strainAxisPct(refFrame)), 'FontSize', 13, 'FontWeight', 'bold');
    cbMap = colorbar(axMap, 'eastoutside');
    cbMap.Label.String = '\gamma_{xy} [\pm0.02]';
    cbMap.Color = 'k';
    i_styleLightAx(axMap);

    % --- Tengah-Kiri: axPSG Kymograph Velocity Magnitude |V| (y = 50%) ---
    axPSG_V = axes('Parent', fig1, 'Position', [0.05 0.39 0.41 0.26]);
    imagesc(axPSG_V, 1:nF, x_mid50, M_vel_mid50);
    colormap(axPSG_V, turbo(256));
    clim(axPSG_V, velLim);
    set(axPSG_V, 'YDir', 'normal');
    hold(axPSG_V, 'on');
    yline(axPSG_V, xFault_mid50, '--w', sprintf('Batas Sesar Utama (X ≈ %.0f px)', xFault_mid50), ...
        'LineWidth', 2.0, 'FontWeight', 'bold', 'FontSize', 10, 'LabelHorizontalAlignment', 'left');
    xline(axPSG_V, refFrame, ':w', sprintf('Frame %d', refFrame), 'LineWidth', 1.6);
    hold(axPSG_V, 'off');
    xlabel(axPSG_V, 'Frame Pair (t = 1 .. 110)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(axPSG_V, 'Posisi X sepanjang Garis Tengah (px)', 'FontWeight', 'bold', 'FontSize', 11);
    title(axPSG_V, 'axPSG (Kymograph 2D) — Velocity Magnitude |V| pada Bagian Tengah (y = 50%)', ...
        'FontSize', 12, 'FontWeight', 'bold');
    cbV = colorbar(axPSG_V, 'eastoutside');
    cbV.Label.String = '|V| (px/frame)';
    cbV.Label.FontWeight = 'bold';
    cbV.Color = 'k';
    i_styleLightAx(axPSG_V);

    % --- Tengah-Kanan: axPSG Kymograph Cleaned Shear Strain \gamma_xy (y = 50%) ---
    axPSG_S = axes('Parent', fig1, 'Position', [0.54 0.39 0.41 0.26]);
    imagesc(axPSG_S, 1:nF, x_mid50, M_shr_mid50);
    colormap(axPSG_S, jet(256));
    clim(axPSG_S, [-shearLim, shearLim]);
    set(axPSG_S, 'YDir', 'normal');
    hold(axPSG_S, 'on');
    yline(axPSG_S, xFault_mid50, '--k', sprintf('Jejak Lokalisasi Sesar (X ≈ %.0f px)', xFault_mid50), ...
        'LineWidth', 1.8, 'FontWeight', 'bold', 'FontSize', 10, 'LabelHorizontalAlignment', 'left');
    xline(axPSG_S, refFrame, ':k', sprintf('Frame %d', refFrame), 'LineWidth', 1.6);
    hold(axPSG_S, 'off');
    xlabel(axPSG_S, 'Frame Pair (t = 1 .. 110)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(axPSG_S, 'Posisi X sepanjang Garis Tengah (px)', 'FontWeight', 'bold', 'FontSize', 11);
    title(axPSG_S, 'axPSG (Kymograph 2D) — Cleaned Shear Strain \gamma_{xy} pada Bagian Tengah (y = 50%)', ...
        'FontSize', 12, 'FontWeight', 'bold');
    cbS = colorbar(axPSG_S, 'eastoutside');
    cbS.Label.String = 'Cleaned \gamma_{xy} [\pm0.02]';
    cbS.Label.FontWeight = 'bold';
    cbS.Color = 'k';
    i_styleLightAx(axPSG_S);

    % --- Bawah-Kiri: axPOT Time-Series Velocity Magnitude |V| (y = 50%) ---
    axPOT_V = axes('Parent', fig1, 'Position', [0.05 0.06 0.41 0.26]);
    hold(axPOT_V, 'on');
    % Indenter mendorong dari KIRI (X < xFault_mid50):
    % Hanging Wall (HW) = 250 < X < (xFault - 60); Footwall (FW) = X > (xFault + 60)
    isHW_mid = (x_mid50 >= 250) & (x_mid50 < (xFault_mid50 - 60));
    isFW_mid = x_mid50 > (xFault_mid50 + 60);
    for r = 1:size(M_vel_mid50, 1)
        if isHW_mid(r)
            plot(axPOT_V, 1:nF, M_vel_mid50(r, :), '-', 'Color', [0.95 0.45 0.45 0.28], 'LineWidth', 0.7);
        elseif isFW_mid(r)
            plot(axPOT_V, 1:nF, M_vel_mid50(r, :), '-', 'Color', [0.40 0.65 0.95 0.28], 'LineWidth', 0.7);
        else
            plot(axPOT_V, 1:nF, M_vel_mid50(r, :), '-', 'Color', [0.65 0.65 0.65 0.30], 'LineWidth', 0.7);
        end
    end
    hwMeanV = mean(M_vel_mid50(isHW_mid, :), 1, 'omitnan');
    fwMeanV = mean(M_vel_mid50(isFW_mid, :), 1, 'omitnan');
    hPeakV = plot(axPOT_V, 1:nF, peak_vel_mid50, '-k', 'LineWidth', 2.4);
    hHW_V  = plot(axPOT_V, 1:nF, hwMeanV, '-', 'Color', [0.85 0.10 0.10], 'LineWidth', 2.2);
    hFW_V  = plot(axPOT_V, 1:nF, fwMeanV, '-', 'Color', [0.05 0.35 0.85], 'LineWidth', 2.2);
    hNet_V = plot(axPOT_V, 1:nF, hwMeanV - fwMeanV, '--', 'Color', [0.05 0.60 0.20], 'LineWidth', 2.0);
    if isfield(ex_qpiv, 'motionMin') && isfinite(ex_qpiv.motionMin) && ex_qpiv.motionMin > 0
        yline(axPOT_V, ex_qpiv.motionMin, ':r', sprintf('Dead Threshold (%.2f)', ex_qpiv.motionMin), ...
            'LineWidth', 1.4, 'FontWeight', 'bold');
    end
    xline(axPOT_V, refFrame, ':k', sprintf('Frame %d', refFrame), 'LineWidth', 1.5);
    grid(axPOT_V, 'on'); xlim(axPOT_V, [1 nF]); ylim(axPOT_V, [0 max(peak_vel_mid50)*1.18]);
    xlabel(axPOT_V, 'Frame Pair (t = 1 .. 110)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(axPOT_V, '|V| (px/frame)', 'FontWeight', 'bold', 'FontSize', 11);
    title(axPOT_V, sprintf('axPOT (Time-Series) — |V| Sepanjang Garis Tengah (y = 50%%, %d titik sampel)', size(M_vel_mid50,1)), ...
        'FontSize', 12, 'FontWeight', 'bold');
    i_styleLightAx(axPOT_V);
    lgV = legend(axPOT_V, [hPeakV, hHW_V, hFW_V, hNet_V], ...
        {'Peak / Indenter Max |V|', 'Mean Hanging Wall (HW, Kiri Sesar)', 'Mean Footwall (FW, Kanan Sesar)', 'Net-Slip Rate \Delta|V| = HW - FW'}, ...
        'Location', 'northeast', 'FontSize', 9.5);
    lgV.Color = [1 1 1]; lgV.TextColor = [0 0 0]; lgV.EdgeColor = [0.7 0.7 0.7];

    % --- Bawah-Kanan: axPOT Time-Series Cleaned Shear Strain \gamma_xy (y = 50%) ---
    axPOT_S = axes('Parent', fig1, 'Position', [0.54 0.06 0.41 0.26]);
    hold(axPOT_S, 'on');
    for r = 1:size(M_shr_mid50, 1)
        plot(axPOT_S, 1:nF, M_shr_mid50(r, :), '-', 'Color', [0.65 0.65 0.68 0.30], 'LineWidth', 0.8);
    end
    faultZoneMask = abs(x_mid50 - xFault_mid50) <= 32;
    faultCurveMean = mean(M_shr_mid50(faultZoneMask, :), 1, 'omitnan');
    faultCurvePeak = max(M_shr_mid50(faultZoneMask, :), [], 1, 'omitnan');
    minShrEnv = min(M_shr_mid50(interior_mid50, :), [], 1, 'omitnan');
    maxShrEnv = max(M_shr_mid50(interior_mid50, :), [], 1, 'omitnan');
    hMaxS   = plot(axPOT_S, 1:nF, maxShrEnv, '-k', 'LineWidth', 2.4);
    hFaultS = plot(axPOT_S, 1:nF, faultCurveMean, '-', 'Color', [0.85 0.10 0.15], 'LineWidth', 2.4);
    hMinS   = plot(axPOT_S, 1:nF, minShrEnv, '--', 'Color', [0.10 0.35 0.85], 'LineWidth', 1.8);
    yline(axPOT_S, 0.0035, ':k', '+Deadband (0.0035)', 'LineWidth', 1.2);
    yline(axPOT_S, -0.0035, ':k', '-Deadband (-0.0035)', 'LineWidth', 1.2);
    xline(axPOT_S, refFrame, ':k', sprintf('Frame %d', refFrame), 'LineWidth', 1.5);
    grid(axPOT_S, 'on'); xlim(axPOT_S, [1 nF]); ylim(axPOT_S, [-0.015, 0.032]);
    xlabel(axPOT_S, 'Frame Pair (t = 1 .. 110)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(axPOT_S, 'Cleaned Shear Strain \gamma_{xy}', 'FontWeight', 'bold', 'FontSize', 11);
    title(axPOT_S, sprintf('axPOT (Time-Series) — Cleaned \\gamma_{xy} Sepanjang Garis Tengah (y = 50%%, Sesar X \\approx %.0f px)', xFault_mid50), ...
        'FontSize', 12, 'FontWeight', 'bold');
    i_styleLightAx(axPOT_S);
    lgS = legend(axPOT_S, [hMaxS, hFaultS, hMinS], ...
        {'Envelope Puncak Sesar (Max \gamma_{xy})', sprintf('Rata-Rata Inti Sesar (X \\approx %.0f \\pm 32 px)', xFault_mid50), 'Envelope Min \gamma_{xy} (Back-Thrust)'}, ...
        'Location', 'northeast', 'FontSize', 9.5);
    lgS.Color = [1 1 1]; lgS.TextColor = [0 0 0]; lgS.EdgeColor = [0.7 0.7 0.7];

    outFig1 = fullfile(outDir, sprintf('%s_PSG_BagianTengah_y50_Dashboard.jpg', expName));
    exportgraphics(fig1, outFig1, 'Resolution', 150, 'BackgroundColor', 'white');
    close(fig1);

    % =====================================================================
    % BAGIAN 4: RENDER DASHBOARD 2 — KOMPARASI BAGIAN TENGAH (y = 50%)
    %           VS GARIS PSG EXISTING (y ≈ 70%: [11,671]->[2991,653])
    % =====================================================================
    fig2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2400 1800]);
    i_forceLightFig(fig2);
    tl2 = tiledlayout(fig2, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl2, sprintf('%s — Komparasi Kymograph (axPSG) & Time-Series (axPOT): Bagian Tengah (y = 50%%) vs Garis PSG Existing (y \\approx 70%%)', expLabel), ...
        'FontSize', 15, 'FontWeight', 'bold', 'Color', 'k');

    % Baris 1: Kymograph |V| (Kiri: y=50%, Kanan: y=70%)
    ax1 = nexttile(tl2, 1);
    imagesc(ax1, 1:nF, x_mid50, M_vel_mid50); colormap(ax1, turbo(256)); clim(ax1, velLim); set(ax1, 'YDir', 'normal');
    hold(ax1, 'on'); yline(ax1, xFault_mid50, '--w', sprintf('Sesar X≈%.0f px', xFault_mid50), 'LineWidth', 1.8); hold(ax1, 'off');
    ylabel(ax1, 'Posisi X (px)', 'FontWeight', 'bold');
    title(ax1, '[1A] Kymograph |V| — BAGIAN TENGAH (y = 50%, y = 461 px)', 'FontWeight', 'bold', 'FontSize', 11.5);
    cb1 = colorbar(ax1); cb1.Label.String = '|V| (px/fr)'; cb1.Color = 'k';
    i_styleLightAx(ax1);

    ax2 = nexttile(tl2, 2);
    imagesc(ax2, 1:nF, x_psg70, M_vel_psg70); colormap(ax2, turbo(256)); clim(ax2, velLim); set(ax2, 'YDir', 'normal');
    hold(ax2, 'on'); yline(ax2, xFault_psg70, '--w', sprintf('Sesar X≈%.0f px', xFault_psg70), 'LineWidth', 1.8); hold(ax2, 'off');
    ylabel(ax2, 'Posisi X (px)', 'FontWeight', 'bold');
    title(ax2, '[1B] Kymograph |V| — GARIS PSG EXISTING (y \approx 70%, [11,671]\rightarrow[2991,653])', 'FontWeight', 'bold', 'FontSize', 11.5);
    cb2 = colorbar(ax2); cb2.Label.String = '|V| (px/fr)'; cb2.Color = 'k';
    i_styleLightAx(ax2);

    % Baris 2: Time-Series POT |V| (Kiri: y=50%, Kanan: y=70%)
    ax3 = nexttile(tl2, 3); hold(ax3, 'on');
    for r = 1:size(M_vel_mid50,1), plot(ax3, 1:nF, M_vel_mid50(r,:), '-', 'Color', [0.65 0.65 0.68 0.28]); end
    plot(ax3, 1:nF, peak_vel_mid50, '-k', 'LineWidth', 2.2);
    plot(ax3, 1:nF, hwMeanV, '-r', 'LineWidth', 2.0);
    plot(ax3, 1:nF, fwMeanV, '-b', 'LineWidth', 2.0);
    grid(ax3, 'on'); xlim(ax3, [1 nF]); ylim(ax3, [0 max(peak_vel_mid50)*1.15]);
    ylabel(ax3, '|V| (px/fr)', 'FontWeight', 'bold');
    title(ax3, '[2A] Time-Series (axPOT) |V| — BAGIAN TENGAH (y = 50%: Hitam=Peak, Merah=HW, Biru=FW)', 'FontWeight', 'bold', 'FontSize', 11.5);
    i_styleLightAx(ax3);

    isHW_70 = (x_psg70 >= 250) & (x_psg70 < (xFault_psg70 - 60));
    isFW_70 = x_psg70 > (xFault_psg70 + 60);
    ax4 = nexttile(tl2, 4); hold(ax4, 'on');
    for r = 1:size(M_vel_psg70,1), plot(ax4, 1:nF, M_vel_psg70(r,:), '-', 'Color', [0.65 0.65 0.68 0.28]); end
    plot(ax4, 1:nF, peak_vel_psg70, '-k', 'LineWidth', 2.2);
    plot(ax4, 1:nF, mean(M_vel_psg70(isHW_70, :), 1, 'omitnan'), '-r', 'LineWidth', 2.0);
    plot(ax4, 1:nF, mean(M_vel_psg70(isFW_70, :), 1, 'omitnan'), '-b', 'LineWidth', 2.0);
    grid(ax4, 'on'); xlim(ax4, [1 nF]); ylim(ax4, [0 max(peak_vel_psg70)*1.15]);
    ylabel(ax4, '|V| (px/fr)', 'FontWeight', 'bold');
    title(ax4, '[2B] Time-Series (axPOT) |V| — GARIS PSG EXISTING (y \approx 70%: Hitam=Peak, Merah=HW, Biru=FW)', 'FontWeight', 'bold', 'FontSize', 11.5);
    i_styleLightAx(ax4);

    % Baris 3: Kymograph Cleaned Shear Strain \gamma_xy (Kiri: y=50%, Kanan: y=70%)
    ax5 = nexttile(tl2, 5);
    imagesc(ax5, 1:nF, x_mid50, M_shr_mid50); colormap(ax5, jet(256)); clim(ax5, [-shearLim shearLim]); set(ax5, 'YDir', 'normal');
    hold(ax5, 'on'); yline(ax5, xFault_mid50, '--k', sprintf('Sesar X≈%.0f px', xFault_mid50), 'LineWidth', 1.8); hold(ax5, 'off');
    ylabel(ax5, 'Posisi X (px)', 'FontWeight', 'bold');
    title(ax5, '[3A] Kymograph Cleaned \gamma_{xy} — BAGIAN TENGAH (y = 50%)', 'FontWeight', 'bold', 'FontSize', 11.5);
    cb5 = colorbar(ax5); cb5.Label.String = '\gamma_{xy}'; cb5.Color = 'k';
    i_styleLightAx(ax5);

    ax6 = nexttile(tl2, 6);
    imagesc(ax6, 1:nF, x_psg70, M_shr_psg70); colormap(ax6, jet(256)); clim(ax6, [-shearLim shearLim]); set(ax6, 'YDir', 'normal');
    hold(ax6, 'on'); yline(ax6, xFault_psg70, '--k', sprintf('Sesar X≈%.0f px', xFault_psg70), 'LineWidth', 1.8); hold(ax6, 'off');
    ylabel(ax6, 'Posisi X (px)', 'FontWeight', 'bold');
    title(ax6, '[3B] Kymograph Cleaned \gamma_{xy} — GARIS PSG EXISTING (y \approx 70%)', 'FontWeight', 'bold', 'FontSize', 11.5);
    cb6 = colorbar(ax6); cb6.Label.String = '\gamma_{xy}'; cb6.Color = 'k';
    i_styleLightAx(ax6);

    % Baris 4: Time-Series POT Cleaned Shear Strain \gamma_xy (Kiri: y=50%, Kanan: y=70%)
    ax7 = nexttile(tl2, 7); hold(ax7, 'on');
    for r = 1:size(M_shr_mid50,1), plot(ax7, 1:nF, M_shr_mid50(r,:), '-', 'Color', [0.65 0.65 0.68 0.28]); end
    plot(ax7, 1:nF, maxShrEnv, '-k', 'LineWidth', 2.0);
    plot(ax7, 1:nF, faultCurveMean, '-r', 'LineWidth', 2.2);
    yline(ax7, -0.0035, ':k'); yline(ax7, 0.0035, ':k');
    grid(ax7, 'on'); xlim(ax7, [1 nF]); ylim(ax7, [-0.015 0.032]);
    xlabel(ax7, 'Frame Pair (t = 1..110)', 'FontWeight', 'bold'); ylabel(ax7, 'Cleaned \gamma_{xy}', 'FontWeight', 'bold');
    title(ax7, sprintf('[4A] Time-Series (axPOT) Cleaned \\gamma_{xy} — BAGIAN TENGAH (Sesar X \\approx %.0f px)', xFault_mid50), 'FontWeight', 'bold', 'FontSize', 11.5);
    i_styleLightAx(ax7);

    faultCurve70 = mean(M_shr_psg70(abs(x_psg70 - xFault_psg70)<=32, :), 1, 'omitnan');
    maxShr70 = max(M_shr_psg70(interior_psg70, :), [], 1, 'omitnan');
    ax8 = nexttile(tl2, 8); hold(ax8, 'on');
    for r = 1:size(M_shr_psg70,1), plot(ax8, 1:nF, M_shr_psg70(r,:), '-', 'Color', [0.65 0.65 0.68 0.28]); end
    plot(ax8, 1:nF, maxShr70, '-k', 'LineWidth', 2.0);
    plot(ax8, 1:nF, faultCurve70, '-r', 'LineWidth', 2.2);
    yline(ax8, -0.0035, ':k'); yline(ax8, 0.0035, ':k');
    grid(ax8, 'on'); xlim(ax8, [1 nF]); ylim(ax8, [-0.015 0.032]);
    xlabel(ax8, 'Frame Pair (t = 1..110)', 'FontWeight', 'bold'); ylabel(ax8, 'Cleaned \gamma_{xy}', 'FontWeight', 'bold');
    title(ax8, sprintf('[4B] Time-Series (axPOT) Cleaned \\gamma_{xy} — GARIS PSG EXISTING (Sesar X \\approx %.0f px)', xFault_psg70), 'FontWeight', 'bold', 'FontSize', 11.5);
    i_styleLightAx(ax8);

    outFig2 = fullfile(outDir, sprintf('%s_PSG_Compare_y50_vs_y70.jpg', expName));
    exportgraphics(fig2, outFig2, 'Resolution', 150, 'BackgroundColor', 'white');
    close(fig2);

    % =====================================================================
    % BAGIAN 5: RENDER DASHBOARD 3 — HASIL MURNI QPIV THIN-STRIP (GRAIN0.m)
    %           PADA BAGIAN TENGAH (pos = 50%) LANGSUNG DARI TKS-5_cm-1.mat
    % =====================================================================
    fig3 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2200 1200]);
    i_forceLightFig(fig3);
    tl3 = tiledlayout(fig3, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl3, sprintf('Modul GRAIN0 (QPIV Thin-Strip Bagian Tengah pos=50%%, ROI Tinggi=%d px) — %s.mat', ...
        size(xQ,1)*8, expLabel), 'FontSize', 14, 'FontWeight', 'bold', 'Color', 'k');

    axQ1 = nexttile(tl3, 1);
    imagesc(axQ1, 1:nF_qpiv, xPts_qpiv, M_vel_qpiv); colormap(axQ1, turbo(256)); clim(axQ1, velLim); set(axQ1, 'YDir', 'normal');
    hold(axQ1, 'on'); yline(axQ1, xFault_mid50, '--w', sprintf('Sesar X≈%.0f px', xFault_mid50), 'LineWidth', 1.8); hold(axQ1, 'off');
    xlabel(axQ1, 'Frame Pair'); ylabel(axQ1, 'Posisi X (px)');
    title(axQ1, 'QPIV Thin-Strip axPSG (Kymograph |V| — Bagian Tengah 50%)', 'FontWeight', 'bold');
    cbQ1 = colorbar(axQ1); cbQ1.Color = 'k';
    i_styleLightAx(axQ1);

    axQ2 = nexttile(tl3, 2);
    imagesc(axQ2, 1:nF_qpiv, xPts_qpiv, M_shr_qpiv); colormap(axQ2, jet(256)); clim(axQ2, [-shearLim shearLim]); set(axQ2, 'YDir', 'normal');
    hold(axQ2, 'on'); yline(axQ2, xFault_mid50, '--k', sprintf('Sesar X≈%.0f px', xFault_mid50), 'LineWidth', 1.8); hold(axQ2, 'off');
    xlabel(axQ2, 'Frame Pair'); ylabel(axQ2, 'Posisi X (px)');
    title(axQ2, 'QPIV Thin-Strip axPSG (Kymograph Cleaned \gamma_{xy} — Bagian Tengah 50%)', 'FontWeight', 'bold');
    cbQ2 = colorbar(axQ2); cbQ2.Color = 'k';
    i_styleLightAx(axQ2);

    axQ3 = nexttile(tl3, 3); hold(axQ3, 'on');
    for r = 1:size(M_vel_qpiv,1), plot(axQ3, 1:nF_qpiv, M_vel_qpiv(r,:), '-', 'Color', [0.65 0.65 0.68 0.30]); end
    plot(axQ3, 1:nF_qpiv, peak_vel_qpiv, '-k', 'LineWidth', 2.2);
    grid(axQ3, 'on'); xlim(axQ3, [1 nF_qpiv]); ylim(axQ3, [0 max(peak_vel_qpiv)*1.15]);
    xlabel(axQ3, 'Frame Pair'); ylabel(axQ3, '|V| (px/frame)');
    title(axQ3, sprintf('QPIV Thin-Strip axPOT (Time-Series |V| — Dead Frames Detected: %d)', nnz(ex_qpiv.ignore)), 'FontWeight', 'bold');
    i_styleLightAx(axQ3);

    interior_qpiv = (xPts_qpiv >= 400) & (xPts_qpiv <= 2600);
    axQ4 = nexttile(tl3, 4); hold(axQ4, 'on');
    for r = 1:size(M_shr_qpiv,1), plot(axQ4, 1:nF_qpiv, M_shr_qpiv(r,:), '-', 'Color', [0.65 0.65 0.68 0.30]); end
    plot(axQ4, 1:nF_qpiv, max(M_shr_qpiv(interior_qpiv, :), [], 1, 'omitnan'), '-k', 'LineWidth', 2.2);
    plot(axQ4, 1:nF_qpiv, mean(M_shr_qpiv(abs(xPts_qpiv - xFault_mid50)<=32, :), 1, 'omitnan'), '-r', 'LineWidth', 2.2);
    yline(axQ4, -0.0035, ':k'); yline(axQ4, 0.0035, ':k');
    grid(axQ4, 'on'); xlim(axQ4, [1 nF_qpiv]); ylim(axQ4, [-0.015 0.032]);
    xlabel(axQ4, 'Frame Pair'); ylabel(axQ4, 'Cleaned \gamma_{xy}');
    title(axQ4, 'QPIV Thin-Strip axPOT (Time-Series Cleaned \gamma_{xy} — Bagian Tengah 50%)', 'FontWeight', 'bold');
    i_styleLightAx(axQ4);

    outFig3 = fullfile(outDir, sprintf('%s_GRAIN0_QPIV_ThinStrip_Mid50.jpg', expName));
    exportgraphics(fig3, outFig3, 'Resolution', 150, 'BackgroundColor', 'white');
    close(fig3);

    % =====================================================================
    % SIMPAN MAT & CSV TIME-SERIES SUMMARY
    % =====================================================================
    fprintf('\n[5/5] Menyimpan matriks PSG/POT (.mat & .csv)...\n');
    outDataMat = fullfile(outDir, sprintf('%s_PSG_POT_matrices.mat', expName));
    save(outDataMat, ...
        'M_vel_mid50', 'M_shr_mid50', 'M_shrDb_mid50', 'posPx_mid50', 'x_mid50', 'y_mid50', ...
        'M_vel_psg70', 'M_shr_psg70', 'M_shrDb_psg70', 'posPx_psg70', 'x_psg70', 'y_psg70', ...
        'M_vel_qpiv',  'M_shr_qpiv',  'posPx_qpiv',    'xPts_qpiv', ...
        'peak_vel_mid50', 'peak_shr_mid50', 'peak_vel_psg70', 'peak_shr_psg70', ...
        'xFault_mid50', 'xFault_psg70', 'strainAxisPct');

    % Simpan CSV ringkasan per frame (1..110)
    T_summary = table((1:nF)', strainAxisPct(:), ...
        peak_vel_mid50(:), hwMeanV(:), fwMeanV(:), (hwMeanV(:) - fwMeanV(:)), ...
        faultCurveMean(:), minShrEnv(:), maxShrEnv(:), ...
        peak_vel_psg70(:), min(M_shr_psg70, [], 1, 'omitnan')', ...
        'VariableNames', {'Frame', 'Shortening_Pct', ...
        'Mid50_Peak_Vel', 'Mid50_HW_Mean_Vel', 'Mid50_FW_Mean_Vel', 'Mid50_NetSlip_Vel', ...
        'Mid50_FaultCore_Shear', 'Mid50_Min_Shear', 'Mid50_Max_Shear', ...
        'PSG70_Peak_Vel', 'PSG70_Min_Shear'});
    outCsv = fullfile(outDir, sprintf('%s_PSG_POT_TimeSeries_Summary.csv', expName));
    writetable(T_summary, outCsv);

    out = struct('outDir', outDir, 'fig1', outFig1, 'fig2', outFig2, 'fig3', outFig3, ...
        'matFile', outDataMat, 'csvFile', outCsv, ...
        'xFault_mid50', xFault_mid50, 'xFault_psg70', xFault_psg70);

    fprintf('\n======================================================================\n');
    fprintf('✅ ANALISIS PSG (KYMOGRAPH) & POT (TIME-SERIES) SELESAI!\n');
    fprintf('🖼️  Dashboard 1 (Bagian Tengah y=50%%) : %s\n', outFig1);
    fprintf('🖼️  Dashboard 2 (y=50%% vs y=70%%)      : %s\n', outFig2);
    fprintf('🖼️  Dashboard 3 (GRAIN0 Thin-Strip)   : %s\n', outFig3);
    fprintf('📊 Data MAT & CSV                     : %s\n', outCsv);
    fprintf('======================================================================\n');
end

function [M, M_db, posPx, xPts] = i_scanLineScalar(data, p1, p2, spacing, modeStr)
    nF = data.nFrames;
    x1 = pivcore.data.safeFrame(data.x, 1);
    y1 = pivcore.data.safeFrame(data.y, 1);
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
    M_db = nan(nPts, nF);
    for f = 1:nF
        if strcmpi(modeStr, 'vel')
            F = pivcore.data.safeFrame(data.velocity_magnitude, f);
            if isempty(F)
                [U, V] = pivcore.data.pickAnyVel(data, f);
                F = hypot(U, V);
            end
            Fdb = F;
        else
            Zraw = pivcore.data.computeShearRate(data, f, 'mode', 'engineering');
            F = medfilt2(Zraw, [3 3], 'symmetric');
            F = imgaussfilt(F, 1.8);
            Fdb = F;
            Fdb(abs(Fdb) < 0.0035) = 0;
        end
        for i = 1:nPts
            M(i, f) = i_mean3x3(F, ci(i), ri(i));
            M_db(i, f) = i_mean3x3(Fdb, ci(i), ri(i));
        end
    end
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

function i_forceLightFig(fig)
    try, theme(fig, 'light'); catch, end
    try, fig.Theme = 'light'; catch, end
    try, fig.Color = [1 1 1]; catch, end
end

function i_styleLightAx(ax)
    try
        ax.Color = [1 1 1];
        ax.XColor = [0.1 0.1 0.1];
        ax.YColor = [0.1 0.1 0.1];
        ax.GridColor = [0.75 0.75 0.75];
        ax.GridAlpha = 0.45;
        ax.Title.Color = [0.05 0.05 0.05];
        ax.XLabel.Color = [0.1 0.1 0.1];
        ax.YLabel.Color = [0.1 0.1 0.1];
        box(ax, 'on');
    catch
    end
end

function i_cleanDir(d)
    if isfolder(d)
        try, rmdir(d, 's'); catch, end
    end
end
