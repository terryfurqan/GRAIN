function test_smoke_pabmask_jpgmode()
%TEST_SMOKE_PABMASK_JPGMODE  Fase B: urutan PAB0->PABMASK->PAB1.
%   A. Engine progres terpadu: setmask/getmask round-trip.
%   B. PABMASK mode JPG: auto-deteksi 'jpg' (folder foto, bukan .mat), scan
%      hanya frame LOLOS QPIV, baca/tulis resep ke progres terpadu (headless).
%   C. maskSidecar: resep dari progres -> sidecar '<matbase>_mask.json' terbaca
%      maskRect (mensimulasikan i_writeMaskSidecars PAB1) & decode benar.
%
%   Jalankan: pab_setup; test_smoke_pabmask_jpgmode   (SELALU R2025b)
    fprintf('\n=== TEST PABMASK JPG-mode (Fase B) ===\n');
    pab_setup();
    assert(~isempty(which('PABMASK')), 'PABMASK tak di-path');

    troot = fullfile(tempdir, sprintf('pabmask_jpg_%d', feature('getpid')));
    if isfolder(troot), rmdir(troot,'s'); end
    mkdir(troot);
    cleaner = onCleanup(@() i_rmdir(troot)); %#ok<NASGU>

    % --- 1 exp, 8 foto JPG bertekstur (unpadded) ---
    expA = fullfile(troot,'exp_A'); mkdir(expA);
    nImg = 8; base = i_texture(200, 260);
    for k = 1:nImg
        imwrite(base, fullfile(expA, sprintf('f_%d.jpg', k)));
    end

    % --- Progress QPIV: qpiv_done + kept_names (buang f_2.jpg -> 7 lolos) ---
    pf = fullfile(troot, 'PAB0_progress.mat');
    PIVlab_automasi_progress('setfile', pf);
    restoreProg = onCleanup(@() PIVlab_automasi_progress('resetfile')); %#ok<NASGU>
    keptNames = arrayfun(@(k) sprintf('f_%d.jpg',k), setdiff(1:nImg,2), 'uni',0);
    eA = PIVlab_automasi_progress('empty');
    eA.expdir = expA; eA.key = PIVlab_automasi_progress('key', expA);
    eA.sequencing='consecutive'; eA.skip=0; eA.qpiv_done=true;
    eA.qpiv_nframes = nImg-1; eA.qpiv_kept_names = keptNames;   % 7 lolos
    PIVlab_automasi_progress('set', eA);

    % ================= A. Engine setmask/getmask =================
    box = struct('rect_first',[10 10 40 30],'rect_last',[15 12 44 33], ...
        'frame_first',1,'frame_last',7);
    recipe = struct('enabled',true,'fill',255,'boxes',box);
    PIVlab_automasi_progress('setmask', expA, recipe);
    got = PIVlab_automasi_progress('getmask', expA);
    assert(~isempty(got) && isstruct(got), 'getmask kosong setelah setmask');
    gm = pivanalyzemat.core.maskRect.normalize(got);
    assert(gm.enabled && ~isempty(gm.boxes), 'resep progres tak valid');
    assert(isequal(round(gm.boxes(1).rect_first), [10 10 40 30]), 'rect_first progres salah');
    % QPIV kept_names TETAP ada setelah setmask (tak tertimpa).
    e2 = PIVlab_automasi_progress('get', expA);
    assert(numel(e2.qpiv_kept_names)==7, 'setmask merusak qpiv_kept_names');
    fprintf('  [A] setmask/getmask round-trip OK; qpiv_kept_names utuh.\n');

    % Kosongkan lagi (nonaktif) -> getmask []
    PIVlab_automasi_progress('setmask', expA, []);
    assert(isempty(PIVlab_automasi_progress('getmask', expA)), 'setmask([]) tak mengosongkan');
    % kembalikan resep utk bagian B/C
    PIVlab_automasi_progress('setmask', expA, recipe);

    % ================= B. PABMASK mode JPG headless =================
    set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible','on')); %#ok<NASGU>
    PABMASK(troot);
    f = findall(0,'Type','figure','-regexp','Name','^PAB Masking');
    if numel(f) > 1, f = f(1); end
    assert(~isempty(f), 'figure PABMASK tak terbentuk');
    closeFig = onCleanup(@() i_closeFig(f)); %#ok<NASGU>
    h = guidata(f);

    assert(strcmp(h.srcMode,'jpg'), 'srcMode harus jpg (folder foto, bukan .mat)');
    iA = find(strcmp({h.list.name}, 'exp_A'), 1);
    assert(~isempty(iA), 'exp_A tak terpindai di mode jpg');
    % Hanya frame LOLOS QPIV: 7 (f_2 dibuang).
    assert(h.list(iA).nFrames == 7, sprintf('nFrames=%d (harus 7 lolos QPIV)', h.list(iA).nFrames));
    assert(numel(h.list(iA).files) == 7, 'files tak tersaring QPIV');
    assert(~any(strcmpi(h.list(iA).files,'f_2.jpg')), 'frame mati f_2 masih ada di daftar');
    % Resep dari progres terbaca -> baris enabled + rectFirst terisi.
    assert(h.list(iA).enabled, 'resep progres tak termuat (enabled=false)');
    assert(~isempty(h.list(iA).rectFirst), 'rectFirst kosong padahal resep ada');
    fprintf('  [B] PABMASK jpg: scan lolos-QPIV (7 frame), resep progres termuat.\n');

    % ================= C. Sidecar dari resep (simulasi PAB1) =================
    % maskSidecar.write(matPath, recipe) — sama seperti i_writeMaskSidecars PAB1.
    fakeMat = fullfile(troot, 'exp_A.mat');   % path .mat semu (tak perlu ada)
    ok = pivanalyzemat.core.maskSidecar.write(fakeMat, recipe);
    assert(ok, 'maskSidecar.write gagal');
    sp = pivanalyzemat.core.maskSidecar.path(fakeMat);
    assert(isfile(sp), 'sidecar json tak tertulis');
    back = pivanalyzemat.core.maskSidecar.read(fakeMat);
    assert(~isempty(back) && back.enabled, 'sidecar tak terbaca balik');
    % Decode: kotak terisi fill di frame pertama.
    img = uint8(zeros(60,80));
    out = pivanalyzemat.core.maskRect.applyMask(img, back, 1, 7);
    bb = pivanalyzemat.core.maskRect.interpRect(back.boxes(1), 1, 7, 80, 60);
    assert(~isempty(bb), 'bbox frame-1 kosong');
    reg = out(bb(2):bb(4), bb(1):bb(3));
    assert(all(reg(:)==255), 'applyMask tak mengisi kotak dgn fill');
    fprintf('  [C] sidecar <matbase>_mask.json tertulis+terbaca; applyMask benar.\n');

    fprintf('=== LULUS ===\n');
end

% ---------------------------------------------------------------------
function img = i_texture(H, W)
    [xx,yy] = meshgrid(1:W, 1:H);
    img = uint8(128 + 60*sin(xx/7) .* cos(yy/9));
end
function i_closeFig(f)
    try, if all(ishghandle(f)), delete(f); end, catch, end
end
function i_rmdir(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
