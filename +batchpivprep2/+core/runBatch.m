function results = runBatch(folders, cfg, stopCheck)
%RUNBATCH  Orkestrasi stabilisasi + cropping batch untuk banyak folder.
%
%   results = batchpivprep2.core.runBatch(folders, cfg, stopCheck)
%
%   INPUT:
%       folders   struct array, satu elemen per folder, field:
%           .path     path folder sumber
%           .files    cell gambar (natural sort)
%           .nImg     jumlah gambar
%           .anchor   struct preset anchor STABILISASI untuk folder ini
%           .crop     struct preset ROI CROPPING untuk folder ini
%       cfg       struct konfigurasi (lihat batchpivprep2.core.processFolder).
%       stopCheck fungsi opsional @() -> logical. Bila mengembalikan true,
%                 proses dihentikan secepatnya (setelah frame berjalan).
%
%   OUTPUT:
%       results   struct array hasil per folder (dari processFolder).
%
%   Pola identik dengan versi 1: waitbar gabungan + log konsol, kegagalan
%   pada satu folder tidak menghentikan folder lain, tombol STOP bekerja
%   karena progressFcn memanggil drawnow. Perbedaan: tiap folder WAJIB
%   punya anchor stabilisasi DAN ROI cropping.

    if nargin < 3 || isempty(stopCheck)
        stopCheck = @() false;
    end

    util = pivprep.util.utilities;
    nFolders = numel(folders);

    % --- Opsi "kemas ke 1 .mat" (default mati: perilaku lama persis) ---
    packSingle = local_get(cfg, 'packSingleMat', false);
    keepFolder = local_get(cfg, 'keepFolder',    false);
    matOutDir  = local_get(cfg, 'matOutDir',     '');   % '' = di folder input
    if packSingle && isempty(which('pivprepPackFolder'))
        % Jembatan (2_bridge) belum di path: coba bootstrap project.
        if ~isempty(which('pivprepv2_setup'))
            try pivprepv2_setup(); catch; end
        end
        if isempty(which('pivprepPackFolder'))
            error('batchpivprep2:runBatch:noBridge', ...
                ['Opsi "kemas ke .mat" butuh pivprepPackFolder (2_bridge) di path. ' ...
                 'Jalankan pivprepv2_setup lebih dulu.']);
        end
    end

    results = repmat(struct('folder', '', 'nFrames', 0, 'nOK', 0, ...
        'nSkip', 0, 'outDirs', struct(), 'jitterSummary', struct(), ...
        'elapsed', 0, 'error', '', 'stopped', false, ...
        'outSize', [0 0], 'cropMode', '', ...
        'singleMat', '', 'mat_bytes', 0, 'folder_bytes', 0), nFolders, 1);

    totalFrames = sum([folders.nImg]);
    doneFrames  = 0;
    stopped     = false;

    % Nama subfolder keluaran unik (penting di mode 'root').
    outNames = local_uniqueOutNames(folders);
    for i = 1:nFolders
        folders(i).outName = outNames{i};
    end

    wb = waitbar(0, 'Memulai...', 'Name', 'BatchPIVPrep2 - Stabilisasi + Cropping Batch');
    cleanupWb = onCleanup(@() local_safeCloseWb(wb)); %#ok<NASGU>

    fprintf('\n========== BatchPIVPrep2: %d folder, %d frame total ==========\n', ...
        nFolders, totalFrames);
    tAll = tic;

    % --- STRATEGI A: paralel ANTAR-FOLDER (tiap worker 1 folder, serial di
    %     dalamnya). Algoritma per-folder TAK berubah (lastGood tetap bergulir
    %     di dalam worker) -> hasil IDENTIK; hanya antrean folder jadi serempak.
    %     Badan per-folder diekstrak ke local_oneFolder agar jalur serial &
    %     paralel memakai logika yang SAMA PERSIS. ---
    opts     = struct('packSingle', packSingle, 'keepFolder', keepFolder, ...
                      'matOutDir', matOutDir);
    template = results(1);   % skema 1-elemen untuk inisialisasi R di worker

    if i_useParforFolders(nFolders, cfg)
        % Pastikan pool + paket pada path worker (defensif; AutoAddClientPath
        % umumnya sudah cukup utk +pivprep/+batchpivprep2 & pivprepPackFolder).
        local_ensurePool();
        logCell = cell(nFolders, 1);
        dq = parallel.pool.DataQueue;
        afterEach(dq, @tickFrame);              % callback jalan di KLIEN (aman GUI)
        progressFcnPar = @(k, nF, s) local_dqTick(dq);
        fprintf('Mode PARALEL: %d folder diproses serempak...\n', nFolders);
        parfor i = 1:nFolders
            [results(i), logCell{i}] = ...
                local_oneFolder(folders(i), cfg, opts, template, progressFcnPar);
        end
        % Cetak header + ringkasan TERURUT setelah run paralel (log worker
        % tak terjamin urut, jadi dikumpulkan lalu dicetak di sini).
        for i = 1:nFolders
            fprintf('\n[Folder %d/%d] %s  (%d frame)\n', ...
                i, nFolders, folders(i).path, folders(i).nImg);
            fprintf('%s', logCell{i});
        end
        doneFrames = totalFrames;
    else
        for i = 1:nFolders
            if stopCheck()
                stopped = true;
                fprintf('\nSTOP: dihentikan sebelum folder %d.\n', i);
                break;
            end
            f = folders(i);
            [~, shortName] = fileparts(strip_sep(f.path));
            fprintf('\n[Folder %d/%d] %s  (%d frame)\n', i, nFolders, f.path, f.nImg);

            % Progress callback: perbarui waitbar gabungan + drawnow + cek stop.
            progressFcn = @(k, nF, statusStr) local_progress( ...
                wb, doneFrames + k, totalFrames, i, nFolders, shortName, statusStr, ...
                stopCheck);

            [results(i), logStr] = ...
                local_oneFolder(f, cfg, opts, template, progressFcn);
            fprintf('%s', logStr);

            doneFrames = doneFrames + f.nImg;
            if results(i).stopped
                stopped = true;
                break;
            end
        end
    end

    elapsedAll = toc(tAll);

    % --- Ringkasan akhir ---
    nDone = sum(arrayfun(@(r) isempty(r.error) && r.nFrames > 0, results));
    totalOK   = sum([results.nOK]);
    totalSkip = sum([results.nSkip]);

    fprintf('\n========== %s ==========\n', local_ternary(stopped, 'DIHENTIKAN', 'SELESAI'));
    fprintf('Folder diproses : %d / %d\n', nDone, nFolders);
    fprintf('Frame OK / Skip : %d / %d\n', totalOK, totalSkip);
    fprintf('Total waktu     : %.1f s (%s)\n', elapsedAll, util.secsToHMS(elapsedAll));
    fprintf('=============================\n\n');

    if stopped
        ttl = 'BatchPIVPrep2 - DIHENTIKAN';
        head = 'BatchPIVPrep2 DIHENTIKAN oleh pengguna.';
    else
        ttl = 'BatchPIVPrep2';
        head = 'BatchPIVPrep2 selesai.';
    end
    msg = sprintf([ ...
        '%s\n\n' ...
        'Folder diproses : %d / %d\n' ...
        'Frame OK / Skip : %d / %d\n' ...
        'Total waktu     : %.1f s (%s)\n\n' ...
        'Keluaran per folder: RAW_/GS_/EXIF_ + ANCHOR_used.mat + CROP_used.mat + JITTER_curve.png.'], ...
        head, nDone, nFolders, totalOK, totalSkip, elapsedAll, util.secsToHMS(elapsedAll));
    % Pop-up ringkasan akhir opsional (default ON = perilaku lama GUI Step 1).
    % Pemanggil non-interaktif (mis. PAB1 "Lanjutkan ke Step 2") set
    % cfg.showSummaryDialog=false agar tak ada pop-up setelah simpan MAT PREP.
    if local_get(cfg, 'showSummaryDialog', true)
        msgbox(msg, ttl, 'help');
    end

    % ---- nested: progres frame mode PARALEL (afterEach, jalan di klien) ----
    function tickFrame(~)
        doneFrames = doneFrames + 1;
        if ~isempty(wb) && ishandle(wb)
            waitbar(min(1, doneFrames / max(totalFrames, 1)), wb, ...
                sprintf('Paralel: %d / %d frame total', doneFrames, totalFrames));
        end
    end
end


% =====================================================================
function [R, logStr] = local_oneFolder(f, cfg, opts, template, progressFcn)
%LOCAL_ONEFOLDER  Proses SATU folder: validasi + stabilisasi/crop (processFolder)
%   + kemas .mat opsional + bersih temp. PARFOR-SAFE: tak menyentuh graphics/
%   handle GUI; progres lewat progressFcn (klien yang pasang waitbar/DataQueue).
%   Kembalikan hasil R (skema 'template', field identik) + logStr (ringkasan
%   untuk dicetak TERURUT oleh pemanggil). Logika SAMA PERSIS dgn versi serial.
    util = pivprep.util.utilities;
    R = template;
    R.folder = f.path;
    lg = '';

    % Wajib: anchor stabilisasi + ROI cropping.
    if ~isfield(f, 'anchor') || isempty(f.anchor)
        R.error = 'Tidak ada anchor stabilisasi yang di-assign.';
        logStr  = sprintf('  DILEWATI: belum ada anchor stabilisasi.\n');
        return;
    end
    if ~isfield(f, 'crop') || isempty(f.crop)
        R.error = 'Tidak ada ROI cropping yang di-assign.';
        logStr  = sprintf('  DILEWATI: belum ada ROI cropping.\n');
        return;
    end

    % Saat "kemas ke .mat": paksa keluaran ke temp DI DALAM folder input
    % (<input>/__pivprep_pack_tmp/<outName>), apa pun mode GUI. Folder standar
    % tetap dibuat di sana lalu dikemas + (opsional) dihapus.
    cfgThis = cfg;
    packTmpRoot = '';
    cleanupTmp = [];   %#ok<NASGU>  onCleanup: hapus temp walau error (bila ~keepFolder)
    if opts.packSingle
        packTmpRoot = fullfile(f.path, '__pivprep_pack_tmp');
        cfgThis.outputMode = 'root';
        cfgThis.outputRoot = packTmpRoot;
        % Jaring pengaman: bila processFolder/pack throw di tengah jalan, temp
        % di dalam folder INPUT tak boleh tertinggal (mengotori scan berikutnya).
        if ~opts.keepFolder
            cleanupTmp = onCleanup(@() local_rmTmp(packTmpRoot)); %#ok<NASGU>
        end
    end

    try
        % processFolder mengembalikan struct 11-field. R sudah berisi field
        % tambahan pack (singleMat/mat_bytes/folder_bytes) dari template, jadi
        % gabung per-field (jangan ganti seluruh struct) -> bentuk struct tetap
        % (hindari "Subscripted assignment between dissimilar structures").
        pf = batchpivprep2.core.processFolder(f, f.anchor, f.crop, cfgThis, progressFcn);
        R  = local_mergeInto(R, pf);
        if R.stopped
            lg = [lg sprintf('  DIHENTIKAN di tengah folder (OK %d, Skip %d).\n', ...
                R.nOK, R.nSkip)];
        else
            lg = [lg sprintf('  Selesai: OK %d, Skip %d, %.1f s (%s) | crop %s -> %d x %d px\n', ...
                R.nOK, R.nSkip, R.elapsed, util.secsToHMS(R.elapsed), ...
                R.cropMode, R.outSize(2), R.outSize(1))];
        end
        if isfield(R, 'jitterSummary') && isfield(R.jitterSummary, 'jitterRMS')
            js = R.jitterSummary;
            lg = [lg sprintf(['  Jitter: mean %.2f px, RMS %.2f px, max %.2f px | ' ...
                              'drift akhir (%.1f, %.1f) px\n'], ...
                js.jitterMean, js.jitterRMS, js.jitterMax, js.driftEndX, js.driftEndY)];
        end
        if isfield(R, 'outDirs') && isfield(R.outDirs, 'base')
            lg = [lg sprintf('  Output: %s\n', R.outDirs.base)];
        end

        % --- Kemas folder eksperimen -> 1 .mat (opsional) ---
        if opts.packSingle && ~R.stopped && isfield(R, 'outDirs') && ...
                isfield(R.outDirs, 'base') && isfolder(R.outDirs.base)
            if isempty(opts.matOutDir); thisMatDir = f.path; else; thisMatDir = opts.matOutDir; end
            if ~isfolder(thisMatDir); util.ensureDir(thisMatDir); end
            matPath = fullfile(thisMatDir, [f.outName '.mat']);
            seq = local_folderSeq(f);   % urutan file -> metadata di .mat
            % GS TIDAK disematkan: .mat hanya RAW + metadata GS (gs_scale/
            % gs_quality dari cfg). GS diregenerasi dari RAW saat analisis
            % (PABSA2 unpack) -> .mat jauh lebih irit.
            gsSc = 0.5; gsQ = 92;
            if isfield(cfgThis, 'gsScale');   gsSc = cfgThis.gsScale;   end
            if isfield(cfgThis, 'gsQuality'); gsQ  = cfgThis.gsQuality; end
            pk = pivprepPackFolder(R.outDirs.base, matPath, ...
                'Verbose', false, 'Sequencing', seq, ...
                'EmbedGS', false, 'GsScale', gsSc, 'GsQuality', gsQ, ...
                'SourceRaw', f.path);   % folder RAW asli -> jembatan key QPIV Step 0
            lg = [lg sprintf('  Urutan file (metadata) : %s\n', local_seqLabel(seq))];
            R.singleMat    = matPath;
            R.mat_bytes    = pk.mat_bytes;
            R.folder_bytes = pk.folder_bytes;
            lg = [lg sprintf('  Dikemas -> %s  (%.1f MB; folder %.1f MB)\n', ...
                matPath, pk.mat_bytes/1e6, pk.folder_bytes/1e6)];
            if ~opts.keepFolder
                local_rmTmp(packTmpRoot);   % hapus temp di folder input (idempoten; onCleanup jaring pengaman)
                lg = [lg sprintf('  Folder antara dihapus (simpan .mat saja).\n')];
            end
        end
    catch ME
        R.error = ME.message;
        lg = [lg sprintf('  GAGAL: %s\n', ME.message)];
    end
    logStr = lg;
end


function tf = i_useParforFolders(nFolders, cfg)
%I_USEPARFORFOLDERS  Putuskan paralel antar-folder. cfg.parallelFolders:
%   []=auto (paralel bila PCT ada & folder>=2), true/false=paksa. Tak ada PCT
%   atau 1 folder -> serial (perilaku lama persis).
    tf = false;
    pref = local_get(cfg, 'parallelFolders', []);
    if islogical(pref) && isscalar(pref)
        if ~pref, return; end                       % paksa serial
        tf = ~isempty(ver('parallel'));             % paksa paralel (bila PCT ada)
        return;
    end
    if nFolders < 2,             return; end          % 1 folder -> tak ada gunanya
    if isempty(ver('parallel')), return; end          % PCT tak ada -> serial
    tf = true;
end


function local_ensurePool()
%LOCAL_ENSUREPOOL  Pastikan parallel pool hidup + path paket pada worker.
%   AutoAddClientPath (default pool lokal) biasanya sudah membawa +pivprep/
%   +batchpivprep2 & pivprepPackFolder; addpath di sini sebagai pengaman.
    pool = gcp('nocreate');
    if isempty(pool)
        try
            pool = parpool;                          % profil default
        catch ME
            warning('batchpivprep2:runBatch:pool', ...
                'Gagal buka parallel pool (%s). Lanjut serial.', ME.message);
            return;
        end
    end
    if isempty(pool); return; end
    try
        thisDir = fileparts(mfilename('fullpath'));   % .../+batchpivprep2/+core
        pabRoot = fileparts(fileparts(thisDir));      % .../PAB
        roots = {pabRoot};
        pp = which('pivprepPackFolder');
        if ~isempty(pp); roots{end+1} = fileparts(pp); end
        fut = parfevalOnAll(@addpath, 0, roots{:});
        wait(fut);
    catch
    end
end


function stop = local_dqTick(dq)
%LOCAL_DQTICK  Progres 1 frame mode paralel: kirim ke DataQueue (afterEach di
%   klien yang memperbarui waitbar). STOP tak didukung di parfor -> selalu false.
    send(dq, 1);
    stop = false;
end


% =====================================================================
function stop = local_progress(wb, done, total, fi, nF, shortName, statusStr, stopCheck)
    if ~isempty(wb) && ishandle(wb)
        frac = min(1, done / max(total, 1));
        waitbar(frac, wb, sprintf('Folder %d/%d: %s\n%s  (%d/%d frame total)', ...
            fi, nF, shortName, statusStr, done, total));
    end
    drawnow limitrate;     % izinkan callback STOP berjalan
    stop = logical(stopCheck());
end


function local_safeCloseWb(wb)
    try
        if ~isempty(wb) && ishandle(wb); close(wb); end
    catch
    end
end


function p = strip_sep(p)
    if ~isempty(p) && (p(end) == filesep || p(end) == '/'); p(end) = []; end
end


function local_rmTmp(tmpRoot)
%LOCAL_RMTMP  Hapus folder temp pack bila masih ada (idempoten; dipakai onCleanup
%   & jalur sukses). Diam bila gagal (best-effort).
    try
        if ~isempty(tmpRoot) && isfolder(tmpRoot); rmdir(tmpRoot, 's'); end
    catch
    end
end


function out = local_ternary(cond, a, b)
    if cond; out = a; else, out = b; end
end


function dst = local_mergeInto(dst, src)
%LOCAL_MERGEINTO  Salin semua field src ke dst (per-field) tanpa mengubah
%   bentuk struct array tujuan. Field di dst yang tak ada di src dibiarkan
%   (mis. singleMat/mat_bytes/folder_bytes yang diisi belakangan). Aman
%   dipakai di dalam prealokasi struct array -> hindari "dissimilar
%   structures".
    fn = fieldnames(src);
    for c = 1:numel(fn)
        dst.(fn{c}) = src.(fn{c});
    end
end


function names = local_uniqueOutNames(folders)
%LOCAL_UNIQUEOUTNAMES  Nama subfolder keluaran unik per folder input.
    n = numel(folders);
    names = cell(n, 1);
    used = containers.Map('KeyType', 'char', 'ValueType', 'double');
    for i = 1:n
        base = '';
        if isfield(folders, 'outName') && ~isempty(folders(i).outName)
            base = local_sanitize(char(folders(i).outName));
        end
        if isempty(base)
            [~, base] = fileparts(strip_sep(folders(i).path));
        end
        if isempty(base); base = 'Folder'; end
        key = lower(base);
        if isKey(used, key)
            c = used(key) + 1;
            used(key) = c;
            names{i} = sprintf('%s_%d', base, c);
        else
            used(key) = 1;
            names{i}  = base;
        end
    end
end


function s = local_sanitize(s)
%LOCAL_SANITIZE  Bersihkan karakter yang tidak aman untuk nama folder.
    s = regexprep(s, '[\\/:*?"<>|]', '_');
    s = regexprep(s, '\s+', '_');
end


function v = local_get(s, fld, def)
%LOCAL_GET  Ambil field s.fld bila ada & tak kosong, jika tidak pakai def.
    if isstruct(s) && isfield(s, fld) && ~isempty(s.(fld))
        v = s.(fld);
    else
        v = def;
    end
end


function seq = local_folderSeq(f)
%LOCAL_FOLDERSEQ  Ambil urutan file folder (kolom tabel Step 1) -> struct.
%   {mode='consecutive'|'pairs'|'skip', step=N}. Folder lama tanpa field ini
%   -> default 'consecutive'. Normalisasi penuh dilakukan di pivprepPackFolder.
    mode = 'consecutive';
    step = 1;
    if isfield(f, 'seqMode') && ~isempty(f.seqMode)
        mode = char(f.seqMode);
    end
    if isfield(f, 'seqStep') && ~isempty(f.seqStep) && isnumeric(f.seqStep)
        step = max(1, round(double(f.seqStep)));
    end
    seq = struct('mode', mode, 'step', step);
end


function s = local_seqLabel(seq)
%LOCAL_SEQLABEL  Label ringkas urutan file untuk log konsol.
    switch lower(seq.mode)
        case 'pairs'
            s = 'Pairs (1-2, 3-4, ...)';
        case 'skip'
            s = sprintf('Skip-%d (1, %d, %d, ...)', seq.step, 1+seq.step, 1+2*seq.step);
        otherwise
            s = 'Consecutive (1-2, 2-3, ...)';
    end
end
