function out = PIVlab_automasi_qpiv(rawFolder, varargin)
%PIVLAB_AUTOMASI_QPIV  Quick PIV (QPIV) pada STRIP tipis sepanjang garis scan.
%
%   Menjalankan analisis PIV HANYA pada sebuah strip (ROI) selebar
%   L_QPIV = 2 x IW pass terakhir, sepanjang seluruh dimensi gambar (P_QPIV),
%   untuk DENGAN CEPAT memperlihatkan displacement per-frame. Hasilnya dipakai
%   menandai frame "mati" (displacement ~nol) sebelum PIV penuh.
%
%   Mesin ini MEMAKAI-ULANG PIVlab_automasi (pipeline preprocess/validasi/
%   smoothing identik dengan PIV penuh, ditambah opsi 'ROI' & 'IntAreas') lalu
%   menulis berkas .mat cache berformat PIVlab standar -> dapat langsung dibaca
%   pivcore.data.buildDataset di jendela QPIV.
%
%   out = PIVlab_automasi_qpiv(rawFolder, 'Name', Value, ...)
%
%   OPSI (Name-Value)
%     'Orient'      : 'Horizontal' (garis kiri<->kanan) | 'Vertical'
%                     (garis atas<->bawah). Default 'Horizontal'.
%     'PosPct'      : posisi garis dalam % (0 = kiri/atas, 100 = kanan/bawah).
%                     Default 50.
%     'IntAreas'    : [1x4] IW pass 1..4 yang DIMINTA. Default [64 32 25 16].
%     'NumPasses'   : jumlah pass diminta (1..4). Default 3.
%     'Suffix'      : pola gambar (mis '*.jpg'). Default deteksi otomatis.
%     'Sequencing'  : 'consecutive' (default) | 'pairs'.
%     'Skip'        : lewati gambar -> ambil tiap (Skip+1) gambar. Default 0.
%     'NumWorkers'  : worker paralel. Default 8 (samakan dgn batch agar pool
%                     tidak dibongkar-pasang).
%     'PIVlabRoot'  : path folder PIVlab. Default deteksi otomatis.
%     'CacheFile'   : path .mat cache keluaran. Default
%                     <rawFolder>/_QPIV_cache.mat.
%     'ProgressFcn' : handle @(frac,msg) untuk laporan progres.
%
%   KELUARAN  out (struct):
%     .x .y .u .v .velocity_magnitude  : cell {nFrames x 1}, koordinat GAMBAR
%                                         PENUH (ROI dipetakan balik oleh PIVlab)
%     .nFrames        : jumlah pasangan PIV
%     .roi            : [xroi yroi widthroi heightroi] (1-based, w/h = SPAN)
%     .orient .posPct : konfigurasi garis scan
%     .iw_passes      : IW diminta (genap) [1x4]
%     .num_passes     : jumlah pass diminta
%     .iw_used        : IW yang BENAR-BENAR dipakai setelah clamp [1x4]
%     .num_passes_used: jumlah pass setelah clamp
%     .iw_max_pass    : IW pass terakhir (px, genap) -> spacing POT & lebar strip
%     .Lwidth         : lebar strip (px) = 2 x iw_max_pass
%     .imageSize      : [H W] gambar
%     .raw_folder     : folder RAW
%     .suffix         : pola gambar terpakai
%     .fn1 .fn2       : nama berkas pasangan per frame (cell {nFrames x 1})
%     .cache_file     : path .mat cache
%     .clamped        : true bila ada pass yang dibuang agar muat di strip
%
%   Lihat juga: PIVlab_automasi, PIVlab_automasi_qpiv_GUI, PIVlab_automasi_progress

addpath(fileparts(mfilename('fullpath')));

%% ----------------------------------------------------------------- input
ip = inputParser;
ip.addRequired('rawFolder', @(x) ischar(x) || isstring(x));
ip.addParameter('Orient', 'Horizontal', @(x) any(strcmpi(x, {'Horizontal','Vertical'})));
ip.addParameter('PosPct', 50, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 100);
ip.addParameter('IntAreas', [64 32 25 16], @(x) isnumeric(x) && numel(x) == 4 && all(x >= 8));
ip.addParameter('NumPasses', 3, @(x) isnumeric(x) && isscalar(x) && any(round(x) == [1 2 3 4]));
ip.addParameter('Suffix', '', @(x) ischar(x) || isstring(x));
ip.addParameter('Sequencing', 'consecutive', @(x) any(strcmpi(x, {'consecutive','pairs'})));
ip.addParameter('Skip', 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
ip.addParameter('NumWorkers', 8, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.addParameter('PIVlabRoot', '', @(x) ischar(x) || isstring(x));
ip.addParameter('CacheFile', '', @(x) ischar(x) || isstring(x));
ip.addParameter('ProgressFcn', [], @(x) isempty(x) || isa(x, 'function_handle'));
ip.addParameter('DryRun', false, @(x) islogical(x) || isnumeric(x));
ip.parse(rawFolder, varargin{:});
opt = ip.Results;

rawFolder = char(rawFolder);
if ~isfolder(rawFolder)
	error('PIVlab_automasi_qpiv:noFolder', 'Folder RAW tidak ditemukan:\n%s', rawFolder);
end
orient = lower(char(opt.Orient));
pos    = double(opt.PosPct);
progFcn = opt.ProgressFcn;

	function report(frac, msg)
		if ~isempty(progFcn); try, progFcn(max(0,min(1,frac)), msg); catch, end; end %#ok<NOSEM,CTCH>
	end

report(0, 'QPIV: menyiapkan strip...');

%% ----------------------------------------- daftar gambar + dimensi
[names, suffix] = i_list_images(rawFolder, char(opt.Suffix));
% Lewati (skip) gambar SEBELUM pasangan: ambil tiap (Skip+1) gambar.
stride = round(opt.Skip) + 1;
if stride > 1 && numel(names) >= 1
	names = names(1:stride:end);
end
if numel(names) < 2
	error('PIVlab_automasi_qpiv:tooFew', ...
		'Butuh minimal 2 gambar (setelah skip) untuk QPIV:\n%s', rawFolder);
end
first = imread(fullfile(rawFolder, names{1}));
H = size(first, 1); W = size(first, 2);

%% ----------------------------------------- IW + clamp (R1) + strip ROI
iaReq = round(opt.IntAreas(:)' / 2) * 2;      % paksa genap (mirror piv_FFTmulti)
npReq = round(opt.NumPasses);
[iaUsed, npUsed, iwMax, iwStrip, clamped] = i_clamp_passes(iaReq, npReq);
% Lebar strip didorong oleh IW TERBESAR yg dipakai (pass-1) supaya pass kasar
% punya ruang (cegah "2 pass gagal"). POT tetap pakai iwMax (terhalus).
Lwidth = 2 * iwStrip;

[roi, Lwidth] = i_strip_roi(orient, pos, H, W, Lwidth);
if clamped
	report(0.02, sprintf(['QPIV: pass kasar dibuang agar muat di strip %dpx ', ...
		'(IW dipakai %s, %d pass).'], Lwidth, mat2str(iaUsed(1:npUsed)), npUsed));
end

%% ----------------------------------------- pasangan frame (untuk peta tampilan)
[fn1, fn2] = i_pairs(names, opt.Sequencing);
nPairs = numel(fn1);

%% ----------------------------------------- path cache (juga utk DryRun)
if isempty(char(opt.CacheFile))
	cacheFile = fullfile(rawFolder, '_QPIV_cache.mat');
else
	cacheFile = char(opt.CacheFile);
end

	function o = i_assemble(nFrames, xc, yc, uc, vc, vmag)
		% Rakit struct keluaran dgn metadata bersama (dipakai DryRun & real).
		o = struct();
		o.x = xc; o.y = yc; o.u = uc; o.v = vc; o.velocity_magnitude = vmag;
		o.nFrames = nFrames;
		o.roi = roi; o.orient = opt.Orient; o.posPct = pos;
		o.iw_passes = iaReq; o.num_passes = npReq;
		o.iw_used = iaUsed; o.num_passes_used = npUsed;
		o.iw_max_pass = iwMax; o.Lwidth = Lwidth;
		o.imageSize = [H W]; o.raw_folder = rawFolder; o.suffix = suffix;
		o.skip = round(opt.Skip); o.sequencing = opt.Sequencing;
		nf = max(0, nFrames);
		o.fn1 = fn1(1:min(nf, numel(fn1)));
		o.fn2 = fn2(1:min(nf, numel(fn2)));
		o.cache_file = cacheFile; o.clamped = clamped;
	end

%% ----------------------------------------- DryRun: metadata saja, tanpa PIV
if opt.DryRun
	out = i_assemble(nPairs, {}, {}, {}, {}, {});
	report(1, sprintf('QPIV DryRun: metadata strip %s (%d frame).', mat2str(roi), nPairs));
	return;
end

%% ----------------------------------------- jalankan PIV pada strip
[cacheDir, cacheName] = fileparts(cacheFile);
if isempty(cacheDir); cacheDir = rawFolder; end
if ~isfolder(cacheDir); mkdir(cacheDir); end

pfWrap = @(frac, msg) report(0.05 + 0.9*frac, ['QPIV: ' msg]);

res = PIVlab_automasi(rawFolder, ...
	'Suffix',       suffix, ...
	'Sequencing',   opt.Sequencing, ...
	'Skip',         round(opt.Skip), ...
	'NumWorkers',   round(opt.NumWorkers), ...
	'PIVlabRoot',   char(opt.PIVlabRoot), ...
	'OutputFolder', cacheDir, ...
	'OutputName',   cacheName, ...
	'IntAreas',     iaUsed, ...
	'NumPasses',    npUsed, ...
	'ROI',          roi, ...
	'PreprocROI',   roi, ...
	'ProgressFcn',  pfWrap);

cacheFile = res.output_file;

%% ----------------------------------------- rangkai keluaran
report(0.97, 'QPIV: memuat hasil strip...');
out = i_assemble(res.num_pairs, res.x, res.y, res.u_smoothed, ...
	res.v_smoothed, res.velocity_magnitude);

report(1, sprintf('QPIV selesai: %d frame, strip %s.', out.nFrames, mat2str(roi)));
end

%% ========================= SUBFUNGSI =====================
function [iaUsed, npUsed, iwMax, iwStrip, clamped] = i_clamp_passes(iaReq, npReq)
%I_CLAMP_PASSES  Pilih pass aktif + tentukan parameter strip.
%   Keluaran:
%     iaUsed  [1x4] IW per pass (diisi ke 4)
%     npUsed  jumlah pass dipakai
%     iwMax   IW pass TERHALUS (terakhir) -> spacing POT
%     iwStrip IW pass TERBESAR (pass-1)   -> lebar strip = 2 x iwStrip
%     clamped true bila ada pass dibuang
%
%   PENTING (perbaikan "QPIV 2 pass selalu gagal"): lebar strip HARUS 2 x IW
%   pass-1 (terbesar), bukan 2 x pass terhalus. Bila tidak, pass-1 IW bisa
%   == lebar strip (mis [64 32] -> strip 64, pass-1 IW 64) sehingga ROI tak
%   cukup untuk grid interogasi -> piv_FFTmulti gagal di interp2.
active = iaReq(1:npReq);             % IW pass aktif (kasar -> halus)
active = active(active >= 8);        % minimal 8 px
if isempty(active); active = 16; end
npUsed  = numel(active);
iwMax   = active(end);               % terhalus -> spacing POT
iwStrip = max(active);               % terbesar -> lebar strip
iaUsed  = [active, repmat(active(end), 1, 4 - npUsed)];
iaUsed  = iaUsed(1:4);
clamped = npUsed < npReq;
end

function [roi, Lwidth] = i_strip_roi(orient, pos, H, W, Lwidth)
%I_STRIP_ROI  Bangun ROI strip [xroi yroi widthroi heightroi] (1-based; w/h=SPAN).
%   Horizontal: garis kiri<->kanan, posisi% = baris (0=atas,100=bawah).
%   Vertical  : garis atas<->bawah, posisi% = kolom (0=kiri,100=kanan).
if strcmpi(orient, 'vertical')
	% strip penuh tinggi, tipis arah-x
	cc = 1 + (pos/100) * (W - 1);          % kolom pusat
	if Lwidth >= W                          % gambar lebih sempit dari strip
		x0 = 1; wSpan = W - 1; Lwidth = W;
	else
		x0 = round(cc - Lwidth/2);
		x0 = max(1, min(x0, W - (Lwidth - 1)));
		wSpan = Lwidth - 1;
	end
	roi = [x0, 1, wSpan, H - 1];
else
	% horizontal: strip penuh lebar, tipis arah-y
	rc = 1 + (pos/100) * (H - 1);          % baris pusat
	if Lwidth >= H                          % gambar lebih pendek dari strip
		y0 = 1; hSpan = H - 1; Lwidth = H;
	else
		y0 = round(rc - Lwidth/2);
		y0 = max(1, min(y0, H - (Lwidth - 1)));
		hSpan = Lwidth - 1;
	end
	roi = [1, y0, W - 1, hSpan];
end
end

function [names, suffix] = i_list_images(folder, suffix)
%I_LIST_IMAGES  Daftar gambar terurut leksikografis + deteksi sufiks otomatis.
exts = {'*.tif','*.tiff','*.jpg','*.jpeg','*.png','*.bmp'};
if isempty(suffix)
	counts = zeros(numel(exts), 1);
	for k = 1:numel(exts)
		d = dir(fullfile(folder, exts{k})); counts(k) = sum(~[d.isdir]);
	end
	[mx, idx] = max(counts);
	if mx == 0
		error('PIVlab_automasi_qpiv:noImages', ...
			'Tidak ada gambar (tif/jpg/png/bmp) di:\n%s', folder);
	end
	suffix = exts{idx};
elseif ~startsWith(suffix, '*')
	if ~startsWith(suffix, '.'); suffix = ['.' suffix]; end
	suffix = ['*' suffix];
end
d = dir(fullfile(folder, suffix));
d = d(~[d.isdir]);
names = sort({d.name});
names = names(:);
end

function [fn1, fn2] = i_pairs(names, seq)
%I_PAIRS  Susun pasangan frame (sama persis PIVlab_automasi).
amount = numel(names);
if strcmpi(seq, 'pairs')
	if mod(amount, 2) == 1; amount = amount - 1; names(end) = []; end
	fn1 = names(1:2:amount-1);
	fn2 = names(2:2:amount);
else
	fn1 = names(1:end-1);
	fn2 = names(2:end);
end
fn1 = fn1(:); fn2 = fn2(:);
end
