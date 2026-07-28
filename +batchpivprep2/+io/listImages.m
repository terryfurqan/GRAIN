function files = listImages(folder)
%LISTIMAGES  Daftar berkas gambar yang didukung di SATU folder (non-rekursif).
%
%   files = batchpivprep2.io.listImages(folder)
%
%   OUTPUT:
%       files   cell array nama berkas (tanpa path), sudah natural sort.
%               Cell kosong bila folder tidak berisi gambar yang didukung.
%
%   Format yang didukung: jpg, jpeg, png, tif, tiff (case-insensitive).
%   Duplikat case-insensitive (mis. *.jpg vs *.JPG di macOS/Windows)
%   dibuang. Mengikuti perilaku pivprep.io.pickInputs (modul +pivprep
%   yang dipakai ulang, tidak diduplikasi logikanya).

    files = {};
    if nargin < 1 || isempty(folder) || ~isfolder(folder)
        return;
    end

    exts = {'*.jpg', '*.jpeg', '*.png', '*.tif', '*.tiff'};
    raw  = {};
    for k = 1:numel(exts)
        d   = dir(fullfile(folder, exts{k}));
        d   = d(~[d.isdir]);
        raw = [raw, {d.name}]; %#ok<AGROW>
    end

    if isempty(raw)
        return;
    end

    [~, ia] = unique(lower(raw), 'stable');
    raw = raw(ia);

    files = pivprep.util.utilities.naturalSort(raw);
end
