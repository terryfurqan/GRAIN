function test_smoke_pab_step0a()
%TEST_SMOKE_PABSA_STEP0A  Smoke test PABSA0a (peta jitter) — TANPA GUI.
%
%   Memvalidasi inti yang dipakai PAB_step_0a (via lib/pivprepJitterGrid):
%     1. Pemindaian grid jalan, mengembalikan nCells = rows*cols + deret per-sel.
%     2. DISKRIMINASI: di urutan frame yg sebagian DIAM & sebagian BERGERAK,
%        sel di area diam punya metrik (RMS simpangan) jauh lebih kecil, dan
%        rekomendasi otomatis (best) jatuh di area DIAM.
%     3. KETERUKURAN: sel di blok polos (tanpa tekstur) ditandai TAK terukur,
%        sehingga TIDAK pernah jadi rekomendasi meski gerak ~0.
%     4. anchorPreset round-trip dari sel rekomendasi (kompatibel Step 1).
%     5. Jalur SURF tidak meledak.
%
%   Jalankan: pab_setup; test_smoke_pab_step0a
%   SELALU MATLAB R2025b.

    fprintf('\n=== SMOKE PABSA0a (PAB_step_0a) ===\n');
    pab_setup();
    assert(~isempty(which('pivprepJitterGrid')),               'pivprepJitterGrid tak di-path');
    assert(~isempty(which('pivprep.stab.buildReference')),     'engine stab tak di-path');
    assert(~isempty(which('PAB_step_0a')),                     'PAB_step_0a tak di-path');

    tdir = fullfile(tempdir, sprintf('pabsa0a_smoke_%d', feature('getpid')));
    if isfolder(tdir), rmdir(tdir,'s'); end
    mkdir(tdir);
    cleaner = onCleanup(@() i_rmdir(tdir));

    % --- 1. Frame sintetis: KIRI diam · KANAN bergerak · TENGAH polos ---
    H = 240; W = 480; nF = 10;
    [xx, yy] = meshgrid(1:W, 1:H);
    staticTex = uint8(120 + 80*sin(xx/9) .* cos(yy/7));    % tekstur diam global
    movTex    = uint8(120 + 80*sin(xx/6 + 1) .* cos(yy/8 - 0.5));

    files = cell(nF,1);
    for k = 1:nF
        img = staticTex;
        sh  = imtranslate(movTex, [(k-1)*0.8, (k-1)*0.4], 'FillValues', 120);
        img(:, 321:end) = sh(:, 321:end);                  % sepertiga KANAN bergerak
        img(120:235, 180:300) = 128;                       % blok TENGAH polos (flat)
        files{k} = fullfile(tdir, sprintf('f_%03d.png', k));
        imwrite(img, files{k});
    end
    refImg = imread(files{1});
    names  = cell(nF,1); for k=1:nF, [~,n,e]=fileparts(files{k}); names{k}=[n e]; end
    fprintf('  [1] %d frame sintetis (kiri diam, kanan gerak, tengah polos)\n', nF);

    % --- 2. Pindai grid (phase-corr, deterministik) --------------------
    opts = struct('rows',4,'cols',8,'method','phasecorr','rankMetric','rms');
    s = pivprepJitterGrid(names, refImg, tdir, opts);
    assert(s.nCells == 32, 'nCells salah');
    assert(isequal(size(s.DX), [32 s.nUse]), 'ukuran deret DX salah');
    assert(s.nUse == nF, 'nUse harus = nF (langkah 1, semua frame)');
    fprintf('  [2] pindai OK: %d sel, %d frame, %d terukur\n', ...
        s.nCells, s.nUse, sum(s.measurable));

    % --- 3. Diskriminasi diam vs bergerak ------------------------------
    cx = s.cellBox(:,1) + s.cellBox(:,3)/2;                 % pusat-x tiap sel
    leftMeas  = s.measurable & cx < 160;                    % area DIAM (kiri)
    rightMeas = s.measurable & cx > 320;                    % area GERAK (kanan)
    assert(any(leftMeas)  , 'tak ada sel terukur di area diam');
    assert(any(rightMeas) , 'tak ada sel terukur di area gerak');
    mL = mean(s.rmsOffset(leftMeas));
    mR = mean(s.rmsOffset(rightMeas));
    fprintf('  [3] RMS simpangan: kiri(diam)=%.3f  kanan(gerak)=%.3f px\n', mL, mR);
    assert(mL < mR - 0.5, sprintf('area diam tak lebih tenang (kiri %.2f >= kanan %.2f)', mL, mR));

    % Rekomendasi otomatis jatuh di area DIAM (kiri).
    assert(~isempty(s.best), 'tak ada rekomendasi best');
    assert(cx(s.best) < 160, sprintf('best (#%d, cx=%.0f) bukan di area diam', s.best, cx(s.best)));
    fprintf('  [3b] best = sel #%d (cx=%.0f, area diam) OK\n', s.best, cx(s.best));

    % --- 4. Keterukuran: blok polos tengah ditandai TAK terukur --------
    cy = s.cellBox(:,2) + s.cellBox(:,4)/2;
    flatCells = cx>190 & cx<290 & cy>140 & cy<225;          % di dalam blok polos
    assert(any(flatCells), 'tak ada sel yang jatuh di blok polos (cek geometri)');
    assert(all(~s.measurable(flatCells)), 'sel blok polos seharusnya TAK terukur');
    assert(s.best ~= find(flatCells,1), 'best tak boleh sel polos');
    fprintf('  [4] %d sel blok polos ditandai TAK terukur (reason cth: "%s")\n', ...
        sum(flatCells), s.reason{find(flatCells,1)});

    % --- 5. anchorPreset round-trip dari sel rekomendasi ---------------
    b = s.cellBox(s.best,:);
    pts = [b(1) b(2); b(1)+b(3) b(2); b(1)+b(3) b(2)+b(4); b(1) b(2)+b(4)];
    preset = batchpivprep2.io.anchorPreset.fromPoints( ...
        pts, size(refImg,[1 2]), s.method, refImg, 'anchor0a-smoke', files{1});
    outP = fullfile(tdir,'anchor0a.mat');
    batchpivprep2.io.anchorPreset.savePreset(preset, outP);
    p2 = batchpivprep2.io.anchorPreset.loadPreset(outP);
    assert(isequal(size(p2.anchorROI),[1 4]), 'anchorROI bukan [x y w h]');
    assert(max(abs(p2.anchorROI - b)) < 1.5, 'anchorROI round-trip melenceng');
    assert(isequal(p2.imgSize, size(refImg,[1 2])), 'imgSize round-trip salah');
    fprintf('  [5] anchorPreset save/load OK: ROI=[%.0f %.0f %.0f %.0f] method=%s\n', ...
        p2.anchorROI, p2.method);

    % --- 6. Jalur SURF tidak meledak -----------------------------------
    sS = pivprepJitterGrid(names, refImg, tdir, ...
        struct('rows',3,'cols',4,'method','surf','maxFrames',4));
    assert(sS.nCells == 12 && isfield(sS,'measurable'), 'pindai SURF cacat');
    fprintf('  [6] jalur SURF jalan: %d/%d sel terukur (maxFrames=4)\n', ...
        sum(sS.measurable), sS.nCells);

    fprintf('=== SMOKE PABSA0a: LULUS ===\n\n');
end

function i_rmdir(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
