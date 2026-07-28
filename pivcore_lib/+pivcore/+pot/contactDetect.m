classdef contactDetect
%CONTACTDETECT  Deteksi TITIK KONTAK (perpotongan pertama) antar pasangan kurva
%   POT yang BERURUTAN sepanjang garis PSG (Step 3v2).
%
%   Konsep domain (imbrikasi sesar naik):
%     - Tiap titik pengukuran sepanjang garis menghasilkan satu kurva
%       displacement-vs-frame. Titik yang lebih DEPAN (sudah ter-translasi jauh)
%       kurvanya naik lebih dulu lalu relatif KONSTAN pada nilai tinggi; titik di
%       BELAKANGNYA kurvanya menyusul NAIK.
%     - Sebuah bidang sesar ditandai oleh gerak DUA hanging wall yang terpisah.
%       Saat kurva belakang (yang sedang naik) "menyusul" / KONTAK dengan kurva
%       depan (yang sudah tinggi & konstan), selisih displacement keduanya
%       mengecil -> net-slip antar keduanya ~ 0. FRAME PERTAMA terjadinya kontak
%       itu = TITIK TRANSISI = penanda berakhirnya aktivitas sesar tsb.
%
%   Aturan deteksi (per pasang tetangga berurutan i & i+1):
%     - Kontak = FRAME PERTAMA di mana |front(f) - trailing(f)| <= tol (toleransi
%       ABSOLUT, satuan displacement), DENGAN syarat kurva trailing sudah "bangun"
%       (telah naik melewati ambang aktivitas) supaya tak salah-deteksi di awal
%       (saat semua kurva ~ 0).
%     - 1 pasang -> PALING BANYAK 1 titik kontak (kontak pertama).
%
%   Stateless & MURNI: input = cell deret + opsi, output = struct titik kontak.
%   Aman headless & di test.
%
%   API:
%     R   = pivcore.pot.contactDetect.run(seriesCell, opt)        % semua pasangan
%     R   = pivcore.pot.contactDetect.run(seriesCell, opt, idxRange)  % subset berurutan
%     opt = pivcore.pot.contactDetect.defaultOpts()
%     [f,v] = pivcore.pot.contactDetect.firstContact(front, trailing, opt)
%
%   Penempatan: PIVTerry/+pivterry/+pot/contactDetect.m

    methods (Static)

        % ================================================================
        function opt = defaultOpts()
        %DEFAULTOPTS  Parameter deteksi kontak.
        %   tol        : ambang ABSOLUT selisih displacement utk "kontak"
        %                (satuan kurva). |front-trailing| <= tol -> kontak.
        %   wakeFrac   : kurva trailing dianggap "bangun" bila telah mencapai
        %                wakeFrac * (puncaknya sendiri) -> cegah deteksi di frame
        %                awal saat kedua kurva ~ 0.
        %   minFrame   : abaikan kontak sebelum frame ini (buffer awal).
        %   requireRise: bila true, hanya hitung kontak setelah trailing mulai naik
        %                berarti (range trailing > minRange).
        %   minRange   : range minimum kurva trailing agar dianggap aktif.
        %
        %   --- Syarat POLA (auto dari data; cegah deteksi tersebar) ---
        %   requirePlateau : front (atas) harus PLATEAU (slope ~0) di jendela
        %                    sebelum kontak. Inti pola domain: kurva depan naik
        %                    dulu lalu KONSTAN, kurva belakang menyusul -> kontak.
        %   requireApproach: gap |front-trailing| harus BERANGSUR mengecil
        %                    (menyusut) di jendela sebelum kontak (trailing
        %                    mengejar), bukan kebetulan dekat sesaat.
        %   requireFrontHigh: front harus berada di level "tinggi" (sudah dekat
        %                    puncaknya sendiri) di titik kontak -> abaikan kurva
        %                    yang melintas di RUANG KOSONG antar bundel.
        %   The window/plateau/high thresholds are AUTO-derived per curve in
        %   firstContact (relatif thd panjang & rentang nilai), bukan angka tetap.
            opt = struct( ...
                'tol',         0.20, ...
                'wakeFrac',    0.30, ...
                'minFrame',    2, ...
                'requireRise', true, ...
                'minRange',    0.50, ...
                'requirePlateau',  true, ...
                'requireApproach', true, ...
                'requireFrontHigh',true);
        end


        % ================================================================
        function R = run(seriesCell, opt, idxRange)
        %RUN  Deteksi kontak utk SEMUA pasangan tetangga berurutan (default) atau
        %   hanya pada subset indeks BERURUTAN `idxRange` (mis. 100:200).
        %
        %   seriesCell : cell {1xN}, sudah TERURUT sepanjang garis (posPx naik).
        %   idxRange   : (opsional) vektor indeks BERURUTAN (subset). Pasangan yg
        %                diuji = (k,k+1) untuk k di dalam range yg dua-duanya ada.
        %
        %   R (struct):
        %     .pairs    : struct-array titik kontak. Field:
        %                   .i, .j      (indeks kurva front=i, trailing=j=i+1)
        %                   .frame      (frame kontak; NaN bila tak ada)
        %                   .value      (nilai displacement di frame kontak)
        %                   .hit        (logical: ada kontak)
        %     .nPairs   : jumlah pasangan diuji
        %     .nHit     : jumlah pasangan yang kontak
        %     .summary  : ringkasan
            if nargin < 2 || isempty(opt), opt = pivcore.pot.contactDetect.defaultOpts(); end
            R = struct('pairs', pivcore.pot.contactDetect.emptyPair(), ...
                'nPairs',0,'nHit',0,'summary','');
            if ~iscell(seriesCell), seriesCell = {seriesCell}; end
            N = numel(seriesCell);
            if N < 2, R.summary = 'Need >= 2 curves.'; return; end

            % Tentukan pasangan (k,k+1) yang diuji.
            if nargin < 3 || isempty(idxRange)
                ks = 1:(N-1);
            else
                ir = idxRange(:).';
                ir = ir(ir >= 1 & ir <= N);
                ir = unique(ir);                 % berurutan & unik
                % Pasangan dalam subset: k & k+1 dua-duanya di subset.
                inSub = false(1,N); inSub(ir) = true;
                ks = [];
                for k = 1:(N-1)
                    if inSub(k) && inSub(k+1), ks(end+1) = k; end %#ok<AGROW>
                end
            end

            pairs = pivcore.pot.contactDetect.emptyPair();
            nHit = 0;
            for t = 1:numel(ks)
                k = ks(t);
                front    = seriesCell{k};        % lebih depan (urut posPx)
                trailing = seriesCell{k+1};      % di belakangnya (menyusul naik)
                [f, v, hit] = pivcore.pot.contactDetect.firstContact(front, trailing, opt);
                e = pivcore.pot.contactDetect.emptyPairOne();
                e.i = k; e.j = k+1; e.frame = f; e.value = v; e.hit = hit;
                if isempty(pairs), pairs = e; else, pairs(end+1) = e; end %#ok<AGROW>
                if hit, nHit = nHit + 1; end
            end
            R.pairs   = pairs;
            R.nPairs  = numel(ks);
            R.nHit    = nHit;
            R.summary = sprintf('Contact: %d/%d neighbour pair(s) in contact (tol=%.3g).', ...
                nHit, numel(ks), opt.tol);
        end


        % ================================================================
        function [frame, value, hit] = firstContact(front, trailing, opt)
        %FIRSTCONTACT  Frame PERTAMA di mana kurva `trailing` (sedang naik)
        %   MENYUSUL & menyentuh kurva `front` (yang sudah naik lalu PLATEAU),
        %   mengikuti POLA domain yang diamati:
        %     1. front (atas) sudah naik & KONSTAN (plateau) menjelang kontak,
        %     2. trailing (bawah) sedang NAIK (mengejar),
        %     3. gap |front-trailing| BERANGSUR mengecil (menyusut) ke ~0,
        %     4. front berada di level TINGGI (dekat puncaknya) -> kurva yang
        %        melintas di RUANG KOSONG antar bundel diabaikan.
        %   Ambang plateau/tinggi/jendela diturunkan OTOMATIS dari data (relatif
        %   thd panjang & rentang nilai), bukan angka tetap. Mengembalikan
        %   (frame, value, hit); value = nilai trailing di frame kontak.
            if nargin < 3 || isempty(opt), opt = pivcore.pot.contactDetect.defaultOpts(); end
            frame = NaN; value = NaN; hit = false;
            a = double(front(:)).';        % front  = kurva atas (plateau)
            b = double(trailing(:)).';     % trailing = kurva bawah (menyusul)
            n = min(numel(a), numel(b));
            if n < 1, return; end
            a = a(1:n); b = b(1:n);
            fin = isfinite(a) & isfinite(b);
            if ~any(fin), return; end

            % --- Rentang & puncak tiap kurva (auto-skala) ---
            aPk = max(a(fin)); aMn = min(a(fin));
            bPk = max(b(fin)); bMn = min(b(fin));
            if ~isfinite(aPk) || ~isfinite(bPk), return; end
            aRange = max(0, aPk - aMn);
            bRange = max(0, bPk - bMn);
            if opt.requireRise && bRange < opt.minRange
                return;     % trailing nyaris datar -> bukan kurva aktif
            end
            wake = bMn + opt.wakeFrac * bRange;              % ambang "bangun" trailing

            % --- Parameter pola AUTO dari data ---
            % Jendela lihat-ke-belakang ~10% panjang deret (min 3 frame).
            W = max(3, round(0.10 * n));
            % Toleransi "plateau" front = slope per-frame kecil thd rentang front.
            % (front dianggap konstan bila naik < ~3% rentang-nya per frame.)
            plSlope = 0.03 * max(aRange, eps);
            % Level "tinggi" front: minimal 70% jalan dari dasar ke puncaknya
            % sendiri -> abaikan front yang masih rendah (di ruang kosong bawah).
            frontHigh = aMn + 0.70 * aRange;

            gap = abs(a - b);
            startF = max(1, round(opt.minFrame));
            for f = startF:n
                if ~fin(f), continue; end
                if b(f) < wake, continue; end                % trailing belum bangun
                if gap(f) > opt.tol, continue; end           % belum cukup dekat

                w0 = max(1, f - W);                           % awal jendela lihat-balik

                % (4) front harus TINGGI di titik kontak (bukan di ruang kosong).
                if opt.requireFrontHigh && a(f) < frontHigh
                    continue;
                end
                % (1) front PLATEAU menjelang kontak: rata-rata |slope| di jendela
                %     [w0..f] kecil (front sudah konstan, tidak sedang melonjak).
                if opt.requirePlateau
                    seg = a(w0:f);
                    seg = seg(isfinite(seg));
                    if numel(seg) >= 2
                        mSlope = mean(abs(diff(seg)));
                        if mSlope > plSlope, continue; end    % front belum konstan
                    end
                end
                % (2)+(3) trailing MENGEJAR: gap di awal jendela jelas lebih besar
                %     dari gap di titik kontak (selisih berangsur mengecil), dan
                %     trailing naik (b di akhir > b di awal jendela).
                if opt.requireApproach
                    g0 = gap(w0); gf = gap(f);
                    if ~(isfinite(g0) && isfinite(gf)), continue; end
                    % gap harus menyusut nyata (>1 tol) supaya bukan kebetulan
                    % berdekatan sesaat di puncak yang sama-sama datar.
                    if ~(g0 > gf + opt.tol), continue; end
                    if ~(b(f) > b(w0)), continue; end          % trailing memang naik
                end

                frame = f; value = b(f); hit = true; return;
            end
        end


        % ================================================================
        function p = emptyPair()
        %EMPTYPAIR  Struct-array kosong (0x0) titik kontak.
            p = struct('i',{},'j',{},'frame',{},'value',{},'hit',{});
        end

        function e = emptyPairOne()
            e = struct('i',NaN,'j',NaN,'frame',NaN,'value',NaN,'hit',false);
        end

    end
end
