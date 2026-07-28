function roi = makePsgLineROI(ax, p1, p2, onMoved, onMoving)
%MAKEPSGLINEROI  Buat garis PSG INTERAKTIF (images.roi.Line) di axes ax dari dua
%   ujung p1,p2 — DRAGGABLE, warna/tebal/marker dari pivui.potStyle (oranye,
%   marker lingkaran). Pola identik PIVTerry StandAlone Step 1 (cara tarik garis
%   terbaik). Bila onMoved (function handle) diberi, dipasang sebagai listener
%   event 'ROIMoved' (dipicu saat user SELESAI menggeser ujung -> ringan).
%   Bila onMoving diberi, dipasang ke 'MovingROI' -> umpan-balik LANGSUNG/mulus
%   saat ujung masih ditarik (jangan dipakai utk pekerjaan berat spt sampling).
%
%   roi = pivui.makePsgLineROI(ax, p1, p2)               % tanpa listener
%   roi = pivui.makePsgLineROI(ax, p1, p2, @cb)          % + ROIMoved
%   roi = pivui.makePsgLineROI(ax, p1, p2, @cb, @cbLive) % + ROIMoved + ROIMoving
%
%   SATU sumber pembuatan ROI garis PSG — sebelumnya literal warna/LW/MS disalin
%   di i_ensureROI & cabang drawline i_onDrawLine (PABSA3/3a).
    st = pivui.potStyle();  s = st.psgLine;
    roi = images.roi.Line('Parent', ax, ...
        'Position', [p1; p2], ...
        'Color', s.color, 'LineWidth', s.lineWidth, 'MarkerSize', s.markerSize, ...
        'Label', 'PSG', 'LabelVisible', 'hover');
    if nargin >= 4 && ~isempty(onMoved)
        addlistener(roi, 'ROIMoved', @(src,evt) onMoved());
    end
    if nargin >= 5 && ~isempty(onMoving)
        addlistener(roi, 'MovingROI', @(src,evt) onMoving());
    end
end
