function y = movavg(x, w)
%MOVAVG  Moving average sederhana yang mempertahankan NaN.
%   Port dari i_movavg (PIV_Viewer.m baris 2596-2609).

    if w < 2, y = x; return; end
    n = numel(x);
    y = nan(size(x));
    half = floor(w/2);
    for i = 1:n
        i1 = max(1, i - half);
        i2 = min(n, i + (w - half - 1));
        seg = x(i1:i2);
        sv = seg(isfinite(seg));
        if ~isempty(sv), y(i) = mean(sv); end
    end
end
