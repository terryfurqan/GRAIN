function out = safeFrame(C, k)
%SAFEFRAME  Akses aman ke C{k}; kembalikan [] jika tidak valid.
%   Port dari i_safeFrame (PIV_Viewer.m baris 1975-1981).

    out = [];
    if iscell(C) && numel(C) >= k && ~isempty(C{k})
        v = C{k};
        if isnumeric(v) || islogical(v), out = double(v); end
    end
end
