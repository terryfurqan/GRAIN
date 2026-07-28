function stats = processFolder(folder, anchor, crop, cfg, progressFcn)
%PROCESSFOLDER  Stabilisasi + cropping satu folder image-sequence.
%
%   stats = batchpivprep2.core.processFolder(folder, anchor, crop, cfg, progressFcn)
%
%   Versi 2: pipeline per frame = STABILISASI (pada gambar yang BELUM
%   di-crop) -> CROPPING. Dua mode cropping (lihat batchpivprep2.io.cropPreset):
%       'crop'   : crop bounding-box apa adanya (rectangle).
%       'square' : squaring/normalisasi geometris (warp projektif 4-titik)
%                  lalu crop pada area persegi hasil squaring.
%   Matematika framing memakai pivprep.geom.computeFraming (modul +pivprep
%   yang dipakai ulang) -> identik dengan PIVPrep.
%
%   INPUT:
%       folder      struct .path (folder sumber) dan .files (cell gambar,
%                   natural sort). Opsional .outName (nama subfolder unik).
%       anchor      struct preset anchor STABILISASI (batchpivprep2.io.anchorPreset).
%                   Koordinat disesuaikan otomatis bila resolusi/FOV berbeda.
%       crop        struct preset ROI CROPPING (batchpivprep2.io.cropPreset).
%                   Disesuaikan otomatis ke frame folder ini.
%       cfg         struct konfigurasi:
%           .suffix       sufiks nama folder keluaran (mis. 'Trial1')
%           .stabMethod   'surf' | 'phasecorr'
%           .jitterTol    ambang jitter diterima (px)
%           .roiPad       padding ROI pencarian (px),     default 50
%           .surfMaxRatio MaxRatio matchFeatures,         default 0.60
%           .minMatchPts  match minimum,                  default 4
%           .rawFormat    'jpg' | 'png' | 'tif'
%           .rawQuality   kualitas JPEG RAW
%           .gsScale      skala GS (0..1)
%           .gsQuality    kualitas JPEG GS
%           .outputMode   'inplace' (dalam folder sumber) | 'root'
%           .outputRoot   akar keluaran (untuk outputMode='root')
%           .marginEnabled/.marginPx  jarak aman titik ROI dari tepi (px)
%       progressFcn fungsi opsional @(k,nF,statusStr) -> stop(logical).
%                   Bila mengembalikan true, loop dihentikan (partial).
%
%   STRUKTUR KELUARAN (per folder) -- sama seperti versi 1:
%       <base>/RAW_<suffix>/    citra hasil (stabilisasi + crop), resolusi penuh
%       <base>/GS_<suffix>/     salinan diperkecil
%       <base>/EXIF_<suffix>/   EXIF.mat + JITTER.mat/.csv/.txt
%       <base>/ANCHOR_used.mat  preset anchor stabilisasi yang dipakai
%       <base>/CROP_used.mat    preset ROI cropping yang dipakai
%       <base>/JITTER_curve.png kurva jitter (disimpan, tidak ditampilkan)
%   dengan base = folder sumber (mode 'inplace') atau
%   <outputRoot>/<namaFolder> (mode 'root', satu folder per input).
%
%   OUTPUT:
%       stats struct: .folder .nFrames .nOK .nSkip .outDirs .jitterSummary
%                     .elapsed .error .stopped .outSize .cropMode

    if nargin < 5; progressFcn = []; end
    util = pivprep.util.utilities;

    stats = struct('folder', folder.path, 'nFrames', numel(folder.files), ...
        'nOK', 0, 'nSkip', 0, 'outDirs', struct(), ...
        'jitterSummary', struct(), 'elapsed', 0, 'error', '', 'stopped', false, ...
        'outSize', [0 0], 'cropMode', '');

    files       = folder.files;
    inputFolder = folder.path;
    nF          = numel(files);
    if nF == 0
        stats.error = 'Folder tidak berisi gambar.';
        return;
    end
    if isempty(crop)
        stats.error = 'Tidak ada ROI cropping yang di-assign.';
        return;
    end

    % --- Folder keluaran (base + RAW_/GS_/EXIF_ dgn sufiks) ---
    if isfield(folder, 'outName') && ~isempty(folder.outName)
        outName = folder.outName;
    else
        [~, outName] = fileparts(strip_trailing_sep(inputFolder));
        if isempty(outName); outName = 'Folder'; end
    end
    outDirs = local_buildOutDirs(inputFolder, cfg, outName);
    util.ensureDir(outDirs.base);
    util.ensureDir(outDirs.raw);
    util.ensureDir(outDirs.gs);
    util.ensureDir(outDirs.exif);
    stats.outDirs = outDirs;

    % --- Frame referensi (pertama) + ukurannya ---
    imgFirst = imread(fullfile(inputFolder, files{1}));
    refSize3 = size(imgFirst);
    if numel(refSize3) == 2, refSize3 = [refSize3, 1]; end
    refSize  = refSize3(1:2);                  % [H W]

    % --- Margin (jarak aman titik ROI dari tepi) dari cfg ---
    if local_get(cfg, 'marginEnabled', true)
        marginPx = local_get(cfg, 'marginPx', []);   % [] -> default
    else
        marginPx = 0;
    end

    % --- Sesuaikan anchor STABILISASI agar MUAT di frame folder ini ---
    [anchorFit, fitInfo] = batchpivprep2.io.anchorPreset.fitToImage(anchor, refSize, marginPx);
    if ~strcmp(fitInfo.status, 'ok')
        fprintf(['  [anchor] disesuaikan ke frame %dx%d (W x H): %s ' ...
                 '(geser=[%.0f %.0f] px, skala=%.3f)\n'], ...
            refSize(2), refSize(1), fitInfo.status, ...
            fitInfo.shift(1), fitInfo.shift(2), fitInfo.scale);
    end

    % --- Sesuaikan ROI CROPPING agar MUAT di frame folder ini ---
    %     (margin di-crop default 0 di dalam cropPreset; bila marginPx kosong,
    %      kita pakai 0 agar crop persis apa adanya kecuali user mengaktifkan).
    cropMarginPx = marginPx;
    if isempty(cropMarginPx); cropMarginPx = 0; end
    [cropFit, cropFitInfo] = batchpivprep2.io.cropPreset.fitToImage(crop, refSize, cropMarginPx);
    if ~strcmp(cropFitInfo.status, 'ok')
        fprintf(['  [crop]   disesuaikan ke frame %dx%d (W x H): %s ' ...
                 '(geser=[%.0f %.0f] px, skala=%.3f)\n'], ...
            refSize(2), refSize(1), cropFitInfo.status, ...
            cropFitInfo.shift(1), cropFitInfo.shift(2), cropFitInfo.scale);
    end
    stats.cropMode = cropFit.cropMode;

    % --- Hitung transform FRAMING (none / square projektif / crop) ---
    if strcmpi(cropFit.cropMode, 'none')
        % Mode 0: TANPA crop. Keluaran = frame penuh hasil stabilisasi.
        frame = struct('mode', 'none', 'outSize', refSize);
        stats.outSize = refSize;       % [H W]
        fprintf('  [crop]   mode none -> output %d x %d px (W x H) (frame penuh)\n', ...
            refSize(2), refSize(1));
    else
        frame = pivprep.geom.computeFraming(cropFit.framePts, cropFit.cropMode, refSize);
        stats.outSize = frame.outSize;     % [H W]
        fprintf('  [crop]   mode %s -> output %d x %d px (W x H), aspect %.3f\n', ...
            cropFit.cropMode, frame.outSize(2), frame.outSize(1), frame.aspectRatio);
    end

    % --- Simpan ROI yang dipakai (di base folder, untuk dokumentasi) ---
    try
        batchpivprep2.io.anchorPreset.savePreset( ...
            anchorFit, fullfile(outDirs.base, 'ANCHOR_used.mat'));
    catch ME
        warning('batchpivprep2:processFolder:anchorSave', ...
            'ANCHOR_used.mat gagal untuk %s: %s', inputFolder, ME.message);
    end
    try
        batchpivprep2.io.cropPreset.savePreset( ...
            cropFit, fullfile(outDirs.base, 'CROP_used.mat'));
    catch ME
        warning('batchpivprep2:processFolder:cropSave', ...
            'CROP_used.mat gagal untuk %s: %s', inputFolder, ME.message);
    end

    % --- Referensi stabilisasi (fitur diekstrak ULANG dari frame pertama
    %     folder ini, pada LOKASI anchor yang dipakai ulang) ---
    refStab = pivprep.stab.buildReference( ...
        imgFirst, anchorFit.anchorROI, cfg.stabMethod);

    stabParams = struct( ...
        'roiPad',      local_get(cfg, 'roiPad', 50), ...
        'jitterTol',   cfg.jitterTol, ...
        'maxRatio',    local_get(cfg, 'surfMaxRatio', 0.60), ...
        'minMatchPts', local_get(cfg, 'minMatchPts', 4));

    % --- Loop frame ---
    exifList   = cell(nF, 1);
    jitterRows = repmat(struct('frame', 0, 'file', '', 'nMatch', 0, ...
        'dx', 0, 'dy', 0, 'jitter', 0, 'accepted', false, 'status', ''), nF, 1);

    lastGood = util.identityTform();
    tStart   = tic;
    kDone    = 0;

    for k = 1:nF
        fname    = files{k};
        fullPath = fullfile(inputFolder, fname);
        [~, baseName] = fileparts(fname);

        % EXIF selalu dibaca (1 baris tabel = 1 berkas)
        meta = pivprep.io.readExifData(fullPath);
        meta.File = fname;
        exifList{k} = meta;

        nMatch = 0; jit = 0; dxF = 0; dyF = 0; accepted = false;

        try
            imgMov = imread(fullPath);

            % --- 1) STABILISASI (pada gambar BELUM di-crop) ---
            stabParams.lastGoodTform = lastGood;
            stabOut = pivprep.stab.estimateTransform(imgMov, refStab, stabParams);

            if stabOut.accepted
                lastGood = stabOut.tform;
                stats.nOK = stats.nOK + 1;
            else
                stats.nSkip = stats.nSkip + 1;
            end
            nMatch   = stabOut.nMatch;
            jit      = stabOut.jitter;
            dxF      = stabOut.dx;
            dyF      = stabOut.dy;
            accepted = stabOut.accepted;
            status   = stabOut.status;

            % Warp stabilisasi ke output view seukuran referensi (full frame,
            % koordinat sama dgn frame pertama -> ROI cropping tetap valid).
            imgStab = imwarp(imgMov, stabOut.tform, ...
                'OutputView', imref2d(refSize), 'Interp', 'linear');

            % --- 2) CROPPING (setelah stabilisasi) ---
            if strcmpi(frame.mode, 'none')
                % Mode 0: tanpa crop -> pakai frame penuh hasil stabilisasi.
                imgFinal = imgStab;
            elseif strcmpi(frame.mode, 'square')
                % Squaring + crop dalam satu warp projektif: OutputView =
                % rectangle target hasil squaring.
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

            % Tulis RAW (RAW_<suffix>/) + GS (GS_<suffix>/), embed EXIF.
            pivprep.io.writeOutputs(imgFinal, outDirs, baseName, cfg, meta);

        catch ME
            status      = sprintf('ERROR: %s', ME.message);
            stats.nSkip = stats.nSkip + 1;
        end

        jitterRows(k) = struct('frame', k, 'file', fname, 'nMatch', nMatch, ...
            'dx', dxF, 'dy', dyF, 'jitter', jit, ...
            'accepted', accepted, 'status', status);
        kDone = k;

        % Progress + cek STOP
        if ~isempty(progressFcn)
            try
                stop = progressFcn(k, nF, sprintf('%s  [%d/%d]', baseName, k, nF));
            catch
                stop = false;
            end
            if stop
                stats.stopped = true;
                break;
            end
        end
    end

    stats.elapsed = toc(tStart);

    % --- Pangkas ke jumlah frame yang benar-benar diproses (untuk STOP) ---
    exifList   = exifList(1:kDone);
    jitterRows = jitterRows(1:kDone);

    % --- Backup tabel EXIF (selalu) ---
    try
        pivprep.io.writeExifTable(exifList, fullfile(outDirs.exif, 'EXIF.mat'));
    catch ME
        warning('batchpivprep2:processFolder:exif', ...
            'EXIF.mat gagal untuk %s: %s', inputFolder, ME.message);
    end

    % --- CONTAINER jitter (.mat/.csv/.txt) + KURVA jitter (.png) ---
    jmeta = struct( ...
        'folder',     inputFolder, ...
        'method',     cfg.stabMethod, ...
        'jitterTol',  cfg.jitterTol, ...
        'anchorName', local_get(anchor, 'name', 'anchor'), ...
        'anchor',     anchorFit, ...
        'cropName',   local_get(crop, 'name', 'crop'), ...
        'cropMode',   cropFit.cropMode, ...
        'crop',       cropFit);
    curvePath = fullfile(outDirs.base, 'JITTER_curve.png');
    try
        stats.jitterSummary = batchpivprep2.io.writeJitter( ...
            jitterRows, outDirs.exif, jmeta, curvePath);
    catch ME
        warning('batchpivprep2:processFolder:jitter', ...
            'Container jitter gagal untuk %s: %s', inputFolder, ME.message);
    end
end


% =====================================================================
function outDirs = local_buildOutDirs(inputFolder, cfg, outName)
%LOCAL_BUILDOUTDIRS  Bangun path base + RAW/GS/EXIF dgn sufiks kustom.
    suffix = '';
    if isfield(cfg, 'suffix'); suffix = strtrim(char(cfg.suffix)); end
    suffix = local_sanitize(suffix);

    if isempty(suffix)
        rawName = 'RAW'; gsName = 'GS'; exifName = 'EXIF';
    else
        rawName  = ['RAW_'  suffix];
        gsName   = ['GS_'   suffix];
        exifName = ['EXIF_' suffix];
    end

    mode = local_get(cfg, 'outputMode', 'inplace');
    if strcmpi(mode, 'root') && isfield(cfg, 'outputRoot') && ~isempty(cfg.outputRoot)
        base = fullfile(cfg.outputRoot, local_sanitize(outName));
    else
        base = inputFolder;
    end

    outDirs = struct( ...
        'base', base, ...
        'raw',  fullfile(base, rawName), ...
        'gs',   fullfile(base, gsName), ...
        'exif', fullfile(base, exifName));
end


function s = local_sanitize(s)
%LOCAL_SANITIZE  Bersihkan karakter yang tidak aman untuk nama folder.
    s = regexprep(s, '[\\/:*?"<>|]', '_');
    s = regexprep(s, '\s+', '_');
end


function p = strip_trailing_sep(p)
    if ~isempty(p) && (p(end) == filesep || p(end) == '/')
        p(end) = [];
    end
end


function v = local_get(s, fld, def)
%LOCAL_GET  Ambil field struct dengan nilai default.
    if isstruct(s) && isfield(s, fld) && ~isempty(s.(fld))
        v = s.(fld);
    else
        v = def;
    end
end
