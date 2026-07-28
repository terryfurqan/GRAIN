function M = computeMagnitude(U, V)
%COMPUTEMAGNITUDE  Hitung magnitude kecepatan dari komponen u,v.
%
%   M = pivcore.data.computeMagnitude(U, V)
%
%   Mengembalikan sqrt(U.^2 + V.^2) dengan toleransi NaN. Jika U atau V
%   kosong, atau ukurannya tidak sama, fungsi mengembalikan [].
%
%   Fungsi ini disediakan agar perhitungan magnitude dilakukan secara
%   konsisten oleh modul tabModif saat menyederhanakan berkas MAT, tanpa
%   bergantung pada bidang velocity_magnitude yang tersimpan di berkas
%   PIVLAB asli.

    M = [];
    if isempty(U) || isempty(V), return; end
    if ~isequal(size(U), size(V)), return; end
    M = sqrt(U.^2 + V.^2);
end
