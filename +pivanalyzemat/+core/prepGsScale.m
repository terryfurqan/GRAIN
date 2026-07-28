function scale = prepGsScale(prep)
%PREPGSSCALE  Resolusi skala GS dari metadata prep (default 0.5; hanya terima
%   0 < s <= 1). SATU sumber — sebelumnya disalin di i_gsScale (PABSA1a) dan
%   i_gsParams (unpackMat).
    scale = 0.5;
    if isstruct(prep) && isfield(prep, 'gs_scale') && ~isempty(prep.gs_scale) ...
            && isnumeric(prep.gs_scale)
        s = double(prep.gs_scale(1));
        if isfinite(s) && s > 0 && s <= 1, scale = s; end
    end
end
