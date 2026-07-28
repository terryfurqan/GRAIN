function [imgFirst, imgLast, nFrames, fmt] = readPivBgPair(matEntry)
%READPIVBGPAIR  Decode latar GS bingkai AWAL + AKHIR dari MAT PIV (1x load).
%
%   [imgFirst, imgLast, nFrames, fmt] = ...
%       pivanalyzemat.core.readPivBgPair(matEntry)
%
%   BEDA dgn readMatFramePair (yang membaca prep.raw dari MAT PREP Step 1):
%   fungsi ini membaca LATAR GS yang sudah TERSEMAT di MAT PIV (output Step 2),
%   yaitu variabel bg_images_blobs / bg_images_index (skema jpeg_dedup_v1,
%   lihat pivanalyze.io.embedGS). MAT PIV self-contained -> editor X0/X1/Lpos
%   tak perlu MAT PREP induk. Inilah foto ber-penggaris-cm yang dibaca manual.
%
%   matEntry : char path .mat ATAU struct dgn field .file / .matfile.
%
%   imgFirst/imgLast : citra (decode JPEG/PNG) bingkai pertama & terakhir,
%                      [] bila tak ada latar. nFrames = jumlah bingkai latar.
%   fmt              : char format ('jpeg_dedup_v1' / 'cell' / '').
%
%   Hanya menyentuh variabel bg_* (load selektif) -> TIDAK memuat blob PIV
%   besar (x/u/v) ke RAM. Lihat juga: pivanalyzemat.core.readMatFramePair.

    imgFirst = []; imgLast = []; nFrames = 0; fmt = '';

    matPath = i_matPath(matEntry);
    if isempty(matPath) || ~isfile(matPath)
        error('pivanalyzemat:readPivBgPair:noFile', ...
            'Berkas .mat tidak ada:\n%s', matPath);
    end

    info  = whos('-file', matPath);
    names = {info.name};

    % --- Skema baru: jpeg_dedup_v1 (bg_images_blobs + bg_images_index) ---
    if any(strcmp(names,'bg_images_blobs')) && any(strcmp(names,'bg_images_index'))
        S = load(matPath, 'bg_images_blobs', 'bg_images_index', 'bg_images_format');
        fmt = 'jpeg_dedup_v1';
        if isfield(S,'bg_images_format') && ~isempty(S.bg_images_format)
            f = S.bg_images_format; if iscell(f), f = f{1}; end
            fmt = char(f);
        end
        blobs = S.bg_images_blobs;
        idx   = double(S.bg_images_index(:));
        nFrames = numel(idx);
        if nFrames == 0 || ~iscell(blobs), return; end
        imgFirst = i_decodeAt(blobs, idx, 1);
        imgLast  = i_decodeAt(blobs, idx, nFrames);
        return;
    end

    % --- Skema lama: cell array uint8 (bg_images / images / ...) ---
    cand = {'bg_images','images','bg_img_A','background_images'};
    nm = '';
    for k = 1:numel(cand)
        if any(strcmp(names, cand{k})), nm = cand{k}; break; end
    end
    if isempty(nm), return; end           % tak ada latar tersemat
    fmt = 'cell';
    S = load(matPath, nm);
    C = S.(nm);
    if ~iscell(C), C = {C}; end
    nFrames = numel(C);
    if nFrames == 0, return; end
    imgFirst = i_asImage(C{1});
    imgLast  = i_asImage(C{nFrames});
end

%% ===================================================================
function img = i_decodeAt(blobs, idx, k)
%I_DECODEAT  Decode bingkai ke-k (lewat index dedup) jadi citra.
    img = [];
    if k < 1 || k > numel(idx), return; end
    bi = idx(k);
    if bi < 1 || bi > numel(blobs), return; end
    img = i_decodeBytes(blobs{bi});
end

function img = i_decodeBytes(bytes)
%I_DECODEBYTES  Decode byte JPEG/PNG -> citra via SATU berkas sementara.
    img = [];
    tmp = [tempname '.jpg'];
    cleaner = onCleanup(@() i_rm(tmp)); %#ok<NASGU>
    try
        fid = fopen(tmp, 'wb');
        if fid < 0, return; end
        fwrite(fid, bytes, 'uint8');
        fclose(fid);
        img = imread(tmp);
    catch
        img = [];
    end
end

function img = i_asImage(x)
%I_ASIMAGE  Skema lama bisa simpan byte JPEG (uint8 vektor) ATAU matriks citra.
    img = [];
    if isempty(x), return; end
    if isvector(x) && isa(x,'uint8')
        img = i_decodeBytes(x);
        if ~isempty(img), return; end
    end
    img = x;   % sudah berupa matriks citra
end

function i_rm(p)
    try, if isfile(p), delete(p); end; catch, end %#ok<CTCH>
end

function p = i_matPath(matEntry)
    if ischar(matEntry) || isstring(matEntry)
        p = char(matEntry);
    elseif isstruct(matEntry) && isfield(matEntry, 'file')
        p = char(matEntry.file);
    elseif isstruct(matEntry) && isfield(matEntry, 'matfile')
        p = char(matEntry.matfile);
    else
        p = '';
    end
end
