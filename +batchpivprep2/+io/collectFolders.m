function folders = collectFolders(parentDir, recursive)
%COLLECTFOLDERS  Temukan folder image-sequence untuk diproses batch.
%
%   folders = batchpivprep2.io.collectFolders(parentDir, recursive)
%
%   INPUT:
%       parentDir   folder yang dipilih user.
%       recursive   logical. true  -> telusuri parentDir DAN seluruh
%                                      subfolder secara rekursif.
%                            false -> hanya parentDir itu sendiri.
%
%   OUTPUT:
%       folders   struct array (mungkin kosong) dengan field:
%           .path   path absolut folder
%           .files  cell array nama gambar (natural sort)
%           .nImg   jumlah gambar
%
%   Hanya folder yang BERISI minimal satu gambar yang didukung yang
%   dikembalikan. Folder keluaran dari proses sebelumnya (nama diawali
%   RAW_, GS_, atau EXIF_  -- juga RAW/GS/EXIF polos) DILEWATI agar
%   hasil olahan tidak ikut diproses ulang. Folder tersembunyi (diawali
%   titik) juga dilewati. Perilaku identik dengan BatchPIVPrep versi 1.

    if nargin < 2 || isempty(recursive)
        recursive = false;
    end

    folders = struct('path', {}, 'files', {}, 'nImg', {});

    if nargin < 1 || isempty(parentDir) || ~isfolder(parentDir)
        return;
    end
    parentDir = char(parentDir);

    % --- Kumpulkan daftar kandidat folder ---
    if recursive
        candidates = local_listSubfoldersRecursive(parentDir);
        candidates = [{parentDir}; candidates(:)];
    else
        candidates = {parentDir};
    end

    % --- Saring: lewati folder keluaran & tanpa gambar ---
    seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    for k = 1:numel(candidates)
        p = candidates{k};
        key = lower(p);
        if isKey(seen, key); continue; end
        seen(key) = true;

        if local_isOutputFolder(p)
            continue;
        end

        files = batchpivprep2.io.listImages(p);
        if isempty(files)
            continue;
        end

        folders(end + 1) = struct( ...
            'path',  p, ...
            'files', {files}, ...
            'nImg',  numel(files)); %#ok<AGROW>
    end
end


% =====================================================================
function subs = local_listSubfoldersRecursive(root)
%LOCAL_LISTSUBFOLDERSRECURSIVE  Semua subfolder (rekursif) di bawah root.
%   Folder keluaran (RAW_/GS_/EXIF_) dan tersembunyi tidak ditelusuri
%   lebih dalam (pemangkasan) agar cepat dan tidak membaca hasil olahan.
    subs  = {};
    stack = {root};
    while ~isempty(stack)
        cur   = stack{end};
        stack(end) = [];
        d = dir(cur);
        for i = 1:numel(d)
            if ~d(i).isdir, continue; end
            nm = d(i).name;
            if strcmp(nm, '.') || strcmp(nm, '..'), continue; end
            if startsWith(nm, '.'), continue; end          % tersembunyi
            full = fullfile(cur, nm);
            if local_isOutputFolder(full)
                continue;                                  % jangan telusuri keluaran
            end
            subs{end + 1} = full;        %#ok<AGROW>
            stack{end + 1} = full;       %#ok<AGROW>
        end
    end
end


% =====================================================================
function tf = local_isOutputFolder(p)
%LOCAL_ISOUTPUTFOLDER  true jika nama folder tampak seperti KELUARAN olahan,
%   BUKAN image-sequence input. Dua kelompok, case-insensitive:
%     (1) keluaran BatchPIVPrep/PIVPrep: RAW, GS, EXIF -- polos / bersufiks
%         (RAW_xxx, GS-xxx, EXIFxxx).
%     (2) keluaran EKSPOR bergambar (JPG/PNG) yang bila ikut terpindai akan
%         salah-terdeteksi sbg "eksperimen": PAB_export, PABLINK_export, dan
%         subfoldernya velmag / shear / _preview (berisi frame JPG hasil render).
%   SENGAJA TIDAK memangkas PIV_<tgl>/ maupun "montage/montase": pola PIV_*
%   berisiko menabrak nama eksperimen input (domain PIV), dan folder PIV_<tgl>/
%   berisi .mat (otomatis dilewati listImages); montase PAB3 = file PNG tunggal
%   (bukan folder), modul itu akan di-deprecate.
    [~, nm] = fileparts(p);
    tf = ~isempty(regexpi(nm, ...
        '^(RAW|GS|EXIF|PAB_export|PABLINK_export|velmag|shear|_preview)([_\-].*)?$', ...
        'once'));
end
