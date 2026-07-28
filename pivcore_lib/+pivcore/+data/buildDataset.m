function data = buildDataset(S)
%BUILDDATASET  Ekstraksi struct data terstandar dari hasil load .mat PIVLAB.
%
%   data = pivcore.data.buildDataset(S)
%
%   PERUBAHAN versi ini:
%     - Mendukung format bg_images terkompresi JPEG yang dihasilkan
%       oleh tabModif.saveMat:
%           S.bg_images_format  = 'jpeg_dedup_v1'
%           S.bg_images_blobs   = {uint8(:); ...}
%           S.bg_images_index   = uint32 vector
%           S.bg_images_quality = scalar
%       Saat dimuat, tiap frame di-decode kembali ke array uint8
%       H x W x C menggunakan imdecode (lewat berkas sementara, agar
%       kompatibel tanpa Image Acquisition Toolbox).
%     - Tetap kompatibel mundur dengan format lama (bg_images sebagai
%       cell of uint8 array).

    data = struct();

    fieldMap = {
        'x',                  {'x'}
        'y',                  {'y'}
        'u_original',         {'u_original'}
        'v_original',         {'v_original'}
        'u_filtered',         {'u_filtered'}
        'v_filtered',         {'v_filtered'}
        'u_smoothed',         {'u_smoothed'}
        'v_smoothed',         {'v_smoothed'}
        'u_component',        {'u_component'}
        'v_component',        {'v_component'}
        'velocity_magnitude', {'velocity_magnitude'}
        'vorticity',          {'vorticity'}
        'divergence',         {'divergence'}
        'shear_rate',         {'shear_rate'}
        'strain_rate',        {'strain_rate'}
        'q_criterion',        {'q_criterion'}
        'LIC',                {'LIC'}
        'vectorangle',        {'vectorangle'}
        'correlation_map',    {'correlation_map','correlation_m','correlation_matrix'}
        'typevector_original',{'typevector_original','typevector_or'}
        'typevector_filtered',{'typevector_filtered','typevector_filt'}
    };

    nFrames = 0;
    for k = 1:size(fieldMap, 1)
        intName  = fieldMap{k, 1};
        candList = fieldMap{k, 2};
        val = i_getFirstField(S, candList);
        if ~isempty(val) && iscell(val)
            data.(intName) = val(:);
            nFrames = max(nFrames, numel(val));
        else
            data.(intName) = {};
        end
    end

    data.calu  = i_getFirstField(S, {'calu'});
    data.calv  = i_getFirstField(S, {'calv'});
    data.calxy = i_getFirstField(S, {'calxy'});
    if isempty(data.calu),  data.calu  = 1; end
    if isempty(data.calv),  data.calv  = 1; end
    if isempty(data.calxy), data.calxy = 1; end

    units = i_getFirstField(S, {'units'});
    if isempty(units), units = '[px] respectively [frame]'; end
    if iscell(units), units = char(units{1}); end
    data.units = char(units);

    info = i_getFirstField(S, {'information'});
    if isempty(info), info = {}; end
    data.information = info;

    % ----- Background images: dukung format baru + lama -----
    data.bg_images = i_loadBackgroundImages(S);
    if ~isempty(data.bg_images)
        nFrames = max(nFrames, numel(data.bg_images));
    end

    data.nFrames = nFrames;
end


% =====================================================================
function v = i_getFirstField(S, names)
    v = [];
    for k = 1:numel(names)
        if isfield(S, names{k})
            v = S.(names{k});
            return;
        end
    end
end


% =====================================================================
function bg = i_loadBackgroundImages(S)
%I_LOADBACKGROUNDIMAGES  Resolve bg_images dari berbagai skema.

    bg = {};

    % --- Skema baru: jpeg_dedup_v1 ---
    if isfield(S, 'bg_images_format') && isfield(S, 'bg_images_blobs') ...
            && isfield(S, 'bg_images_index')
        fmt = S.bg_images_format;
        if iscell(fmt), fmt = fmt{1}; end
        fmt = char(fmt);

        switch lower(fmt)
            case 'jpeg_dedup_v1'
                bg = i_decodeJpegDedup(S.bg_images_blobs, S.bg_images_index);
                return;
            otherwise
                warning('Format bg_images tidak dikenal: %s. Diabaikan.', fmt);
                bg = {};
                return;
        end
    end

    % --- Skema lama: cell array uint8 mentah ---
    raw = i_getFirstField(S, {'bg_images','images','bg_img_A','background_images'});
    if isempty(raw)
        bg = {};
    elseif iscell(raw)
        bg = raw(:);
    else
        bg = {raw};
    end
end


% =====================================================================
function bg = i_decodeJpegDedup(blobs, idxRaw)
%I_DECODEJPEGDEDUP  Decode blob JPEG kembali menjadi cell array gambar.

    if ~iscell(blobs)
        bg = {};
        return;
    end
    idx = double(idxRaw(:));
    n = numel(idx);
    bg = cell(n, 1);

    % Cache per-blob: decode sekali, pakai untuk semua frame yang
    % mengacu blob yang sama (deduplikasi sisi-load).
    cache = cell(numel(blobs), 1);

    tmpFile = [tempname() '.jpg'];
    cleanup = onCleanup(@() i_safeDelete(tmpFile)); %#ok<NASGU>

    for k = 1:n
        b = idx(k);
        if b < 1 || b > numel(blobs)
            bg{k} = [];
            continue;
        end
        if isempty(cache{b})
            cache{b} = i_decodeOneBlob(blobs{b}, tmpFile);
        end
        bg{k} = cache{b};
    end
end


% =====================================================================
function img = i_decodeOneBlob(bytes, tmpFile)
    img = [];
    if isempty(bytes), return; end
    if ~isa(bytes,'uint8'), bytes = uint8(bytes); end
    fid = fopen(tmpFile, 'wb');
    if fid < 0
        warning('Tidak dapat menulis berkas JPEG sementara untuk dekompresi.');
        return;
    end
    fwrite(fid, bytes, 'uint8');
    fclose(fid);
    try
        img = imread(tmpFile);
    catch ME
        warning('Gagal mendekode JPEG: %s', ME.message);
        img = [];
    end
end


% =====================================================================
function i_safeDelete(p)
    try
        if exist(p, 'file'), delete(p); end
    catch
    end
end
