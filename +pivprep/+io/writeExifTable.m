function writeExifTable(metaList, outPath)
%WRITEEXIFTABLE  Gabungkan banyak struct EXIF menjadi satu tabel & simpan.
%
%   pivprep.io.writeExifTable(metaList, outPath)
%
%   INPUT:
%       metaList  cell array struct (hasil pivprep.io.readExifData per
%                 berkas). Setiap elemen mewakili satu berkas.
%       outPath   path berkas .mat keluaran. Variabel yang disimpan
%                 bernama 'exif' (sebuah table).
%
%   PERILAKU:
%       - Satu BARIS tabel = satu berkas. Jumlah baris = numel(metaList).
%       - Kolom adalah seluruh field EXIF. Sub-struct (mis. DigitalCamera,
%         GPSInfo) diratakan menjadi kolom berawalan 'DigitalCamera_' dst.
%       - Kolom nama berkas (File / Filename / SourceFile) didahulukan.
%       - Field yang hanya ada di sebagian berkas diisi NaN (kolom numerik)
%         atau "" (kolom teks). Kolom bertipe campuran disimpan sebagai teks.

    util = pivprep.util.utilities;
    n = numel(metaList);

    if n == 0
        exif = table(); %#ok<NASGU>
        save(outPath, 'exif');
        return;
    end

    % --- Ratakan setiap struct EXIF ---
    flat = cell(n, 1);
    for i = 1:n
        flat{i} = util.flattenStruct(metaList{i}, '');
    end

    % --- Union nama field, urutan pertama-terlihat ---
    fields = {};
    for i = 1:n
        fn  = fieldnames(flat{i});
        new = fn(~ismember(fn, fields));
        fields = [fields; new(:)]; %#ok<AGROW>
    end

    % --- Dahulukan kolom nama berkas ---
    priority = {'File', 'Filename', 'SourceFile'};
    for p = numel(priority):-1:1
        idx = find(strcmp(fields, priority{p}), 1);
        if ~isempty(idx)
            fields = [fields(idx); fields([1:idx-1, idx+1:end])];
        end
    end

    % --- Bangun tabel kolom demi kolom ---
    exif = table();
    for f = 1:numel(fields)
        fld = fields{f};

        % Numerik hanya jika SEMUA nilai yang ada berupa skalar numerik.
        allNum = true;
        for i = 1:n
            if isfield(flat{i}, fld)
                v = flat{i}.(fld);
                if ~(isnumeric(v) && isscalar(v))
                    allNum = false;
                    break;
                end
            end
        end

        if allNum
            col = nan(n, 1);
            for i = 1:n
                if isfield(flat{i}, fld)
                    col(i) = double(flat{i}.(fld));
                end
            end
        else
            col = strings(n, 1);
            for i = 1:n
                if isfield(flat{i}, fld)
                    col(i) = util.valueToStr(flat{i}.(fld));
                end
            end
        end

        exif.(fld) = col;
    end

    save(outPath, 'exif');
end
