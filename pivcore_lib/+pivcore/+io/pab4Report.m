classdef pab4Report
%PAB4REPORT  Helper MURNI/HEADLESS untuk fitur "📄 Report PDF" PAB4.
%   Merakit 1 file PDF landscape per-eksperimen (Group A–E) sebagai bahan
%   menulis report ilmiah. Engine ini menyediakan fungsi DATA-ONLY (mudah
%   di-test tanpa membuka figure); logika render/PDF ada di PAB4.m.
%
%   TATA LETAK folder sesi (konsisten pola pab4DescExport):
%     <pabRoot>/PAB4_DESC/<exp>/<ddmmyy-HHMMSS>_<psg>_report/
%        report.pdf                              PDF akhir (landscape)
%        report.json                             sidecar meta (dt, group, dsb)
%        _img/                                   gambar antara (JPG ≤700KB)
%
%   API:
%     d     = pivcore.io.pab4Report.reportDir(pabRoot, dataFile, ts, psgName)
%     imgD  = pivcore.io.pab4Report.imgDir(reportDir)
%     pdf   = pivcore.io.pab4Report.pdfPath(reportDir)
%     jp    = pivcore.io.pab4Report.jsonPath(reportDir)
%     pairs = pivcore.io.pab4Report.fsMaxPairs(rows, fNum)   % [a b; c d]
%     est   = pivcore.io.pab4Report.estNetSlip(ns, pairs, velMult, dtSec)
%     dt    = pivcore.io.pab4Report.readDtMean(dataFile)
%     nm    = pivcore.io.pab4Report.safeName(s)
%     pivcore.io.pab4Report.writeJsonAtomic(p, obj)
%
%   Penempatan: PAB/pivcore_lib/+pivcore/+io/pab4Report.m

    methods (Static)

        % ================================================================
        %                          PATH / FOLDER
        % ================================================================
        function d = reportDir(pabRoot, dataFile, ts, psgName)
        %REPORTDIR  <pabRoot>/PAB4_DESC/<exp>/<ts>_<psg>_report/ (ber-versi).
            if nargin < 3 || isempty(ts), ts = pivcore.io.pab4DescExport.stamp(); end
            if nargin < 4, psgName = ''; end
            pn = pivcore.io.pab4Report.safeName(psgName);
            if isempty(pn), pn = 'PSG'; end
            expDir = pivcore.io.pab4DescExport.expDir(pabRoot, dataFile);
            d = fullfile(expDir, sprintf('%s_%s_report', ...
                pivcore.io.pab4Report.safeName(ts), pn));
        end

        function d = imgDir(reportDir)
        %IMGDIR  Subfolder gambar antara.
            d = fullfile(char(reportDir), '_img');
        end

        function p = pdfPath(reportDir)
            p = fullfile(char(reportDir), 'report.pdf');
        end

        function p = jsonPath(reportDir)
            p = fullfile(char(reportDir), 'report.json');
        end


        % ================================================================
        %                    ANGKA MURNI (di-test golden)
        % ================================================================
        function pairs = fsMaxPairs(rows, fNum)
        %FSMAXPAIRS  Frame baris DESC ber-POI 'ACT-FSR' untuk F# = fNum ('F3'/'3'),
        %   di-SORT menaik + di-PASANGKAN 2-2 -> matriks Nx2 [a b; c d; ...].
        %   Sisa ganjil di akhir DIABAIKAN. F# tanpa FS-max -> [] (0x2).
            pairs = zeros(0,2);
            tgt = pivcore.io.pab4Report.normFtag(fNum);
            fr = [];
            for k = 1:numel(rows)
                r = rows{k};
                if ~isstruct(r), continue; end
                p = ''; if isfield(r,'poi'), p = strtrim(char(r.poi)); end
                if ~strcmpi(p, 'ACT-FSR'), continue; end
                if ~isempty(tgt)
                    ft = ''; if isfield(r,'fNum'), ft = pivcore.io.pab4Report.normFtag(r.fNum); end
                    if ~strcmp(ft, tgt), continue; end
                end
                v = NaN; if isfield(r,'frame'), v = r.frame; end
                if isscalar(v) && isfinite(v), fr(end+1) = round(v); end %#ok<AGROW>
            end
            fr = sort(unique(fr));
            n2 = floor(numel(fr)/2);
            for i = 1:n2
                pairs(i,:) = [fr(2*i-1) fr(2*i)];
            end
        end

        function est = estNetSlip(ns, pairs, velMult, dtSec)
        %ESTNETSLIP  Estimasi net-slip terakumulasi (cm) sebuah sesar:
        %     est = Σ_pasangan Σ_{k=a..b} ns[k] * velMult * dtSec
        %   dgn `velMult` = cm/s per (px/frame) — GUNAKAN velMultGeom (kalibrasi
        %   geometri indenter), bukan konstanta. Analisis dimensi:
        %     ns[px/frame] * velMult[cm/s per px/frame] = cm/s ;
        %     * dtSec[s/frame], dijumlah tiap frame (Σ = ∫ diskret) -> cm.
        %   ns = vektor net-slip px/frame; pairs = Nx2 rentang FS-max→FS-max
        %   (frame). Nilai NaN di ns dilewati. pairs kosong -> NaN (tak dihitung).
            est = NaN;
            if isempty(pairs), return; end
            if nargin < 3 || isempty(velMult) || ~isfinite(velMult), velMult = 0.005; end
            if nargin < 4 || isempty(dtSec) || ~isfinite(dtSec), dtSec = 10; end
            ns = double(ns(:).');
            n = numel(ns);
            tot = 0; got = false;
            for i = 1:size(pairs,1)
                a = round(pairs(i,1)); b = round(pairs(i,2));
                a = max(1, min(a, n)); b = max(1, min(b, n));
                lo = min(a,b); hi = max(a,b);
                seg = ns(lo:hi);
                seg = seg(isfinite(seg));
                if isempty(seg), continue; end
                tot = tot + sum(seg) * velMult * dtSec;
                got = true;
            end
            if got, est = tot; end
        end


        % ================================================================
        %                    KALIBRASI KECEPATAN (geometri)
        % ================================================================
        function [vm, info] = velMultGeom(dataFile, indenterMax, dtSec, nF)
        %VELMULTGEOM  Faktor kalibrasi cm/s per (px/frame) dari GEOMETRI indenter.
        %   Metode (sama dgn frameCatalog.resolveRender opsi-3):
        %     dxCm     = |X0_cm - X1_cm|                (total geser indenter, cm)
        %     vIndCmS  = dxCm / ((nF-1) * dtSec)        (kecepatan fisik indenter, cm/s)
        %     vm       = vIndCmS / indenterMax          (cm/s per px/frame)
        %   `indenterMax` = puncak |V| envelope kurva POT (px/frame).
        %   Kembalikan vm=NaN bila geometri/indenter tak lengkap (caller fallback).
        %   info = struct(dxCm, vIndCmS, indenterMax, dtSec, nF, source).
            vm = NaN;
            info = struct('dxCm',NaN,'vIndCmS',NaN,'indenterMax',NaN, ...
                'dtSec',NaN,'nF',NaN,'source','fallback');
            % readGeom mengembalikan [strainPct, cmPerPx, dxCm]; ambil dxCm.
            dxCm = NaN;
            try, [~, ~, dxCm] = pivcore.export.frameCatalog.readGeom(dataFile); catch, end
            if nargin < 4 || isempty(nF) || ~isfinite(nF)
                nF = NaN;
                try
                    V = whos('-file', dataFile);
                    idx = find(strcmp({V.name},'velocity_magnitude'),1);
                    if ~isempty(idx)
                        sz = V(idx).size;
                        % velocity_magnitude bisa cell 1xN (per-frame) atau 3-D HxWxN.
                        if numel(sz) >= 3
                            nF = sz(3);
                        elseif numel(sz) == 2 && min(sz) == 1
                            nF = max(sz);   % cell array per-frame
                        end
                    end
                catch
                end
            end
            info.dxCm = dxCm; info.indenterMax = indenterMax; info.dtSec = dtSec; info.nF = nF;
            ok = isfinite(dxCm) && dxCm>0 && isfinite(dtSec) && dtSec>0 ...
                && isfinite(nF) && nF>1 && isfinite(indenterMax) && indenterMax>0;
            if ok
                vIndCmS = dxCm / ((nF-1)*dtSec);
                vm = vIndCmS / indenterMax;
                info.vIndCmS = vIndCmS; info.source = 'geom';
            end
        end


        % ================================================================
        %                            dt (EXIF)
        % ================================================================
        function dt = readDtMean(dataFile)
        %READDTMEAN  Baca dt detik/frame dari MAT PIV. Urutan:
        %     1) exif_meta.dt_mean_s (jika var 'exif_meta' punya field dt_mean_s)
        %     2) frameCatalog.readExifDt (median EXIF)
        %     3) fallback 10 detik.
        %   SELALU kembalikan skalar finite > 0.
            dt = NaN;
            try
                V = whos('-file', dataFile); names = {V.name};
                if any(strcmp(names,'exif_meta'))
                    S = load(dataFile, 'exif_meta'); em = S.exif_meta;
                    if isstruct(em) && isfield(em,'dt_mean_s')
                        v = em.dt_mean_s;
                        if isscalar(v) && isfinite(v) && v > 0, dt = double(v); end
                    end
                end
            catch
            end
            if ~(isscalar(dt) && isfinite(dt) && dt > 0)
                try, dt = pivcore.export.frameCatalog.readExifDt(dataFile); catch, dt = NaN; end
            end
            if ~(isscalar(dt) && isfinite(dt) && dt > 0), dt = 10; end
        end


        % ================================================================
        %                       HELPER (publik)
        % ================================================================
        function nm = safeName(s)
            nm = pivcore.io.pab4DescExport.safeName(s);
        end

        function writeJsonAtomic(p, obj)
            pivcore.io.pab4DescExport.writeJsonAtomic(p, obj);
        end

        function t = normFtag(fNum)
        %NORMFTAG  Normalkan tag F# ke 'F<num>' ('F3'/'3'/3 -> 'F3'). Kosong -> ''.
            t = '';
            s = '';
            if ischar(fNum)
                s = fNum;
            elseif isnumeric(fNum) && isscalar(fNum) && isfinite(fNum)
                s = sprintf('%g', fNum);
            elseif isstring(fNum) && isscalar(fNum)
                s = char(fNum);
            end
            s = strtrim(s);
            if isempty(s), return; end
            s = regexprep(s, '^[Ff]+', '');
            num = str2double(s);
            if isfinite(num), t = sprintf('F%g', num); else, t = ['F' s]; end
        end

    end
end
