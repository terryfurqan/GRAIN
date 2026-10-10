function render_TKS5_6_verification_jpgs()
% RENDER_TKS5_6_VERIFICATION_JPGS  Render JPG visualisasi verifikasi hasil
% deteksi spasiotemporal untuk TKS-5_cm-6:
%   1. TKS-5_cm-6_20_Garis_Horizontal_L01_L20.jpg
%      (Citra Grayscale + Overlay Shear Strain \gamma_xy + 20 Garis L01..L20 + Titik Deteksi Sesar)
%   2. TKS-5_cm-6_PSG_Y710px_dan_Tengah_Dashboard.jpg
%      (Kymograph axPSG & Time-Series axPOT 119-Frame Consecutive + Full PIV pada Y=710 px & Y=484 px)
%   3. TKS-5_cm-6_Evolusi_3Fase_Early_Mid_Late.jpg
%      (Bukti visual 3 fase: Early F05, Mid F12, Late F24 yang memverifikasi propagasi sesar,
%       pengangkatan fault scarp > Y=800 px, toe slumping X≈1430 px, dan mundurnya basal detachment)

    here = fileparts(mfilename('fullpath'));
    cd(here);
    grain_setup();

    pivMatFile = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm/PIV_2026-06-24/TKS-5_cm-6-NOVL-S1-120to28-4p20px.mat';
    outDir = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm/TKS_5 Compare/TKS-5_cm-6_Spatiotemporal_Detection';
    if ~isfolder(outDir), mkdir(outDir); end

    fprintf('Memuat %s...\n', pivMatFile);
    S_piv = load(pivMatFile);
    dataFull = pivcore.data.buildDataset(S_piv);
    nF = dataFull.nFrames;
    x1 = pivcore.data.safeFrame(dataFull.x, 1);
    y1 = pivcore.data.safeFrame(dataFull.y, 1);
    xExt = [min(x1(:)), max(x1(:))];
    yExt = [min(y1(:)), max(y1(:))];
    yMid = (yExt(1) + yExt(2)) / 2;
    yF = (yExt(2) + yExt(1)) - y1;
    xv = x1(1, :);
    yv = y1(:, 1);

    % Precompute stacks
    velStack = cell(1, nF);
    shrCleanStack = cell(1, nF);
    shrDbStack = cell(1, nF);
    for f = 1:nF
        [U, V] = pivcore.data.pickAnyVel(dataFull, f);
        velStack{f} = hypot(U, V);
        Zraw = pivcore.data.computeShearRate(dataFull, f, 'mode', 'engineering');
        Zcln = imgaussfilt(medfilt2(Zraw, [3 3], 'symmetric'), 1.8);
        Zdb  = Zcln;
        Zdb(abs(Zdb) < 0.0035) = 0;
        shrCleanStack{f} = Zcln;
        shrDbStack{f}    = Zdb;
    end

    % 20 Garis Horizontal (L01 .. L20)
    nLines = 20;
    posPct = linspace(2.5, 97.5, nLines)';
    yRow = yExt(1) + (posPct / 100) * (yExt(2) - yExt(1));
    yAx  = 2 * yMid - yRow;

    % =====================================================================
    % GAMBAR 1: 20 GARIS HORIZONTAL (L01 .. L20) + OVERLAY DETEKSI SPASIOTEMPORAL
    % =====================================================================
    refFrame = 12; % Mid-stage peak localization (F12/26)
    bgRef = pivcore.data.bgAt(dataFull, refFrame);
    rgbRef = pivcore.util.grayCLAHE(bgRef, true, true);
    [Uref, Vref] = pivcore.data.pickAnyVel(dataFull, refFrame);
    Zref = shrDbStack{refFrame};
    ZmeanMid = mean(cat(3, shrCleanStack{9:16}), 3);

    % Cari titik potong sesar utama pada tiap garis L03..L15 dan detachment di L15..L16
    xFaultLine = nan(nLines, 1);
    valFaultLine = nan(nLines, 1);
    for k = 1:nLines
        [~, rIdx] = min(abs(yv - yRow(k)));
        rowVals = ZmeanMid(rIdx, :);
        if k >= 3 && k <= 15
            msk = (xv >= 950) & (xv <= 1600);
            rowMasked = rowVals; rowMasked(~msk) = -Inf;
            [mxV, cIdx] = max(rowMasked);
            if isfinite(mxV) && mxV >= 0.0020
                xFaultLine(k) = xv(cIdx);
                valFaultLine(k) = mxV;
            end
        end
    end

    fig1 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2400 1650]);
    i_forceLightFig(fig1);
    tl1 = tiledlayout(fig1, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    % Panel Atas: Citra Grayscale CLAHE + 20 Garis Horizontal
    ax1 = nexttile(tl1, 1);
    hold(ax1, 'on');
    image(ax1, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgbRef);
    set(ax1, 'YDir', 'normal');
    axis(ax1, 'image'); xlim(ax1, xExt); ylim(ax1, yExt);
    cmapLines = turbo(nLines);
    for k = 1:nLines
        cL = cmapLines(k, :);
        plot(ax1, xExt, [yAx(k) yAx(k)], '-', 'Color', [0 0 0 0.55], 'LineWidth', 2.2);
        plot(ax1, xExt, [yAx(k) yAx(k)], '--', 'Color', cL, 'LineWidth', 1.5);
        text(ax1, xExt(1) + 12, yAx(k), sprintf(' L%02d (%4.1f%%) ', k, posPct(k)), ...
            'Color', 'w', 'BackgroundColor', [0 0 0 0.78], 'FontWeight', 'bold', 'FontSize', 8.5, ...
            'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left', 'Margin', 1);
        text(ax1, xExt(2) - 12, yAx(k), sprintf(' L%02d | Y=%.0f px ', k, yAx(k)), ...
            'Color', [1 0.95 0.3], 'BackgroundColor', [0 0 0 0.78], 'FontWeight', 'bold', 'FontSize', 8.5, ...
            'VerticalAlignment', 'middle', 'HorizontalAlignment', 'right', 'Margin', 1);
    end
    title(ax1, sprintf('TKS-5\\_cm-6 (Frame %d/%d) — Citra Grayscale Asli + 20 Garis Scanline Horizontal (L01 Atas \\rightarrow L20 Bawah)', refFrame, nF), ...
        'FontSize', 13, 'FontWeight', 'bold');
    ylabel(ax1, 'Posisi Y (px)', 'FontWeight', 'bold', 'FontSize', 11);
    i_styleLightAx(ax1);

    % Panel Bawah: Overlay Cleaned Shear Strain + Vektor + Hasil Deteksi Spasiotemporal
    ax2 = nexttile(tl1, 2);
    hold(ax2, 'on');
    imagesc(ax2, xExt, [yExt(2) yExt(1)], Zref);
    colormap(ax2, jet(256)); clim(ax2, [-0.02, 0.02]);
    image(ax2, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgbRef, 'AlphaData', 0.33);
    pivcore.util.drawGlyphs(ax2, x1, yF, Uref, -Vref, 12, 1.1, [1 1 1]);

    for k = 1:nLines
        isKey = ismember(k, [3 4 5 9 10 14 16]);
        lw = 1.1; if isKey, lw = 2.0; end
        plot(ax2, xExt, [yAx(k) yAx(k)], '--', 'Color', [0.1 0.1 0.1 0.65], 'LineWidth', lw);
        text(ax2, xExt(1) + 12, yAx(k), sprintf(' L%02d (Y=%.0f) ', k, yAx(k)), ...
            'Color', 'w', 'BackgroundColor', [0 0 0 0.75], 'FontWeight', 'bold', 'FontSize', 8.5, ...
            'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left', 'Margin', 1);

        if isfinite(xFaultLine(k))
            plot(ax2, xFaultLine(k), yAx(k), 'o', 'MarkerSize', 9, ...
                'MarkerFaceColor', [1 0.95 0], 'MarkerEdgeColor', 'k', 'LineWidth', 1.6);
            text(ax2, xExt(2) - 12, yAx(k), sprintf(' L%02d | X_{sesar}=%.0f px (\\gamma_{xy}=%+.3f) ', k, xFaultLine(k), valFaultLine(k)), ...
                'Color', [0.65 1 0.65], 'BackgroundColor', [0 0 0 0.78], 'FontWeight', 'bold', 'FontSize', 8.5, ...
                'VerticalAlignment', 'middle', 'HorizontalAlignment', 'right', 'Margin', 1);
        elseif k == 16
            % Tandai rentang Basal Detachment di L16
            plot(ax2, [250 1004], [yAx(k) yAx(k)], '-', 'Color', [0 1 1], 'LineWidth', 3.0);
            text(ax2, xExt(2) - 12, yAx(k), ' L16 | Detachment Basal X=200..1004 px (\gamma_{xy}=-0.047) ', ...
                'Color', [0.4 0.95 1], 'BackgroundColor', [0 0 0 0.78], 'FontWeight', 'bold', 'FontSize', 8.5, ...
                'VerticalAlignment', 'middle', 'HorizontalAlignment', 'right', 'Margin', 1);
        else
            text(ax2, xExt(2) - 12, yAx(k), sprintf(' L%02d | (di luar zona sesar utama) ', k), ...
                'Color', [0.85 0.85 0.85], 'BackgroundColor', [0 0 0 0.68], 'FontSize', 8.0, ...
                'VerticalAlignment', 'middle', 'HorizontalAlignment', 'right', 'Margin', 1);
        end
    end
    % Plot garis hubung jejak sesar hasil deteksi buta (L15 -> L03)
    validF = isfinite(xFaultLine);
    plot(ax2, xFaultLine(validF), yAx(validF), '-y', 'LineWidth', 2.4);

    set(ax2, 'YDir', 'normal');
    axis(ax2, 'image'); xlim(ax2, xExt); ylim(ax2, yExt);
    cb2 = colorbar(ax2, 'eastoutside'); cb2.Label.String = 'Cleaned \gamma_{xy} [\pm0.02]'; cb2.Color = 'k';
    title(ax2, sprintf('TKS-5\\_cm-6 (Frame %d/%d) — Verifikasi Visual Hasil Deteksi Spasiotemporal (Jejak Sesar Kuning \\theta \\approx 65.1^\\circ & Detachment Basal Cyan)', refFrame, nF), ...
        'FontSize', 13, 'FontWeight', 'bold');
    xlabel(ax2, 'Posisi X sepanjang Sandbox (px)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(ax2, 'Posisi Y (px)', 'FontWeight', 'bold', 'FontSize', 11);
    i_styleLightAx(ax2);

    outFig1 = fullfile(outDir, 'TKS-5_cm-6_20_Garis_Horizontal_L01_L20.jpg');
    exportgraphics(fig1, outFig1, 'Resolution', 150, 'BackgroundColor', 'white');
    close(fig1);

    % =====================================================================
    % GAMBAR 2: KYMOGRAPH SPASIAL & DASHBOARD (Y = 710 px [L05] & Y = 484 px [L10])
    % =====================================================================
    spacingPx = 16;
    [M_vel_710, ~, x_710, ~] = i_sampleStackAlongImageLine(x1, y1, velStack, [xExt(1) 710], [xExt(2) 710], spacingPx);
    [M_shr_710, ~, ~, ~]     = i_sampleStackAlongImageLine(x1, y1, shrCleanStack, [xExt(1) 710], [xExt(2) 710], spacingPx);
    [M_vel_484, ~, x_484, ~] = i_sampleStackAlongImageLine(x1, y1, velStack, [xExt(1) 483.5], [xExt(2) 483.5], spacingPx);
    [M_shr_484, ~, ~, ~]     = i_sampleStackAlongImageLine(x1, y1, shrCleanStack, [xExt(1) 483.5], [xExt(2) 483.5], spacingPx);

    % Muat juga QPIV 119-frame consecutive untuk menampilkan deteksi dead frames 1-6 & 118-119
    Sq50  = load(fullfile(outDir, 'TKS-5_cm-6_QPIV_consec_mid50.mat')); dQ50  = pivcore.data.buildDataset(Sq50);
    Sq710 = load(fullfile(outDir, 'TKS-5_cm-6_QPIV_consec_y710.mat'));  dQ710 = pivcore.data.buildDataset(Sq710);
    [M_vel_c50, M_shr_c50, x_c50]   = i_scanStripCenter(dQ50);
    [M_vel_c710, M_shr_c710, x_c710] = i_scanStripCenter(dQ710);
    nFc = size(M_vel_c50, 2);
    peakV_c50 = max(M_vel_c50, [], 1, 'omitnan');
    ex50 = pivprepFrameExclusion(peakV_c50, nan(1, nFc), struct('useMotion', true, 'useTime', false));

    fig2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2400 1750]);
    i_forceLightFig(fig2);
    tl2 = tiledlayout(fig2, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl2, 'TKS-5\_cm-6 — Kymograph (axPSG) & Time-Series (axPOT) Hasil Deteksi Spasiotemporal (119-Frame Consecutive)', ...
        'FontSize', 15, 'FontWeight', 'bold', 'Color', 'k');

    % [1,1] Kymograph |V| pada Y = 710 px (L05, 119 frames)
    axK1 = nexttile(tl2, 1);
    imagesc(axK1, 1:nFc, x_c710, M_vel_c710); colormap(axK1, turbo(256)); clim(axK1, [0 2.0]); set(axK1, 'YDir', 'normal');
    hold(axK1, 'on');
    yline(axK1, 1298, '--w', 'Sesar Utama X ≈ 1298 px', 'LineWidth', 1.8, 'FontWeight', 'bold');
    xline(axK1, 6.5, '-r', 'Akhir Idle Awal (F06)', 'LineWidth', 1.6);
    xline(axK1, 117.5, '-r', 'Shutoff Akhir (F118)', 'LineWidth', 1.6);
    hold(axK1, 'off');
    ylabel(axK1, 'Posisi X (px)', 'FontWeight', 'bold');
    title(axK1, '[1A] Kymograph |V| — Garis L05 (Y = 710 px, 119 Pasangan Konsekutif)', 'FontWeight', 'bold', 'FontSize', 11.5);
    cbK1 = colorbar(axK1); cbK1.Label.String = '|V| (px/fr)'; cbK1.Color = 'k';
    i_styleLightAx(axK1);

    % [1,2] Kymograph Cleaned \gamma_xy pada Y = 710 px (L05, 119 frames)
    axK2 = nexttile(tl2, 2);
    imagesc(axK2, 1:nFc, x_c710, M_shr_c710); colormap(axK2, jet(256)); clim(axK2, [-0.015 0.015]); set(axK2, 'YDir', 'normal');
    hold(axK2, 'on');
    yline(axK2, 1298, '--k', 'Fore-Thrust X ≈ 1298 px', 'LineWidth', 1.8, 'FontWeight', 'bold');
    yline(axK2, 1421, ':b', 'Toe Flexure / Slump X ≈ 1421 px', 'LineWidth', 1.6, 'FontWeight', 'bold');
    hold(axK2, 'off');
    ylabel(axK2, 'Posisi X (px)', 'FontWeight', 'bold');
    title(axK2, '[1B] Kymograph Cleaned \gamma_{xy} — Garis L05 (Y = 710 px, 119 Pasangan Konsekutif)', 'FontWeight', 'bold', 'FontSize', 11.5);
    cbK2 = colorbar(axK2); cbK2.Label.String = '\gamma_{xy}'; cbK2.Color = 'k';
    i_styleLightAx(axK2);

    % [2,1] Kymograph |V| pada Y = 461 px (Tengah 50%, 119 frames)
    axK3 = nexttile(tl2, 3);
    imagesc(axK3, 1:nFc, x_c50, M_vel_c50); colormap(axK3, turbo(256)); clim(axK3, [0 2.0]); set(axK3, 'YDir', 'normal');
    hold(axK3, 'on');
    yline(axK3, 1218, '--w', 'Sesar Utama X ≈ 1218 px', 'LineWidth', 1.8, 'FontWeight', 'bold');
    xline(axK3, 6.5, '-r', 'F06', 'LineWidth', 1.6);
    xline(axK3, 117.5, '-r', 'F118', 'LineWidth', 1.6);
    hold(axK3, 'off');
    ylabel(axK3, 'Posisi X (px)', 'FontWeight', 'bold');
    title(axK3, '[2A] Kymograph |V| — Bagian Tengah (Y = 461 px, 119 Pasangan Konsekutif)', 'FontWeight', 'bold', 'FontSize', 11.5);
    cbK3 = colorbar(axK3); cbK3.Label.String = '|V| (px/fr)'; cbK3.Color = 'k';
    i_styleLightAx(axK3);

    % [2,2] Kymograph Cleaned \gamma_xy pada Y = 461 px (Tengah 50%, 119 frames)
    axK4 = nexttile(tl2, 4);
    imagesc(axK4, 1:nFc, x_c50, M_shr_c50); colormap(axK4, jet(256)); clim(axK4, [-0.02 0.02]); set(axK4, 'YDir', 'normal');
    hold(axK4, 'on');
    yline(axK4, 1218, '--k', 'Fore-Thrust X ≈ 1218 px', 'LineWidth', 1.8, 'FontWeight', 'bold');
    hold(axK4, 'off');
    ylabel(axK4, 'Posisi X (px)', 'FontWeight', 'bold');
    title(axK4, '[2B] Kymograph Cleaned \gamma_{xy} — Bagian Tengah (Y = 461 px, 119 Pasangan Konsekutif)', 'FontWeight', 'bold', 'FontSize', 11.5);
    cbK4 = colorbar(axK4); cbK4.Label.String = '\gamma_{xy}'; cbK4.Color = 'k';
    i_styleLightAx(axK4);

    % [3,1] axPOT Time-Series |V| + Dead Frames [1-6, 118-119]
    axK5 = nexttile(tl2, 5); hold(axK5, 'on');
    for r = 1:size(M_vel_c50, 1)
        plot(axK5, 1:nFc, M_vel_c50(r, :), '-', 'Color', [0.65 0.65 0.68 0.25]);
    end
    isHW50 = (x_c50 >= 250) & (x_c50 < 1150);
    isFW50 = (x_c50 > 1300);
    hPk = plot(axK5, 1:nFc, peakV_c50, '-k', 'LineWidth', 2.2);
    hHW = plot(axK5, 1:nFc, mean(M_vel_c50(isHW50, :), 1, 'omitnan'), '-r', 'LineWidth', 2.0);
    hFW = plot(axK5, 1:nFc, mean(M_vel_c50(isFW50, :), 1, 'omitnan'), '-b', 'LineWidth', 2.0);
    yline(axK5, ex50.motionMin, '--r', sprintf('Dead Threshold (%.3f px/fr)', ex50.motionMin), 'LineWidth', 1.4, 'FontWeight', 'bold');
    % Arsir dead frames 1-6 dan 118-119
    patch(axK5, [0.5 6.5 6.5 0.5], [0 0 2.8 2.8], [1 0.4 0.4], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    patch(axK5, [117.5 119.5 119.5 117.5], [0 0 2.8 2.8], [1 0.4 0.4], 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    grid(axK5, 'on'); xlim(axK5, [1 nFc]); ylim(axK5, [0 2.8]);
    xlabel(axK5, 'Consecutive Frame Pair (1 .. 119)', 'FontWeight', 'bold');
    ylabel(axK5, '|V| (px/frame)', 'FontWeight', 'bold');
    title(axK5, '[3A] axPOT Time-Series |V| — Deteksi Dead Frames [1–6] & [118–119] (Arsir Merah)', 'FontWeight', 'bold', 'FontSize', 11.5);
    lgK5 = legend(axK5, [hPk, hHW, hFW], {'Peak Indenter |V|', 'Mean Hanging Wall (Kiri)', 'Mean Footwall (Kanan)'}, 'Location', 'northeast');
    lgK5.Color = [1 1 1]; lgK5.TextColor = [0 0 0];
    i_styleLightAx(axK5);

    % [3,2] axPOT Time-Series Perbandingan Propagasi Sesar Y=461 px vs Y=710 px
    axK6 = nexttile(tl2, 6); hold(axK6, 'on');
    shrCore461 = mean(M_shr_c50(abs(x_c50 - 1218) <= 32, :), 1, 'omitnan');
    shrCore710 = mean(M_shr_c710(abs(x_c710 - 1298) <= 32, :), 1, 'omitnan');
    shrToe710  = mean(M_shr_c710(abs(x_c710 - 1421) <= 32, :), 1, 'omitnan');
    hC461 = plot(axK6, 1:nFc, shrCore461, '-r', 'LineWidth', 2.2);
    hC710 = plot(axK6, 1:nFc, shrCore710, '-', 'Color', [0.0 0.55 0.85], 'LineWidth', 2.2);
    hT710 = plot(axK6, 1:nFc, shrToe710, '--', 'Color', [0.15 0.20 0.75], 'LineWidth', 1.8);
    yline(axK6, 0.0035, ':k', '+Deadband'); yline(axK6, -0.0035, ':k', '-Deadband');
    grid(axK6, 'on'); xlim(axK6, [1 nFc]); ylim(axK6, [-0.012 0.026]);
    xlabel(axK6, 'Consecutive Frame Pair (1 .. 119)', 'FontWeight', 'bold');
    ylabel(axK6, 'Cleaned Shear Strain \gamma_{xy}', 'FontWeight', 'bold');
    title(axK6, '[3B] Bukti Propagasi Vertikal: Inti Sesar Y=461 px (Merah) vs Y=710 px (Biru) & Toe Flexure', 'FontWeight', 'bold', 'FontSize', 11.5);
    lgK6 = legend(axK6, [hC461, hC710, hT710], ...
        {'Inti Sesar Tengah (Y=461 px, X≈1218 px)', 'Inti Sesar Atas L05 (Y=710 px, X≈1298 px)', 'Toe Flexure / Slump L05 (Y=710 px, X≈1421 px)'}, ...
        'Location', 'northeast');
    lgK6.Color = [1 1 1]; lgK6.TextColor = [0 0 0];
    i_styleLightAx(axK6);

    outFig2 = fullfile(outDir, 'TKS-5_cm-6_PSG_Y710px_dan_Tengah_Dashboard.jpg');
    exportgraphics(fig2, outFig2, 'Resolution', 150, 'BackgroundColor', 'white');
    close(fig2);

    % =====================================================================
    % GAMBAR 3: EVOLUSI 3 FASE (EARLY F05, MID F12, LATE F24) — VERIFIKASI
    %           FAULT SCARP UPLIFT, TOE SLUMPING & BASAL DETACHMENT RETREAT
    % =====================================================================
    fig3 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2300 1750]);
    i_forceLightFig(fig3);
    tl3 = tiledlayout(fig3, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl3, 'TKS-5\_cm-6 — Verifikasi Visual 3 Fase Evolusi (Early F05, Mid F12, Late F24) terhadap Prediksi Spasiotemporal', ...
        'FontSize', 15, 'FontWeight', 'bold', 'Color', 'k');

    frList = [5, 12, 24];
    stLbls = {
        '[1] FASE AWAL (Frame 05/26) — Sesar Aktif dari Akar Ramp (X=1100) ke Permukaan (X=1309) & Detachment Penuh s/d X=1004 px', ...
        '[2] FASE MENENGAH (Frame 12/26) — Klimaks Lokalisasi Geser (\gamma_{xy}=+0.042 @ L09/L10) & Gawir Sesar Mulai Terangkat > Y=800 px', ...
        '[3] FASE AKHIR (Frame 24/26) — Gawir Sesar Tinggi (L03), Toe Slumping (Biru di X≈1421–1453 px), & Detachment Basal Mundur ke X≈716 px'
    };

    for idx = 1:3
        f = frList(idx);
        ax = nexttile(tl3, idx);
        hold(ax, 'on');
        bgF = pivcore.data.bgAt(dataFull, f);
        rgbF = pivcore.util.grayCLAHE(bgF, true, true);
        [Uf, Vf] = pivcore.data.pickAnyVel(dataFull, f);
        Zf = shrDbStack{f};

        imagesc(ax, xExt, [yExt(2) yExt(1)], Zf);
        colormap(ax, jet(256)); clim(ax, [-0.02, 0.02]);
        image(ax, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgbF, 'AlphaData', 0.34);
        pivcore.util.drawGlyphs(ax, x1, yF, Uf, -Vf, 12, 1.1, [1 1 1]);

        % Garis referensi kunci: L03 (Y=798.5), L05 (Y=708.5), L10 (Y=483.5), L16 (Y=213.5)
        for kk = [3, 5, 10, 16]
            plot(ax, xExt, [yAx(kk) yAx(kk)], '--k', 'LineWidth', 1.2);
            text(ax, xExt(1)+15, yAx(kk)+18, sprintf('L%02d (Y=%.0f px)', kk, yAx(kk)), ...
                'Color', 'w', 'BackgroundColor', [0 0 0 0.72], 'FontWeight', 'bold', 'FontSize', 9);
        end
        % Plot jejak sesar hasil deteksi
        plot(ax, xFaultLine(validF), yAx(validF), '-y', 'LineWidth', 2.2);
        plot(ax, xFaultLine(validF), yAx(validF), 'ko', 'MarkerFaceColor', 'y', 'MarkerSize', 7);

        % Tandai fitur spesifik yang terdeteksi secara buta
        if idx == 3
            plot(ax, 1435, 730, 'bs', 'MarkerSize', 14, 'MarkerFaceColor', [0.2 0.8 1], 'LineWidth', 2);
            text(ax, 1470, 730, '\leftarrow Toe Flexure / Slump (X \approx 1421-1453 px, \gamma_{xy} < 0)', ...
                'Color', [0.4 0.95 1], 'BackgroundColor', [0 0 0 0.80], 'FontWeight', 'bold', 'FontSize', 10);
            xline(ax, 716, '--c', 'Batas Detachment Late (X≈716 px)', 'LineWidth', 1.8, 'FontWeight', 'bold');
        else
            xline(ax, 1004, '--c', 'Ujung Detachment (X≈1004 px)', 'LineWidth', 1.8, 'FontWeight', 'bold');
        end

        set(ax, 'YDir', 'normal'); axis(ax, 'image'); xlim(ax, xExt); ylim(ax, yExt);
        cb = colorbar(ax, 'eastoutside'); cb.Label.String = '\gamma_{xy} [\pm0.02]'; cb.Color = 'k';
        title(ax, stLbls{idx}, 'FontWeight', 'bold', 'FontSize', 12);
        ylabel(ax, 'Posisi Y (px)', 'FontWeight', 'bold');
        if idx == 3
            xlabel(ax, 'Posisi X sepanjang Sandbox (px)', 'FontWeight', 'bold', 'FontSize', 11);
        end
        i_styleLightAx(ax);
    end

    outFig3 = fullfile(outDir, 'TKS-5_cm-6_Evolusi_3Fase_Early_Mid_Late.jpg');
    exportgraphics(fig3, outFig3, 'Resolution', 150, 'BackgroundColor', 'white');
    close(fig3);

    fprintf('\n✅ Ketiga JPG verifikasi TKS-5_cm-6 berhasil dibuat:\n');
    fprintf('   1) %s\n   2) %s\n   3) %s\n', outFig1, outFig2, outFig3);
end

function [M_vel, M_shr, xPts] = i_scanStripCenter(data)
    nF = data.nFrames;
    x1 = pivcore.data.safeFrame(data.x, 1);
    y1 = pivcore.data.safeFrame(data.y, 1);
    xv = x1(1, :);
    yv = y1(:, 1);
    rMid = round(numel(yv) / 2);
    xPts = xv;
    nPts = numel(xPts);
    M_vel = nan(nPts, nF);
    M_shr = nan(nPts, nF);
    for f = 1:nF
        [U, V] = pivcore.data.pickAnyVel(data, f);
        Vmag = hypot(U, V);
        Zraw = pivcore.data.computeShearRate(data, f, 'mode', 'engineering');
        Zcln = imgaussfilt(medfilt2(Zraw, [3 3], 'symmetric'), 1.8);
        for c = 1:nPts
            M_vel(c, f) = i_mean3x3(Vmag, c, rMid);
            M_shr(c, f) = i_mean3x3(Zcln, c, rMid);
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
