function test_smoke_grain1_handoff()
%TEST_SMOKE_GRAIN1_HANDOFF  Verifikasi jalur "Lanjutkan ke Step 2":
%   prog.folders -> runBatch(packSingleMat) -> MAT PREP (RAW+EXIF+jitter) ->
%   scanMats membaca daftar -> GRAIN2 bisa menunjuk folder itu.
%   HEADLESS (tanpa GUI). Jalankan: grain_setup; test_smoke_grain1_handoff
    grain_setup();

    src = fullfile(fileparts(fileparts(mfilename('fullpath'))), '..', '5 cm-1');
    assert(isfolder(src), 'Sample "5 cm-1" tidak ditemukan: %s', src);
    d = dir(fullfile(src, '*.JPG'));
    files = {d.name};
    files = files(1:min(8, numel(files)));   % subset cepat
    assert(~isempty(files), 'Tak ada JPG di sample.');

    img = imread(fullfile(src, files{1}));
    imgSize = size(img, [1 2]);
    % ROI kecil tengah-atas (area diam) -> anchor preset.
    roiPts = [800 800; 1000 800; 1000 900; 800 900];
    anchor = batchpivprep2.io.anchorPreset.fromPoints(roiPts, imgSize, 'surf', ...
        img, 'anchor0-test', fullfile(src, files{1}));
    crop = batchpivprep2.io.cropPreset.makeNone('full-test');

    folders = struct('path', src, 'files', {files}, 'nImg', numel(files), ...
        'outName', 'exp5cm1', 'seqMode', 'consecutive', 'seqStep', 1, ...
        'anchor', anchor, 'anchorName', anchor.name, 'crop', crop, 'cropName', crop.name);

    prepDir = fullfile(tempdir, sprintf('pab1_handoff_%d', feature('getpid')));
    if isfolder(prepDir); rmdir(prepDir, 's'); end
    mkdir(prepDir);
    cleanup = onCleanup(@() rmdir(prepDir, 's')); %#ok<NASGU>

    cfg = struct('suffix','', 'stabMethod','surf', 'jitterTol',50, ...
        'roiPad',50, 'surfMaxRatio',0.60, 'minMatchPts',4, ...
        'marginEnabled',true, 'marginPx',10, ...
        'rawFormat','jpg', 'rawQuality',90, 'gsScale',0.5, 'gsQuality',85, ...
        'outputMode','root', 'outputRoot',prepDir, ...
        'packSingleMat',true, 'keepFolder',false, 'matOutDir',prepDir);

    results = batchpivprep2.core.runBatch(folders, cfg);
    assert(~isempty(results(1).singleMat), 'MAT PREP tidak dihasilkan.');
    assert(isfile(results(1).singleMat), 'Berkas MAT PREP hilang: %s', results(1).singleMat);

    % Isi WAJIB: RAW + EXIF + jitter ada di .mat PREP.
    S = load(results(1).singleMat, 'prep');
    assert(isfield(S, 'prep'), '.mat tak punya struct prep.');
    assert(isfield(S.prep, 'exif'),   'MAT PREP tak punya EXIF.');
    assert(isfield(S.prep, 'jitter'), 'MAT PREP tak punya jitter.');

    % scanMats (yang dipakai GRAIN2 onScan) harus menemukan exp ini.
    sc = pivanalyzemat.core.scanMats(prepDir, 'Recursive', false, 'MinFrames', 2);
    assert(~isempty(sc), 'scanMats tak menemukan MAT PREP.');

    fprintf('OK: MAT PREP %s (%.1f MB), EXIF+jitter ada, scanMats(%d) lulus.\n', ...
        results(1).singleMat, results(1).mat_bytes/1e6, numel(sc));
end
