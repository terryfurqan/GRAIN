function d = glyphDefaults()
%GLYPHDEFAULTS  Default render glyph vektor (panah quiver) untuk GUI PIV.
%   d.spacing   : decimation node (tiap-N node digambar)   [3]
%   d.lineWidth : tebal garis panah                         [1]
%   Cermin fallback nargin di pivcore.util.drawGlyphs — SATU sumber konstanta
%   supaya seed handle GUI (h.glyphSp/h.glyphLW) & string edit-box tak hardcode.
    d = struct('spacing', 3, 'lineWidth', 1);
end
