classdef autoAggregate
%AUTOAGGREGATE  Pengelompokan OTOMATIS & DETERMINISTIK kurva POT-PSG4 menjadi
%   "Kurva Sesar" (fault zones) berdasarkan PROFIL INTEGRAL (luas area) tiap
%   kurva sepanjang garis PSG.
%
%   METODE (sharp-break / monotone-run, deterministik -- BUKAN median-gap):
%   Profil area sebuah eksperimen thrust-fault landai-menurun (creep butiran
%   intra-sesar) diselingi LANGKAH TURUN TAJAM (bidang sesar = diskontinuitas
%   medan kecepatan). Batas grup ditempatkan di langkah i HANYA bila langkah
%   itu SEKALIGUS:
%     (a) TURUN          : profil menurun di bidang sesar (dA < 0);
%     (b) MAKSIMUM LOKAL : |dA(i)| mendominasi tetangga +/-W (break asli,
%                          bukan bagian lereng mulus);
%     (c) CURAM vs CREEP : |dA(i)| >= K x langkah-creep LOKAL (median |dA|
%                          atas L kurva sebelumnya) -- uji utama;
%     (d) DI ATAS JITTER : |dA(i)| >= F x area(i) -- offset pecahan nyata,
%                          bukan riak kuantisasi PIV sub-piksel.
%   Lalu pass-2 deterministik menggabung grup < MINSZ kurva ke tetangga yg
%   mean-area-nya terdekat.
%
%   Konstanta UTAMA: K=4.0 (rasio drop-sesar terhadap creep LOKAL). K adalah
%   rasio terhadap baseline LOKAL, BUKAN median/persentil GLOBAL dataset, jadi
%   portabel lintas-eksperimen & lintas-amplitudo (skala area boleh apa saja).
%   K=4.0 -> ~11 grup yang koheren-geologis pada P-CON-D-1-OK; K lebih kecil =
%   lebih banyak grup (lebih sensitif). F/W/L/MINSZ = gerbang sekunder tetap.
%
%   Dipakai oleh modul Step 3 (tabStep3). Murni perhitungan -- tanpa GUI.
%
%   Asal metode: workflow desain multi-agent (4 usulan -> 3 juri -> sintesis),
%   konsensus 3/3 juri + verifikasi numerik di MATLAB R2025b (boundaries pada
%   P-CON-D-1-OK = [199 300 316 371 433 441 449 511 519 527 535]).
%
%   API:
%     [faultOf, info] = pivcore.pot.autoAggregate.groupByAreaJump(M, nF, opts)
%        M       : model potpsg4 (pivcore.pot.potpsg4Model.ensure)
%        nF      : jumlah frame
%        opts    : struct opsional .kFactor (default 4.0) -> override K.
%                  (.minGroup -> override MINSZ, default 4)
%        faultOf : 1 x numel(M.records), nomor sesar tiap record (1..G).
%        info    : struct(nGroups, sizes, K, boundaries)
%     [labels, boundaries] = pivcore.pot.autoAggregate.faultCurves(area, opts)
%        Inti deterministik atas vektor area (urutan posisi). Bisa diuji
%        mandiri tanpa model.
%
%   Penempatan: PIVTerry/+pivterry/+pot/autoAggregate.m

    methods (Static)

        function [faultOf, info] = groupByAreaJump(M, nF, opts)
            if nargin < 3 || ~isstruct(opts), opts = struct(); end

            nR = numel(M.records);
            faultOf = zeros(1, nR);
            info = struct('nGroups',0,'sizes',[],'K',i_getf(opts,'kFactor',4.0), ...
                          'boundaries',[]);
            if nR == 0, return; end

            % --- Urutkan record menurut posisi sepanjang garis (posPx) ---
            pos = nan(1, nR);
            for r = 1:nR
                p = M.records(r).posPx;
                if isscalar(p) && isfinite(p), pos(r) = p; else, pos(r) = r; end
            end
            [~, ord] = sort(pos, 'ascend');     % indeks record terurut posisi

            % --- Area (integral) tiap kurva pada urutan posisi ---
            areaPos = nan(1, nR);
            for j = 1:nR
                r   = ord(j);
                rec = pivcore.pot.potpsg4Model.normalizeRecord(M.records(r));
                if M.cutOn
                    yd = pivcore.pot.potpsg4Model.cutData(M, r, nF);
                else
                    yd = rec.data(:).';
                end
                g = isfinite(yd);
                if any(g), areaPos(j) = trapz(find(g), yd(g)); else, areaPos(j) = 0; end
            end

            % --- Deteksi sesar deterministik atas profil area ---
            [labels, bnd] = pivcore.pot.autoAggregate.faultCurves(areaPos, opts);

            % --- Petakan label (urutan posisi) -> record asli ---
            faultOf(ord) = labels;

            % Ukuran tiap grup (urutan posisi).
            G = max(labels);
            sizes = zeros(1, G);
            for g = 1:G, sizes(g) = sum(labels == g); end

            info.nGroups    = G;
            info.sizes      = sizes;
            info.boundaries = bnd;     % indeks LOKAL (urutan posisi) awal grup
        end


        % ================================================================
        function [labels, boundaries] = faultCurves(area, opts)
        %FAULTCURVES  Inti deterministik: vektor area (urutan posisi) ->
        %   label grup per kurva + indeks awal tiap grup. Lihat header kelas.
            if nargin < 2 || ~isstruct(opts), opts = struct(); end
            area = area(:).';
            N = numel(area);
            labels = ones(1, N);
            boundaries = 1;
            if N < 2, return; end

            % ---- Konstanta fisik tetap (tak diturunkan dari dataset) ----
            K     = i_getf(opts, 'kFactor',  4.0);  % drop sesar >= K x creep LOKAL
            F     = i_getf(opts, 'fracMin',  0.02); % offset >= 2% level lokal
            W     = i_getf(opts, 'winLocal', 3);    % half-window maksimum lokal
            L     = i_getf(opts, 'baseLen',  8);    % panjang baseline creep
            MINSZ = i_getf(opts, 'minGroup', 4);    % min kurva/zona (pass-2)

            dA = [0, diff(area)];
            m  = abs(dA);

            % ---- PASS 1: detektor break konstanta-tetap (scan maju) ----
            g = 1; labels(1) = 1;
            for i = 2:N
                isDrop = dA(i) < 0;
                fracOK = m(i) >= F * area(i);

                lo = max(2, i - W);  hi = min(N, i + W);
                localMax = all(m(i) >= m(lo:i-1)) && all(m(i) > m(i+1:hi)); % kiri-menang saat seri

                base    = max(median(m(max(2, i-L):i-1)), 1.0);  % lereng creep lokal
                ratioOK = m(i) >= K * base;

                if isDrop && fracOK && localMax && ratioOK
                    g = g + 1;          % buka zona sesar baru
                end
                labels(i) = g;
            end

            % ---- PASS 2: gabung zona < MINSZ ke tetangga mean-terdekat ----
            labels = pivcore.pot.autoAggregate.mergeSmall(labels, area, MINSZ);

            boundaries = find([true, diff(labels) ~= 0]);   % indeks awal tiap grup
        end


        % ================================================================
        function labels = mergeSmall(labels, area, MINSZ)
        %MERGESMALL  Gabung berulang grup < MINSZ kurva ke grup tetangga yg
        %   mean-area-nya terdekat (urutan iterasi tetap -> deterministik).
            changed = true;
            while changed
                changed = false;
                edges = [find([true, diff(labels) ~= 0]), numel(labels)+1];
                nG = numel(edges) - 1;
                if nG <= 1, break; end
                for k = 1:nG
                    a = edges(k); b = edges(k+1) - 1;
                    if (b - a + 1) < MINSZ
                        gmean = mean(area(a:b));
                        tgt = ''; bestD = inf;
                        if k > 1
                            d = abs(mean(area(edges(k-1):edges(k)-1)) - gmean);
                            if d < bestD, bestD = d; tgt = 'prev'; end
                        end
                        if k < nG
                            d = abs(mean(area(edges(k+1):edges(k+2)-1)) - gmean);
                            if d < bestD, tgt = 'next'; end
                        end
                        if strcmp(tgt, 'prev')
                            labels(a:b) = labels(a-1);
                        elseif strcmp(tgt, 'next')
                            labels(a:b) = labels(b+1);
                        end
                        [~, ~, labels] = unique(labels, 'stable');
                        labels = labels(:).';
                        changed = true;
                        break;
                    end
                end
            end
            [~, ~, labels] = unique(labels, 'stable');
            labels = labels(:).';
        end

    end
end


% =====================================================================
function v = i_getf(S, name, default)
    if isstruct(S) && isfield(S, name) && ~isempty(S.(name)) ...
            && isscalar(S.(name)) && isfinite(S.(name))
        v = S.(name);
    else
        v = default;
    end
end
