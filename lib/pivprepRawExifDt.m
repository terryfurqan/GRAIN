function info = pivprepRawExifDt(rawFolder, fn1, fn2)
%PIVPREPRAWEXIFDT  Interval waktu per-frame PIV langsung dari EXIF JPG MENTAH.
%
%   info = pivprepRawExifDt(rawFolder, fn1, fn2)
%
%   = pembaca waktu untuk GRAINSA0b. Berbeda dari PIVlab_automasi_exiftime yang
%   membaca tabel EXIF.mat hasil PIVPrep, fungsi ini membaca timestamp EXIF
%   LANGSUNG dari berkas JPG mentah (via imfinfo: DigitalCamera.DateTimeOriginal
%   + SubSecTimeOriginal) sehingga bisa dipakai pada folder RAW yang BELUM
%   diproses PIVPrep — kebutuhan GRAINSA0b (deteksi counter-wrap shutter).
%
%   ALIGNMENT FRAME: dt dihitung dari pasangan QPIV yang SUDAH dibentuk
%   (out.fn1/out.fn2), jadi indeks frame info.dt persis sama dengan frame
%   QPIV (|V| puncak). Untuk frame k: dt(k) = t(fn2{k}) - t(fn1{k}).
%
%   INPUT:
%       rawFolder  folder berisi JPG.
%       fn1, fn2   cellstr nama berkas pasangan tiap frame (out.fn1/out.fn2 dari
%                  PIVlab_automasi_qpiv). Panjang sama = nFrames.
%
%   OUTPUT info (struct):
%       .dt_s       [nF x 1] interval detik tiap frame (NaN bila tak terbaca).
%       .t0_s       [nF x 1] waktu mulai tiap pasangan relatif gambar pertama (det).
%       .nFrames    jumlah frame.
%       .median_dt  median dt valid (NaN bila nihil).
%       .n_valid    jumlah dt valid.
%       .status     'OK' | 'SEBAGIAN' | 'TANPA_WAKTU'.
%       .message    catatan diagnostik.
%
%   Lihat juga: PIVlab_automasi_qpiv, pivprepFrameExclusion, PIVlab_automasi_exiftime.

    fn1 = cellstr(fn1(:)); fn2 = cellstr(fn2(:));
    nF  = min(numel(fn1), numel(fn2));
    info = struct('dt_s', nan(nF,1), 't0_s', nan(nF,1), 'nFrames', nF, ...
        'median_dt', NaN, 'n_valid', 0, 'status', 'TANPA_WAKTU', 'message', '');
    if nF == 0; info.message = 'Tak ada pasangan frame.'; return; end

    cache = containers.Map('KeyType','char','ValueType','double');   % name -> datenum
    function t = timeOf(name)
        t = NaN;
        if isempty(name); return; end
        if isKey(cache, name); t = cache(name); return; end
        p = fullfile(rawFolder, name);
        if isfile(p)
            t = i_readExifTime(p);
        end
        cache(name) = t;
    end

    tA = nan(nF,1); tB = nan(nF,1);
    for k = 1:nF
        tA(k) = timeOf(fn1{k});
        tB(k) = timeOf(fn2{k});
    end
    dt = (tB - tA) * 86400;            % datenum (hari) -> detik
    info.dt_s = dt;

    validStart = isfinite(tA);
    if any(validStart)
        t0 = min(tA(validStart));
        info.t0_s = (tA - t0) * 86400;
    end

    nv = sum(isfinite(dt));
    info.n_valid = nv;
    if nv > 0; info.median_dt = median(dt(isfinite(dt))); end
    if nv == 0
        info.status = 'TANPA_WAKTU';
        info.message = 'EXIF DateTimeOriginal tak terbaca di JPG ini.';
    elseif nv < nF
        info.status = 'SEBAGIAN';
        info.message = sprintf('%d/%d frame ber-dt valid (median %.3g s).', nv, nF, info.median_dt);
    else
        info.status = 'OK';
        info.message = sprintf('Semua %d frame ber-dt valid (median %.3g s).', nF, info.median_dt);
    end
end


% =====================================================================
function dn = i_readExifTime(p)
%I_READEXIFTIME  Datenum waktu pemotretan dari EXIF JPG; NaN bila gagal.
%   Prioritas DateTimeOriginal (+SubSec) -> DateTimeDigitized -> DateTime.
    dn = NaN;
    try
        info = imfinfo(p);
    catch
        return;
    end
    if numel(info) > 1; info = info(1); end

    raw = ''; sub = '';
    if isfield(info, 'DigitalCamera') && isstruct(info.DigitalCamera)
        dc = info.DigitalCamera;
        raw = i_getstr(dc, 'DateTimeOriginal');
        if isempty(raw); raw = i_getstr(dc, 'DateTimeDigitized'); end
        sub = i_getstr(dc, 'SubSecTimeOriginal');
        if isempty(sub); sub = i_getstr(dc, 'SubsecTimeOriginal'); end
        if isempty(sub); sub = i_getstr(dc, 'SubSecTime'); end
    end
    if isempty(raw); raw = i_getstr(info, 'DateTime'); end
    if isempty(raw); return; end

    dt = i_parseOne(raw);
    if isnat(dt); return; end
    frac = i_subsec(sub);
    if ~isnan(frac); dt = dt + seconds(frac); end
    dn = datenum(dt); %#ok<DATNM>
end

function s = i_getstr(st, f)
    s = '';
    if isfield(st, f)
        v = st.(f);
        if ischar(v); s = strtrim(v);
        elseif isstring(v) && isscalar(v) && ~ismissing(v); s = char(strtrim(v));
        elseif isnumeric(v) && isscalar(v); s = num2str(v);
        end
    end
end

function dt = i_parseOne(s)
    dt = NaT;
    s = strtrim(char(s));
    if isempty(s); return; end
    fmts = {'yyyy:MM:dd HH:mm:ss', 'yyyy-MM-dd HH:mm:ss', ...
            'yyyy:MM:dd HH:mm:ss.SSS', 'yyyy-MM-dd HH:mm:ss.SSS'};
    for i = 1:numel(fmts)
        try
            dt = datetime(s, 'InputFormat', fmts{i});
            if ~isnat(dt); return; end
        catch
        end
    end
    try, dt = datetime(s); catch, dt = NaT; end
end

function frac = i_subsec(s)
    frac = NaN;
    s = strtrim(char(s));
    if isempty(s); return; end
    if all(isstrprop(s, 'digit')); frac = str2double(['0.' s]); end
end
