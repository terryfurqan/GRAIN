function L = currentLineFromROI(roi, fallback)
%CURRENTLINEFROMROI  Posisi garis PSG TERKINI sebagai struct('p1',[x y],'p2',[x y]).
%   Utamakan ROI (mungkin sudah digeser user); bila ROI tak valid/kosong, pakai
%   fallback (mis. h.line tersimpan). Kosong -> [].
%
%   L = pivui.currentLineFromROI(roi, fallback)
%
%   Sebelumnya logika i_currentLine di PABSA3/3a.
    L = [];
    if ~isempty(roi) && isvalid(roi) && ~isempty(roi.Position)
        P = roi.Position;
        L = struct('p1', P(1,:), 'p2', P(2,:));
    elseif nargin >= 2 && ~isempty(fallback)
        L = fallback;
    end
end
