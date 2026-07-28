function imOut = orientImage(im, h)
%ORIENTIMAGE  Terapkan flip & rotasi pada citra (RGB).
%   Port dari i_orientImage (PIV_Viewer.m baris 1673-1689).

    imOut = im;
    if isempty(imOut), return; end
    if get(h.chkFlipH,'Value') == 1
        imOut = imOut(:, end:-1:1, :);
    end
    if get(h.chkFlipV,'Value') == 1
        imOut = imOut(end:-1:1, :, :);
    end
    rotIdx = get(h.popRotate,'Value');
    switch rotIdx
        case 2, imOut = rot90(imOut, 1);   % 90 CCW
        case 3, imOut = rot90(imOut, 2);   % 180
        case 4, imOut = rot90(imOut, -1);  % 90 CW
    end
end
