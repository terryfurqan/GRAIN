function results = PIVlab_automasi(image_folder, varargin)
%PIVLAB_AUTOMASI  Otomasi penuh analisis PIV memakai fungsi-fungsi PIVlab.
%
%   Fungsi ini menjalankan seluruh alur kerja PIVlab secara otomatis untuk
%   satu folder berisi gambar sekuensial, PERSIS seperti pengaturan pada
%   screenshot:
%
%     1. Pra-pemrosesan citra
%          - CLAHE aktif, window 64 px
%          - Highpass aktif, kernel 15 px
%          - Intensity capping non-aktif
%          - Wiener2 non-aktif
%          - Auto contrast stretch (imadjust) minimum 0, maksimum 1
%          - Background subtraction off
%     2. Analisis PIV: Multipass FFT window deformation, 3 lapis
%          - Pass 1: 64 px (step 32)
%          - Pass 2: 32 px (step 16)
%          - Pass 3: 25 px (step 16)
%          - Sub-pixel estimator: Gauss 2x3-point
%          - Correlation robustness: Standard (recommended)
%          - Disable auto-correlation: tidak
%     3. Validasi vektor (diterapkan ke SEMUA frame)
%          - Velocity limit: inactive
%          - Standard deviation filter, threshold 8
%          - Local median filter, threshold 3
%          - Interpolate missing data: ya (inpaint_nans)
%     4. Parameter turunan (smoothing kekuatan MAKSIMAL pada slider).
%        Slider PIVlab: min=1, max=11 -> floor(11)=11 -> smoothn S = 11/10 = 1.1
%          - Vektor (u,v) yang telah di-smooth
%          - Displacement magnitude  = sqrt(u^2 + v^2) dari vektor ter-smooth
%          - Simple strain rate       = plot.strain(...) dari vektor ter-smooth
%     5. Ekspor ke file .mat dengan nama = nama folder target (format MAT
%        PIVlab standar).
%
%   Komputasi PIV dijalankan paralel dengan 8 worker (default).
%   Fungsi ini TIDAK memodifikasi aplikasi PIVlab; ia hanya MEMANGGIL
%   fungsi-fungsi PIVlab (paket +preproc, +piv, +postproc, +plot, +misc).
%
%   PENGGUNAAN
%     results = PIVlab_automasi(image_folder)
%     results = PIVlab_automasi(image_folder, 'Name', Value, ...)
%
%   ARGUMEN
%     image_folder   : folder berisi gambar sekuensial (string/char).
%
%   OPSI (Name-Value)
%     'Suffix'       : pola file gambar, mis. '*.tif'. Default: deteksi
%                      otomatis (tif/tiff/jpg/jpeg/png/bmp - terbanyak).
%     'NumWorkers'   : jumlah worker paralel. Default: 8.
%     'Sequencing'   : 'consecutive' (1-2,2-3,3-4,...) [default] atau
%                      'pairs' (1-2,3-4,5-6,...).
%     'OutputFolder' : folder penyimpanan .mat. Default: image_folder.
%     'OutputName'   : nama file tanpa ekstensi. Default: nama folder target.
%     'PIVlabRoot'   : path folder PIVlab. Default: deteksi otomatis.
%     'ProgressFcn'  : handle fungsi @(frac,msg) untuk laporan progres
%                      (dipakai GUI). Default: cetak ke Command Window.
%     'IntAreas'     : [1x4] ukuran interrogation window pass 1..4 (px).
%                      Default [64 32 25 16] (= perilaku lama persis).
%                      Nilai dipaksa genap (round(x/2)*2) seperti PIVlab.
%     'NumPasses'    : jumlah pass multipass (1..4). Default 3.
%     'ROI'          : [x y width height] (1-based px, width/height = SPAN)
%                      untuk membatasi analisis ke sebagian gambar (mis. strip
%                      Quick PIV). Default [] = seluruh gambar. Koordinat x/y
%                      keluaran tetap di ruang gambar penuh.
%     'PreprocROI'   : [x y width height] (1-based px). Bila diberi, pra-proses
%                      (CLAHE/Highpass) HANYA dihitung di dalam strip ini, bukan
%                      seluruh frame -> hemat 3-10x untuk QPIV. Set sama dgn
%                      'ROI'. Default [] = pra-proses seluruh gambar (lama).
%     'Step1Frac'    : fraksi step pass-1 terhadap IW pass-1. Default 0.5
%                      (= step 32 saat IW1=64, perilaku lama).
%     'Skip'         : lewati gambar -> ambil tiap (Skip+1) gambar SEBELUM
%                      membentuk pasangan. 0 (default) = semua; 1 = A,C,E,...;
%                      2 = A,D,G,... Mengubah jumlah & penomoran frame.
%
%   KELUARAN
%     results : struct berisi seluruh medan hasil + 'output_file' (path .mat).
%
%   Lihat juga: PIVlab_automasi_GUI

%% ----------------------------------------------------------------- input
ip = inputParser;
ip.addRequired('image_folder', @(x) ischar(x) || isstring(x));
ip.addParameter('Suffix', '',  @(x) ischar(x) || isstring(x));
ip.addParameter('NumWorkers', 8, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.addParameter('Sequencing', 'consecutive', @(x) any(strcmpi(x, {'consecutive','pairs'})));
ip.addParameter('OutputFolder', '', @(x) ischar(x) || isstring(x));
ip.addParameter('OutputName', '',   @(x) ischar(x) || isstring(x));
ip.addParameter('PIVlabRoot', '',   @(x) ischar(x) || isstring(x));
ip.addParameter('ProgressFcn', [],  @(x) isempty(x) || isa(x, 'function_handle'));
ip.addParameter('IntAreas', [64 32 25 16], @(x) isnumeric(x) && numel(x) == 4 && all(x >= 8));
ip.addParameter('NumPasses', 3, @(x) isnumeric(x) && isscalar(x) && any(round(x) == [1 2 3 4]));
ip.addParameter('ROI', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 4));
ip.addParameter('PreprocROI', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 4));
ip.addParameter('Step1Frac', 0.5, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
ip.addParameter('Skip', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
ip.parse(image_folder, varargin{:});
opt = ip.Results;

image_folder = char(image_folder);
numWorkers   = round(opt.NumWorkers);
progFcn      = opt.ProgressFcn;          % digunakan oleh fungsi nested report()

if ~isfolder(image_folder)
	error('PIVlab_automasi:noFolder', 'Folder gambar tidak ditemukan:\n%s', image_folder);
end

%% -------------------------------------------------- lokasi & path PIVlab
if ~isempty(opt.PIVlabRoot)
	pivlab_root = char(opt.PIVlabRoot);
else
	here = fileparts(mfilename('fullpath'));
	cand = fullfile(fileparts(here), 'PIVlab');           % folder PIVlab sebagai "saudara"
	if exist(fullfile(cand, 'PIVlab_GUI.m'), 'file')
		pivlab_root = cand;
	else
		w = which('PIVlab_GUI.m');
		if ~isempty(w)
			pivlab_root = fileparts(w);
		else
			error('PIVlab_automasi:noRoot', ...
				'Folder PIVlab tidak ditemukan. Tentukan lewat opsi ''PIVlabRoot''.');
		end
	end
end
if ~exist(fullfile(pivlab_root, 'PIVlab_GUI.m'), 'file')
	error('PIVlab_automasi:badRoot', 'PIVlabRoot tidak valid:\n%s', pivlab_root);
end
addpath(pivlab_root);   % paket +piv, +preproc, dll. dapat diakses dari sini

%% ----------------------------------------------------- daftar file gambar
suffix = char(opt.Suffix);
if isempty(suffix)
	suffix = detect_suffix(image_folder);
elseif ~startsWith(suffix, '*')
	if ~startsWith(suffix, '.'); suffix = ['.' suffix]; end
	suffix = ['*' suffix];
end

direc = dir(fullfile(image_folder, suffix));
direc = direc(~[direc.isdir]);
if isempty(direc)
	error('PIVlab_automasi:noImages', ...
		'Tidak ada file %s di folder:\n%s', suffix, image_folder);
end
filenames = sort({direc.name});      % sortir leksikografis (sama seperti PIVlab)
filenames = filenames(:);            % jadikan vektor kolom

% Lewati (skip) gambar: ambil tiap (Skip+1) gambar. Skip=0 -> semua;
% Skip=1 -> A,C,E,...; Skip=2 -> A,D,G,...  (subsample SEBELUM membentuk pasangan)
stride = round(opt.Skip) + 1;
if stride > 1
	filenames = filenames(1:stride:end);
end
amount    = numel(filenames);

%% --------------------------------------------------- penyusunan pasangan
if strcmpi(opt.Sequencing, 'pairs')   % [A+B],[C+D],[E+F],...
	if mod(amount, 2) == 1
		amount = amount - 1;           % buang gambar terakhir bila ganjil
		filenames(end) = [];
	end
	fn1 = filenames(1:2:amount-1);
	fn2 = filenames(2:2:amount);
else                                   % consecutive: [A+B],[B+C],[C+D],...
	fn1 = filenames(1:end-1);
	fn2 = filenames(2:end);
end
nPairs = numel(fn1);
if nPairs < 1
	error('PIVlab_automasi:tooFew', 'Butuh minimal 2 gambar untuk analisis PIV.');
end

%% ------------------------------------------------ pengaturan PRA-PROSES (p)
% sesuai screenshot "Image pre-processing"
p = cell(10, 2);
% ROI pra-proses: bila diberi (mis. QPIV strip), CLAHE/Highpass HANYA dihitung
% di dalam strip itu (PIVlab_preproc mengembalikan gambar penuh, hanya ROI yg
% diolah). PIV ROI memakai strip yg sama -> hasil IDENTIK, jauh lebih cepat.
% Default [] = seluruh gambar (perilaku lama persis).
p{1,1}  = 'ROI';               p{1,2}  = opt.PreprocROI;
p{2,1}  = 'CLAHE';             p{2,2}  = 1;       % aktif
p{3,1}  = 'CLAHE size';        p{3,2}  = 64;      % window 64 px
p{4,1}  = 'Highpass';          p{4,2}  = 1;       % aktif
p{5,1}  = 'Highpass size';     p{5,2}  = 15;      % kernel 15 px
p{6,1}  = 'Clipping';          p{6,2}  = 0;       % intensity capping off
p{7,1}  = 'Wiener';            p{7,2}  = 0;       % Wiener2 off
p{8,1}  = 'Wiener size';       p{8,2}  = 3;
p{9,1}  = 'Minimum intensity'; p{9,2}  = 0.0;     % auto contrast stretch min
p{10,1} = 'Maximum intensity'; p{10,2} = 1.0;     % auto contrast stretch max

%% --------------------------------------------------- pengaturan PIV (s)
% sesuai screenshot "PIV settings": Multipass FFT window deformation, 3 lapis.
% Ukuran IW pass 1..4 + jumlah pass + ROI kini dapat di-override lewat opsi
% (default mereproduksi perilaku lama persis: [64 32 25 16], 3 pass, ROI kosong).
ia = round(opt.IntAreas(:)' / 2) * 2;     % paksa genap (mirror piv.piv_FFTmulti)
nPass = round(opt.NumPasses);
s = cell(15, 2);
s{1,1}  = 'Int. area 1';             s{1,2}  = ia(1);                          % pass 1
s{2,1}  = 'Step size 1';             s{2,2}  = max(2, round(ia(1)*opt.Step1Frac)); % step pass 1
s{3,1}  = 'Subpix. finder';          s{3,2}  = 1;         % 1 = Gauss 2x3-point
s{4,1}  = 'Mask';                    s{4,2}  = [];
s{5,1}  = 'ROI';                     s{5,2}  = opt.ROI;   % [] = seluruh gambar
s{6,1}  = 'Nr. of passes';           s{6,2}  = nPass;     % jumlah lapis
s{7,1}  = 'Int. area 2';             s{7,2}  = ia(2);     % pass 2
s{8,1}  = 'Int. area 3';             s{8,2}  = ia(3);     % pass 3
s{9,1}  = 'Int. area 4';             s{9,2}  = ia(4);     % pass 4
s{10,1} = 'Window deformation';      s{10,2} = '*linear'; % Standard (recommended)
s{11,1} = 'Repeated Correlation';    s{11,2} = 0;         % Standard -> repeat 0
s{12,1} = 'Disable Autocorrelation'; s{12,2} = 0;         % checkbox tidak dicentang
s{13,1} = 'Correlation style';       s{13,2} = 0;         % Standard -> do_pad 0
s{14,1} = 'Repeat last pass';        s{14,2} = 0;         % tidak
s{15,1} = 'Last pass quality slope'; s{15,2} = 0.025;

%% ------------------------------------------------- pengaturan VALIDASI
stdThresh    = 8;   % Standard deviation filter
locMedThresh = 3;   % Local median filter
% Velocity limit "inactive" -> valid_vel = [] (di-hardcode di dalam loop)
% Interpolate missing data -> aktif (inpaint_nans, di dalam loop)

%% ------------------------------------------------- pengaturan SMOOTHING
% Slider smoothing PIVlab: min=1, max=11. Posisi MAKSIMAL -> value 11.
% derivative_calc.m: smoothfactor = floor(get(smoothstr,'Value')) = 11
%                    misc.smoothn(u, smoothfactor/10) -> S = 11/10 = 1.1
smoothParam = 11 / 10;   % = 1.1 (kekuatan smoothing maksimal pada slider)

%% --------------------------------------------------------- parallel pool
hasPCT = ~isempty(ver('parallel'));
useParallel = false;
if hasPCT
	report(0, sprintf('Menyiapkan parallel pool (%d worker)...', numWorkers));
	pool = gcp('nocreate');
	if isempty(pool) || pool.NumWorkers ~= numWorkers
		if ~isempty(pool); delete(pool); end
		try
			parpool('local', numWorkers);
		catch
			try
				parpool(numWorkers);
			catch ME
				warning('PIVlab_automasi:pool', ...
					'Gagal membuka pool %d worker (%s). Lanjut tanpa paralel.', ...
					numWorkers, ME.message);
			end
		end
	end
	pool = gcp('nocreate');
	useParallel = ~isempty(pool);
	if useParallel
		% pastikan paket PIVlab ada pada path setiap worker
		try
			fut = parfevalOnAll(@addpath, 0, pivlab_root);
			wait(fut);
		catch
		end
	end
else
	warning('PIVlab_automasi:noPCT', ...
		'Parallel Computing Toolbox tidak terdeteksi. Analisis dijalankan serial.');
end

%% ----------------------------------------------- progres: jumlah unit
unitsDone  = 0;
totalUnits = 2 * nPairs;   % fase PIV (nPairs) + fase validasi/turunan (nPairs)
N = nPairs;   % salinan lokal (tidak di-share dgn fungsi nested) untuk rentang parfor

%% ============================== FASE 1 : PRA-PROSES + ANALISIS PIV ======
report(0, sprintf('Analisis PIV: 0 / %d pasangan', nPairs));
x    = cell(nPairs, 1); y = x; u = x; v = x;
tvec = x; cmap = x;

if useParallel
	dqPIV = parallel.pool.DataQueue;
	afterEach(dqPIV, @tickPIV);
	parfor i = 1:N
		[x{i}, y{i}, u{i}, v{i}, tvec{i}, cmap{i}] = ...
			piv.piv_analysis(image_folder, fn1{i}, fn2{i}, p, s, numWorkers, false);
		send(dqPIV, i);
	end
else
	for i = 1:N
		[x{i}, y{i}, u{i}, v{i}, tvec{i}, cmap{i}] = ...
			piv.piv_analysis(image_folder, fn1{i}, fn2{i}, p, s, 1, false);
		tickPIV();
	end
end

%% ================ FASE 2 : VALIDASI (semua frame) + PARAMETER TURUNAN ===
report(unitsDone / totalUnits, sprintf('Validasi & parameter turunan: 0 / %d frame', nPairs));
u_filt = cell(nPairs, 1); v_filt = u_filt; tv_filt = u_filt;
u_sm   = u_filt;          v_sm   = u_filt;
mag    = u_filt;          strain_r = u_filt;

if useParallel
	dqD = parallel.pool.DataQueue;
	afterEach(dqD, @tickDerive);
	parfor i = 1:N
		[u_filt{i}, v_filt{i}, tv_filt{i}, u_sm{i}, v_sm{i}, mag{i}, strain_r{i}] = ...
			local_validate_derive(u{i}, v{i}, tvec{i}, x{i}, y{i}, ...
				stdThresh, locMedThresh, smoothParam);
		send(dqD, i);
	end
else
	for i = 1:N
		[u_filt{i}, v_filt{i}, tv_filt{i}, u_sm{i}, v_sm{i}, mag{i}, strain_r{i}] = ...
			local_validate_derive(u{i}, v{i}, tvec{i}, x{i}, y{i}, ...
				stdThresh, locMedThresh, smoothParam);
		tickDerive();
	end
end

%% ============================== FASE 3 : EKSPOR KE .MAT =================
report(1, 'Menyimpan hasil ke file .mat ...');

% nama keluaran = nama folder target
ff = regexprep(image_folder, '[\\/]+$', '');     % buang slash di akhir
[~, folderName] = fileparts(ff);
if isempty(opt.OutputName);   outName   = folderName;   else; outName   = char(opt.OutputName);   end
if isempty(opt.OutputFolder); outFolder = image_folder; else; outFolder = char(opt.OutputFolder); end
if ~isfolder(outFolder); mkdir(outFolder); end
outPath = fullfile(outFolder, [outName '.mat']);

% ---- susun variabel dalam format MAT PIVlab standar ----
% (lihat +export/mat_file_save.m). Nama variabel dibuat identik dengan
% ekspor PIVlab GUI sehingga file .mat sepenuhnya kompatibel. Parameter
% turunan yang tidak dihitung dibiarkan sebagai sel kosong, sama seperti
% perilaku PIVlab GUI.
empt = cell(nPairs, 1);
% x, y, u, v, tvec, cmap sudah berisi data per-frame (sel {nPairs x 1})
u_original             = u;
v_original             = v;
typevector_original    = tvec;
u_filtered             = u_filt;
v_filtered             = v_filt;
typevector_filtered    = tv_filt;
u_smoothed             = u_sm;
v_smoothed             = v_sm;
velocity_magnitude     = mag;        % "Displacement magnitude"
strain_rate            = strain_r;   % "Simple strain rate"
vorticity              = empt;
u_component            = empt;
v_component            = empt;
divergence             = empt;
q_criterion            = empt;
shear_rate             = empt;
LIC                    = empt;
vectorangle            = empt;
correlation_map        = cmap;       % koefisien korelasi dari analisis PIV
calxy = 1; calu = 1; calv = 1;
units = '[px] respectively [px/frame]';
information = { ...
	'Dihasilkan otomatis oleh PIVlab_automasi.m'; ...
	'Dimensi pertama variabel adalah nomor frame.'; ...
	'Typevector: 0 = masked, 1 = vektor valid, 2 = vektor terfilter/diinterpolasi.'; ...
	'u_original/v_original = kecepatan mentah dari cross-correlation.'; ...
	'u_filtered/v_filtered = setelah validasi (stdev 8, local median 3) + interpolasi.'; ...
	'u_smoothed/v_smoothed = setelah smoothing (smoothn S=1.1, slider maksimal).'; ...
	'velocity_magnitude & strain_rate dihitung dari vektor yang telah di-smooth.'};

% catatan pengaturan untuk dokumentasi (variabel tambahan, opsional)
automasi_settings = struct();
automasi_settings.preprocess             = p;
automasi_settings.piv                    = s;
automasi_settings.stdev_threshold        = stdThresh;
automasi_settings.local_median_threshold = locMedThresh;
automasi_settings.smoothn_S              = smoothParam;
automasi_settings.num_workers            = numWorkers;
automasi_settings.sequencing             = opt.Sequencing;
automasi_settings.skip                   = round(opt.Skip);
automasi_settings.suffix                 = suffix;
automasi_settings.image_folder           = image_folder;
automasi_settings.num_pairs              = nPairs;

save(outPath, ...
	'x', 'y', 'u_original', 'v_original', 'typevector_original', ...
	'u_filtered', 'v_filtered', 'typevector_filtered', ...
	'u_smoothed', 'v_smoothed', ...
	'vorticity', 'velocity_magnitude', 'u_component', 'v_component', ...
	'divergence', 'q_criterion', 'shear_rate', 'strain_rate', 'LIC', ...
	'vectorangle', 'correlation_map', ...
	'calxy', 'calu', 'calv', 'units', 'information', 'automasi_settings', '-v7.3');

report(1, sprintf('Selesai. Hasil: %s', outPath));

%% ------------------------------------------------------- struct keluaran
results = struct();
results.output_file         = outPath;
results.num_pairs           = nPairs;
results.x                   = x;
results.y                   = y;
results.u_original          = u_original;
results.v_original          = v_original;
results.u_filtered          = u_filtered;
results.v_filtered          = v_filtered;
results.typevector_filtered = typevector_filtered;
results.u_smoothed          = u_smoothed;
results.v_smoothed          = v_smoothed;
results.velocity_magnitude  = velocity_magnitude;
results.strain_rate         = strain_rate;
results.correlation_map     = correlation_map;
results.settings            = automasi_settings;

%% ============================= FUNGSI NESTED ============================
	function report(frac, msg)
		% lapor progres ke GUI (jika ada) atau Command Window
		frac = max(0, min(1, frac));
		if ~isempty(progFcn)
			try
				progFcn(frac, msg);
			catch
			end
		else
			fprintf('[%3.0f%%] %s\n', 100 * frac, msg);
		end
	end

	function tickPIV(~)
		unitsDone = unitsDone + 1;
		report(unitsDone / totalUnits, ...
			sprintf('Analisis PIV: %d / %d pasangan', unitsDone, nPairs));
	end

	function tickDerive(~)
		unitsDone = unitsDone + 1;
		report(unitsDone / totalUnits, ...
			sprintf('Validasi & parameter turunan: %d / %d frame', unitsDone - nPairs, nPairs));
	end
end

%% ========================= SUBFUNGSI (parfor-safe) =====================
function suffix = detect_suffix(folder)
% Deteksi otomatis ekstensi gambar yang paling banyak di dalam folder.
exts = {'*.tif', '*.tiff', '*.jpg', '*.jpeg', '*.png', '*.bmp'};
counts = zeros(numel(exts), 1);
for k = 1:numel(exts)
	d = dir(fullfile(folder, exts{k}));
	counts(k) = sum(~[d.isdir]);
end
[mx, idx] = max(counts);
if mx == 0
	error('PIVlab_automasi:noImages', ...
		'Tidak ditemukan gambar (tif/tiff/jpg/jpeg/png/bmp) di:\n%s', folder);
end
suffix = exts{idx};
end

function [uf, vf, tvf, us, vs, mg, sr] = local_validate_derive(ui, vi, tvi, xi, yi, stdThresh, locMedThresh, S)
% Replikasi 1:1 alur PIVlab untuk satu frame:
%   validate.filtervectors_all_parallel  ->  derivative_calc (smooth, magnitude, strain)
% tanpa memerlukan GUI. Kalibrasi = 1 (data tak terkalibrasi, px/frame).

% --- Validasi vektor (urutan PIVlab: postproc lalu interpolasi) ---
%   valid_vel = []  (velocity limit inactive)
%   do_stdev_check = 1, do_local_median = 1
[uf, vf] = postproc.PIVlab_postproc(ui, vi, 1, 1, [], 1, stdThresh, 1, locMedThresh);

tvf = tvi;
tvf(isnan(uf)) = 2;
tvf(isnan(vf)) = 2;
tvf(tvi == 0)  = 0;     % pertahankan area mask (bila ada)

% --- Interpolate missing data (inpaint_nans, persis seperti GUI) ---
try, uf = misc.inpaint_nans(uf, 4); catch, end
try, vf = misc.inpaint_nans(vf, 4); catch, end

% --- Smoothing kekuatan maksimal (smoothn, S = 1.1) ---
us = misc.smoothn(uf, S);
vs = misc.smoothn(vf, S);

% --- Parameter turunan dari vektor yang TELAH di-smooth ---
% Displacement magnitude (deriv==3): sqrt(u^2 + v^2), subtr=0, cal=1
mg = sqrt(us.^2 + vs.^2);
% Simple strain rate (deriv==9): plot.strain(x, y, u, v), calxy=1
sr = plot.strain(xi, yi, us, vs);
end
