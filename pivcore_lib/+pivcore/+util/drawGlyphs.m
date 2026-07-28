function hq = drawGlyphs(ax, x, y, U, V, spacing, lineWidth, color)
%DRAWGLYPHS  Overlay glyph vektor (panah quiver) medan kecepatan di axes.
%
%   hq = pivcore.util.drawGlyphs(ax, x, y, U, V, spacing, lineWidth, color)
%
%   x,y,U,V : grid & komponen kecepatan bingkai (matriks ukuran sama).
%   spacing : ambil tiap-N node (decimation) — makin besar makin jarang.
%   lineWidth : tebal garis panah.
%   color   : warna panah [r g b] (default hitam [0 0 0]). Pakai [1 1 1] putih
%             saat latar gelap (mis. shear diverging) supaya kontras.
%
%   Mengembalikan handle quiver ([] bila tak ada data). Autoscale ON (panjang
%   relatif), HitTest mati supaya tak mengganggu ROI/garis PSG. Dipakai GUI
%   (PAB_step_3) & montase — SATU sumber kebenaran glyph.

    hq = [];
    if nargin < 6 || ~(isfinite(spacing) && spacing >= 1), spacing = 3; end
    if nargin < 7 || ~(isfinite(lineWidth) && lineWidth > 0), lineWidth = 1; end
    if nargin < 8 || numel(color) ~= 3, color = [0 0 0]; end
    spacing = round(spacing);
    if isempty(x) || isempty(y) || isempty(U) || isempty(V), return; end
    if ~isequal(size(x), size(U)) || ~isequal(size(y), size(V)), return; end

    s = 1:spacing:size(x,1);
    t = 1:spacing:size(x,2);
    if numel(s) < 1 || numel(t) < 1, return; end
    xs = x(s,t); ys = y(s,t);
    us = U(s,t); vs = V(s,t);

    g = isfinite(us) & isfinite(vs);
    if ~any(g(:)), return; end

    hold(ax,'on');
    hq = quiver(ax, xs, ys, us, vs, ...
        'Color',color, 'LineWidth',lineWidth, 'AutoScale','on', ...
        'MaxHeadSize',0.6, 'Tag','velGlyph', ...
        'HitTest','off','PickableParts','none');
end
