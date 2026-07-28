function test_smoke_grain_step0()
%TEST_SMOKE_GRAINSA_STEP0  Smoke test GRAINSA0 multi-eksperimen (PAB_step_0).
%
%   Memvalidasi (headless, tanpa interaksi mouse):
%     1. Scan rekursif ROOT -> daftar eksperimen (collectFolders, identik Step 1).
%     2. Engine jitter SAMA Step 1 (roiPad=0, lastGood=I, tol besar) melacak
%        geseran buatan via phase-corr (akurat) + cumDx/cumDy = cumsum.
%     3. GUI PAB_step_0 terbentuk headless: tabel terisi N exp, handle inti ada.
%     4. Progress 'BatchPIVPrep2Progress' yg dibangun GRAINSA0 (folders+anchor,
%        crop=full-frame) BISA di-AUTO-LOAD oleh PAB_step_1(progressPath):
%        h.folders terisi & anchor non-kosong. = jalur "Buka di Step 1".
%
%   Jalankan: grain_setup; test_smoke_grain_step0
%   SELALU MATLAB R2025b.

    fprintf('\n=== SMOKE GRAINSA0 multi-exp (PAB_step_0) ===\n');
    grain_setup();
    assert(~isempty(which('GRAIN1')),                             'GRAIN1 (ROI jitter) tak di-path');
    assert(~isempty(which('batchpivprep2.io.collectFolders')),  'collectFolders tak di-path');

    troot = fullfile(tempdir, sprintf('grainsa0_multi_%d', feature('getpid')));
    if isfolder(troot), rmdir(troot,'s'); end
    mkdir(troot);
    cleaner = onCleanup(@() i_rmdir(troot));

    % --- Bangun 3 subfolder eksperimen (frame bertekstur + geseran) -----
    nExp = 3; nF = 10;
    expDirs = cell(nExp,1);
    for ie = 1:nExp
        d = fullfile(troot, sprintf('exp_%02d', ie));
        mkdir(d); expDirs{ie} = d;
        base = i_textureBase(280, 360, ie);
        for k = 1:nF
            if k==1, img = base;
            else,    img = imtranslate(base, [(k-1)*0.6*ie, sin((k-1)/2)*1.0], 'FillValues',128);
            end
            imwrite(img, fullfile(d, sprintf('f_%03d.png', k)));
        end
    end
    fprintf('  [1] %d eksperimen x %d frame ditulis di %s\n', nExp, nF, troot);

    % --- 1. Scan rekursif (identik Step 1) ------------------------------
    found = batchpivprep2.io.collectFolders(troot, true);
    assert(numel(found) == nExp, sprintf('scan: %d folder (harusnya %d)', numel(found), nExp));
    assert(all(arrayfun(@(f) f.nImg==nF, found)), 'jumlah gambar per-exp salah');
    fprintf('  [2] collectFolders rekursif: %d eksperimen terdeteksi\n', numel(found));

    % --- 2. Engine jitter per-exp (phase-corr akurat) -------------------
    roiBox = [120 90 130 110];                 % ROI kecil
    Iform  = pivprep.util.utilities.identityTform();
    prm    = struct('roiPad',0,'jitterTol',1e9,'lastGoodTform',Iform);
    e1 = found(1);
    img1 = imread(fullfile(e1.path, e1.files{1}));
    ref  = pivprep.stab.buildReference(img1, roiBox, 'phasecorr');
    dx = zeros(nF,1); dy = zeros(nF,1);
    for k = 1:nF
        o = pivprep.stab.estimateTransform(imread(fullfile(e1.path,e1.files{k})), ref, prm);
        dx(k)=o.dx; dy(k)=o.dy;
    end
    cumDx = cumsum(dx);
    errX = abs(abs(dx(end)) - abs((nF-1)*0.6*1));   % exp #1 ramp
    assert(abs(dx(1))<1e-6 && abs(dy(1))<1e-6, 'frame-1 harus 0');
    assert(errX < 1.5, sprintf('dx tak melacak geseran (err=%.2f px)', errX));
    assert(numel(cumDx)==nF, 'cumsum panjang salah');
    fprintf('  [3] engine jitter melacak geseran (errX=%.2f px), cumsum OK\n', errX);

    % --- 3. GUI PAB_step_0 terbentuk headless ---------------------------
    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>  % pulihkan sesi
    GRAIN1(troot);
    % Nama figure GRAIN1 (pasca-rename): 'GRAIN1 (Step 1) — ...'. Cocokkan via
    % prefiks 'GRAIN1' agar tahan rename judul di masa depan.
    f0 = findall(0,'Type','figure','-regexp','Name','^GRAIN1');
    if numel(f0) > 1, f0 = f0(1); end
    assert(~isempty(f0), 'figure GRAIN1 tak terbentuk');
    h0 = guidata(f0);
    assert(isfield(h0,'tbl') && isfield(h0,'axJit') && isfield(h0,'btnRect'), 'handle inti hilang');
    assert(isfield(h0,'btnDelExp') && ishghandle(h0.btnDelExp), 'tombol Hapus tak ada');
    assert(isfield(h0,'btnClearExp') && ishghandle(h0.btnClearExp), 'tombol Kosongkan tak ada');
    assert(isfield(h0,'axJit') && isfield(h0,'axCum') && ishghandle(h0.axCum), ...
        'plot belum dipisah 2 (axCum tak ada)');
    assert(isfield(h0,'btnDoneNext') && ishghandle(h0.btnDoneNext), 'tombol Simpan+Next tak ada');
    assert(isfield(h0,'btnSaveProg') && ishghandle(h0.btnSaveProg), 'tombol Simpan Progress tak ada');
    assert(numel(h0.exps) == nExp, sprintf('exps=%d (harusnya %d)', numel(h0.exps), nExp));
    D = get(h0.tbl,'Data');
    assert(size(D,1) == nExp, 'tabel exp tak terisi');
    fprintf('  [4] GUI GRAINSA0 OK: %d exp di tabel, handle+tombol hapus ada\n', numel(h0.exps));

    % Hapus dari DAFTAR via callback NYATA. questdlg memblok/eror headless,
    % jadi di-stub sementara -> 'Remove' (handler dijalankan sepenuhnya).
    rmRow = 2; rmName = h0.exps(rmRow).name; rmDir = h0.exps(rmRow).path;
    stubDir = i_makeQuestdlgStub('Remove');
    restoreStub = onCleanup(@() i_rmStub(stubDir));
    h0.selRows = rmRow; h0.activeRow = rmRow; guidata(f0, h0);
    cbDel = get(h0.btnDelExp,'Callback'); cbDel(h0.btnDelExp, []);
    h0 = guidata(f0);
    assert(numel(h0.exps) == nExp-1, 'hapus dari daftar gagal');
    assert(~ismember(rmName, {h0.exps.name}), 'exp terhapus masih ada');
    assert(isfolder(rmDir), 'folder di disk ikut terhapus (TIDAK BOLEH)');
    assert(size(get(h0.tbl,'Data'),1) == nExp-1, 'tabel tak ter-refresh');
    clear restoreStub;   % buang stub questdlg
    fprintf('  [4b] Hapus dari daftar (callback) OK: %d->%d exp, folder disk utuh\n', ...
        nExp, numel(h0.exps));

    % [4c] Hitung Jitter EKSPLISIT: set ROI -> result MASIH kosong (tak auto);
    %      tekan tombol "Hitung Jitter" -> result terisi.
    assert(isfield(h0,'btnCompute') && ishghandle(h0.btnCompute), 'tombol Hitung Jitter tak ada');
    h0.activeRow = 1;
    boxc = [120 90 130 110];
    h0.exps(1).roiPts = [boxc(1) boxc(2); boxc(1)+boxc(3) boxc(2); ...
        boxc(1)+boxc(3) boxc(2)+boxc(4); boxc(1) boxc(2)+boxc(4)];
    h0.exps(1).roiBox = boxc; h0.exps(1).result = [];
    guidata(f0, h0);
    % Pilih metode phasecorr lewat callback popup NYATA (spt user klik popup).
    set(h0.popMethod,'Value',2);
    cbM = get(h0.popMethod,'Callback'); cbM(h0.popMethod, []);
    h0 = guidata(f0);
    assert(isempty(h0.exps(1).result), 'set ROI mestinya TIDAK auto-hitung jitter');
    cbCompute = get(h0.btnCompute,'Callback'); cbCompute(h0.btnCompute, []);
    h0 = guidata(f0);
    assert(~isempty(h0.exps(1).result), 'tombol Hitung Jitter tak menghasilkan result');
    assert(isempty(h0.exps(1).result.failMsg), ['compute gagal: ' h0.exps(1).result.failMsg]);
    % Exp 1 punya ramp geseran nyata -> drift harus jelas > 0 (bukan diam).
    assert(h0.exps(1).result.driftMag > 1, ...
        sprintf('drift %.2f px terlalu kecil — compute mungkin salah frame/metode', ...
        h0.exps(1).result.driftMag));
    fprintf('  [4c] Hitung Jitter EKSPLISIT OK: ROI tak auto-hitung; tombol -> drift %.2f px\n', ...
        h0.exps(1).result.driftMag);

    % [4e] Simpan+Next menandai SELESAI lalu pindah exp; Hitung TIDAK menandai
    %      selesai. Lalu "💾 Simpan Progress" -> tulis KHUSUS GRAIN1:
    %      <ROOT>/PAB1_progress.mat berisi var 'pab1' (.exps), pasca-rename.
    assert(~(isfield(h0.exps(1),'done') && ~isempty(h0.exps(1).done) && h0.exps(1).done), ...
        'hitung jitter TIDAK boleh menandai selesai');
    h0.activeRow = 1; guidata(f0, h0);
    cbDN = get(h0.btnDoneNext,'Callback'); cbDN(h0.btnDoneNext, []);
    h0 = guidata(f0);
    assert(h0.exps(1).done, 'Simpan+Next tak menandai exp selesai');
    assert(h0.activeRow ~= 1, 'Simpan+Next tak pindah ke exp berikutnya');
    progFile = fullfile(troot,'PAB1_progress.mat');
    if isfile(progFile), delete(progFile); end
    cbSP = get(h0.btnSaveProg,'Callback'); cbSP(h0.btnSaveProg, []);
    assert(isfile(progFile), 'Simpan Progress tak menulis <ROOT>/PAB1_progress.mat');
    Sp = load(progFile);
    assert(isfield(Sp,'pab1') && isfield(Sp.pab1,'exps'), ...
        'PAB1_progress.mat tak berisi struct pab1.exps');
    delete(progFile);
    fprintf('  [4e] Simpan+Next (done+pindah) & Simpan Progress GRAIN1 OK\n');
    close(f0);

    % [4d] REGRESI commit ROI: drawrectangle BLOCKING -> commit harus INLINE,
    %      BUKAN via listener DrawingFinished (race: event lewat sblm listener
    %      terpasang -> ROI tak ter-commit & tombol Hitung tetap grey).
    src = fileread(which('GRAIN1'));
    assert(~contains(src, 'addlistener(roi'), ...
        'GRAIN1 masih pasang listener pd objek ROI (race bug DrawingFinished).');
    assert(contains(src, 'i_commitROI(fig, roi, mode)'), ...
        'commit ROI inline (i_commitROI) hilang dari handler gambar.');
    fprintf('  [4d] Commit ROI INLINE (tanpa listener race) OK\n');

    % --- 4. Progress BatchPIVPrep2 -> auto-load di PAB_step_1 -----------
    % Bangun progress seperti GRAINSA0 (folders + anchor dari ROI; crop full).
    folders = struct('path',{},'files',{},'nImg',{},'outName',{}, ...
        'seqMode',{},'seqStep',{},'anchor',{},'anchorName',{},'crop',{},'cropName',{});
    for ie = 1:nExp
        ee = found(ie);
        im = imread(fullfile(ee.path, ee.files{1}));
        pts = [roiBox(1) roiBox(2); roiBox(1)+roiBox(3) roiBox(2); ...
               roiBox(1)+roiBox(3) roiBox(2)+roiBox(4); roiBox(1) roiBox(2)+roiBox(4)];
        anchor = batchpivprep2.io.anchorPreset.fromPoints( ...
            pts, size(im,[1 2]), 'surf', im, sprintf('anchor0-exp%02d',ie), ee.files{1});
        crop = batchpivprep2.io.cropPreset.makeNone(sprintf('full-exp%02d',ie));
        folders(end+1) = struct( ...
            'path',ee.path,'files',{ee.files},'nImg',ee.nImg, ...
            'outName',sprintf('exp_%02d',ie),'seqMode','consecutive','seqStep',1, ...
            'anchor',anchor,'anchorName',anchor.name,'crop',crop,'cropName',crop.name); %#ok<AGROW>
    end
    progress = struct('type','BatchPIVPrep2Progress','version',1, ...
        'folders',folders,'activeAnchor',folders(1).anchor,'activeCrop',[], ...
        'cropMode','crop','marginEnabled',true,'marginPx',10,'outputRoot',troot, ...
        'settings',struct('suffix','','stabMethodVal',1,'jitterTol','2', ...
            'rawFmtVal',1,'rawQual','90','gsScale','50','gsQual','85', ...
            'cropModeVal',1,'cropModeStr','crop','outLocRoot',1), ...
        'savedAt','test'); %#ok<NASGU>
    progPath = fullfile(troot,'PAB_progress.mat');
    save(progPath,'progress');

    % Validasi schema bisa di-Load: jalankan PAB1_old(progPath) (BatchPIVPrep2) headless.
    PAB1_old(progPath);
    f1 = findall(0,'Type','figure', ...
        'Name','BatchPIVPrep2 - Batch Stabilization + Cropping Preprocessor');
    assert(~isempty(f1), 'GUI Step 1 tak terbentuk');
    h1 = guidata(f1(1));
    assert(isfield(h1,'folders') && numel(h1.folders)==nExp, ...
        sprintf('Step1 folders=%d (harusnya %d)', numel(i_get(h1,'folders')), nExp));
    assert(~isempty(h1.activeAnchor) && isfield(h1.activeAnchor,'anchorROI'), ...
        'Step1 activeAnchor kosong/cacat');
    assert(~isempty(h1.folders(1).anchor) && ~isempty(h1.folders(1).crop), ...
        'folder Step1 tanpa anchor/crop');
    fprintf('  [5] PAB_step_1(progress) auto-load OK: %d folder, anchor ROI=[%.0f %.0f %.0f %.0f]\n', ...
        numel(h1.folders), h1.activeAnchor.anchorROI);
    close(f1);

    fprintf('=== SMOKE GRAINSA0 multi-exp: LULUS ===\n\n');
end


% ---------------------------------------------------------------------
function base = i_textureBase(H, W, seedScale)
%I_TEXTUREBASE  Latar abu + grid blob terang/gelap (kaya gradien utk phasecorr).
    base = uint8(120*ones(H,W));
    [cx, cy] = meshgrid(20:30:W, 20:30:H);
    cx = cx(:); cy = cy(:);
    for b = 1:numel(cx)
        v = 220; if mod(b+seedScale,2)==0, v = 30; end
        x0 = max(1,cx(b)-4):min(W,cx(b)+4);
        y0 = max(1,cy(b)-4):min(H,cy(b)+4);
        base(y0,x0) = v;
    end
    base = imgaussfilt(base, 1.2);
end

function v = i_get(s,f), v = s.(f); end

function stubDir = i_makeQuestdlgStub(answer)
%I_MAKEQUESTDLGSTUB  Buat questdlg.m sementara di path -> kembalikan 'answer'.
    stubDir = fullfile(tempdir, sprintf('grainsa0_qstub_%d', feature('getpid')));
    if ~isfolder(stubDir), mkdir(stubDir); end
    fid = fopen(fullfile(stubDir,'questdlg.m'),'w');
    fprintf(fid, 'function b = questdlg(varargin)\nb = ''%s'';\nend\n', answer);
    fclose(fid);
    addpath(stubDir); rehash;
end

function i_rmStub(stubDir)
    try, rmpath(stubDir); catch, end
    try, if isfolder(stubDir), rmdir(stubDir,'s'); end, catch, end
    try, rehash; catch, end
end

function i_rmdir(d)
    try
        f = findall(0,'Type','figure');
        for k=1:numel(f), try, close(f(k)); catch, end, end
    catch
    end
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
