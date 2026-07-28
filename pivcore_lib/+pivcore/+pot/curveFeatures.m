classdef curveFeatures
%CURVEFEATURES  Ekstraksi fitur kuantitatif dari kurva POT (deret-waktu titik
%   sampling) dan dari GRUP kurva yang di-assign pengguna ke satu label
%   (HW-#/F-#/F0). Fitur ini MEREKAM cara pengguna mengidentifikasi sebuah
%   agregat secara manual, agar nanti bisa dipelajari (model menyusul).
%
%   Stateless: tak menyentuh GUI/handle figure. Semua fungsi murni
%   (input -> output), aman dipanggil headless & di test.
%
%   Konsep domain (imbrikasi sesar naik):
%     - Hanging Wall (HW) = bagian bergerak -> kurva yang NAIK.
%     - Fault (F) = bidang diskontinuitas akibat gerak HW.
%     - AWAL kurva diidentifikasi pengguna di sekitar MINIMUM, AKHIR di sekitar
%       MAKSIMUM (kurva menanjak dari diam menuju pergerakan penuh). Karena itu
%       startF = argmin, endF = argmax adalah penanda dasar.
%     - F0 (sesar pertama) dibedakan lewat LOMPATAN INTEGRAL antar grup kurva
%       berurutan -> fitur grup menyimpan integralGapPrev/Next.
%
%   API:
%     f = pivcore.pot.curveFeatures.featCurve(data, posPx)
%     g = pivcore.pot.curveFeatures.featGroup(records, curveIdx)
%     [sf,ef] = pivcore.pot.curveFeatures.startEndFrames(data)
%
%   Penempatan: PIVTerry/+pivterry/+pot/curveFeatures.m

    methods (Static)

        % ================================================================
        function f = featCurve(data, posPx)
        %FEATCURVE  Fitur satu kurva POT (vektor nilai per frame).
        %   data  : [1xnF] deret-waktu (velocity_magnitude di titik sampling)
        %   posPx : posisi (px) titik sepanjang garis swath (opsional)
        %
        %   Mengembalikan struct fitur (semua skalar; NaN bila tak terdefinisi).
            if nargin < 2, posPx = NaN; end
            f = pivcore.pot.curveFeatures.emptyCurveFeat();
            if isempty(data), return; end
            v = double(data(:)).';            % baris
            v = v(isfinite(v) | true);        % pertahankan panjang; NaN ditangani di bawah
            nF = numel(v);
            f.nF    = nF;
            f.posPx = double(posPx);

            finiteMask = isfinite(v);
            if ~any(finiteMask), return; end
            vv = v; vv(~finiteMask) = NaN;

            [minVal, minF] = min(vv, [], 'omitnan');
            [maxVal, maxF] = max(vv, [], 'omitnan');
            f.minVal = minVal;  f.maxVal = maxVal;
            f.minF   = minF;    f.maxF   = maxF;
            f.range  = maxVal - minVal;
            f.peakFrame = maxF;

            % AWAL/AKHIR (penanda identifikasi pengguna): start=min, end=max.
            [f.startF, f.endF] = pivcore.pot.curveFeatures.startEndFrames(vv);

            % Integral (luas di bawah kurva) -> dipakai untuk pengelompokan
            % & deteksi F0 lewat lompatan integral antar kurva.
            idx = find(finiteMask);
            if numel(idx) >= 2
                f.integral = trapz(idx, vv(idx));
            else
                f.integral = 0;
            end

            % Slope rata-rata (kemiringan tren global) via polyfit deg-1.
            if numel(idx) >= 2
                p = polyfit(idx, vv(idx), 1);
                f.meanSlope = p(1);
            else
                f.meanSlope = NaN;
            end

            % Fraksi frame yang menaik (kurva HW didominasi kenaikan).
            d = diff(vv(idx));
            if ~isempty(d)
                f.riseFrac = sum(d > 0) / numel(d);
            else
                f.riseFrac = NaN;
            end

            % Bentuk kenaikan: frame saat kurva mencapai 10% & 90% dari range
            % (relatif minVal). t90-t10 = "ketajaman" transisi naik.
            if f.range > 0
                lvl10 = minVal + 0.10 * f.range;
                lvl90 = minVal + 0.90 * f.range;
                f.t10 = pivcore.pot.curveFeatures.firstCrossFrame(vv, idx, lvl10);
                f.t90 = pivcore.pot.curveFeatures.firstCrossFrame(vv, idx, lvl90);
                if isfinite(f.t10) && isfinite(f.t90)
                    f.riseSpan = f.t90 - f.t10;
                end
            end
        end


        % ================================================================
        function g = featGroup(records, curveIdx)
        %FEATGROUP  Fitur ringkasan satu GRUP kurva (agregat label HW-#/F-#).
        %   records : struct-array record POT-PSG4 (punya .data, .posPx)
        %   curveIdx: indeks baris records yg masuk grup ini
        %
        %   Termasuk lompatan integral terhadap grup tetangga (urut posPx) yang
        %   diisi BELAKANGAN oleh pemanggil (fillGroupGaps) karena perlu konteks
        %   antar-grup; di sini integralGapPrev/Next dibiarkan NaN.
            g = pivcore.pot.curveFeatures.emptyGroupFeat();
            curveIdx = curveIdx(:).';
            curveIdx = curveIdx(curveIdx >= 1 & curveIdx <= numel(records));
            g.nCurves = numel(curveIdx);
            if g.nCurves == 0, return; end

            integrals = nan(1, g.nCurves);
            posPxs    = nan(1, g.nCurves);
            startFs   = nan(1, g.nCurves);
            endFs     = nan(1, g.nCurves);
            for k = 1:g.nCurves
                r = records(curveIdx(k));
                pos = NaN;
                if isfield(r,'posPx'), pos = r.posPx; end
                cf = pivcore.pot.curveFeatures.featCurve(r.data, pos);
                integrals(k) = cf.integral;
                posPxs(k)    = cf.posPx;
                startFs(k)   = cf.startF;
                endFs(k)     = cf.endF;
            end

            g.integralTotal = sum(integrals, 'omitnan');
            g.integralMean  = mean(integrals, 'omitnan');
            g.posPxMin = min(posPxs, [], 'omitnan');
            g.posPxMax = max(posPxs, [], 'omitnan');
            if isfinite(g.posPxMin) && isfinite(g.posPxMax)
                g.posPxSpan = g.posPxMax - g.posPxMin;
            end
            g.startF = median(startFs, 'omitnan');
            g.endF   = median(endFs, 'omitnan');
        end


        % ================================================================
        function assign = fillGroupGaps(assign)
        %FILLGROUPGAPS  Isi integralGapPrev/Next pada feat tiap grup, setelah
        %   semua grup diurutkan berdasarkan posisi (posPxMin). Lompatan
        %   integral antar grup berurutan = sinyal yang dipakai pengguna untuk
        %   memisahkan F0 dari F1+ (perubahan drastis = batas).
            if isempty(assign), return; end
            n = numel(assign);
            % Urutkan grup berdasar posPxMin (NaN ke belakang).
            key = nan(1, n);
            for i = 1:n
                if isfield(assign(i),'feat') && isfield(assign(i).feat,'posPxMin')
                    key(i) = assign(i).feat.posPxMin;
                end
            end
            [~, ord] = sort(key);
            for j = 1:numel(ord)
                i = ord(j);
                if ~isfield(assign(i),'feat') || ~isstruct(assign(i).feat)
                    continue;
                end
                assign(i).feat.integralGapPrev = NaN;
                assign(i).feat.integralGapNext = NaN;
                if j > 1
                    ip = ord(j-1);
                    assign(i).feat.integralGapPrev = ...
                        assign(i).feat.integralMean - assign(ip).feat.integralMean;
                end
                if j < numel(ord)
                    inx = ord(j+1);
                    assign(i).feat.integralGapNext = ...
                        assign(inx).feat.integralMean - assign(i).feat.integralMean;
                end
            end
        end


        % ================================================================
        function [sf, ef] = startEndFrames(data)
        %STARTENDFRAMES  Penanda AWAL (argmin) & AKHIR (argmax) kurva. Sesuai
        %   cara pengguna menandai: cari minimum & maksimum kurva.
            sf = NaN; ef = NaN;
            if isempty(data), return; end
            v = double(data(:)).';
            if ~any(isfinite(v)), return; end
            [~, sf] = min(v, [], 'omitnan');
            [~, ef] = max(v, [], 'omitnan');
        end


        % ================================================================
        function fr = firstCrossFrame(v, idx, level)
        %FIRSTCROSSFRAME  Frame pertama (di antara idx) saat v mencapai/melewati
        %   `level` ke atas. NaN bila tak pernah.
            fr = NaN;
            for k = 1:numel(idx)
                if v(idx(k)) >= level
                    fr = idx(k);
                    return;
                end
            end
        end


        % ================================================================
        function f = emptyCurveFeat()
        %EMPTYCURVEFEAT  Template fitur per-kurva (semua NaN).
            f = struct('nF',0,'minF',NaN,'maxF',NaN,'minVal',NaN,'maxVal',NaN, ...
                'range',NaN,'integral',NaN,'meanSlope',NaN,'riseFrac',NaN, ...
                'posPx',NaN,'peakFrame',NaN,'startF',NaN,'endF',NaN, ...
                't10',NaN,'t90',NaN,'riseSpan',NaN);
        end


        % ================================================================
        function g = emptyGroupFeat()
        %EMPTYGROUPFEAT  Template fitur per-grup (semua NaN/0).
            g = struct('nCurves',0,'posPxMin',NaN,'posPxMax',NaN,'posPxSpan',NaN, ...
                'integralTotal',0,'integralMean',NaN,'startF',NaN,'endF',NaN, ...
                'integralGapPrev',NaN,'integralGapNext',NaN);
        end

    end
end
