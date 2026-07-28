classdef maskRect
%MASKRECT  Engine murni masking persegi NON-DESTRUKTIF, interpolasi per-frame.
%
%   Resep masking disimpan di MAT PREP sebagai field opsional `prep.masking`
%   (lihat skema di `normalize`). Kotak putih TIDAK dibakar ke blob JPEG asli;
%   ia ditempel saat decode (unpackMat / readMatFrame) ke citra yang akan
%   dimakan analisis PIV — sehingga frame asli tetap utuh & kotak bisa diedit
%   ulang kapan saja, sambil PIV tetap menerima JPEG yang sudah ter-masking.
%
%   Koordinat dalam PIKSEL ruang frame MAT PREP (pasca-crop/stabilisasi).
%   Tiap kotak punya `rect_first` [x y w h] di frame acuan awal & `rect_last`
%   di frame acuan akhir; ukuran/posisi kotak di frame-k = interpolasi linear
%   (air/pasir masuk → area berubah mulus).
%
%   API (semua static, murni/headless):
%     m    = pivanalyzemat.core.maskRect.normalize(masking)      % isi default+validasi
%     bb   = pivanalyzemat.core.maskRect.interpRect(box, k, N, W, H)  % [x1 y1 x2 y2] int clamp
%     img2 = pivanalyzemat.core.maskRect.applyMask(img, masking, k, N) % tempel SEMUA kotak
%     tf   = pivanalyzemat.core.maskRect.isActive(masking)       % enabled & ada kotak
%
%   Interpolasi (pola identik strain buildMontagePOT):
%     rect_k = rect_first + (k-1)/(N-1) * (rect_last - rect_first)
%   dengan k = posisi frame (1-based, urut SAMA dgn unpackMat/readMatFrame).
%
%   Penempatan berkas: PAB/+pivanalyzemat/+core/maskRect.m
%   Lihat juga: pivanalyzemat.core.unpackMat, pivanalyzemat.core.readMatFrame

    methods (Static)

        % ================================================================
        function tf = isActive(masking)
        %ISACTIVE  true bila masking ada, enabled, dan punya >=1 kotak valid.
            tf = false;
            if ~isstruct(masking) || isempty(masking); return; end
            if ~isfield(masking, 'enabled') || ~masking.enabled; return; end
            if ~isfield(masking, 'boxes') || isempty(masking.boxes); return; end
            tf = true;
        end

        % ================================================================
        function m = normalize(masking)
        %NORMALIZE  Kembalikan struct masking baku & tervalidasi.
        %
        %   Skema:
        %     m.enabled : logical
        %     m.fill    : skalar 0..255 (nilai putih; default 255)
        %     m.n_ref   : jumlah frame ACUAN saat resep dibuat (0=tak diketahui).
        %                 Bila >0 dan berbeda dari N aktual saat decode, indeks
        %                 acuan kotak (frame_first/last) DISKALA ke N -> resep
        %                 kebal terhadap perubahan jumlah frame antar-modul
        %                 (mis. PABMASK menghitung nFrames sedikit beda dgn
        %                 prep.nFrames MAT PREP). 0 -> perilaku lama (tak skala).
        %     m.boxes   : array struct, tiap elemen:
        %                   .rect_first  [x y w h]  (frame awal)
        %                   .rect_last   [x y w h]  (frame akhir)
        %                   .frame_first indeks acuan awal (default 1)
        %                   .frame_last  indeks acuan akhir (default N; NaN=auto)
        %                   .keyframes   array {frame_index, rect [x y w h]}
        %                                keyframe TENGAH opsional; kosong = interp
        %                                dua-ujung (perilaku lama). Ada -> ukuran
        %                                kotak jadi piecewise-linear antar node
        %                                (ujung + keyframe) mengikuti distorsi.
        %
        %   Masukan kosong/invalid -> masking dinonaktifkan (enabled=false,
        %   boxes kosong) supaya konsumer mundur anggun.
            m = struct('enabled', false, 'fill', 255, 'n_ref', 0, 'boxes', i_emptyBoxes());
            if ~isstruct(masking) || isempty(masking); return; end

            if isfield(masking, 'enabled') && ~isempty(masking.enabled)
                m.enabled = logical(masking.enabled(1));
            end
            if isfield(masking, 'fill') && ~isempty(masking.fill) && isnumeric(masking.fill)
                f = double(masking.fill(1));
                if isfinite(f); m.fill = max(0, min(255, f)); end
            end
            if isfield(masking, 'n_ref') && ~isempty(masking.n_ref) && isnumeric(masking.n_ref)
                nr = round(double(masking.n_ref(1)));
                if isfinite(nr) && nr >= 2; m.n_ref = nr; end
            end

            if isfield(masking, 'boxes') && ~isempty(masking.boxes)
                src = masking.boxes;
                out = i_emptyBoxes();
                for i = 1:numel(src)
                    b = pivanalyzemat.core.maskRect.normalizeBox(src(i));
                    if ~isempty(b); out(end+1) = b; end %#ok<AGROW>
                end
                m.boxes = out;
            end

            % Tak ada kotak valid -> nonaktifkan (hindari "enabled tapi kosong").
            if isempty(m.boxes); m.enabled = false; end
        end

        % ================================================================
        function b = normalizeBox(box)
        %NORMALIZEBOX  Validasi satu kotak; [] bila tak punya rect valid.
            b = [];
            if ~isstruct(box) || isempty(box); return; end
            rf = i_rect4(i_getf(box, 'rect_first'));
            rl = i_rect4(i_getf(box, 'rect_last'));
            % rect_last absen -> samakan dgn rect_first (kotak statis).
            if isempty(rf) && isempty(rl); return; end
            if isempty(rf); rf = rl; end
            if isempty(rl); rl = rf; end
            ff = i_posIntOr(i_getf(box, 'frame_first'), 1);
            fl = i_posIntOr(i_getf(box, 'frame_last'),  NaN);  % NaN -> auto = N
            kf = i_normKeyframes(i_getf(box, 'keyframes'));     % keyframe TENGAH opsional
            b = struct('rect_first', rf, 'rect_last', rl, ...
                'frame_first', ff, 'frame_last', fl, 'keyframes', kf);
        end

        % ================================================================
        function bb = interpRect(box, k, N, W, H, nRef)
        %INTERPRECT  Bbox integer [x1 y1 x2 y2] kotak `box` pada frame k.
        %
        %   k,N 1-based. Interpolasi linear rect_first->rect_last terhadap
        %   frame acuan (frame_first/frame_last; default 1..N), DI-CLAMP ke
        %   rentang [0,1] sehingga di luar acuan kotak menempel pada ujung.
        %   Hasil dibulatkan & dijepit ke [1..W]x[1..H]. [] bila kotak invalid
        %   atau hasil bbox kosong (lebar/tinggi < 1 px).
        %
        %   nRef (opsional): jumlah frame acuan saat resep dibuat. Bila diberi
        %   (>=2) & berbeda dari N, indeks acuan (frame_first/last) DISKALA
        %   linear ke ruang N: fN = 1 + (f-1)*(N-1)/(nRef-1). Ini menjaga posisi
        %   RELATIF kotak saat jumlah frame berbeda (PABMASK vs MAT PREP).
            bb = [];
            b = pivanalyzemat.core.maskRect.normalizeBox(box);
            if isempty(b); return; end

            N = max(1, round(double(N)));
            k = round(double(k));
            if nargin < 6; nRef = []; end
            % Interpolasi [x y w h] pada frame k: dua-ujung lama bila tanpa
            % keyframe, ATAU piecewise-linear antar node bila ada keyframe tengah.
            r = i_interpRectR(b, k, N, nRef);
            x1 = r(1); y1 = r(2); x2 = r(1) + r(3); y2 = r(2) + r(4);

            % Bbox ter-urut (pelindung bila w/h negatif) + dibulatkan.
            xa = round(min(x1, x2)); xb = round(max(x1, x2));
            ya = round(min(y1, y2)); yb = round(max(y1, y2));

            % Clamp ke gambar (W/H opsional; bila diberi).
            if nargin >= 4 && ~isempty(W) && isfinite(W)
                xa = max(1, min(W, xa)); xb = max(1, min(W, xb));
            else
                xa = max(1, xa); xb = max(1, xb);
            end
            if nargin >= 5 && ~isempty(H) && isfinite(H)
                ya = max(1, min(H, ya)); yb = max(1, min(H, yb));
            else
                ya = max(1, ya); yb = max(1, yb);
            end

            if xb < xa || yb < ya; return; end       % kosong
            bb = [xa ya xb yb];
        end

        % ================================================================
        function img = applyMask(img, masking, k, N)
        %APPLYMASK  Tempel SEMUA kotak masking ke `img` pada frame k (1-based).
        %
        %   No-op (img dikembalikan apa adanya) bila masking tak aktif. Aman
        %   untuk grayscale (HxW), grayscale+alpha, & RGB (HxWxC): seluruh
        %   kanal di region kotak diisi nilai `fill` (default 255 = putih).
            if isempty(img); return; end
            m = pivanalyzemat.core.maskRect.normalize(masking);
            if ~m.enabled || isempty(m.boxes); return; end

            H = size(img, 1); W = size(img, 2);
            fill = i_castFill(m.fill, class(img));
            nRef = []; if isfield(m,'n_ref') && ~isempty(m.n_ref) && m.n_ref >= 2; nRef = m.n_ref; end
            for i = 1:numel(m.boxes)
                bb = pivanalyzemat.core.maskRect.interpRect(m.boxes(i), k, N, W, H, nRef);
                if isempty(bb); continue; end
                img(bb(2):bb(4), bb(1):bb(3), :) = fill;
            end
        end

    end
end

%% ===================================================================
function s = i_emptyBoxes()
%I_EMPTYBOXES  Array struct 0x0 dgn field kotak (untuk pertumbuhan via end+1).
%   `keyframes` = array keyframe TENGAH opsional (kosong = interpolasi dua-ujung).
s = struct('rect_first', {}, 'rect_last', {}, 'frame_first', {}, ...
           'frame_last', {}, 'keyframes', {});
end

function kf = i_emptyKf()
%I_EMPTYKF  Array struct 0x0 keyframe {frame_index, rect [x y w h]}.
kf = struct('frame_index', {}, 'rect', {});
end

function kf = i_normKeyframes(src)
%I_NORMKEYFRAMES  Validasi array keyframe {frame_index, rect [x y w h]}.
%   Buang keyframe invalid (frame_index non-posint / rect bukan 4 angka w,h>0);
%   urutkan by frame_index. Terima cell ATAU struct-array (quirk jsondecode).
kf = i_emptyKf();
if isempty(src); return; end
for i = 1:numel(src)
    if iscell(src); one = src{i}; else; one = src(i); end
    if ~isstruct(one); continue; end
    fi = i_posIntOr(i_getf(one, 'frame_index'), NaN);
    rc = i_rect4(i_getf(one, 'rect'));
    if isnan(fi) || isempty(rc); continue; end
    kf(end+1) = struct('frame_index', fi, 'rect', rc); %#ok<AGROW>
end
if isempty(kf); return; end
[~, ord] = sort([kf.frame_index]);
kf = kf(ord);
end

function [g0, g1] = i_scaleRefFrames(f0, f1, N, nRef)
%I_SCALEREFFRAMES  Skala indeks acuan (f0,f1) dari ruang nRef ke ruang N.
%   fN = 1 + (f-1)*(N-1)/(nRef-1). Tanpa nRef (>=2) yg berbeda dari N -> apa
%   adanya (perilaku lama, backward-compat resep tanpa n_ref).
g0 = f0; g1 = f1;
if isempty(nRef) || ~isfinite(nRef) || nRef < 2; return; end
N = round(double(N));
if N < 2 || nRef == N; return; end
sc = (N - 1) / (nRef - 1);
g0 = 1 + (f0 - 1) * sc;
g1 = 1 + (f1 - 1) * sc;
end

function f = i_scaleKfFrames(f, N, nRef)
%I_SCALEKFFRAMES  Skala vektor frame_index keyframe dari ruang nRef ke ruang N.
%   Rumus sama i_scaleRefFrames; tanpa nRef berbeda -> apa adanya.
if isempty(nRef) || ~isfinite(nRef) || nRef < 2; return; end
N = round(double(N));
if N < 2 || nRef == N; return; end
f = 1 + (double(f) - 1) * ((N - 1) / (nRef - 1));
end

function r = i_interpRectR(b, k, N, nRef)
%I_INTERPRECTR  Interpolasi rect [x y w h] kotak `b` pada frame k (1-based).
%   Tanpa keyframe: linear rect_first->rect_last (frame_first..frame_last,
%   clamp di luar). Dengan keyframe TENGAH: piecewise-linear pada node terurut
%   [f0:rect_first, kf:rect ..., f1:rect_last] — clamp ke node ujung. Indeks
%   acuan & keyframe diskala oleh nRef yang sama (kebal beda jumlah frame).
    f0 = b.frame_first;
    f1 = b.frame_last; if ~isfinite(f1); f1 = N; end
    [f0, f1] = i_scaleRefFrames(f0, f1, N, nRef);

    hasKf = isfield(b, 'keyframes') && ~isempty(b.keyframes);
    if ~hasKf
        if f1 <= f0
            t = 0;                       % acuan degenerate -> pakai awal
        else
            t = (k - f0) / (f1 - f0);
            t = max(0, min(1, t));       % clamp di luar [f0,f1]
        end
        r = b.rect_first + t * (b.rect_last - b.rect_first);
        return;
    end

    % Rakit node terurut: endpoint + keyframe tengah (skala nRef).
    fn = i_scaleKfFrames([b.keyframes.frame_index], N, nRef);
    F  = [f0, fn, f1];
    R  = [b.rect_first(:).'; ...
          reshape([b.keyframes.rect], 4, []).'; ...
          b.rect_last(:).'];
    [F, ord] = sort(F);
    R = R(ord, :);

    if k <= F(1);   r = R(1, :);   return; end
    if k >= F(end); r = R(end, :); return; end
    hi = find(F >= k, 1, 'first');
    lo = hi - 1;
    if F(hi) <= F(lo); r = R(lo, :); return; end
    t = (k - F(lo)) / (F(hi) - F(lo)); t = max(0, min(1, t));
    r = R(lo, :) + t * (R(hi, :) - R(lo, :));
end

function v = i_getf(s, name)
v = [];
if isstruct(s) && isfield(s, name); v = s.(name); end
end

function r = i_rect4(v)
%I_RECT4  Validasi rect [x y w h]; [] bila bukan 4 angka hingga & w,h>0.
r = [];
if isempty(v) || ~isnumeric(v) || numel(v) ~= 4; return; end
v = double(v(:)).';
if ~all(isfinite(v)); return; end
if v(3) <= 0 || v(4) <= 0; return; end       % lebar/tinggi harus positif
r = v;
end

function n = i_posIntOr(v, dflt)
%I_POSINTOR  Bilangan bulat >=1; dflt bila kosong/invalid (NaN dipertahankan).
n = dflt;
if isempty(v) || ~isnumeric(v); return; end
x = double(v(1));
if isnan(dflt) && (isempty(v) || isnan(x)); n = NaN; return; end
if isfinite(x) && x >= 1; n = round(x); end
end

function f = i_castFill(fill, cls)
%I_CASTFILL  Cast nilai isi ke kelas citra (uint8 default; double 0..1 utk float).
switch cls
    case 'double'
        f = double(fill) / 255;       % citra double biasanya skala 0..1
    case 'single'
        f = single(double(fill) / 255);
    case 'logical'
        f = fill >= 128;
    otherwise
        f = cast(round(fill), cls);   % uint8/uint16/dll
end
end
