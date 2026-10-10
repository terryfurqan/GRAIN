function analyze_spatiotemporal_TKS5_6()
% ANALYZE_SPATIOTEMPORAL_TKS5_6  Deteksi buta (100% numerik spasiotemporal,
% TANPA melihat citra visual) untuk eksperimen TKS-5_cm-6.mat.
%
% Mengekstrak:
%   1. Karakteristik Temporal 119 Frame Consecutive langsung dari TKS-5_cm-6.mat
%      (EXIF dt, jitter, dead-frame detection, fase aktif vs berhenti, kecepatan indenter)
%      melalui QPIV scan pada Y = 461 px (Tengah 50%) dan Y = 710 px (L05, 22.5% dari atas).
%   2. Tomografi Spasiotemporal 20 Garis Horizontal (L01 .. L20, dari atas ke bawah)
%      sepanjang seluruh ruang X [px] dan waktu t:
%      - Deteksi batas udara vs permukaan pasir (topografi & pengangkatan scarp)
%      - Deteksi posisi & laju dorong dinding Indenter
%      - Deteksi bidang Detachment Basal (kedalaman Y, rentang X, intensitas geser)
%      - Deteksi semua zona lokalisasi sesar (Fore-thrust utama, Sesar sekunder / Back-thrust)
%        pada tiap garis L01..L20 (koordinat X_sesar, kemiringan dip, lebar zona geser)
%      - Urutan waktu kemunculan (onset frame) dan propagasi vertikal dari bawah ke atas.

    here = fileparts(mfilename('fullpath'));
    cd(here);
    grain_setup();

    rawMatFile = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm/TKS-5_cm-6.mat';
    pivMatFile = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm/PIV_2026-06-24/TKS-5_cm-6-NOVL-S1-120to28-4p20px.mat';
    outDir = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm/TKS_5 Compare/TKS-5_cm-6_Spatiotemporal_Detection';
    if ~isfolder(outDir), mkdir(outDir); end

    fprintf('========================================================================\n');
    fprintf('🔬 DETEKSI SPASIOTEMPORAL MURNI (BLIND NUMERICAL) — TKS-5_cm-6\n');
    fprintf('========================================================================\n');

    % =====================================================================
    % TAHAP 1: BEDAH METADATA, EXIF DT, JITTER & QPIV 119-FRAME DARI TKS-5_cm-6.mat
    % =====================================================================
    S_raw = load(rawMatFile);
    prep = S_raw.prep;
    nImgs = numel(prep.raw.blobs);
    nPairsConsec = nImgs - 1;
    fprintf('\n[1] DATA KONTainer MENTAH (TKS-5_cm-6.mat):\n');
    fprintf('    - Jumlah Foto Mentah (blobs)   : %d foto (%d pasangan konsekutif)\n', nImgs, nPairsConsec);
    if isfield(prep, 'crop_used') && ~isempty(prep.crop_used)
        if isnumeric(prep.crop_used)
            fprintf('    - Crop ROI yang dipakai        : [%s]\n', num2str(prep.crop_used));
        elseif isstruct(prep.crop_used)
            disp(prep.crop_used);
        end
    end
    if isfield(prep, 'anchor_used') && ~isempty(prep.anchor_used)
        if isnumeric(prep.anchor_used)
            fprintf('    - Anchor Jitter ROI            : [%s]\n', num2str(prep.anchor_used));
        elseif isstruct(prep.anchor_used)
            disp(prep.anchor_used);
        end
    end
    if isfield(prep, 'jitter') && isstruct(prep.jitter)
        fnJ = fieldnames(prep.jitter);
        fprintf('    - Field Jitter                 : %s\n', strjoin(fnJ, ', '));
        if isfield(prep.jitter, 'dx') && isfield(prep.jitter, 'dy')
            dxJ = prep.jitter.dx(:); dyJ = prep.jitter.dy(:);
            fprintf('    - Amplitudo Jitter Kamera      : dx = [%.2f .. %.2f] px (RMS=%.2f), dy = [%.2f .. %.2f] px (RMS=%.2f)\n', ...
                min(dxJ), max(dxJ), std(dxJ), min(dyJ), max(dyJ), std(dyJ));
        end
    end

    % Jalankan / muat QPIV Thin-Strip Consecutive (1..119) pada 2 ketinggian kunci:
    %   Strip A: Tengah (pos = 50%, Y_ax ≈ 461 px)
    %   Strip B: Atas   (pos = 22.5%, Y_ax ≈ 710 px, L05)
    qpivMidMat = fullfile(outDir, 'TKS-5_cm-6_QPIV_consec_mid50.mat');
    qpiv710Mat = fullfile(outDir, 'TKS-5_cm-6_QPIV_consec_y710.mat');

    if ~isfile(qpivMidMat) || ~isfile(qpiv710Mat)
        fprintf('\n    Menjalankan ekstraksi QPIV Consecutive (119 frame pairs) pada Y=50%% dan Y=710px...\n');
        tmpRawDir = fullfile(tempdir, sprintf('grain_tks5_6_%s', char(matlab.lang.internal.uuid())));
        mkdir(tmpRawDir);
        cleanupTmp = onCleanup(@() i_cleanDir(tmpRawDir));
        for k = 1:nImgs
            fn = fullfile(tmpRawDir, sprintf('frame_%04d.jpg', k));
            fid = fopen(fn, 'wb');
            fwrite(fid, prep.raw.blobs{k}, 'uint8');
            fclose(fid);
        end
        imInfo = imfinfo(fullfile(tmpRawDir, 'frame_0001.jpg'));
        H_img = imInfo.Height;
        W_img = imInfo.Width;
        fprintf('    Dimensi Citra TKS-5_cm-6       : %d x %d px (W x H)\n', W_img, H_img);

        iwStrip = 64; stripPad = 10;
        Lwidth = iwStrip + ceil(iwStrip/2) + 2*stripPad; % 116 px

        % Strip 50% (Y_ax ≈ 461 px)
        if ~isfile(qpivMidMat)
            rc50 = 1 + 0.50 * (H_img - 1);
            y0_50 = max(1, round(rc50 - Lwidth/2));
            roi50 = [1, y0_50, W_img - 1, min(H_img - y0_50, Lwidth - 1)];
            PIVlab_automasi(tmpRawDir, 'Suffix', '*.jpg', 'Sequencing', 'consecutive', 'Skip', 0, ...
                'NumWorkers', 8, 'IntAreas', [64 32 16 16], 'NumPasses', 3, ...
                'ROI', roi50, 'PreprocROI', roi50, 'OutputFolder', outDir, ...
                'OutputName', 'TKS-5_cm-6_QPIV_consec_mid50');
        end

        % Strip Y = 710 px (22.5% dari atas -> row = H_img - 710)
        if ~isfile(qpiv710Mat)
            rc710 = H_img - 710;
            y0_710 = max(1, round(rc710 - Lwidth/2));
            roi710 = [1, y0_710, W_img - 1, min(H_img - y0_710, Lwidth - 1)];
            PIVlab_automasi(tmpRawDir, 'Suffix', '*.jpg', 'Sequencing', 'consecutive', 'Skip', 0, ...
                'NumWorkers', 8, 'IntAreas', [64 32 16 16], 'NumPasses', 3, ...
                'ROI', roi710, 'PreprocROI', roi710, 'OutputFolder', outDir, ...
                'OutputName', 'TKS-5_cm-6_QPIV_consec_y710');
        end
    end

    % Analisis Time-Series 119 Frame Consecutive dari QPIV Mid50 & Y710
    Sq50  = load(qpivMidMat); dQ50  = pivcore.data.buildDataset(Sq50);
    Sq710 = load(qpiv710Mat); dQ710 = pivcore.data.buildDataset(Sq710);
    [M_vel_c50, M_shr_c50, x_c50]   = i_scanStripCenter(dQ50);
    [M_vel_c710, M_shr_c710, x_c710] = i_scanStripCenter(dQ710);

    peakV_c50  = max(M_vel_c50, [], 1, 'omitnan');
    peakV_c710 = max(M_vel_c710, [], 1, 'omitnan');
    ex50 = pivprepFrameExclusion(peakV_c50, nan(1, numel(peakV_c50)), struct('useMotion', true, 'useTime', false));

    deadIdx = find(ex50.ignore);
    activeIdx = find(~ex50.ignore);
    fprintf('\n[2] DETEKSI FASE TEMPORAL & DEAD FRAMES (119 PASANGAN KONSEKUTIF):\n');
    fprintf('    - Ambang Gerak (Dead Threshold): |V|_max < %.3f px/frame\n', ex50.motionMin);
    fprintf('    - Total Frame Aktif            : %d / %d pasangan (%.1f%%)\n', numel(activeIdx), numel(peakV_c50), 100*numel(activeIdx)/numel(peakV_c50));
    fprintf('    - Total Dead / Drop Frames     : %d pasangan -> Indeks: [%s]\n', numel(deadIdx), i_formatRanges(deadIdx));
    if ~isempty(activeIdx)
        fprintf('    - Rentang Frame Eksperimen Aktif: Frame %d s/d Frame %d\n', min(activeIdx), max(activeIdx));
    end
    fprintf('    - Kecepatan Puncak Indenter    : Median = %.3f px/fr | Mean = %.3f px/fr | Max = %.3f px/fr\n', ...
        median(peakV_c50(activeIdx), 'omitnan'), mean(peakV_c50(activeIdx), 'omitnan'), max(peakV_c50(activeIdx), [], 'omitnan'));

    % Lokasi sesar pada 119 frame konsekutif di Y=50% dan Y=710px
    int50 = (x_c50 >= 600) & (x_c50 <= 2400);
    meanShr_c50 = mean(M_shr_c50(:, activeIdx), 2, 'omitnan');
    meanShr_c50_pos = meanShr_c50; meanShr_c50_pos(~int50) = -Inf;
    [pkShr50_pos, idxF50_pos] = max(meanShr_c50_pos);
    xFault_c50_fore = x_c50(idxF50_pos);

    meanShr_c50_neg = meanShr_c50; meanShr_c50_neg(~int50) = Inf;
    [pkShr50_neg, idxF50_neg] = min(meanShr_c50_neg);
    xFault_c50_back = x_c50(idxF50_neg);

    int710 = (x_c710 >= 600) & (x_c710 <= 2400);
    meanShr_c710 = mean(M_shr_c710(:, activeIdx), 2, 'omitnan');
    meanShr_c710_pos = meanShr_c710; meanShr_c710_pos(~int710) = -Inf;
    [pkShr710_pos, idxF710_pos] = max(meanShr_c710_pos);
    xFault_c710_fore = x_c710(idxF710_pos);

    meanShr_c710_neg = meanShr_c710; meanShr_c710_neg(~int710) = Inf;
    [pkShr710_neg, idxF710_neg] = min(meanShr_c710_neg);
    xFault_c710_back = x_c710(idxF710_neg);

    fprintf('\n[3] DETEKSI SESAR PADA DATA 119-FRAME CONSECUTIVE (Y=461 px vs Y=710 px):\n');
    fprintf('    - Pada Y ≈ 461 px (Tengah 50%%):\n');
    fprintf('      * Puncak Geser Positif (Fore-Thrust, +gamma_xy) : X ≈ %.0f px (mean = %+.4f, max = %+.4f)\n', ...
        xFault_c50_fore, pkShr50_pos, max(M_shr_c50(idxF50_pos, activeIdx)));
    fprintf('      * Puncak Geser Negatif (Back-Thrust, -gamma_xy) : X ≈ %.0f px (mean = %+.4f, min = %+.4f)\n', ...
        xFault_c50_back, pkShr50_neg, min(M_shr_c50(idxF50_neg, activeIdx)));
    fprintf('    - Pada Y = 710 px (Garis L05, 22.5%% dari atas):\n');
    fprintf('      * Puncak Geser Positif (Fore-Thrust, +gamma_xy) : X ≈ %.0f px (mean = %+.4f, max = %+.4f)\n', ...
        xFault_c710_fore, pkShr710_pos, max(M_shr_c710(idxF710_pos, activeIdx)));
    fprintf('      * Puncak Geser Negatif (Back-Thrust, -gamma_xy) : X ≈ %.0f px (mean = %+.4f, min = %+.4f)\n', ...
        xFault_c710_back, pkShr710_neg, min(M_shr_c710(idxF710_neg, activeIdx)));

    % Lacak evolusi temporal per-segmen frame (1..119) pada Y=461 px dan Y=710 px
    fprintf('\n    --- Evolusi Temporal Lokalisasi Geser per Jendela Frame (Consecutive 1..119) ---\n');
    fprintf('    %-12s | %-28s | %-28s | %-18s\n', 'Frame Window', 'Y=461px Peak +Shr @ X', 'Y=710px Peak +Shr @ X', 'Y=461px Peak -Shr @ X');
    fprintf('    %s\n', repmat('-', 1, 95));
    winEdges = 1:10:nPairsConsec;
    for w = 1:numel(winEdges)
        f1 = winEdges(w);
        f2 = min(nPairsConsec, f1 + 9);
        sub50 = mean(M_shr_c50(:, f1:f2), 2, 'omitnan');
        sub710 = mean(M_shr_c710(:, f1:f2), 2, 'omitnan');
        s50p = sub50; s50p(~int50) = -Inf; [v50p, i50p] = max(s50p);
        s710p = sub710; s710p(~int710) = -Inf; [v710p, i710p] = max(s710p);
        s50n = sub50; s50n(~int50) = Inf; [v50n, i50n] = min(s50n);
        fprintf('    F%03d - F%03d  | %+0.4f @ X=%4.0f px          | %+0.4f @ X=%4.0f px          | %+0.4f @ X=%4.0f px\n', ...
            f1, f2, v50p, x_c50(i50p), v710p, x_c710(i710p), v50n, x_c50(i50n));
    end

    % =====================================================================
    % TAHAP 2: TOMOGRAFI SPASIOTEMPORAL 20 GARIS HORIZONTAL (L01 .. L20)
    %          PADA KONTAINER PIV PENUH TKS-5_cm-6 (28 FRAME AKTIF)
    % =====================================================================
    fprintf('\n========================================================================\n');
    fprintf('[4] TOMOGRAFI SPASIOTEMPORAL 20 GARIS HORIZONTAL (L01 s/d L20)\n');
    fprintf('    Sumber: %s\n', pivMatFile);
    fprintf('========================================================================\n');

    S_piv = load(pivMatFile);
    if isfield(S_piv, 'qpiv_dropped_frames')
        fprintf('    - qpiv_dropped_frames tercatat di .mat : [%s]\n', num2str(S_piv.qpiv_dropped_frames(:)'));
    end
    dataFull = pivcore.data.buildDataset(S_piv);
    nF = dataFull.nFrames;
    x1 = pivcore.data.safeFrame(dataFull.x, 1);
    y1 = pivcore.data.safeFrame(dataFull.y, 1);
    xExt = [min(x1(:)), max(x1(:))];
    yExt = [min(y1(:)), max(y1(:))];
    yMid = (yExt(1) + yExt(2)) / 2;

    fprintf('    - Grid PIV Penuh: %d baris x %d kolom | nFrames = %d | X=[%.0f..%.0f] px, Y=[%.0f..%.0f] px\n', ...
        size(x1,1), size(x1,2), nF, xExt(1), xExt(2), yExt(1), yExt(2));

    % Precompute |V|, U, V, Cleaned Shear Strain (Med 3x3 + Gauss 1.8) untuk semua nF frame
    velStack = cell(1, nF);
    uStack   = cell(1, nF);
    vStack   = cell(1, nF);
    shrStack = cell(1, nF);
    for f = 1:nF
        [U, V] = pivcore.data.pickAnyVel(dataFull, f);
        uStack{f} = U;
        vStack{f} = V;
        velStack{f} = hypot(U, V);
        Zraw = pivcore.data.computeShearRate(dataFull, f, 'mode', 'engineering');
        Zcln = imgaussfilt(medfilt2(Zraw, [3 3], 'symmetric'), 1.8);
        shrStack{f} = Zcln;
    end

    % Definisi 20 garis horizontal L01..L20 (2.5% s/d 97.5% dari atas)
    nLines = 20;
    posPct = linspace(2.5, 97.5, nLines)';
    yRow = yExt(1) + (posPct / 100) * (yExt(2) - yExt(1));
    yAx  = 2 * yMid - yRow;
    spacingPx = 16;

    fprintf('\n    %-4s | %-6s | %-7s | %-9s | %-25s | %-25s | %-22s\n', ...
        'ID', 'Top%', 'Y_Ax(px)', 'Mean|V|HW', 'Peak +Shear (Fore-Thrust)', 'Peak -Shear (Back/Basal)', 'Batas Gerak |V| Drop X');
    fprintf('    %s\n', repmat('-', 1, 112));

    for k = 1:nLines
        p1 = [xExt(1), yAx(k)];
        p2 = [xExt(2), yAx(k)];
        [Mv, ~, xPts, ~] = i_sampleStackAlongImageLine(x1, y1, velStack, p1, p2, spacingPx);
        [Ms, ~, ~, ~]    = i_sampleStackAlongImageLine(x1, y1, shrStack, p1, p2, spacingPx);
        [Mu, ~, ~, ~]    = i_sampleStackAlongImageLine(x1, y1, uStack, p1, p2, spacingPx);
        [Mvy, ~, ~, ~]   = i_sampleStackAlongImageLine(x1, y1, vStack, p1, p2, spacingPx);

        % Rata-rata waktu selama fase aktif utama (frame 3..nF-1)
        fAct = 2:max(2, nF-1);
        meanV_x = mean(Mv(:, fAct), 2, 'omitnan');
        meanS_x = mean(Ms(:, fAct), 2, 'omitnan');
        maxS_x  = prctile(Ms(:, fAct), 90, 2);
        minS_x  = prctile(Ms(:, fAct), 10, 2);

        % Kecepatan rata-rata di blok kiri (X = 300..900 px)
        hwMask = (xPts >= 300) & (xPts <= 900);
        meanV_HW = mean(meanV_x(hwMask), 'omitnan');

        % Cari puncak +Shear di interior (500..2500 px)
        intMask = (xPts >= 500) & (xPts <= 2500);
        sPos = maxS_x; sPos(~intMask) = -Inf;
        [valPos, idxPos] = max(sPos);
        xPos = xPts(idxPos);

        % Cari puncak -Shear (bisa basal detachment di X=150..1200 atau backthrust di interior)
        detMask = (xPts >= 150) & (xPts <= 2500);
        sNeg = minS_x; sNeg(~detMask) = Inf;
        [valNeg, idxNeg] = min(sNeg);
        xNeg = xPts(idxNeg);

        % Cari di mana |V| turun melewati 50% dari meanV_HW (batas depan blok bergerak)
        xDrop = NaN;
        if meanV_HW > 1.0
            dropCand = find((xPts' > 700) & (meanV_x < 0.45 * meanV_HW), 1, 'first');
            if ~isempty(dropCand)
                xDrop = xPts(dropCand);
            end
        end

        fprintf('    L%02d  | %5.1f%% | %7.1f | %9.2f | %+0.4f @ X=%4.0f px       | %+0.4f @ X=%4.0f px       | X_drop ≈ %4.0f px\n', ...
            k, posPct(k), yAx(k), meanV_HW, valPos, xPos, valNeg, xNeg, xDrop);
    end

    % =====================================================================
    % TAHAP 3: DETEKSI MULTI-SESAR & PROPAGASI SPASIOTEMPORAL PER FRAME (1..28)
    %          PADA GARIS L05 (Y=710 px), L08 (Y=574 px), L10 (Y=484 px), L13 (Y=348 px), L16 (Y=212 px)
    % =====================================================================
    keyLines = [5, 8, 10, 13, 16];
    fprintf('\n========================================================================\n');
    fprintf('[5] DETAIL EVOLUSI SPASIOTEMPORAL PER FRAME (F01..F%02d) PADA GARIS KUNCI\n', nF);
    fprintf('========================================================================\n');

    for kk = 1:numel(keyLines)
        k = keyLines(kk);
        p1 = [xExt(1), yAx(k)];
        p2 = [xExt(2), yAx(k)];
        [Mv, ~, xPts, ~] = i_sampleStackAlongImageLine(x1, y1, velStack, p1, p2, spacingPx);
        [Ms, ~, ~, ~]    = i_sampleStackAlongImageLine(x1, y1, shrStack, p1, p2, spacingPx);
        [Mvy, ~, ~, ~]   = i_sampleStackAlongImageLine(x1, y1, vStack, p1, p2, spacingPx);

        fprintf('\n--- GARIS L%02d (Y_Ax = %.1f px, %.1f%% dari Atas) ---\n', k, yAx(k), posPct(k));
        fprintf('Frame | Peak|V| | Mean|V|_HW | Peak1 +Shr @ X     | Peak2 +Shr @ X     | Peak -Shr @ X      | X_Front(|V|)\n');
        fprintf('%s\n', repmat('-', 1, 102));

        intMask = (xPts >= 500) & (xPts <= 2500);
        hwMask  = (xPts >= 300) & (xPts <= 900);

        for f = 1:nF
            vCol = Mv(:, f);
            sCol = Ms(:, f);
            pkV = max(vCol, [], 'omitnan');
            mHW = mean(vCol(hwMask), 'omitnan');

            % Cari Peak 1 +Shear
            s1 = sCol; s1(~intMask) = -Inf;
            [valP1, iP1] = max(s1);
            xP1 = xPts(iP1);

            % Cari Peak 2 +Shear (minimal berjarak 160 px dari Peak 1)
            s2 = s1;
            s2(abs(xPts - xP1) < 160) = -Inf;
            [valP2, iP2] = max(s2);
            xP2 = xPts(iP2);

            % Cari Peak -Shear
            sN = sCol; sN((xPts < 150) | (xPts > 2500)) = Inf;
            [valN, iN] = min(sN);
            xN = xPts(iN);

            % Cari X_Front tempat |V| turun di bawah 0.45 * mHW
            xFr = NaN;
            if mHW > 0.5
                idxFr = find((xPts' > 700) & (vCol < 0.45 * mHW), 1, 'first');
                if ~isempty(idxFr), xFr = xPts(idxFr); end
            end

            fprintf('F%02d   | %7.2f | %10.2f | %+0.4f @ X=%4.0f px | %+0.4f @ X=%4.0f px | %+0.4f @ X=%4.0f px | %4.0f px\n', ...
                f, pkV, mHW, valP1, xP1, valP2, xP2, valN, xN, xFr);
        end
    end
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

function i_cleanDir(d)
    if isfolder(d)
        try, rmdir(d, 's'); catch, end
    end
end
