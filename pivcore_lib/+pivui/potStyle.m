function s = potStyle()
%POTSTYLE  Palet warna & tebal garis ROI/kurva POT-PSG untuk GUI pratinjau
%   (GRAINSA3/3a). SATU sumber gaya — sebelumnya literal warna/LW di-hardcode di
%   tiap pemanggil (drawline/plot envelope/garis-frame/kurva-terpilih/marker).
%
%   s.psgLine   : garis PSG (ROI Line)   — color/lineWidth/markerSize
%   s.indenter  : envelope indenter-max  — color/lineWidth
%   s.frameLine : indikator frame axPOT  — color/lineWidth
%   s.selCurve  : kurva POT terpilih     — color/lineWidth
%   s.selMarker : kotak sorot record (3a) — color/lineWidth
    s.psgLine   = struct('color', [1 0.55 0],        'lineWidth', 2,   'markerSize', 11);
    s.indenter  = struct('color', [0 0 0],           'lineWidth', 3);
    s.frameLine = struct('color', [0.10 0.45 0.90],  'lineWidth', 1.4);
    s.selCurve  = struct('color', [1 0 0],           'lineWidth', 3.0);
    s.selMarker = struct('color', [1 0 0],           'lineWidth', 1.3);
end
