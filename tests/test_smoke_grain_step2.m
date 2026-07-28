function test_smoke_grain_step2(rawFolder)
%TEST_SMOKE_GRAINSA_STEP2  Uji headless Step 2: .mat -> scanMats -> unpack -> PIV.
%
%   test_smoke_grain_step2('/path/ke/raw')
%
%   Membuktikan pipeline Step 2 END-TO-END tanpa GUI:
%     1. setup path GRAIN_SA
%     2. buat satu .mat 'pivprep_single_v1' (pivprepSingle) di folder root
%     3. pivanalyzemat.core.scanMats -> temukan .mat itu
%     4. pivanalyzemat.core.processBatchMat -> bongkar + jalankan engine
%        +pivanalyze (PIV + GS + EXIF + geometri) APA ADANYA
%     5. assert .mat hasil PIV muncul di PIV_<tgl>/ dengan vektor + GS.
%
%   SELALU MATLAB R2025b.

if nargin < 1; rawFolder = '/tmp/grainsa_test/raw'; end
fprintf('==== TEST SMOKE GRAIN_SA STEP 2 (input .mat) ====\n');

% --- 1) setup ---
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));  % +root (grain_setup, GRAIN*) sejak tests/ dipisah
roots = grain_setup();
assert(~isempty(roots.pivlab), 'Core PIVlab tidak ditemukan.');
assert(~isempty(which('pivanalyzemat.core.scanMats')), '+pivanalyzemat tidak di path.');

% --- 2) buat satu .mat di folder root khusus tes ---
rootDir = fullfile(tempdir, 'grainsa_step2_root');
if isfolder(rootDir); rmdir(rootDir, 's'); end
mkdir(rootDir);

exts = dir(fullfile(rawFolder, '*.jpg'));
if isempty(exts)
    fprintf(['[SKIP] test_smoke_grain_step2: tak ada *.jpg di %s — uji pipeline butuh ' ...
        'folder JPG mentah. Jalankan: test_smoke_grain_step2(folderJPG).\n'], rawFolder);
    return;
end
first = fullfile(rawFolder, exts(1).name);
img = imread(first); sz = size(img, [1 2]); H = sz(1); W = sz(2);
pts = [1 1; W 1; W H; 1 H];
crop   = batchpivprep2.io.cropPreset.fromPoints(pts, sz, 'crop', img, 'crop', first);
anchor = batchpivprep2.io.anchorPreset.fromPoints(pts, sz, 'phasecorr', img, 'anchor', first);

outMat = fullfile(rootDir, 'smoke_exp.mat');
cfg = struct('inSuffix','', 'stabMethod','phasecorr', 'jitterTol',Inf, ...
	'gsScale',0.5, 'gsQuality',85, 'rawFormat','jpg', 'rawQuality',90);
pivprepSingle(rawFolder, anchor, crop, cfg, outMat, 'Verbose', false);
assert(isfile(outMat), 'output .mat tidak terbentuk');
S = load(outMat, 'prep');
assert(strcmp(S.prep.format,'pivprep_single_v1'), 'format container salah');
fprintf('[ok] .mat root: %s (nFrames=%d)\n', outMat, S.prep.nFrames);

% --- 3) scanMats ---
exps = pivanalyzemat.core.scanMats(rootDir, 'Recursive', true, 'MinFrames', 2);
assert(numel(exps) == 1, 'scanMats harus menemukan 1 .mat, dapat %d', numel(exps));
fprintf('[ok] scanMats: %d eksperimen | #RAW=%d #GS=%d pair=%d EXIF=%d\n', ...
	numel(exps), exps(1).count, exps(1).gscount, exps(1).npairs, exps(1).has_exif);

% --- 3b) unpack -> folder sementara ---
e = pivanalyzemat.core.unpackMat(exps(1));
assert(isfolder(e.path), 'folder RAW sementara tak ada');
nraw = numel(dir(fullfile(e.path, '*.jpg')));
fprintf('[ok] unpack -> %s (%d RAW)\n', e.unpacked, nraw);
assert(nraw == exps(1).count, 'jumlah RAW bongkar (%d) != metadata (%d)', nraw, exps(1).count);

% --- 3c) readMatFrame: baca 1 frame ON-THE-FLY dari .mat (tanpa dump) ---
[imgA, nmA, nF1] = pivanalyzemat.core.readMatFrame(exps(1), 'first');
[imgB, nmB, ~  ] = pivanalyzemat.core.readMatFrame(exps(1), 'last');
assert(~isempty(imgA) && ~isempty(imgB), 'readMatFrame gagal decode frame');
assert(nF1 == exps(1).count, 'readMatFrame nFrames (%d) != metadata (%d)', nF1, exps(1).count);
assert(~strcmp(nmA, nmB) || nF1 == 1, 'frame awal & akhir seharusnya beda nama');
fprintf('[ok] readMatFrame: awal=%s akhir=%s (nF=%d, tanpa dump folder)\n', nmA, nmB, nF1);

% --- 3d) gsClahe: latar GS optimum on-the-fly (kosmetik) ---
g = pivanalyzemat.core.gsClahe(imgA);
assert(~isempty(g) && size(g,3) == 3, 'gsClahe harus keluarkan citra 3-kanal');
fprintf('[ok] gsClahe: latar %dx%dx3 (CLAHE+auto kontras)\n', size(g,1), size(g,2));

% bersihkan bongkaran uji 3b sebelum batch (uji batch hapus-sendiri di bawah)
if isfolder(e.unpacked); rmdir(e.unpacked, 's'); end

% --- 4) processBatchMat (engine penuh) ---
exps(1).X0 = 1; exps(1).X1 = 2; exps(1).Lpos = 10;   % geometri dummy valid
outRoot = fullfile(rootDir, ['PIV_' char(datetime('now','Format','yyyy-MM-dd'))]);
unpackRoot = fullfile(rootDir, '.grainsa2_unpack_test');
if isfolder(unpackRoot); rmdir(unpackRoot, 's'); end
cfg2 = pivanalyze.config('Folders', [], 'NumWorkers', 4, 'OutputFolder', outRoot, ...
	'Confirm', false, 'Provenance', 'test_smoke_step2', ...
	'LogFcn', @(s) fprintf('    %s\n', s));
cfg2.UnpackRoot = unpackRoot;   % folder kerja temporer batch (harus KOSONG di akhir)
[summary, aborted] = pivanalyzemat.core.processBatchMat(exps, cfg2);
assert(~aborted, 'batch tak boleh abort');
assert(~isempty(summary), 'summary kosong');
assert(~strcmp(summary(1).status, 'GAGAL'), 'eksperimen GAGAL: %s', summary(1).message);
assert(isfile(summary(1).output_file), 'output .mat PIV tak ada: %s', summary(1).output_file);
fprintf('[ok] PIV .mat: %s (%d pasangan, GS %d)\n', ...
	summary(1).output_file, summary(1).num_pairs, summary(1).n_gs_embedded);

% --- 4c) DUMP TEMPORER: bongkaran per-exp HARUS sudah dihapus (tak ada artefak) ---
leftover = {};
if isfolder(unpackRoot)
	dd = dir(unpackRoot);
	dd = dd(~ismember({dd.name}, {'.', '..'}));
	leftover = {dd.name};
end
assert(isempty(leftover), ['Folder kerja batch TIDAK bersih — sisa bongkaran: ' ...
	strjoin(leftover, ', ')]);
fprintf('[ok] folder kerja batch BERSIH (bongkaran per-exp terhapus otomatis).\n');

% --- 4b) verifikasi isi .mat hasil ---
R = load(summary(1).output_file);
assert(isfield(R, 'u_original') || isfield(R, 'u_filtered') || isfield(R, 'x'), ...
	'output PIV tak punya field vektor PIVlab');
fprintf('[ok] output .mat berisi field PIVlab (vektor).\n');

% --- 5) bersihkan ---
pivanalyzemat.core.cleanupTmp();
fprintf('[ok] cleanup folder sementara.\n');

fprintf('==== STEP 2 SEMUA LULUS ✓ ====\n');
end
