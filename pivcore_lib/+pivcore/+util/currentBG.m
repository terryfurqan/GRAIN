function bg = currentBG(h, k)
%CURRENTBG  Ambil citra latar yang terkait bingkai k.
%   Port dari i_currentBG (PIV_Viewer.m baris 1789-1802).

    bg = [];
    if isempty(h.state.bgImages), return; end
    if numel(h.state.bgImages) < k
        idx = numel(h.state.bgImages);
    else
        idx = k;
    end
    if idx < 1, return; end
    img = h.state.bgImages{idx};
    if isempty(img), return; end
    if ~isnumeric(img) && ~islogical(img), return; end
    bg = img;
end
