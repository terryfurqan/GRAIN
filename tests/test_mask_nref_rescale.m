function test_mask_nref_rescale()
%TEST_MASK_NREF_RESCALE  Resep masking KEBAL beda jumlah frame antar-modul.
%
%   Latar: GRAINMASK menetapkan indeks acuan kotak/keyframe pada n_ref = jumlah
%   frame LOLOS QPIV saat resep dibuat. MAT PREP yang diproduksi GRAIN1 bisa punya
%   nFrames (N) BERBEDA (pemetaan skip/nama sedikit lain). Tanpa penskalaan,
%   frame_last=n_ref di-clamp -> interpolasi rect_first->rect_last tak pernah
%   tercapai (kotak macet di awal). Fix: field n_ref di resep -> decoder skala
%   indeks acuan ke N aktual: fN = 1 + (f-1)*(N-1)/(n_ref-1).
%
%   Uji:
%     A. maskRect.interpRect dgn n_ref != N -> posisi RELATIF terjaga.
%     B. maskRect.applyMask via struct m.n_ref (jalur produksi).
%     C. Backward-compat: TANPA n_ref -> perilaku lama (absolut) persis.
%     D. maskPoly.interpVerts dgn n_ref != N.
%     E. Round-trip sidecar mempertahankan n_ref (rect & poly).
%
%   Jalankan: grain_setup; test_mask_nref_rescale   (SELALU R2025b)
    fprintf('\n=== TEST mask n_ref rescale ===\n');
    grain_setup();
    MR = 'pivanalyzemat.core.maskRect';
    MP = 'pivanalyzemat.core.maskPoly';
    assert(~isempty(which(MR)) && ~isempty(which(MP)), 'engine mask tak di-path');

    tol = 1e-9;

    % ===== A. interpRect: n_ref=11, decode di N=6 =====
    % Kotak bergerak dari x=0 (frame acuan 1) ke x=100 (frame acuan 11).
    box = struct('rect_first',[0 0 10 10], 'rect_last',[100 0 10 10], ...
        'frame_first',1, 'frame_last',11);
    % Di ruang n_ref=11: frame 6 = tengah (t=0.5) -> x1 ~ 50.
    % Di ruang N=6 TANPA skala: frame_last=11 > N -> pakai apa adanya, tapi decode
    % k hanya sampai 6 -> t=(6-1)/(11-1)=0.5 juga. Untuk membuat perbedaan JELAS,
    % pakai n_ref BESAR relatif N: n_ref=11, N=6, minta frame TERAKHIR (k=6=N).
    % Dgn skala: f1 -> 1+(11-1)*(6-1)/(11-1)=6 -> t di k=6 = 1 -> x1=100 (BENAR).
    % Tanpa skala: f1=11, k=6 -> t=(6-1)/(11-1)=0.5 -> x1=50 (SALAH, kotak belum
    % sampai ujung padahal ini frame terakhir MAT PREP).
    bbEndScaled  = pivanalyzemat.core.maskRect.interpRect(box, 6, 6, [], [], 11);
    bbEndNoScale = pivanalyzemat.core.maskRect.interpRect(box, 6, 6, [], []);
    assert(abs(bbEndScaled(1) - 100) < 0.5, ...
        sprintf('A: n_ref skala salah, x1=%.2f (harap ~100)', bbEndScaled(1)));
    assert(abs(bbEndNoScale(1) - 50) < 1.5, ...
        sprintf('A: tanpa-skala harusnya ~50, dapat %.2f', bbEndNoScale(1)));
    fprintf('  [A] interpRect n_ref!=N: frame akhir capai rect_last (x=%.0f) OK.\n', bbEndScaled(1));

    % titik tengah N=6 (k=3) dgn skala -> f di ruang n_ref = 1+(3-1)*(11-1)/(6-1)=5
    % t=(5-1)/(11-1)=0.4 -> x1=40.
    bbMid = pivanalyzemat.core.maskRect.interpRect(box, 3, 6, [], [], 11);
    assert(abs(bbMid(1) - 40) < 1.0, sprintf('A: tengah salah x1=%.2f (harap ~40)', bbMid(1)));
    fprintf('  [A] interpRect n_ref!=N titik tengah proporsional OK.\n');

    % ===== B. applyMask via struct.n_ref (jalur produksi nyata) =====
    m = pivanalyzemat.core.maskRect.normalize(struct('enabled',true,'fill',255, ...
        'n_ref',11, 'boxes', box));
    assert(isfield(m,'n_ref') && m.n_ref==11, 'B: n_ref tak dipertahankan normalize');
    img = uint8(zeros(30, 130));
    % frame terakhir MAT PREP (N=6): kotak harus berada di sekitar x=100..110.
    outEnd = pivanalyzemat.core.maskRect.applyMask(img, m, 6, 6);
    assert(outEnd(5, 105) == 255, 'B: applyMask n_ref frame akhir tak menutup x~105');
    assert(outEnd(5, 5)  == 0,   'B: applyMask n_ref bocor di x~5 (harusnya kosong di frame akhir)');
    fprintf('  [B] applyMask via m.n_ref menempel di posisi benar OK.\n');

    % ===== C. Backward-compat: resep TANPA n_ref = perilaku lama =====
    mOld = pivanalyzemat.core.maskRect.normalize(struct('enabled',true,'fill',255,'boxes',box));
    assert(mOld.n_ref==0, 'C: default n_ref harus 0 (tak diketahui)');
    % Tanpa n_ref, N=11 (sama dgn frame_last) -> interpolasi absolut normal.
    % Catatan: interpRect meng-clamp koordinat minimum ke 1 (indeks piksel),
    % jadi rect_first x=0 -> xa=1.
    bbA1  = pivanalyzemat.core.maskRect.interpRect(box, 1,  11, [], []);
    bbA11 = pivanalyzemat.core.maskRect.interpRect(box, 11, 11, [], []);
    assert(abs(bbA1(1)-1) < tol && abs(bbA11(1)-100) < 0.5, 'C: perilaku lama berubah!');
    fprintf('  [C] backward-compat (tanpa n_ref) perilaku lama utuh OK.\n');

    % ===== D. maskPoly.interpVerts dgn n_ref =====
    sq = @(cx,cy,r) [cx-r cy-r; cx+r cy-r; cx+r cy+r; cx-r cy+r];
    kf1 = struct('frame_index',1,  'vertices', sq(0,20,5));
    kfN = struct('frame_index',11, 'vertices', sq(100,20,5));
    pg  = struct('enabled',true,'fill',[], 'keyframes',[kf1 kfN]);
    % N=6, minta frame akhir (k=6) dgn n_ref=11 -> harus capai cx=100.
    Vend = pivanalyzemat.core.maskPoly.interpVerts(pg, 6, 6, 11);
    cxEnd = mean(Vend(:,1));
    assert(abs(cxEnd - 100) < 0.5, sprintf('D: poly n_ref frame akhir cx=%.2f (harap ~100)', cxEnd));
    % via applyMask+struct.n_ref
    poly = pivanalyzemat.core.maskPoly.normalize(struct('enabled',true,'fill',255, ...
        'n_ref',11, 'polygons', pg));
    assert(poly.n_ref==11, 'D: n_ref poly tak dipertahankan');
    imgP = uint8(zeros(40, 130));
    outP = pivanalyzemat.core.maskPoly.applyMask(imgP, poly, 6, 6);
    assert(outP(20, 100) == 255, 'D: applyMask poly n_ref frame akhir tak menutup cx~100');
    fprintf('  [D] maskPoly interpVerts+applyMask n_ref OK.\n');

    % ===== E. Round-trip sidecar mempertahankan n_ref =====
    troot = fullfile(tempdir, sprintf('masknref_%d', feature('getpid')));
    if isfolder(troot), rmdir(troot,'s'); end; mkdir(troot);
    cleaner = onCleanup(@() i_rmdir(troot)); %#ok<NASGU>
    fakeMat = fullfile(troot, 'exp.mat');
    assert(pivanalyzemat.core.maskSidecar.write(fakeMat, m), 'E: tulis v1_rect gagal');
    assert(pivanalyzemat.core.maskSidecar.writePoly(fakeMat, poly), 'E: tulis v2_poly gagal');
    r2 = pivanalyzemat.core.maskSidecar.read(fakeMat);
    p2 = pivanalyzemat.core.maskSidecar.readPoly(fakeMat);
    assert(~isempty(r2) && r2.n_ref==11, 'E: n_ref rect hilang lewat sidecar');
    assert(~isempty(p2) && p2.n_ref==11, 'E: n_ref poly hilang lewat sidecar');
    % decode dari sidecar di N=6 -> frame akhir tetap di ujung.
    canvas = uint8(zeros(40,130));
    c1 = pivanalyzemat.core.maskRect.applyMask(canvas, r2, 6, 6);
    assert(c1(5,105)==255, 'E: decode rect dari sidecar (n_ref) salah posisi');
    c2 = pivanalyzemat.core.maskPoly.applyMask(canvas, p2, 6, 6);
    assert(c2(20,100)==255, 'E: decode poly dari sidecar (n_ref) salah posisi');
    fprintf('  [E] sidecar round-trip mempertahankan n_ref + decode benar OK.\n');

    fprintf('=== LULUS ===\n');
end

function i_rmdir(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
