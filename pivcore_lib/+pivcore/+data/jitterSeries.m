function [fr, jit, acc] = jitterSeries(p)
%JITTERSERIES  Deret (frame, jitter_px, accepted) dari prep.jitter.perFrame.
%   Parser MURNI struct-in/data-out (nol GUI). fr/jit hanya bingkai dgn jitter
%   finite; acc = vektor logical terima (kosong bila kolom Accepted absen).
%   Sebelumnya disalin byte-identik sebagai i_jitterSeries di GRAINSA1a/1b.
    fr = []; jit = []; acc = [];
    if ~isfield(p,'jitter') || isempty(p.jitter) || ~isstruct(p.jitter), return; end
    j = p.jitter;
    if ~isfield(j,'perFrame') || isempty(j.perFrame) || ~istable(j.perFrame), return; end
    T = j.perFrame; vn = T.Properties.VariableNames;
    if ismember('jitter_px', vn), jit = double(T.jitter_px(:)); else, return; end
    if ismember('Frame', vn), fr = double(T.Frame(:)); else, fr = (1:numel(jit))'; end
    if ismember('Accepted', vn)
        a = T.Accepted;
        if islogical(a), acc = a(:); elseif isnumeric(a), acc = a(:) ~= 0; end
    end
    g = isfinite(jit);
    fr = fr(g); jit = jit(g);
    if ~isempty(acc) && numel(acc) == numel(g), acc = acc(g); else, acc = []; end
end
