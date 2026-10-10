function masterTable = run_batch_TKS5_cm_1_to_8()
% RUN_BATCH_TKS5_CM_1_TO_8  Eksekusi batch deteksi patahan spasiotemporal
% 20 garis horizontal (Kymograph axPSG & Time-Series axPOT) untuk seluruh
% 8 eksperimen TKS-5_cm-1 s/d TKS-5_cm-8 TANPA mengulang analisis PIV.
%
% Seluruh perhitungan menggunakan hasil PIV yang sudah ada di:
%   /Volumes/Tora 400gb/EXP_coll/TKS/5 cm/PIV_2026-06-24/TKS-5_cm-*-NOVL-S1-*-4p20px.mat
% serta metadata (nFrames mentah & jitter) dari:
%   /Volumes/Tora 400gb/EXP_coll/TKS/5 cm/TKS-5_cm-*.mat

    here = fileparts(mfilename('fullpath'));
    cd(here);
    if isfile(fullfile(here, 'grain_setup.m'))
        grain_setup();
    end

    baseDir = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm';
    pivDir  = fullfile(baseDir, 'PIV_2026-06-24');
    outRoot = fullfile(baseDir, 'TKS_5 Compare', 'TKS-5_cm_All_1_to_8_Spatiotemporal');
    if ~isfolder(outRoot), mkdir(outRoot); end

    nExp = 8;
    nLines = 20;
    spacingPx = 16;
    deadband = 0.0035;

    fprintf('========================================================================================\n');
    fprintf('🚀 BATCH SPATIOTEMPORAL KYMOGRAPH FAULT DETECTION: TKS-5_cm-1 s/d TKS-5_cm-8 (NO RE-PIV)\n');
    fprintf('========================================================================================\n');

    % Variabel penampung ringkasan master 8 eksperimen
    expNames          = cell(nExp, 1);
    pivFiles          = cell(nExp, 1);
    rawFrameCount     = nan(nExp, 1);
    droppedFrameCount = nan(nExp, 1);
    droppedFrameStr   = cell(nExp, 1);
    activePivFrames   = nan(nExp, 1);
    jitterRmsDx       = nan(nExp, 1);
    jitterRmsDy       = nan(nExp, 1);
    meanVelHW_Mid     = nan(nExp, 1);
    peakVelHW_Mid     = nan(nExp, 1);
    xFault_L14_Root   = nan(nExp, 1);
    xFault_L10_Mid    = nan(nExp, 1);
    xFault_L05_Y710   = nan(nExp, 1);
    xFault_L03_Top    = nan(nExp, 1);
    faultDip_Deg      = nan(nExp, 1);
    maxPosShear_Mid   = nan(nExp, 1);
    maxPosShear_Y710  = nan(nExp, 1);
    xSecondary_Mid    = nan(nExp, 1);
    valSecondary_Mid  = nan(nExp, 1);
    detachment_Y_px   = nan(nExp, 1);
    detachment_Xmax   = nan(nExp, 1);
    detachment_MinShr = nan(nExp, 1);
    toeSlump_X_Y710   = nan(nExp, 1);
    toeSlump_MinShr   = nan(nExp, 1);
    scarpMaxVy_L03    = nan(nExp, 1);

    % Cache untuk montage 4x2 lintas 8 eksperimen
    montageData = cell(nExp, 1);

    for e = 1:nExp
        expLabel = sprintf('TKS-5_cm-%d', e);
        expNames{e} = expLabel;
        rawMatPath = fullfile(baseDir, sprintf('%s.mat', expLabel));
        dPiv = dir(fullfile(pivDir, sprintf('%s-NOVL-S1-*-4p20px.mat', expLabel)));
        if isempty(dPiv)
            error('File PIV 4p20px tidak ditemukan untuk %s', expLabel);
        end
        pivMatPath = fullfile(dPiv(1).folder, dPiv(1).name);
        pivFiles{e} = dPiv(1).name;

        expOutDir = fullfile(outRoot, expLabel);
        if ~isfolder(expOutDir), mkdir(expOutDir); end

        fprintf('\n----------------------------------------------------------------------------------------\n');
        fprintf('▶️ [%d/8] Memproses %s | File PIV: %s\n', e, expLabel, dPiv(1).name);
        fprintf('----------------------------------------------------------------------------------------\n');

        % 1. Baca metadata ringan dari raw .mat (tanpa mengekstrak/menjalankan PIV ulang)
        if isfile(rawMatPath)
            S_raw = load(rawMatPath, 'prep');
            if isfield(S_raw, 'prep')
                prep = S_raw.prep;
                if isfield(prep, 'nFrames') && ~isempty(prep.nFrames)
                    rawFrameCount(e) = prep.nFrames;
                elseif isfield(prep, 'raw') && isfield(prep.raw, 'blobs')
                    rawFrameCount(e) = numel(prep.raw.blobs);
                end
                if isfield(prep, 'jitter') && isstruct(prep.jitter) && isfield(prep.jitter, 'dx')
                    jitterRmsDx(e) = std(double(prep.jitter.dx(:)), 'omitnan');
                    jitterRmsDy(e) = std(double(prep.jitter.dy(:)), 'omitnan');
                end
            end
            clear S_raw prep;
        end

        % 2. Muat kontainer PIV yang sudah ada
        S_piv = load(pivMatPath);
        if isfield(S_piv, 'qpiv_dropped_frames') && ~isempty(S_piv.qpiv_dropped_frames)
            df = S_piv.qpiv_dropped_frames(:)';
            droppedFrameCount(e) = numel(df);
            droppedFrameStr{e}   = i_formatRanges(df);
        else
            droppedFrameCount(e) = 0;
            droppedFrameStr{e}   = 'tidak ada';
        end

        dataFull = pivcore.data.buildDataset(S_piv);
        nF = dataFull.nFrames;
        activePivFrames(e) = nF;
        x1 = pivcore.data.safeFrame(dataFull.x, 1);
        y1 = pivcore.data.safeFrame(dataFull.y, 1);
        xExt = [min(x1(:)), max(x1(:))];
        yExt = [min(y1(:)), max(y1(:))];
        yMid = (yExt(1) + yExt(2)) / 2;
        yF   = (yExt(2) + yExt(1)) - y1;
        xv   = x1(1, :);
        yv   = y1(:, 1);

        % 3. Precompute |V|, U, Vy (+ ke atas), Cleaned Shear Strain (Med 3x3 + Gauss 1.8)
        velStack      = cell(1, nF);
        uStack        = cell(1, nF);
        vyStack       = cell(1, nF);
        shrCleanStack = cell(1, nF);
        shrDbStack    = cell(1, nF);

        for f = 1:nF
            [U, V] = pivcore.data.pickAnyVel(dataFull, f);
            uStack{f}   = U;
            vyStack{f}  = -V; % positif ke atas (uplift)
            velStack{f} = hypot(U, V);
            Zraw = pivcore.data.computeShearRate(dataFull, f, 'mode', 'engineering');
            Zcln = imgaussfilt(medfilt2(Zraw, [3 3], 'symmetric'), 1.8);
            Zdb  = Zcln;
            Zdb(abs(Zdb) < deadband) = 0;
            shrCleanStack{f} = Zcln;
            shrDbStack{f}    = Zdb;
        end

        % 4. Definisi 20 garis horizontal L01..L20 (2.5% s/d 97.5% dari atas)
        posPct = linspace(2.5, 97.5, nLines)';
        yRow   = yExt(1) + (posPct / 100) * (yExt(2) - yExt(1));
        yAx    = 2 * yMid - yRow;

        % Rentang frame aktif utama untuk statistik spasial
        fAct = max(2, round(0.12 * nF)) : max(2, round(0.88 * nF));
        fMid = max(2, round(0.30 * nF)) : max(2, round(0.75 * nF));

        lineID       = cell(nLines, 1);
        meanVelHW    = nan(nLines, 1);
        peakPosShr   = nan(nLines, 1);
        xPosShr      = nan(nLines, 1);
        peak2PosShr  = nan(nLines, 1);
        x2PosShr     = nan(nLines, 1);
        peakNegShr   = nan(nLines, 1);
        xNegShr      = nan(nLines, 1);
        xVelDrop     = nan(nLines, 1);
        maxVyLine    = nan(nLines, 1);
        zoneLabel    = cell(nLines, 1);

        kymoVel   = cell(nLines, 1);
        kymoShear = cell(nLines, 1);
        kymoVy    = cell(nLines, 1);
        xSample   = [];

        for k = 1:nLines
            lineID{k} = sprintf('L%02d', k);
            p1 = [xExt(1), yAx(k)];
            p2 = [xExt(2), yAx(k)];
            [Mv, ~, xPts, ~]  = i_sampleStackAlongImageLine(x1, y1, velStack, p1, p2, spacingPx);
            [Ms, ~, ~, ~]     = i_sampleStackAlongImageLine(x1, y1, shrCleanStack, p1, p2, spacingPx);
            [Mvy, ~, ~, ~]    = i_sampleStackAlongImageLine(x1, y1, vyStack, p1, p2, spacingPx);
            kymoVel{k}   = Mv;
            kymoShear{k} = Ms;
            kymoVy{k}    = Mvy;
            xSample      = xPts;

            meanV_x = mean(Mv(:, fAct), 2, 'omitnan');
            maxS_x  = prctile(Ms(:, fAct), 90, 2);
            minS_x  = prctile(Ms(:, fAct), 10, 2);
            maxVy_x = prctile(Mvy(:, fAct), 95, 2);

            hwMask = (xPts >= 300) & (xPts <= 900);
            meanVelHW(k) = mean(meanV_x(hwMask), 'omitnan');

            intMask = (xPts >= 600) & (xPts <= 2400);
            sPos = maxS_x; sPos(~intMask) = -Inf;
            [peakPosShr(k), idxP] = max(sPos);
            xPosShr(k) = xPts(idxP);

            % Cari Peak ke-2 (+Shear) berjarak >= 180 px dari Peak 1
            sPos2 = sPos;
            sPos2(abs(xPts - xPosShr(k)) < 180) = -Inf;
            [peak2PosShr(k), idxP2] = max(sPos2);
            x2PosShr(k) = xPts(idxP2);

            detMask = (xPts >= 150) & (xPts <= 2400);
            sNeg = minS_x; sNeg(~detMask) = Inf;
            [peakNegShr(k), idxN] = min(sNeg);
            xNegShr(k) = xPts(idxN);

            maxVyLine(k) = max(maxVy_x(intMask), [], 'omitnan');

            if meanVelHW(k) > 0.8
                dCand = find((xPts' > 650) & (meanV_x < 0.45 * meanVelHW(k)), 1, 'first');
                if ~isempty(dCand), xVelDrop(k) = xPts(dCand); end
            end
        end

        % 5. Pelacakan Koheren Jejak Sesar Utama (L03 .. L15) dari anchor bagian tengah (L08..L12)
        ZmeanMid = mean(cat(3, shrCleanStack{fMid}), 3);
        anchorLines = 8:12;
        [~, bestA] = max(peakPosShr(anchorLines));
        kAnchor = anchorLines(bestA);
        xAnchor = xPosShr(kAnchor);

        xFaultLine   = nan(nLines, 1);
        valFaultLine = nan(nLines, 1);
        xFaultLine(kAnchor)   = xAnchor;
        valFaultLine(kAnchor) = peakPosShr(kAnchor);

        % Lacak ke atas (kAnchor-1 turun ke 3)
        xPrev = xAnchor;
        for k = (kAnchor-1):-1:3
            [~, rIdx] = min(abs(yv - yRow(k)));
            rowVals = prctile(kymoShear{k}(:, fAct), 90, 2)';
            % Koridor koheren: sekitar xPrev (-80 s/d +220 px karena sesar naik miring ke kanan)
            msk = (xSample >= max(650, xPrev - 90)) & (xSample <= min(2400, xPrev + 220));
            rowM = rowVals; rowM(~msk) = -Inf;
            [mxV, cIdx] = max(rowM);
            if isfinite(mxV) && mxV >= 0.0020
                xFaultLine(k)   = xSample(cIdx);
                valFaultLine(k) = mxV;
                xPrev = xFaultLine(k);
            end
        end

        % Lacak ke bawah (kAnchor+1 naik ke 15)
        xPrev = xAnchor;
        for k = (kAnchor+1):15
            rowVals = prctile(kymoShear{k}(:, fAct), 90, 2)';
            % Koridor koheren: sekitar xPrev (-220 s/d +80 px karena sesar berakar ke kiri bawah)
            msk = (xSample >= max(550, xPrev - 220)) & (xSample <= min(2300, xPrev + 90));
            rowM = rowVals; rowM(~msk) = -Inf;
            [mxV, cIdx] = max(rowM);
            if isfinite(mxV) && mxV >= 0.0020
                xFaultLine(k)   = xSample(cIdx);
                valFaultLine(k) = mxV;
                xPrev = xFaultLine(k);
            end
        end

        % Klasifikasi zona anatomi tiap garis L01..L20
        for k = 1:nLines
            if meanVelHW(k) < 0.35 && posPct(k) > 78
                zoneLabel{k} = 'Base / Ruler (Stationary)';
            elseif peakNegShr(k) < -0.022 && xNegShr(k) < 1150 && posPct(k) > 68
                zoneLabel{k} = 'Basal Detachment Horizon';
            elseif isfinite(xFaultLine(k))
                if peakNegShr(k) < -0.009 && xNegShr(k) > xFaultLine(k)
                    zoneLabel{k} = 'Upper Sand + Fore-Thrust & Toe Slump';
                else
                    zoneLabel{k} = 'Active Fore-Thrust Fault Core';
                end
            elseif posPct(k) < 16
                zoneLabel{k} = 'Top Air / Fault Scarp Crest';
            else
                zoneLabel{k} = 'Sand Pack / Transition';
            end
        end

        % Regresi sudut kemiringan sesar (Dip Angle) dari garis valid L04..L14
        validFit = false(nLines, 1);
        validFit(4:14) = isfinite(xFaultLine(4:14)) & (valFaultLine(4:14) >= 0.0030);
        if nnz(validFit) >= 3
            pFit = polyfit(yAx(validFit), xFaultLine(validFit), 1); % dX / dY
            faultDip_Deg(e) = atand(1 / abs(pFit(1)));
        end

        % Ringkasan metrik kunci eksperimen ke-e
        meanVelHW_Mid(e)   = meanVelHW(10);
        peakVelHW_Mid(e)   = max(kymoVel{10}(:), [], 'omitnan');
        xFault_L14_Root(e) = xFaultLine(14);
        xFault_L10_Mid(e)  = xFaultLine(10);
        xFault_L05_Y710(e) = xFaultLine(5);
        xFault_L03_Top(e)  = xFaultLine(3);
        maxPosShear_Mid(e) = valFaultLine(10);
        maxPosShear_Y710(e)= valFaultLine(5);
        xSecondary_Mid(e)  = x2PosShr(10);
        valSecondary_Mid(e)= peak2PosShr(10);

        % Basal detachment (di antara L15..L17)
        detCand = 15:17;
        [minDetVal, idxDetRel] = min(peakNegShr(detCand));
        idxDet = detCand(idxDetRel);
        detachment_Y_px(e)   = yAx(idxDet);
        detachment_Xmax(e)   = xVelDrop(idxDet);
        if isnan(detachment_Xmax(e)), detachment_Xmax(e) = xFaultLine(14); end
        detachment_MinShr(e) = minDetVal;

        % Toe slump / flexure di depan sesar pada L05 (Y=710 px)
        ms5 = min(kymoShear{5}(:, fAct), [], 2, 'omitnan');
        mskToe = (xSample > xFaultLine(5) + 60) & (xSample <= xFaultLine(5) + 350);
        if any(mskToe)
            ms5_t = ms5; ms5_t(~mskToe) = Inf;
            [vToe, iToe] = min(ms5_t);
            if isfinite(vToe) && vToe < -0.005
                toeSlump_X_Y710(e) = xSample(iToe);
                toeSlump_MinShr(e) = vToe;
            end
        end
        scarpMaxVy_L03(e) = maxVyLine(3);

        % Simpan Tabel CSV 20 Garis per Eksperimen
        T_lines = table((1:nLines)', lineID, posPct, yAx, yRow, meanVelHW, ...
            xFaultLine, valFaultLine, x2PosShr, peak2PosShr, xNegShr, peakNegShr, xVelDrop, maxVyLine, zoneLabel, ...
            'VariableNames', {'Line_Index', 'Line_ID', 'Pos_Pct_From_Top', 'Y_AxMain_px', 'Y_GridRow_px', ...
            'Mean_Vel_HW', 'X_ForeThrust_px', 'Peak_Pos_Shear', 'X_Secondary_px', 'Peak2_Pos_Shear', ...
            'X_NegShear_px', 'Peak_Neg_Shear', 'X_VelDrop_px', 'Max_Vy_Uplift', 'Detected_Zone'});
        csvLinePath = fullfile(expOutDir, sprintf('%s_20Lines_Spatiotemporal_Detection.csv', expLabel));
        writetable(T_lines, csvLinePath);

        matOutPath = fullfile(expOutDir, sprintf('%s_20Lines_Kymograph_Matrices.mat', expLabel));
        save(matOutPath, 'T_lines', 'kymoVel', 'kymoShear', 'kymoVy', 'xSample', 'yAx', 'yRow', 'posPct', 'xFaultLine', 'valFaultLine');

        fprintf('   ✅ Sesar Utama: L14(Y=%.0f)->X=%.0f | L10(Y=%.0f)->X=%.0f | L05(Y=%.0f)->X=%.0f | Dip=%.1f deg | Detachment Y=%.0f px\n', ...
            yAx(14), xFault_L14_Root(e), yAx(10), xFault_L10_Mid(e), yAx(5), xFault_L05_Y710(e), faultDip_Deg(e), detachment_Y_px(e));

        % =================================================================
        % RENDER 3 JPG VERIFIKASI PER EKSPERIMEN
        % =================================================================
        refFrame = max(2, round(0.50 * nF));
        bgRef  = pivcore.data.bgAt(dataFull, refFrame);
        rgbRef = pivcore.util.grayCLAHE(bgRef, true, true);
        [Uref, Vref] = pivcore.data.pickAnyVel(dataFull, refFrame);
        Zref = shrDbStack{refFrame};
        validF = isfinite(xFaultLine);

        % Simpan ke cache montage
        montageData{e} = struct('expLabel', expLabel, 'refFrame', refFrame, 'nF', nF, ...
            'xExt', xExt, 'yExt', yExt, 'x1', x1, 'yF', yF, 'rgbRef', rgbRef, ...
            'Uref', Uref, 'Vref', Vref, 'Zref', Zref, 'yAx', yAx, ...
            'xFaultLine', xFaultLine, 'valFaultLine', valFaultLine, 'faultDip', faultDip_Deg(e), ...
            'idxDet', idxDet, 'detXmax', detachment_Xmax(e), ...
            'xSample', xSample, 'kymoVel5', kymoVel{5}, 'kymoShr5', kymoShear{5}, ...
            'kymoVel10', kymoVel{10}, 'kymoShr10', kymoShear{10});

        % --- JPG 1: 20 Garis Horizontal + Peta Deteksi Sesar ---
        fig1 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2300 1550]);
        i_forceLightFig(fig1);
        tl1 = tiledlayout(fig1, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

        ax1 = nexttile(tl1, 1); hold(ax1, 'on');
        image(ax1, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgbRef);
        set(ax1, 'YDir', 'normal'); axis(ax1, 'image'); xlim(ax1, xExt); ylim(ax1, yExt);
        cmapLines = turbo(nLines);
        for k = 1:nLines
            plot(ax1, xExt, [yAx(k) yAx(k)], '-', 'Color', [0 0 0 0.55], 'LineWidth', 2.0);
            plot(ax1, xExt, [yAx(k) yAx(k)], '--', 'Color', cmapLines(k, :), 'LineWidth', 1.4);
            text(ax1, xExt(1) + 12, yAx(k), sprintf(' L%02d (%4.1f%%) ', k, posPct(k)), ...
                'Color', 'w', 'BackgroundColor', [0 0 0 0.75], 'FontWeight', 'bold', 'FontSize', 8, ...
                'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left', 'Margin', 1);
            text(ax1, xExt(2) - 12, yAx(k), sprintf(' L%02d | Y=%.0f px ', k, yAx(k)), ...
                'Color', [1 0.95 0.3], 'BackgroundColor', [0 0 0 0.75], 'FontWeight', 'bold', 'FontSize', 8, ...
                'VerticalAlignment', 'middle', 'HorizontalAlignment', 'right', 'Margin', 1);
        end
        title(ax1, sprintf('%s (Frame %d/%d) — Citra Grayscale CLAHE + 20 Garis Scanline Horizontal (L01 Atas \\rightarrow L20 Bawah)', ...
            strrep(expLabel, '_', '\_'), refFrame, nF), 'FontSize', 12.5, 'FontWeight', 'bold');
        ylabel(ax1, 'Posisi Y (px)', 'FontWeight', 'bold');
        i_styleLightAx(ax1);

        ax2 = nexttile(tl1, 2); hold(ax2, 'on');
        imagesc(ax2, xExt, [yExt(2) yExt(1)], Zref);
        colormap(ax2, jet(256)); clim(ax2, [-0.02, 0.02]);
        image(ax2, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgbRef, 'AlphaData', 0.33);
        pivcore.util.drawGlyphs(ax2, x1, yF, Uref, -Vref, 12, 1.1, [1 1 1]);
        for k = 1:nLines
            plot(ax2, xExt, [yAx(k) yAx(k)], '--', 'Color', [0.1 0.1 0.1 0.60], 'LineWidth', 1.1);
            text(ax2, xExt(1) + 12, yAx(k), sprintf(' L%02d (Y=%.0f) ', k, yAx(k)), ...
                'Color', 'w', 'BackgroundColor', [0 0 0 0.75], 'FontWeight', 'bold', 'FontSize', 8, ...
                'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left', 'Margin', 1);
            if isfinite(xFaultLine(k))
                plot(ax2, xFaultLine(k), yAx(k), 'o', 'MarkerSize', 8.5, ...
                    'MarkerFaceColor', [1 0.95 0], 'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
                text(ax2, xExt(2) - 12, yAx(k), sprintf(' L%02d | X_{sesar}=%.0f px (\\gamma_{xy}=%+.3f) ', k, xFaultLine(k), valFaultLine(k)), ...
                    'Color', [0.65 1 0.65], 'BackgroundColor', [0 0 0 0.78], 'FontWeight', 'bold', 'FontSize', 8, ...
                    'VerticalAlignment', 'middle', 'HorizontalAlignment', 'right', 'Margin', 1);
            elseif k == idxDet
                xDetEnd = min(2000, max(700, detachment_Xmax(e)));
                plot(ax2, [200 xDetEnd], [yAx(k) yAx(k)], '-', 'Color', [0 1 1], 'LineWidth', 3.0);
                text(ax2, xExt(2) - 12, yAx(k), sprintf(' L%02d | Detachment Basal X=200..%.0f px (\\gamma_{xy}=%+.3f) ', k, xDetEnd, detachment_MinShr(e)), ...
                    'Color', [0.4 0.95 1], 'BackgroundColor', [0 0 0 0.78], 'FontWeight', 'bold', 'FontSize', 8, ...
                    'VerticalAlignment', 'middle', 'HorizontalAlignment', 'right', 'Margin', 1);
            end
        end
        if any(validF)
            plot(ax2, xFaultLine(validF), yAx(validF), '-y', 'LineWidth', 2.4);
        end
        set(ax2, 'YDir', 'normal'); axis(ax2, 'image'); xlim(ax2, xExt); ylim(ax2, yExt);
        cb2 = colorbar(ax2, 'eastoutside'); cb2.Label.String = 'Cleaned \gamma_{xy} [\pm0.02]'; cb2.Color = 'k';
        title(ax2, sprintf('%s (Frame %d/%d) — Deteksi Spasiotemporal 20 Garis (Jejak Sesar Kuning \\theta \\approx %.1f^\\circ & Detachment Cyan)', ...
            strrep(expLabel, '_', '\_'), refFrame, nF, faultDip_Deg(e)), 'FontSize', 12.5, 'FontWeight', 'bold');
        xlabel(ax2, 'Posisi X sepanjang Sandbox (px)', 'FontWeight', 'bold');
        ylabel(ax2, 'Posisi Y (px)', 'FontWeight', 'bold');
        i_styleLightAx(ax2);

        exportgraphics(fig1, fullfile(expOutDir, sprintf('%s_20_Garis_Horizontal_L01_L20.jpg', expLabel)), 'Resolution', 140, 'BackgroundColor', 'white');
        close(fig1);

        % --- JPG 2: Dashboard Kymograph (axPSG) & Time-Series (axPOT) pada L05 (Y≈710px) & L10 (Y≈484px) ---
        fig2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2300 1650]);
        i_forceLightFig(fig2);
        tl2 = tiledlayout(fig2, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        title(tl2, sprintf('%s — Kymograph (axPSG) & Time-Series (axPOT) dari Data PIV (%d Frame Aktif, Dropped: [%s])', ...
            strrep(expLabel, '_', '\_'), nF, droppedFrameStr{e}), 'FontSize', 14, 'FontWeight', 'bold', 'Color', 'k');

        % [1,1] Kymograph |V| L05 (Y≈710px)
        axK1 = nexttile(tl2, 1);
        imagesc(axK1, 1:nF, xSample, kymoVel{5}); colormap(axK1, turbo(256)); clim(axK1, [0 max(4, prctile(kymoVel{5}(:), 98))]); set(axK1, 'YDir', 'normal');
        hold(axK1, 'on');
        if isfinite(xFaultLine(5))
            yline(axK1, xFaultLine(5), '--w', sprintf('Sesar L05 X ≈ %.0f px', xFaultLine(5)), 'LineWidth', 1.8, 'FontWeight', 'bold');
        end
        hold(axK1, 'off');
        ylabel(axK1, 'Posisi X (px)', 'FontWeight', 'bold');
        title(axK1, sprintf('[1A] Kymograph |V| — Garis L05 (Y = %.0f px)', yAx(5)), 'FontWeight', 'bold');
        cbK1 = colorbar(axK1); cbK1.Label.String = '|V| (px/step)'; cbK1.Color = 'k';
        i_styleLightAx(axK1);

        % [1,2] Kymograph \gamma_xy L05 (Y≈710px)
        axK2 = nexttile(tl2, 2);
        imagesc(axK2, 1:nF, xSample, kymoShear{5}); colormap(axK2, jet(256)); clim(axK2, [-0.02 0.02]); set(axK2, 'YDir', 'normal');
        hold(axK2, 'on');
        if isfinite(xFaultLine(5))
            yline(axK2, xFaultLine(5), '--k', sprintf('Fore-Thrust X ≈ %.0f px', xFaultLine(5)), 'LineWidth', 1.8, 'FontWeight', 'bold');
        end
        if isfinite(toeSlump_X_Y710(e))
            yline(axK2, toeSlump_X_Y710(e), ':b', sprintf('Toe Flexure/Slump X ≈ %.0f px', toeSlump_X_Y710(e)), 'LineWidth', 1.5, 'FontWeight', 'bold');
        end
        hold(axK2, 'off');
        ylabel(axK2, 'Posisi X (px)', 'FontWeight', 'bold');
        title(axK2, sprintf('[1B] Kymograph Cleaned \\gamma_{xy} — Garis L05 (Y = %.0f px)', yAx(5)), 'FontWeight', 'bold');
        cbK2 = colorbar(axK2); cbK2.Label.String = '\gamma_{xy}'; cbK2.Color = 'k';
        i_styleLightAx(axK2);

        % [2,1] Kymograph |V| L10 (Y≈484px Tengah)
        axK3 = nexttile(tl2, 3);
        imagesc(axK3, 1:nF, xSample, kymoVel{10}); colormap(axK3, turbo(256)); clim(axK3, [0 max(4, prctile(kymoVel{10}(:), 98))]); set(axK3, 'YDir', 'normal');
        hold(axK3, 'on');
        if isfinite(xFaultLine(10))
            yline(axK3, xFaultLine(10), '--w', sprintf('Sesar L10 X ≈ %.0f px', xFaultLine(10)), 'LineWidth', 1.8, 'FontWeight', 'bold');
        end
        hold(axK3, 'off');
        ylabel(axK3, 'Posisi X (px)', 'FontWeight', 'bold');
        title(axK3, sprintf('[2A] Kymograph |V| — Garis Tengah L10 (Y = %.0f px)', yAx(10)), 'FontWeight', 'bold');
        cbK3 = colorbar(axK3); cbK3.Label.String = '|V| (px/step)'; cbK3.Color = 'k';
        i_styleLightAx(axK3);

        % [2,2] Kymograph \gamma_xy L10 (Y≈484px Tengah)
        axK4 = nexttile(tl2, 4);
        imagesc(axK4, 1:nF, xSample, kymoShear{10}); colormap(axK4, jet(256)); clim(axK4, [-0.02 0.02]); set(axK4, 'YDir', 'normal');
        hold(axK4, 'on');
        if isfinite(xFaultLine(10))
            yline(axK4, xFaultLine(10), '--k', sprintf('Fore-Thrust X ≈ %.0f px', xFaultLine(10)), 'LineWidth', 1.8, 'FontWeight', 'bold');
        end
        hold(axK4, 'off');
        ylabel(axK4, 'Posisi X (px)', 'FontWeight', 'bold');
        title(axK4, sprintf('[2B] Kymograph Cleaned \\gamma_{xy} — Garis Tengah L10 (Y = %.0f px)', yAx(10)), 'FontWeight', 'bold');
        cbK4 = colorbar(axK4); cbK4.Label.String = '\gamma_{xy}'; cbK4.Color = 'k';
        i_styleLightAx(axK4);

        % [3,1] axPOT Time-Series |V| (L10 Tengah)
        axK5 = nexttile(tl2, 5); hold(axK5, 'on');
        M10v = kymoVel{10};
        for r = 1:size(M10v, 1)
            plot(axK5, 1:nF, M10v(r, :), '-', 'Color', [0.65 0.65 0.68 0.25]);
        end
        xf10 = xFaultLine(10); if isnan(xf10), xf10 = 1200; end
        isHW = (xSample >= 250) & (xSample < xf10 - 80);
        isFW = (xSample > xf10 + 120);
        hPk = plot(axK5, 1:nF, max(M10v, [], 1, 'omitnan'), '-k', 'LineWidth', 2.2);
        hHW = plot(axK5, 1:nF, mean(M10v(isHW, :), 1, 'omitnan'), '-r', 'LineWidth', 2.0);
        hFW = plot(axK5, 1:nF, mean(M10v(isFW, :), 1, 'omitnan'), '-b', 'LineWidth', 2.0);
        grid(axK5, 'on'); xlim(axK5, [1 nF]);
        xlabel(axK5, sprintf('Active PIV Frame Index (1 .. %d)', nF), 'FontWeight', 'bold');
        ylabel(axK5, '|V| (px/step)', 'FontWeight', 'bold');
        title(axK5, '[3A] axPOT Time-Series |V| — Kontras Hanging Wall (Merah) vs Footwall (Biru)', 'FontWeight', 'bold');
        lg5 = legend(axK5, [hPk, hHW, hFW], {'Peak |V|', 'Mean Hanging Wall (Kiri)', 'Mean Footwall (Kanan)'}, 'Location', 'northeast');
        lg5.Color = [1 1 1]; lg5.TextColor = [0 0 0];
        i_styleLightAx(axK5);

        % [3,2] axPOT Time-Series Shear Strain \gamma_xy: L10 vs L05
        axK6 = nexttile(tl2, 6); hold(axK6, 'on');
        xf5 = xFaultLine(5); if isnan(xf5), xf5 = xf10 + 80; end
        shrCore10 = mean(kymoShear{10}(abs(xSample - xf10) <= 32, :), 1, 'omitnan');
        shrCore05 = mean(kymoShear{5}(abs(xSample - xf5) <= 32, :), 1, 'omitnan');
        hC10 = plot(axK6, 1:nF, shrCore10, '-r', 'LineWidth', 2.2);
        hC05 = plot(axK6, 1:nF, shrCore05, '-', 'Color', [0.0 0.55 0.85], 'LineWidth', 2.2);
        yline(axK6, deadband, ':k', '+Deadband'); yline(axK6, -deadband, ':k', '-Deadband');
        grid(axK6, 'on'); xlim(axK6, [1 nF]);
        xlabel(axK6, sprintf('Active PIV Frame Index (1 .. %d)', nF), 'FontWeight', 'bold');
        ylabel(axK6, 'Cleaned Shear Strain \gamma_{xy}', 'FontWeight', 'bold');
        title(axK6, '[3B] axPOT Evolusi Geser Inti Sesar: Tengah L10 (Merah) vs Atas L05 Y=710px (Biru)', 'FontWeight', 'bold');
        lg6 = legend(axK6, [hC10, hC05], ...
            {sprintf('Inti Sesar L10 (Y=%.0f px, X≈%.0f px)', yAx(10), xf10), ...
             sprintf('Inti Sesar L05 (Y=%.0f px, X≈%.0f px)', yAx(5), xf5)}, 'Location', 'northeast');
        lg6.Color = [1 1 1]; lg6.TextColor = [0 0 0];
        i_styleLightAx(axK6);

        exportgraphics(fig2, fullfile(expOutDir, sprintf('%s_PSG_Y710px_dan_Tengah_Dashboard.jpg', expLabel)), 'Resolution', 140, 'BackgroundColor', 'white');
        close(fig2);

        % --- JPG 3: Evolusi 3 Fase (Early, Mid, Late) ---
        fig3 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2250 1700]);
        i_forceLightFig(fig3);
        tl3 = tiledlayout(fig3, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
        fEarly = max(2, round(0.18 * nF));
        fMidSt = max(2, round(0.50 * nF));
        fLate  = min(nF, max(3, round(0.88 * nF)));
        frList = [fEarly, fMidSt, fLate];
        stNames = {'FASE AWAL (Early Stage)', 'FASE MENENGAH (Mid Stage)', 'FASE AKHIR (Late Stage)'};

        title(tl3, sprintf('%s — Verifikasi Visual 3 Fase Evolusi (Frame %d, %d, %d dari %d) terhadap Jejak Sesar Spasiotemporal', ...
            strrep(expLabel, '_', '\_'), fEarly, fMidSt, fLate, nF), 'FontSize', 14, 'FontWeight', 'bold', 'Color', 'k');

        for idx = 1:3
            f = frList(idx);
            ax = nexttile(tl3, idx); hold(ax, 'on');
            bgF  = pivcore.data.bgAt(dataFull, f);
            rgbF = pivcore.util.grayCLAHE(bgF, true, true);
            [Uf, Vf] = pivcore.data.pickAnyVel(dataFull, f);
            Zf = shrDbStack{f};

            imagesc(ax, xExt, [yExt(2) yExt(1)], Zf);
            colormap(ax, jet(256)); clim(ax, [-0.02, 0.02]);
            image(ax, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgbF, 'AlphaData', 0.34);
            pivcore.util.drawGlyphs(ax, x1, yF, Uf, -Vf, 12, 1.1, [1 1 1]);

            for kk = [3, 5, 10, idxDet]
                plot(ax, xExt, [yAx(kk) yAx(kk)], '--k', 'LineWidth', 1.1);
                text(ax, xExt(1)+15, yAx(kk)+18, sprintf('L%02d (Y=%.0f px)', kk, yAx(kk)), ...
                    'Color', 'w', 'BackgroundColor', [0 0 0 0.72], 'FontWeight', 'bold', 'FontSize', 8.5);
            end
            if any(validF)
                plot(ax, xFaultLine(validF), yAx(validF), '-y', 'LineWidth', 2.2);
                plot(ax, xFaultLine(validF), yAx(validF), 'ko', 'MarkerFaceColor', 'y', 'MarkerSize', 6.5);
            end
            set(ax, 'YDir', 'normal'); axis(ax, 'image'); xlim(ax, xExt); ylim(ax, yExt);
            cb = colorbar(ax, 'eastoutside'); cb.Label.String = '\gamma_{xy} [\pm0.02]'; cb.Color = 'k';
            title(ax, sprintf('[%d] %s — Frame %02d/%02d (Dip \\approx %.1f^\\circ)', idx, stNames{idx}, f, nF, faultDip_Deg(e)), ...
                'FontWeight', 'bold', 'FontSize', 11.5);
            ylabel(ax, 'Posisi Y (px)', 'FontWeight', 'bold');
            if idx == 3, xlabel(ax, 'Posisi X sepanjang Sandbox (px)', 'FontWeight', 'bold'); end
            i_styleLightAx(ax);
        end
        exportgraphics(fig3, fullfile(expOutDir, sprintf('%s_Evolusi_3Fase_Early_Mid_Late.jpg', expLabel)), 'Resolution', 140, 'BackgroundColor', 'white');
        close(fig3);
    end

    % =====================================================================
    % SIMPAN TABEL RINGKASAN MASTER LINTAS 8 EKSPERIMEN (TKS-5_cm-1 s/d 8)
    % =====================================================================
    masterTable = table((1:nExp)', expNames, pivFiles, rawFrameCount, droppedFrameCount, droppedFrameStr, ...
        activePivFrames, jitterRmsDx, jitterRmsDy, meanVelHW_Mid, peakVelHW_Mid, ...
        xFault_L14_Root, xFault_L10_Mid, xFault_L05_Y710, xFault_L03_Top, faultDip_Deg, ...
        maxPosShear_Mid, maxPosShear_Y710, xSecondary_Mid, valSecondary_Mid, ...
        detachment_Y_px, detachment_Xmax, detachment_MinShr, toeSlump_X_Y710, toeSlump_MinShr, scarpMaxVy_L03, ...
        'VariableNames', {'Exp_No', 'Experiment_ID', 'PIV_Mat_File', 'Raw_Frames', 'QPIV_Dropped_Count', 'QPIV_Dropped_Indices', ...
        'Active_PIV_Frames', 'Jitter_RMS_dx_px', 'Jitter_RMS_dy_px', 'Mean_Vel_HW_L10', 'Peak_Vel_HW_L10', ...
        'X_Fault_L14_Root_px', 'X_Fault_L10_Mid_px', 'X_Fault_L05_Y710_px', 'X_Fault_L03_Top_px', 'Fault_Dip_Deg', ...
        'Peak_Pos_Shear_L10', 'Peak_Pos_Shear_L05', 'X_Secondary_L10_px', 'Peak2_Pos_Shear_L10', ...
        'Detachment_Y_px', 'Detachment_Xmax_px', 'Detachment_Min_Shear', 'ToeSlump_X_L05_px', 'ToeSlump_Min_Shear', 'Scarp_Max_Vy_L03'});

    disp('========================================================================================');
    disp('📊 RINGKASAN MASTER DETEKSI SPASIOTEMPORAL 8 EKSPERIMEN (TKS-5_cm-1 s/d TKS-5_cm-8):');
    disp('========================================================================================');
    disp(masterTable);

    masterCsv = fullfile(outRoot, 'TKS-5_cm_All_1_to_8_Master_Summary.csv');
    writetable(masterTable, masterCsv);
    masterMat = fullfile(outRoot, 'TKS-5_cm_All_1_to_8_Master_Summary.mat');
    save(masterMat, 'masterTable', 'montageData');

    % =====================================================================
    % RENDER MONTAGE 1: PETA DETEKSI SESAR 20 GARIS (4x2) LINTAS 8 EKSPERIMEN
    % =====================================================================
    figM1 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2600 1850]);
    i_forceLightFig(figM1);
    tlM1 = tiledlayout(figM1, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tlM1, 'KOMPARASI SPASIOTEMPORAL 20 GARIS: TKS-5\_cm-1 s/d TKS-5\_cm-8 — Jejak Sesar Utama (Kuning) & Detachment Basal (Cyan)', ...
        'FontSize', 15, 'FontWeight', 'bold', 'Color', 'k');

    for e = 1:nExp
        md = montageData{e};
        ax = nexttile(tlM1, e); hold(ax, 'on');
        imagesc(ax, md.xExt, [md.yExt(2) md.yExt(1)], md.Zref);
        colormap(ax, jet(256)); clim(ax, [-0.02, 0.02]);
        image(ax, 'XData', md.xExt, 'YData', [md.yExt(2) md.yExt(1)], 'CData', md.rgbRef, 'AlphaData', 0.34);
        pivcore.util.drawGlyphs(ax, md.x1, md.yF, md.Uref, -md.Vref, 14, 1.05, [1 1 1]);

        for k = [3, 5, 10, 14, md.idxDet]
            plot(ax, md.xExt, [md.yAx(k) md.yAx(k)], '--', 'Color', [0.1 0.1 0.1 0.65], 'LineWidth', 1.0);
        end
        % Detachment basal cyan
        xDetEnd = min(2000, max(700, md.detXmax));
        plot(ax, [200 xDetEnd], [md.yAx(md.idxDet) md.yAx(md.idxDet)], '-c', 'LineWidth', 2.6);

        % Jejak sesar utama kuning
        vf = isfinite(md.xFaultLine);
        if any(vf)
            plot(ax, md.xFaultLine(vf), md.yAx(vf), '-y', 'LineWidth', 2.4);
            plot(ax, md.xFaultLine(vf), md.yAx(vf), 'ko', 'MarkerFaceColor', 'y', 'MarkerSize', 6);
        end
        set(ax, 'YDir', 'normal'); axis(ax, 'image'); xlim(ax, md.xExt); ylim(ax, md.yExt);
        cb = colorbar(ax, 'eastoutside'); cb.Color = 'k';
        title(ax, sprintf('[%d] %s (F%02d/%02d) | X_{L10}=%.0f px, X_{L05(Y710)}=%.0f px | Dip \\approx %.1f^\\circ', ...
            e, strrep(md.expLabel, '_', '\_'), md.refFrame, md.nF, xFault_L10_Mid(e), xFault_L05_Y710(e), md.faultDip), ...
            'FontWeight', 'bold', 'FontSize', 10.5);
        ylabel(ax, 'Y (px)', 'FontWeight', 'bold');
        if e >= 7, xlabel(ax, 'X (px)', 'FontWeight', 'bold'); end
        i_styleLightAx(ax);
    end
    outMontage1 = fullfile(outRoot, 'TKS-5_cm_All_1_to_8_Fault_Map_Montage_4x2.jpg');
    exportgraphics(figM1, outMontage1, 'Resolution', 150, 'BackgroundColor', 'white');
    close(figM1);

    % =====================================================================
    % RENDER MONTAGE 2: KYMOGRAPH axPSG SHEAR STRAIN PADA Y=710px (L05) (4x2)
    % =====================================================================
    figM2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2500 1800]);
    i_forceLightFig(figM2);
    tlM2 = tiledlayout(figM2, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tlM2, 'KOMPARASI KYMOGRAPH (axPSG) CLEANED SHEAR STRAIN \gamma_{xy} PADA GARIS L05 (Y \approx 710 px) & L10 (Y \approx 484 px): TKS-5\_cm-1 s/d 8', ...
        'FontSize', 14.5, 'FontWeight', 'bold', 'Color', 'k');

    for e = 1:nExp
        md = montageData{e};
        ax = nexttile(tlM2, e);
        imagesc(ax, 1:md.nF, md.xSample, md.kymoShr5);
        colormap(ax, jet(256)); clim(ax, [-0.02 0.02]); set(ax, 'YDir', 'normal');
        hold(ax, 'on');
        if isfinite(xFault_L05_Y710(e))
            yline(ax, xFault_L05_Y710(e), '--k', sprintf('Sesar L05 (Y=710) X≈%.0f px', xFault_L05_Y710(e)), 'LineWidth', 1.8, 'FontWeight', 'bold');
        end
        if isfinite(xFault_L10_Mid(e))
            yline(ax, xFault_L10_Mid(e), ':r', sprintf('Sesar L10 (Y=484) X≈%.0f px', xFault_L10_Mid(e)), 'LineWidth', 1.5, 'FontWeight', 'bold');
        end
        if isfinite(toeSlump_X_Y710(e))
            yline(ax, toeSlump_X_Y710(e), '-.b', sprintf('Toe Slump X≈%.0f px', toeSlump_X_Y710(e)), 'LineWidth', 1.4);
        end
        hold(ax, 'off');
        cb = colorbar(ax, 'eastoutside'); cb.Label.String = '\gamma_{xy}'; cb.Color = 'k';
        ylabel(ax, 'Posisi X (px)', 'FontWeight', 'bold');
        if e >= 7, xlabel(ax, 'Active PIV Frame Index', 'FontWeight', 'bold'); end
        title(ax, sprintf('[%d] %s — Kymograph L05 (Y=710 px) | Peak +\\gamma_{xy}=%+.3f @ X=%.0f px', ...
            e, strrep(md.expLabel, '_', '\_'), maxPosShear_Y710(e), xFault_L05_Y710(e)), ...
            'FontWeight', 'bold', 'FontSize', 10.5);
        i_styleLightAx(ax);
    end
    outMontage2 = fullfile(outRoot, 'TKS-5_cm_All_1_to_8_Kymograph_Y710_Montage_4x2.jpg');
    exportgraphics(figM2, outMontage2, 'Resolution', 150, 'BackgroundColor', 'white');
    close(figM2);

    fprintf('\n🎉 SELESAI! Seluruh 8 eksperimen (TKS-5_cm-1 s/d 8) berhasil dianalisis & dirender di:\n   %s\n', outRoot);
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

function s = i_formatRanges(idx)
    if isempty(idx), s = 'tidak ada'; return; end
    idx = sort(unique(idx(:)))';
    parts = {};
    i = 1;
    while i <= numel(idx)
        j = i;
        while j < numel(idx) && idx(j+1) == idx(j) + 1
            j = j + 1;
        end
        if i == j
            parts{end+1} = sprintf('%d', idx(i)); %#ok<AGROW>
        else
            parts{end+1} = sprintf('%d-%d', idx(i), idx(j)); %#ok<AGROW>
        end
        i = j + 1;
    end
    s = strjoin(parts, ', ');
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
