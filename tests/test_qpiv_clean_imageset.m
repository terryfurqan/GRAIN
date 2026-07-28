function test_qpiv_clean_imageset()
%TEST_QPIV_CLEAN_IMAGESET  Frame MATI (mesin berhenti) dibuang UTUH — termasuk
%   gambar mati PERTAMA & zona mati di AWAL (frame-1). Regresi bug: mode
%   'consecutive' dulu hanya buang gambar ke-2 pasangan (drop(k+1)) sehingga
%   frame-1 di zona mati awal LOLOS & muncul lagi di GRAINMASK.
%
%   Uji engine bersama batchpivprep2.io.qpivCleanImageSet:
%     A. consecutive, zona mati AWAL (pasangan 1..3) -> gambar 1..4 dibuang.
%     B. consecutive, zona mati TENGAH -> kedua sisi tiap pasangan dibuang.
%     C. consecutive, tanpa ignore -> semua gambar lolos, dropped kosong.
%     D. pairs -> kedua gambar tiap pasangan mati dibuang.
%     E. kept & dropped PARTISI sempurna (tak tumpang-tindih, gabung=semua).
%     F. ignore sbg INDEKS maupun LOGICAL menghasilkan sama.
%
%   Jalankan: grain_setup; test_qpiv_clean_imageset   (SELALU R2025b)
    fprintf('\n=== TEST qpivCleanImageSet (frame mati dibuang utuh) ===\n');
    grain_setup();
    F = 'batchpivprep2.io.qpivCleanImageSet';
    assert(~isempty(which(F)), 'engine qpivCleanImageSet tak di-path');

    % 6 gambar -> 5 pasangan consecutive: (1,2)(2,3)(3,4)(4,5)(5,6).
    g = @(k) sprintf('img%02d.jpg', k);
    names = arrayfun(g, 1:6, 'uni', 0);
    fn1 = names(1:5); fn2 = names(2:6);

    % ===== A. zona mati AWAL: pasangan 1,2,3 mati -> gambar 1,2,3,4 buang =====
    [kA, dA] = batchpivprep2.io.qpivCleanImageSet(fn1, fn2, 'consecutive', [1 2 3]);
    assert(isequal(sort(dA), {g(1),g(2),g(3),g(4)}), ...
        'A: dropped salah: %s', strjoin(dA,','));
    assert(isequal(kA, {g(5),g(6)}), 'A: kept salah: %s', strjoin(kA,','));
    % INTI keluhan: gambar-1 (frame mati pertama) HARUS ikut terbuang.
    assert(~any(strcmpi(kA, g(1))), 'A: frame-1 (mati) MASIH lolos — BUG!');
    fprintf('  [A] zona mati awal: gambar 1..4 dibuang, frame-1 tak lolos OK.\n');

    % ===== B. zona mati TENGAH: pasangan 3,4 mati -> gambar 3,4,5 buang =====
    [kB, dB] = batchpivprep2.io.qpivCleanImageSet(fn1, fn2, 'consecutive', [3 4]);
    assert(isequal(sort(dB), {g(3),g(4),g(5)}), 'B: dropped salah: %s', strjoin(dB,','));
    assert(isequal(kB, {g(1),g(2),g(6)}), 'B: kept salah: %s', strjoin(kB,','));
    fprintf('  [B] zona mati tengah: kedua sisi pasangan dibuang OK.\n');

    % ===== C. tanpa ignore =====
    [kC, dC] = batchpivprep2.io.qpivCleanImageSet(fn1, fn2, 'consecutive', []);
    assert(isequal(kC, names) && isempty(dC), 'C: tanpa-ignore harus lolos semua');
    fprintf('  [C] tanpa ignore: semua lolos, dropped kosong OK.\n');

    % ===== D. pairs: 6 gambar -> 3 pasangan (1,2)(3,4)(5,6); pasangan 2 mati =====
    fp1 = {g(1),g(3),g(5)}; fp2 = {g(2),g(4),g(6)};
    [kD, dD] = batchpivprep2.io.qpivCleanImageSet(fp1, fp2, 'pairs', 2);
    assert(isequal(sort(dD), {g(3),g(4)}), 'D: pairs dropped salah: %s', strjoin(dD,','));
    assert(isequal(kD, {g(1),g(2),g(5),g(6)}), 'D: pairs kept salah');
    fprintf('  [D] pairs: kedua gambar pasangan mati dibuang OK.\n');

    % ===== E. partisi sempurna (consecutive, ignore campuran) =====
    [kE, dE] = batchpivprep2.io.qpivCleanImageSet(fn1, fn2, 'consecutive', [1 5]);
    allNames = sort(names);
    union_ = sort([kE, dE]);
    assert(isequal(union_, allNames), 'E: kept+dropped != semua gambar');
    assert(isempty(intersect(kE, dE)), 'E: kept & dropped tumpang-tindih');
    fprintf('  [E] kept & dropped partisi sempurna OK.\n');

    % ===== F. indeks == logical =====
    logIg = false(1,5); logIg([1 2 3]) = true;
    [kF, dF] = batchpivprep2.io.qpivCleanImageSet(fn1, fn2, 'consecutive', logIg);
    assert(isequal(kF, kA) && isequal(sort(dF), sort(dA)), 'F: logical != indeks');
    fprintf('  [F] ignore indeks == logical OK.\n');

    fprintf('=== LULUS ===\n');
end
