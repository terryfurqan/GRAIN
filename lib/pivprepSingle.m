function out = pivprepSingle(rawFolder, anchor, crop, cfg, outMatPath, varargin)
%PIVPREPSINGLE  Jalankan PIVPrep standar pada satu folder -> SATU file .mat.
%
%   out = pivprepSingle(rawFolder, anchor, crop, cfg, outMatPath)
%   out = pivprepSingle(..., 'Name', Value, ...)
%
%   Ini adalah PIVPrep "single output": melakukan SELURUH analisis standar
%   PIVPrep (stabilisasi SURF -> cropping, EXIF, container jitter, preset
%   anchor/crop, kurva jitter) dengan MEMAKAI ULANG modul ilmiah yang sudah
%   ada (batchpivprep2.core.processFolder + paket +pivprep), lalu MEMBUNGKUS
%   seluruh keluaran folder kompleks itu menjadi SATU berkas .mat
%   ('pivprep_single_v1') lewat pivprepPackFolder.
%
%   Alur: RAW folder --(processFolder, ke folder sementara)--> struktur
%   folder standar --(pivprepPackFolder)--> 1 .mat. Folder sementara dihapus
%   kecuali 'KeepWorkDir' = true.
%
%   ARGUMEN
%     rawFolder  folder berisi citra RAW sekuensial.
%     anchor     struct preset anchor stabilisasi (batchpivprep2.io.anchorPreset).
%     crop       struct preset ROI cropping (batchpivprep2.io.cropPreset).
%     cfg        struct konfigurasi processFolder (suffix, stabMethod, jitterTol,
%                rawFormat, rawQuality, gsScale, gsQuality, ...). Field yang
%                hilang diisi default standar GUI.
%     outMatPath path .mat keluaran tunggal.
%
%   OPSI
%     'WorkDir'     folder kerja sementara (default: tempname).
%     'KeepWorkDir' true -> JANGAN hapus folder kerja (untuk membandingkan
%                   ukuran folder-vs-mat). Default false.
%     'Verbose'     default true.
%
%   KELUARAN  out (struct): .out_file .work_base .stats (dari processFolder)
%             .pack (info pivprepPackFolder) .elapsed_prep .elapsed_pack.
%
%   Lihat juga: pivprepPackFolder, PIVlab_automasi_fromSingleMat

ip = inputParser;
ip.addParameter('WorkDir',     '',   @(x) ischar(x) || isstring(x));
ip.addParameter('KeepWorkDir', false, @(x) islogical(x) || isnumeric(x));
ip.addParameter('Verbose',     true, @(x) islogical(x) || isnumeric(x));
ip.parse(varargin{:});
o = ip.Results;
vb = logical(o.Verbose);

pab_setup();   % bootstrap path PAB_SA (paket + lib + PIVlab inti)

rawFolder = char(rawFolder);
if ~isfolder(rawFolder)
	error('pivprepSingle:noFolder', 'Folder RAW tidak ditemukan:\n%s', rawFolder);
end

%% --- konfigurasi standar (lengkapi default GUI BatchPIVPrep2) ---
cfg = i_defaultCfg(cfg);

%% --- daftar berkas (urut leksikografis, sama seperti PIVlab/PIVPrep) ---
suffix = cfg.inSuffix;
direc = dir(fullfile(rawFolder, suffix));
direc = direc(~[direc.isdir]);
if isempty(direc)
	error('pivprepSingle:noImages', 'Tidak ada %s di:\n%s', suffix, rawFolder);
end
files = sort({direc.name});
files = files(:);

%% --- folder kerja sementara untuk keluaran processFolder ---
if isempty(o.WorkDir); workRoot = [tempname '_pivprep']; else; workRoot = char(o.WorkDir); end
if ~isfolder(workRoot); mkdir(workRoot); end

[~, expName] = fileparts(regexprep(rawFolder, '[\\/]+$', ''));
if isempty(expName); expName = 'exp'; end

folder = struct('path', rawFolder, 'files', {files}, 'outName', expName);

% Mode 'root' -> tulis ke <workRoot>/<expName> (1 folder eksperimen standar).
% PENTING: processFolder MEMBERSIHKAN nama folder (spasi -> '_', dll) via
% local_sanitize. Kita harus memakai nama BERSIH yang SAMA untuk workBase,
% jika tidak pivprepPackFolder gagal menemukan folder (mis. '5 cm-1' -> '5_cm-1').
cfg.outputMode = 'root';
cfg.outputRoot = workRoot;
safeName = i_sanitizeName(expName);
workBase = fullfile(workRoot, safeName);

%% --- FASE A: PIVPrep standar (reuse processFolder) ---
if vb; fprintf('=== PIVPrep standar (stabilisasi+crop) %d frame ===\n', numel(files)); end
tPrep = tic;
prog = [];
if vb
	prog = @(k, nF, s) i_tick(k, nF);
end
stats = batchpivprep2.core.processFolder(folder, anchor, crop, cfg, prog);
elapsedPrep = toc(tPrep);
if vb
	fprintf('\n[prep] selesai %.1f s | OK %d / Skip %d | crop %s -> %d x %d px\n', ...
		elapsedPrep, stats.nOK, stats.nSkip, stats.cropMode, stats.outSize(2), stats.outSize(1));
end

%% --- FASE B: bungkus folder kompleks -> 1 .mat ---
%   GS TIDAK disematkan (EmbedGS=false): .mat hanya RAW + metadata GS
%   (gs_scale/gs_quality dari cfg). GS diregenerasi dari RAW saat analisis
%   (unpackMat) -> .mat lebih irit. Latar = turunan RAW, bukan dipakai PIV.
tPack = tic;
packInfo = pivprepPackFolder(workBase, outMatPath, 'Verbose', vb, ...
	'EmbedGS', false, 'GsScale', cfg.gsScale, 'GsQuality', cfg.gsQuality, ...
	'SourceRaw', rawFolder);   % jembatan key QPIV Step 0 -> .mat (lihat prep.pab_src)
elapsedPack = toc(tPack);

%% --- bersihkan folder kerja (kecuali diminta disimpan) ---
if ~logical(o.KeepWorkDir)
	try, rmdir(workRoot, 's'); catch; end
end

out = struct();
out.out_file      = outMatPath;
out.work_base     = workBase;
out.kept_work     = logical(o.KeepWorkDir);
out.stats         = stats;
out.pack          = packInfo;
out.elapsed_prep  = elapsedPrep;
out.elapsed_pack  = elapsedPack;
end

%% ====================================================================
function cfg = i_defaultCfg(cfg)
if nargin < 1 || isempty(cfg); cfg = struct(); end
d = struct( ...
	'suffix',       '', ...            % sufiks nama folder keluaran (RAW/GS/EXIF)
	'inSuffix',     '*.jpg', ...       % pola berkas INPUT RAW
	'stabMethod',   'surf', ...
	'jitterTol',    2, ...
	'roiPad',       50, ...
	'surfMaxRatio', 0.60, ...
	'minMatchPts',  4, ...
	'marginEnabled', true, ...
	'marginPx',     10, ...
	'rawFormat',    'jpg', ...
	'rawQuality',   90, ...
	'gsScale',      0.50, ...
	'gsQuality',    85);
fn = fieldnames(d);
for k = 1:numel(fn)
	if ~isfield(cfg, fn{k}) || isempty(cfg.(fn{k}))
		cfg.(fn{k}) = d.(fn{k});
	end
end
% normalisasi inSuffix
s = char(cfg.inSuffix);
if ~startsWith(s, '*')
	if ~startsWith(s, '.'); s = ['.' s]; end
	s = ['*' s];
end
cfg.inSuffix = s;
end

function s = i_sanitizeName(s)
%I_SANITIZENAME  Samakan PERSIS dengan local_sanitize di processFolder.
s = regexprep(s, '[\\/:*?"<>|]', '_');
s = regexprep(s, '\s+', '_');
end

function i_tick(k, nF)
if mod(k, max(1, round(nF/20))) == 0 || k == nF
	fprintf('  [prep] frame %d / %d\n', k, nF);
end
end
