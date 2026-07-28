function [d, dx, dy] = nodeSpacing(data)
%NODESPACING  Estimasi jarak antar-node grid vektor PIV (px) dari data.x/data.y.
%   [d, dx, dy] = pivcore.data.nodeSpacing(data)
%
%   Grid vektor PIV (PIVLAB) jauh lebih kasar daripada raster citra: satu
%   vektor hanya ada setiap ~Δ piksel. Garis & spacing sampling didefinisikan
%   di koordinat citra, jadi mengetahui Δ memungkinkan pengguna memilih
%   spacing = Δ -> tepat satu sampel per node (tanpa double-sampling).
%
%   Mengembalikan:
%     d  = jarak node representatif (px), median dari dx & dy (estimasi isotropik)
%     dx = median jarak antar-kolom (sepanjang x), dari x(1,:) frame-1
%     dy = median jarak antar-baris (sepanjang y), dari y(:,1) frame-1
%   Bernilai NaN bila grid tidak bisa diuraikan (data kosong / tak ada x,y).

    d = NaN; dx = NaN; dy = NaN;
    if nargin < 1 || isempty(data) || ~isstruct(data), return; end

    x = []; y = [];
    if isfield(data,'x'), x = pivcore.data.safeFrame(data.x, 1); end
    if isfield(data,'y'), y = pivcore.data.safeFrame(data.y, 1); end

    if ~isempty(x) && size(x,2) >= 2
        dv = diff(x(1,:));
        dv = dv(isfinite(dv) & dv ~= 0);
        if ~isempty(dv), dx = median(abs(dv)); end
    end
    if ~isempty(y) && size(y,1) >= 2
        dv = diff(y(:,1));
        dv = dv(isfinite(dv) & dv ~= 0);
        if ~isempty(dv), dy = median(abs(dv)); end
    end

    cand = [dx dy];
    cand = cand(isfinite(cand) & cand > 0);
    if ~isempty(cand), d = median(cand); end
end
