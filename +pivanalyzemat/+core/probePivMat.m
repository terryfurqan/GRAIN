function [meta, ok] = probePivMat(f)
%PROBEPIVMAT  Deteksi murah apakah .mat berisi data PIVlab + metadata ringan.
%   ok=true bila ada var 'x' atau 'velocity_magnitude' (tanpa load isi).
%   nFrames dari panjang cell var bingkai (x/velocity_magnitude/u_*), fallback 1.
%   meta.sizeMB dari ukuran berkas. Sebelumnya i_probeMat di PABSA3/3a.
    meta = struct('sizeMB',0,'nFrames',1); ok = false;
    di = dir(f); if ~isempty(di), meta.sizeMB = di(1).bytes/1e6; end
    try
        info = whos('-file', f);
    catch
        return;
    end
    names = {info.name};
    isPiv = any(strcmp(names,'x')) || any(strcmp(names,'velocity_magnitude'));
    if ~isPiv, return; end
    ok = true;
    for cand = {'x','velocity_magnitude','u_original','u_filtered'}
        ix = find(strcmp(names, cand{1}), 1);
        if isempty(ix), continue; end
        if strcmp(info(ix).class,'cell')
            sz = info(ix).size; meta.nFrames = max(1, prod(sz)); break;
        end
    end
end
