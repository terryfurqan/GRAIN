function [files, inputFolder] = pickInputs()
%PICKINPUTS  Dialog pemilihan FOLDER berisi gambar input untuk PIVPrep.
%
%   [files, inputFolder] = pivprep.io.pickInputs()
%
%   User memilih SATU folder; seluruh berkas gambar yang didukung di
%   dalam folder tersebut dikumpulkan otomatis lalu diurutkan secara
%   natural (berdasarkan angka di nama berkas).
%
%   OUTPUT:
%       files       cell array nama berkas (tanpa path), sudah natural sort.
%       inputFolder path folder yang dipilih user.
%
%   Mengembalikan cell kosong dan string kosong jika user membatalkan
%   atau jika folder tidak berisi berkas gambar yang didukung.
%
%   Format yang didukung: jpg, jpeg, png, tif, tiff (case-insensitive).

    inputFolder = uigetdir(pwd, ...
        'Pilih Folder Berisi Gambar Input (semua gambar akan dimuat)');

    if isequal(inputFolder, 0)
        files = {};
        inputFolder = '';
        return;
    end

    % --- Kumpulkan semua berkas gambar yang didukung ---
    exts = {'*.jpg', '*.jpeg', '*.png', '*.tif', '*.tiff'};
    raw  = {};
    for k = 1:numel(exts)
        d   = dir(fullfile(inputFolder, exts{k}));
        d   = d(~[d.isdir]);
        raw = [raw, {d.name}];  %#ok<AGROW>
    end

    % Buang duplikat secara case-insensitive (mis. *.jpg vs *.JPG pada
    % filesystem case-insensitive seperti macOS/Windows).
    if ~isempty(raw)
        [~, ia] = unique(lower(raw), 'stable');
        raw = raw(ia);
    end

    if isempty(raw)
        files = {};
        warndlg(sprintf([ ...
            'Tidak ada berkas gambar yang didukung di folder:\n%s\n\n' ...
            'Format yang didukung: jpg, jpeg, png, tif, tiff.'], ...
            inputFolder), 'PIVPrep: Folder Kosong');
        return;
    end

    files = pivprep.util.utilities.naturalSort(raw);
end
