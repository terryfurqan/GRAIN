function tf = quiet()
%QUIET  Mode SENYAP untuk tes: TRUE bila figure disembunyikan
%   (DefaultFigureVisible='off', di-set oleh test). Saat senyap, modul JANGAN
%   membuat waitbar — jendela waitbar memaksa dirinya terlihat ('Visible','on')
%   sehingga MEREBUT FOKUS MOUSE pengguna walau figure utama invisible.
%
%   Pola: di awal smoke test ->
%     ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
%     restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov));
%   lalu modul cek `pivui.quiet()` sebelum `waitbar(...)`.
    tf = strcmp(get(groot,'DefaultFigureVisible'),'off');
end
