classdef netslip
%NETSLIP  Net-slip sesar dari kurva POT — fungsi MURNI (headless). RE-
%   IMPLEMENTASI CLEAN-ROOM dari pola PIVTerry tabStep4 (dibaca read-only;
%   TIDAK dipanggil lintas-folder). Divalidasi terhadap ANGKA GOLDEN sintetik
%   (test_pab4_engines), BUKAN diff terhadap tabStep4.
%
%   DEFINISI (PAB4_PLAN §3b):
%     repVec      kurva representatif satu HW = rata-rata per-frame kurva-kurva
%                 anggota HW itu (omitnan). Satu kurva -> kurva itu sendiri.
%     netslipVec  net-slip(frame) = repA(frame) - repB(frame), dgn:
%                   repA = HWₙ; repB = HWₙ₊₁ (sesar berikutnya), ATAU
%                   repB = FFW bila HWₙ = sesar terakhir.
%     area        integral net-slip frame Start..END (trapz, BERTANDA).
%     dNet        ns(END) - ns(Start)  (selisih net pada batas titik).
%
%   KONVENSI TANDA: net-slip & turunannya BERTANDA secara alami (pengurangan +
%   trapz). Untuk mode 'absolute' (cermin toggle drift ABSOLUT) -> abs(ns)
%   sebelum area/dNet (applySign). 'signed' = apa adanya.
%
%   API:
%     y  = pivcore.pot.netslip.repVec(curves, nF)     % curves: cell vektor | matriks MxN
%     ns = pivcore.pot.netslip.netslipVec(repA, repB)
%     a  = pivcore.pot.netslip.area(ns, f0, f1)
%     d  = pivcore.pot.netslip.dNet(ns, f0, f1)
%     ns = pivcore.pot.netslip.applySign(ns, conv)    % 'signed'|'absolute'
%     R  = pivcore.pot.netslip.compute(repA, repB, pt [, conv])  % struct rangkum
%
%   Penempatan berkas: PAB/pivcore_lib/+pivcore/+pot/netslip.m

    methods (Static)

        % ================================================================
        function y = repVec(curves, nF)
        %REPVEC  Kurva representatif (1 x nF) = rata-rata per-frame (omitnan).
        %   `curves` = cell vektor-baris ATAU matriks MxN (M kurva). Frame yang
        %   SEMUA anggotanya non-finite -> NaN.
            if nargin < 2 || isempty(nF) || ~isfinite(nF) || nF < 1
                nF = pivcore.pot.netslip.guessLen(curves);
            end
            nF = round(nF);
            Y = pivcore.pot.netslip.stack(curves, nF);
            if isempty(Y), y = nan(1, nF); return; end
            y = mean(Y, 1, 'omitnan');
            y(all(~isfinite(Y), 1)) = NaN;
            y = y(:).';
        end


        % ================================================================
        function ns = netslipVec(repA, repB)
        %NETSLIPVEC  repA - repB (selaras ke panjang minimum; NaN merambat).
            a = repA(:).'; b = repB(:).';
            m = min(numel(a), numel(b));
            if m == 0, ns = []; return; end
            ns = a(1:m) - b(1:m);
        end


        % ================================================================
        function a = area(ns, f0, f1)
        %AREA  Integral trapz net-slip pada frame f0..f1 (BERTANDA). NaN bila
        %   <2 titik berhingga / batas tak valid. Urutan f0,f1 tak penting.
            a = NaN;
            if ~(isscalar(f0) && isfinite(f0) && isscalar(f1) && isfinite(f1)), return; end
            f0 = round(f0); f1 = round(f1);
            if f1 < f0, t = f0; f0 = f1; f1 = t; end
            idx = f0:f1;
            idx = idx(idx >= 1 & idx <= numel(ns));
            if numel(idx) < 2, return; end
            vv = ns(idx); g = isfinite(vv);
            if nnz(g) < 2, return; end
            a = trapz(idx(g), vv(g));
        end


        % ================================================================
        function d = dNet(ns, f0, f1)
        %DNET  ns(f1) - ns(f0) — selisih net pada batas (END - Start). URUTAN
        %   DIPERTAHANKAN (tanda bermakna). NaN bila batas/nilai tak valid.
            d = NaN;
            if ~(isscalar(f0) && isfinite(f0) && isscalar(f1) && isfinite(f1)), return; end
            f0 = round(f0); f1 = round(f1); n = numel(ns);
            if f0 < 1 || f0 > n || f1 < 1 || f1 > n, return; end
            if ~isfinite(ns(f0)) || ~isfinite(ns(f1)), return; end
            d = ns(f1) - ns(f0);
        end


        % ================================================================
        function ns = applySign(ns, conv)
        %APPLYSIGN  Terapkan konvensi tanda: 'absolute' -> abs(ns); selain itu
        %   apa adanya.
            if nargin >= 2 && ischar(conv) && strcmpi(conv, 'absolute')
                ns = abs(ns);
            end
        end


        % ================================================================
        function R = compute(repA, repB, pt, conv)
        %COMPUTE  Rangkum net-slip satu HW dari dua kurva representatif + titik
        %   Start/NUC/FSR/END (struct snapPoints). Mengembalikan struct:
        %     .values .area .dNet .start .nuc .fsr .end .convention
            if nargin < 4, conv = 'signed'; end
            ns = pivcore.pot.netslip.netslipVec(repA, repB);
            ns = pivcore.pot.netslip.applySign(ns, conv);
            s = NaN; nu = NaN; fr = NaN; en = NaN;
            if isstruct(pt)
                if isfield(pt,'startF'), s  = pivcore.pot.netslip.sc(pt.startF); end
                if isfield(pt,'nclF'),   nu = pivcore.pot.netslip.sc(pt.nclF);   end
                if isfield(pt,'fsrF'),   fr = pivcore.pot.netslip.sc(pt.fsrF);   end
                if isfield(pt,'endF'),   en = pivcore.pot.netslip.sc(pt.endF);   end
            end
            R = struct();
            R.values     = ns;
            R.start      = s; R.nuc = nu; R.fsr = fr; R.end = en;
            R.area       = pivcore.pot.netslip.area(ns, s, en);
            R.dNet       = pivcore.pot.netslip.dNet(ns, s, en);
            R.convention = conv;
        end

    end


    methods (Static, Access = private)

        function Y = stack(curves, nF)
        %STACK  Bangun matriks MxnF dari cell/matriks (potong/pad ke nF).
            Y = [];
            if iscell(curves)
                M = numel(curves);
                Y = nan(M, nF);
                for j = 1:M
                    v = curves{j}(:).';
                    m = min(numel(v), nF);
                    if m >= 1, Y(j, 1:m) = v(1:m); end
                end
            elseif isnumeric(curves) && ~isempty(curves)
                Y = double(curves);
                if isvector(Y), Y = Y(:).'; end
                c = size(Y, 2);
                if c > nF, Y = Y(:, 1:nF);
                elseif c < nF, Y(:, c+1:nF) = NaN; end
            end
        end

        function nF = guessLen(curves)
            nF = 1;
            if iscell(curves)
                for j = 1:numel(curves), nF = max(nF, numel(curves{j})); end
            elseif isnumeric(curves) && ~isempty(curves)
                if isvector(curves), nF = numel(curves); else, nF = size(curves,2); end
            end
        end

        function v = sc(x)
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end

    end
end
