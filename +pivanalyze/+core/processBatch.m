function [summary, aborted] = processBatch(folders, cfg)
%PROCESSBATCH  Loop analisis PIV per-eksperimen (engine inti +pivanalyze).
%
%   [summary, aborted] = pivanalyze.core.processBatch(folders, cfg)
%
%   folders : struct-array eksperimen siap-pakai (keluaran
%             pivanalyze.core.scanExperiments; outname sudah final).
%   cfg     : struct dari pivanalyze.config.
%
%   Untuk tiap eksperimen:
%     A. PIV pada folder RAW (PIVlab_automasi, IW dapat di-override)
%     B. petakan frame->GS, kemas (PIVlab_automasi_packgs), sematkan ke .mat
%     C. waktu EXIF (PIVlab_automasi_exiftime) + geometri/strain -> .mat
%     D. buang frame mati yang ditandai Quick PIV (PIVlab_automasi_dropframes)
%
%   summary : struct-array ringkasan per-eksperimen (lihat empty_summary).
%   aborted : logical (true bila CheckAbort meminta berhenti).
%
%   Logika dipertahankan persis dari blok "proses tiap eksperimen"
%   PIVlab_automasi_batch_V4; subfungsi dipindah ke +io/+geom/+util.

    u   = pivanalyze.util.utilities;
    log = @(varargin) i_log(cfg, varargin{:});
    bar = repmat('=', 1, 70);
    sub = repmat('-', 1, 70);

    checkAbortFcn = cfg.CheckAbort;
    if isempty(checkAbortFcn); checkAbortFcn = @() false; end
    aborted = false;

    seq        = cfg.Sequencing;
    dropFirst  = logical(cfg.DropFirstGS);
    gsPattern  = char(cfg.GSPattern);
    exifName   = char(cfg.ExifName);
    doTime     = logical(cfg.EmbedExifTime);
    doTable    = logical(cfg.EmbedExifTable);
    intAreas   = cfg.IntAreas;
    numPasses  = round(cfg.NumPasses);
    nw         = round(cfg.NumWorkers);
    skipGlobal = round(cfg.Skip);
    readProg   = logical(cfg.ReadProgress);
    outRoot    = char(cfg.OutputFolder);
    prov       = cfg.Provenance;

    nFolders = numel(folders);
    summary  = empty_summary();
    if nFolders == 0; return; end
    w = max([cellfun(@numel, {folders.relpath}), 10]);

    batchClock = tic;
    for idx = 1:nFolders
        if checkAbortFcn()
            aborted = true;
            log('');
            log('>>> DIBATALKAN oleh pengguna setelah %d dari %d eksperimen.', numel(summary), nFolders);
            break;
        end
        log('');
        log(bar);
        log('[%d/%d] Eksperimen : %s', idx, nFolders, folders(idx).relpath);
        log('       RAW: %s', folders(idx).path);
        log('       GS : %s  (%d citra)', folders(idx).gsdir, folders(idx).gscount);
        log(bar);

        t0 = tic;
        status = 'OK'; emsg = ''; outfile = ''; npairs = folders(idx).npairs;
        nGsEmbed = 0; nGsUnique = 0;
        exifStatus = 'TIDAK'; nDtValid = 0; nDtTot = 0; dtMed = NaN; timeField = '';
        nDropped = 0; nKept = npairs;
        geom = pivanalyze.geom.computeGeometry(folders(idx).X0, folders(idx).X1, folders(idx).Lpos, prov);

        % Urutan pasangan PER-EKSPERIMEN: bila QPIV sudah dilakukan, pakai urutan
        % yang dipakai QPIV (tersimpan di progres) agar INDEKS frame yang dibuang
        % (ignore_frames) tetap cocok. Bila tidak, pakai urutan global.
        expKey  = PIVlab_automasi_progress('key', folders(idx).expdir);
        seqThis = seq; skipThis = skipGlobal;
        iwThis  = intAreas; npassThis = numPasses;   % default = global panel
        % Jembatan QPIV Step 0: bila entry tak ada di key .mat, coba folder RAW
        % asli (pab_src) yang dipakai Step 0b. '' -> tak ada fallback.
        pabSrc  = '';
        if isfield(folders(idx), 'pab_src'); pabSrc = folders(idx).pab_src; end
        peThis  = PIVlab_automasi_progress('get', expKey, pabSrc);
        qpivOverride = ~isfield(cfg, 'QpivParamsOverride') || logical(cfg.QpivParamsOverride);
        if qpivOverride && ~isempty(peThis) && isfield(peThis, 'qpiv_done') && peThis.qpiv_done
            if isfield(peThis, 'sequencing') && ~isempty(peThis.sequencing)
                seqThis = peThis.sequencing;
            end
            if isfield(peThis, 'skip') && ~isempty(peThis.skip)
                skipThis = round(peThis.skip);
            end
            % IW pass & jumlah pass HASIL evaluasi QPIV jadi DASAR PIV penuh
            % exp ini (menimpa IntAreas/NumPasses global panel).
            if isfield(peThis, 'iw_passes') && ~isempty(peThis.iw_passes)
                iwThis = double(peThis.iw_passes(:)');
                if numel(iwThis) < 4; iwThis(end+1:4) = 16; end
            end
            if isfield(peThis, 'num_passes') && ~isempty(peThis.num_passes)
                npassThis = round(peThis.num_passes);
            end
            if ~strcmpi(seqThis, seq) || skipThis ~= skipGlobal
                log('   [i] Dari QPIV: urutan=%s, skip=%d (menimpa global urutan=%s, skip=%d).', ...
                    seqThis, skipThis, seq, skipGlobal);
            end
            if ~isequal(iwThis, intAreas) || npassThis ~= numPasses
                log('   [i] Dari QPIV: IW=[%s] #pass=%d (menimpa global IW=[%s] #pass=%d).', ...
                    i_iwStr(iwThis), npassThis, i_iwStr(intAreas), numPasses);
            end
        end
        gsStride = skipThis + 1;

        if ~isempty(cfg.ProgressFcn)
            thisIdx = idx; thisName = folders(idx).name;
            pfPIV = @(frac, msg) i_prog(cfg, (thisIdx - 1 + 0.72*frac) / nFolders, ...
                sprintf('[%d/%d] %s — PIV: %s', thisIdx, nFolders, thisName, msg));
            pfGS  = @(frac, msg) i_prog(cfg, (thisIdx - 1 + 0.72 + 0.16*frac) / nFolders, ...
                sprintf('[%d/%d] %s — GS: %s', thisIdx, nFolders, thisName, msg));
        else
            pfPIV = []; pfGS = [];
        end

        if isempty(outRoot); thisOut = folders(idx).expdir; else; thisOut = outRoot; end

        try
            % --- FASE A: analisis PIV (IW dapat di-override) pada folder RAW ---
            res = PIVlab_automasi(folders(idx).path, ...
                'NumWorkers', nw, 'Sequencing', seqThis, 'Skip', skipThis, ...
                'Suffix', folders(idx).suffix, ...
                'OutputName', folders(idx).outname, 'OutputFolder', thisOut, ...
                'PIVlabRoot', cfg.PIVlabRoot, 'IntAreas', iwThis, ...
                'NumPasses', npassThis, 'ProgressFcn', pfPIV);
            outfile = res.output_file;
            npairs  = res.num_pairs;
            nKept   = npairs;
            log('   PIV OK (%d pasangan, %.1f detik). Menyematkan GS...', npairs, toc(t0));

            % --- FASE B: petakan frame -> GS, kemas, sematkan ke .mat ---
            gsSorted = pivanalyze.io.listGsSorted(folders(idx).gsdir, gsPattern);
            if gsStride > 1 && ~isempty(gsSorted)
                gsSorted = gsSorted(1:gsStride:end);   % subsample GS sejajar skip RAW
            end
            if isempty(gsSorted)
                status = 'OK (tanpa GS)';
                emsg = 'Folder GS kosong / tak cocok pola; .mat tetap berisi PIV lengkap.';
                log('   [!] %s', emsg);
            else
                gsPerFrame = pivanalyze.io.mapFramesToGs(gsSorted, npairs, seqThis, dropFirst);
                pack = PIVlab_automasi_packgs(gsPerFrame, ...
                    'Quality', round(cfg.GSQuality), 'ReencodeJpeg', logical(cfg.ReencodeJpeg), ...
                    'ProgressFcn', pfGS, 'LogFcn', @(m) log('   %s', m));
                pivanalyze.io.embedGS(outfile, pack, folders(idx).gsdir, prov);
                nGsEmbed  = pack.nRead;
                nGsUnique = pack.nUnique;
                log('   GS tersemat: %d frame berlatar (%d blob unik).', nGsEmbed, nGsUnique);
            end

            % --- FASE C: waktu EXIF (dt per-frame) + geometri ---
            i_prog(cfg, (idx - 1 + 0.90) / nFolders, ...
                sprintf('[%d/%d] %s — Waktu EXIF & geometri...', idx, nFolders, folders(idx).name));
            tinfo = [];
            if doTime
                exifdir = pivanalyze.io.resolveExifDir(folders(idx), exifName);
                rawNames = pivanalyze.io.rawSortedNames(folders(idx).path, folders(idx).suffix);
                if gsStride > 1 && ~isempty(rawNames)
                    rawNames = rawNames(1:gsStride:end);   % subsample sejajar skip RAW
                end
                tinfo = PIVlab_automasi_exiftime(exifdir, rawNames, seqThis, 'LoadTable', doTable);
                exifStatus = tinfo.status;
                nDtValid   = tinfo.n_dt_valid;
                nDtTot     = tinfo.nFrames;
                dtMed      = tinfo.dt_median_s;
                timeField  = tinfo.time_field;
                log('   Waktu EXIF: %s — %s', exifStatus, tinfo.message);
            end
            pivanalyze.io.embedTimeGeom(outfile, tinfo, geom, doTable, prov);
            if geom.valid
                log('   Geometri: strain_cumm=%+.4g%% (%s)', geom.strain_cumm_pct, geom.mode);
            end

            log('   PIV+embed selesai (%.1f detik total).', toc(t0));
        catch ME
            status = 'GAGAL';
            emsg   = ME.message;
            log('   --> GAGAL: %s', emsg);
        end

        % --- FASE D: buang frame yang ditandai abaikan (Quick PIV) ---
        if ~strcmp(status, 'GAGAL') && ~isempty(outfile) && isfile(outfile)
            ignFallback = '';
            if isfield(folders(idx), 'pab_src'); ignFallback = folders(idx).pab_src; end
            dropVec = u.getIgnore(PIVlab_automasi_progress('key', folders(idx).expdir), ...
                cfg.IgnoreMap, readProg, ignFallback);
            dropVec = dropVec(dropVec >= 1 & dropVec <= npairs);
            if ~isempty(dropVec)
                i_prog(cfg, (idx - 1 + 0.97) / nFolders, ...
                    sprintf('[%d/%d] %s — Membuang %d frame mati...', idx, nFolders, ...
                    folders(idx).name, numel(dropVec)));
                try
                    cinfo = PIVlab_automasi_dropframes(outfile, dropVec);
                    nDropped = cinfo.nDrop; nKept = cinfo.nKept;
                    log('   Frame diabaikan dibuang: %d (tersisa %d dari %d).', ...
                        nDropped, nKept, npairs);
                catch ME
                    log('   [!] Gagal membuang frame: %s', ME.message);
                end
            end
        end

        log('   --> Tersimpan: %s', outfile);

        summary(end+1) = struct('name', folders(idx).name, 'relpath', folders(idx).relpath, ...
            'path', folders(idx).path, 'gsdir', folders(idx).gsdir, 'output_file', outfile, ...
            'status', status, 'message', emsg, 'num_pairs', npairs, ...
            'n_gs_embedded', nGsEmbed, 'n_gs_unique', nGsUnique, ...
            'exif_status', exifStatus, 'n_dt_valid', nDtValid, 'n_dt_total', nDtTot, ...
            'dt_median_s', dtMed, 'time_field', timeField, ...
            'strain_cumm', geom.strain_cumm, 'geom_mode', geom.mode, 'geom_valid', geom.valid, ...
            'n_dropped', nDropped, 'n_kept', nKept, 'elapsed_s', toc(t0)); %#ok<AGROW>
    end

    % --- ringkasan ---
    nOK = sum(~strcmp({summary.status}, 'GAGAL'));
    nDropAll = sum([summary.n_dropped]);
    log('');
    log(bar);
    log('  RINGKASAN BATCH (pivanalyze)');
    log(bar);
    for k = 1:numel(summary)
        if strcmp(summary(k).status, 'GAGAL')
            log('  [%2d] %-*s : GAGAL  -> %s', k, w, summary(k).relpath, summary(k).message);
        else
            gtxt = 'geom -';
            if summary(k).geom_valid
                gtxt = sprintf('strain %+.3g%% (%s)', summary(k).strain_cumm*100, summary(k).geom_mode);
            end
            dtxt = '';
            if summary(k).n_dropped > 0
                dtxt = sprintf(' | buang %d->%d', summary(k).n_dropped, summary(k).n_kept);
            end
            log('  [%2d] %-*s : %-13s | GS:%d | dt:%d/%d %s | %s%s', k, w, summary(k).relpath, ...
                summary(k).status, summary(k).n_gs_embedded, summary(k).n_dt_valid, ...
                summary(k).n_dt_total, summary(k).exif_status, gtxt, dtxt);
        end
    end
    log(sub);
    if aborted
        log('DIBATALKAN: %d selesai (%d berhasil), %d frame dibuang total. Total waktu: %.1f detik.', ...
            numel(summary), nOK, nDropAll, toc(batchClock));
    else
        log('Berhasil %d dari %d eksperimen | %d frame mati dibuang total. Total waktu: %.1f detik.', ...
            nOK, nFolders, nDropAll, toc(batchClock));
    end
    log(bar);

    if ~isempty(cfg.ProgressFcn)
        if aborted
            i_prog(cfg, numel(summary)/max(1,nFolders), ...
                sprintf('Dibatalkan: %d/%d eksperimen diproses.', numel(summary), nFolders));
        else
            i_prog(cfg, 1, sprintf('Batch selesai: %d/%d berhasil, %d frame dibuang.', ...
                nOK, nFolders, nDropAll));
        end
    end
end

%% ----------------------------------------------------------- helper lokal
function s = empty_summary()
    s = struct('name', {}, 'relpath', {}, 'path', {}, 'gsdir', {}, 'output_file', {}, ...
        'status', {}, 'message', {}, 'num_pairs', {}, 'n_gs_embedded', {}, ...
        'n_gs_unique', {}, 'exif_status', {}, 'n_dt_valid', {}, 'n_dt_total', {}, ...
        'dt_median_s', {}, 'time_field', {}, 'strain_cumm', {}, 'geom_mode', {}, ...
        'geom_valid', {}, 'n_dropped', {}, 'n_kept', {}, 'elapsed_s', {});
end

function i_log(cfg, varargin)
    if isempty(varargin); str = ''; else; str = sprintf(varargin{:}); end
    if ~isempty(cfg.LogFcn)
        try cfg.LogFcn(str); catch; end
    else
        fprintf('%s\n', str);
    end
end

function i_prog(cfg, frac, msg)
    if isempty(cfg.ProgressFcn); return; end
    try cfg.ProgressFcn(max(0, min(1, frac)), msg); catch; end
end

function s = i_iwStr(iw)
    iw = round(double(iw(:)'));
    s = strjoin(arrayfun(@(v) num2str(v), iw, 'UniformOutput', false), ' ');
end
