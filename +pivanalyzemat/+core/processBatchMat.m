function [summary, aborted] = processBatchMat(matEntries, cfg)
%PROCESSBATCHMAT  Batch analisis PIV Step 2 dengan input .mat (pivprep_single_v1).
%
%   [summary, aborted] = pivanalyzemat.core.processBatchMat(matEntries, cfg)
%
%   matEntries : struct-array dari pivanalyzemat.core.scanMats (tiap elemen =
%                satu .mat PIVPrep single; punya .matfile/.X0/.X1/.Lpos/.outname).
%   cfg        : struct dari pivanalyze.config (opsi engine, IDENTIK V4/V5).
%
%   Alur (REUSE PENUH engine V4/+pivanalyze, tanpa mengubah logika ilmiah):
%     1. Nama keluaran unik + laporan dihitung SEKALI dari METADATA semua .mat
%        (pivanalyze.core.scanExperiments; TIDAK menyentuh disk / tidak unpack).
%     2. DUMP TEMPORER PER-EKSPERIMEN: tiap .mat dibongkar ke folder kerja
%        TEPAT sebelum diproses, dioper ke pivanalyze.core.processBatch (PIV +
%        embed GS + waktu EXIF + geometri + Quick PIV + buang frame), lalu folder
%        bongkarannya LANGSUNG DIHAPUS. Jadi maksimal SATU eksperimen menempati
%        disk pada satu waktu — tak ada pembengkakan di muka, tak ada artefak
%        tertinggal setelah batch (sesuai prinsip "dump sangat temporer").
%
%   Penamaan keluaran unik & laporan dilakukan oleh
%   pivanalyze.core.scanExperiments (dengan cfg.Folders sudah diisi), sama
%   seperti V5. Folder output (cfg.OutputFolder) ditetapkan pemanggil
%   (Step 2 = PIV_<tgl>/ di dalam root .mat).
%
%   Lihat juga: pivanalyzemat.core.scanMats, pivanalyzemat.core.unpackMat,
%               pivanalyze.core.processBatch, PIVlab_automasi_batch_V4

	pivanalyze_addpaths_safe();

	log = cfg.LogFcn;
	if isempty(log); log = @(s) fprintf('%s\n', s); end

	checkAbort = cfg.CheckAbort;
	if isempty(checkAbort); checkAbort = @() false; end

	% Progres global: tiap exp diproses sendiri (processBatch melihat nFolders=1),
	% jadi kita petakan fraksi 0..1 per-exp ke porsi (i-1+frac)/nF batch penuh.
	gpf = [];
	if isfield(cfg, 'ProgressFcn'); gpf = cfg.ProgressFcn; end

	% Folder induk bongkaran: cfg.UnpackRoot (Step 2 = subfolder hashed DI DALAM
	% root .mat) bila diberikan; selainnya unpackMat pakai tempdir per-sesi.
	unpackRoot = '';
	if isfield(cfg, 'UnpackRoot') && ~isempty(cfg.UnpackRoot)
		unpackRoot = char(cfg.UnpackRoot);
	end

	n = numel(matEntries);
	summary = i_emptySummary();
	aborted = false;
	if n == 0
		log('Tidak ada berkas .mat untuk diproses.');
		return;
	end

	% --- FASE 0: nama keluaran unik + laporan DARI METADATA (tanpa unpack) ---
	% Bangun 'folders' metadata (RAW/GS/EXIF belum diisi — diisi per-exp saat
	% dibongkar). scanExperiments hanya menormalkan field + menghitung nama unik
	% + laporan; TIDAK menyentuh disk. Ini memastikan dedup nama lintas-eksperimen
	% tetap benar walau kita memproses (dan menghapus) satu per satu.
	metaFolders = i_emptyFolders();
	for i = 1:n
		metaFolders(end+1) = i_toMetaEntry(matEntries(i)); %#ok<AGROW>
	end
	cfg.Folders = metaFolders;
	[metaFolders, info] = pivanalyze.core.scanExperiments('', cfg);
	if info.nFolders == 0
		log('Tidak ada eksperimen valid.');
		return;
	end
	nF = numel(metaFolders);

	% --- FASE 1: DUMP TEMPORER PER-EKSPERIMEN: bongkar -> proses -> HAPUS ---
	% Maksimal satu eksperimen menempati disk pada satu waktu. cfg.Folders dikunci
	% (per-exp diisi sendiri) supaya processBatch tidak memindai ulang.
	% Ringkasan dikumpulkan sbg cell lalu digabung di akhir (hindari ketergantungan
	% urutan-field saat concat struct-array).
	% scanExperiments mempertahankan URUTAN -> metaFolders(i) padan matEntries(i).
	% Bongkar selalu dari matEntries(i) (punya .matfile); nama unik dari metaFolders.
	cfgOne = cfg;
	resCells = {};
	for i = 1:nF
		if checkAbort(); aborted = true; break; end
		mf  = metaFolders(i);     % metadata + outname unik (tanpa .matfile)
		src = matEntries(i);      % entry .mat asli (punya .matfile utk unpack)
		log(sprintf('[%d/%d] Membongkar %s ke folder kerja (temporer)...', i, nF, mf.relpath));

		% (1) bongkar .mat ke folder kerja (RAW + GS regen + EXIF)
		try
			e = pivanalyzemat.core.unpackMat(src, 'LogFcn', log, 'RootTmp', unpackRoot, ...
				'Force', true);   % temporer: selalu bongkar baru (tak menumpuk cache)
		catch ME
			log(sprintf('   [!] Gagal membongkar %s: %s', mf.name, ME.message));
			continue;
		end
		unpackedDir = e.unpacked;   % folder kerja exp ini (akan dihapus setelah proses)

		% (2) proses SATU eksperimen (PIV + GS + EXIF + geometri + buang frame).
		%     Pertahankan outname unik hasil FASE 0 (jangan dihitung ulang).
		one = i_toEngineEntry(e);
		one.outname = mf.outname;
		cfgOne.Folders = one;
		% Petakan progres per-exp (0..1) -> porsi global ((i-1)+frac)/nF.
		if ~isempty(gpf)
			iLoc = i; nLoc = nF;
			cfgOne.ProgressFcn = @(frac, msg) gpf(max(0, min(1, (iLoc - 1 + frac) / nLoc)), msg);
		end
		try
			[res1, ab1] = pivanalyze.core.processBatch(one, cfgOne);
			for r = 1:numel(res1); resCells{end+1} = res1(r); end %#ok<AGROW>
			if ab1; aborted = true; end
		catch ME
			log(sprintf('   [!] Gagal memproses %s: %s', mf.name, ME.message));
		end

		% (3) HAPUS bongkaran exp ini SEGERA (dump benar-benar temporer).
		i_rmExpDir(unpackedDir, log);

		if aborted; break; end
	end

	% Gabung ringkasan per-exp -> struct-array tunggal (selaras urutan-field).
	for r = 1:numel(resCells)
		if isempty(summary); summary = resCells{r}; else; summary(end+1) = resCells{r}; end %#ok<AGROW>
	end

	if aborted
		log('>>> Dibatalkan oleh pengguna.');
	end
end

%% ===================================================================
function i_rmExpDir(d, log)
%I_RMEXPDIR  Hapus folder bongkaran satu eksperimen (aman; no-op bila kosong).
if isempty(d) || ~isfolder(d); return; end
try
	rmdir(d, 's');
	log(sprintf('   Bongkaran dihapus (temporer): %s', d));
catch ME
	log(sprintf('   [!] Gagal menghapus bongkaran %s: %s', d, ME.message));
end
end

function f = i_toMetaEntry(matEntry)
%I_TOMETAENTRY  Entry engine dari METADATA .mat (RAW/GS/EXIF belum dibongkar).
%   Cukup utk scanExperiments (penamaan unik + laporan); path RAW/GS diisi nanti
%   per-eksperimen oleh unpackMat. expdir = .mat (kunci progres stabil).
f = struct();
f.path    = '';
f.gsdir   = '';
f.expdir  = matEntry.matfile;
f.relpath = matEntry.relpath;
f.name    = matEntry.name;
f.count   = matEntry.count;
f.gscount = matEntry.gscount;
f.suffix  = matEntry.suffix;
f.npairs  = matEntry.npairs;
f.outname = matEntry.outname;
f.exifdir = '';
f.X0   = i_get(matEntry, 'X0', NaN);
f.X1   = i_get(matEntry, 'X1', NaN);
f.Lpos = i_get(matEntry, 'Lpos', NaN);
f.pab_src = i_get(matEntry, 'pab_src', '');   % jembatan key QPIV Step 0
end

%% ===================================================================
function s = i_emptySummary()
s = struct('name', {}, 'relpath', {}, 'path', {}, 'gsdir', {}, 'output_file', {}, ...
	'status', {}, 'message', {}, 'num_pairs', {}, 'n_gs_embedded', {}, ...
	'n_gs_unique', {}, 'exif_status', {}, 'n_dt_valid', {}, 'n_dt_total', {}, ...
	'dt_median_s', {}, 'time_field', {}, 'strain_cumm', {}, 'geom_mode', {}, ...
	'geom_valid', {}, 'n_dropped', {}, 'n_kept', {}, 'elapsed_s', {});
end

function s = i_emptyFolders()
s = struct('path', {}, 'gsdir', {}, 'expdir', {}, 'relpath', {}, 'name', {}, ...
	'count', {}, 'gscount', {}, 'suffix', {}, 'npairs', {}, 'outname', {}, ...
	'exifdir', {}, 'X0', {}, 'X1', {}, 'Lpos', {}, 'pab_src', {});
end

function f = i_toEngineEntry(e)
%I_TOENGINEENTRY  Petakan entry .mat (sudah dibongkar) -> entry engine.
f = struct();
f.path    = e.path;            % folder RAW sementara
f.gsdir   = e.gsdir;           % folder GS sementara ('' bila tak ada)
f.expdir  = e.matfile;         % KUNCI progres = path .mat (stabil)
f.relpath = e.relpath;
f.name    = e.name;
f.count   = e.count;
f.gscount = e.gscount;
f.suffix  = e.suffix;
f.npairs  = e.npairs;
f.outname = e.outname;
f.exifdir = e.exifdir;         % folder EXIF sementara ('' bila tak ada)
f.X0   = i_get(e, 'X0', NaN);
f.X1   = i_get(e, 'X1', NaN);
f.Lpos = i_get(e, 'Lpos', NaN);
f.pab_src = i_get(e, 'pab_src', '');   % jembatan key QPIV Step 0
end

function v = i_get(s, name, def)
if isfield(s, name) && ~isempty(s.(name)); v = s.(name); else; v = def; end
end

function pivanalyze_addpaths_safe()
if exist('pivanalyze_addpaths', 'file') == 2
	pivanalyze_addpaths();
elseif exist('grain_setup', 'file') == 2 && isempty(which('pivanalyze.config'))
	grain_setup();
end
end
