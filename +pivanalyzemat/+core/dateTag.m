function tag = dateTag()
%DATETAG  Tag tanggal 'yyyy-MM-dd' (hari ini) untuk penamaan folder output PIV.
%   SATU sumber format tanggal kontrak Step 2 -> Step 3/3a.
%   Sebelumnya disalin sebagai i_dateTag di PAB_step_2.
    tag = char(datetime('now', 'Format', 'yyyy-MM-dd'));
end
