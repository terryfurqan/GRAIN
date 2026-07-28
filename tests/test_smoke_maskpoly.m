function test_smoke_maskpoly()
%TEST_SMOKE_MASKPOLY  Fase C: engine maskPoly + sidecar v2_poly + decode.
%   A. interpVerts: 2-keyframe linear + N-keyframe + clamp luar-rentang.
%   B. applyMask: poly2mask isi fill; no-op saat nonaktif; RGB aman.
%   C. normalize: buang polygon dgn K vertex tak seragam.
%   D. sidecar v2_poly round-trip TANPA merusak v1_rect (kotak).
%
%   Jalankan: grain_setup; test_smoke_maskpoly   (SELALU R2025b)
    fprintf('\n=== TEST maskPoly (Fase C) ===\n');
    grain_setup();
    MP = 'pivanalyzemat.core.maskPoly';
    assert(~isempty(which(MP)), 'maskPoly tak di-path');

    % ===== A. interpVerts =====
    sq = @(cx,cy,r) [cx-r cy-r; cx+r cy-r; cx+r cy+r; cx-r cy+r];  % 4-vertex square
    kf1 = struct('frame_index',1, 'vertices', sq(20,20,10));
    kfN = struct('frame_index',11,'vertices', sq(40,20,10));
    pg  = struct('enabled',true, 'fill',[], 'keyframes',[kf1 kfN]);
    V1  = pivanalyzemat.core.maskPoly.interpVerts(pg, 1, 11);
    V6  = pivanalyzemat.core.maskPoly.interpVerts(pg, 6, 11);
    V11 = pivanalyzemat.core.maskPoly.interpVerts(pg, 11, 11);
    assert(isequal(V1, sq(20,20,10)), 'interp f1 salah');
    assert(isequal(V11, sq(40,20,10)), 'interp fN salah');
    assert(max(abs(V6(:) - reshape(sq(30,20,10),[],1))) < 1e-9, 'interp tengah (cx=30) salah');
    % clamp luar rentang
    V0  = pivanalyzemat.core.maskPoly.interpVerts(pg, -5, 11);
    V20 = pivanalyzemat.core.maskPoly.interpVerts(pg, 99, 11);
    assert(isequal(V0, sq(20,20,10)) && isequal(V20, sq(40,20,10)), 'clamp luar-rentang salah');
    fprintf('  [A] interpVerts 2-keyframe + clamp OK.\n');

    % N-keyframe (3): 1 -> 6 -> 11
    kfMid = struct('frame_index',6, 'vertices', sq(100,100,5));
    pg3 = struct('enabled',true,'fill',[], 'keyframes',[kf1 kfMid kfN]);
    Vm = pivanalyzemat.core.maskPoly.interpVerts(pg3, 6, 11);
    assert(isequal(Vm, sq(100,100,5)), 'N-keyframe: keyframe tengah tak tepat');
    fprintf('  [A] interpVerts N-keyframe OK.\n');

    % ===== B. applyMask =====
    poly = struct('enabled',true, 'fill',255, 'polygons', pg);
    img = uint8(zeros(60,80));
    out = pivanalyzemat.core.maskPoly.applyMask(img, poly, 1, 11);
    % region sekitar (20,20) harus terisi
    assert(out(20,20) == 255, 'applyMask tak mengisi polygon');
    assert(out(1,80) == 0, 'applyMask bocor ke luar polygon');
    % no-op saat nonaktif
    polyOff = poly; polyOff.enabled = false;
    out2 = pivanalyzemat.core.maskPoly.applyMask(img, polyOff, 1, 11);
    assert(isequal(out2, img), 'nonaktif harus no-op');
    % RGB aman
    rgb = uint8(zeros(60,80,3));
    outC = pivanalyzemat.core.maskPoly.applyMask(rgb, poly, 1, 11);
    assert(outC(20,20,1)==255 && outC(20,20,3)==255, 'RGB fill salah');
    fprintf('  [B] applyMask fill/no-op/RGB OK.\n');

    % ===== C. normalize buang K tak seragam =====
    bad = struct('enabled',true,'fill',[], 'keyframes', ...
        [struct('frame_index',1,'vertices',sq(10,10,5)), ...
         struct('frame_index',5,'vertices',[10 10; 20 10; 15 20])]);  % K=4 vs K=3
    pn = pivanalyzemat.core.maskPoly.normalize(struct('enabled',true,'fill',255,'polygons',bad));
    % polygon punya 1 keyframe valid (yg pertama), keyframe K-beda dibuang.
    assert(pn.enabled && numel(pn.polygons)==1, 'normalize polygon salah');
    assert(numel(pn.polygons(1).keyframes)==1, 'keyframe K-beda tak dibuang');
    fprintf('  [C] normalize buang keyframe K tak seragam OK.\n');

    % ===== D. sidecar v2_poly round-trip + jaga v1_rect =====
    troot = fullfile(tempdir, sprintf('maskpoly_%d', feature('getpid')));
    if isfolder(troot), rmdir(troot,'s'); end; mkdir(troot);
    cleaner = onCleanup(@() i_rmdir(troot)); %#ok<NASGU>
    fakeMat = fullfile(troot, 'exp.mat');
    % tulis kotak (v1_rect) dulu
    rect = struct('enabled',true,'fill',255,'boxes', ...
        struct('rect_first',[5 5 10 10],'rect_last',[8 6 12 11],'frame_first',1,'frame_last',11));
    assert(pivanalyzemat.core.maskSidecar.write(fakeMat, rect), 'tulis v1_rect gagal');
    % tulis polygon (v2_poly) — TAK boleh hapus v1_rect
    assert(pivanalyzemat.core.maskSidecar.writePoly(fakeMat, poly), 'tulis v2_poly gagal');
    r2 = pivanalyzemat.core.maskSidecar.read(fakeMat);
    p2 = pivanalyzemat.core.maskSidecar.readPoly(fakeMat);
    assert(~isempty(r2) && r2.enabled, 'v1_rect hilang setelah tulis v2_poly');
    assert(~isempty(p2) && p2.enabled && ~isempty(p2.polygons), 'v2_poly tak terbaca');
    % decode gabungan via applyMask masing-masing
    canvas = uint8(zeros(60,80));
    c1 = pivanalyzemat.core.maskRect.applyMask(canvas, r2, 1, 11);
    c2 = pivanalyzemat.core.maskPoly.applyMask(c1, p2, 1, 11);
    assert(c2(6,6)==255 && c2(20,20)==255, 'decode gabungan kotak+polygon salah');
    fprintf('  [D] sidecar v2_poly round-trip + jaga v1_rect + decode gabungan OK.\n');

    fprintf('=== LULUS ===\n');
end

function i_rmdir(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
