classdef vscale
%VSCALE  Skala vertikal plot POT (axPOT): zoom sumbu-Y dgn LEBAR (sumbu-X)
%   DIJAGA tetap. Anchor di BAWAH (ymin). `scale` = pengali tinggi visual kurva
%   relatif fit-penuh: 1 = fit, >1 = membesar (zoom-in, kurva lebih tinggi),
%   <1 = mengecil (zoom-out, kurva terkompres). SATU sumber kebenaran untuk GUI
%   standalone (step2) — kontrol MURNI/headless (tak menyentuh handle figure),
%   aman di-test. Gaya sejajar [[pivcore.pot.labels]] / curveFeatures.
%
%   API:
%     L  = pivcore.pot.vscale.levels()                         % nilai diskret
%     s  = pivcore.pot.vscale.defaultLevel()                   % skala awal (1x)
%     s  = pivcore.pot.vscale.snap(v [,L])                     % -> level terdekat
%     yl = pivcore.pot.vscale.ylimFor(yBase, scale [,padFrac]) % [lo hi]

    methods (Static)

        function L = levels()
        %LEVELS  Nilai skala vertikal DISKRET yg ditawarkan slider (urut naik).
        %   <1 = mengecil (kompres), 1 = fit penuh, >1 = membesar.
            L = [0.25 0.5 0.75 1 1.5 2];
        end


        function s = defaultLevel()
        %DEFAULTLEVEL  Skala awal = 1x (fit penuh).
            s = 1;
        end


        function s = snap(v, L)
        %SNAP  Bulatkan v ke level terdekat di L (default levels()). Nilai tak
        %   valid -> defaultLevel(). Di luar rentang -> level ujung terdekat.
            if nargin < 2 || isempty(L), L = pivcore.pot.vscale.levels(); end
            if ~(isscalar(v) && isfinite(v))
                s = pivcore.pot.vscale.defaultLevel(); return;
            end
            L = L(:).';
            [~, k] = min(abs(L - v));
            s = L(k);
        end


        function yl = ylimFor(yBase, scale, padFrac)
        %YLIMFOR  YLim [lo hi] utk dasar data yBase=[ymin ymax] pada `scale`.
        %   Anchor BAWAH: lo = ymin - pad; hi = lo + (range + 2*pad)/scale.
        %   Jadi scale NAIK -> rentang Y MENGECIL (kurva tampak lebih tinggi).
        %   [] bila yBase/range tak valid. padFrac default 0.04 (4% range).
            yl = [];
            if numel(yBase) ~= 2, return; end
            y0 = yBase(1); y1 = yBase(2);
            rng = y1 - y0;
            if ~(isfinite(rng) && rng > 0), return; end
            if nargin < 3 || ~(isscalar(padFrac) && isfinite(padFrac) && padFrac >= 0)
                padFrac = 0.04;
            end
            if ~(isscalar(scale) && isfinite(scale) && scale > 0), scale = 1; end
            pad = padFrac * rng;
            lo = y0 - pad;
            hi = lo + (rng + 2*pad) / scale;
            if ~(hi > lo), hi = lo + 1; end
            yl = [lo hi];
        end

    end
end
