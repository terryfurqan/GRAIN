function t = titleWithVersion(baseTitle)
%TITLEWITHVERSION  Judul window + keterangan versi build (untuk 'Name' figure).
%
%   t = pivui.titleWithVersion('PAB Masking — ...')
%   -> 'PAB Masking — ...   [v a1b2c3d · 2026-07-03 10:20]'
%
%   Supaya user langsung tahu salinan mana yang jalan (mis. cek PC-2 sudah versi
%   terbaru atau belum). Versi dari pivui.pabVersion (commit git, cached). Aman:
%   bila git tak terbaca -> '[v (tanpa-git)]'. Bila pabVersion tak ada -> judul
%   apa adanya (mundur anggun).
    baseTitle = char(baseTitle);
    try
        v = pivui.pabVersion();
        if isstruct(v) && isfield(v, 'label') && ~isempty(v.label)
            t = sprintf('%s   [%s]', baseTitle, v.label);
            return;
        end
    catch
    end
    t = baseTitle;
end
