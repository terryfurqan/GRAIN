function [sorted, idx] = natsort(c)
%NATSORT  Natural sort untuk nama berkas dengan angka.
%   Port dari i_natsort (PIV_Viewer.m baris 1345-1386).

    if isempty(c)
        sorted = c; idx = []; return;
    end
    n = numel(c);
    keyNum = zeros(n,1);
    for k = 1:n
        s = c{k};
        tok = regexp(s, '\d+', 'match', 'once');
        if isempty(tok)
            keyNum(k) = inf;
        else
            v = str2double(tok);
            if ~isfinite(v), v = inf; end
            keyNum(k) = v;
        end
    end
    [~, idx] = sort(keyNum);
    sorted   = c(idx);
    keys     = keyNum(idx);
    i = 1;
    while i <= n
        j = i;
        while j < n && keys(j+1) == keys(i)
            j = j+1;
        end
        if j > i
            sub    = sorted(i:j);
            subIdx = idx(i:j);
            [sub2, ord2] = sort(sub);
            sorted(i:j) = sub2;
            idx(i:j)    = subIdx(ord2);
        end
        i = j+1;
    end
end
