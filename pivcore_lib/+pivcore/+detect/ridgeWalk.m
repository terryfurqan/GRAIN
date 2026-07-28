classdef ridgeWalk
%RIDGEWALK  Deteksi & tracing punggungan (ridge) shear strain rate — SEMI-OTOMATIS.
%   Analog interpretasi seismik: user meng-klik SATU titik dekat punggungan shear
%   (pita merah/biru), sistem menelusuri (walk) sepanjang puncak |shear| ke DUA
%   arah sampai nilai turun di bawah ambang. Hasil = 1 polyline (Nx2 koordinat grid
%   yang diberikan) yang bisa diedit lagi oleh user.
%
%   Prinsip (sesuai permintaan user):
%     - Basis ridge = |shear| ABSOLUT (merah + & biru - diperlakukan sama).
%     - Polaritas (tanda) DIKUNCI dari sel seed supaya walk tak lompat antar-pita
%       berlawanan tanda.
%     - Klik dulu di-SNAP ke puncak lokal terdekat (window snapRadius sel), lalu
%       walk 2 arah mengikuti tetangga-maju ber-|shear| tertinggi & >= threshold.
%     - Ambang = max(thrAbs, thrFrac * seedVal): user atur lewat "maksimum-minimum
%       shear" (thrAbs, mis. 0.04) ATAU relatif seed (thrFrac).
%
%   MURNI / HEADLESS (tak menyentuh GUI/handle). Semua fungsi bisa diuji langsung.
%   Input Z = matriks shear BERTANDA (mis. dari pivcore.data.computeShearRate).
%   Koordinat keluaran memakai matriks X,Y (grid PIV, satuan piksel gambar) bila
%   diberikan; bila tidak, memakai indeks [col row].
%
%   Penempatan: GRAIN/pivcore_lib/+pivcore/+detect/ridgeWalk.m

    methods (Static)

        % ================================================================
        function opt = defaults()
        %DEFAULTS  Parameter deteksi ridge default.
        %   snapRadius : radius window (sel) untuk snap klik -> puncak lokal.
        %   thrAbs     : ambang absolut |shear| (walk berhenti bila < ini). NaN=abaikan.
        %   thrFrac    : ambang relatif thd nilai seed (0..1).
        %   smoothSigma: sigma gaussian penghalus |shear| (stabilkan ridge). 0=off.
        %   stepMax    : batas langkah walk per-arah (jaga-jaga).
        %   inertia    : bias 0..1 menyukai arah lurus (kurangi zig-zag).
        %   minVerts   : polyline < ini dianggap gagal.
            %   gapTol : berapa sel berturut BOLEH di bawah ambang (jurang kecil)
            %            sebelum ridge dianggap putus. Menjaga ridge lemah/terputus
            %            tetap tersambung.
            opt = struct('snapRadius',8, 'thrAbs',0.015, 'thrFrac',0.30, ...
                         'smoothSigma',1.0, 'stepMax',800, 'inertia',0.02, ...
                         'minVerts',2, 'gapTol',3);
        end

        % ================================================================
        function [V, info] = trace(Z, clickXY, X, Y, opt)
        %TRACE  Jejak ridge dari satu klik. INTI modul.
        %   Z       : matriks shear BERTANDA (nR x nC).
        %   clickXY : [x y] lokasi klik dalam koordinat X/Y (piksel). Bila X/Y kosong,
        %             clickXY diperlakukan sbg [col row] indeks grid.
        %   X,Y     : matriks koordinat grid (sama ukuran Z). [] -> pakai indeks.
        %   opt     : struct (lihat defaults); field hilang diisi default.
        %   Keluaran:
        %     V    : Nx2 polyline dalam koordinat X/Y (atau [col row] bila X/Y kosong).
        %     info : struct diagnostik {seedRC, seedVal, polarity, meanAbs, lenGrid,
        %            thr, ok, msg}.
            if nargin < 3, X = []; end
            if nargin < 4, Y = []; end
            if nargin < 5, opt = struct(); end
            opt = pivcore.detect.ridgeWalk.fillOpt(opt);

            V = zeros(0,2);
            info = struct('seedRC',[NaN NaN], 'seedVal',NaN, 'polarity',0, ...
                          'meanAbs',NaN, 'lenGrid',0, 'thr',NaN, 'ok',false, 'msg','');

            [nR, nC] = size(Z);
            if nR < 3 || nC < 3
                info.msg = 'Grid shear terlalu kecil.'; return;
            end

            % --- shear BERTANDA (tanpa nilai absolut) --------------------
            %   Basis ridge = shear TERARAH sesuai polaritas titik klik: klik di
            %   pita BIRU (shear<0) -> telusuri nilai NEGATIF (cari paling negatif);
            %   klik di MERAH (shear>0) -> nilai positif. Kita bentuk medan searah
            %   S = polarity * Zsmooth -> puncak pita = S paling BESAR (positif).
            %   Tak ada abs -> tak mungkin lompat ke pita lawan tanda.
            Zs = Z; Zs(~isfinite(Zs)) = 0;
            if opt.smoothSigma > 0
                Zs = pivcore.detect.ridgeWalk.smooth(Zs, opt.smoothSigma);
            end

            % --- klik -> indeks grid (col,row) terdekat -------------------
            [c0, r0] = pivcore.detect.ridgeWalk.xy2rc(clickXY, X, Y, nR, nC);
            if isnan(c0) || isnan(r0)
                info.msg = 'Klik di luar grid.'; return;
            end

            % --- POLARITAS dari TANDA di titik klik (bukan max absolut) ----
            %   Ambil tanda dominan pita di window kecil sekitar klik (median tanda
            %   dari sel ber-|shear| berarti) supaya robust thd 1 sel berisik.
            polarity = pivcore.detect.ridgeWalk.clickPolarity(Zs, r0, c0, opt);
            if polarity == 0, polarity = -1; end   % default biru (user: seringnya biru)

            % Medan searah: puncak pita = nilai terbesar.
            S = polarity * Zs;

            % --- snap ke puncak lokal pita (window) ----------------------
            sr = opt.snapRadius;
            rr = max(r0-sr,1):min(r0+sr,nR);
            cc = max(c0-sr,1):min(c0+sr,nC);
            sub = S(rr,cc);
            [mv, mi] = max(sub(:));
            if ~isfinite(mv) || mv <= 0
                info.msg = 'Tak ada pita shear (searah polaritas klik) di sekitar klik.'; return;
            end
            [sr2, sc2] = ind2sub(size(sub), mi);
            r = rr(sr2); c = cc(sc2);
            seedVal = S(r,c);

            thr = pivcore.detect.ridgeWalk.threshold(seedVal, opt);
            info.seedRC = [r c];
            info.seedVal = seedVal;
            info.polarity = polarity;
            info.thr = thr;

            % --- walk 2 arah pada medan searah S -------------------------
            pathA = pivcore.detect.ridgeWalk.walkDir(S, r, c, thr, +1, opt);
            pathB = pivcore.detect.ridgeWalk.walkDir(S, r, c, thr, -1, opt);
            ridgeRC = [flipud(pathB); [r c]; pathA];

            % dedup titik berurutan identik
            if size(ridgeRC,1) >= 2
                keep = [true; any(diff(ridgeRC,1,1) ~= 0, 2)];
                ridgeRC = ridgeRC(keep,:);
            end

            if size(ridgeRC,1) < opt.minVerts
                info.msg = sprintf('Ridge terlalu pendek (%d titik).', size(ridgeRC,1));
                return;
            end

            % --- konversi indeks -> koordinat ----------------------------
            V = pivcore.detect.ridgeWalk.rc2xy(ridgeRC, X, Y);
            % mean magnitudo sepanjang ridge (S searah = |shear| pita) — nama
            % 'meanAbs' dipertahankan (kompat sidecar/tabel).
            info.meanAbs = mean(arrayfun(@(a,b) S(a,b), ridgeRC(:,1), ridgeRC(:,2)));
            info.lenGrid = sum(hypot(diff(V(:,1)), diff(V(:,2))));
            info.ok = true;
        end

        % ================================================================
        function p = clickPolarity(Zs, r0, c0, opt)
        %CLICKPOLARITY  Tanda pita di titik klik (−1 biru / +1 merah). Ambil tanda
        %   dari sel ber-magnitudo TERBESAR di window kecil sekitar klik (robust
        %   thd 1 sel berisik & thd klik sedikit meleset dari inti pita).
            p = 0;
            [nR, nC] = size(Zs);
            w = max(2, round(opt.snapRadius/2));
            rr = max(r0-w,1):min(r0+w,nR);
            cc = max(c0-w,1):min(c0+w,nC);
            sub = Zs(rr,cc);
            [~, mi] = max(abs(sub(:)));
            if isempty(mi), return; end
            p = sign(sub(mi));
        end

        % ================================================================
        function P = walkDir(S, r, c, thr, dirSign, opt)
        %WALKDIR  Telusuri ridge dari (r,c) ke SATU arah (dirSign=+1/-1) pada medan
        %   SEARAH S (= polarity*shear; puncak pita = S terbesar positif).
        %   Langkah pertama: pilih tetangga-8 ber-S tertinggi; dirSign membalik utk
        %   dua sisi. Lalu tiap langkah: dari 3 arah maju (lurus + 2 diagonal apit)
        %   pilih S tertinggi; berhenti bila S < thr (toleransi 'jurang' opt.gapTol
        %   sel di bawah ambang sebelum benar-benar putus) atau lewat batas langkah.
            [nR, nC] = size(S);
            P = zeros(0,2);

            % arah awal
            best = -inf; bd = [0 0];
            for dr = -1:1
                for dc = -1:1
                    if dr==0 && dc==0, continue; end
                    rr = r+dr; cc = c+dc;
                    if rr<1||rr>nR||cc<1||cc>nC, continue; end
                    if S(rr,cc) > best, best = S(rr,cc); bd = [dr dc]; end
                end
            end
            if all(bd == 0), return; end
            dir = dirSign * bd;
            cr = r; cc0 = c;
            gap = 0;                 % berapa sel berturut di bawah ambang
            pend = zeros(0,2);        % titik tertahan (di jurang) — commit bila ridge lanjut

            for s = 1:opt.stepMax
                cand = pivcore.detect.ridgeWalk.forwardNeighbors(dir);
                best = -inf; pick = []; pdir = [];
                for i = 1:size(cand,1)
                    nr = cr + cand(i,1); ncc = cc0 + cand(i,2);
                    if nr<1||nr>nR||ncc<1||ncc>nC, continue; end
                    v = S(nr,ncc);
                    if isequal(cand(i,:), dir), v = v * (1 + opt.inertia); end
                    if v > best, best = v; pick = [nr ncc]; pdir = cand(i,:); end
                end
                if isempty(pick), break; end
                if S(pick(1),pick(2)) < thr
                    % di bawah ambang -> mungkin cuma 'jurang' kecil; lanjut sampai
                    % gapTol sel. Kalau ridge bangkit lagi, titik jurang ikut masuk.
                    gap = gap + 1;
                    if gap > opt.gapTol, break; end
                    pend(end+1,:) = pick; %#ok<AGROW>
                    cr = pick(1); cc0 = pick(2); dir = pdir;
                    continue;
                end
                % di atas ambang: commit titik tertahan (jurang) + titik ini.
                if ~isempty(pend), P = [P; pend]; pend = zeros(0,2); end %#ok<AGROW>
                gap = 0;
                P(end+1,:) = pick; %#ok<AGROW>
                cr = pick(1); cc0 = pick(2); dir = pdir;
            end
        end

        function thr = threshold(seedVal, opt)
        %THRESHOLD  Ambang berhenti pada medan searah S. Bila thrAbs finite -> pakai
        %   NILAI ABSOLUT itu (mis. 0.02) sbg batas magnitudo pita; else relatif
        %   thrFrac*seedVal. Diambil MINIMUM keduanya bila keduanya aktif supaya
        %   ridge lemah (seed kecil) TIDAK langsung mati (bug lama: thrAbs>seed).
            fr = opt.thrFrac * seedVal;
            if isfinite(opt.thrAbs) && opt.thrFrac > 0
                thr = min(opt.thrAbs, fr);
            elseif isfinite(opt.thrAbs)
                thr = opt.thrAbs;
            else
                thr = fr;
            end
            if ~isfinite(thr) || thr < 0, thr = 0; end
        end

        function C = forwardNeighbors(dir)
        %FORWARDNEIGHBORS  3 arah maju pada grid 8-connect: lurus + 2 diagonal apit.
            d8 = [ -1 0; -1 1; 0 1; 1 1; 1 0; 1 -1; 0 -1; -1 -1];
            [~, idx] = ismember(dir, d8, 'rows');
            if idx == 0, idx = 1; end
            i1 = mod(idx-2, 8) + 1;   % sebelum
            i2 = mod(idx,   8) + 1;   % sesudah
            C = [d8(idx,:); d8(i1,:); d8(i2,:)];
        end

        % ================================================================
        %                    HELPER KOORDINAT
        % ================================================================
        function [c, r] = xy2rc(clickXY, X, Y, nR, nC)
        %XY2RC  Koordinat klik [x y] -> indeks grid (col,row) terdekat.
            c = NaN; r = NaN;
            if numel(clickXY) < 2, return; end
            px = clickXY(1); py = clickXY(2);
            if isempty(X) || isempty(Y)
                % clickXY = [col row] langsung
                c = round(px); r = round(py);
            else
                xr = X(1,:); yc = Y(:,1);
                % index terdekat via interp1 (grid monotonik)
                c = round(pivcore.detect.ridgeWalk.nearestIdx(xr, px));
                r = round(pivcore.detect.ridgeWalk.nearestIdx(yc, py));
            end
            c = min(max(c,1), nC);
            r = min(max(r,1), nR);
        end

        function idx = nearestIdx(vec, val)
        %NEARESTIDX  Indeks elemen vec terdekat ke val (robust utk vec naik/turun).
            vec = double(vec(:));
            [~, idx] = min(abs(vec - val));
        end

        function V = rc2xy(rc, X, Y)
        %RC2XY  Konversi Nx2 [row col] -> Nx2 [x y] koordinat grid. X/Y kosong ->
        %   pakai [col row] (kolom=x, baris=y) sbg koordinat indeks.
            if isempty(X) || isempty(Y)
                V = [rc(:,2), rc(:,1)];
                return;
            end
            n = size(rc,1);
            V = zeros(n,2);
            for i = 1:n
                V(i,1) = X(rc(i,1), rc(i,2));
                V(i,2) = Y(rc(i,1), rc(i,2));
            end
        end

        function As = smooth(A, sigma)
        %SMOOTH  Gaussian smoothing. Pakai imgaussfilt bila ada; else fallback konv.
            if exist('imgaussfilt','file') == 2
                try
                    As = imgaussfilt(A, sigma); return;
                catch
                end
            end
            % fallback separable gaussian
            rad = max(1, ceil(3*sigma));
            t = -rad:rad;
            g = exp(-(t.^2)/(2*sigma^2)); g = g / sum(g);
            As = conv2(g, g, A, 'same');
        end

        function opt = fillOpt(opt)
        %FILLOPT  Lengkapi field opt yang hilang dgn default.
            d = pivcore.detect.ridgeWalk.defaults();
            if ~isstruct(opt), opt = struct(); end
            fn = fieldnames(d);
            for i = 1:numel(fn)
                if ~isfield(opt, fn{i}) || isempty(opt.(fn{i}))
                    opt.(fn{i}) = d.(fn{i});
                end
            end
        end

    end
end
