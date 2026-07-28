function applyRowStyles(tbl, bgRows, fgRows)
%APPLYROWSTYLES  Warnai tiap baris uitable: bgRows(r,:) = latar, fgRows(r,:) =
%   teks. Hapus style lama dulu. Best-effort (uistyle/addStyle R2023a+); no-op
%   aman bila tak didukung. Dipakai tabel kurva step2 (warna = warna label).
    if ~ishghandle(tbl), return; end
    try
        removeStyle(tbl);
    catch
    end
    for r = 1:size(bgRows,1)
        try
            st = uistyle('BackgroundColor', bgRows(r,:), 'FontColor', fgRows(r,:));
            addStyle(tbl, st, 'row', r);
        catch
            return;
        end
    end
end
