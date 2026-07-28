function clearFigModes(fig)
%CLEARFIGMODES  Matikan mode interaktif figure (zoom/pan/rotate/datacursor/
%   brush) supaya klik di axes murni untuk menetapkan garis PSG, bukan pan.
%   Sebelumnya disalin sebagai i_clearFigModes di PABSA3/3a.
    if ~ishghandle(fig), return; end
    try, zoom(fig,'off');        catch, end
    try, pan(fig,'off');         catch, end
    try, rotate3d(fig,'off');    catch, end
    try, datacursormode(fig,'off'); catch, end
    try, brush(fig,'off');       catch, end
end
