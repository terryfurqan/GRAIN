classdef pab4FaultGeom
%PAB4FAULTGEOM  Model GEOMETRI SESAR PAB4 — sidecar `<base>_faultgeom.json` di
%   folder yang sama dgn MAT PIV. Menyimpan POLYLINE (multi-vertex) yang
%   digambar di AX-MAIN untuk tiap sesar (fault), terikat ke (psgId, F#), pada
%   frame acuan POI FS-max pertama. Dari polyline dihitung:
%     - PANJANG SESAR (cm)  = Σ hypot(Δx_px,Δy_px) × cmPerPx
%     - SUDUT / dip (°)     = regresi linear least-squares vertex vs horizontal
%     - GROWTH RATE (cm/s)  = length / (Δframe[NUC-FSR..FS-max terdekat] × dt)
%     - DIE-OUT RATE (cm/s) = length / (Δframe[FS-max terakhir..END] × dt)
%
%   Vertex disimpan dalam KOORDINAT PIXEL GAMBAR AX-MAIN (bukan data-coords),
%   supaya independen zoom/pan. Konversi px->cm ISOTROPIK (skala X=Y):
%     cmPerPx = dxCm / lebarFramePx  (dxCm = |X0_cm-X1_cm| experiment_geometry).
%   PABAXCAL (_axcal.json) TIDAK dipakai di sini (keputusan user).
%
%   INI kebenaran milik PAB4 (bersih, terpisah). MAT PIV biner,
%   `<base>_faults.json` (PAB5) & `<base>_desc.json`/`_potdata.json` TIDAK
%   disentuh — PAB4 hanya MEMBACA konteks sesar & baris DESC (FS-max/NUC-FSR).
%
%   Satu `_faultgeom.json` per-eksperimen menampung entri untuk SEMUA garis PSG
%   (dibedakan `psgId`) & SEMUA F# (dibedakan `fNum`). Satu entri per (psgId,F#).
%
%   Penulisan WAJIB ATOMIC (tmp -> movefile). NaN <-> JSON null.
%
%   API:
%     p    = pivcore.io.pab4FaultGeom.dataPath(dataFile)
%     doc  = pivcore.io.pab4FaultGeom.emptyDoc(dataFile)
%     doc  = pivcore.io.pab4FaultGeom.read(dataFile)             % [] -> emptyDoc
%     pivcore.io.pab4FaultGeom.write(dataFile, doc)              % ATOMIC
%     e    = pivcore.io.pab4FaultGeom.geomFor(doc, psgId, fNum)  % [] bila absen
%     doc  = pivcore.io.pab4FaultGeom.setGeomFor(doc, psgId, fNum, vertsPx, frameRef)
%     doc  = pivcore.io.pab4FaultGeom.clearGeomFor(doc, psgId, fNum)
%     -- fungsi MURNI (di-test golden) --
%     L    = pivcore.io.pab4FaultGeom.polylineLenPx(vertsPx)
%     Lcm  = pivcore.io.pab4FaultGeom.lenCm(vertsPx, cmPerPx)
%     deg  = pivcore.io.pab4FaultGeom.angleDeg(vertsPx)
%     cpp  = pivcore.io.pab4FaultGeom.cmPerPxFromGeom(dxCm, widthPx)
%     g    = pivcore.io.pab4FaultGeom.growthRate(lenCm, dFrame, dtSec)
%     d    = pivcore.io.pab4FaultGeom.dieOutRate(lenCm, dFrame, dtSec)
%     [fr,dd] = pivcore.io.pab4FaultGeom.nearestFsMaxToNuc(fsFrames, nucFrame)
%
%   Penempatan berkas: PAB/pivcore_lib/+pivcore/+io/pab4FaultGeom.m

    methods (Static)

        % ================================================================
        function p = dataPath(dataFile)
        %DATAPATH  <dir>/<base>_faultgeom.json untuk MAT PIV dataFile.
            p = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_faultgeom.json', base));
        end


        % ================================================================
        function doc = emptyDoc(dataFile)
        %EMPTYDOC  Kerangka dokumen kosong.
            if nargin < 1, dataFile = ''; end
            [~, base, ext] = fileparts(char(dataFile));
            doc = struct();
            doc.formatName    = 'PAB4 Fault Geometry';
            doc.formatVersion = 1;
            doc.source        = [base ext];
            doc.meta          = struct('basename', base);
            doc.faults        = {};    % cell of geom-entry struct (JSON array)
            % REFERENSI HORIZONTAL (koreksi kemiringan kamera != 0°). Sudut garis
            % referensi (derajat vs horizontal citra) yang user set via ROI di
            % axMain; sudut sesar DIKURANGI nilai ini. NaN = tak diset (pakai
            % horizontal citra 0°). Satu ref per-eksperimen (semua sesar).
            doc.refHorizonDeg = NaN;
        end


        % ================================================================
        function doc = read(dataFile)
        %READ  Baca & NORMALISASI sidecar. Tak ada berkas -> emptyDoc. Rusak ->
        %   emptyDoc + warning (tak melempar agar GUI tetap jalan).
            p = pivcore.io.pab4FaultGeom.dataPath(dataFile);
            if isempty(p) || ~isfile(p)
                doc = pivcore.io.pab4FaultGeom.emptyDoc(dataFile); return;
            end
            try
                txt = fileread(p);
                raw = jsondecode(txt);
            catch ME
                warning('pivcore:pab4FaultGeom:read', ...
                    'Gagal membaca/parse %s (%s); pakai dokumen kosong.', p, ME.message);
                doc = pivcore.io.pab4FaultGeom.emptyDoc(dataFile); return;
            end
            doc = pivcore.io.pab4FaultGeom.normalizeDoc(raw, dataFile);
        end


        % ================================================================
        function write(dataFile, doc)
        %WRITE  Tulis dokumen ke `<base>_faultgeom.json` secara ATOMIC.
            p = pivcore.io.pab4FaultGeom.dataPath(dataFile);
            if isempty(p)
                error('pivcore:pab4FaultGeom:noPath', ...
                    'Tak bisa menentukan path _faultgeom untuk: %s', dataFile);
            end
            doc = pivcore.io.pab4FaultGeom.prepForEncode(doc);
            txt = jsonencode(doc, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0
                error('pivcore:pab4FaultGeom:open', 'Tak bisa membuka %s utk tulis.', tmp);
            end
            cleaner = onCleanup(@() pivcore.io.pab4FaultGeom.cleanupTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
            fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok
                error('pivcore:pab4FaultGeom:move', ...
                    'Gagal memindah tmp->final (%s): %s', p, msg);
            end
        end


        % ================================================================
        function e = entryStruct(psgId, fNum, vertsPx, frameRef)
        %ENTRYSTRUCT  Skeleton satu entri geometri sesar. Semua argumen opsional.
        %   vertsPx = Nx2 [x y] pixel gambar AX-MAIN. frameRef = frame acuan
        %   (FS-max pertama) saat polyline digambar.
            if nargin < 1, psgId    = ''; end
            if nargin < 2, fNum     = ''; end
            if nargin < 3, vertsPx  = zeros(0,2); end
            if nargin < 4, frameRef = NaN; end
            % DUA FASE polyline per sesar (bentuk bisa beda):
            %   NUC = nukleasi->FSR (Ctrl+Q; frame FS-max ke-1; Len+sudut+growth)
            %   DIE = FSR->die-out (Ctrl+W; frame FS-max ke-2; Len saja utk die-out)
            % Arg-3/4 (vertsPx/frameRef) mengisi fase NUC demi kompat pemanggil lama.
            e = struct();
            e.psgId        = pivcore.io.pab4FaultGeom.tostr(psgId);
            e.fNum         = pivcore.io.pab4FaultGeom.tostr(fNum);
            e.verticesNuc  = pivcore.io.pab4FaultGeom.normVerts(vertsPx);
            e.frameRefNuc  = pivcore.io.pab4FaultGeom.scal(frameRef);
            e.verticesDie  = zeros(0,2);
            e.frameRefDie  = NaN;
        end


        % ================================================================
        function e = geomFor(doc, psgId, fNum)
        %GEOMFOR  Entri geometri milik (psgId, F#) atau [] bila belum ada.
        %   Entri punya 2 fase: verticesNuc/frameRefNuc + verticesDie/frameRefDie.
            e = [];
            if ~isstruct(doc) || ~isfield(doc,'faults'), return; end
            all = pivcore.io.pab4FaultGeom.tocell(doc.faults);
            kP  = pivcore.io.pab4FaultGeom.tostr(psgId);
            kF  = pivcore.io.pab4FaultGeom.normFtag(fNum);
            for k = 1:numel(all)
                r = pivcore.io.pab4FaultGeom.normEntry(all{k});
                if strcmp(r.psgId, kP) && strcmp(pivcore.io.pab4FaultGeom.normFtag(r.fNum), kF)
                    e = r; return;
                end
            end
        end


        % ================================================================
        function v = phaseVerts(e, phase)
        %PHASEVERTS  Vertex fase 'nuc'/'die' dari entri (Nx2). [] bila absen.
            v = zeros(0,2);
            if isempty(e) || ~isstruct(e), return; end
            e = pivcore.io.pab4FaultGeom.normEntry(e);
            if strcmpi(phase,'die'), v = e.verticesDie; else, v = e.verticesNuc; end
        end


        % ================================================================
        function doc = setGeomFor(doc, psgId, fNum, vertsPx, frameRef, phase)
        %SETGEOMFOR  Sisip/ganti FASE (nuc|die) entri (psgId, F#) dgn vertex+
        %   frameRef. Fase LAIN entri itu + entri (psgId,F#) LAIN dipertahankan.
        %   phase default 'nuc' (kompat pemanggil lama). Vertex kosong -> fase itu
        %   dikosongkan (entri tetap ada); pakai clearGeomFor utk hapus seluruhnya.
            if ~isstruct(doc), doc = pivcore.io.pab4FaultGeom.emptyDoc(''); end
            if ~isfield(doc,'faults'), doc.faults = {}; end
            if nargin < 5, frameRef = NaN; end
            if nargin < 6 || isempty(phase), phase = 'nuc'; end
            isDie = strcmpi(phase,'die');
            kP  = pivcore.io.pab4FaultGeom.tostr(psgId);
            kF  = pivcore.io.pab4FaultGeom.normFtag(fNum);
            V   = pivcore.io.pab4FaultGeom.normVerts(vertsPx);
            fr  = pivcore.io.pab4FaultGeom.scal(frameRef);
            all = pivcore.io.pab4FaultGeom.tocell(doc.faults);
            keep = {}; replaced = false;
            for k = 1:numel(all)
                r = pivcore.io.pab4FaultGeom.normEntry(all{k});
                if strcmp(r.psgId, kP) && strcmp(pivcore.io.pab4FaultGeom.normFtag(r.fNum), kF)
                    if isDie, r.verticesDie = V; r.frameRefDie = fr;
                    else,     r.verticesNuc = V; r.frameRefNuc = fr; end
                    keep{end+1} = r; replaced = true; %#ok<AGROW>
                else
                    keep{end+1} = r; %#ok<AGROW>
                end
            end
            if ~replaced
                newE = pivcore.io.pab4FaultGeom.entryStruct(kP, fNum);
                if isDie, newE.verticesDie = V; newE.frameRefDie = fr;
                else,     newE.verticesNuc = V; newE.frameRefNuc = fr; end
                keep{end+1} = newE;
            end
            doc.faults = keep;
        end


        % ================================================================
        function doc = clearGeomFor(doc, psgId, fNum)
        %CLEARGEOMFOR  Hapus entri (psgId, F#) sepenuhnya dari doc.
            if ~isstruct(doc) || ~isfield(doc,'faults'), return; end
            kP  = pivcore.io.pab4FaultGeom.tostr(psgId);
            kF  = pivcore.io.pab4FaultGeom.normFtag(fNum);
            all = pivcore.io.pab4FaultGeom.tocell(doc.faults);
            keep = {};
            for k = 1:numel(all)
                r = pivcore.io.pab4FaultGeom.normEntry(all{k});
                if strcmp(r.psgId, kP) && strcmp(pivcore.io.pab4FaultGeom.normFtag(r.fNum), kF)
                    continue;
                end
                keep{end+1} = r; %#ok<AGROW>
            end
            doc.faults = keep;
        end


        % ================================================================
        function deg = refHorizonDeg(doc)
        %REFHORIZONDEG  Sudut referensi horizontal tersimpan (derajat vs horizontal
        %   citra). NaN bila tak diset.
            deg = NaN;
            if isstruct(doc) && isfield(doc,'refHorizonDeg')
                deg = pivcore.io.pab4FaultGeom.scal(doc.refHorizonDeg);
            end
        end


        % ================================================================
        function doc = setRefHorizonDeg(doc, deg)
        %SETREFHORIZONDEG  Set sudut referensi horizontal (koreksi kemiringan
        %   kamera). [] / NaN -> reset ke tak-diset.
            if ~isstruct(doc), doc = pivcore.io.pab4FaultGeom.emptyDoc(''); end
            doc.refHorizonDeg = pivcore.io.pab4FaultGeom.scal(deg);
        end


        % ================================================================
        function doc = setRefHorizonFromPts(doc, p1, p2)
        %SETREFHORIZONFROMPTS  Set referensi dari 2 titik garis (di axMain) ->
        %   sudut vs horizontal citra. Titik invalid -> tak diubah.
            deg = pivcore.pot.faultAngle.fromPoints(p1, p2);
            if isfinite(deg), doc = pivcore.io.pab4FaultGeom.setRefHorizonDeg(doc, deg); end
        end


        % ================================================================
        %                    ANGKA MURNI (di-test golden)
        % ================================================================
        function L = polylineLenPx(vertsPx)
        %POLYLINELENPX  Panjang polyline (pixel) = Σ hypot antar-vertex berurutan.
        %   < 2 vertex valid -> 0. Baris ber-NaN memutus segmen (dilewati).
            L = 0;
            V = pivcore.io.pab4FaultGeom.normVerts(vertsPx);
            if size(V,1) < 2, return; end
            for k = 2:size(V,1)
                a = V(k-1,:); b = V(k,:);
                if any(~isfinite([a b])), continue; end
                L = L + hypot(b(1)-a(1), b(2)-a(2));
            end
        end


        % ================================================================
        function Lcm = lenCm(vertsPx, cmPerPx)
        %LENCM  Panjang polyline dalam cm. NaN bila cmPerPx tak valid.
            Lcm = NaN;
            if nargin < 2 || ~isscalar(cmPerPx) || ~isfinite(cmPerPx) || cmPerPx <= 0, return; end
            Lcm = pivcore.io.pab4FaultGeom.polylineLenPx(vertsPx) * double(cmPerPx);
        end


        % ================================================================
        function deg = angleDeg(vertsPx)
        %ANGLEDEG  Sudut/dip polyline via REGRESI least-squares vertex vs
        %   horizontal, dinormalkan (-90,90] lewat pivcore.pot.faultAngle.
        %   fromPoints (konvensi garis tak-berarah). >=2 vertex. Kasus vertikal
        %   (dx≈0) -> ±90. NaN bila <2 vertex valid.
            deg = NaN;
            V = pivcore.io.pab4FaultGeom.normVerts(vertsPx);
            V = V(all(isfinite(V),2), :);      % buang baris NaN
            if size(V,1) < 2, return; end
            x = V(:,1); y = V(:,2);
            dx = max(x) - min(x);
            if dx < eps                        % (hampir) vertikal -> 90
                deg = pivcore.pot.faultAngle.fromPoints([0 0], [0 1]);
                if ~isfinite(deg), deg = 90; end
                return;
            end
            p = polyfit(x, y, 1);              % slope = p(1); y = slope*x + c
            % Normalkan lewat fromPoints: garis dari (0,0) ke (1,slope).
            deg = pivcore.pot.faultAngle.fromPoints([0 0], [1 p(1)]);
        end


        % ================================================================
        function deg = angleDegRel(vertsPx, refDeg)
        %ANGLEDEGREL  Sudut/dip polyline RELATIF referensi horizontal (koreksi
        %   kemiringan kamera). = angleDeg(verts) − refDeg, dinormalkan (-90,90].
        %   refDeg NaN/absen -> = angleDeg (relatif horizontal citra).
            deg = pivcore.io.pab4FaultGeom.angleDeg(vertsPx);
            if ~isfinite(deg), return; end
            if nargin < 2 || ~isscalar(refDeg) || ~isfinite(refDeg), return; end
            % Normalkan selisih lewat fromPoints (garis tak-berarah, (-90,90]).
            d = deg - double(refDeg);
            deg = pivcore.pot.faultAngle.fromPoints([0 0], [cosd(d) sind(d)]);
        end


        % ================================================================
        function cpp = cmPerPxFromGeom(dxCm, widthPx)
        %CMPERPXFROMGEOM  Rasio cm/pixel ISOTROPIK dari geometri indenter:
        %   cmPerPx = dxCm / widthPx. NaN bila argumen tak valid.
            cpp = NaN;
            if ~isscalar(dxCm)  || ~isfinite(dxCm)  || dxCm  <= 0, return; end
            if ~isscalar(widthPx) || ~isfinite(widthPx) || widthPx <= 0, return; end
            cpp = double(dxCm) / double(widthPx);
        end


        % ================================================================
        function r = growthRate(lenCm, dFrame, dtSec)
        %GROWTHRATE  cm/detik = lenCm / (dFrame * dtSec). dFrame = jumlah frame
        %   antara NUC-FSR dan FS-max terdekat. NaN bila argumen tak valid /
        %   dFrame<=0.
            r = NaN;
            if nargin < 3 || isempty(dtSec) || ~isfinite(dtSec) || dtSec <= 0, dtSec = 10; end
            if ~isscalar(lenCm) || ~isfinite(lenCm), return; end
            if ~isscalar(dFrame) || ~isfinite(dFrame) || dFrame <= 0, return; end
            r = double(lenCm) / (double(dFrame) * double(dtSec));
        end


        % ================================================================
        function r = dieOutRate(lenCm, dFrame, dtSec)
        %DIEOUTRATE  cm/detik = lenCm / (dFrame * dtSec). dFrame = jumlah frame
        %   antara FS-max terakhir dan END. Sama rumus dgn growthRate; dipisah
        %   demi kejelasan makna. NaN bila argumen tak valid / dFrame<=0.
            r = pivcore.io.pab4FaultGeom.growthRate(lenCm, dFrame, dtSec);
        end


        % ================================================================
        function [fr, dd] = nearestFsMaxToNuc(fsFrames, nucFrame)
        %NEARESTFSMAXTONUC  Dari daftar frame FS-max, pilih yg |selisih| ke
        %   nucFrame TERKECIL. fr = frame FS-max terpilih; dd = |fr-nucFrame|.
        %   Kosong / nuc NaN -> [NaN NaN].
            fr = NaN; dd = NaN;
            f = double(fsFrames(:).'); f = f(isfinite(f));
            if isempty(f) || ~isscalar(nucFrame) || ~isfinite(nucFrame), return; end
            [dd, ix] = min(abs(f - double(nucFrame)));
            fr = f(ix);
        end


        % ================================================================
        %                        NORMALISASI / ENCODE
        % ================================================================
        function doc = normalizeDoc(raw, dataFile)
        %NORMALIZEDOC  Rakit dokumen bersih dari hasil jsondecode.
            doc = pivcore.io.pab4FaultGeom.emptyDoc(dataFile);
            if ~isstruct(raw), return; end
            if isfield(raw,'formatVersion') && isscalar(raw.formatVersion)
                doc.formatVersion = double(raw.formatVersion);
            end
            if isfield(raw,'source') && ischar(raw.source), doc.source = raw.source; end
            if isfield(raw,'refHorizonDeg')
                doc.refHorizonDeg = pivcore.io.pab4FaultGeom.scal(raw.refHorizonDeg);
            end
            faults = {};
            if isfield(raw,'faults')
                fc = pivcore.io.pab4FaultGeom.tocell(raw.faults);
                for k = 1:numel(fc)
                    faults{end+1} = pivcore.io.pab4FaultGeom.normEntry(fc{k}); %#ok<AGROW>
                end
            end
            doc.faults = faults;
        end


        function e = normEntry(s)
        %NORMENTRY  Normalkan satu entri -> struct 2-fase lengkap (field selalu
        %   ada). MIGRASI kompat lama: field 'vertices'/'frameRef' (1-fase) ->
        %   verticesNuc/frameRefNuc.
            e = pivcore.io.pab4FaultGeom.entryStruct();
            if ~isstruct(s), return; end
            if isfield(s,'psgId'), e.psgId = pivcore.io.pab4FaultGeom.tostr(s.psgId); end
            if isfield(s,'fNum'),  e.fNum  = pivcore.io.pab4FaultGeom.tostr(s.fNum);  end
            % Fase NUC: field baru verticesNuc, else field lama 'vertices'.
            if isfield(s,'verticesNuc')
                e.verticesNuc = pivcore.io.pab4FaultGeom.normVerts(s.verticesNuc);
            elseif isfield(s,'vertices')
                e.verticesNuc = pivcore.io.pab4FaultGeom.normVerts(s.vertices);
            end
            if isfield(s,'frameRefNuc')
                e.frameRefNuc = pivcore.io.pab4FaultGeom.scal(s.frameRefNuc);
            elseif isfield(s,'frameRef')
                e.frameRefNuc = pivcore.io.pab4FaultGeom.scal(s.frameRef);
            end
            % Fase DIE.
            if isfield(s,'verticesDie'), e.verticesDie = pivcore.io.pab4FaultGeom.normVerts(s.verticesDie); end
            if isfield(s,'frameRefDie'), e.frameRefDie = pivcore.io.pab4FaultGeom.scal(s.frameRefDie); end
        end


        function doc = prepForEncode(doc)
        %PREPFORENCODE  Siapkan dokumen utk jsonencode. faults: cell -> tiap
        %   elemen entry-struct bersih. vertices dijadikan cell-of-[x y] supaya
        %   jsonencode SELALU menulis array-of-arrays (round-trip Nx2 stabil,
        %   termasuk N=1 yg kalau matriks biasa jsondecode balik jadi vektor).
            if ~isstruct(doc), doc = pivcore.io.pab4FaultGeom.emptyDoc(''); end
            if ~isfield(doc,'faults'), doc.faults = {}; end
            all = pivcore.io.pab4FaultGeom.tocell(doc.faults);
            out = cell(1, numel(all));
            for k = 1:numel(all)
                e = pivcore.io.pab4FaultGeom.normEntry(all{k});
                e.verticesNuc = pivcore.io.pab4FaultGeom.vertsToCell(e.verticesNuc);
                e.verticesDie = pivcore.io.pab4FaultGeom.vertsToCell(e.verticesDie);
                out{k} = e;
            end
            doc.faults = out;   % selalu cell -> JSON array
        end


        % --- helper vertex -------------------------------------------
        function V = normVerts(x)
        %NORMVERTS  Ratakan input vertex apa pun -> Nx2 double [x y].
        %   Terima: Nx2 matriks · cell-of-[x y] (dari jsonencode kami) · struct
        %   {x,y} · vektor 1x2 (N=1). Bentuk tak dikenal -> 0x2.
            V = zeros(0,2);
            if isempty(x), return; end
            if iscell(x)
                rows = zeros(0,2);
                for k = 1:numel(x)
                    v = pivcore.io.pab4FaultGeom.pt2(x{k});
                    if ~isempty(v), rows(end+1,:) = v; end %#ok<AGROW>
                end
                V = rows; return;
            end
            if isstruct(x)
                rows = zeros(0,2);
                for k = 1:numel(x)
                    xi = NaN; yi = NaN;
                    if isfield(x(k),'x'), xi = pivcore.io.pab4FaultGeom.scal(x(k).x); end
                    if isfield(x(k),'y'), yi = pivcore.io.pab4FaultGeom.scal(x(k).y); end
                    rows(end+1,:) = [xi yi]; %#ok<AGROW>
                end
                V = rows; return;
            end
            if isnumeric(x)
                M = double(x);
                if isvector(M) && numel(M) == 2
                    V = reshape(M,1,2); return;      % 1x2 / 2x1 -> 1 vertex
                end
                if size(M,2) == 2
                    V = M; return;                   % Nx2
                end
                if size(M,1) == 2
                    V = M.'; return;                 % 2xN -> Nx2
                end
            end
        end

        function v = pt2(x)
        %PT2  Satu titik -> 1x2 [x y] atau [] bila tak dikenal.
            v = [];
            if isnumeric(x) && numel(x) == 2, v = reshape(double(x),1,2); return; end
            if isstruct(x) && isfield(x,'x') && isfield(x,'y')
                v = [pivcore.io.pab4FaultGeom.scal(x.x) pivcore.io.pab4FaultGeom.scal(x.y)];
            end
        end

        function c = vertsToCell(V)
        %VERTSTOCELL  Nx2 -> cell{1xN} of [x y] (utk jsonencode array-of-arrays).
            V = pivcore.io.pab4FaultGeom.normVerts(V);
            c = cell(1, size(V,1));
            for k = 1:size(V,1), c{k} = V(k,:); end
        end


        % --- helper tipe ---------------------------------------------
        function c = tocell(x)
            if isempty(x), c = {}; return; end
            if iscell(x), c = reshape(x, 1, []); return; end
            if isstruct(x)
                c = cell(1, numel(x));
                for k = 1:numel(x), c{k} = x(k); end
                return;
            end
            c = {x};
        end

        function v = scal(x)
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end

        function t = normFtag(fNum)
        %NORMFTAG  Normalkan tag F# -> angka-string tanpa 'F' ('F3'/'3'/3 -> '3').
        %   '' / tak dikenal -> ''.
            t = '';
            s = pivcore.io.pab4FaultGeom.tostr(fNum);
            s = strtrim(s);
            if isempty(s), return; end
            s = regexprep(s, '^[Ff]', '');
            m = regexp(s, '\d+', 'match', 'once');
            if ~isempty(m), t = m; else, t = s; end
        end

        function s = tostr(x)
        %TOSTR  Ratakan apa pun ke char row aman (1 baris).
            if isempty(x), s = ''; return; end
            if ischar(x)
                if size(x,1) > 1, x = strjoin(cellstr(x), newline); end
                s = reshape(char(x), 1, []); return;
            end
            if isstring(x)
                s = char(strjoin(x(:).', newline)); s = reshape(s, 1, []); return;
            end
            if iscell(x)
                parts = cellfun(@(e) pivcore.io.pab4FaultGeom.tostr(e), x(:).', 'uni', 0);
                s = strjoin(parts, newline); s = reshape(char(s), 1, []); return;
            end
            if isnumeric(x) && isscalar(x)
                if isfinite(x), s = num2str(x); else, s = ''; end
                return;
            end
            try, s = reshape(char(string(x)), 1, []); catch, s = ''; end
        end

        function cleanupTmp(tmp)
            try, if isfile(tmp), delete(tmp); end, catch, end
        end

    end
end
