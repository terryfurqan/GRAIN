function fr = evenFrames(nFrames, nPanels)
%EVENFRAMES  Pilih nPanels bingkai ber-spasi-RATA dari 1..nFrames (inklusif
%   ujung). Selalu memuat bingkai-1 dan bingkai-terakhir bila nPanels>=2.
%
%   fr = pivcore.montage.evenFrames(nFrames, nPanels)
%
%   Contoh: evenFrames(35, 8) -> [1 6 11 16 20 25 30 35] (8 tahap merata,
%   meniru a..h pada figur publikasi).

    nFrames = max(1, round(nFrames));
    nPanels = max(1, round(nPanels));
    if nPanels == 1
        fr = 1; return;
    end
    if nPanels >= nFrames
        fr = 1:nFrames; return;
    end
    fr = round(linspace(1, nFrames, nPanels));
    fr = unique(fr, 'stable');
    % unique bisa memangkas bila ada tabrakan pembulatan; isi ulang bila kurang.
    if numel(fr) < nPanels
        all = 1:nFrames;
        rest = setdiff(all, fr, 'stable');
        need = nPanels - numel(fr);
        fr = sort([fr, rest(1:min(need, numel(rest)))]);
    end
end
