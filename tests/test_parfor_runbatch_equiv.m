function test_parfor_runbatch_equiv()
%TEST_PARFOR_RUNBATCH_EQUIV  Bukti Strategi A: runBatch paralel antar-folder ==
%   serial. Memvalidasi hasil stabilisasi per-folder IDENTIK saat folder
%   diproses serempak (parfor) vs antre (serial), dan worker MENEMUKAN paket
%   +batchpivprep2/+pivprep + pivprepPackFolder. Pakai stabMethod='phasecorr'
%   (deterministik, tanpa RANSAC) supaya perbandingan bisa EKSAK.
%   Jalankan: pab_setup; test_parfor_runbatch_equiv
    pab_setup();

    if isempty(ver('parallel'))
        fprintf('SKIP: Parallel Computing Toolbox tak ada.\n'); return;
    end

    src = fullfile(fileparts(fileparts(mfilename('fullpath'))), '..', '5 cm-1');
    assert(isfolder(src), 'Sample "5 cm-1" tak ditemukan: %s', src);
    d = dir(fullfile(src, '*.JPG'));
    files = {d.name};
    files = files(1:min(6, numel(files)));        % subset cepat
    assert(numel(files) >= 3, 'Butuh >=3 frame.');

    img = imread(fullfile(src, files{1}));
    imgSize = size(img, [1 2]);
    roiPts = [800 800; 1000 800; 1000 900; 800 900];   % area diam tengah-atas
    anchor = batchpivprep2.io.anchorPreset.fromPoints(roiPts, imgSize, 'phasecorr', ...
        img, 'anc-test', fullfile(src, files{1}));
    crop = batchpivprep2.io.cropPreset.makeNone('full-test');

    base = fullfile(tempdir, sprintf('pfeq_%d', feature('getpid')));
    if isfolder(base); rmdir(base, 's'); end
    mkdir(base);
    cleanup = onCleanup(@() i_rmDir(base)); %#ok<NASGU>

    % --- 3 folder input independen (isi sama; cukup utk uji plumbing+ekuivalensi) ---
    nF = 3;
    folders = repmat(struct('path','','files',{{}},'nImg',0,'outName','', ...
        'seqMode','consecutive','seqStep',1,'anchor',[],'anchorName','', ...
        'crop',[],'cropName',''), 1, nF);
    for j = 1:nF
        fdir = fullfile(base, sprintf('in_exp_%d', j));
        mkdir(fdir);
        for q = 1:numel(files)
            copyfile(fullfile(src, files{q}), fullfile(fdir, files{q}));
        end
        folders(j) = struct('path',fdir, 'files',{files}, 'nImg',numel(files), ...
            'outName',sprintf('exp%d',j), 'seqMode','consecutive', 'seqStep',1, ...
            'anchor',anchor, 'anchorName',anchor.name, 'crop',crop, 'cropName',crop.name);
    end

    cfg0 = struct('suffix','', 'stabMethod','phasecorr', 'jitterTol',1e9, ...
        'roiPad',50, 'surfMaxRatio',0.60, 'minMatchPts',4, ...
        'marginEnabled',false, 'marginPx',0, ...
        'rawFormat','jpg', 'rawQuality',90, 'gsScale',0.5, 'gsQuality',85, ...
        'packSingleMat',true, 'keepFolder',false, 'showSummaryDialog',false);

    % --- SERIAL (paksa) ---
    cfgS = cfg0; cfgS.parallelFolders = false;
    cfgS.matOutDir = fullfile(base, 'matS'); mkdir(cfgS.matOutDir);
    resS = batchpivprep2.core.runBatch(folders, cfgS);

    % --- PARALEL (paksa) ---
    cfgP = cfg0; cfgP.parallelFolders = true;
    cfgP.matOutDir = fullfile(base, 'matP'); mkdir(cfgP.matOutDir);
    resP = batchpivprep2.core.runBatch(folders, cfgP);

    % --- BANDINGKAN per folder ---
    maxd = 0;
    for j = 1:nF
        assert(isfile(resS(j).singleMat), 'Serial: .mat folder %d hilang.', j);
        assert(isfile(resP(j).singleMat), 'Paralel: .mat folder %d hilang.', j);
        assert(resS(j).nOK   == resP(j).nOK,   'nOK beda di folder %d.', j);
        assert(resS(j).nSkip == resP(j).nSkip, 'nSkip beda di folder %d.', j);
        a = resS(j).jitterSummary; b = resP(j).jitterSummary;
        fld = {'jitterMean','jitterRMS','jitterMax','driftEndX','driftEndY'};
        for c = 1:numel(fld)
            assert(isfield(a,fld{c}) && isfield(b,fld{c}), 'jitterSummary.%s hilang.', fld{c});
            maxd = max(maxd, abs(a.(fld{c}) - b.(fld{c})));
        end
    end
    fprintf('nFolders=%d  max|delta(jitterSummary)|=%.3g\n', nF, maxd);
    assert(maxd < 1e-9, 'jitterSummary serial != paralel (delta=%.3g).', maxd);
    assert(sum([resP.nOK]) > 0, 'nOK total nol — stabilisasi tak jalan?');
    disp('TEST_PARFOR_RUNBATCH_EQUIV: LULUS');
end

function i_rmDir(p)
    try, if isfolder(p); rmdir(p, 's'); end; catch; end
end
