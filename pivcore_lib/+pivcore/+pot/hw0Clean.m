classdef hw0Clean
%HW0CLEAN  Logika "HW-0 Clean" (Step 3v2): fokus kurva di ZONA antara
%   MAX INDENTER (envelope hitam) dan HW-1 (kurva hijau), lalu BERSIHKAN
%   ekor menurun tiap kurva supaya hanya fase NAIK menuju indenter yang
%   tersisa. Kurva yang dibersihkan di-flag HW-0.
%
%   Konsep domain (imbrikasi sesar naik):
%     - MAX INDENTER (hitam) = envelope ATAS semua kurva per frame = batas
%       gerak maksimum (dinding pendorong / indenter).
%     - HW-1 (hijau) = hanging wall pertama, kurva tertinggi KEDUA.
%     - Kurva di ZONA hitam-hijau bergerak NAIK mendekati indenter, lalu pada
%       suatu titik MENURUN menjauh dari indenter (amalgamasi/berbalik). Bagian
%       MENURUN itu "kotor" -> dibuang (di-NaN-kan) supaya tinggal fase naik +
%       puncak (titik terdekat ke indenter).
%
%   Stateless & MURNI: tak menyentuh GUI/handle figure. Input = matriks/array
%   numerik, output = array. Aman dipanggil headless & di test.
%
%   API:
%     env  = pivcore.pot.hw0Clean.indenterEnvelope(M)               % [1xnF] max
%     z    = pivcore.pot.hw0Clean.inZone(series, indenter, opt)     % logical
%     [ys, peakF, cutF] = pivcore.pot.hw0Clean.trimDescending(series, indenter, opt)
%     R    = pivcore.pot.hw0Clean.autoClean(seriesCell, indenter, opt)
%     opt  = pivcore.pot.hw0Clean.defaultOpts()
%
%   Penempatan: PIVTerry/+pivterry/+pot/hw0Clean.m

    methods (Static)

        % ================================================================
        function opt = defaultOpts()
        %DEFAULTOPTS  Parameter aturan auto-clean.
        %   zoneFrac    : kurva "di zona" bila puncaknya >= zoneFrac * puncak
        %                 indenter LOKAL (di frame puncaknya). 0.85 = 85% tinggi
        %                 indenter -> hanya kurva yang benar-benar mendekati
        %                 indenter (zona hitam-hijau) yang masuk.
        %   dropFrac    : ekor dianggap "menurun signifikan" bila jatuh
        %                 dropFrac * range di bawah puncak (histeresis kecil agar
        %                 noise tak memicu pemotongan dini).
        %   minRiseFrac : abaikan kurva yang nyaris datar (range < minRiseFrac *
        %                 puncak indenter global) -> bukan kurva HW yang menanjak.
        %   tolFrac     : toleransi relatif "menyentuh" indenter (thd puncak
        %                 indenter) saat menilai kedekatan ke garis hitam.
            opt = struct( ...
                'zoneFrac',    0.85, ...
                'dropFrac',    0.05, ...
                'minRiseFrac', 0.10, ...
                'tolFrac',     0.02);
        end


        % ================================================================
        function env = indenterEnvelope(seriesCell, nF)
        %INDENTERENVELOPE  Envelope ATAS (max) per frame dari sekumpulan deret.
        %   seriesCell : cell {1xN} tiap sel = [1xnF] deret kurva (boleh NaN).
        %   nF         : panjang frame (opsional; default = deret terpanjang).
        %   env        : [1xnF] nilai maksimum per frame (NaN bila semua NaN).
            env = [];
            if isempty(seriesCell), return; end
            if ~iscell(seriesCell), seriesCell = {seriesCell}; end
            if nargin < 2 || isempty(nF) || ~isfinite(nF)
                nF = 0;
                for k = 1:numel(seriesCell)
                    nF = max(nF, numel(seriesCell{k}));
                end
            end
            if nF < 1, return; end
            M = nan(numel(seriesCell), nF);
            for k = 1:numel(seriesCell)
                v = double(seriesCell{k}(:)).';
                m = min(numel(v), nF);
                if m >= 1, M(k,1:m) = v(1:m); end
            end
            env = max(M, [], 1, 'omitnan');
        end


        % ================================================================
        function tf = inZone(series, indenter, opt)
        %INZONE  True bila `series` masuk ZONA hitam-hijau: puncaknya cukup
        %   dekat ke indenter (>= zoneFrac * indenter di frame puncak) DAN
        %   menanjak berarti (range >= minRiseFrac * puncak indenter).
            if nargin < 3 || isempty(opt), opt = pivcore.pot.hw0Clean.defaultOpts(); end
            tf = false;
            v = double(series(:)).';
            ind = double(indenter(:)).';
            if isempty(v) || isempty(ind), return; end
            n = min(numel(v), numel(ind));
            v = v(1:n); ind = ind(1:n);
            fin = isfinite(v);
            if ~any(fin), return; end
            [pk, pkF] = max(v, [], 'omitnan');
            mn = min(v, [], 'omitnan');
            if ~isfinite(pk) || ~isfinite(mn), return; end
            indScale = max(ind(isfinite(ind)));
            if isempty(indScale) || ~isfinite(indScale) || indScale <= 0, return; end
            % Rise berarti (bukan kurva datar di dasar).
            if (pk - mn) < opt.minRiseFrac * indScale, return; end
            % Puncak cukup dekat indenter LOKAL (di frame puncak).
            localInd = ind(pkF);
            if ~isfinite(localInd) || localInd <= 0
                localInd = indScale;     % fallback puncak indenter global
            end
            tf = pk >= opt.zoneFrac * localInd;
        end


        % ================================================================
        function [ys, peakF, cutF] = trimDescending(series, indenter, opt) %#ok<INUSD>
        %TRIMDESCENDING  Buang EKOR MENURUN kurva: pertahankan fase naik sampai
        %   PUNCAK (titik terdekat ke indenter), lalu NaN-kan setelah frame di
        %   mana kurva mulai MENURUN signifikan dari puncak (menjauh dari
        %   indenter / jatuh di bawah hitam). Non-destruktif (bekerja pd salinan).
        %
        %   Mengembalikan:
        %     ys    : deret terpotong (NaN setelah cutF; sama panjang dgn input)
        %     peakF : frame puncak (terdekat ke indenter); NaN bila tak ada
        %     cutF  : frame TERAKHIR yang dipertahankan; NaN bila tak dipotong
            if nargin < 3 || isempty(opt), opt = pivcore.pot.hw0Clean.defaultOpts(); end
            ys = double(series(:)).'; peakF = NaN; cutF = NaN;
            if isempty(ys), return; end
            v = ys;
            fin = isfinite(v);
            if ~any(fin), return; end
            [pk, pkF] = max(v, [], 'omitnan');
            mn = min(v, [], 'omitnan');
            peakF = pkF;
            rng = pk - mn;
            if ~isfinite(rng) || rng <= 0, return; end   % datar -> tak ada ekor
            % Ekor menurun didefinisikan relatif thd PUNCAK kurva itu sendiri
            % (titik terdekat ke indenter); `indenter` tak diperlukan untuk
            % menentukan potongan -- argumen dipertahankan di signature demi
            % simetri API (dipakai di inZone/autoClean), sengaja tak direferensi.
            dropAbs = opt.dropFrac * rng;     % histeresis dlm satuan kurva
            % Cari frame PERTAMA SETELAH puncak yang turun >= dropAbs di bawah
            % puncak (mulai menurun menjauh dari indenter). Itu awal "ekor kotor".
            cut = numel(v);                   % default: tak ada ekor (simpan semua)
            for f = pkF+1:numel(v)
                if ~isfinite(v(f)), continue; end
                if v(f) <= pk - dropAbs
                    cut = f - 1;              % pertahankan sampai sebelum drop
                    break;
                end
            end
            cut = max(cut, pkF);              % minimal pertahankan sampai puncak
            if cut < numel(v)
                ys(cut+1:end) = NaN;
                cutF = cut;
            end
        end


        % ================================================================
        function R = autoClean(seriesCell, indenter, opt)
        %AUTOCLEAN  Jalankan deteksi-zona + trim-ekor untuk SEMUA kurva.
        %   seriesCell : cell {1xN}, tiap sel = [1xnF] deret kurva.
        %   indenter   : [1xnF] envelope max (bila kosong -> dihitung dari kurva).
        %   opt        : parameter (defaultOpts bila kosong).
        %
        %   R (struct):
        %     .inZone   : 1xN logical, kurva masuk zona hitam-hijau
        %     .cleaned  : cell {1xN}, deret terpotong (= input bila tak di-zona)
        %     .peakF    : 1xN frame puncak (NaN bila tak relevan)
        %     .cutF     : 1xN frame potong (NaN bila tak dipotong)
        %     .nZone    : jumlah kurva di zona
        %     .nCut     : jumlah kurva yang ekornya benar-benar dipotong
        %     .indenter : envelope yang dipakai
            if nargin < 3 || isempty(opt), opt = pivcore.pot.hw0Clean.defaultOpts(); end
            if ~iscell(seriesCell), seriesCell = {seriesCell}; end
            N = numel(seriesCell);
            R = struct('inZone',false(1,N),'cleaned',{cell(1,N)}, ...
                'peakF',nan(1,N),'cutF',nan(1,N),'nZone',0,'nCut',0,'indenter',[]);
            if N == 0, return; end
            if nargin < 2 || isempty(indenter)
                indenter = pivcore.pot.hw0Clean.indenterEnvelope(seriesCell);
            end
            R.indenter = indenter;
            for k = 1:N
                v = double(seriesCell{k}(:)).';
                R.cleaned{k} = v;                       % default: tak diubah
                if ~pivcore.pot.hw0Clean.inZone(v, indenter, opt), continue; end
                R.inZone(k) = true;
                [ys, pkF, cutF] = pivcore.pot.hw0Clean.trimDescending(v, indenter, opt);
                R.cleaned{k} = ys;
                R.peakF(k)   = pkF;
                R.cutF(k)    = cutF;
                if isfinite(cutF), R.nCut = R.nCut + 1; end
            end
            R.nZone = nnz(R.inZone);
        end


        % ================================================================
        function [ys, cutF] = trimManual(series, indenter, opt)
        %TRIMMANUAL  Versi MANUAL: pengguna memilih kurva, kita TETAP buang ekor
        %   menurunnya (sama trimDescending) TANPA cek zona (kurva dipilih
        %   manual, jadi keputusan "ini HW-0" ada di tangan pengguna).
            if nargin < 3 || isempty(opt), opt = pivcore.pot.hw0Clean.defaultOpts(); end
            if nargin < 2, indenter = []; end
            [ys, ~, cutF] = pivcore.pot.hw0Clean.trimDescending(series, indenter, opt);
        end


        % ================================================================
        function [ys, dieF] = cutAtIndenter(series, indenter, opt)
        %CUTATINDENTER  Potong `series` di FRAME PERTAMA yang MENYENTUH
        %   `indenter` (envelope MAX) SETELAH kurva benar-benar menanjak ke
        %   dinding — bukan di pangkal yang masih nyaris-nol. Mengembalikan deret
        %   terpotong (NaN setelah dieF) + frame "kematian" dieF (NaN bila tak
        %   pernah menyentuh). Non-destruktif (bekerja pada salinan).
        %
        %   Dipakai untuk "trim kurva ke max indenter": kurva hanging wall yang
        %   menanjak hingga MENYENTUH dinding pendorong (indenter) lalu ber-
        %   amalgamasi -> nilai SETELAH titik sentuh dibuang. Beda dgn
        %   trimDescending (yg memakai puncak kurva itu sendiri), di sini acuan
        %   potong adalah garis indenter eksternal.
        %
        %   opt (semua opsional, additive — pemanggil lama 2-arg pakai default):
        %     .minHeightFrac : GERBANG tinggi. Sentuhan hanya dihitung di frame yg
        %                      nilai kurvanya >= minHeightFrac * puncak indenter.
        %                      Mencegah "sentuhan palsu" di frame-frame awal saat
        %                      SEMUA kurva masih bertumpuk dekat nol (indenter pun
        %                      masih ~0) — penyebab dulu memotong di frame 1 hingga
        %                      kurva "hilang semua". Default 0.7.
        %     .tolFrac       : toleransi "menyentuh" relatif thd puncak indenter
        %                      (robust thd noise). Default 0.01 (=1%).
        %     .minHold       : butuh sentuhan BERTAHAN sebanyak ini frame
        %                      berturut-turut sebelum memotong (anti-noise).
        %                      Default 1 (=sentuhan tunggal, perilaku lama).
            ys = double(series(:)).'; dieF = NaN;
            if isempty(ys) || isempty(indenter), return; end
            % --- baca opsi (default = perilaku robust baru) -----------------
            minHeightFrac = 0.7; tolFrac = 0.01; minHold = 1;
            if nargin >= 3 && isstruct(opt)
                if isfield(opt,'minHeightFrac') && isscalar(opt.minHeightFrac) && isfinite(opt.minHeightFrac)
                    minHeightFrac = double(opt.minHeightFrac);
                end
                if isfield(opt,'tolFrac') && isscalar(opt.tolFrac) && isfinite(opt.tolFrac)
                    tolFrac = double(opt.tolFrac);
                end
                if isfield(opt,'minHold') && isscalar(opt.minHold) && isfinite(opt.minHold)
                    minHold = double(opt.minHold);
                end
            end
            minHold = max(1, round(minHold));
            ind = double(indenter(:)).';
            n = min(numel(ys), numel(ind));
            if n < 1, return; end
            yy = ys(1:n); ii = ind(1:n);
            % Skala = puncak indenter (acuan toleransi & gerbang tinggi).
            sc = max(ii(isfinite(ii)));
            if isempty(sc) || ~isfinite(sc) || sc <= 0, sc = 1; end
            tol  = max(tolFrac, 0) * sc;                  % ambang "menyentuh"
            gate = min(max(minHeightFrac, 0), 1) * sc;    % ambang tinggi minimum
            % Frame "menyentuh indenter": dekat garis hitam DAN kurva sudah naik
            % melewati gerbang tinggi (bukan di kerumunan pangkal nyaris-nol).
            hitMask = isfinite(yy) & isfinite(ii) & (yy >= ii - tol) & (yy >= gate);
            % Awal RUN pertama sepanjang minHold sentuhan berturut-turut.
            run = 0; k = [];
            for f = 1:n
                if hitMask(f)
                    run = run + 1;
                    if run >= minHold, k = f - minHold + 1; break; end
                else
                    run = 0;
                end
            end
            if isempty(k), return; end       % tak pernah menyentuh di atas gerbang
            dieF = k;
            ys(k+1:end) = NaN;               % nilai setelah titik mati dibuang
        end

    end
end
