function tf = isPivOutName(name)
%ISPIVOUTNAME  TRUE bila nama folder berawalan 'PIV_' (folder output Step 2).
%   Sisi KONSUMER kontrak; dipakai pemindai Step 3/3a (scanPivMats).
    nm = char(name);
    tf = numel(nm) >= 4 && strcmpi(nm(1:4), 'PIV_');
end
