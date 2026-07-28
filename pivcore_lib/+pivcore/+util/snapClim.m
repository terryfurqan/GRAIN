function hi = snapClim(mx, step, mode)
%SNAPCLIM  Bulatkan batas ATAS CLim Vel mag ke kelipatan step (default 0.5).
%   mode 'ceil'  (DEFAULT, kompat PABSA3/3a): selalu KE ATAS — 3.3->3.5, 4.7->5.0.
%   mode 'round' (PAB4): ke TERDEKAT, batas keputusan 0.25× step (separuh step) —
%                8.6->8.5, 8.9->9.0, 8.3->8.5 (frac>0.25 di atas 8.0 -> naik).
%   Untuk mx tak valid (<=0 / non-finite) kembalikan step (batas atas minimum)
%   supaya CLim selalu [0 hi>0]. Kernel murni — dipisah dari callback GUI.
    if nargin < 2 || isempty(step) || ~(isfinite(step) && step > 0)
        step = 0.5;
    end
    if nargin < 3 || isempty(mode), mode = 'ceil'; end
    if ~(isfinite(mx) && mx > 0)
        hi = step; return;
    end
    switch lower(mode)
        case 'round', hi = round(mx / step) * step;   % batas 0.25× step
        otherwise,    hi = ceil(mx / step) * step;     % 'ceil'
    end
    if hi <= 0, hi = step; end
end
