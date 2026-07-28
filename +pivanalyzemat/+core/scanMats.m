function exps = scanMats(rootFolder, varargin)
%SCANMATS  Pindai folder root untuk berkas .mat PIVPrep single (pivprep_single_v1).
%
%   exps = pivanalyzemat.core.scanMats(rootFolder)
%   exps = pivanalyzemat.core.scanMats(rootFolder, 'Name', Value, ...)
%
%   Padanan PIVlab_automasi_scanprep, TAPI untuk Step 2: alih-alih mencari
%   folder eksperimen (RAW+GS), fungsi ini mencari BERKAS .mat keluaran Step 1
%   (skema 'pivprep_single_v1', lihat pivprepPackFolder). Tiap .mat = satu
%   eksperimen lengkap (blob RAW + GS + EXIF + jitter dalam satu berkas).
%
%   Hanya METADATA ringan yang dibaca di sini (tanpa membongkar blob): jumlah
%   frame, sequencing, jumlah GS, ekstensi. Pembongkaran penuh ke folder
%   sementara dilakukan saat dibutuhkan oleh pivanalyzemat.core.unpackMat.
%
%   Mengembalikan struct-array dengan field yang KOMPATIBEL dengan
%   pivanalyze.core.scanExperiments / processBatch (path/gsdir/expdir diisi
%   nanti oleh unpackMat; di sini diisi penanda + metadata):
%       .matfile  - path berkas .mat sumber (INPUT Step 2)
%       .path     - '' (diisi unpackMat = folder RAW sementara)
%       .gsdir    - '' (diisi unpackMat = folder GS sementara)
%       .expdir   - path berkas .mat (dipakai sbg KUNCI progres/QPIV, stabil)
%       .relpath  - path relatif .mat thd root (tampilan)
%       .name     - nama dasar .mat -> nama keluaran default
%       .count    - jumlah frame RAW (dari prep.nFrames)
%       .gscount  - jumlah citra GS
%       .suffix   - pola ekstensi RAW (mis '*.jpg')
%       .npairs   - perkiraan jumlah pasangan
%       .outname  - nama keluaran (default = .name)
%       .seqmode  - mode sequencing dari .mat ('consecutive'|'pairs'|'skip')
%       .seqstep  - langkah skip dari .mat (>=1)
%       .has_exif - logical, .mat memuat tabel EXIF
%       .unpacked - '' (diisi unpackMat = folder eksperimen sementara)
%
%   OPSI
%     'Recursive'  : true (default) telusuri subfolder bertingkat.
%     'MinFrames'  : minimum frame RAW agar valid (>=2). Default 2.
%     'Sequencing' : override hitung npairs bila .mat tak punya metadata.
%                    'consecutive' (default) | 'pairs'.
%
%   Lihat juga: pivanalyzemat.core.unpackMat, pivprepPackFolder,
%               PIVlab_automasi_scanprep

ip = inputParser;
ip.addRequired('rootFolder', @(x) ischar(x) || isstring(x));
ip.addParameter('Recursive',  true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('MinFrames',  2,    @(x) isnumeric(x) && isscalar(x) && x >= 2);
ip.addParameter('Sequencing', 'consecutive', @(x) any(strcmpi(x, {'consecutive','pairs'})));
ip.parse(rootFolder, varargin{:});
opt = ip.Results;

rootFolder = char(rootFolder);
if ~isfolder(rootFolder)
	error('pivanalyzemat:scanMats:noFolder', ...
		'Folder root tidak ditemukan:\n%s', rootFolder);
end

exps = empty_exps();

mats = i_listMats(rootFolder, logical(opt.Recursive));
pfx  = [rootFolder filesep];

for k = 1:numel(mats)
	mp = mats{k};
	meta = i_readMeta(mp);
	if isempty(meta);            continue; end           % bukan pivprep_single_v1
	if meta.nFrames < opt.MinFrames; continue; end

	% --- npairs sesuai sequencing efektif ---
	[seqMode, seqStep] = i_effSeq(meta, opt.Sequencing);
	npairs = i_npairs(meta.nFrames, seqMode, seqStep);

	[~, nm] = fileparts(mp);
	if startsWith(mp, pfx)
		rel = extractAfter(mp, pfx);
	else
		rel = mp;
	end

	exps(end+1) = struct( ...
		'matfile',  mp, ...
		'path',     '', ...
		'gsdir',    '', ...
		'expdir',   mp, ...           % KUNCI progres = path .mat (stabil antar sesi)
		'relpath',  rel, ...
		'name',     nm, ...
		'count',    meta.nFrames, ...
		'gscount',  meta.nGs, ...
		'suffix',   meta.suffix, ...
		'npairs',   npairs, ...
		'outname',  nm, ...
		'seqmode',  seqMode, ...
		'seqstep',  seqStep, ...
		'has_exif', meta.has_exif, ...
		'unpacked', '', ...
		'pab_src',  meta.pab_src); %#ok<AGROW>
end

if ~isempty(exps)
	[~, ord] = sort({exps.matfile});
	exps = exps(ord);
end
end

%% ===================================================================
function s = empty_exps()
s = struct('matfile', {}, 'path', {}, 'gsdir', {}, 'expdir', {}, 'relpath', {}, ...
	'name', {}, 'count', {}, 'gscount', {}, 'suffix', {}, 'npairs', {}, ...
	'outname', {}, 'seqmode', {}, 'seqstep', {}, 'has_exif', {}, 'unpacked', {}, ...
	'pab_src', {});
end

function mats = i_listMats(root, recursive)
%I_LISTMATS  Daftar semua *.mat di bawah root (rekursif opsional), urut.
mats = {};
d = dir(fullfile(root, '*.mat'));
for k = 1:numel(d)
	% Lewati sidecar cache metadata '<mat>.pmeta.mat' (bukan MAT PREP).
	if ~d(k).isdir && ~endsWith(d(k).name, '.pmeta.mat')
		mats{end+1} = fullfile(root, d(k).name); %#ok<AGROW>
	end
end
if recursive
	items = dir(root);
	for k = 1:numel(items)
		nm = items(k).name;
		if items(k).isdir && ~strcmp(nm,'.') && ~strcmp(nm,'..') && ~startsWith(nm,'.')
			mats = [mats, i_listMats(fullfile(root, nm), true)]; %#ok<AGROW>
		end
	end
end
mats = unique(mats, 'stable');
end

function meta = i_readMeta(matPath)
%I_READMETA  Baca metadata ringan dari .mat -> lewat CACHE sidecar bila valid.
%
%   MAT PREP disimpan '-v7' (terkompresi). '-v7' TIDAK mendukung partial-load,
%   jadi `matfile.prep` atau `load(...,'prep')` selalu DEKOMPRESI SELURUH blob
%   RAW (puluhan-ratusan MB) ke RAM hanya untuk membaca nFrames/format/ext.
%   Dengan banyak .mat di folder, pindai jadi lambat detik-puluhan detik.
%
%   OPTIMASI: simpan metadata ringan ke sidecar '<mat>.pmeta.mat' (beberapa
%   ratus byte) yg divalidasi thd (bytes, datenum) berkas .mat. Pindai pertama
%   tetap load-penuh sekali (tak terhindar utk '-v7') lalu tulis sidecar; pindai
%   berikutnya baca sidecar -> instan. Bila .mat berubah (edit masking dll),
%   ukuran/mtime beda -> cache basi diabaikan & ditulis ulang. Folder read-only
%   -> gagal tulis diabaikan (mundur anggun, sekadar tak ada percepatan).
% (1) TERCEPAT: variabel 'pmeta' top-level terpisah di .mat. '-v7' bisa memuat
%     satu variabel kecil tanpa mendekompresi blob 'prep' -> ≈0 detik. File yg
%     dibuat pivprepPackFolder terbaru sudah punya ini.
meta = i_metaFromPmetaVar(matPath);
if ~isempty(meta); return; end

% (2) sidecar cache '<mat>.pmeta.mat' (file lama; validasi bytes+mtime).
meta = i_metaFromCache(matPath);
if ~isempty(meta); return; end

% (3) TERLAMBAT: load penuh 'prep' (dekompresi blob) — SEKALI utk berkas lama.
%     CATATAN PENTING (perf): JANGAN 'append' pmeta ke .mat besar di sini —
%     save(...,'-append') pada file '-v7' 500 MB me-rewrite SELURUH file (puluhan
%     detik) sehingga pindai jadi sangat lambat. Cukup tulis SIDECAR '<mat>.pmeta
%     .mat' (berkas kecil terpisah, cepat) supaya pindai berikutnya instan.
%     Upgrade in-file (pmeta + blob-store) dilakukan SEKALI saat file benar-benar
%     DIBUKA (readMatFrame -> prepBlobStore.upgradeFile), bukan saat sekadar
%     memindai daftar.
meta = i_readMetaRaw(matPath);
if ~isempty(meta)
	i_writeMetaCache(matPath, meta);         % sidecar kecil (cepat), bukan -append
end
end

function meta = i_metaFromPmetaVar(matPath)
%I_METAFROMPMETAVAR  Baca metadata dari variabel 'pmeta' terpisah (cepat, blob
%   tak disentuh). [] bila var tak ada / bukan skema pmeta.
meta = [];
try
	w = who('-file', matPath);       % daftar variabel (tak muat isi)
	if ~ismember('pmeta', w); return; end
	S = load(matPath, 'pmeta');      % '-v7': muat HANYA var kecil ini
	if ~isfield(S,'pmeta'); return; end
	p = S.pmeta;
catch
	return;
end
if ~isstruct(p) || ~isfield(p,'format'); return; end
if ~strcmpi(char(p.format), 'pivprep_single_v1'); return; end
meta = i_pmetaToMeta(p);
end

function meta = i_pmetaToMeta(p)
%I_PMETATOMETA  Petakan struct 'pmeta' -> struct meta yang dipakai scanMats.
gv = @(nm,df) i_pget(p, nm, df);
meta = struct( ...
	'nFrames',  double(gv('nFrames',0)), ...
	'nGs',      double(gv('nGs',0)), ...
	'suffix',   char(gv('suffix','*.jpg')), ...
	'seqmode',  char(gv('seqmode','consecutive')), ...
	'seqstep',  max(1, round(double(gv('seqstep',1)))), ...
	'has_exif', logical(gv('has_exif',false)), ...
	'pab_src',  char(gv('pab_src','')));
end

function v = i_pget(s, nm, df)
v = df;
if isfield(s, nm) && ~isempty(s.(nm)); v = s.(nm); end
end

function ok = i_upgradePmetaVar(matPath, meta)
%I_UPGRADEPMETAVAR  Tulis variabel 'pmeta' ke .mat lama TANPA menyentuh blob.
%   save(...,'-append') menambah 1 variabel kecil; 'prep' (blob RAW) tetap utuh.
%   true bila berhasil; false bila gagal (mis. read-only) -> pemanggil pakai
%   sidecar cache sebagai gantinya.
ok = false;
try
	pmeta = struct('schema','pivprep_pmeta_v1', ...
		'format','pivprep_single_v1', 'nFrames',meta.nFrames, 'nGs',meta.nGs, ...
		'ext', i_extFromSuffix(meta.suffix), 'suffix',meta.suffix, ...
		'seqmode',meta.seqmode, 'seqstep',meta.seqstep, ...
		'has_exif',meta.has_exif, 'pab_src',meta.pab_src); %#ok<NASGU>
	save(matPath, 'pmeta', '-append');    % -append pertahankan var + versi file
	ok = true;
catch
	ok = false;
end
end

function e = i_extFromSuffix(sfx)
e = char(sfx);
if startsWith(e,'*'); e = e(2:end); end
if isempty(e); e = '.jpg'; end
if ~startsWith(e,'.'); e = ['.' e]; end
end

function meta = i_readMetaRaw(matPath)
%I_READMETARAW  Baca metadata ringan dgn load 'prep' (jalur lambat, sekali saja).
%   Mengembalikan [] bila bukan pivprep_single_v1.
%
%   PERF: pakai load(matPath,'prep'), BUKAN matfile(...).prep. Utk berkas '-v7'
%   keduanya mendekompresi seluruh blob, TAPI matfile.prep ternyata ~3x LEBIH
%   LAMBAT (mis. 13,7s vs 4,5s pada 561 MB) — matfile membuka file & baca skema
%   lebih berat. load partial-variabel lebih cepat.
meta = [];
try
	w = who('-file', matPath);
	if ~ismember('prep', w); return; end
	S = load(matPath, 'prep');             % lebih cepat dari matfile(...).prep
	prep = S.prep;
catch
	return;
end
if ~isstruct(prep) || ~isfield(prep, 'format'); return; end
if ~strcmpi(char(prep.format), 'pivprep_single_v1'); return; end

nF = 0;
if isfield(prep, 'nFrames') && ~isempty(prep.nFrames)
	nF = double(prep.nFrames);
elseif isfield(prep, 'raw') && isfield(prep.raw, 'names')
	nF = numel(prep.raw.names);
end

nGs = 0; sfx = '*.jpg';
if isfield(prep, 'raw') && isfield(prep.raw, 'ext') && ~isempty(prep.raw.ext)
	e = char(prep.raw.ext); if ~startsWith(e,'.'); e = ['.' e]; end
	sfx = ['*' e];
elseif isfield(prep, 'raw') && isfield(prep.raw, 'names') && ~isempty(prep.raw.names)
	[~,~,e] = fileparts(prep.raw.names{1}); if isempty(e); e = '.jpg'; end
	sfx = ['*' e];
end
if isfield(prep, 'gs') && isfield(prep.gs, 'names')
	nGs = numel(prep.gs.names);
elseif isfield(prep, 'gs') && isfield(prep.gs, 'index')
	nGs = numel(prep.gs.index);
end
% GS tak disematkan (gs_embedded=false / blob kosong): GS akan DIREGENERASI
% 1:1 dari RAW saat unpack, jadi laporkan jumlah = #frame RAW (bukan 0)
% supaya laporan/cek-mismatch tidak menyesatkan ("tanpa GS").
if nGs == 0 && nF > 0
	nGs = nF;
end

seqMode = 'consecutive'; seqStep = 1;
if isfield(prep, 'sequencing') && isstruct(prep.sequencing)
	if isfield(prep.sequencing, 'mode') && ~isempty(prep.sequencing.mode)
		seqMode = lower(char(prep.sequencing.mode));
	end
	if isfield(prep.sequencing, 'step') && ~isempty(prep.sequencing.step)
		seqStep = max(1, round(double(prep.sequencing.step)));
	end
end

hasExif = isfield(prep, 'exif') && ~isempty(prep.exif);

% Folder RAW asli (jembatan ke progres QPIV Step 0). '' bila .mat lama tak punya.
pabSrc = '';
if isfield(prep, 'pab_src') && ~isempty(prep.pab_src)
	pabSrc = char(prep.pab_src);
end

meta = struct('nFrames', nF, 'nGs', nGs, 'suffix', sfx, ...
	'seqmode', seqMode, 'seqstep', seqStep, 'has_exif', hasExif, ...
	'pab_src', pabSrc);
end

%% ---- cache metadata (sidecar '<mat>.pmeta.mat') --------------------
function p = i_metaCachePath(matPath)
%I_METACACHEPATH  Nama sidecar cache metadata utk sebuah .mat.
p = [matPath '.pmeta.mat'];
end

function meta = i_metaFromCache(matPath)
%I_METAFROMCACHE  Ambil metadata dari sidecar bila ada & cocok (bytes+datenum).
%   [] bila tak ada / basi / rusak -> pemanggil jatuh ke jalur load penuh.
meta = [];
cp = i_metaCachePath(matPath);
if ~isfile(cp); return; end
try
	d = dir(matPath);
	if isempty(d); return; end
	S = load(cp, 'pmeta');
	if ~isfield(S, 'pmeta'); return; end
	c = S.pmeta;
	% Validasi: berkas .mat tak berubah sejak cache dibuat.
	if ~isfield(c,'src_bytes') || ~isfield(c,'src_datenum') || ~isfield(c,'meta')
		return;
	end
	if c.src_bytes ~= d.bytes; return; end
	if abs(c.src_datenum - d.datenum) > 1e-6; return; end   % mtime beda -> basi
	if ~isfield(c,'ver') || c.ver ~= 1; return; end         % skema cache
	meta = c.meta;
	if ~isstruct(meta) || ~isfield(meta,'nFrames'); meta = []; end
catch
	meta = [];
end
end

function i_writeMetaCache(matPath, meta)
%I_WRITEMETACACHE  Tulis sidecar cache (best-effort; folder read-only diabaikan).
try
	d = dir(matPath);
	if isempty(d); return; end
	pmeta = struct('ver',1, 'src_bytes',d.bytes, 'src_datenum',d.datenum, ...
		'meta',meta); %#ok<NASGU>
	save(i_metaCachePath(matPath), 'pmeta', '-v7');
catch
	% folder read-only / tak bisa tulis -> lewatkan, tetap benar hanya tak cepat.
end
end

function [seqMode, seqStep] = i_effSeq(meta, override)
%I_EFFSEQ  Sequencing efektif: metadata .mat sebagai default, override bila ada.
seqMode = meta.seqmode; seqStep = meta.seqstep;
if ~isempty(override)
	seqMode = lower(char(override));
end
if ~any(strcmp(seqMode, {'consecutive','pairs','skip'})); seqMode = 'consecutive'; end
if ~strcmp(seqMode, 'skip'); seqStep = 1; end
end

function np = i_npairs(nFrames, seqMode, seqStep)
%I_NPAIRS  Perkiraan jumlah pasangan setelah skip + mode.
stride = max(1, round(seqStep));
n = numel(1:stride:max(nFrames,0));
switch seqMode
	case 'pairs'; np = floor(n / 2);
	otherwise;    np = max(0, n - 1);   % consecutive / skip
end
end
