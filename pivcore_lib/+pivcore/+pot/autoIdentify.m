classdef autoIdentify
%AUTOIDENTIFY  Mesin IDENTIFIKASI OTOMATIS kurva HW-#/F-# (Step 4), berbasis
%   ATURAN yang DIPELAJARI dari rekaman manual pengguna (mis. PCON D1 OK).
%
%   Latar: di Step 3 pengguna mengidentifikasi kurva SECARA MANUAL lalu MEREKAM
%   karakteristiknya (pivcore.io.assignDataset -> _context/). Setelah mengkaji
%   rekaman PCON D1 (146 kurva, 13 grup HW-1..HW-7 / F-1..F-6), pola identifikasi
%   pengguna terbukti REPRODUSIBEL 100% dengan aturan segmentasi sekuens berikut:
%
%   POLA DOMAIN (imbrikasi sesar naik):
%     - Titik diakuisisi sepanjang GARIS PSG dgn spacing tetap (mis. 10 px).
%     - ZONA SESAR (F) disampel RAPAT (deret titik berjarak ~spacing dasar):
%       pengguna ingin resolusi halus di bidang diskontinuitas.
%     - HANGING WALL (HW) = balok bergerak; pengguna hanya menaruh DUA titik
%       penanda yang MENGAPIT celah lebar (interior balok jarang disampel).
%
%   ATURAN (run-based segmentation):
%     1. Urutkan record berdasar posisi sepanjang garis (posPx; fallback indeks).
%     2. Kelompokkan jadi RUN RAPAT maksimal: titik berurutan yg jaraknya
%        <= denseGap (adaptif: 1.5x spacing dasar = median gap kecil).
%     3. Untuk run ke-r (1-based):
%          - titik PERTAMA run        -> HW-r      (penambat penutup balok r)
%          - titik-titik INTERIOR run -> F-r       (bidang sesar ke-r)
%          - titik TERAKHIR run       -> HW-(r+1)  (penambat pembuka balok r+1)
%        Run singleton (1 titik) -> HW-r (penambat tunggal).
%     Hasil: barisan berselang-seling HW-1, F-1, HW-2, F-2, ... persis cara
%     pengguna melabeli. Diverifikasi 100% pada PCON D1.
%
%   Stateless & MURNI: tak menyentuh GUI/handle. Input = records (atau posPx +
%   data), output = label per-record + skor keyakinan + ringkasan segmen. Aman
%   dipanggil headless & di test.
%
%   API:
%     R = pivcore.pot.autoIdentify.run(records)            % opsi default
%     R = pivcore.pot.autoIdentify.run(records, opts)
%     opts = pivcore.pot.autoIdentify.defaultOpts()
%     [labels,info] = pivcore.pot.autoIdentify.fromPos(posPx, opts)
%
%   R (struct):
%     .labels    : 1xN cellstr label per record ('' bila tak ter-ID)
%     .conf      : 1xN skor keyakinan [0..1] per record
%     .runs      : struct-array segmen rapat (a,b idx, n, posLo, posHi)
%     .denseGap  : ambang jarak rapat yang dipakai (px)
%     .baseSpacing : spacing dasar terdeteksi (px)
%     .nHW, .nF  : jumlah grup HW / F yang dihasilkan
%     .summary   : char ringkasan singkat
%
%   Penempatan: PIVTerry/+pivterry/+pot/autoIdentify.m

    methods (Static)

        % ================================================================
        function opt = defaultOpts()
        %DEFAULTOPTS  Parameter aturan (dipelajari dari PCON D1).
        %   denseFactor  : ambang rapat = denseFactor * spacing dasar.
        %   denseGapFixed : bila >0, paksa ambang rapat ini (px), abaikan adaptif.
        %   minRunForFault: panjang run minimum agar interiornya jadi F (>=3 =
        %                   ada >=1 titik interior). Run lebih pendek -> hanya HW.
            opt = struct( ...
                'denseFactor',   1.5, ...
                'denseGapFixed', 0, ...
                'minRunForFault', 3);
        end


        % ================================================================
        function R = run(records, opt)
        %RUN  Identifikasi otomatis dari struct-array record POT-PSG4.
        %   records butuh field .posPx (posisi px sepanjang garis); bila tak ada,
        %   dipakai urutan indeks sbg posisi (spacing=1). .data hanya dipakai utk
        %   skor keyakinan (opsional).
            if nargin < 2 || isempty(opt), opt = pivcore.pot.autoIdentify.defaultOpts(); end
            R = pivcore.pot.autoIdentify.emptyResult();
            if isempty(records) || ~isstruct(records), return; end
            nR = numel(records);

            % --- posisi sepanjang garis (px) ---
            pos = nan(1, nR);
            for r = 1:nR
                if isfield(records(r),'posPx') && isscalar(records(r).posPx) ...
                        && isfinite(records(r).posPx)
                    pos(r) = double(records(r).posPx);
                end
            end
            if ~any(isfinite(pos))
                pos = 1:nR;                 % fallback: urutan indeks
            else
                % isi posisi hilang dgn indeks-skala agar urutan stabil
                bad = ~isfinite(pos);
                if any(bad), pos(bad) = i_fillPos(pos, bad); end
            end

            % Urutkan record berdasar posisi (kembalikan ke urutan record asli).
            [~, ord] = sort(pos);
            posS = pos(ord);

            [labS, info] = pivcore.pot.autoIdentify.fromPos(posS, opt);

            % Skor keyakinan per titik (urutan tersortir) -> dipetakan balik.
            confS = pivcore.pot.autoIdentify.confidence(posS, info);

            % Petakan label & conf kembali ke urutan record asli.
            labels = repmat({''}, 1, nR);
            conf   = zeros(1, nR);
            for k = 1:nR
                labels{ord(k)} = labS{k};
                conf(ord(k))   = confS(k);
            end

            R.labels      = labels;
            R.conf        = conf;
            R.runs        = info.runs;
            R.denseGap    = info.denseGap;
            R.baseSpacing = info.baseSpacing;
            R.nHW         = info.nHW;
            R.nF          = info.nF;
            R.summary     = sprintf(['Auto-ID: %d curve(s) -> %d HW / %d F group(s) ', ...
                '(denseGap=%.1f px, base=%.1f px).'], nR, info.nHW, info.nF, ...
                info.denseGap, info.baseSpacing);
        end


        % ================================================================
        function [labels, info] = fromPos(posS, opt)
        %FROMPOS  Inti aturan: posisi TERSORTIR (px) -> label per titik.
        %   posS  : 1xN posisi menaik (px). labels : 1xN cellstr.
        %   info  : struct (runs, denseGap, baseSpacing, nHW, nF).
            if nargin < 2 || isempty(opt), opt = pivcore.pot.autoIdentify.defaultOpts(); end
            n = numel(posS);
            labels = repmat({''}, 1, n);
            info = struct('runs', struct('a',{},'b',{},'n',{},'posLo',{},'posHi',{}), ...
                'denseGap', NaN, 'baseSpacing', NaN, 'nHW', 0, 'nF', 0);
            if n == 0, return; end
            if n == 1
                labels{1} = 'HW-1';
                info.runs(1) = struct('a',1,'b',1,'n',1,'posLo',posS(1),'posHi',posS(1));
                info.nHW = 1; info.baseSpacing = NaN; info.denseGap = NaN;
                return;
            end

            gaps = diff(posS);
            gaps = gaps(isfinite(gaps) & gaps >= 0);

            % --- spacing dasar = median gap "kecil" (kelompok bawah) ---
            if isempty(gaps)
                base = 1;
            else
                med = median(gaps);
                small = gaps(gaps <= med);
                if isempty(small), small = gaps; end
                base = median(small);
                if ~isfinite(base) || base <= 0, base = min(gaps(gaps > 0)); end
                if isempty(base) || ~isfinite(base) || base <= 0, base = 1; end
            end
            info.baseSpacing = base;

            if opt.denseGapFixed > 0
                denseGap = opt.denseGapFixed;
            else
                denseGap = opt.denseFactor * base;
            end
            info.denseGap = denseGap;

            % --- run rapat maksimal: titik berurutan dgn gap <= denseGap ---
            runs = struct('a',{},'b',{},'n',{},'posLo',{},'posHi',{});
            i = 1;
            while i <= n
                j = i;
                while j+1 <= n && (posS(j+1) - posS(j)) <= denseGap
                    j = j + 1;
                end
                runs(end+1) = struct('a',i,'b',j,'n',j-i+1, ...
                    'posLo',posS(i),'posHi',posS(j)); %#ok<AGROW>
                i = j + 1;
            end
            info.runs = runs;

            % --- pelabelan per run ---
            nHW = 0; nF = 0;
            for ri = 1:numel(runs)
                a = runs(ri).a; b = runs(ri).b;
                if a == b
                    labels{a} = sprintf('HW-%d', ri);   % penambat tunggal
                    nHW = max(nHW, ri);
                    continue;
                end
                labels{a} = sprintf('HW-%d', ri);        % penutup balok r
                labels{b} = sprintf('HW-%d', ri+1);      % pembuka balok r+1
                nHW = max(nHW, ri+1);
                if (b-1) >= (a+1) && runs(ri).n >= opt.minRunForFault
                    for k = a+1:b-1
                        labels{k} = sprintf('F-%d', ri);
                    end
                    nF = nF + 1;
                end
            end
            info.nHW = nHW;
            info.nF  = nF;
        end


        % ================================================================
        function confS = confidence(posS, info)
        %CONFIDENCE  Skor keyakinan [0..1] per titik (urutan tersortir).
        %   Heuristik transparan:
        %     - Titik INTERIOR run rapat (F) -> keyakinan TINGGI: jaraknya ke
        %       kedua tetangga <= denseGap (jelas bagian zona sesar).
        %     - Titik penambat HW di tepi run -> keyakinan SEDANG-TINGGI bila
        %       celah ke sisi balok jauh > denseGap (kontras jelas), turun bila
        %       celahnya nanggung (dekat ambang) -> ambigu, perlu dicek mata.
        %   Tujuan: menandai titik yg layak diperiksa visual di Step 4.
            n = numel(posS);
            confS = zeros(1, n);
            if n == 0, return; end
            if n == 1, confS(1) = 0.5; return; end
            dg = info.denseGap;
            if ~isfinite(dg) || dg <= 0, dg = 1; end
            for i = 1:n
                gp = Inf; gn = Inf;
                if i > 1, gp = posS(i) - posS(i-1); end
                if i < n, gn = posS(i+1) - posS(i); end
                near = min(gp, gn);          % tetangga terdekat
                far  = max(gp, gn);
                if near <= dg && far <= dg
                    % interior zona rapat -> F yakin
                    confS(i) = 1.0;
                elseif near <= dg && far > dg
                    % penambat tepi: kontras = seberapa jauh sisi balok dari ambang
                    ratio = min(1, (far - dg) / max(dg, eps));
                    confS(i) = 0.6 + 0.4 * ratio;   % 0.6..1.0
                else
                    % terisolasi di kedua sisi (jarang) -> ambigu
                    confS(i) = 0.5;
                end
            end
        end


        % ================================================================
        function R = emptyResult()
        %EMPTYRESULT  Template hasil (kosong).
            R = struct( ...
                'labels',    {{}}, ...
                'conf',      [], ...
                'runs',      struct('a',{},'b',{},'n',{},'posLo',{},'posHi',{}), ...
                'denseGap',  NaN, ...
                'baseSpacing', NaN, ...
                'nHW', 0, 'nF', 0, ...
                'summary',   '');
        end

    end
end


% =====================================================================
% Helper lokal
% =====================================================================
function pf = i_fillPos(pos, bad)
%I_FILLPOS  Isi posisi NaN dgn interpolasi linear berdasar indeks (agar urutan
%   tetap monoton); ekstrapolasi tepi memakai spacing tetangga terdekat.
    n = numel(pos);
    idxAll = 1:n;
    good = ~bad;
    if nnz(good) >= 2
        pf = interp1(idxAll(good), pos(good), idxAll(bad), 'linear', 'extrap');
    elseif nnz(good) == 1
        % satu titik valid: geser per indeks (spacing 1)
        gi = find(good, 1);
        pf = pos(gi) + (idxAll(bad) - gi);
    else
        pf = idxAll(bad);
    end
end
