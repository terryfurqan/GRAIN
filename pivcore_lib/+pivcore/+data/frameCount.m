function n = frameCount(data)
%FRAMECOUNT  Jumlah bingkai citra termuat (panjang cell data.x); fallback ke
%   data.nFrames lalu 1. Port verbatim dari step2 i_imageFrameCount.
    n = 1;
    if ~isstruct(data), return; end
    if isfield(data,'x') && iscell(data.x)
        n = max(1, numel(data.x));
    elseif isfield(data,'nFrames') && isfinite(data.nFrames)
        n = max(1, data.nFrames);
    end
end
