function lockAxInteractions(ax)
%LOCKAXINTERACTIONS  axes HANYA untuk garis PSG: matikan semua interaksi bawaan
%   axes (scroll-zoom, drag-pan, datatip, rotate). Tampilan dijaga zoom-fit lewat
%   xlim/ylim di pemanggil. Lintas-versi: bungkus try. Sebelumnya disalin sebagai
%   i_lockAxInteractions di GRAINSA3/3a.
    if ~ishghandle(ax), return; end
    try, disableDefaultInteractivity(ax); catch, end   % R2019a+
    try, ax.Interactions = [];               catch, end % buang scroll/pan/datatip
    try, ax.Toolbar = [];                    catch, end % buang toolbar hover axes
end
