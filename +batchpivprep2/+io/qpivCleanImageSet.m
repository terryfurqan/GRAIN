function [kept, dropped] = qpivCleanImageSet(fn1, fn2, seq, ig)
%QPIVCLEANIMAGESET  Petakan pasangan QPIV + vektor ignore -> daftar gambar
%   TERSISA (kept) & DIBUANG (dropped), pada urutan QPIV yang BENAR.
%
%   [kept, dropped] = batchpivprep2.io.qpivCleanImageSet(fn1, fn2, seq, ig)
%
%   fn1,fn2 : cellstr nama gambar per-PASANGAN (fn1{k}=gambar-1, fn2{k}=gambar-2).
%   seq     : 'consecutive' (default) | 'pairs'.
%   ig      : logical/indeks pasangan yang DIABAIKAN (frame MATI: |V|≈0).
%
%   SEMANTIK (detektor exclusion GRAIN0 = FRAME MATI, mesin berhenti): bila
%   pasangan (a,b) mati, KEDUA gambar pembentuknya (a DAN b) diam -> keduanya
%   dibuang. Ini memperbaiki bug lama di mana mode 'consecutive' hanya membuang
%   gambar ke-2 pasangan (drop(k+1)) -> gambar MATI PERTAMA / gambar di zona
%   mati AWAL (frame-1) LOLOS & muncul lagi di hilir (GRAINMASK).
%
%   Daftar gambar disusun:
%     consecutive : names = [fn1(1:N); fn2(N)]  (N+1 gambar unik berurutan),
%                   pasangan k -> drop(k) & drop(k+1).
%     pairs       : names = selang-seling fn1/fn2 (2N gambar),
%                   pasangan k -> drop(2k-1) & drop(2k).
%
%   Keluaran basename (nama+ekstensi) saja, kebal beda path antar-modul.
    kept = {}; dropped = {};
    if isempty(fn1) || isempty(fn2); return; end
    if nargin < 3 || isempty(seq); seq = 'consecutive'; end
    fn1 = fn1(:); fn2 = fn2(:);
    N = min(numel(fn1), numel(fn2));
    ig = i_asMask(ig, N);

    if strcmpi(seq, 'pairs')
        names = cell(2*N, 1); names(1:2:end) = fn1(1:N); names(2:2:end) = fn2(1:N);
        drop = false(2*N, 1);
        for k = find(ig(1:N)); drop(2*k-1) = true; drop(2*k) = true; end
    else
        names = [fn1(1:N); fn2(N)];              % N+1 gambar unik
        drop = false(N+1, 1);
        for k = find(ig(1:N)); drop(k) = true; drop(k+1) = true; end   % KEDUA sisi
    end
    kept    = i_basenames(names(~drop));
    dropped = i_basenames(names(drop));
end

function m = i_asMask(ig, N)
%I_ASMASK  Normalkan ignore -> logical [1 x N]. Terima logical ATAU indeks.
    m = false(1, N);
    if isempty(ig); return; end
    if islogical(ig)
        v = ig(:)'; L = min(N, numel(v)); m(1:L) = v(1:L);
    else
        idx = round(double(ig(:)')); idx = idx(idx >= 1 & idx <= N);
        m(idx) = true;
    end
end

function c = i_basenames(x)
    c = {};
    if isempty(x); return; end
    if ischar(x); x = {x}; end
    x = x(:)'; c = cell(1, numel(x));
    for i = 1:numel(x)
        [~, nm, ext] = fileparts(char(x{i})); c{i} = [nm ext];
    end
end
