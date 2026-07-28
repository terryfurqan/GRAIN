function img = decodeBlob(bytes, ext)
%DECODEBLOB  Decode blob byte (uint8) -> citra lewat berkas sementara + imread.
%   Primitif murni: tulis bytes ke tempname.<ext>, imread, hapus (onCleanup).
%   Kembalikan [] bila bytes kosong / gagal tulis / imread error.
%
%   img = pivcore.util.decodeBlob(bytes, ext)   % ext mis. 'jpg' / 'png'
%
%   ext default 'jpg' bila tak diberi. Pemanggil yang punya cache/ekstensi
%   bervariasi (mis. PABSA1a i_frameImage) urus itu di luar; ini hanya inti
%   tulis->baca->hapus. Sebelumnya disalin sebagai i_decodeImg/i_decodePNG.
    img = [];
    if isempty(bytes), return; end
    if nargin < 2 || isempty(ext), ext = 'jpg'; end
    ext = regexprep(char(ext), '^\.', '');           % buang titik depan bila ada
    tmp = [tempname '.' ext];
    fid = fopen(tmp,'wb'); if fid < 0, return; end
    fwrite(fid, bytes, 'uint8'); fclose(fid);
    cu = onCleanup(@() i_safeDelete(tmp)); %#ok<NASGU>
    try, img = imread(tmp); catch, img = []; end
end

function i_safeDelete(p)
    try, if isfile(p), delete(p); end, catch, end
end
