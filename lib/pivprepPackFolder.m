function info = pivprepPackFolder(baseFolder, outMatPath, varargin)
%PIVPREPPACKFOLDER  Kemas SELURUH folder keluaran PIVPrep menjadi SATU file .mat.
%
%   info = pivprepPackFolder(baseFolder, outMatPath)
%   info = pivprepPackFolder(baseFolder, outMatPath, 'Name', Value, ...)
%
%   Keluaran standar BatchPIVPrep2 untuk satu eksperimen adalah sebuah folder
%   "base" yang berisi struktur KOMPLEKS:
%
%       <base>/RAW_<suffix>/    citra hasil stabilisasi+crop (resolusi penuh)
%       <base>/GS_<suffix>/     salinan diperkecil (latar untuk PIVTerry)
%       <base>/EXIF_<suffix>/   EXIF.mat + JITTER.mat/.csv/.txt
%       <base>/ANCHOR_used.mat  preset anchor stabilisasi
%       <base>/CROP_used.mat    preset ROI cropping
%       <base>/JITTER_curve.png kurva jitter
%
%   Fungsi ini "membungkus" semua itu menjadi SATU struct biner `prep` dan
%   menyimpannya ke `outMatPath` (skema 'pivprep_single_v1'). Citra RAW & GS
%   disimpan sebagai BLOB JPEG apa adanya (passthrough, lossless) dengan
%   de-duplikasi berbasis isi -- sehingga 1 eksperimen = 1 berkas, mudah
%   dipindah/diarsip, dan ukurannya tidak lebih besar dari folder aslinya.
%
%   OPSI
%     'Verbose'    : true (default) cetak progres ringkas.
%     'SaveVersion': '-v7' (default; terkompresi) atau '-v7.3'.
%     'EmbedGS'    : true = sematkan blob GS ke .mat (perilaku lama). false
%                    (DEFAULT) = JANGAN simpan blob GS; .mat hanya berisi RAW +
%                    METADATA GS (prep.gs_scale / prep.gs_quality). GS
%                    diregenerasi DARI RAW di hilir (PABSA2 unpack), sehingga
%                    .mat jauh lebih irit. Konsumer yang regen GS membaca
%                    gs_scale/gs_quality ini.
%     'GsScale'    : skala GS 0..1 yang dicatat sbg metadata (default: deteksi
%                    dari rasio dimensi GS thd RAW bila folder GS ada, jika
%                    tidak 0.5).
%     'GsQuality'  : kualitas JPEG GS yang dicatat sbg metadata (default 92).
%     'Sequencing' : struct urutan file untuk konsumer PIV (METADATA saja --
%                    isi RAW/GS tetap SEMUA frame). Field:
%                      .mode  'consecutive' (berurutan) | 'pairs' (berpasangan)
%                             | 'skip' (ambil tiap N: 1,3,5,...)
%                      .step  langkah N untuk mode 'skip' (>=1; default 1).
%                    Ditulis apa adanya ke prep.sequencing. Default:
%                    {mode='consecutive', step=1}. Boleh juga char
%                    'consecutive'/'pairs' (step=1).
%
%   KELUARAN  info (struct): .out_file .nRaw .nGs .raw_blobs .gs_blobs
%             .mat_bytes .folder_bytes (lihat akhir fungsi).
%
%   Lihat juga: pivprepSingle, PIVlab_automasi_fromSingleMat

ip = inputParser;
ip.addRequired('baseFolder',  @(x) ischar(x) || isstring(x));
ip.addRequired('outMatPath',  @(x) ischar(x) || isstring(x));
ip.addParameter('Verbose',     true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('SaveVersion', '-v7', @(x) any(strcmpi(x, {'-v7','-v7.3'})));
ip.addParameter('Sequencing',  [],   @(x) isempty(x) || isstruct(x) || ischar(x) || isstring(x));
ip.addParameter('EmbedGS',     false, @(x) islogical(x) || isnumeric(x));
ip.addParameter('GsScale',     [],   @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('GsQuality',   92,   @(x) isnumeric(x) && isscalar(x));
ip.addParameter('SourceRaw',   '',   @(x) ischar(x) || isstring(x));
ip.parse(baseFolder, outMatPath, varargin{:});
opt = ip.Results;
seq = i_normSequencing(opt.Sequencing);
embedGS = logical(opt.EmbedGS);

baseFolder = char(baseFolder);
outMatPath = char(outMatPath);
vb = logical(opt.Verbose);
if ~isfolder(baseFolder)
	error('pivprepPackFolder:noBase', 'Folder base tidak ditemukan:\n%s', baseFolder);
end

rawDir  = i_findPrefixed(baseFolder, 'RAW');
gsDir   = i_findPrefixed(baseFolder, 'GS');
exifDir = i_findPrefixed(baseFolder, 'EXIF');
if isempty(rawDir)
	error('pivprepPackFolder:noRAW', 'Subfolder RAW tidak ditemukan di:\n%s', baseFolder);
end

%% ------------------------------------------------ kemas RAW & GS jadi blob
if vb; fprintf('[pack] RAW : %s\n', rawDir); end
[rawPack, rawNames] = i_packImageDir(rawDir);
if vb; fprintf('[pack]       %d frame -> %d blob unik\n', numel(rawNames), numel(rawPack.blobs)); end

% --- GS: sematkan blob HANYA bila EmbedGS=true. Default false: GS
%     diregenerasi dari RAW di hilir (lihat unpackMat). .mat cuma simpan
%     metadata gs_scale/gs_quality. Ini sumber penghematan ukuran. ---
gsPack = struct('blobs', {{}}, 'index', uint32([])); gsNames = {};
gsScale   = opt.GsScale;
gsQuality = round(double(opt.GsQuality));
if ~isfinite(gsQuality) || gsQuality < 1 || gsQuality > 100; gsQuality = 92; end
if isempty(gsScale)
	gsScale = i_detectGsScale(rawDir, gsDir);   % deteksi rasio GS:RAW; 0.5 bila gagal
end
if embedGS && ~isempty(gsDir)
	if vb; fprintf('[pack] GS  : %s (embed)\n', gsDir); end
	[gsPack, gsNames] = i_packImageDir(gsDir);
	if vb; fprintf('[pack]       %d frame -> %d blob unik\n', numel(gsNames), numel(gsPack.blobs)); end
elseif vb
	fprintf('[pack] GS  : TIDAK disematkan (regen dari RAW; scale=%.3g q=%d)\n', gsScale, gsQuality);
end

%% --------------------------------------------------------- struct keluaran
prep = struct();
prep.format      = 'pivprep_single_v1';
prep.created     = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
prep.source_base = baseFolder;                 % folder kerja sementara (BUKAN key)
% Folder RAW ASLI eksperimen -> jembatan ke progres Step 0 (QPIV).
%   Step 0b mengunci progres QPIV dengan key = folder RAW. .mat hasil Step 1
%   harus membawa folder itu agar Step 2 bisa menelusuri balik setelan QPIV
%   (mode/skip/ignore/IW). Kanonkan ke path ABSOLUT supaya key cocok dgn Step 0b
%   (yang juga absolut); '' bila tak diberi -> jembatan nonaktif (mundur anggun).
prep.pab_src     = i_canonSrc(opt.SourceRaw);
prep.nFrames     = numel(rawNames);

% --- Urutan file untuk konsumer PIV (METADATA: tidak mengubah isi RAW/GS) ---
%   Ditetapkan di Step 1 (tabel folder BatchPIVPrep2). Konsumer
%   (PIVlab_automasi_fromSingleMat) membaca ini untuk memilih cara membentuk
%   pasangan citra. 'consecutive' = (1,2),(2,3),... ; 'pairs' = (1,2),(3,4),...
%   ; 'skip' = ambil tiap .step frame lebih dulu (1,1+N,1+2N,...) lalu
%   dipasangkan konsekutif.
prep.sequencing = seq;

prep.raw = struct('format', 'jpeg_dedup_v1', 'blobs', {rawPack.blobs}, ...
	'index', rawPack.index, 'names', {rawNames(:)}, 'ext', i_commonExt(rawNames));
% prep.gs : struct yang SAMA bentuknya, tapi blobs/index/names KOSONG bila
% EmbedGS=false (default). gscount tetap = jumlah frame RAW supaya konsumer
% tahu berapa latar yang harus diregenerasi.
prep.gs  = struct('format', 'jpeg_dedup_v1', 'blobs', {gsPack.blobs}, ...
	'index', gsPack.index, 'names', {gsNames(:)}, 'ext', i_commonExt(gsNames), ...
	'quality', gsQuality);

% --- Metadata regenerasi GS dari RAW (dipakai bila blob GS tak ada) ---
prep.gs_embedded = embedGS;       % true bila blob GS benar-benar disematkan
prep.gs_scale    = gsScale;       % 0..1 skala imresize thd RAW
prep.gs_quality  = gsQuality;     % kualitas JPEG GS

% --- Sidecar ilmiah (EXIF, jitter, preset, kurva) : container setia ---
prep.exif            = [];
prep.jitter          = [];
prep.jitter_csv      = '';
prep.jitter_txt      = '';
prep.jitter_curve_png = uint8([]);
prep.anchor_used     = [];
prep.crop_used       = [];

if ~isempty(exifDir)
	prep.exif   = i_loadVar(fullfile(exifDir, 'EXIF.mat'),   'exif');
	prep.jitter = i_loadVar(fullfile(exifDir, 'JITTER.mat'), 'jitter');
	prep.jitter_csv = i_readText(fullfile(exifDir, 'JITTER.csv'));
	prep.jitter_txt = i_readText(fullfile(exifDir, 'JITTER_summary.txt'));
end
prep.anchor_used = i_loadVar(fullfile(baseFolder, 'ANCHOR_used.mat'), 'preset');
prep.crop_used   = i_loadVar(fullfile(baseFolder, 'CROP_used.mat'),   'cropROI');
prep.jitter_curve_png = i_readBytes(fullfile(baseFolder, 'JITTER_curve.png'));

%% ------------------------------------------------------------------- simpan
outDir = fileparts(outMatPath);
if ~isempty(outDir) && ~isfolder(outDir); mkdir(outDir); end
if vb; fprintf('[pack] menyimpan %s (%s)...\n', outMatPath, opt.SaveVersion); end
% Metadata RINGAN terpisah ('pmeta') supaya pindai folder (scanMats) cukup
% load(file,'pmeta') tanpa mendekompresi blob RAW. Lihat pivanalyzemat.core.prepMeta.
pmeta = i_buildPmeta(prep); %#ok<NASGU>

% SKEMA TUNGGAL: 'prep' (blob RAW di prep.raw.blobs) + 'pmeta'. Resep masking
% TIDAK di sini — hidup di SIDECAR '<nama>_mask.json' (pivanalyzemat.core.
% maskSidecar) supaya MAT PREP tak pernah ditulis ulang saat masking berubah.
%
% '-v6' (TANPA kompresi): blob JPEG SUDAH terkompresi -> gzip '-v7' hampir tak
% menghemat ukuran (±7%) tapi 75-100x LEBIH LAMBAT menulis (15-20s vs 0,2s utk
% 500 MB). Kecuali user minta '-v7' eksplisit (opt.SaveVersion), pakai '-v6'.
sv = opt.SaveVersion;
if strcmpi(sv, '-v7'); sv = '-v6'; end   % default '-v7' -> '-v6' (JPEG tak perlu gzip)
save(outMatPath, 'prep', 'pmeta', sv);

%% -------------------------------------------------------------- laporan info
matInfo = dir(outMatPath);
info = struct();
info.out_file     = outMatPath;
info.nRaw         = numel(rawNames);
info.nGs          = numel(gsNames);
info.raw_blobs    = numel(rawPack.blobs);
info.gs_blobs     = numel(gsPack.blobs);
info.mat_bytes    = matInfo.bytes;
info.folder_bytes = i_dirBytes(baseFolder);
if vb
	fprintf('[pack] SELESAI. folder=%.2f MB -> mat=%.2f MB (%.1f%%)\n', ...
		info.folder_bytes/1e6, info.mat_bytes/1e6, ...
		100*info.mat_bytes/max(info.folder_bytes,1));
end
end

%% ====================================================================
function seq = i_normSequencing(s)
%I_NORMSEQUENCING  Normalkan opsi 'Sequencing' -> struct {mode, step} baku.
%   Terima: [] (default consecutive), char/string ('consecutive'|'pairs'|
%   'skip'), atau struct dgn field .mode / .step. Mode tak dikenal -> jatuh
%   ke 'consecutive'. step di-clamp ke bilangan bulat >= 1.
seq = struct('mode', 'consecutive', 'step', 1);
if isempty(s); return; end
if ischar(s) || isstring(s)
	seq.mode = i_validMode(char(s));
	return;
end
if isstruct(s)
	if isfield(s, 'mode') && ~isempty(s.mode)
		seq.mode = i_validMode(char(s.mode));
	end
	if isfield(s, 'step') && ~isempty(s.step) && isnumeric(s.step)
		seq.step = max(1, round(double(s.step(1))));
	end
end
% step hanya relevan untuk 'skip'; mode lain dipaksa step = 1.
if ~strcmpi(seq.mode, 'skip'); seq.step = 1; end
end

function m = i_validMode(m)
m = lower(strtrim(char(m)));
if ~any(strcmp(m, {'consecutive', 'pairs', 'skip'}))
	m = 'consecutive';
end
end

%% ====================================================================
function src = i_canonSrc(s)
%I_CANONSRC  Siapkan folder RAW sumber sbg key QPIV (jembatan Step 0 -> Step 2).
%   '' / kosong -> '' (jembatan nonaktif). Tujuan: key (i_key, leksikal) HARUS
%   cocok dgn yang disimpan Step 0b. Step 0b menyimpan path APA ADANYA (dari
%   dialog/tabel), jadi kita TIDAK boleh me-resolusi symlink (mis. /tmp ->
%   /private/tmp di macOS) yg justru mengubah bentuk & merusak kecocokan.
%   Kita HANYA jadikan absolut bila relatif (tanpa mengubah komponen lain),
%   karena Step 0b memang menyimpan path absolut.
src = char(s);
if isempty(src); return; end
% Sudah absolut? (POSIX '/...', UNC '\\...', atau drive Windows 'C:\') -> biarkan.
isAbs = ~isempty(regexp(src, '^([/\\]|[A-Za-z]:[/\\])', 'once'));
if ~isAbs
	src = fullfile(pwd, src);   % absolut tanpa resolve symlink
end
end

%% ====================================================================
function [pack, names] = i_packImageDir(d)
%I_PACKIMAGEDIR  Baca semua citra (urut leksikografis) -> blob JPEG dedup.
patterns = {'*.jpg','*.jpeg','*.png','*.tif','*.tiff','*.bmp'};
seen = containers.Map('KeyType','char','ValueType','logical');
names = {};
for i = 1:numel(patterns)
	dd = dir(fullfile(d, patterns{i}));
	for j = 1:numel(dd)
		if ~dd(j).isdir && ~isKey(seen, dd(j).name)
			seen(dd(j).name) = true;
			names{end+1} = dd(j).name; %#ok<AGROW>
		end
	end
end
names = sort(names);
n = numel(names);

blobs = {};
index = zeros(n, 1, 'uint32');
hashMap = containers.Map('KeyType','char','ValueType','uint32');
for k = 1:n
	bytes = i_readBytes(fullfile(d, names{k}));
	if isempty(bytes); index(k) = 0; continue; end
	key = i_md5(bytes);
	if isKey(hashMap, key)
		index(k) = hashMap(key);
	else
		blobs{end+1,1} = bytes; %#ok<AGROW>
		idx = uint32(numel(blobs));
		hashMap(key) = idx;
		index(k) = idx;
	end
end
pack = struct('blobs', {blobs}, 'index', uint32(index));
end

%% ====================================================================
function s = i_detectGsScale(rawDir, gsDir)
%I_DETECTGSSCALE  Tebak skala GS dari rasio lebar GS:RAW (frame pertama).
%   Bila folder GS tak ada atau gagal baca dimensi -> 0.5 (default umum).
s = 0.5;
if isempty(gsDir) || ~isfolder(gsDir) || isempty(rawDir) || ~isfolder(rawDir)
	return;
end
try
	rw = i_firstImgWidth(rawDir);
	gw = i_firstImgWidth(gsDir);
	if ~isempty(rw) && ~isempty(gw) && rw > 0
		r = gw / rw;
		if isfinite(r) && r > 0 && r <= 1.0001
			s = min(1, r);
		end
	end
catch
end
end

function w = i_firstImgWidth(d)
%I_FIRSTIMGWIDTH  Lebar (piksel) citra pertama (leksikografis) di folder d.
w = [];
patterns = {'*.jpg','*.jpeg','*.png','*.tif','*.tiff','*.bmp'};
names = {};
for i = 1:numel(patterns)
	dd = dir(fullfile(d, patterns{i}));
	for j = 1:numel(dd)
		if ~dd(j).isdir; names{end+1} = dd(j).name; end %#ok<AGROW>
	end
end
if isempty(names); return; end
names = sort(names);
info = imfinfo(fullfile(d, names{1}));
w = info(1).Width;
end

%% ====================================================================
function p = i_findPrefixed(base, prefix)
%I_FINDPREFIXED  Cari subfolder bernama <prefix> atau <prefix>_<suffix>.
p = '';
d = dir(base);
lp = lower(prefix);
for i = 1:numel(d)
	if d(i).isdir && ~strcmp(d(i).name,'.') && ~strcmp(d(i).name,'..')
		ln = lower(d(i).name);
		if strcmp(ln, lp) || startsWith(ln, [lp '_'])
			p = fullfile(base, d(i).name); return;
		end
	end
end
end

function bytes = i_readBytes(p)
bytes = uint8([]);
if isempty(p) || ~isfile(p); return; end
fid = fopen(p, 'rb');
if fid < 0; return; end
bytes = fread(fid, Inf, '*uint8');
fclose(fid);
bytes = bytes(:);
end

function txt = i_readText(p)
txt = '';
b = i_readBytes(p);
if ~isempty(b); txt = char(b(:)'); end
end

function v = i_loadVar(p, name)
v = [];
if isempty(p) || ~isfile(p); return; end
try
	S = load(p);
	if isfield(S, name)
		v = S.(name);
	else
		fn = fieldnames(S);
		if ~isempty(fn); v = S.(fn{1}); end
	end
catch
	v = [];
end
end

function e = i_commonExt(names)
e = '';
if isempty(names); return; end
[~,~,e] = fileparts(names{1});
end

function key = i_md5(bytes)
persistent md
if isempty(md); md = java.security.MessageDigest.getInstance('MD5'); end
md.reset(); md.update(bytes);
digest = typecast(md.digest(), 'uint8');
key = lower(reshape(dec2hex(digest, 2).', 1, []));
end

function nbytes = i_dirBytes(d)
%I_DIRBYTES  Total ukuran logis semua berkas di bawah folder (rekursif).
nbytes = 0;
items = dir(d);
for i = 1:numel(items)
	if strcmp(items(i).name,'.') || strcmp(items(i).name,'..'); continue; end
	p = fullfile(d, items(i).name);
	if items(i).isdir
		nbytes = nbytes + i_dirBytes(p);
	else
		nbytes = nbytes + items(i).bytes;
	end
end
end

function pmeta = i_buildPmeta(prep)
%I_BUILDPMETA  Metadata ringan terpisah (lihat pivanalyzemat.core.prepMeta).
%   Pakai engine kanonik bila terjangkau; fallback minimal supaya pack tak gagal.
try
	pmeta = pivanalyzemat.core.prepMeta(prep);
	return;
catch
end
nF = 0;
if isfield(prep,'nFrames') && ~isempty(prep.nFrames)
	nF = double(prep.nFrames);
elseif isfield(prep,'raw') && isfield(prep.raw,'names')
	nF = numel(prep.raw.names);
end
pmeta = struct('schema','pivprep_pmeta_v1', ...
	'format', i_getf(prep,'format',''), 'nFrames', nF, 'nGs', nF, ...
	'ext','.jpg', 'suffix','*.jpg', 'seqmode','consecutive', 'seqstep',1, ...
	'has_exif', isfield(prep,'exif') && ~isempty(prep.exif), ...
	'pab_src', i_getf(prep,'pab_src',''));
end

function v = i_getf(s, name, dflt)
v = dflt;
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)); v = s.(name); end
end

