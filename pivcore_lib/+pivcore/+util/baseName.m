function b = baseName(p)
%BASENAME  Nama berkas tanpa folder & tanpa ekstensi (fileparts arg ke-2).
%   Kosong -> ''. Sebelumnya disalin sebagai i_baseName di PABSA1a/3/3a.
    if isempty(p), b = ''; else, [~, b] = fileparts(p); end
end
