function t = titleWithVersion(baseTitle)
%TITLEWITHVERSION  Judul window + keterangan versi build (untuk 'Name' figure).
%
%   t = pivui.titleWithVersion('GRAIN Masking — ...')
%   -> 'GRAIN Masking — ...   [v a1b2c3d · 2026-07-03 10:20]'
%
%   Supaya user langsung tahu salinan mana yang jalan (mis. cek PC-2 sudah versi
%   terbaru atau belum). Versi dari pivui.grainVersion (commit git, cached). Aman:
%   bila git tak terbaca -> '[v (tanpa-git)]'. Bila grainVersion tak ada -> judul
%   apa adanya (mundur anggun).
    baseTitle = char(baseTitle);
    try
        v = pivui.grainVersion();
        if isstruct(v) && isfield(v, 'label') && ~isempty(v.label)
            t = sprintf('%s   [%s]', baseTitle, v.label);
            return;
        end
    catch
    end
    t = baseTitle;
end
