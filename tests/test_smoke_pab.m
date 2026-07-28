function test_smoke_pab(rawFolder)
%TEST_SMOKE_PABSA  Uji cepat headless: setup -> preset -> prep .mat -> QPIV.
%   Membuktikan engine PAB_SA terpasang & core PIVlab jalan, tanpa GUI.
%   test_smoke_pab('/tmp/pabsa_test/raw')

if nargin < 1; rawFolder = '/tmp/pabsa_test/raw'; end
fprintf('==== TEST SMOKE PAB_SA ====\n');

% --- 1) setup path ---
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));  % +root (pab_setup, PAB*) sejak tests/ dipisah
roots = pab_setup();
assert(~isempty(roots.pivlab), 'Core PIVlab tidak ditemukan.');

% --- 2) preset full-frame no-op ---
exts = dir(fullfile(rawFolder, '*.jpg'));
if isempty(exts)
    fprintf(['[SKIP] test_smoke_pab: tak ada *.jpg di %s — uji PIPELINE PENUH ' ...
        '(prep+QPIV) butuh folder JPG mentah. Jalankan: test_smoke_pab(folderJPG).\n'], rawFolder);
    return;
end
first = fullfile(rawFolder, exts(1).name);
img = imread(first); sz = size(img, [1 2]); H = sz(1); W = sz(2);
pts = [1 1; W 1; W H; 1 H];
crop   = batchpivprep2.io.cropPreset.fromPoints(pts, sz, 'crop', img, 'crop', first);
anchor = batchpivprep2.io.anchorPreset.fromPoints(pts, sz, 'phasecorr', img, 'anchor', first);
fprintf('[ok] preset full-frame %dx%d\n', W, H);

% --- 3) prep -> single .mat (stabilisasi efektif lewat: jitterTol=Inf) ---
outMat = fullfile(tempdir, 'pabsa_smoke_prep.mat');
cfg = struct('inSuffix','', 'stabMethod','phasecorr', 'jitterTol',Inf, ...
	'gsScale',0.5, 'gsQuality',85, 'rawFormat','jpg', 'rawQuality',90);
o = pivprepSingle(rawFolder, anchor, crop, cfg, outMat, 'Verbose', true);
assert(isfile(outMat), 'output .mat tidak terbentuk');
mb = dir(outMat);
fprintf('[ok] single .mat: %s (%.1f MB, prep %.1fs)\n', outMat, mb.bytes/1e6, o.elapsed_prep);
S = load(outMat, 'prep');
assert(strcmp(S.prep.format,'pivprep_single_v1'), 'format container salah');
fprintf('[ok] container pivprep_single_v1, nFrames=%d\n', S.prep.nFrames);

% --- 4) QPIV: bukti core PIVlab jalan ---
res = PIVlab_automasi_qpiv(rawFolder, 'NumWorkers', 4);
assert(res.nFrames >= 1, 'QPIV tak hasilkan frame');
fprintf('[ok] QPIV %d frame, strip %s, IW %s\n', res.nFrames, ...
	mat2str(res.roi), mat2str(res.iw_used(1:res.num_passes_used)));

fprintf('==== SEMUA LULUS ✓ ====\n');
end
