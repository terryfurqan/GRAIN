function js = jitterSummary(p)
%JITTERSUMMARY  Ambil struct ringkasan jitter (prep.jitter.summary) atau [] bila
%   absen. Parser MURNI struct-in/data-out (nol GUI).
%   Sebelumnya disalin byte-identik sebagai i_jitterSummary di PABSA1a/1b.
    js = [];
    if isfield(p,'jitter') && isstruct(p.jitter) && isfield(p.jitter,'summary') ...
            && isstruct(p.jitter.summary)
        js = p.jitter.summary;
    end
end
