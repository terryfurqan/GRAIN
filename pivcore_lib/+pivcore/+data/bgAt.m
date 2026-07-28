function bg = bgAt(data, k)
%BGAT  Citra latar bingkai k dari DATASET (cell data.bg_images); fallback ke
%   elemen terakhir lalu elemen-1. Port verbatim dari step2 i_bgAt.
%
%   Beda dari pivcore.util.currentBG yang membaca h.state.bgImages (bentuk
%   main-suite, butuh struct handle); yang ini membaca dataset polos.
    bg = [];
    if ~isstruct(data) || ~isfield(data,'bg_images') || ~iscell(data.bg_images)
        return;
    end
    C = data.bg_images;
    if isempty(C), return; end
    if k < 1, k = 1; end
    if k > numel(C), k = numel(C); end
    bg = C{k};
end
