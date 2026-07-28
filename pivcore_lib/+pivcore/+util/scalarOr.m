function v = scalarOr(x, def)
%SCALAROR  Paksa x menjadi skalar numerik ganda (ambil elemen pertama, cast
%   double). Bila kosong/non-numerik -> def (default NaN). Cegah error
%   "&&/min butuh skalar" bila guidata kembalikan field non-skalar (mis. state
%   setengah-jadi saat callback bertumpuk).
%
%   Penyatuan i_scalar (PABSA1a/1b/3/3a). Versi 1a/1b melakukan double(x(1));
%   versi 3/3a memakai x(1) mentah — disatukan ke double(x(1)) (superset aman:
%   hasil numerik double untuk semua pemanggil; logical/int ikut ter-cast).
    if nargin < 2, def = NaN; end
    if isnumeric(x) && ~isempty(x), v = double(x(1)); else, v = def; end
end
