function meta = readExifData(filePath)
%READEXIFDATA  Ekstrak metadata EXIF/imfinfo dari berkas gambar.
%
%   meta = pivprep.io.readExifData(filePath)
%
%   OUTPUT:
%       meta    struct berisi seluruh field dari imfinfo,
%               ditambah SourceFile dan ExtractedAt.
%               Mengembalikan struct dengan field .Error jika gagal.
%
%   Catatan: MATLAB membaca EXIF lewat imfinfo. Sub-struktur seperti
%   DigitalCamera dan GPSInfo (jika ada) ikut terbaca.

    meta = struct();
    try
        info = imfinfo(filePath);
        info = info(1);
        flds = fieldnames(info);
        for k = 1:numel(flds)
            meta.(flds{k}) = info.(flds{k});
        end
        meta.SourceFile  = filePath;
        meta.ExtractedAt = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    catch ME
        meta.Error      = ME.message;
        meta.SourceFile = filePath;
    end
end
