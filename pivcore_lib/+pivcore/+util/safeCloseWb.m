function safeCloseWb(wb)
%SAFECLOSEWB  Penutupan waitbar yang aman.
%   Port dari i_safeCloseWb (PIV_Viewer.m baris 1388-1390).

    try, if ishandle(wb), close(wb); end, catch, end %#ok<NOSEM,CTCH>
end
