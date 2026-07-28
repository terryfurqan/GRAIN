function rgb = grayCLAHE(bg, useCLAHE, useAdjust)
%GRAYCLAHE  Citra latar -> GRAYSCALE (paksa) + CLAHE + auto kontras/brightness
%   opsional -> RGB [0,1].
%
%   rgb = pivcore.util.grayCLAHE(bg)                 % grayscale + CLAHE + adjust (semua ON)
%   rgb = pivcore.util.grayCLAHE(bg, useCLAHE)       % atur CLAHE saja
%   rgb = pivcore.util.grayCLAHE(bg, useCLAHE, useAdjust)  % + auto kontras/brightness
%
%   Selalu mengembalikan GRAYSCALE direplikasi ke 3 kanal (RGB) supaya warna
%   asli citra TAK mengganggu color-coding skalar.
%     - useCLAHE  : CLAHE (adapthisteq) -> kontras LOKAL adaptif.
%     - useAdjust : auto kontras+brightness (imadjust stretchlim) -> rentang
%                   intensitas optimum (regang p1..p99 ke [0 1]).
%   Murni (tanpa handle GUI) -> aman headless. Fallback aman bila toolbox absen.

    rgb = [];
    if nargin < 2 || isempty(useCLAHE),  useCLAHE  = true; end
    if nargin < 3 || isempty(useAdjust), useAdjust = true; end
    if isempty(bg) || (~isnumeric(bg) && ~islogical(bg)), return; end

    % 1) Normalisasi ke double [0,1].
    d = double(bg);
    if isa(bg,'uint8'),       d = d / 255;
    elseif isa(bg,'uint16'),  d = d / 65535;
    elseif islogical(bg),     d = double(bg);
    else
        mx = max(d(:));
        if mx > 1.5
            if mx <= 255, d = d/255; elseif mx <= 65535, d = d/65535; else, d = d/mx; end
        end
    end
    d = max(0, min(1, d));

    % 2) Paksa GRAYSCALE (1 kanal).
    if size(d,3) == 3
        try, g = rgb2gray(d); catch, g = mean(d,3); end
    elseif size(d,3) == 1
        g = d;
    else
        g = mean(d,3);
    end
    g = max(0, min(1, g));

    % 3) Auto kontras + brightness (regang rentang intensitas optimum).
    if useAdjust && exist('imadjust','file') ~= 0
        try
            if exist('stretchlim','file') ~= 0
                lohi = stretchlim(g, [0.01 0.99]);   % buang 1% ekor -> robust
            else
                lohi = [min(g(:)); max(g(:))];
            end
            if lohi(2) > lohi(1), g = imadjust(g, lohi, [0 1]); end
        catch
        end
    end

    % 4) CLAHE (kontras lokal adaptif) bila diminta & tersedia.
    if useCLAHE && exist('adapthisteq','file') ~= 0
        try, g = adapthisteq(g); catch, end
    end

    % 5) Replikasi ke RGB (tetap abu-abu).
    rgb = repmat(max(0,min(1,g)), [1 1 3]);
end
