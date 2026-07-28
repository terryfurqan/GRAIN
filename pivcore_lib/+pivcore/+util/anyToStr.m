function s = anyToStr(v)
%ANYTOSTR  Konversi nilai apa pun ke string.
%   Port dari i_anyToStr (PIV_Viewer.m baris 2109-2122).

    if ischar(v)
        s = v;
    elseif isstring(v)
        s = char(strjoin(v,' '));
    elseif isnumeric(v) || islogical(v)
        s = mat2str(v);
    elseif iscell(v)
        parts = cellfun(@pivcore.util.anyToStr, v, 'UniformOutput', false);
        s = strjoin(parts, ' | ');
    else
        s = '<tidak dapat ditampilkan>';
    end
end
