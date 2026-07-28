function r = pivOutDir(base)
%PIVOUTDIR  Folder output PIV ber-tag-tanggal: <base>/PIV_<yyyy-MM-dd>.
%   Sisi PRODUSER kontrak Step 2 (dipakai PAB_step_2 i_outRoot).
%   isPivOutName menguji sisi KONSUMERnya (Step 3/3a).
    r = fullfile(base, ['PIV_' pivanalyzemat.core.dateTag()]);
end
