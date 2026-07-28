classdef hbMerge
%HBMERGE  Gabung beberapa kurva KANDIDAT menjadi SATU garis HB (Hinterland
%   Block) — fungsi MURNI (headless). Dipakai GRAIN6 (analisis tampak PETA) untuk
%   membangun garis HB = "mirip max-indenter, tapi untuk Hanging Wall aktif".
%   Pola sibling: pivcore.pot.faultAngle / netslip (murni, tak menyentuh GUI/IO).
%
%   KONSEP (keputusan user):
%     - Tiap kurva kandidat k berkontribusi nilainya HANYA di rentang [x0_k, x1_k]
%       (batas awal/akhir ditandai user via axPOT; snap ke kurva).
%     - Kurva-kurva kandidat SALING OVERLAP di sumbu frame -> digabung jadi 1 garis.
%     - Di ZONA OVERLAP nilai HB = MAX nilai kurva-kurva valid di frame itu
%       (ENVELOPE ATAS — analog garis max-indenter; BUKAN rata-rata).
%     - Garis HB MULAI di X0 kurva PERTAMA (candidates{1}.x0): frame sebelum itu
%       di-NaN-kan (TIDAK ada ekor turun ke Y=0). HB "terus dinilai maksimumnya".
%
%   KONVENSI: kandidat = struct dgn field
%       .values  (1 x nF, deret |V| per-frame — sudah lewat trim+moving-avg)
%       .x0, .x1 (frame batas; NaN -> pakai tepi 1 / nF)
%   Cell array atau struct array keduanya diterima (dinormalkan ke cell).
%
%   API:
%     [hb, startX] = pivcore.pot.hbMerge.merge(cands, nF)
%     y            = pivcore.pot.hbMerge.clipToRange(values, x0, x1, nF)
%     tf           = pivcore.pot.hbMerge.isCoveredAt(x0, x1, f, nF)
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivcore/+pot/hbMerge.m

    methods (Static)

        % ================================================================
        function [hb, startX] = merge(cands, nF)
        %MERGE  Gabung kandidat -> garis HB (1 x nF). Zona overlap = MAX. HB NaN
        %   di luar cakupan & sebelum startX (X0 kurva pertama). startX = NaN bila
        %   tak ada kandidat.
            C = pivcore.pot.hbMerge.tocell(cands);
            if nargin < 2 || isempty(nF) || ~isfinite(nF), nF = 0; end
            nF = max(0, round(double(nF)));
            hb = nan(1, nF); startX = NaN;
            if isempty(C) || nF < 1, return; end

            % startX = X0 kurva PERTAMA (fallback: frame finite pertama kurva-1).
            startX = pivcore.pot.hbMerge.scal(pivcore.pot.hbMerge.gf(C{1}, 'x0'));
            if ~isfinite(startX)
                v1 = pivcore.pot.hbMerge.rowv(pivcore.pot.hbMerge.gf(C{1}, 'values'));
                g1 = find(isfinite(v1), 1, 'first');
                if ~isempty(g1), startX = g1; else, startX = 1; end
            end
            startX = max(1, min(nF, round(startX)));

            for f = startX:nF
                acc = [];
                for k = 1:numel(C)
                    c  = C{k};
                    x0 = pivcore.pot.hbMerge.scal(pivcore.pot.hbMerge.gf(c,'x0'));
                    x1 = pivcore.pot.hbMerge.scal(pivcore.pot.hbMerge.gf(c,'x1'));
                    if ~isfinite(x0), x0 = 1;  end
                    if ~isfinite(x1), x1 = nF; end
                    if f < round(min(x0,x1)) || f > round(max(x0,x1)), continue; end
                    v = pivcore.pot.hbMerge.rowv(pivcore.pot.hbMerge.gf(c,'values'));
                    if f <= numel(v) && isfinite(v(f)), acc(end+1) = v(f); end %#ok<AGROW>
                end
                if ~isempty(acc), hb(f) = max(acc); end   % OVERLAP -> MAX (envelope atas)
            end
        end


        % ================================================================
        function y = clipToRange(values, x0, x1, nF)
        %CLIPTORANGE  Deret 1 kurva di-NaN-kan di luar [x0,x1] (utk preview per-
        %   kandidat). x0/x1 NaN -> tepi 1 / nF.
            v = pivcore.pot.hbMerge.rowv(values);
            if nargin < 4 || isempty(nF) || ~isfinite(nF), nF = numel(v); end
            nF = max(numel(v), round(double(nF)));
            y = nan(1, nF); y(1:numel(v)) = v;
            a = pivcore.pot.hbMerge.scal(x0); if ~isfinite(a), a = 1;  end
            b = pivcore.pot.hbMerge.scal(x1); if ~isfinite(b), b = nF; end
            a = max(1, round(min(a,b))); b = min(nF, round(max(a,b)));
            mask = false(1, nF); mask(a:b) = true;
            y(~mask) = NaN;
        end


        % ================================================================
        function tf = isCoveredAt(x0, x1, f, nF)
        %ISCOVEREDAT  true bila frame f dalam [x0,x1] (NaN x0 -> 1; NaN x1 -> nF).
            if nargin < 4 || ~isfinite(nF), nF = Inf; end
            a = pivcore.pot.hbMerge.scal(x0); if ~isfinite(a), a = 1;  end
            b = pivcore.pot.hbMerge.scal(x1); if ~isfinite(b), b = nF; end
            lo = round(min(a,b)); hi = round(max(a,b));
            tf = isfinite(f) && f >= lo && f <= hi;
        end

    end


    % =================================================================
    methods (Static, Access = private)

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

        function v = gf(s, name)
        %GF  Ambil field s.(name) jika ada, else []/NaN aman.
            v = [];
            if isstruct(s) && isfield(s, name), v = s.(name); end
        end

        function v = rowv(x)
            if isempty(x), v = []; return; end
            v = double(x(:)).';
        end

        function v = scal(x)
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end

    end
end
