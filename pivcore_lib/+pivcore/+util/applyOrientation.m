function [xo, yo, Uo, Vo, Zo] = applyOrientation(h, x, y, U, V, Z)
%APPLYORIENTATION  Terapkan flip + rotasi pada koordinat dan data.
%   Port dari i_applyOrientation (PIV_Viewer.m baris 1587-1648).

    xo = x; yo = y; Uo = U; Vo = V; Zo = Z;
    if isempty(xo) || isempty(yo), return; end

    flipV = get(h.chkFlipV,'Value') == 1;
    flipH = get(h.chkFlipH,'Value') == 1;
    rotIdx = get(h.popRotate,'Value');  % 1: 0deg, 2: 90 CCW, 3: 180, 4: 90 CW

    if flipH
        xMid = (max(xo(:)) + min(xo(:)))/2;
        xo = 2*xMid - xo;
        if ~isempty(Uo), Uo = -Uo; end
    end
    if flipV
        yMid = (max(yo(:)) + min(yo(:)))/2;
        yo = 2*yMid - yo;
        if ~isempty(Vo), Vo = -Vo; end
    end

    if rotIdx ~= 1
        cx = (max(xo(:)) + min(xo(:)))/2;
        cy = (max(yo(:)) + min(yo(:)))/2;
        switch rotIdx
            case 2  % 90 CCW
                xn = -(yo - cy) + cx;
                yn =  (xo - cx) + cy;
                if ~isempty(Uo)
                    Un = -Vo;  Vn =  Uo;
                else, Un = Uo; Vn = Vo;
                end
                xo = xn; yo = yn; Uo = Un; Vo = Vn;
                Zo = pivcore.util.rotMat(Zo, 'ccw');
                xo = pivcore.util.rotMat(xo, 'ccw');
                yo = pivcore.util.rotMat(yo, 'ccw');
                if ~isempty(Uo)
                    Uo = pivcore.util.rotMat(Uo,'ccw');
                    Vo = pivcore.util.rotMat(Vo,'ccw');
                end
            case 3  % 180
                xn = 2*cx - xo;
                yn = 2*cy - yo;
                if ~isempty(Uo), Un = -Uo; Vn = -Vo; else, Un = Uo; Vn = Vo; end
                xo = xn; yo = yn; Uo = Un; Vo = Vn;
                Zo = pivcore.util.rotMat(Zo, '180');
                xo = pivcore.util.rotMat(xo, '180');
                yo = pivcore.util.rotMat(yo, '180');
                if ~isempty(Uo)
                    Uo = pivcore.util.rotMat(Uo,'180');
                    Vo = pivcore.util.rotMat(Vo,'180');
                end
            case 4  % 90 CW
                xn =  (yo - cy) + cx;
                yn = -(xo - cx) + cy;
                if ~isempty(Uo)
                    Un =  Vo;  Vn = -Uo;
                else, Un = Uo; Vn = Vo;
                end
                xo = xn; yo = yn; Uo = Un; Vo = Vn;
                Zo = pivcore.util.rotMat(Zo, 'cw');
                xo = pivcore.util.rotMat(xo, 'cw');
                yo = pivcore.util.rotMat(yo, 'cw');
                if ~isempty(Uo)
                    Uo = pivcore.util.rotMat(Uo,'cw');
                    Vo = pivcore.util.rotMat(Vo,'cw');
                end
        end
    end
end
