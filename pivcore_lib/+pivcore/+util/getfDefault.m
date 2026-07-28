function v = getfDefault(s, f, def)
%GETFDEFAULT  Ambil field f dari struct s; bila s bukan struct / field absen /
%   nilainya kosong -> kembalikan def. Pembaca struct yang aman & ringkas.
%   Sebelumnya disalin sebagai i_getf di PABSA1a/1b.
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
end
