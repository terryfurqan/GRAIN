function data = syntheticDataset()
%SYNTHETICDATASET  Dataset PIVLAB sintetik RINGAN (1 frame, grid kecil).
%
%   Dipakai oleh alur boot folder-first PIVTerry saat app dibuka di tab Index
%   TANPA memuat eksperimen sungguhan. Alih-alih placeholder kosong (yang
%   menyulitkan redraw karena tak punya koordinat), kita berikan dataset
%   mungil yang berbentuk PERSIS seperti keluaran PIVLAB sehingga seluruh
%   jalur render (initAxisLimits/redraw/autoInit) berjalan normal tanpa
%   perlakuan khusus.
%
%   Ukuran sengaja kecil (grid ~16x16, 1 frame) -> ringan, instan, dan tidak
%   membebani memori. Pola kecepatan = pusaran lembut agar tampak masuk akal.
%
%   data = pivcore.data.syntheticDataset()
%       Mengembalikan struct hasil pivcore.data.buildDataset atas struct
%       PIVLAB sintetik (jadi kontrak field-nya identik dataset asli).

    % --- Grid kecil ---
    nx = 16; ny = 16;
    [X, Y] = meshgrid(linspace(0, 150, nx), linspace(0, 150, ny));

    % --- Medan kecepatan: pusaran (vortex) lembut di tengah ---
    cx = mean(X(:)); cy = mean(Y(:));
    U  = -(Y - cy);
    V  =  (X - cx);
    sc = 0.05;
    U  = U * sc;
    V  = V * sc;
    typev = ones(ny, nx);   % semua vektor valid (typevector PIVLAB: 1 = ada)

    % --- Susun struct PIVLAB sintetik (cell of 2D grid, 1 frame) ---
    S = struct();
    S.x = {X};
    S.y = {Y};
    S.u_original = {U};
    S.v_original = {V};
    S.u_filtered = {U};
    S.v_filtered = {V};
    S.u_smoothed = {U};
    S.v_smoothed = {V};
    S.typevector_original = {typev};
    S.typevector_filtered = {typev};
    S.calu  = 1;
    S.calv  = 1;
    S.calxy = 1;
    S.units = '[px] respectively [frame]';

    % --- Lewatkan ke buildDataset agar kontrak field identik dataset asli ---
    data = pivcore.data.buildDataset(S);
end
