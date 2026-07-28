function pts = prepRoiPts(prep, field, ptsField, roiField)
%PREPROIPTS  Ambil titik poligon ROI (Nx2) dari preset tersemat di prep.
%   Prioritas *Pts (Nx2); fallback *ROI ([x y w h] -> 4 sudut). [] bila tak ada.
%   SATU sumber pembaca ROI preset skema prep — sebelumnya i_roiPts (GRAINSA1a).
%
%   pts = pivanalyzemat.core.prepRoiPts(prep, field, ptsField, roiField)
%     field    : nama sub-struct preset (mis. 'anchor_used' / 'crop_used')
%     ptsField : nama field titik poligon (mis. 'anchorPts' / 'framePts')
%     roiField : nama field rect (mis. 'anchorROI' / 'frameROI')
    pts = [];
    if ~isstruct(prep) || ~isfield(prep, field) || isempty(prep.(field)) || ~isstruct(prep.(field))
        return;
    end
    s = prep.(field);
    if isfield(s, ptsField) && ~isempty(s.(ptsField)) && size(s.(ptsField),2) == 2
        pts = double(s.(ptsField)); return;
    end
    if isfield(s, roiField) && numel(s.(roiField)) == 4
        r = double(s.(roiField));
        pts = [r(1) r(2); r(1)+r(3) r(2); r(1)+r(3) r(2)+r(4); r(1) r(2)+r(4)];
    end
end
