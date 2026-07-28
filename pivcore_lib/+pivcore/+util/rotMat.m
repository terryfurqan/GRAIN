function M = rotMat(M, dir)
%ROTMAT  Rotasi matriks generik (90 CCW / 90 CW / 180).
%   Port dari i_rotMat (PIV_Viewer.m baris 1650-1659).

    if isempty(M), return; end
    switch dir
        case 'ccw',  M = rot90(M, 1);
        case 'cw',   M = rot90(M, -1);
        case '180',  M = rot90(M, 2);
    end
end
