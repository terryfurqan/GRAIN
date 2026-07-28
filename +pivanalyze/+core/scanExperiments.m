function [folders, info] = scanExperiments(parent_folder, cfg)
%SCANEXPERIMENTS  Pindai/normalkan daftar eksperimen PIVPrep + laporan verbose.
%
%   [folders, info] = pivanalyze.core.scanExperiments(parent_folder, cfg)
%
%   - Bila cfg.Folders kosong: pindai parent_folder dengan PIVlab_automasi_scanprep.
%   - Pastikan field wajib (gsdir/exifdir/X0/X1/Lpos/outname) tersedia.
%   - Hitung nama keluaran unik (PIVlab_automasi_uniquenames).
%   - Tulis laporan ke cfg.LogFcn (atau Command Window).
%
%   info : struct ringkas { nFolders, totalFiles, totalPairs, w,
%          nWithDrop, totalDrop }.
%
%   Logika dipertahankan persis dari blok "pindai/laporan" PIVlab_automasi_batch_V4.

    u   = pivanalyze.util.utilities;
    log = @(varargin) i_log(cfg, varargin{:});
    bar = repmat('=', 1, 70);
    sub = repmat('-', 1, 70);

    seq       = cfg.Sequencing;
    gsPattern = char(cfg.GSPattern);
    dropFirst = logical(cfg.DropFirstGS); %#ok<NASGU>
    doTime    = logical(cfg.EmbedExifTime);
    doTable   = logical(cfg.EmbedExifTable);
    nw        = round(cfg.NumWorkers);
    intAreas  = cfg.IntAreas;
    numPasses = round(cfg.NumPasses);
    readProg  = logical(cfg.ReadProgress);

    log(bar);
    log('  PIVlab AUTOMASI  --  ENGINE pivanalyze (PIV + GS + waktu EXIF + geometri + buang frame)');
    log(bar);
    if isfolder(parent_folder)
        log('Folder induk : %s', parent_folder);
    elseif ~isempty(cfg.Folders)
        log('Sumber       : daftar eksperimen yang diberikan (%d)', numel(cfg.Folders));
    end

    if isempty(cfg.Folders)
        if cfg.Recursive
            log('Memindai eksperimen PIVPrep (RAW+GS) secara rekursif ...');
        else
            log('Memindai eksperimen PIVPrep (RAW+GS) di subfolder langsung ...');
        end
        folders = PIVlab_automasi_scanprep(parent_folder, ...
            'Recursive', cfg.Recursive, 'MinImages', cfg.MinImages, ...
            'Suffix', cfg.Suffix, 'Sequencing', seq, 'GsPattern', gsPattern);
    else
        folders = cfg.Folders;
    end
    nFolders = numel(folders);

    info = struct('nFolders', nFolders, 'totalFiles', 0, 'totalPairs', 0, ...
        'w', 10, 'nWithDrop', 0, 'totalDrop', 0);
    if nFolders == 0
        log('');
        log('!! Tidak ditemukan folder eksperimen (berisi subfolder RAW & GS) di bawah folder induk.');
        return;
    end

    if ~isfield(folders, 'gsdir')
        error('pivanalyze:scanExperiments:noGS', ...
            'Setiap entri ''Folders'' harus punya field .gsdir (gunakan PIVlab_automasi_scanprep).');
    end
    folders = u.ensureField(folders, 'exifdir', '');
    folders = u.ensureField(folders, 'X0',   NaN);
    folders = u.ensureField(folders, 'X1',   NaN);
    folders = u.ensureField(folders, 'Lpos', NaN);

    outRoot = char(cfg.OutputFolder);
    if ~isfield(folders, 'outname'); [folders.outname] = deal(''); end
    for i = 1:nFolders
        if isempty(folders(i).outname); folders(i).outname = folders(i).name; end
    end
    destdirs = cell(1, nFolders);
    for i = 1:nFolders
        if isempty(outRoot); destdirs{i} = folders(i).expdir; else; destdirs{i} = outRoot; end
    end
    finalNames = PIVlab_automasi_uniquenames(destdirs, {folders.outname});

    totalFiles = sum([folders.count]);
    totalPairs = sum([folders.npairs]);
    w = max([cellfun(@numel, {folders.relpath}), 10]);

    log('');
    if isempty(outRoot)
        log('Folder output : (.mat disimpan di folder eksperimen masing-masing)');
    else
        log('Folder output : %s', outRoot);
    end
    log('IW pass       : %s  | jumlah pass: %d', mat2str(round(intAreas)), numPasses);
    log('Ditemukan %d eksperimen PIVPrep:', nFolders);
    nWithDrop = 0; totalDrop = 0;
    for k = 1:nFolders
        folders(k).outname = finalNames{k};
        dvFallback = '';
        if isfield(folders(k), 'pab_src'); dvFallback = folders(k).pab_src; end
        dv = u.getIgnore(PIVlab_automasi_progress('key', folders(k).expdir), cfg.IgnoreMap, readProg, dvFallback);
        dv = dv(dv >= 1 & dv <= folders(k).npairs);
        if ~isempty(dv); nWithDrop = nWithDrop + 1; totalDrop = totalDrop + numel(dv); end
        dtxt = ''; if ~isempty(dv); dtxt = sprintf('  [buang %d frame]', numel(dv)); end
        mism = '';
        if folders(k).gscount ~= folders(k).count
            mism = sprintf('  [!] #GS=%d != #RAW=%d', folders(k).gscount, folders(k).count);
        end
        log('  [%2d] %-*s : RAW %4d (%s) -> %4d pasangan | GS %4d -> %s.mat%s%s', ...
            k, w, folders(k).relpath, folders(k).count, folders(k).suffix, ...
            folders(k).npairs, folders(k).gscount, folders(k).outname, dtxt, mism);
    end
    log(sub);
    log('TOTAL : %d eksperimen | %d gambar RAW | %d pasangan frame | %d eksperimen ber-frame-dibuang (%d frame)', ...
        nFolders, totalFiles, totalPairs, nWithDrop, totalDrop);
    log('Setelan: %d worker | urutan=%s | GS q=%d | abaikan-foto-1=%d | waktu-EXIF=%d | tabel-EXIF=%d', ...
        nw, seq, round(cfg.GSQuality), logical(cfg.DropFirstGS), doTime, doTable);
    log(bar);

    info.totalFiles = totalFiles;
    info.totalPairs = totalPairs;
    info.w          = w;
    info.nWithDrop  = nWithDrop;
    info.totalDrop  = totalDrop;
end

function i_log(cfg, varargin)
    if isempty(varargin); str = ''; else; str = sprintf(varargin{:}); end
    if ~isempty(cfg.LogFcn)
        try cfg.LogFcn(str); catch; end
    else
        fprintf('%s\n', str);
    end
end
