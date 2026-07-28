function entry = unpackMat(matEntry, varargin)
%UNPACKMAT  Bongkar satu .mat PIVPrep single -> folder eksperimen sementara.
%
%   entry = pivanalyzemat.core.unpackMat(matEntry)
%   entry = pivanalyzemat.core.unpackMat(matEntry, 'Name', Value, ...)
%
%   matEntry : satu elemen struct dari pivanalyzemat.core.scanMats (punya
%              field .matfile / .name / .seqmode / .seqstep, dst).
%
%   Membongkar blob RAW + GS + EXIF di dalam .mat menjadi folder sementara yang
%   BERBENTUK PERSIS seperti eksperimen PIVPrep:
%
%       <tmp>/<name>/RAW/   citra RAW (apa adanya, JPEG passthrough)
%       <tmp>/<name>/GS/    citra GS (latar)
%       <tmp>/<name>/EXIF/  EXIF.mat (+ JITTER.* bila ada)
%
%   Dengan begitu SELURUH engine V4/+pivanalyze (PIV, embed GS, waktu EXIF,
%   geometri, Quick PIV, buang frame) berjalan APA ADANYA pada folder ini —
%   tanpa menyentuh logika ilmiah. Hasil bongkar di-cache per-sesi (persistent
%   Map berdasar path .mat); namun PAB Step 2 kini memakai bongkaran secara
%   TEMPORER (on-demand lalu hapus) — pemanggil yang ingin selalu segar mengoper
%   'Force', true dan menghapus folder bongkaran setelah pekerjaan selesai.
%
%   entry (keluaran): salinan matEntry dengan field path/gsdir/expdir/exifdir/
%   unpacked terisi ke folder sementara, siap dipakai pivanalyze.core.processBatch
%   (lewat pivanalyzematToExp) atau langsung sbg job QPIV.
%
%   OPSI
%     'RootTmp' : folder induk untuk hasil bongkar. Default: tempdir kHUSUS
%                 sesi (lihat pivanalyzemat.core.sessionTmpRoot).
%     'Force'   : true = bongkar ulang walau cache ada. Default false.
%     'LogFcn'  : @(str). Default tak ada.
%
%   Lihat juga: pivanalyzemat.core.scanMats, pivanalyzemat.core.cleanupTmp,
%               PIVlab_automasi_fromSingleMat (rujukan unpack RAW)

	persistent CACHE
	if isempty(CACHE)
		CACHE = containers.Map('KeyType', 'char', 'ValueType', 'char');
	end

	ip = inputParser;
	ip.addRequired('matEntry', @isstruct);
	ip.addParameter('RootTmp', '', @(x) ischar(x) || isstring(x));
	ip.addParameter('Force',   false, @(x) islogical(x) || isnumeric(x));
	ip.addParameter('LogFcn',  [], @(x) isempty(x) || isa(x, 'function_handle'));
	ip.addParameter('ProgressFcn', [], @(x) isempty(x) || isa(x, 'function_handle'));
	ip.parse(matEntry, varargin{:});
	opt = ip.Results;
	logf = opt.LogFcn;
	progf = opt.ProgressFcn;   % @(frac, msg) — 0..1 selama dumping isi .mat

	matPath = char(matEntry.matfile);
	if ~isfile(matPath)
		error('pivanalyzemat:unpackMat:noFile', 'Berkas .mat tidak ada:\n%s', matPath);
	end

	% --- root sementara (subfolder hashed di root .mat bila diberikan) ---
	rootTmp = char(opt.RootTmp);
	if isempty(rootTmp); rootTmp = pivanalyzemat.core.sessionTmpRoot(); end
	if ~isfolder(rootTmp); mkdir(rootTmp); end

	% --- cache hit? (hanya valid bila bongkaran lama masih DI BAWAH rootTmp
	%     yang diminta — root bisa berganti antar-pemindaian dlm satu sesi) ---
	cacheKey = i_canon(matPath);
	if ~opt.Force && isKey(CACHE, cacheKey)
		expdirCached = CACHE(cacheKey);
		if isfolder(expdirCached) && isfolder(fullfile(expdirCached, 'RAW')) ...
				&& i_isUnder(expdirCached, rootTmp)
			entry = i_fillEntry(matEntry, expdirCached);
			i_log(logf, '   [cache] pakai bongkaran sebelumnya: %s', expdirCached);
			return;
		else
			remove(CACHE, cacheKey);   % cache basi / root berbeda
		end
	end

	% nama folder unik & mudah dibaca: <name>_<hash8>
	leaf   = i_safeLeaf(matEntry.name);
	tag    = i_hash8(cacheKey);
	expdir = fullfile(rootTmp, sprintf('%s_%s', leaf, tag));
	rawDir  = fullfile(expdir, 'RAW');
	gsDir   = fullfile(expdir, 'GS');
	exifDir = fullfile(expdir, 'EXIF');

	% bila sisa lama -> hapus dulu (Force / cache basi)
	if isfolder(expdir); try, rmdir(expdir, 's'); catch; end; end
	mkdir(rawDir);

	i_log(logf, '   Membongkar %s ...', matEntry.name);
	% --- MEMUAT .mat (bisa LAMA utk data besar): tandai 'loading' supaya GUI
	%     bisa pasang mode indeterminate (animasi jalan, tak terlihat hang). ---
	d = dir(matPath);
	mbFile = 0; if ~isempty(d); mbFile = d(1).bytes / 1048576; end
	i_prog(progf, 0, sprintf('Memuat %s (%.0f MB) ke memori...', matEntry.name, mbFile), ...
		struct('phase', 'loading', 'mb', mbFile));
	S = load(matPath);
	if ~isfield(S, 'prep')
		error('pivanalyzemat:unpackMat:badFile', ...
			'Berkas bukan pivprep_single_v1 (variabel ''prep'' tak ada):\n%s', matPath);
	end
	prep = S.prep;

	% --- Blob-store per-frame: file baru menyimpan blob di variabel braw_*
	%     (prep.raw.blobs KOSONG). unpackMat perlu SEMUA blob -> rakit ulang
	%     prep.raw.blobs dari store (S sudah memuat braw_* karena load penuh). ---
	if isfield(prep, 'raw') && (~isfield(prep.raw, 'blobs') || isempty(prep.raw.blobs)) ...
			&& isfield(S, 'braw_idx')
		prep.raw = i_rebuildRawFromStore(prep.raw, S);
	end

	% --- Masking persegi NON-DESTRUKTIF (opsional): kotak putih ditempel ke
	%     citra RAW saat decode (frame asli di blob TAK tersentuh). GS regen dari
	%     RAW ter-masking otomatis ikut bersih (i_regenGsFromRaw baca RAW). ---
	%     Resep dibaca via prepBlobStore.readMasking: SIDECAR '<nama>_mask.json'
	%     diprioritaskan; fallback warisan pmasking/prep.masking. -> PAB2 produksi
	%     otomatis ter-masking dari sidecar tanpa perubahan PAB2.
	masking = [];
	mCand = [];
	try
		mCand = pivanalyzemat.core.prepBlobStore.readMasking(matPath, true);
	catch
		mCand = [];
	end
	if isempty(mCand)   % fallback ke var in-file yg sudah termuat di S
		if isfield(S, 'pmasking') && ~isempty(S.pmasking)
			mCand = S.pmasking;
		elseif isfield(prep, 'masking')
			mCand = prep.masking;
		end
	end
	rectM = []; polyM = [];
	if ~isempty(mCand) && pivanalyzemat.core.maskRect.isActive(mCand)
		rectM = mCand;
		i_log(logf, '     MASK: kotak aktif (%d)', numel(rectM.boxes));
	end
	% Layer-2 polygon (PABMASK2) dari sidecar v2_poly.
	try
		pCand = pivanalyzemat.core.maskSidecar.readPoly(matPath);
		if ~isempty(pCand) && pivanalyzemat.core.maskPoly.isActive(pCand)
			polyM = pCand;
			i_log(logf, '     MASK: polygon aktif (%d)', numel(polyM.polygons));
		end
	catch
	end
	if ~isempty(rectM) || ~isempty(polyM)
		masking = struct('rect', rectM, 'poly', polyM);   % bundel 2 layer
	end

	% --- RAW (fase dump pertama: 0 -> 0.5) ---
	nRaw = i_writeImages(rawDir, prep.raw, ...
		@(f, det) i_prog(progf, 0.50*f, ...
			sprintf('Menulis RAW %d/%d (%s)', det.k, det.N, det.leaf), ...
			i_mergeDet(det, 'raw')), masking);
	i_log(logf, '     RAW : %d citra', nRaw);

	% --- GS : SELALU diregenerasi DARI RAW (bukan dari blob .mat). ---
	%   Sejak optimasi ukuran, .mat PIVPrep TIDAK lagi menyematkan blob GS;
	%   hanya metadata prep.gs_scale / prep.gs_quality. GS = latar PIVTerry,
	%   murni turunan RAW (imresize lanczos3 + JPEG), tak dipakai komputasi
	%   PIV. Jadi kita bangun ulang di sini agar engine V4 jalan apa adanya.
	%   (Blob GS lama, bila ada di .mat warisan, sengaja diabaikan.)
	[gsScale, gsQuality] = i_gsParams(prep);
	mkdir(gsDir);
	% --- GS (fase dump kedua: 0.5 -> 1.0) ---
	nGs = i_regenGsFromRaw(rawDir, gsDir, gsScale, gsQuality, ...
		@(f, det) i_prog(progf, 0.50 + 0.50*f, ...
			sprintf('Membangun GS %d/%d (%s)', det.k, det.N, det.leaf), ...
			i_mergeDet(det, 'gs')));
	i_log(logf, '     GS  : %d citra (regen dari RAW; scale=%.3g q=%d)', nGs, gsScale, gsQuality);

	% --- EXIF + jitter ---
	if isfield(prep, 'exif') && ~isempty(prep.exif)
		mkdir(exifDir);
		exif = prep.exif; %#ok<NASGU>
		save(fullfile(exifDir, 'EXIF.mat'), 'exif', '-v7');
		if isfield(prep, 'jitter') && ~isempty(prep.jitter)
			jitter = prep.jitter; %#ok<NASGU>
			save(fullfile(exifDir, 'JITTER.mat'), 'jitter', '-v7');
		end
		if isfield(prep, 'jitter_csv') && ~isempty(prep.jitter_csv)
			i_writeText(fullfile(exifDir, 'JITTER.csv'), prep.jitter_csv);
		end
		if isfield(prep, 'jitter_txt') && ~isempty(prep.jitter_txt)
			i_writeText(fullfile(exifDir, 'JITTER_summary.txt'), prep.jitter_txt);
		end
		i_log(logf, '     EXIF: EXIF.mat tertulis');
	end

	CACHE(cacheKey) = expdir;
	i_prog(progf, 1, 'Selesai membongkar.');
	entry = i_fillEntry(matEntry, expdir);
end

%% ===================================================================
function entry = i_fillEntry(matEntry, expdir)
%I_FILLENTRY  Lengkapi entry dengan path folder sementara.
entry = matEntry;
entry.unpacked = expdir;
entry.path     = fullfile(expdir, 'RAW');
gsd = fullfile(expdir, 'GS');
if isfolder(gsd); entry.gsdir = gsd; else; entry.gsdir = ''; end
exd = fullfile(expdir, 'EXIF');
if isfolder(exd); entry.exifdir = exd; else; entry.exifdir = ''; end
% PENTING: expdir DIBIARKAN = path .mat asli (entry.matfile, sudah ada di
% matEntry). Engine memakai expdir HANYA untuk (a) kunci progres QPIV/buang-
% frame — harus STABIL antar-sesi, jadi pakai .mat bukan folder sementara yang
% berganti tiap sesi — dan (b) default OutputFolder (selalu ditimpa di Step 2).
% resolveExifDir mendahulukan entry.exifdir (sudah diisi), jadi tak butuh
% expdir berupa folder nyata. raw_folder/gsdir menunjuk ke folder bongkaran.
end

function raw = i_rebuildRawFromStore(raw, S)
%I_REBUILDRAWFROMSTORE  Susun kembali raw.blobs/index/names dari blob-store
%   (variabel braw_00001..braw_000M + braw_idx) yang sudah termuat di S.
%   Hasilnya berbentuk PERSIS skema lama (jpeg_dedup_v1) supaya i_writeImages
%   jalan apa adanya: blobs = cell blob unik, index = frame->blob unik,
%   names = urutan leksikografis (= urutan frame di braw_idx).
bi = S.braw_idx;
nU = 0;
if isfield(bi, 'nUnique') && ~isempty(bi.nUnique); nU = double(bi.nUnique); end
blobs = cell(nU, 1);
for u = 1:nU
	vn = sprintf('braw_%05d', u);
	if isfield(S, vn); blobs{u} = S.(vn); else; blobs{u} = uint8([]); end
end
raw.blobs = blobs;
raw.index = uint32(bi.index(:));
raw.names = bi.names(:);
if isfield(bi, 'ext') && ~isempty(bi.ext); raw.ext = bi.ext; end
end

function [scale, quality] = i_gsParams(prep)
%I_GSPARAMS  Ambil skala & kualitas GS dari metadata prep (default 0.5/92).
scale = pivanalyzemat.core.prepGsScale(prep);   % skala lewat satu sumber bersama
quality = 92;
if isfield(prep, 'gs_quality') && ~isempty(prep.gs_quality) && isnumeric(prep.gs_quality)
	q = round(double(prep.gs_quality(1)));
	if isfinite(q) && q >= 1 && q <= 100; quality = q; end
elseif isfield(prep, 'gs') && isstruct(prep.gs) && isfield(prep.gs, 'quality') ...
		&& ~isempty(prep.gs.quality) && isnumeric(prep.gs.quality)
	q = round(double(prep.gs.quality(1)));   % warisan: ambil dari prep.gs.quality
	if isfinite(q) && q >= 1 && q <= 100; quality = q; end
end
end

function n = i_regenGsFromRaw(rawDir, gsDir, scale, quality, progFcn)
%I_REGENGSFROMRAW  Bangun GS dari tiap RAW: imresize lanczos3 + JPEG.
%   Persis logika pivprep.io.writeOutputs (latar PIVTerry). Nama keluaran =
%   nama RAW dgn '-RAW'->'-GS' dan ekstensi '.jpg' (urutan leksikografis
%   tetap sejajar RAW -> pemetaan frame->GS tak berubah).
n = 0;
if nargin < 5; progFcn = []; end
patterns = {'*.jpg','*.jpeg','*.png','*.tif','*.tiff','*.bmp'};
names = {};
for i = 1:numel(patterns)
	dd = dir(fullfile(rawDir, patterns{i}));
	for j = 1:numel(dd)
		if ~dd(j).isdir; names{end+1} = dd(j).name; end %#ok<AGROW>
	end
end
names = sort(names);
N = numel(names);
for k = 1:N
	img = imread(fullfile(rawDir, names{k}));
	if scale > 0 && scale < 1
		gsImg = imresize(img, scale, 'lanczos3');
	else
		gsImg = img;
	end
	gsName = i_gsName(names{k});
	imwrite(gsImg, fullfile(gsDir, gsName), 'jpg', 'Quality', quality);
	n = n + 1;
	% GS = imresize+JPEG per citra (relatif berat) -> update tiap frame.
	if ~isempty(progFcn)
		progFcn(k / N, struct('k', k, 'N', N, 'leaf', gsName, 'bytes', 0));
	end
end
end

function gsName = i_gsName(rawName)
%I_GSNAME  Turunkan nama GS dari nama RAW: '-RAW'->'-GS', paksa ekstensi .jpg.
[~, base, ~] = fileparts(rawName);
if endsWith(base, '-RAW', 'IgnoreCase', true)
	base = base(1:end-4);
	gsName = [base '-GS.jpg'];
else
	gsName = [base '-GS.jpg'];
end
end

function n = i_writeImages(destDir, pack, progFcn, masking)
%I_WRITEIMAGES  Tulis blob (dedup) -> berkas di destDir, urut sesuai names.
%
%   Bila `masking` aktif: jalur DECODE blob -> tempel kotak putih
%   (pivanalyzemat.core.maskRect.applyMask) -> RE-ENCODE -> tulis. Bila tidak:
%   passthrough byte apa adanya (cepat, lossless, byte-identik perilaku lama).
%   Indeks frame untuk interpolasi (k) = RANK nama dalam urutan leksikografis
%   (SAMA dgn readMatFrame & PIVlab) supaya kotak konsisten antar-konsumer,
%   tak peduli urutan asli pack.
n = 0;
if nargin < 3; progFcn = []; end
if nargin < 4; masking = []; end
if ~isfield(pack, 'names') || isempty(pack.names); return; end
names = pack.names; idx = double(pack.index(:)); blobs = pack.blobs;
N = numel(names);

% Peta nama -> rank frame (1..N) leksikografis, utk indeks masking.
% masking bisa berupa bundel struct('rect',..,'poly',..) [baru] ATAU struct
% maskRect langsung [warisan]. i_maskActive menangani keduanya.
doMask = i_maskActive(masking);
rankOf = [];
if doMask
	[~, ord] = sort(names(:));
	rankOf = zeros(N, 1);
	rankOf(ord) = 1:N;          % rankOf(k) = posisi names{k} setelah sort
end

% Update lebih SERING utk file besar (citra berat -> tiap 1; ringan -> tiap 5)
% supaya bar terus bergerak & tak terlihat hang.
step = i_progStep(blobs);
for k = 1:N
	if k > numel(idx); break; end
	bi = idx(k);
	if bi < 1 || bi > numel(blobs); continue; end
	nb = numel(blobs{bi});
	if doMask
		nb = i_writeMaskedImage(fullfile(destDir, names{k}), blobs{bi}, ...
			masking, rankOf(k), N);
	else
		i_writeBytes(fullfile(destDir, names{k}), blobs{bi});
	end
	n = n + 1;
	if ~isempty(progFcn) && (mod(k, step) == 0 || k == N)
		progFcn(k / N, struct('k', k, 'N', N, 'leaf', names{k}, 'bytes', nb));
	end
end
end

function nb = i_writeMaskedImage(destPath, bytes, masking, kFrame, N)
%I_WRITEMASKEDIMAGE  Decode blob -> applyMask -> tulis citra ke destPath.
%   Encode pakai ekstensi destPath (JPEG kualitas 95 utk konsumsi PIV; PNG/TIF
%   apa adanya). Bila decode gagal -> fallback passthrough byte asli.
%
%   OPTIMASI: decode blob dari MEMORI (Java ImageIO/raster in-memory) tanpa
%   file temporer -> tak ada tulis+baca+delete per frame (mahal di disk
%   jaringan). Fallback ke jalur file-temp lama utk format yg tak ditangani
%   Java (mis. TIFF, PNG 16-bit) atau bila Java gagal.
nb = numel(bytes);
[~, ~, ext] = fileparts(destPath);
ext = lower(char(ext)); if isempty(ext); ext = '.jpg'; end

img = i_decodeBytes(bytes, ext);   % [] bila gagal

if isempty(img)
	% Decode gagal -> tulis byte asli (jangan korup output). TAPI ini berarti
	% kotak/polygon TAK tertempel di frame ini (area yg harus disembunyikan
	% bocor). Peringatkan agar tak senyap.
	warning('pivanalyzemat:unpackMat:maskDecodeFail', ...
		'Decode gagal utk %s -> frame ini TANPA masking (area bocor).', destPath);
	i_writeBytes(destPath, bytes);
	return;
end

img = i_applyBundle(img, masking, kFrame, N);

switch ext
	case {'.jpg', '.jpeg'}
		imwrite(img, destPath, 'jpg', 'Quality', 95);
	case '.png'
		imwrite(img, destPath, 'png');
	case {'.tif', '.tiff'}
		imwrite(img, destPath, 'tif');
	otherwise
		imwrite(img, destPath, 'jpg', 'Quality', 95);
end
d = dir(destPath); if ~isempty(d); nb = d(1).bytes; end
end

function img = i_decodeBytes(bytes, ext)
%I_DECODEBYTES  Decode blob citra (uint8) -> array MATLAB, TANPA file temporer.
%   Coba Java ImageIO in-memory dulu (byte-identik dgn imread utk JPEG/PNG 8-bit
%   grayscale/RGB, tanpa I/O disk). Fallback ke berkas sementara + imread utk
%   format yg tak didukung Java / bila apa pun gagal. [] bila kedua jalur gagal.
img = [];
% --- Jalur cepat: Java ImageIO dari memori ---
try
	bis = java.io.ByteArrayInputStream(bytes);
	bi  = javax.imageio.ImageIO.read(bis);
	if ~isempty(bi)
		H = double(bi.getHeight); W = double(bi.getWidth);
		ras = bi.getRaster();
		nb = double(ras.getNumBands());
		if nb == 1
			v = ras.getPixels(0, 0, W, H, []);          % row-major W*H
			img = uint8(reshape(v, [W H]).');
		else
			px = bi.getRGB(0, 0, W, H, [], 0, W);       % int32 ARGB row-major
			px = typecast(int32(px), 'uint32');
			R = uint8(bitand(bitshift(px, -16), 255));
			G = uint8(bitand(bitshift(px,  -8), 255));
			B = uint8(bitand(px,               255));
			R = reshape(R, [W H]).'; G = reshape(G, [W H]).'; B = reshape(B, [W H]).';
			img = cat(3, R, G, B);
		end
	end
catch
	img = [];
end
if ~isempty(img); return; end

% --- Fallback: berkas sementara + imread (format aneh / Java gagal) ---
tmp = [tempname ext];
try
	fid = fopen(tmp, 'wb');
	if fid >= 0
		fwrite(fid, bytes, 'uint8'); fclose(fid);
		img = imread(tmp);
	end
catch
	img = [];
end
if isfile(tmp); try, delete(tmp); catch; end; end
end

function tf = i_maskActive(masking)
%I_MASKACTIVE  true bila bundel/warisan punya layer aktif (kotak atau polygon).
tf = false;
if isempty(masking) || ~isstruct(masking); return; end
if isfield(masking,'rect') || isfield(masking,'poly')   % bundel baru
	tf = (isfield(masking,'rect') && pivanalyzemat.core.maskRect.isActive(masking.rect)) ...
	  || (isfield(masking,'poly') && pivanalyzemat.core.maskPoly.isActive(masking.poly));
else                                                    % warisan: maskRect langsung
	tf = pivanalyzemat.core.maskRect.isActive(masking);
end
end

function img = i_applyBundle(img, masking, kFrame, N)
%I_APPLYBUNDLE  Tempel layer-1 (kotak) lalu layer-2 (polygon). Terima bundel
%   struct('rect',..,'poly',..) [baru] atau maskRect langsung [warisan].
if isempty(masking) || ~isstruct(masking); return; end
if isfield(masking,'rect') || isfield(masking,'poly')
	if isfield(masking,'rect') && ~isempty(masking.rect)
		img = pivanalyzemat.core.maskRect.applyMask(img, masking.rect, kFrame, N);
	end
	if isfield(masking,'poly') && ~isempty(masking.poly)
		img = pivanalyzemat.core.maskPoly.applyMask(img, masking.poly, kFrame, N);
	end
else
	img = pivanalyzemat.core.maskRect.applyMask(img, masking, kFrame, N);
end
end

function step = i_progStep(blobs)
%I_PROGSTEP  Frekuensi update: file besar -> tiap frame, kecil -> tiap 5.
step = 5;
if isempty(blobs); return; end
nb = numel(blobs{1});                 % ukuran blob pertama sbg proksi
if nb >= 2*1048576; step = 1;         % >= 2 MB/citra: update tiap frame
elseif nb >= 512*1024; step = 2; end  % >= 0.5 MB: tiap 2
end

function i_writeBytes(p, bytes)
fid = fopen(p, 'wb');
if fid < 0; error('Gagal menulis: %s', p); end
fwrite(fid, bytes, 'uint8');
fclose(fid);
end

function i_writeText(p, txt)
fid = fopen(p, 'w');
if fid < 0; return; end
fwrite(fid, char(txt));
fclose(fid);
end

function leaf = i_safeLeaf(name)
leaf = regexprep(char(name), '[^\w\-]', '_');
if isempty(leaf); leaf = 'exp'; end
if numel(leaf) > 40; leaf = leaf(1:40); end
end

function s = i_canon(p)
s = char(p);
try, s = char(java.io.File(s).getCanonicalPath()); catch; end
end

function tf = i_isUnder(child, parent)
%I_ISUNDER  true bila `child` berada di dalam folder `parent` (canonik, case-insensitif).
c = lower(strrep(i_canon(child),  '\', '/'));
p = lower(strrep(i_canon(parent), '\', '/'));
p = regexprep(p, '/+$', '');
tf = strcmp(c, p) || startsWith(c, [p '/']);
end

function h = i_hash8(str)
persistent md
if isempty(md); md = java.security.MessageDigest.getInstance('MD5'); end
md.reset(); md.update(uint8(char(str)));
digest = typecast(md.digest(), 'uint8');
hx = lower(reshape(dec2hex(digest, 2).', 1, []));
h = hx(1:8);
end

function i_log(logf, varargin)
if isempty(logf); return; end
try, logf(sprintf(varargin{:})); catch; end
end

function i_prog(progf, frac, msg, detail)
%I_PROG  Panggil callback progres dump (0..1) dgn aman (no-op bila kosong).
%   Kompatibel mundur: callback lama @(f,m) tetap jalan; callback baru
%   @(f,m,det) menerima struct detail verbose (phase/k/N/leaf/mb).
if isempty(progf); return; end
if nargin < 3; msg = ''; end
if nargin < 4; detail = struct(); end
try
	if nargin(progf) >= 3 || nargin(progf) < 0   % <0 = anonim varargin/cukup arg
		progf(max(0, min(1, frac)), msg, detail);
	else
		progf(max(0, min(1, frac)), msg);
	end
catch
	try, progf(max(0, min(1, frac)), msg); catch; end
end
end

function det = i_mergeDet(det, phase)
%I_MERGEDET  Sisipkan label fase ke struct detail per-frame.
det.phase = phase;
end
