classdef pab4Lifecycle
%PAB4LIFECYCLE  Engine MURNI/HEADLESS: rangkum SIKLUS HIDUP sesar menjadi
%   TIMELINE FASE ber-stempel, untuk dibaca CLCW / analisis ilmiah. Menceritakan
%   perkembangan sesar dari belum-ada -> nukleasi -> membentuk FSR -> aktivitas
%   berkurang -> berhenti aktif.
%
%   Fase diturunkan dari POI baris DESC PAB4 (frame mentah) + kalibrasi ruang-
%   waktu (strainTotalPct linear per-frame + dtSec). Tidak ada dependensi GUI —
%   fungsi murni, mudah di-test golden.
%
%   POI penanda (frame; NaN bila tak dicatat user):
%     nucFsr      frame POI 'NUC-FSR'  (nukleasi mulai)
%     fsMaxFirst  frame POI 'FS-max' PERTAMA (FSR mulai terbentuk)
%     fsMaxLast   frame POI 'FS-max' TERAKHIR (FSR menyempurnakan / puncak slip)
%     fsx         frame POI 'FS-x'    (fault slip STOP -> berhenti aktif)
%
%   FASE KANONIK (interval [frameStart..frameEnd], di-clamp [1,nF], monoton):
%     pre-fault      1          -> nucFsr        belum ada sesar
%     nucleation     nucFsr     -> fsMaxFirst    nukleasi (growthRate cm/s)
%     FSR-formation  fsMaxFirst -> fsMaxLast     membentuk/menyempurnakan FSR
%     active-slip    fsMaxLast  -> fsx | nF      slip aktif penuh
%     waning         fsMaxLast  -> fsx           aktivitas berkurang (dieOutRate)
%     inactive       fsx        -> nF            berhenti aktif
%
%   Fase dgn boundary NaN DILEWATI (skip) tanpa merusak urutan. active-slip &
%   waning boleh berbagi rentang FS-max_terakhir->FS-x: active-slip = kejadian
%   slip; waning = interpretasi die-out atas rentang yg sama.
%
%   Tiap fase distempel:
%     phase           nama fase (char)
%     frameStart/End  frame mentah (clamp [1,nF])
%     strainStartPct  cumulative strain % di frameStart (linear per-frame)
%     strainEndPct    cumulative strain % di frameEnd
%     durationSec     (frameEnd - frameStart) * dtSec   ([] bila dtSec absen)
%     rateType/rate   opsional: 'growth'/'die-out' (cm/s) dari geometri polyline
%
%   API:
%     poi    = pivcore.io.pab4Lifecycle.poiStruct(nucFsr, fsMaxFirst, fsMaxLast, fsx)
%     phases = pivcore.io.pab4Lifecycle.lifecyclePhases(poi, nF, strainTot, dtSec, rates)
%     pct    = pivcore.io.pab4Lifecycle.strainAtFrameLinear(frameK, nF, strainTotalPct)
%
%   Penempatan: PAB/pivcore_lib/+pivcore/+io/pab4Lifecycle.m

    methods (Static)

        % ================================================================
        function poi = poiStruct(nucFsr, fsMaxFirst, fsMaxLast, fsx)
        %POISTRUCT  Kerangka POI frame. Argumen absen -> NaN.
            if nargin < 1, nucFsr     = NaN; end
            if nargin < 2, fsMaxFirst = NaN; end
            if nargin < 3, fsMaxLast  = NaN; end
            if nargin < 4, fsx        = NaN; end
            poi = struct( ...
                'nucFsr',     pivcore.io.pab4Lifecycle.scal(nucFsr), ...
                'fsMaxFirst', pivcore.io.pab4Lifecycle.scal(fsMaxFirst), ...
                'fsMaxLast',  pivcore.io.pab4Lifecycle.scal(fsMaxLast), ...
                'fsx',        pivcore.io.pab4Lifecycle.scal(fsx));
        end


        % ================================================================
        function phases = lifecyclePhases(poi, nF, strainTot, dtSec, rates)
        %LIFECYCLEPHASES  Bangun cell timeline fase ber-stempel dari POI frame.
        %   poi       struct dari poiStruct (nucFsr/fsMaxFirst/fsMaxLast/fsx)
        %   nF        jumlah frame eksperimen (skalar)
        %   strainTot total cumulative strain % (skalar; NaN -> strain di-null)
        %   dtSec     detik/frame (skalar >0; absen/NaN -> durationSec = null)
        %   rates     opsional struct(growth, dieOut) cm/s dari geometri polyline
        %             -> ditempel ke fase nucleation (growth) & waning (die-out).
        %   RETURN: cell 1xM of phase-struct (JSON array). Fase boundary invalid
        %   dilewati. Selalu kembalikan cell (bisa kosong).
            if nargin < 5 || ~isstruct(rates), rates = struct('growth',NaN,'dieOut',NaN); end
            if nargin < 4, dtSec = NaN; end
            if nargin < 3, strainTot = NaN; end
            if nargin < 2, nF = NaN; end
            L  = @pivcore.io.pab4Lifecycle.scal;
            poi = pivcore.io.pab4Lifecycle.normPoi(poi);
            nFv = L(nF);
            if ~isfinite(nFv) || nFv < 1, nFv = NaN; end

            % Ambil boundary (frame mentah; NaN bila absen).
            nuc = poi.nucFsr; f1 = poi.fsMaxFirst; f2 = poi.fsMaxLast; fx = poi.fsx;
            % fsMaxLast minimal = fsMaxFirst bila hanya 1 FS-max dicatat.
            if ~isfinite(f2) && isfinite(f1), f2 = f1; end
            endActive = fx; if ~isfinite(endActive), endActive = nFv; end

            gr = pivcore.io.pab4Lifecycle.rateVal(rates, 'growth');
            do = pivcore.io.pab4Lifecycle.rateVal(rates, 'dieOut');

            % Definisi fase kanonik {name, a, b, rateType, rateVal}.
            defs = { ...
                'pre-fault',      1,   nuc, '',        NaN ; ...
                'nucleation',     nuc,  f1, 'growth',  gr  ; ...
                'FSR-formation',  f1,   f2, '',        NaN ; ...
                'active-slip',    f2, endActive, '',   NaN ; ...
                'waning',         f2,   fx, 'die-out', do  ; ...
                'inactive',       fx,  nFv, '',        NaN };

            phases = {};
            for k = 1:size(defs,1)
                a = pivcore.io.pab4Lifecycle.scal(defs{k,2});
                b = pivcore.io.pab4Lifecycle.scal(defs{k,3});
                if ~isfinite(a) || ~isfinite(b), continue; end   % boundary hilang
                a = pivcore.io.pab4Lifecycle.clampFrame(a, nFv);
                b = pivcore.io.pab4Lifecycle.clampFrame(b, nFv);
                if b < a, continue; end                          % interval terbalik -> skip
                ph = pivcore.io.pab4Lifecycle.phaseStruct( ...
                    defs{k,1}, a, b, nFv, strainTot, dtSec, defs{k,4}, defs{k,5});
                phases{end+1} = ph; %#ok<AGROW>
            end
        end


        % ================================================================
        function ph = phaseStruct(name, a, b, nF, strainTot, dtSec, rateType, rateVal)
        %PHASESTRUCT  Rakit satu fase ber-stempel (strain% + durasi detik).
            if nargin < 7, rateType = ''; end
            if nargin < 8, rateVal  = NaN; end
            ph = struct();
            ph.phase          = char(name);
            ph.frameStart     = double(a);
            ph.frameEnd       = double(b);
            ph.strainStartPct = pivcore.io.pab4Lifecycle.numOrNan( ...
                pivcore.io.pab4Lifecycle.strainAtFrameLinear(a, nF, strainTot));
            ph.strainEndPct   = pivcore.io.pab4Lifecycle.numOrNan( ...
                pivcore.io.pab4Lifecycle.strainAtFrameLinear(b, nF, strainTot));
            dt = pivcore.io.pab4Lifecycle.scal(dtSec);
            if isfinite(dt) && dt > 0
                ph.durationSec = (double(b) - double(a)) * dt;
            else
                ph.durationSec = NaN;   % jsonencode -> null
            end
            % Laju opsional (growth/die-out) hanya bila type diberi & nilai finite.
            if ~isempty(rateType) && isscalar(rateVal) && isfinite(rateVal)
                ph.rateType = char(rateType);
                ph.rate     = double(rateVal);   % cm/s
            end
        end


        % ================================================================
        function pct = strainAtFrameLinear(frameK, nF, strainTotalPct)
        %STRAINATFRAMELINEAR  Cumulative strain % di frame k: (k-1)/(nF-1)*total.
        %   Frame 1 -> 0%, frame nF -> total. NaN bila input invalid. Identik pola
        %   pivcore.io.pab5FaultExport.strainAtFrame (di-duplikasi supaya engine
        %   ini mandiri/headless, tanpa dependensi lintas-paket).
            pct = NaN;
            if ~(isscalar(frameK) && isfinite(frameK)), return; end
            if ~(isscalar(strainTotalPct) && isfinite(strainTotalPct)), return; end
            if ~(isscalar(nF) && isfinite(nF)), return; end
            if nF <= 1, pct = double(strainTotalPct);
            else, pct = (double(frameK)-1)/(double(nF)-1) * double(strainTotalPct); end
        end


        % ================================================================
        %                        HELPER (privat/pure)
        % ================================================================
        function poi = normPoi(p)
        %NORMPOI  Normalkan input POI -> struct lengkap (field selalu ada, skalar).
            poi = pivcore.io.pab4Lifecycle.poiStruct();
            if ~isstruct(p), return; end
            L = @pivcore.io.pab4Lifecycle.scal;
            if isfield(p,'nucFsr'),     poi.nucFsr     = L(p.nucFsr);     end
            if isfield(p,'fsMaxFirst'), poi.fsMaxFirst = L(p.fsMaxFirst); end
            if isfield(p,'fsMaxLast'),  poi.fsMaxLast  = L(p.fsMaxLast);  end
            if isfield(p,'fsx'),        poi.fsx        = L(p.fsx);        end
        end

        function f = clampFrame(x, nF)
        %CLAMPFRAME  Batasi frame ke [1, nF] (bila nF finite). Bulatkan.
            f = round(double(x));
            if f < 1, f = 1; end
            if isscalar(nF) && isfinite(nF) && nF >= 1 && f > nF, f = round(nF); end
        end

        function v = rateVal(rates, fld)
        %RATEVAL  Ambil nilai laju dari struct rates (finite) atau NaN.
            v = NaN;
            if isstruct(rates) && isfield(rates, fld)
                t = rates.(fld);
                if isscalar(t) && isnumeric(t) && isfinite(t), v = double(t); end
            end
        end

        function v = scal(x)
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end

        function v = numOrNan(x)
        %NUMORNAN  Skalar finite -> double; else NaN (jsonencode -> null).
            if isscalar(x) && isnumeric(x) && isfinite(x), v = double(x); else, v = NaN; end
        end

    end
end
