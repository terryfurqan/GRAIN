function T_fsr = detect_fsr_TKS5_1_to_8()
% DETECT_FSR_TKS5_1_TO_8  Deteksi frame terbentuknya FSR (Fault Surface Rupture)
% pada TKS-5_cm-1 s/d TKS-5_cm-8 berdasarkan momen pertama kali Shear Strain
% (\gamma_xy) terdeteksi pada garis dekat permukaan Y ≈ 700-710 px (Garis L05).

    here = fileparts(mfilename('fullpath'));
    cd(here);
    if isfile(fullfile(here, 'grain_setup.m'))
        grain_setup();
    end

    baseDir = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm';
    pivDir  = fullfile(baseDir, 'PIV_2026-06-24');
    outRoot = fullfile(baseDir, 'TKS_5 Compare', 'TKS-5_cm_All_1_to_8_Spatiotemporal');

    nExp = 8;
    % Kita uji beberapa ambang deteksi shear strain \gamma_xy di Y≈700-710 px (L05):
    %   1) Ambang sensitif awal (onset di atas noise lantai): \gamma_xy >= 0.0025
    %   2) Ambang deadband standar GRAIN: \gamma_xy >= 0.0035
    %   3) Ambang lokalisasi kuat (50% dari puncak L05): \gamma_xy >= 0.0050
    thr_onset    = 0.0025;
    thr_deadband = 0.0035;
    thr_strong   = 0.0050;

    expID          = cell(nExp, 1);
    nFramesPIV     = nan(nExp, 1);
    xFault_L05     = nan(nExp, 1);
    f_NUC_L14      = nan(nExp, 1); % Onset di akar ramp L14 (Y=303.5 px)
    f_MID_L10      = nan(nExp, 1); % Onset di tengah L10 (Y=483.5 px)
    f_FSR_Onset    = nan(nExp, 1); % Pertama kali \gamma_xy >= 0.0025 di Y≈700-710 px
    f_FSR_Deadband = nan(nExp, 1); % Pertama kali \gamma_xy >= 0.0035 (Deadband) di Y≈700-710 px
    f_FSR_Strong   = nan(nExp, 1); % Pertama kali \gamma_xy >= 0.0050 di Y≈700-710 px
    f_FSR_Peak     = nan(nExp, 1); % Frame saat \gamma_xy mencapai puncak pertama/utama di Y≈700-710 px
    raw_FSR_Deadband = nan(nExp, 1); % Nomor foto asli (raw frame index) saat FSR (deadband)
    shr_at_F1      = nan(nExp, 1);
    shr_at_FSR     = nan(nExp, 1);
    shr_Max_L05    = nan(nExp, 1);

    shrCurves_L05  = cell(nExp, 1);
    shrCurves_L10  = cell(nExp, 1);
    shrCurves_L14  = cell(nExp, 1);
    rawIdxCell     = cell(nExp, 1);

    fprintf('====================================================================================================\n');
    fprintf('🎯 DETEKSI FRAME TERBENTUKNYA FSR (FAULT SURFACE RUPTURE) PADA Y ≈ 700-710 px (GARIS L05)\n');
    fprintf('====================================================================================================\n');

    for e = 1:nExp
        expLabel = sprintf('TKS-5_cm-%d', e);
        expID{e} = expLabel;
        matFile = fullfile(outRoot, expLabel, sprintf('%s_20Lines_Kymograph_Matrices.mat', expLabel));
        S = load(matFile);

        % Cek juga bg_images_index di file PIV .mat untuk memetakan Frame PIV -> Frame Foto Mentah
        dPiv = dir(fullfile(pivDir, sprintf('%s-NOVL-S1-*-4p20px.mat', expLabel)));
        Spiv = load(fullfile(dPiv(1).folder, dPiv(1).name), 'bg_images_index');
        if isfield(Spiv, 'bg_images_index') && ~isempty(Spiv.bg_images_index)
            rawIdx = double(Spiv.bg_images_index(:)');
        else
            rawIdx = 1:size(S.kymoShear{5}, 2);
        end
        rawIdxCell{e} = rawIdx;

        xSample = S.xSample;
        Ms05 = S.kymoShear{5};  % Garis L05: Y_Ax = 708.5 px (~700 px, dekat permukaan)
        Ms06 = S.kymoShear{6};  % Garis L06: Y_Ax = 663.5 px
        Ms10 = S.kymoShear{10}; % Garis L10: Y_Ax = 483.5 px (tengah)
        Ms14 = S.kymoShear{14}; % Garis L14: Y_Ax = 303.5 px (akar ramp)
        nF = size(Ms05, 2);
        nFramesPIV(e) = nF;

        xf05 = S.xFaultLine(5);
        xf10 = S.xFaultLine(10);
        xf14 = S.xFaultLine(14);
        xFault_L05(e) = xf05;

        % Ambil kurva waktu (time-series) nilai puncak positif \gamma_xy di koridor inti sesar
        % pada L05 (Y=708.5 px, koridor X_sesar ± 48 px)
        cor05 = abs(xSample - xf05) <= 48;
        cor10 = abs(xSample - xf10) <= 48;
        cor14 = abs(xSample - xf14) <= 48;

        c05 = max(Ms05(cor05, :), [], 1, 'omitnan');
        c10 = max(Ms10(cor10, :), [], 1, 'omitnan');
        c14 = max(Ms14(cor14, :), [], 1, 'omitnan');

        shrCurves_L05{e} = c05;
        shrCurves_L10{e} = c10;
        shrCurves_L14{e} = c14;

        shr_at_F1(e) = c05(1);
        [shr_Max_L05(e), f_FSR_Peak(e)] = max(c05);

        % Deteksi frame pertama kali melewati ambang di L14 (akar), L10 (tengah), dan L05 (permukaan = FSR)
        i14 = find(c14 >= thr_deadband, 1, 'first');
        if ~isempty(i14), f_NUC_L14(e) = i14; end

        i10 = find(c10 >= thr_deadband, 1, 'first');
        if ~isempty(i10), f_MID_L10(e) = i10; end

        iOnset = find(c05 >= thr_onset, 1, 'first');
        if ~isempty(iOnset), f_FSR_Onset(e) = iOnset; end

        % Untuk FSR Deadband (>= 0.0035): cari frame pertama di mana sinyal bertahan
        % (atau minimal >= 0.0035 dan diikuti aktivitas sesar)
        iDb = find(c05 >= thr_deadband, 1, 'first');
        if ~isempty(iDb)
            f_FSR_Deadband(e) = iDb;
            shr_at_FSR(e) = c05(iDb);
            if iDb <= numel(rawIdx)
                raw_FSR_Deadband(e) = rawIdx(iDb);
            end
        end

        iStr = find(c05 >= thr_strong, 1, 'first');
        if ~isempty(iStr), f_FSR_Strong(e) = iStr; end

        fprintf('\n--- [%d] %s (nFrames PIV = %d | X_Sesar L05 = %.0f px) ---\n', e, expLabel, nF, xf05);
        fprintf('    Frame PIV  : ');
        for f = 1:min(12, nF), fprintf('  F%02d  ', f); end
        fprintf('\n    L14 (Y=304): ');
        for f = 1:min(12, nF), fprintf('%+0.4f ', c14(f)); end
        fprintf('\n    L10 (Y=484): ');
        for f = 1:min(12, nF), fprintf('%+0.4f ', c10(f)); end
        fprintf('\n    L05 (Y=709): ');
        for f = 1:min(12, nF), fprintf('%+0.4f ', c05(f)); end
        fprintf('\n    => NUC (L14/L10 >= 0.0035): F%02d -> F%02d | FSR @ Y≈709px: Onset(>=0.0025)=F%02d, Deadband(>=0.0035)=F%02d (Foto Asli #%d), Kuat(>=0.0050)=F%02d\n', ...
            f_NUC_L14(e), f_MID_L10(e), f_FSR_Onset(e), f_FSR_Deadband(e), raw_FSR_Deadband(e), f_FSR_Strong(e));
    end

    T_fsr = table((1:nExp)', expID, nFramesPIV, xFault_L05, f_NUC_L14, f_MID_L10, ...
        f_FSR_Onset, f_FSR_Deadband, raw_FSR_Deadband, f_FSR_Strong, f_FSR_Peak, ...
        shr_at_F1, shr_at_FSR, shr_Max_L05, ...
        'VariableNames', {'Exp_No', 'Experiment_ID', 'Active_PIV_Frames', 'X_Fault_L05_px', ...
        'Frame_NUC_Root_L14', 'Frame_Mid_L10', 'Frame_FSR_Onset_0025', 'Frame_FSR_Deadband_0035', ...
        'RawPhoto_at_FSR', 'Frame_FSR_Strong_0050', 'Frame_Peak_Shear_L05', ...
        'Shear_L05_at_F01', 'Shear_L05_at_FSR', 'Max_Shear_L05'});

    fprintf('\n====================================================================================================\n');
    fprintf('📋 TABEL RINGKASAN DETEKSI FRAME FSR (Y ≈ 700-710 px / GARIS L05) LINTAS 8 EKSPERIMEN:\n');
    fprintf('====================================================================================================\n');
    disp(T_fsr);

    outCsv = fullfile(outRoot, 'TKS-5_cm_All_1_to_8_FSR_Detection_Y700px.csv');
    writetable(T_fsr, outCsv);

    % Render Grafik Time-Series Propagasi Sesar dari Bawah (L14 -> L10) ke Permukaan (L05 Y≈709px = FSR)
    fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2400 1650]);
    try, theme(fig, 'light'); catch, end
    tl = tiledlayout(fig, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, 'DETEKSI FRAME TERBENTUKNYA FSR (FAULT SURFACE RUPTURE) PADA GARIS Y \approx 709 px (L05): TKS-5\_cm-1 s/d 8', ...
        'FontSize', 15, 'FontWeight', 'bold', 'Color', 'k');

    for e = 1:nExp
        ax = nexttile(tl, e); hold(ax, 'on');
        nF = nFramesPIV(e);
        c14 = shrCurves_L14{e};
        c10 = shrCurves_L10{e};
        c05 = shrCurves_L05{e};

        h14 = plot(ax, 1:nF, c14, ':k', 'LineWidth', 1.6);
        h10 = plot(ax, 1:nF, c10, '--r', 'LineWidth', 1.9);
        h05 = plot(ax, 1:nF, c05, '-', 'Color', [0.0 0.45 0.85], 'LineWidth', 2.6);

        yline(ax, thr_deadband, '--', 'Color', [0.1 0.65 0.2], 'LineWidth', 1.5, ...
            'Label', 'Ambang Deteksi FSR (\gamma_{xy} = +0.0035)', 'LabelHorizontalAlignment', 'right', 'FontWeight', 'bold');
        yline(ax, thr_strong, ':', 'Color', [0.85 0.4 0.0], 'LineWidth', 1.2, ...
            'Label', 'Lokalisasi Kuat (+0.0050)', 'LabelHorizontalAlignment', 'right');

        % Tandai titik FSR Deadband (>= 0.0035) dan FSR Strong (>= 0.0050)
        fDb = f_FSR_Deadband(e);
        if isfinite(fDb)
            plot(ax, fDb, c05(fDb), 'o', 'MarkerSize', 10, 'MarkerFaceColor', [0.1 0.75 0.25], 'MarkerEdgeColor', 'k', 'LineWidth', 1.8);
            xline(ax, fDb, '-', 'Color', [0.1 0.65 0.2], 'LineWidth', 1.6);
            text(ax, fDb + 0.4, max(0.018, c05(fDb) + 0.004), ...
                sprintf('FSR = F%02d (Foto #%d)\n\\gamma_{xy}=%+.4f', fDb, raw_FSR_Deadband(e), c05(fDb)), ...
                'Color', [0.05 0.45 0.15], 'BackgroundColor', [0.92 1.0 0.92], 'EdgeColor', [0.1 0.65 0.2], ...
                'FontWeight', 'bold', 'FontSize', 8.5, 'Margin', 2);
        end

        fSt = f_FSR_Strong(e);
        if isfinite(fSt) && fSt ~= fDb
            plot(ax, fSt, c05(fSt), 's', 'MarkerSize', 8.5, 'MarkerFaceColor', [1 0.8 0.1], 'MarkerEdgeColor', 'k', 'LineWidth', 1.4);
        end

        grid(ax, 'on'); xlim(ax, [1 nF]); ylim(ax, [-0.002, 0.046]);
        title(ax, sprintf('[%d] %s — NUC (Bawah/Tengah): F%02d | FSR (Permukaan Y=709px): Frame PIV F%02d (Strong: F%02d)', ...
            e, strrep(expID{e}, '_', '\_'), min(f_NUC_L14(e), f_MID_L10(e)), fDb, fSt), ...
            'FontWeight', 'bold', 'FontSize', 10.5);
        ylabel(ax, 'Peak +\gamma_{xy}', 'FontWeight', 'bold');
        if e >= 7, xlabel(ax, 'Active PIV Frame Index (F)', 'FontWeight', 'bold'); end
        if e == 1
            lg = legend(ax, [h05, h10, h14], {'Garis Permukaan L05 (Y=709 px) [Penentu FSR]', 'Garis Tengah L10 (Y=484 px)', 'Garis Akar Ramp L14 (Y=304 px)'}, ...
                'Location', 'northwest', 'FontSize', 8.5);
            lg.Color = [1 1 1]; lg.TextColor = [0 0 0];
        end
        ax.Color = [1 1 1]; ax.XColor = [0.1 0.1 0.1]; ax.YColor = [0.1 0.1 0.1]; box(ax, 'on');
    end

    outFig = fullfile(outRoot, 'TKS-5_cm_All_1_to_8_FSR_Detection_Chart.jpg');
    exportgraphics(fig, outFig, 'Resolution', 150, 'BackgroundColor', 'white');
    close(fig);
    fprintf('\n✅ Grafik deteksi FSR disimpan di: %s\n', outFig);
end
