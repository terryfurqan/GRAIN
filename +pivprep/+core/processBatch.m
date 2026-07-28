function processBatch(files, inputFolder, outDir, cfg)
%PROCESSBATCH  Loop batch utama PIVPrep.
%
%   pivprep.core.processBatch(files, inputFolder, outDir, cfg)
%
%   INPUT:
%       files        cell array nama berkas (sudah natural sort)
%       inputFolder  path folder input
%       outDir       path folder output (sudah dipastikan ada)
%       cfg          struct konfigurasi dari installCallbacks. Field
%                    'showMonitor' (logical) mengaktifkan jendela monitor
%                    real-time (default true jika field tidak ada).
%
%   Alur per frame:
%       1. Baca gambar
%       2. (opsional) Estimasi transform stabilisasi dan terapkan
%       3. Terapkan framing (square rectangular atau crop)
%       4. Tulis RAW (folder RAW/) + GS (folder GS/); EXIF dikumpulkan
%          lalu disimpan sebagai satu tabel di EXIF/EXIF.mat (akhir batch)
%       5. Update monitor (jika diaktifkan): plot dx, dy signed
%          (instantaneous) dan running sum (cumulative), tampilkan ETA.

    util = pivprep.util.utilities;

    if ~isfield(cfg, 'showMonitor') || isempty(cfg.showMonitor)
        cfg.showMonitor = true;
    end

    % --- 1: Muat frame referensi (pertama dan terakhir) ---
    util.printHeader('1/4', 'Load Reference Frames');
    imgFirst = imread(fullfile(inputFolder, files{1}));
    imgLast  = imread(fullfile(inputFolder, files{end}));
    if any(size(imgFirst, 1:2) ~= size(imgLast, 1:2))
        imgLast = imresize(imgLast, size(imgFirst, [1 2]));
    end
    imgOverlay = uint8(0.5*double(imgFirst) + 0.5*double(imgLast));
    fprintf('  Reference image size : %d x %d px (W x H)\n', ...
        size(imgFirst, 2), size(imgFirst, 1));

    % --- 2: Definisi region interaktif ---
    util.printHeader('2/4', 'Define Interactive Regions');
    regions = pivprep.ui.defineRegions(imgOverlay, cfg.mode, cfg.useStab, cfg);

    % --- 3: Hitung transform framing ---
    util.printHeader('3/4', 'Compute Framing Transform');
    refSize = size(imgFirst, [1 2]);
    frame   = pivprep.geom.computeFraming(regions.framePts, cfg.mode, refSize);
    fprintf('  Framing mode         : %s\n', cfg.mode);
    fprintf('  Output size          : %d x %d px (W x H)\n', ...
        frame.outSize(2), frame.outSize(1));
    fprintf('  Output aspect ratio  : %.3f (W/H)\n', frame.aspectRatio);

    % --- 3b: Siapkan referensi stabilisasi ---
    refStab = [];
    if cfg.useStab
        refStab = pivprep.stab.buildReference( ...
            imgFirst, regions.anchorROI, cfg.stabMethod);
        switch refStab.method
            case 'surf'
                fprintf('  Stabilization method : SURF | reference points: %d\n', ...
                    refStab.nPoints);
            case 'phasecorr'
                fprintf('  Stabilization method : Phase Correlation | patch: %d x %d\n', ...
                    size(refStab.patch, 2), size(refStab.patch, 1));
        end
    else
        fprintf('  Stabilization        : disabled\n');
    end

    % --- 4: Batch loop ---
    util.printHeader('4/4', 'Batch Processing');
    nF = numel(files);

    % --- Subfolder keluaran: RAW / GS / EXIF ---
    outDirs = struct( ...
        'raw',  fullfile(outDir, 'RAW'), ...
        'gs',   fullfile(outDir, 'GS'), ...
        'exif', fullfile(outDir, 'EXIF'));
    util.ensureDir(outDirs.raw);
    util.ensureDir(outDirs.gs);
    util.ensureDir(outDirs.exif);   % backup EXIF selalu dibuat

    % Kumpulan metadata EXIF: satu sel per berkas (1 baris tabel = 1 file)
    exifList = cell(nF, 1);

    fprintf('  Frames               : %d\n', nF);
    fprintf('  Output folder        : %s\n', outDir);
    fprintf('\n  %-5s  %-7s  %-12s  %-9s  %-9s  %s\n', ...
        'Frame', 'Match', 'Jitter(px)', 'dx(px)', 'dy(px)', 'Status');
    fprintf('  %s\n', repmat('-', 1, 78));

    % --- Waitbar (text-based progress) ---
    wb = waitbar(0, sprintf('Processing 1/%d ...', nF), 'Name', 'PIVPrep');
    cleanupWb = onCleanup(@() util.safeCloseWb(wb));  %#ok<NASGU>

    % --- Monitor real-time (opsional) ---
    monitor = [];
    if cfg.showMonitor
        monitor = pivprep.ui.buildMonitor(nF, cfg.useStab);
        cleanupMon = onCleanup(@() local_safeCloseMonitor(monitor));  %#ok<NASGU>
    end

    countOK   = 0;
    countSkip = 0;
    lastGood  = util.identityTform();
    tStart    = tic;

    stabParams = struct( ...
        'roiPad',      cfg.roiPad, ...
        'jitterTol',   cfg.jitterTol, ...
        'maxRatio',    cfg.surfMaxRatio, ...
        'minMatchPts', cfg.minMatchPts);

    refSize3 = size(imgFirst);
    if numel(refSize3) == 2
        refSize3 = [refSize3, 1];
    end

    for k = 1:nF
        fname    = files{k};
        fullPath = fullfile(inputFolder, fname);
        [~, baseName] = fileparts(fname);

        % EXIF dibaca tanpa syarat agar setiap berkas tetap menjadi satu
        % baris tabel, walau pemrosesan citra di bawah gagal.
        meta      = pivprep.io.readExifData(fullPath);
        meta.File = fname;
        exifList{k} = meta;

        nMatch = 0;
        jit    = 0;
        dxF    = 0;   % signed dx untuk monitor
        dyF    = 0;   % signed dy untuk monitor
        status = 'N/A';

        try
            imgMov = imread(fullPath);

            % --- Stabilize ---
            if cfg.useStab
                stabParams.lastGoodTform = lastGood;
                stabOut = pivprep.stab.estimateTransform( ...
                    imgMov, refStab, stabParams);

                if stabOut.accepted
                    lastGood = stabOut.tform;
                    countOK = countOK + 1;
                else
                    countSkip = countSkip + 1;
                end
                nMatch = stabOut.nMatch;
                jit    = stabOut.jitter;
                dxF    = stabOut.dx;
                dyF    = stabOut.dy;
                status = stabOut.status;

                imgStab = imwarp(imgMov, stabOut.tform, ...
                    'OutputView', imref2d(refSize3(1:2)), ...
                    'Interp', 'linear');
            else
                imgStab = imgMov;
                status  = 'No-stab';
                countOK = countOK + 1;
            end

            % --- Frame: square (rectangular projective) atau crop ---
            if strcmpi(frame.mode, 'square')
                imgFinal = imwarp(imgStab, frame.tform, ...
                    'OutputView', frame.refView, 'Interp', 'cubic');
            else
                r = frame.cropRect;
                imgFinal = imcrop(imgStab, r);
                target = [frame.outSize(1), frame.outSize(2)];
                if any(size(imgFinal, [1 2]) ~= target)
                    imgFinal = imresize(imgFinal, target);
                end
            end

            % --- Save outputs (RAW -> RAW/, GS -> GS/) ---
            pivprep.io.writeOutputs(imgFinal, outDirs, baseName, cfg, meta);

        catch ME
            status    = sprintf('ERROR: %s', ME.message);
            countSkip = countSkip + 1;
        end

        fprintf('  [%03d]  %-7d  %-12.2f  %-9.2f  %-9.2f  %s\n', ...
            k, nMatch, jit, dxF, dyF, status);

        % --- Update monitor real-time (ringan: hanya set XData/YData) ---
        elapsed = toc(tStart);
        if ~isempty(monitor) && isfield(monitor, 'fig') && ishandle(monitor.fig)
            monitor = pivprep.ui.updateMonitor( ...
                monitor, k, dxF, dyF, jit, elapsed);
        end

        % --- Waitbar batched (setiap 5 frame atau frame terakhir) ---
        if mod(k, 5) == 0 || k == nF
            rate = k / max(elapsed, 0.001);
            eta  = max(0, (nF - k) / max(rate, 0.001));
            if ishandle(wb)
                waitbar(k/nF, wb, sprintf( ...
                    'Frame %d / %d  |  ETA %.0f s  (%s)', ...
                    k, nF, eta, util.secsToHMS(eta)));
            end
        end
    end

    elapsed = toc(tStart);

    % --- Backup EXIF: satu tabel gabungan (1 baris = 1 berkas), selalu ---
    exifPath = fullfile(outDirs.exif, 'EXIF.mat');
    try
        pivprep.io.writeExifTable(exifList, exifPath);
        fprintf('  EXIF backup table    : %s (%d baris)\n', exifPath, nF);
    catch ME
        fprintf('  EXIF backup GAGAL    : %s\n', ME.message);
    end

    fprintf('\n  %s\n', repmat('=', 1, 78));
    fprintf('  DONE | Time: %.1f s (%s) | OK: %d | Skip/Error: %d\n', ...
        elapsed, util.secsToHMS(elapsed), countOK, countSkip);
    fprintf('  Output: %s\n', outDir);
    fprintf('  %s\n\n', repmat('=', 1, 78));

    msg = sprintf([ ...
        'PIVPrep finished.\n\n' ...
        'Frames processed : %d (OK: %d, Skip: %d)\n' ...
        'Elapsed time     : %.1f s (%s)\n' ...
        'Output folder    : %s'], ...
        nF, countOK, countSkip, elapsed, util.secsToHMS(elapsed), outDir);
    msgbox(msg, 'PIVPrep', 'help');
end


% =====================================================================
function local_safeCloseMonitor(monitor)
%LOCAL_SAFECLOSEMONITOR  Tutup figure monitor tanpa error meskipun
%   user sudah menutupnya manual atau struct kosong.
    try
        if ~isempty(monitor) && isfield(monitor, 'fig') && ...
                ishandle(monitor.fig)
            % Biarkan figure tetap terbuka agar user bisa inspect setelah
            % proses selesai. Jika ingin auto-close, ganti baris berikut
            % dengan: close(monitor.fig);
            figure(monitor.fig);   % bawa ke depan
        end
    catch
    end
end
