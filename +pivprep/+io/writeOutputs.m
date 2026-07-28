function writeOutputs(img, outDirs, baseName, cfg, exifMeta)
%WRITEOUTPUTS  Tulis dua keluaran citra per frame: RAW + GS.
%
%   pivprep.io.writeOutputs(img, outDirs, baseName, cfg, exifMeta)
%
%   INPUT:
%       img        uint8 HxWxC, gambar hasil pemrosesan
%       outDirs    struct folder keluaran:
%           .raw   folder berkas RAW (resolusi penuh)
%           .gs    folder berkas GS  (resolusi diperkecil)
%       baseName   nama dasar (tanpa ekstensi)
%       cfg        struct konfigurasi:
%           .rawFormat   'jpg' | 'png' | 'tif'
%           .rawQuality  kualitas JPEG 1-100 (untuk rawFormat='jpg')
%           .gsScale     skala GS (0..1); 1 berarti tidak resize
%           .gsQuality   kualitas JPEG GS 1-100
%       exifMeta   struct hasil pivprep.io.readExifData (boleh kosong)
%
%   KELUARAN BERKAS:
%       <outDirs.raw>/<baseName>-RAW.<ext>   keluaran resolusi penuh
%       <outDirs.gs>/<baseName>-GS.jpg       keluaran resolusi diperkecil
%
%   PRESERVASI EXIF (selalu aktif, tidak opsional):
%   Metadata EXIF SELALU disisipkan selengkap mungkin ke berkas RAW
%   (komentar JPEG / deskripsi PNG-TIFF). Sebagai cadangan bila embed
%   gagal/terbatas, seluruh EXIF juga dikumpulkan menjadi satu tabel
%   EXIF/EXIF.mat di tingkat batch (lihat pivprep.io.writeExifTable).

    % Komentar EXIF lengkap untuk disisipkan ke berkas citra.
    exifComment = local_buildComment(exifMeta, baseName);

    % --- RAW (resolusi penuh) ---
    rawExt = lower(cfg.rawFormat);
    switch rawExt
        case {'jpg', 'jpeg'}
            rawPath = fullfile(outDirs.raw, [baseName '-RAW.jpg']);
            args = {'jpg', 'Quality', cfg.rawQuality};
            if ~isempty(exifComment)
                args = [args, {'Comment', exifComment}];
            end
            imwrite(img, rawPath, args{:});

        case 'png'
            rawPath = fullfile(outDirs.raw, [baseName '-RAW.png']);
            if ~isempty(exifComment)
                imwrite(img, rawPath, 'png', 'Description', exifComment);
            else
                imwrite(img, rawPath, 'png');
            end

        case {'tif', 'tiff'}
            rawPath = fullfile(outDirs.raw, [baseName '-RAW.tif']);
            if ~isempty(exifComment)
                imwrite(img, rawPath, 'tif', 'Compression', 'lzw', ...
                    'Description', exifComment);
            else
                imwrite(img, rawPath, 'tif', 'Compression', 'lzw');
            end

        otherwise
            error('pivprep:writeOutputs:format', ...
                'Format RAW tidak dikenali: %s', rawExt);
    end

    % --- GS (resolusi diperkecil) ---
    if cfg.gsScale > 0 && cfg.gsScale < 1
        gsImg = imresize(img, cfg.gsScale, 'lanczos3');
    else
        gsImg = img;
    end
    gsPath = fullfile(outDirs.gs, [baseName '-GS.jpg']);
    if ~isempty(exifComment)
        imwrite(gsImg, gsPath, 'jpg', 'Quality', cfg.gsQuality, ...
            'Comment', exifComment);
    else
        imwrite(gsImg, gsPath, 'jpg', 'Quality', cfg.gsQuality);
    end
end


function cmt = local_buildComment(exifMeta, baseName)
%LOCAL_BUILDCOMMENT  Serialisasi seluruh EXIF menjadi satu string komentar.
%   Bentuk: 'PIVPrep EXIF | proc=<waktu> | key=val | key=val | ...'
    if isempty(exifMeta) || ~isstruct(exifMeta) || isempty(fieldnames(exifMeta))
        cmt = '';
        return;
    end
    util = pivprep.util.utilities;
    flat = util.flattenStruct(exifMeta, '');
    fn   = fieldnames(flat);
    parts = cell(numel(fn), 1);
    for i = 1:numel(fn)
        parts{i} = sprintf('%s=%s', fn{i}, char(util.valueToStr(flat.(fn{i}))));
    end
    body = strjoin(parts, ' | ');
    cmt  = sprintf('PIVPrep EXIF | file=%s | proc=%s | %s', ...
        baseName, ...
        char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        body);
end
