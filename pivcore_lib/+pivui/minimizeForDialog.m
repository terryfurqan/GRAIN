function minimizeForDialog(fig)
%MINIMIZEFORDIALOG  Kecilkan jendela utama sebelum membuka dialog berkas
%   (uigetfile/uigetdir/uiputfile) supaya dialog OS tak ketutup figure penuh.
%   Pasangan: restoreAfterDialog. Aturan global GUI seri PAB_SA. No-op aman.
%   Sebelumnya disalin sebagai i_minimize (PABSA1a/1b/3/3a) & nested minFig (step_2).
    try, set(fig,'WindowState','minimized'); drawnow; catch, end
end
