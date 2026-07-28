function restoreAfterDialog(fig)
%RESTOREAFTERDIALOG  Pulihkan jendela utama ke ukuran normal & beri fokus setelah
%   dialog berkas ditutup. Pasangan: minimizeForDialog. No-op aman.
%   Sebelumnya disalin sebagai i_restore (GRAINSA1a/1b/3/3a) & nested restoreFig (step_2).
    try, set(fig,'WindowState','normal'); drawnow; figure(fig); catch, end
end
