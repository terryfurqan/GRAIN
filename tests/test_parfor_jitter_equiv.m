function test_parfor_jitter_equiv()
%TEST_PARFOR_JITTER_EQUIV  Bukti: sapu jitter parfor == serial (PAB1 Step 1).
%   Memvalidasi loop antar-frame independen (lastGoodTform=identitas) memberi
%   dx/dy IDENTIK saat dijalankan parfor vs serial, dan worker MENEMUKAN paket
%   +pivprep (risiko AutoAddClientPath). Engine = pivprep.stab.* (sama Step 1).
    here = fileparts(mfilename('fullpath'));
    run(fullfile(here, '..', 'pab_setup.m'));

    folder = fullfile(here, '..', '..', '5 cm-1');
    d = dir(fullfile(folder, '*.JPG'));
    assert(~isempty(d), 'Data sampel "5 cm-1" tak ditemukan.');
    files = {d.name};
    nUse = min(40, numel(files));            % > ambang 24 -> jalur parfor aktif
    assert(nUse >= 24, 'Butuh >=24 frame agar jalur parfor terpakai.');

    img1 = imread(fullfile(folder, files{1}));
    [H, W] = size(rgb2gray(img1));
    roi = [round(W*0.05) round(H*0.05) round(W*0.20) round(H*0.20)]; % pojok diam
    ref = pivprep.stab.buildReference(img1, roi, 'phasecorr');
    Iform = pivprep.util.utilities.identityTform();
    prm = struct('roiPad',0,'jitterTol',1e9,'lastGoodTform',Iform);

    % --- SERIAL ---
    dxS=zeros(nUse,1); dyS=zeros(nUse,1); jS=zeros(nUse,1); okS=false(nUse,1);
    okS(1)=true;
    for k = 2:nUse
        [dxS(k),dyS(k),jS(k),okS(k)] = local_one(folder, files{k}, ref, prm);
    end

    % --- PARFOR (paksa pool agar uji jalur paralel) ---
    assert(~isempty(ver('parallel')), 'Parallel Computing Toolbox tak ada.');
    if isempty(gcp('nocreate')); parpool('local'); end
    dxP=zeros(nUse,1); dyP=zeros(nUse,1); jP=zeros(nUse,1); okP=false(nUse,1);
    okP(1)=true;
    parfor k = 2:nUse
        [dxP(k),dyP(k),jP(k),okP(k)] = local_one(folder, files{k}, ref, prm);
    end

    % --- BANDINGKAN ---
    eqOk = isequal(okS, okP);
    dmax = max(abs([dxS-dxP; dyS-dyP; jS-jP]));
    fprintf('nUse=%d  max|delta(dx,dy,jit)|=%.3g  ok-vektor sama=%d\n', nUse, dmax, eqOk);
    assert(eqOk, 'Vektor OK serial != parfor.');
    assert(dmax < 1e-9, 'dx/dy/jit serial != parfor (delta=%.3g).', dmax);
    assert(any(abs(dxP(2:end))>0 | abs(dyP(2:end))>0), 'Semua dx/dy nol — engine tak jalan?');
    disp('TEST_PARFOR_JITTER_EQUIV: LULUS');
end

function [dx,dy,jit,ok] = local_one(basePath, fname, ref, prm)
%LOCAL_ONE  Replika i_oneFrameJitter (PAB1) — parfor-safe, tanpa GUI.
    try
        im  = imread(fullfile(basePath, fname));
        o   = pivprep.stab.estimateTransform(im, ref, prm);
        dx  = o.dx;  dy = o.dy;  jit = o.jitter;
        ok  = ~startsWith(o.status,'REJECT');
    catch
        dx = NaN;  dy = NaN;  jit = NaN;  ok = false;
    end
end
