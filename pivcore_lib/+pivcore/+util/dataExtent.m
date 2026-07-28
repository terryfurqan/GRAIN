function [xExt, yExt] = dataExtent(h, x, y)
%DATAEXTENT  Hitung extent (xMin/xMax/yMin/yMax) dari koordinat.
%   Port dari i_dataExtent (PIV_Viewer.m baris 1661-1671).

    if ~isempty(x) && ~isempty(y)
        xExt = [min(x(:)) max(x(:))];
        yExt = [min(y(:)) max(y(:))];
        if xExt(1) == xExt(2), xExt(2) = xExt(1) + 1; end
        if yExt(1) == yExt(2), yExt(2) = yExt(1) + 1; end
    else
        xExt = h.state.lockedXLim;
        yExt = h.state.lockedYLim;
    end
end
