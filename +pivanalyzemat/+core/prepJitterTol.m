function tol = prepJitterTol(prep)
%PREPJITTERTOL  Ambil ambang toleransi jitter (px) dari struct prep, NaN bila tak
%   terekam. SATU sumber daftar-kunci alias toleransi pada skema prep —
%   sebelumnya disalin di i_jitterTol & i_flag (PABSA1b).
%
%   tol = pivanalyzemat.core.prepJitterTol(prep)
%
%   Cari di prep.jitter.summary lalu prep.jitter (urutan itu), pada kunci alias:
%   tol / tolerance / jitterTol / tolPx / jitter_tol. Nilai pertama yang finite
%   dipakai.
    tol = NaN;
    if ~isstruct(prep) || ~isfield(prep,'jitter') || ~isstruct(prep.jitter), return; end
    j = prep.jitter;
    cand = {};
    if isfield(j,'summary') && isstruct(j.summary), cand{end+1} = j.summary; end
    cand{end+1} = j;
    keys = pivanalyzemat.core.prepTolKeys();
    for c = 1:numel(cand)
        s = cand{c};
        for k = 1:numel(keys)
            if isfield(s, keys{k}) && ~isempty(s.(keys{k}))
                v = s.(keys{k}); v = v(1);
                if isnumeric(v) && isfinite(v), tol = double(v); return; end
            end
        end
    end
end
