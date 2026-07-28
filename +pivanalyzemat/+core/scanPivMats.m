function files = scanPivMats(root)
%SCANPIVMATS  Kumpulkan berkas .mat keluaran PIV (Step 2) di bawah root:
%   root itu sendiri + subfolder LANGSUNG bernama PIV_* (1 level, tak rekursif
%   dalam-dalam), lalu buang berkas progres/sidecar (substring _autopot / progress).
%
%   files = pivanalyzemat.core.scanPivMats(root)   % cell array path .mat
%
%   CATATAN: pemindai INI berbeda dari scanMats (yang mendeteksi skema
%   'pivprep_single_v1'/prep Step 1) dan dari pivcore.io.indexScanner (rekursi
%   penuh + filter suffix). Scope & filter di sini SENGAJA dipertahankan persis
%   seperti i_collectMats PABSA3/3a agar daftar berkas identik.
    files = {};
    d = dir(fullfile(root, '*.mat'));
    for i = 1:numel(d)
        if ~d(i).isdir, files{end+1} = fullfile(root, d(i).name); end %#ok<AGROW>
    end
    sub = dir(root);
    for i = 1:numel(sub)
        if ~sub(i).isdir, continue; end
        nm = sub(i).name;
        if strcmp(nm,'.') || strcmp(nm,'..'), continue; end
        if pivanalyzemat.core.isPivOutName(nm)
            dd = dir(fullfile(root, nm, '*.mat'));
            for j = 1:numel(dd)
                if ~dd(j).isdir
                    files{end+1} = fullfile(root, nm, dd(j).name); %#ok<AGROW>
                end
            end
        end
    end
    % Buang berkas progres / sidecar (bukan data PIV).
    keep = true(1, numel(files));
    for i = 1:numel(files)
        [~, b] = fileparts(files{i});
        bl = lower(b);
        if contains(bl,'_autopot') || contains(bl,'progress')
            keep(i) = false;
        end
    end
    files = files(keep);
end
