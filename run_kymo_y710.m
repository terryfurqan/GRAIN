function out = run_kymo_y710(pivMatFile)
% RUN_KYMO_Y710  Ekstraksi & Visualisasi Kymograph (axPSG) + Time-Series (axPOT)
% pada garis horizontal Y = 710 px (Garis L05, 22.5% dari atas) untuk TKS-5_cm-1.
%
% Menghasilkan:
%   1. Dashboard Standar GRAIN (axMain + axPSG [Frame x Posisi] + axPOT [Time-Series])
%      untuk Velocity Magnitude |V| dan Cleaned Shear Strain \gamma_xy pada Y = 710 px.
%   2. Kymograph Spasial Sejajar Citra (axMain di atas + Kymograph |V| & \gamma_xy di bawah
%      dengan sumbu-X = Posisi X [9..2993 px] sejajar langsung dengan penampang sandbox).
%   3. Tabel CSV & MAT matriks kymograph Y = 710 px.

    if nargin < 1 || isempty(pivMatFile)
        pivMatFile = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm/TKS_5 Compare/TKS-5_cm-1-OVL-S0-111-3p16px.mat';
    end

    here = fileparts(mfilename('fullpath'));
    cd(here);
    grain_setup();

    outDir = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm/TKS_5 Compare/TKS-5_cm-1_PSG_Kymograph_POT';
    if ~isfolder(outDir), mkdir(outDir); end

    fprintf('======================================================================\n');
    fprintf('📈 KYMOGRAPH (axPSG) & TIME-SERIES (axPOT) PADA GARIS Y = 710 px (L05)\n');
    fprintf('======================================================================\n');

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

    % Garis Horizontal Y = 710 px (L05, 22.5% dari atas)
    yTargetAx = 710.0;
    yTargetRow = 2 * yMid - yTargetAx; % 922 - 710 = 212 px dari atas
    p1_710 = [xExt(1), yTargetAx];
    p2_710 = [xExt(2), yTargetAx];
    spacingPx = 16;

    % Precompute seluruh 110 frame untuk |V| dan Cleaned Shear Strain (Level 2: Med 3x3 + Gauss sigma=1.8)
    velStack      = cell(1, nF);
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

        shrCleanStack{f} = Zcln;
        shrDbStack{f}    = Zdb;
    end

    % Sampling sepanjang Garis Y = 710 px
    [M_vel_710, posPx_710, x_710, y_710] = i_sampleStackAlongImageLine(x1, y1, velStack, p1_710, p2_710, spacingPx);
    [M_shr_710, ~, ~, ~]                 = i_sampleStackAlongImageLine(x1, y1, shrCleanStack, p1_710, p2_710, spacingPx);
    [M_shrDb_710, ~, ~, ~]               = i_sampleStackAlongImageLine(x1, y1, shrDbStack, p1_710, p2_710, spacingPx);

    peak_vel_710 = max(M_vel_710, [], 1, 'omitnan');
    peak_shr_710 = max(abs(M_shr_710), [], 1, 'omitnan');

    % Cari lokasi X sesar utama pada garis Y = 710 px (area interior 950 <= X <= 1650 px)
    interior_710 = (x_710 >= 950) & (x_710 <= 1650);
    meanAbsShr_710 = mean(abs(M_shr_710(:, 20:min(70,nF))), 2, 'omitnan');
    meanAbsShr_710(~interior_710) = -Inf;
    [~, idxFault_710] = max(meanAbsShr_710);
    xFault_710 = x_710(idxFault_710);

    % Lacak posisi puncak sesar per-frame di sekitar zona sesar (950..1650 px)
    xFaultTrack = nan(1, nF);
    shrFaultTrack = nan(1, nF);
    for f = 1:nF
        col = M_shr_710(:, f);
        colMasked = col;
        colMasked(~interior_710) = -Inf;
        [mxVal, idxF] = max(colMasked);
        if isfinite(mxVal) && mxVal >= 0.0035
            xFaultTrack(f) = x_710(idxF);
            shrFaultTrack(f) = mxVal;
        end
    end

    fprintf('📍 Garis Y = %.1f px (L05, Grid Row Y = %.1f px dari atas)\n', yTargetAx, yTargetRow);
    fprintf('📍 Posisi Sesar Utama Rata-Rata pada Y = 710 px : X ≈ %.0f px\n', xFault_710);
    fprintf('📍 Puncak |V| Maksimum sepanjang Y = 710 px     : %.3f px/frame\n', max(peak_vel_710));
    fprintf('📍 Puncak Shear Strain Maksimum pada Y = 710 px : %.4f\n', max(M_shr_710(interior_710, :), [], 'all', 'omitnan'));

    % =====================================================================
    % DASHBOARD 1: FORMAT STANDAR GRAIN (axMain + axPSG + axPOT) PADA Y = 710 px
    % =====================================================================
    refFrame = 35;
    bg35 = pivcore.data.bgAt(dataFull, refFrame);
    rgb35 = pivcore.util.grayCLAHE(bg35, true, true);
    [U35, V35] = pivcore.data.pickAnyVel(dataFull, refFrame);
    yF = (yExt(2) + yExt(1)) - y1;
    Z35_clean = shrDbStack{refFrame};
    shearLim = 0.02;
    velLim = [0, max(1.8, prctile(M_vel_710(:), 99))];

    fig1 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2400 1650]);
    i_forceLightFig(fig1);

    % --- Panel Atas: axMain Frame 35 + Garis Y = 710 px (L05) ---
    axMap = axes('Parent', fig1, 'Position', [0.04 0.72 0.91 0.24]);
    hold(axMap, 'on');
    imagesc(axMap, xExt, [yExt(2) yExt(1)], Z35_clean);
    colormap(axMap, jet(256));
    clim(axMap, [-shearLim, shearLim]);
    image(axMap, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgb35, 'AlphaData', 0.32);
    pivcore.util.drawGlyphs(axMap, x1, yF, U35, -V35, 12, 1.1, [1 1 1]);

    % Gambar garis Y = 710 px (L05)
    plot(axMap, [p1_710(1) p2_710(1)], [p1_710(2) p2_710(2)], '-', 'Color', [0.0 0.95 1.0], 'LineWidth', 3.6);
    plot(axMap, [p1_710(1) p2_710(1)], [p1_710(2) p2_710(2)], '--', 'Color', [0.05 0.05 0.05], 'LineWidth', 1.4);
    plot(axMap, xFault_710, yTargetAx, 'o', 'MarkerSize', 14, ...
        'MarkerFaceColor', [1 0.95 0], 'MarkerEdgeColor', 'k', 'LineWidth', 2.2);

    text(axMap, xExt(1)+30, yTargetAx+38, ...
        sprintf('GARIS KYMOGRAPH L05 (Y = 710 px | 22.5%% dari Atas) — Titik Potong Sesar Utama di X ≈ %.0f px', xFault_710), ...
        'Color', [0.2 1.0 1.0], 'BackgroundColor', [0 0 0 0.80], 'FontWeight', 'bold', 'FontSize', 11.5);

    set(axMap, 'YDir', 'normal');
    axis(axMap, 'image'); xlim(axMap, xExt); ylim(axMap, yExt);
    xlabel(axMap, 'Posisi X sepanjang Sandbox (px)  [Kiri: Indenter / Hanging Wall  \rightarrow  Kanan: Foreland / Footwall]', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(axMap, 'Posisi Y (px)', 'FontWeight', 'bold', 'FontSize', 11);
    title(axMap, sprintf('axMain — TKS-5\\_cm-1 (Frame %d/%d, Shortening %.2f%%) · Scanline Kymograph pada Y = 710 px (Garis L05)', ...
        refFrame, nF, -strainAxisPct(refFrame)), 'FontSize', 13, 'FontWeight', 'bold');
    cbMap = colorbar(axMap, 'eastoutside');
    cbMap.Label.String = '\gamma_{xy} [\pm0.02]';
    cbMap.Color = 'k';
    i_styleLightAx(axMap);

    % --- Tengah-Kiri: axPSG Kymograph Velocity Magnitude |V| (Y = 710 px) ---
    axPSG_V = axes('Parent', fig1, 'Position', [0.05 0.39 0.41 0.26]);
    imagesc(axPSG_V, 1:nF, x_710, M_vel_710);
    colormap(axPSG_V, turbo(256));
    clim(axPSG_V, velLim);
    set(axPSG_V, 'YDir', 'normal');
    hold(axPSG_V, 'on');
    yline(axPSG_V, xFault_710, '--w', sprintf('Batas Sesar Utama (X ≈ %.0f px)', xFault_710), ...
        'LineWidth', 2.0, 'FontWeight', 'bold', 'FontSize', 10, 'LabelHorizontalAlignment', 'left');
    xline(axPSG_V, refFrame, ':w', sprintf('Frame %d', refFrame), 'LineWidth', 1.6);
    hold(axPSG_V, 'off');
    xlabel(axPSG_V, 'Frame Pair (t = 1 .. 110)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(axPSG_V, 'Posisi X sepanjang Garis Y=710 px (px)', 'FontWeight', 'bold', 'FontSize', 11);
    title(axPSG_V, 'axPSG (Kymograph 2D) — Velocity Magnitude |V| pada Y = 710 px (L05)', ...
        'FontSize', 12, 'FontWeight', 'bold');
    cbV = colorbar(axPSG_V, 'eastoutside');
    cbV.Label.String = '|V| (px/frame)';
    cbV.Label.FontWeight = 'bold';
    cbV.Color = 'k';
    i_styleLightAx(axPSG_V);

    % --- Tengah-Kanan: axPSG Kymograph Cleaned Shear Strain \gamma_xy (Y = 710 px) ---
    axPSG_S = axes('Parent', fig1, 'Position', [0.54 0.39 0.41 0.26]);
    imagesc(axPSG_S, 1:nF, x_710, M_shr_710);
    colormap(axPSG_S, jet(256));
    clim(axPSG_S, [-shearLim, shearLim]);
    set(axPSG_S, 'YDir', 'normal');
    hold(axPSG_S, 'on');
    yline(axPSG_S, xFault_710, '--k', sprintf('Jejak Lokalisasi Sesar (X ≈ %.0f px)', xFault_710), ...
        'LineWidth', 1.8, 'FontWeight', 'bold', 'FontSize', 10, 'LabelHorizontalAlignment', 'left');
    xline(axPSG_S, refFrame, ':k', sprintf('Frame %d', refFrame), 'LineWidth', 1.6);
    hold(axPSG_S, 'off');
    xlabel(axPSG_S, 'Frame Pair (t = 1 .. 110)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(axPSG_S, 'Posisi X sepanjang Garis Y=710 px (px)', 'FontWeight', 'bold', 'FontSize', 11);
    title(axPSG_S, 'axPSG (Kymograph 2D) — Cleaned Shear Strain \gamma_{xy} pada Y = 710 px (L05)', ...
        'FontSize', 12, 'FontWeight', 'bold');
    cbS = colorbar(axPSG_S, 'eastoutside');
    cbS.Label.String = 'Cleaned \gamma_{xy} [\pm0.02]';
    cbS.Label.FontWeight = 'bold';
    cbS.Color = 'k';
    i_styleLightAx(axPSG_S);

    % --- Bawah-Kiri: axPOT Time-Series Velocity Magnitude |V| (Y = 710 px) ---
    axPOT_V = axes('Parent', fig1, 'Position', [0.05 0.06 0.41 0.26]);
    hold(axPOT_V, 'on');
    isHW_710 = (x_710 >= 250) & (x_710 < (xFault_710 - 60));
    isFW_710 = x_710 > (xFault_710 + 60);
    for r = 1:size(M_vel_710, 1)
        if isHW_710(r)
            plot(axPOT_V, 1:nF, M_vel_710(r, :), '-', 'Color', [0.95 0.45 0.45 0.28], 'LineWidth', 0.7);
        elseif isFW_710(r)
            plot(axPOT_V, 1:nF, M_vel_710(r, :), '-', 'Color', [0.40 0.65 0.95 0.28], 'LineWidth', 0.7);
        else
            plot(axPOT_V, 1:nF, M_vel_710(r, :), '-', 'Color', [0.65 0.65 0.65 0.30], 'LineWidth', 0.7);
        end
    end
    hwMeanV = mean(M_vel_710(isHW_710, :), 1, 'omitnan');
    fwMeanV = mean(M_vel_710(isFW_710, :), 1, 'omitnan');
    hPeakV = plot(axPOT_V, 1:nF, peak_vel_710, '-k', 'LineWidth', 2.4);
    hHW_V  = plot(axPOT_V, 1:nF, hwMeanV, '-', 'Color', [0.85 0.10 0.10], 'LineWidth', 2.2);
    hFW_V  = plot(axPOT_V, 1:nF, fwMeanV, '-', 'Color', [0.05 0.35 0.85], 'LineWidth', 2.2);
    hNet_V = plot(axPOT_V, 1:nF, hwMeanV - fwMeanV, '--', 'Color', [0.05 0.60 0.20], 'LineWidth', 2.0);
    xline(axPOT_V, refFrame, ':k', sprintf('Frame %d', refFrame), 'LineWidth', 1.5);
    grid(axPOT_V, 'on'); xlim(axPOT_V, [1 nF]); ylim(axPOT_V, [0 max(peak_vel_710)*1.18]);
    xlabel(axPOT_V, 'Frame Pair (t = 1 .. 110)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(axPOT_V, '|V| (px/frame)', 'FontWeight', 'bold', 'FontSize', 11);
    title(axPOT_V, sprintf('axPOT (Time-Series) — |V| Sepanjang Garis Y = 710 px (L05, %d titik sampel)', size(M_vel_710,1)), ...
        'FontSize', 12, 'FontWeight', 'bold');
    i_styleLightAx(axPOT_V);
    lgV = legend(axPOT_V, [hPeakV, hHW_V, hFW_V, hNet_V], ...
        {'Peak / Indenter Max |V|', 'Mean Hanging Wall (HW, Kiri Sesar)', 'Mean Footwall (FW, Kanan Sesar)', 'Net-Slip Rate \Delta|V| = HW - FW'}, ...
        'Location', 'northeast', 'FontSize', 9.5);
    lgV.Color = [1 1 1]; lgV.TextColor = [0 0 0]; lgV.EdgeColor = [0.7 0.7 0.7];

    % --- Bawah-Kanan: axPOT Time-Series Cleaned Shear Strain \gamma_xy (Y = 710 px) ---
    axPOT_S = axes('Parent', fig1, 'Position', [0.54 0.06 0.41 0.26]);
    hold(axPOT_S, 'on');
    for r = 1:size(M_shr_710, 1)
        plot(axPOT_S, 1:nF, M_shr_710(r, :), '-', 'Color', [0.65 0.65 0.68 0.30], 'LineWidth', 0.8);
    end
    faultZoneMask = abs(x_710 - xFault_710) <= 32;
    faultCurveMean = mean(M_shr_710(faultZoneMask, :), 1, 'omitnan');
    minShrEnv = min(M_shr_710(interior_710, :), [], 1, 'omitnan');
    maxShrEnv = max(M_shr_710(interior_710, :), [], 1, 'omitnan');
    hMaxS   = plot(axPOT_S, 1:nF, maxShrEnv, '-k', 'LineWidth', 2.4);
    hFaultS = plot(axPOT_S, 1:nF, faultCurveMean, '-', 'Color', [0.85 0.10 0.15], 'LineWidth', 2.4);
    hMinS   = plot(axPOT_S, 1:nF, minShrEnv, '--', 'Color', [0.10 0.35 0.85], 'LineWidth', 1.8);
    yline(axPOT_S, 0.0035, ':k', '+Deadband (0.0035)', 'LineWidth', 1.2);
    yline(axPOT_S, -0.0035, ':k', '-Deadband (-0.0035)', 'LineWidth', 1.2);
    xline(axPOT_S, refFrame, ':k', sprintf('Frame %d', refFrame), 'LineWidth', 1.5);
    grid(axPOT_S, 'on'); xlim(axPOT_S, [1 nF]); ylim(axPOT_S, [-0.015, 0.032]);
    xlabel(axPOT_S, 'Frame Pair (t = 1 .. 110)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(axPOT_S, 'Cleaned Shear Strain \gamma_{xy}', 'FontWeight', 'bold', 'FontSize', 11);
    title(axPOT_S, sprintf('axPOT (Time-Series) — Cleaned \\gamma_{xy} Sepanjang Garis Y = 710 px (L05, Sesar X \\approx %.0f px)', xFault_710), ...
        'FontSize', 12, 'FontWeight', 'bold');
    i_styleLightAx(axPOT_S);
    lgS = legend(axPOT_S, [hMaxS, hFaultS, hMinS], ...
        {'Envelope Puncak Sesar (Max \gamma_{xy})', sprintf('Rata-Rata Inti Sesar (X \\approx %.0f \\pm 32 px)', xFault_710), 'Envelope Min \gamma_{xy}'}, ...
        'Location', 'northeast', 'FontSize', 9.5);
    lgS.Color = [1 1 1]; lgS.TextColor = [0 0 0]; lgS.EdgeColor = [0.7 0.7 0.7];

    outFig1 = fullfile(outDir, 'TKS-5_cm-1_PSG_Y710px_L05_Dashboard.jpg');
    exportgraphics(fig1, outFig1, 'Resolution', 150, 'BackgroundColor', 'white');
    close(fig1);

    % =====================================================================
    % DASHBOARD 2: KYMOGRAPH SPASIAL SEJAJAR CITRA (X = Posisi Sandbox, Y = Frame)
    % =====================================================================
    fig2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2200 1650]);
    i_forceLightFig(fig2);
    tl2 = tiledlayout(fig2, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl2, 'TKS-5\_cm-1 — Kymograph Spasial Sejajar Penampang pada Garis L05 (Y = 710 px)', ...
        'FontSize', 15, 'FontWeight', 'bold', 'Color', 'k');

    % Panel 1: axMain Penampang Sandbox + Garis Y = 710 px
    axS1 = nexttile(tl2, 1);
    hold(axS1, 'on');
    imagesc(axS1, xExt, [yExt(2) yExt(1)], Z35_clean);
    colormap(axS1, jet(256)); clim(axS1, [-shearLim, shearLim]);
    image(axS1, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgb35, 'AlphaData', 0.35);
    pivcore.util.drawGlyphs(axS1, x1, yF, U35, -V35, 12, 1.1, [1 1 1]);
    plot(axS1, [p1_710(1) p2_710(1)], [p1_710(2) p2_710(2)], '-', 'Color', [0 0.95 1], 'LineWidth', 3.5);
    plot(axS1, [p1_710(1) p2_710(1)], [p1_710(2) p2_710(2)], '--k', 'LineWidth', 1.4);
    plot(axS1, xFault_710, yTargetAx, 'o', 'MarkerSize', 13, 'MarkerFaceColor', [1 0.95 0], 'MarkerEdgeColor', 'k', 'LineWidth', 2.0);
    xline(axS1, xFault_710, '--w', 'LineWidth', 1.5);
    set(axS1, 'YDir', 'normal'); xlim(axS1, xExt); ylim(axS1, yExt);
    ylabel(axS1, 'Posisi Y (px)', 'FontWeight', 'bold', 'FontSize', 11);
    title(axS1, sprintf('[1] Penampang Sandbox (Frame %d/%d) — Garis Scanline L05 pada Y = 710 px (Sesar Utama di X \\approx %.0f px)', refFrame, nF, xFault_710), ...
        'FontWeight', 'bold', 'FontSize', 12);
    cbS1 = colorbar(axS1, 'eastoutside'); cbS1.Label.String = '\gamma_{xy} [\pm0.02]'; cbS1.Color = 'k';
    i_styleLightAx(axS1);

    % Panel 2: Kymograph Velocity Magnitude |V| (Sumbu-X = Posisi X [px], Sumbu-Y = Frame [1..110])
    axS2 = nexttile(tl2, 2);
    imagesc(axS2, x_710, 1:nF, M_vel_710');
    colormap(axS2, turbo(256)); clim(axS2, velLim);
    set(axS2, 'YDir', 'normal'); xlim(axS2, xExt); ylim(axS2, [1 nF]);
    hold(axS2, 'on');
    xline(axS2, xFault_710, '--w', sprintf('Batas Sesar X ≈ %.0f px', xFault_710), 'LineWidth', 2.0, 'FontWeight', 'bold');
    yline(axS2, refFrame, ':w', sprintf('Frame %d', refFrame), 'LineWidth', 1.5);
    hold(axS2, 'off');
    ylabel(axS2, 'Frame Pair (t = 1 \rightarrow 110)', 'FontWeight', 'bold', 'FontSize', 11);
    title(axS2, '[2] Kymograph Spasial Velocity Magnitude |V| pada Y = 710 px (Kiri Sesar = Hanging Wall Bergerak, Kanan Sesar = Footwall Diam)', ...
        'FontWeight', 'bold', 'FontSize', 12);
    cbS2 = colorbar(axS2, 'eastoutside'); cbS2.Label.String = '|V| (px/frame)'; cbS2.Color = 'k';
    i_styleLightAx(axS2);

    % Panel 3: Kymograph Cleaned Shear Strain \gamma_xy (Sumbu-X = Posisi X [px], Sumbu-Y = Frame [1..110])
    axS3 = nexttile(tl2, 3);
    imagesc(axS3, x_710, 1:nF, M_shr_710');
    colormap(axS3, jet(256)); clim(axS3, [-shearLim, shearLim]);
    set(axS3, 'YDir', 'normal'); xlim(axS3, xExt); ylim(axS3, [1 nF]);
    hold(axS3, 'on');
    xline(axS3, xFault_710, '--k', sprintf('Jejak Sesar X ≈ %.0f px', xFault_710), 'LineWidth', 1.8, 'FontWeight', 'bold');
    yline(axS3, refFrame, ':k', sprintf('Frame %d', refFrame), 'LineWidth', 1.5);
    hold(axS3, 'off');
    xlabel(axS3, 'Posisi X sepanjang Garis Y = 710 px (px)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(axS3, 'Frame Pair (t = 1 \rightarrow 110)', 'FontWeight', 'bold', 'FontSize', 11);
    title(axS3, '[3] Kymograph Spasial Cleaned Shear Strain \gamma_{xy} pada Y = 710 px (Evolusi Lokalisasi Sesar dari Frame 1 \rightarrow 110)', ...
        'FontWeight', 'bold', 'FontSize', 12);
    cbS3 = colorbar(axS3, 'eastoutside'); cbS3.Label.String = 'Cleaned \gamma_{xy} [\pm0.02]'; cbS3.Color = 'k';
    i_styleLightAx(axS3);

    outFig2 = fullfile(outDir, 'TKS-5_cm-1_Kymo_Spasial_Y710px_Sejajar_Citra.jpg');
    exportgraphics(fig2, outFig2, 'Resolution', 150, 'BackgroundColor', 'white');
    close(fig2);

    % Simpan CSV & MAT untuk Y = 710 px
    T_710 = table((1:nF)', strainAxisPct(:), peak_vel_710(:), hwMeanV(:), fwMeanV(:), (hwMeanV(:)-fwMeanV(:)), ...
        faultCurveMean(:), maxShrEnv(:), minShrEnv(:), xFaultTrack(:), ...
        'VariableNames', {'Frame', 'Shortening_Pct', 'Peak_Vel_Y710', 'HW_Mean_Vel_Y710', 'FW_Mean_Vel_Y710', 'NetSlip_Vel_Y710', ...
        'FaultCore_Shear_Y710', 'Max_Shear_Y710', 'Min_Shear_Y710', 'X_Fault_Peak_px'});
    outCsv = fullfile(outDir, 'TKS-5_cm-1_Kymo_Y710px_L05_TimeSeries.csv');
    writetable(T_710, outCsv);

    outMat = fullfile(outDir, 'TKS-5_cm-1_Kymo_Y710px_L05_Matrices.mat');
    save(outMat, 'M_vel_710', 'M_shr_710', 'M_shrDb_710', 'posPx_710', 'x_710', 'y_710', ...
        'peak_vel_710', 'peak_shr_710', 'xFault_710', 'xFaultTrack', 'strainAxisPct');

    out = struct('figDashboard', outFig1, 'figSpatial', outFig2, 'csvFile', outCsv, 'matFile', outMat, 'xFault_710', xFault_710);
    fprintf('\n✅ Selesai! Berkas tersimpan di:\n   1) %s\n   2) %s\n   3) %s\n', outFig1, outFig2, outCsv);
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
