function info = PIVlab_automasi_exiftime(exifSource, rawSortedNames, seq, varargin)
%PIVLAB_AUTOMASI_EXIFTIME  Hitung interval waktu per-frame PIV dari EXIF PIVPrep.
%
%   info = PIVlab_automasi_exiftime(exifSource, rawSortedNames, seq)
%   info = PIVlab_automasi_exiftime(..., 'Name', Value, ...)
%
%   Hasil PIV PIVlab bersatuan per-FRAME (px/frame). Untuk dapat dikonversi ke
%   per-DETIK (px/s) di PIVTerry, kita perlu interval waktu nyata antar gambar
%   tiap pasangan. Interval itu diambil dari metadata EXIF yang dikumpulkan
%   PIVPrep menjadi <eksperimen>/EXIF/EXIF.mat (tabel 'exif', 1 baris = 1 gambar
%   masukan; lihat +pivprep/+io/writeExifTable.m & readExifData.m).
%
%   Fungsi ini:
%     1. Memuat tabel EXIF, menemukan kolom NAMA BERKAS (File/Filename/SourceFile)
%        dan kolom WAKTU PEMOTRETAN terbaik (prioritas DateTimeOriginal +
%        SubsecTimeOriginal, lalu DateTimeDigitized, DateTime, terakhir FileModDate).
%     2. Memetakan tiap gambar RAW (dalam urutan PIV = sort leksikografis,
%        identik PIVlab_automasi) ke timestamp EXIF lewat KECOCOKAN NAMA DASAR
%        (RAW '<base>-RAW.jpg' <-> EXIF '<base>.<ext>'), bukan posisi -- aman
%        meski urutan natural-sort EXIF berbeda dari sort leksikografis RAW.
%     3. Menghitung dt per frame sesuai 'seq':
%          'consecutive' : N gambar -> N-1 frame; frame k = (img_k, img_{k+1}),
%                          dt(k) = t(img_{k+1}) - t(img_k).
%          'pairs'       : N gambar -> floor(N/2) frame; frame k = (img_{2k-1},
%                          img_{2k}), dt(k) = t(img_{2k}) - t(img_{2k-1}).
%
%   Frame yang timestamp-nya tak lengkap/tak terbaca -> dt = NaN (DITANDAI;
%   kalibrasi waktu final diputuskan di PIVTerry, fungsi ini tidak menebak).
%
%   INPUT
%     exifSource      : path folder EXIF (berisi EXIF.mat) ATAU path langsung
%                       ke berkas EXIF.mat. '' / tak ada -> status 'TANPA_EXIF'.
%     rawSortedNames  : cellstr nama berkas RAW dalam URUTAN PIV (sort), mis.
%                       hasil sort({dir(fullfile(rawdir,suffix)).name}).
%     seq             : 'consecutive' (default) atau 'pairs'.
%
%   OPSI (Name-Value)
%     'TimeFields' : daftar prioritas kolom waktu (cellstr). Default lihat atas.
%     'LoadTable'  : true (default) muat & kembalikan tabel EXIF mentah di
%                    info.exif_table; false -> hanya hitung waktu (tabel kosong).
%
%   OUTPUT  info (struct)
%     .frame_dt_s     [N x 1] interval detik per frame PIV (NaN bila gagal).
%     .frame_time_s   [N x 1] waktu kumulatif (detik) di awal tiap pasangan,
%                     relatif gambar pertama yang valid (untuk sumbu-X POT).
%     .frame_time_abs {N x 1} cellstr timestamp absolut (ISO) gambar pertama
%                     tiap pasangan; '' bila tak terbaca.
%     .nFrames        jumlah frame PIV.
%     .time_field     char kolom waktu yang dipakai (mis.
%                     'DigitalCamera_DateTimeOriginal') atau '' bila tak ada.
%     .status         'OK' | 'SEBAGIAN' | 'TANPA_EXIF' | 'TANPA_WAKTU'.
%     .n_images       jumlah gambar RAW.
%     .n_matched      gambar RAW yang ketemu padanannya di EXIF.
%     .n_dt_valid     jumlah dt non-NaN.
%     .n_dt_nan       jumlah dt NaN.
%     .dt_median_s    median dt valid (NaN bila tak ada).
%     .dt_mean_s      rata-rata dt valid (NaN bila tak ada).
%     .exif_table     tabel EXIF mentah (kosong bila 'LoadTable' false / gagal).
%     .exif_file      path EXIF.mat yang dimuat ('' bila tak ada).
%     .message        catatan diagnostik (char).
%
%   Lihat juga: PIVlab_automasi_batch_V3, PIVlab_automasi_batch_GUI_V3,
%               PIVlab_automasi_scanprep

ip = inputParser;
ip.addRequired('exifSource');
ip.addRequired('rawSortedNames', @(x) iscell(x) || isstring(x));
ip.addOptional('seq', 'consecutive', @(x) any(strcmpi(x, {'consecutive','pairs'})));
ip.addParameter('TimeFields', { ...
	'DigitalCamera_DateTimeOriginal', ...
	'DigitalCamera_DateTimeDigitized', ...
	'DateTime', ...
	'FileModDate'}, @(x) iscell(x) || isstring(x));
ip.addParameter('LoadTable', true, @(x) islogical(x) || isnumeric(x));
ip.parse(exifSource, rawSortedNames, seq, varargin{:});
opt = ip.Results;

rawSortedNames = cellstr(rawSortedNames(:));
seq = lower(char(opt.seq));
timeFields = cellstr(opt.TimeFields);

% Subsec pendamping untuk tiap kolom waktu (bila ada di tabel).
subsecMap = containers.Map( ...
	{'DigitalCamera_DateTimeOriginal', 'DigitalCamera_DateTimeDigitized', 'DateTime'}, ...
	{'DigitalCamera_SubsecTimeOriginal','DigitalCamera_SubsecTimeDigitized','DigitalCamera_SubsecTime'});

nImg    = numel(rawSortedNames);
nFrames = i_nframes(nImg, seq);

% ---- Kerangka keluaran (default: tanpa EXIF) ----
info = struct();
info.frame_dt_s     = nan(nFrames, 1);
info.frame_time_s   = nan(nFrames, 1);
info.frame_time_abs = repmat({''}, nFrames, 1);
info.nFrames        = nFrames;
info.time_field     = '';
info.status         = 'TANPA_EXIF';
info.n_images       = nImg;
info.n_matched      = 0;
info.n_dt_valid     = 0;
info.n_dt_nan       = nFrames;
info.dt_median_s    = NaN;
info.dt_mean_s      = NaN;
info.exif_table     = table();
info.exif_file      = '';
info.message        = '';

% ---- Temukan EXIF.mat ----
matPath = i_resolve_exif_mat(exifSource);
if isempty(matPath)
	info.message = 'EXIF.mat tidak ditemukan; dt waktu diisi NaN.';
	return;
end
info.exif_file = matPath;

% ---- Muat tabel ----
try
	S = load(matPath);
catch ME
	info.message = sprintf('Gagal memuat %s: %s', matPath, ME.message);
	return;
end
if ~isfield(S, 'exif') || ~istable(S.exif) || height(S.exif) == 0
	info.message = 'EXIF.mat tidak berisi tabel ''exif'' yang valid.';
	return;
end
exif = S.exif;
if logical(opt.LoadTable)
	info.exif_table = exif;
end

vnames = exif.Properties.VariableNames;

% ---- Kolom nama berkas ----
fileCol = i_first_present(vnames, {'File','Filename','SourceFile'});
if isempty(fileCol)
	info.message = 'Kolom nama berkas (File/Filename/SourceFile) tak ada di EXIF.';
	info.status  = 'TANPA_WAKTU';
	return;
end
exifKeys = i_basekeys(i_col_str(exif, fileCol));   % nama-dasar tiap baris EXIF

% ---- Pilih kolom waktu terbaik (prioritas; minimal 2 timestamp valid) ----
bestField = ''; bestTimes = []; bestValid = -1;
for f = 1:numel(timeFields)
	fld = timeFields{f};
	if ~ismember(fld, vnames); continue; end
	raw = i_col_str(exif, fld);
	subStr = [];
	if isKey(subsecMap, fld) && ismember(subsecMap(fld), vnames)
		subStr = i_col_str(exif, subsecMap(fld));
	end
	times = i_parse_times(raw, subStr);
	nv = sum(~isnat(times));
	if nv > bestValid
		bestValid = nv; bestTimes = times; bestField = fld;
	end
	if nv >= 2 && f <= numel(timeFields)
		% Kolom prioritas tertinggi yang cukup -> pakai, hentikan pencarian.
		break;
	end
end

if isempty(bestField) || bestValid < 1 || isempty(bestTimes)
	info.message = 'Tidak ada kolom waktu EXIF yang dapat di-parse.';
	info.status  = 'TANPA_WAKTU';
	return;
end
info.time_field = bestField;

% Peta nama-dasar -> datetime (baris terakhir menang bila ganda).
key2time = containers.Map('KeyType','char','ValueType','double');  % simpan datenum
for i = 1:numel(exifKeys)
	k = exifKeys{i};
	if isempty(k); continue; end
	if ~isnat(bestTimes(i))
		key2time(k) = datenum(bestTimes(i)); %#ok<DATNM>
	end
end

% ---- Timestamp absolut tiap gambar RAW (urutan PIV) ----
tabs = NaT(nImg, 1);
nMatched = 0;
for i = 1:nImg
	k = i_basekey(rawSortedNames{i});
	if isKey(key2time, k)
		tabs(i) = datetime(key2time(k), 'ConvertFrom', 'datenum');
		nMatched = nMatched + 1;
	end
end
info.n_matched = nMatched;

% Acuan t0 = gambar valid paling awal.
validMask = ~isnat(tabs);
if any(validMask)
	t0 = min(tabs(validMask));
else
	t0 = NaT;
end

% ---- dt & waktu kumulatif per frame ----
dt   = nan(nFrames, 1);
tcum = nan(nFrames, 1);
tabsFrame = repmat({''}, nFrames, 1);
for kf = 1:nFrames
	[ia, ib] = i_pair_idx(kf, seq);            % indeks gambar (1-based)
	if ib <= nImg && ~isnat(tabs(ia)) && ~isnat(tabs(ib))
		dt(kf) = seconds(tabs(ib) - tabs(ia));
	end
	if ia <= nImg && ~isnat(tabs(ia))
		if ~isnat(t0); tcum(kf) = seconds(tabs(ia) - t0); end
		tabsFrame{kf} = char(tabs(ia), 'yyyy-MM-dd HH:mm:ss.SSS');
	end
end

info.frame_dt_s     = dt;
info.frame_time_s   = tcum;
info.frame_time_abs = tabsFrame;
info.n_dt_valid     = sum(~isnan(dt));
info.n_dt_nan       = sum(isnan(dt));
if info.n_dt_valid > 0
	info.dt_median_s = median(dt(~isnan(dt)));
	info.dt_mean_s   = mean(dt(~isnan(dt)));
end

if info.n_dt_valid == 0
	info.status = 'TANPA_WAKTU';
	info.message = sprintf(['Kolom waktu ''%s'' ada tetapi tak ada pasangan ' ...
		'frame dengan dua timestamp valid.'], bestField);
elseif info.n_dt_nan > 0 || nMatched < nImg
	info.status = 'SEBAGIAN';
	info.message = sprintf(['%d/%d gambar ter-match EXIF; %d/%d frame ber-dt ' ...
		'valid (sumber: %s).'], nMatched, nImg, info.n_dt_valid, nFrames, bestField);
else
	info.status = 'OK';
	info.message = sprintf('Semua %d frame ber-dt valid (sumber: %s).', nFrames, bestField);
end
end

%% ============================= SUBFUNGSI =============================
function n = i_nframes(nImg, seq)
if nImg < 2; n = 0; return; end
if strcmpi(seq, 'pairs'); n = floor(nImg / 2); else; n = nImg - 1; end
end

function [ia, ib] = i_pair_idx(kf, seq)
if strcmpi(seq, 'pairs'); ia = 2*kf - 1; ib = 2*kf; else; ia = kf; ib = kf + 1; end
end

function p = i_resolve_exif_mat(src)
%I_RESOLVE_EXIF_MAT  Kembalikan path EXIF.mat dari folder/berkas; '' bila nihil.
p = '';
if isempty(src); return; end
src = char(src);
if isfile(src) && endsWith(lower(src), '.mat'); p = src; return; end
if isfolder(src)
	cand = fullfile(src, 'EXIF.mat');
	if isfile(cand); p = cand; return; end
	% case-insensitive / berkas .mat pertama di folder EXIF
	d = dir(fullfile(src, '*.mat'));
	d = d(~[d.isdir]);
	% utamakan yang mengandung 'exif'
	for k = 1:numel(d)
		if ~isempty(regexpi(d(k).name, 'exif', 'once'))
			p = fullfile(src, d(k).name); return;
		end
	end
	if ~isempty(d); p = fullfile(src, d(1).name); end
end
end

function name = i_first_present(have, want)
name = '';
for k = 1:numel(want)
	idx = find(strcmpi(have, want{k}), 1);
	if ~isempty(idx); name = have{idx}; return; end
end
end

function keys = i_basekeys(names)
keys = cell(numel(names), 1);
for i = 1:numel(names); keys{i} = i_basekey(names{i}); end
end

function k = i_basekey(name)
%I_BASEKEY  Nama-dasar ternormalisasi untuk pencocokan RAW<->EXIF.
%   Buang path & ekstensi, lalu buang akhiran '-RAW'/'-GS' bila ada, lowercase.
k = '';
if isempty(name); return; end
[~, base] = fileparts(char(name));
base = regexprep(base, '[-_]?(RAW|GS)$', '', 'ignorecase');
k = lower(strtrim(base));
end

function c = i_col_str(T, name)
%I_COL_STR  Ambil kolom tabel sebagai cellstr Nx1 (apa pun tipenya).
v = T.(name);
n = height(T);
c = repmat({''}, n, 1);
if isstring(v)
	for i = 1:n; if ~ismissing(v(i)); c{i} = char(v(i)); end; end
elseif iscell(v)
	for i = 1:n
		if ischar(v{i}); c{i} = v{i};
		elseif isstring(v{i}) && isscalar(v{i}) && ~ismissing(v{i}); c{i} = char(v{i});
		elseif isnumeric(v{i}) && isscalar(v{i}); c{i} = num2str(v{i});
		end
	end
elseif ischar(v)
	for i = 1:n; c{i} = strtrim(v(i, :)); end
elseif isnumeric(v) || islogical(v)
	for i = 1:n; if ~isnan(double(v(i))); c{i} = num2str(v(i)); end; end
end
end

function times = i_parse_times(rawStr, subStr)
%I_PARSE_TIMES  Parse cellstr timestamp -> datetime array (NaT bila gagal),
%   plus tambahan sub-detik dari subStr bila tersedia & berupa digit.
n = numel(rawStr);
times = NaT(n, 1);
for i = 1:n
	dt = i_parse_one(rawStr{i});
	if ~isnat(dt) && ~isempty(subStr) && i <= numel(subStr)
		frac = i_subsec(subStr{i});
		if ~isnan(frac); dt = dt + seconds(frac); end
	end
	times(i) = dt;
end
end

function dt = i_parse_one(s)
dt = NaT;
s = strtrim(char(s));
if isempty(s) || strcmpi(s, 'NaN') || strcmpi(s, '<missing>') || strcmpi(s, 'NaT')
	return;
end
fmts = {'yyyy:MM:dd HH:mm:ss', 'yyyy-MM-dd HH:mm:ss', ...
	'yyyy:MM:dd HH:mm:ss.SSS', 'yyyy-MM-dd HH:mm:ss.SSS', ...
	'dd-MMM-yyyy HH:mm:ss'};
for i = 1:numel(fmts)
	try
		dt = datetime(s, 'InputFormat', fmts{i});
		if ~isnat(dt); return; end
	catch
	end
end
try
	dt = datetime(s);          % upaya terakhir: parser default
catch
	dt = NaT;
end
end

function frac = i_subsec(s)
%I_SUBSEC  '037' -> 0.037 detik. Hanya digit yang diterima.
frac = NaN;
s = strtrim(char(s));
if isempty(s); return; end
if all(isstrprop(s, 'digit'))
	frac = str2double(['0.' s]);
end
end
