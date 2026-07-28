function C = divergingMap(n)
%DIVERGINGMAP  Colormap diverging biru–putih–merah (n level) untuk medan
%   BERTANDA: biru = negatif, putih = nol, merah = positif. Port verbatim dari
%   step2 i_divergingMap (dipakai untuk shear strain bertanda).
    if nargin < 1 || ~isfinite(n) || n < 2, n = 256; end
    % Cache kasus paling umum (n==256): deterministik, hemat rebuild tiap panel.
    persistent D256
    if n == 256 && ~isempty(D256), C = D256; return; end
    m = floor(n/2);
    lo = [linspace(0.23,1,m)', linspace(0.30,1,m)', linspace(0.75,1,m)'];
    hi = [linspace(1,0.71,n-m)', linspace(1,0.09,n-m)', linspace(1,0.16,n-m)'];
    C = [lo; hi];
    C = min(1, max(0, C));
    if n == 256, D256 = C; end
end
