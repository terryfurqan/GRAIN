classdef maskPoly
%MASKPOLY  Engine murni masking POLYGON NON-DESTRUKTIF, berkeyframe (ala After
%   Effects). Layer-2 (pelengkap maskRect = layer-1 kotak). Resep di sidecar
%   field `v2_poly`. Polygon TIDAK dibakar ke blob; ditempel saat decode.
%
%   Alur kerja user (restorasi mundur): gambar polygon di FRAME AKHIR, lalu
%   mundur bertahap set keyframe -> sampai frame pertama. Antar-keyframe =
%   interpolasi LINEAR tiap vertex.
%
%   Skema `poly`:
%     poly.enabled  : logical
%     poly.fill     : 0..255 (default 255)
%     poly.polygons : array struct, tiap polygon:
%         .enabled   : logical (default true)
%         .fill      : opsional override (default = poly.fill)
%         .keyframes : array struct (>=1), tiap:
%             .frame_index : rank frame 1-based
%             .vertices    : [K x 2] (x,y piksel ruang frame)
%
%   SYARAT: semua keyframe dalam SATU polygon punya K vertex SAMA (interp
%   vertex-per-vertex). Polygon yg melanggar -> dibuang saat normalize.
%
%   API (semua static, murni/headless):
%     p    = maskPoly.normalize(poly)
%     V    = maskPoly.interpVerts(polygon, k, N)   % [K x 2] atau []
%     img2 = maskPoly.applyMask(img, poly, k, N)
%     tf   = maskPoly.isActive(poly)
%
%   Konvensi k = rank leksikografis (SAMA maskRect/unpackMat/readMatFrame).
%   Lihat juga: pivanalyzemat.core.maskRect, maskSidecar (v2_poly).

    methods (Static)

        function tf = isActive(poly)
        %ISACTIVE  true bila poly ada, enabled, dan punya >=1 polygon valid.
            tf = false;
            if ~isstruct(poly) || isempty(poly); return; end
            if ~isfield(poly,'enabled') || ~poly.enabled; return; end
            if ~isfield(poly,'polygons') || isempty(poly.polygons); return; end
            tf = true;
        end

        function p = normalize(poly)
        %NORMALIZE  Struct poly baku & tervalidasi. Kosong/invalid -> nonaktif.
        %   p.n_ref = jumlah frame acuan saat resep dibuat (0=tak diketahui).
        %   Bila >=2 & berbeda dari N aktual saat decode, frame_index keyframe
        %   DISKALA ke ruang N -> kebal perubahan jumlah frame antar-modul.
            p = struct('enabled', false, 'fill', 255, 'n_ref', 0, 'polygons', i_emptyPolys());
            if ~isstruct(poly) || isempty(poly); return; end
            if isfield(poly,'enabled') && ~isempty(poly.enabled)
                p.enabled = logical(poly.enabled(1));
            end
            if isfield(poly,'fill') && ~isempty(poly.fill) && isnumeric(poly.fill)
                f = double(poly.fill(1));
                if isfinite(f); p.fill = max(0,min(255,f)); end
            end
            if isfield(poly,'n_ref') && ~isempty(poly.n_ref) && isnumeric(poly.n_ref)
                nr = round(double(poly.n_ref(1)));
                if isfinite(nr) && nr >= 2; p.n_ref = nr; end
            end
            if isfield(poly,'polygons') && ~isempty(poly.polygons)
                src = poly.polygons;
                out = i_emptyPolys();
                for i = 1:numel(src)
                    g = pivanalyzemat.core.maskPoly.normalizePolygon(i_pick(src,i));
                    if ~isempty(g); out(end+1) = g; end %#ok<AGROW>
                end
                p.polygons = out;
            end
            if isempty(p.polygons); p.enabled = false; end
        end

        function g = normalizePolygon(pg)
        %NORMALIZEPOLYGON  Validasi satu polygon; [] bila tak sah (keyframe<1,
        %   vertex<3, atau K berbeda antar-keyframe).
            g = [];
            if ~isstruct(pg) || isempty(pg); return; end
            kf = i_getf(pg,'keyframes');
            if isempty(kf); return; end
            KF = i_emptyKf(); Kref = -1;
            for i = 1:numel(kf)
                one = i_pick(kf,i);
                fi = i_posInt(i_getf(one,'frame_index'), NaN);
                V  = i_verts(i_getf(one,'vertices'));
                if isnan(fi) || isempty(V); continue; end
                K = size(V,1);
                if K < 3; continue; end
                if Kref < 0; Kref = K; elseif K ~= Kref; continue; end   % K harus sama
                KF(end+1) = struct('frame_index',fi,'vertices',V); %#ok<AGROW>
            end
            if numel(KF) < 1; return; end
            % urutkan keyframe by frame_index
            [~,ord] = sort([KF.frame_index]); KF = KF(ord);
            en = true;
            if isfield(pg,'enabled') && ~isempty(pg.enabled); en = logical(pg.enabled(1)); end
            fl = [];
            if isfield(pg,'fill') && ~isempty(pg.fill) && isnumeric(pg.fill)
                fv = double(pg.fill(1));
                if isfinite(fv); fl = max(0,min(255,fv)); end
            end
            g = struct('enabled',en, 'fill',fl, 'keyframes',KF);
        end

        function V = interpVerts(polygon, k, N, nRef)
        %INTERPVERTS  Vertices [K x 2] polygon pada frame k (interp linear antar
        %   keyframe; clamp ke keyframe terdekat di luar rentang). [] bila invalid.
        %
        %   nRef (opsional): jumlah frame acuan saat resep dibuat. Bila >=2 &
        %   berbeda dari N, frame_index tiap keyframe DISKALA ke ruang N:
        %   fN = 1 + (f-1)*(N-1)/(nRef-1) sebelum interpolasi. Tanpa nRef ->
        %   keyframe dipakai absolut (perilaku lama).
            V = [];
            g = pivanalyzemat.core.maskPoly.normalizePolygon(polygon);
            if isempty(g); return; end
            if nargin < 4; nRef = []; end
            KF = g.keyframes; f = [KF.frame_index];
            f = i_scaleKf(f, N, nRef);   % skala ke ruang N bila n_ref berbeda
            k = round(double(k));
            if isscalar(KF); V = KF(1).vertices; return; end
            if k <= f(1); V = KF(1).vertices; return; end
            if k >= f(end); V = KF(end).vertices; return; end
            hi = find(f >= k, 1, 'first');
            lo = hi - 1;
            f0 = f(lo); f1 = f(hi);
            if f1 <= f0; V = KF(lo).vertices; return; end
            t = (k - f0)/(f1 - f0); t = max(0,min(1,t));
            V = KF(lo).vertices + t*(KF(hi).vertices - KF(lo).vertices);
        end

        function [pg, msg] = reconcileVertexCount(pg, curFrame, Vold, Vnew)
        %RECONCILEVERTEXCOUNT  Selaraskan jumlah vertex (K) SEMUA keyframe lain
        %   dgn bentuk baru Vnew di curFrame. Vold = bentuk polygon di curFrame
        %   SEBELUM edit (acuan). Titik yg DITAMBAH disisipkan (nilai = titik
        %   tengah segmen) di indeks setara pd tiap keyframe lain; titik yg
        %   DIHAPUS dibuang di indeks setara. Menjaga invarian K-seragam yg
        %   dituntut interpVerts. Keyframe di curFrame TIDAK ditulis di sini
        %   (pemanggil yg upsert Vnew). msg = catatan aksi (utk status bar).
        %
        %   Murni/headless: tak menyentuh GUI. Aman dipanggil dari editor & test.
            msg = '';
            if isempty(pg) || ~isstruct(pg) || ~isfield(pg,'keyframes') || isempty(pg.keyframes)
                return;
            end
            Kold = size(Vold,1); Knew = size(Vnew,1);
            if Knew == Kold; return; end
            mp = pivanalyzemat.core.maskPoly;
            if Knew > Kold
                nAdd = Knew - Kold;
                ins = mp.matchInsertIndices(Vold, Vnew);
                if numel(ins) ~= nAdd; ins = repmat(Kold+1, 1, nAdd); end
                ins = sort(ins,'descend');
                for a = 1:numel(ins)
                    pg = mp.insertVertexAll(pg, ins(a), curFrame);
                end
                msg = sprintf('+%d titik disisipkan ke semua keyframe.', nAdd);
            else
                nDel = Kold - Knew;
                del = mp.matchDeleteIndices(Vold, Vnew);
                if numel(del) ~= nDel; del = (Kold-nDel+1):Kold; end
                del = sort(del,'descend');
                for a = 1:numel(del)
                    pg = mp.removeVertexAll(pg, del(a));
                end
                msg = sprintf('-%d titik dihapus dari semua keyframe.', nDel);
            end
        end

        function pg = insertVertexAll(pg, p, skipFrame)
        %INSERTVERTEXALL  Sisipkan 1 vertex di indeks p pada semua keyframe KECUALI
        %   skipFrame. Nilai = titik tengah segmen (rata-rata vertex p-1 & p, melingkar).
            if nargin < 3; skipFrame = NaN; end
            kf = pg.keyframes;
            for j = 1:numel(kf)
                if isfinite(skipFrame) && kf(j).frame_index == round(skipFrame); continue; end
                V = kf(j).vertices; K = size(V,1);
                pp = max(1, min(K+1, round(p)));
                a = pp-1; if a < 1; a = K; end
                b = pp;   if b > K; b = 1; end
                mid = (V(a,:) + V(b,:)) / 2;
                kf(j).vertices = [V(1:pp-1,:); mid; V(pp:end,:)];
            end
            pg.keyframes = kf;
        end

        function pg = removeVertexAll(pg, idx)
        %REMOVEVERTEXALL  Buang vertex indeks idx pada SEMUA keyframe (jaga K>=3).
            kf = pg.keyframes;
            for j = 1:numel(kf)
                V = kf(j).vertices; K = size(V,1);
                if K <= 3; continue; end
                i0 = max(1, min(K, round(idx)));
                V(i0,:) = []; kf(j).vertices = V;
            end
            pg.keyframes = kf;
        end

        function ins = matchInsertIndices(Vold, Vnew)
        %MATCHINSERTINDICES  Tebak indeks sisip titik baru: cocokkan tiap titik Vold
        %   ke titik Vnew terdekat (greedy, jaga urutan). Titik Vnew tak terpakai =
        %   baru; indeks sisip (ruang Vold) = jumlah titik Vold cocok sebelumnya + 1.
            Kold = size(Vold,1); Knew = size(Vnew,1);
            ins = [];
            if Knew <= Kold || Kold < 1; return; end
            usedNew = false(Knew,1); matchNewForOld = zeros(Kold,1); startN = 1;
            for i = 1:Kold
                bestN = 0; bestD = inf;
                for n = startN:Knew
                    if usedNew(n); continue; end
                    d = sum((Vnew(n,:) - Vold(i,:)).^2);
                    if d < bestD; bestD = d; bestN = n; end
                end
                if bestN == 0; bestN = startN; end
                matchNewForOld(i) = bestN; usedNew(bestN) = true; startN = bestN + 1;
            end
            for n = 1:Knew
                if usedNew(n); continue; end
                nBeforeOld = sum(matchNewForOld < n & matchNewForOld > 0);
                ins(end+1) = nBeforeOld + 1; %#ok<AGROW>
            end
        end

        function del = matchDeleteIndices(Vold, Vnew)
        %MATCHDELETEINDICES  Tebak indeks vertex Vold yg dihapus: titik Vold tanpa
        %   pasangan dekat di Vnew (greedy jaga urutan).
            Kold = size(Vold,1); Knew = size(Vnew,1);
            del = [];
            if Knew >= Kold || Knew < 1; return; end
            usedNew = false(Knew,1); startN = 1;
            for i = 1:Kold
                bestN = 0; bestD = inf;
                for n = startN:Knew
                    if usedNew(n); continue; end
                    d = sum((Vnew(n,:) - Vold(i,:)).^2);
                    if d < bestD; bestD = d; bestN = n; end
                end
                if bestN == 0
                    del(end+1) = i; %#ok<AGROW>
                else
                    usedNew(bestN) = true; startN = bestN + 1;
                end
            end
        end

        function img = applyMask(img, poly, k, N)
        %APPLYMASK  Tempel SEMUA polygon ke `img` pada frame k. No-op bila nonaktif.
        %   Aman grayscale/RGB (semua kanal region diisi fill).
            if isempty(img); return; end
            p = pivanalyzemat.core.maskPoly.normalize(poly);
            if ~p.enabled || isempty(p.polygons); return; end
            H = size(img,1); W = size(img,2);
            nRef = []; if isfield(p,'n_ref') && ~isempty(p.n_ref) && p.n_ref >= 2; nRef = p.n_ref; end
            for i = 1:numel(p.polygons)
                g = p.polygons(i);
                if ~g.enabled; continue; end
                V = pivanalyzemat.core.maskPoly.interpVerts(g, k, N, nRef);
                if isempty(V); continue; end
                BW = poly2mask(V(:,1), V(:,2), H, W);
                if ~any(BW(:)); continue; end
                fl = g.fill; if isempty(fl); fl = p.fill; end
                fill = i_castFill(fl, class(img));
                nc = size(img,3);
                for c = 1:nc
                    ch = img(:,:,c); ch(BW) = fill; img(:,:,c) = ch;
                end
            end
        end

    end
end

%% ===================================================================
function s = i_emptyPolys()
s = struct('enabled', {}, 'fill', {}, 'keyframes', {});
end
function f = i_scaleKf(f, N, nRef)
%I_SCALEKF  Skala vektor frame_index dari ruang nRef ke ruang N (linear).
%   fN = 1 + (f-1)*(N-1)/(nRef-1). Tanpa nRef (>=2) berbeda dari N -> apa adanya.
if isempty(nRef) || ~isfinite(nRef) || nRef < 2; return; end
N = round(double(N));
if N < 2 || nRef == N; return; end
f = 1 + (double(f) - 1) * ((N - 1) / (nRef - 1));
end
function s = i_emptyKf()
s = struct('frame_index', {}, 'vertices', {});
end
function v = i_getf(s, name)
v = []; if isstruct(s) && isfield(s, name); v = s.(name); end
end
function one = i_pick(arr, i)
%I_PICK  Ambil elemen ke-i dari struct-array ATAU cell (jsondecode quirk).
if iscell(arr); one = arr{i}; else; one = arr(i); end
end
function V = i_verts(v)
%I_VERTS  Validasi vertices -> [K x 2] double hingga; [] bila tak sah.
V = [];
if isempty(v) || ~isnumeric(v); return; end
v = double(v);
if size(v,2) ~= 2
    if size(v,1) == 2; v = v.'; else; return; end
end
if size(v,1) < 3 || ~all(isfinite(v(:))); return; end
V = v;
end
function n = i_posInt(v, dflt)
n = dflt;
if isempty(v) || ~isnumeric(v); return; end
x = double(v(1));
if isfinite(x) && x >= 1; n = round(x); end
end
function f = i_castFill(fill, cls)
switch cls
    case 'double'; f = double(fill)/255;
    case 'single'; f = single(double(fill)/255);
    case 'logical'; f = fill >= 128;
    otherwise; f = cast(round(fill), cls);
end
end
