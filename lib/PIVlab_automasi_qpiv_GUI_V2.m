function PIVlab_automasi_qpiv_GUI_V2(job, progressKey, onDoneFcn, navFcn)
%PIVLAB_AUTOMASI_QPIV_GUI_V2  Jendela Quick PIV + modul SKIP manual (ketik daftar).
%
%   V2 = PIVlab_automasi_qpiv_GUI + satu modul "Skip frame manual": kotak teks
%   untuk MENGETIK indeks frame yang diabaikan langsung (mis "1,2,5-9"), selain
%   memilih lewat tabel/grafik. Tombol:
%     - "Tambah skip" : gabungkan daftar ketikan ke ceklis yang sudah ada.
%     - "Set skip"    : ganti seluruh ceklis dengan daftar ketikan.
%   Daftar dipetakan ke indeks frame ASLI (1-based, terhadap frame PENUH) dan
%   tersambung penuh ke `ignore` -> tabel, pita merah, simpan, pratinjau bersih
%   semuanya ikut sinkron. Sisanya identik dengan V1.
%
%   Menjalankan/membuka QPIV strip (PIVlab_automasi_qpiv) lalu menampilkan:
%     - axMain : citra strip + bidang |V| (slider frame)
%     - axPSG  : kymograph ruang-waktu (posisi sepanjang garis x frame, warna=|V|)
%                -> frame mati = kolom gelap vertikal
%     - axPOT  : spaghetti Plot-Over-Time + envelope |V| puncak + ambang
%     - Tabel frame : No | |V| puncak | Abaikan (checkbox)
%   Frame dgn |V| puncak < ambang otomatis disarankan untuk diabaikan; pengguna
%   dapat mengoreksi ceklis. "Simpan" menulis daftar ke berkas progres global
%   (PIVlab_automasi_progress) -> dipakai PIV penuh (batch V4) untuk MENGABAIKAN
%   frame tsb (file gambar TIDAK dihapus).
%
%   PIVlab_automasi_qpiv_GUI_V2(job, progressKey, onDoneFcn, navFcn)
%     job        : struct {raw_folder, expdir, name, suffix, sequencing,
%                  scan_orient, scan_pos_pct, iw_passes[1x4], num_passes,
%                  cache_file, ignore_frames, num_workers}
%     progressKey: kunci entry progres (default = key(expdir))
%     onDoneFcn  : @() dipanggil setelah run/simpan agar GUI induk refresh
%     navFcn     : @(dir)->newJob utk tombol "Exp sebelumnya/berikutnya"
%                  (dir=-1/+1). Mengembalikan struct job tetangga ([] = batal).
%                  [] / tak diisi -> tombol navigasi nonaktif. Ceklis exp saat
%                  ini OTOMATIS disimpan sebelum pindah.
%
%   Lihat juga: PIVlab_automasi_qpiv, PIVlab_automasi_progress,
%               PIVlab_automasi_batch_GUI_V4

here = fileparts(mfilename('fullpath'));
addpath(here);
% PAB_SA: pivcore/pivui di-addpath oleh pab_setup (pivcore_lib/).
if exist('pab_setup', 'file') == 2 && isempty(which('pivcore.data.buildDataset'))
	pab_setup();
end

if nargin < 1 || ~isstruct(job)
	error('PIVlab_automasi_qpiv_GUI:noJob', 'Butuh struct job (raw_folder, dst).');
end
if nargin < 2 || isempty(progressKey)
	progressKey = PIVlab_automasi_progress('key', i_field(job, 'expdir', i_field(job,'raw_folder','')));
end
if nargin < 3; onDoneFcn = []; end
if nargin < 4; navFcn = []; end   % @(dir)->newJob utk Prev(-1)/Next(+1) exp ([]=nonaktif)

% --- pivcore tersedia? ---
if isempty(which('pivcore.data.buildDataset'))
	error('PIVlab_automasi_qpiv_GUI:noPivcore', ...
		'Paket pivcore tidak ditemukan di:\n%s', fullfile(here,'PIVTerry','core'));
end

%% ------------------------------------------------------ state (nested scope)
key      = progressKey;
onDone   = onDoneFcn;
nav      = navFcn;
closeFcn = i_field(job, 'close_fcn', []);   % @() dipanggil saat jendela ditutup
									% (Step 2: hapus bongkaran RAW temporer exp ini)
rawFolder = char(i_field(job, 'raw_folder', ''));
expdir   = char(i_field(job, 'expdir', rawFolder));
expname  = char(i_field(job, 'name', ''));
if isempty(expname); [~, expname] = fileparts(regexprep(expdir, '[\\/]+$', '')); end
suffix   = char(i_field(job, 'suffix', ''));
seqv     = char(i_field(job, 'sequencing', 'consecutive'));
nWork    = i_field(job, 'num_workers', 8);
cacheFile = char(i_field(job, 'cache_file', ''));
if isempty(cacheFile)
	cacheFile = fullfile(expdir, [expname '_QPIV_cache.mat']);
end

orient = char(i_field(job, 'scan_orient', 'Horizontal'));
pos    = i_field(job, 'scan_pos_pct', 50);
iw     = i_field(job, 'iw_passes', [64 32 25 16]); iw = double(iw(:)'); if numel(iw)<4; iw(end+1:4)=16; end
npass  = i_field(job, 'num_passes', 3);
skip   = round(i_field(job, 'skip', 0));
ign0   = i_field(job, 'ignore_frames', []);

out    = [];          % metadata QPIV (engine / DryRun)
data   = [];          % dataset pivcore dari cache
recs   = [];          % records POT
M      = [];          % matriks nPts x nF (deret tiap titik)
posPx  = [];          % posisi titik (px)
peak   = [];          % |V| puncak per frame (1 x nF)
nF     = 0;           % jumlah frame PENUH (ukuran ignore/peak/M kolom)
frame  = 1;           % POSISI tampilan (1..numel(dispIdx)), bukan indeks asli
ignore = false(0);    % logical 1 x nF (indeks ASLI/penuh — disimpan utk batch)
dispIdx = [];         % indeks frame asli yang ditampilkan (mode bersih membuang yg diabaikan)
viewClean = false;    % true = sembunyikan frame diabaikan (pratinjau hasil)
thresh   = NaN;       % ambang BAWAH |V| puncak (frame < thresh -> mati/diabaikan)
threshHi = Inf;       % ambang ATAS |V| puncak (frame > threshHi -> diabaikan)
climVel = [0 1];
gsOn   = true;
imgCache = {};        % strip grayscale per frame (lazy, indeks asli)
busy   = false;

%% --------------------------------------------------------------- figure
fig = uifigure('Name', sprintf('Quick PIV (V2 · skip manual) — %s', expname), ...
	'Position', [70 50 1330 800], 'Color', [1 1 1], ...
	'CloseRequestFcn', @(~,~) onClose());   % tutup via X jendela = onClose (bersihkan)
try theme(fig, 'light'); catch; try fig.Theme = 'light'; catch; end; end

titleLbl = uilabel(fig, 'Position', [16 774 960 24], 'FontSize', 16, 'FontWeight', 'bold', ...
	'Text', '', 'Interpreter', 'none');
% Navigasi antar-eksperimen (auto-simpan ceklis lalu pindah). Aktif bila navFcn ada.
prevExpBtn = uibutton(fig, 'Position', [986 772 158 28], 'Text', '‹ Exp sebelumnya', ...
	'FontWeight', 'bold', 'BackgroundColor', [0.90 0.93 0.86], ...
	'Tooltip', 'Simpan ceklis exp ini lalu buka eksperimen sebelumnya di daftar.', ...
	'ButtonPushedFcn', @(~,~) onNavExp(-1));
nextExpBtn = uibutton(fig, 'Position', [1150 772 168 28], 'Text', 'Exp berikutnya ›', ...
	'FontWeight', 'bold', 'BackgroundColor', [0.86 0.93 0.99], ...
	'Tooltip', 'Simpan ceklis exp ini lalu buka eksperimen berikutnya di daftar.', ...
	'ButtonPushedFcn', @(~,~) onNavExp(+1));
if isempty(nav); prevExpBtn.Enable = 'off'; nextExpBtn.Enable = 'off'; end
i_updateTitle();

%% ----------------------------------------------- panel konfigurasi (atas)
cfg = uipanel(fig, 'Position', [16 690 1010 80], ...
	'Title', 'Konfigurasi garis scan, interrogation window, pasangan frame & skala warna', ...
	'BackgroundColor', [1 1 1]);
% --- Baris 1: garis scan + IW + jalankan ---
uilabel(cfg, 'Position', [10 44 56 22], 'Text', 'Orientasi:');
orientDd = uidropdown(cfg, 'Position', [68 44 104 24], ...
	'Items', {'Horizontal', 'Vertical'}, 'Value', i_capOrient(orient), ...
	'ValueChangedFcn', @(~,~) onCfgChange());
uilabel(cfg, 'Position', [184 44 50 22], 'Text', 'Posisi%:');
posField = uieditfield(cfg, 'numeric', 'Position', [236 44 50 24], 'Value', pos, ...
	'Limits', [0 100], 'ValueDisplayFormat', '%g', 'ValueChangedFcn', @(~,~) onCfgChange());
uilabel(cfg, 'Position', [298 44 26 22], 'Text', 'IW:');
iwF = gobjects(1,4);
for j = 1:4
	iwF(j) = uieditfield(cfg, 'numeric', 'Position', [324 + (j-1)*48 44 44 24], ...
		'Value', iw(j), 'Limits', [8 512], 'RoundFractionalValues', 'on', ...
		'ValueDisplayFormat', '%d', 'ValueChangedFcn', @(~,~) onCfgChange());
end
uilabel(cfg, 'Position', [520 44 44 22], 'Text', '#pass:');
npassDd = uidropdown(cfg, 'Position', [564 44 48 24], 'Items', {'1','2','3','4'}, ...
	'Value', num2str(max(1,min(4,round(npass)))), 'ValueChangedFcn', @(~,~) onCfgChange());
runBtn = uibutton(cfg, 'Position', [624 43 150 28], 'Text', 'Jalankan QPIV', ...
	'FontWeight', 'bold', 'BackgroundColor', [0.82 0.92 0.82], ...
	'ButtonPushedFcn', @(~,~) onRun());
gsCb = uicheckbox(cfg, 'Position', [786 44 170 22], 'Text', 'Overlay citra strip', ...
	'Value', true, 'ValueChangedFcn', @(~,~) onToggleGS());
% --- Baris 2: pasangan frame (urutan) + skip foto + skala warna |V| ---
uilabel(cfg, 'Position', [10 10 56 22], 'Text', 'Pasangan:');
seqDd = uidropdown(cfg, 'Position', [66 10 196 24], ...
	'Items', {'Berurutan (overlap): 1-2, 2-3, ...', 'Berpasangan (terpisah): 1-2, 3-4, ...'}, ...
	'ItemsData', {'consecutive', 'pairs'}, 'Value', seqv, ...
	'Tooltip', ['Cara membentuk pasangan frame untuk QPIV (& PIV penuh exp ini). ' ...
	'Berpasangan = non-overlap. Indeks frame abaikan mengikuti pilihan ini + skip.'], ...
	'ValueChangedFcn', @(~,~) onCfgChange());
uilabel(cfg, 'Position', [270 10 34 22], 'Text', 'Skip:');
skipField = uieditfield(cfg, 'numeric', 'Position', [304 10 42 24], 'Value', skip, ...
	'Limits', [0 Inf], 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d', ...
	'Tooltip', '0 = pakai semua foto; 1 = ambil tiap foto ke-2 (A,C,E,…); 2 = tiap ke-3 (A,D,G,…).', ...
	'ValueChangedFcn', @(~,~) onCfgChange());
uilabel(cfg, 'Position', [358 10 56 22], 'Text', 'Warna|V|:');
climLoField = uieditfield(cfg, 'numeric', 'Position', [414 10 50 24], 'Value', climVel(1), ...
	'ValueDisplayFormat', '%.3g', 'Tooltip', 'Batas bawah warna |V|.', ...
	'ValueChangedFcn', @(~,~) onClimEdit());
uilabel(cfg, 'Position', [466 10 14 22], 'Text', '–');
climHiField = uieditfield(cfg, 'numeric', 'Position', [482 10 50 24], 'Value', climVel(2), ...
	'ValueDisplayFormat', '%.3g', 'Tooltip', 'Batas atas warna |V|.', ...
	'ValueChangedFcn', @(~,~) onClimEdit());
autoClimBtn = uibutton(cfg, 'Position', [536 9 60 26], 'Text', 'Auto', ...
	'Tooltip', 'Set rentang warna |V| otomatis (0..persentil-98).', ...
	'ButtonPushedFcn', @(~,~) onAutoClim());
uilabel(cfg, 'Position', [604 10 392 22], 'FontAngle', 'italic', 'FontColor', [0.4 0.4 0.4], ...
	'Text', 'Ubah pasangan/skip/IW → klik "Jalankan QPIV". Warna dipakai axMain & axPSG.');

%% ----------------------------------------------------------- axes
axMain = uiaxes(fig, 'Position', [56 534 880 150]);
title(axMain, 'axMain — |V| & citra strip'); axMain.XTick = []; axMain.YTick = [];
axPSG = uiaxes(fig, 'Position', [56 320 880 196]);
title(axPSG, 'axPSG — kymograph (posisi × frame)');
axPOT = uiaxes(fig, 'Position', [56 82 880 220]);
title(axPOT, 'axPOT — Plot Over Time'); xlabel(axPOT, 'Frame'); ylabel(axPOT, '|V| (px/frame)');

uilabel(fig, 'Position', [56 58 60 22], 'Text', 'Frame:');
frSlider = uislider(fig, 'Position', [116 78 760 3], 'Limits', [1 2], 'Value', 1, ...
	'MajorTicks', [], 'ValueChangedFcn', @(~,~) onSlider());
frLbl = uilabel(fig, 'Position', [884 56 120 22], 'Text', 'f 0/0', 'FontWeight', 'bold');

statusLbl = uilabel(fig, 'Position', [56 10 880 40], 'Text', 'Siap.', ...
	'FontAngle', 'italic', 'VerticalAlignment', 'top');

%% --------------------------------------------------- panel kanan: seleksi
rp = uipanel(fig, 'Position', [1040 12 278 758], 'Title', 'Seleksi frame untuk diabaikan', ...
	'BackgroundColor', [1 1 1], 'FontWeight', 'bold');
uilabel(rp, 'Position', [10 706 110 22], 'Text', 'Ambang |V| puncak:');
uilabel(rp, 'Position', [10 682 30 22], 'Text', 'min', 'FontAngle', 'italic', ...
	'FontColor', [0.4 0.4 0.4]);
threshField = uieditfield(rp, 'numeric', 'Position', [40 682 70 24], 'Value', 0, ...
	'Limits', [0 Inf], 'ValueDisplayFormat', '%.3g', ...
	'Tooltip', 'Batas BAWAH: frame dgn |V| puncak < min ditandai abaikan (frame ~mati).', ...
	'ValueChangedFcn', @(~,~) onThreshEdit());
uilabel(rp, 'Position', [120 682 30 22], 'Text', 'max', 'FontAngle', 'italic', ...
	'FontColor', [0.4 0.4 0.4]);
threshHiField = uieditfield(rp, 'numeric', 'Position', [150 682 70 24], 'Value', Inf, ...
	'Limits', [0 Inf], 'ValueDisplayFormat', '%.3g', ...
	'Tooltip', 'Batas ATAS: frame dgn |V| puncak > max ditandai abaikan (lonjakan/outlier). Inf = tanpa batas atas.', ...
	'ValueChangedFcn', @(~,~) onThreshEdit());
applyBtn = uibutton(rp, 'Position', [10 648 130 28], 'Text', 'Terapkan saran', ...
	'BackgroundColor', [0.84 0.91 0.97], 'ButtonPushedFcn', @(~,~) onApplySuggest());
clearBtn = uibutton(rp, 'Position', [146 648 120 28], 'Text', 'Bersihkan ceklis', ...
	'ButtonPushedFcn', @(~,~) onClearSel());
selLbl = uilabel(rp, 'Position', [10 624 256 22], 'Text', '0 frame ditandai abaikan.', ...
	'FontAngle', 'italic');

% --- Modul SKIP manual: ketik daftar indeks frame (asli, 1-based) ---
uilabel(rp, 'Position', [10 596 256 20], 'Text', 'Skip frame manual (mis 1,2,5-9):', ...
	'FontWeight', 'bold');
skipFramesField = uieditfield(rp, 'text', 'Position', [10 570 256 24], 'Value', '', ...
	'Placeholder', '1,2,5-9', ...
	'Tooltip', ['Daftar indeks frame (terhadap frame PENUH/asli) untuk diabaikan. ' ...
	'Pakai koma & rentang, mis "1,2,5-9". "Tambah" gabung ke ceklis; "Set" mengganti.'], ...
	'ValueChangedFcn', @(~,~) onAddSkip());   % Enter = Tambah
addSkipBtn = uibutton(rp, 'Position', [10 540 124 26], 'Text', 'Tambah skip', ...
	'BackgroundColor', [0.84 0.91 0.97], 'ButtonPushedFcn', @(~,~) onAddSkip());
setSkipBtn = uibutton(rp, 'Position', [142 540 124 26], 'Text', 'Set skip', ...
	'ButtonPushedFcn', @(~,~) onSetSkip());

frTable = uitable(rp, 'Position', [10 138 258 390], ...
	'ColumnName', {'Frame', '|V|max', 'Abaikan'}, ...
	'ColumnWidth', {64, 84, 70}, 'ColumnEditable', [false false true], ...
	'RowName', {}, 'CellEditCallback', @(~, ev) onTableEdit(ev), ...
	'CellSelectionCallback', @(~, ev) onTableSelect(ev));

% Kombo: simpan ceklis -> exp berikutnya -> langsung Run QPIV (param sama, tanpa popup).
saveNextRunBtn = uibutton(rp, 'Position', [10 104 256 30], 'Text', '✓ Simpan → Exp berikutnya → Run', ...
	'FontWeight', 'bold', 'BackgroundColor', [0.80 0.90 0.80], ...
	'Tooltip', ['Simpan ceklis exp ini ke progres, buka eksperimen BERIKUTNYA, lalu ' ...
	'langsung jalankan QPIV dgn parameter yang sama — tanpa dialog laporan.'], ...
	'ButtonPushedFcn', @(~,~) onSaveNextRun());
if isempty(nav); saveNextRunBtn.Enable = 'off'; end

cleanBtn = uibutton(rp, 'Position', [10 70 256 30], 'Text', 'Olah ulang tanpa frame diabaikan', ...
	'FontWeight', 'bold', 'BackgroundColor', [0.86 0.93 0.99], ...
	'Tooltip', ['Terapkan & simpan ceklis lalu tampilkan POT/PSG/citra HANYA dari frame ' ...
	'yang dipertahankan (frame diabaikan disembunyikan). Klik lagi untuk tampilkan semua.'], ...
	'ButtonPushedFcn', @(~,~) onToggleClean());

saveBtn = uibutton(rp, 'Position', [10 36 256 28], 'Text', 'Simpan ceklis → progres', ...
	'FontWeight', 'bold', 'BackgroundColor', [1.00 0.85 0.20], ...
	'ButtonPushedFcn', @(~,~) onSave());
closeBtn = uibutton(rp, 'Position', [10 6 256 26], 'Text', 'Tutup', ...
	'ButtonPushedFcn', @(~,~) onClose()); %#ok<NASGU>

%% --------------------------------------------------- muat awal
i_styleAxes();
loadOrPrompt();

%% ============================ FUNGSI NESTED =============================
	function i_updateTitle()
		titleLbl.Text = sprintf('Quick PIV — %s  (tandai frame ~nol untuk diabaikan)', expname);
		fig.Name = sprintf('Quick PIV (V2 · skip manual) — %s', expname);
	end

	function onNavExp(dirn)
		i_navExp(dirn, false);
	end

	function onSaveNextRun()
		% Kombo: simpan ceklis -> exp BERIKUTNYA -> langsung Run QPIV (tanpa popup).
		i_navExp(+1, true);
	end

	function ok = i_navExp(dirn, autoRun)
		ok = false;
		if isempty(nav) || busy; return; end
		% Auto-simpan ceklis exp saat ini sebelum pindah (bila ada hasil).
		if nF > 0
			try
				PIVlab_automasi_progress('setIgnore', key, find(ignore));
				persistEntry();
				if ~isempty(onDone); try onDone(); catch; end; end
			catch ME
				setStatus(sprintf('[!] Gagal menyimpan sebelum pindah: %s', ME.message));
			end
		end
		setBusy(true, 'Membuka eksperimen lain...');
		newJob = [];
		try
			newJob = nav(dirn);   % minta job tetangga dari GUI induk (bongkar dll)
		catch ME
			setBusy(false, sprintf('Gagal navigasi: %s', ME.message));
			uialert(fig, ME.message, 'Navigasi gagal'); return;
		end
		if isempty(newJob) || ~isstruct(newJob)
			setBusy(false, 'Tidak ada eksperimen lain untuk dibuka.'); return;
		end
		i_applyJob(newJob);
		i_updateTitle();
		% reset konfigurasi panel agar cocok job baru
		orientDd.Value = i_capOrient(orient); posField.Value = pos;
		for jj = 1:4; iwF(jj).Value = iw(jj); end
		npassDd.Value = num2str(max(1,min(4,round(npass))));
		seqDd.Value = seqv; skipField.Value = skip;
		viewClean = false;
		cleanBtn.Text = 'Olah ulang tanpa frame diabaikan';
		cleanBtn.BackgroundColor = [0.86 0.93 0.99];
		setBusy(false, '');
		if autoRun
			onRun();          % param sama (dari panel = main GUI); tanpa popup
		else
			loadOrPrompt();
		end
		ok = true;
	end

	function i_applyJob(j)
		% Setel ulang state dari job baru (dipakai saat pindah eksperimen).
		key       = PIVlab_automasi_progress('key', char(i_field(j, 'expdir', i_field(j,'raw_folder',''))));
		rawFolder = char(i_field(j, 'raw_folder', ''));
		expdir    = char(i_field(j, 'expdir', rawFolder));
		expname   = char(i_field(j, 'name', ''));
		if isempty(expname); [~, expname] = fileparts(regexprep(expdir, '[\\/]+$', '')); end
		suffix    = char(i_field(j, 'suffix', ''));
		seqv      = char(i_field(j, 'sequencing', 'consecutive'));
		nWork     = i_field(j, 'num_workers', 8);
		cacheFile = char(i_field(j, 'cache_file', ''));
		if isempty(cacheFile); cacheFile = fullfile(expdir, [expname '_QPIV_cache.mat']); end
		orient    = char(i_field(j, 'scan_orient', 'Horizontal'));
		pos       = i_field(j, 'scan_pos_pct', 50);
		iw        = i_field(j, 'iw_passes', [64 32 25 16]); iw = double(iw(:)'); if numel(iw)<4; iw(end+1:4)=16; end
		npass     = i_field(j, 'num_passes', 3);
		skip      = round(i_field(j, 'skip', 0));
		ign0      = i_field(j, 'ignore_frames', []);
		% reset state turunan
		out = []; data = []; recs = []; M = []; posPx = []; peak = [];
		nF = 0; frame = 1; ignore = false(0); dispIdx = []; thresh = NaN; threshHi = Inf;
		climVel = [0 1]; imgCache = {};
	end

	function loadOrPrompt()
		% Buka cache bila ada & cocok; jika tidak, minta pengguna klik Jalankan.
		if isfile(cacheFile)
			try
				setBusy(true, 'Memuat hasil QPIV tersimpan...');
				out = PIVlab_automasi_qpiv(rawFolder, 'Orient', orient, 'PosPct', pos, ...
					'IntAreas', iw, 'NumPasses', npass, 'Suffix', suffix, ...
					'Sequencing', seqv, 'Skip', skip, 'CacheFile', cacheFile, 'DryRun', true);
				ingestCache();
				setBusy(false, sprintf(['Dimuat dari cache: %d frame. ' ...
					'Ubah konfigurasi lalu "Jalankan QPIV" bila perlu.'], nF));
				return;
			catch ME
				setBusy(false, sprintf('Cache tak terbaca (%s). Klik "Jalankan QPIV".', ME.message));
			end
		else
			setStatus('Belum ada hasil QPIV. Atur garis scan lalu klik "Jalankan QPIV".');
		end
	end

	function onRun()
		if busy; return; end
		readCfg();
		try
			setBusy(true, 'Menjalankan QPIV pada strip...');
			out = PIVlab_automasi_qpiv(rawFolder, 'Orient', orient, 'PosPct', pos, ...
				'IntAreas', iw, 'NumPasses', npass, 'Suffix', suffix, ...
				'Sequencing', seqv, 'Skip', skip, 'NumWorkers', nWork, 'CacheFile', cacheFile, ...
				'ProgressFcn', @(f,m) setStatus(sprintf('[%3.0f%%] %s', 100*f, m)));
			ignore = false(1, out.nFrames);     % run baru -> reset, lalu auto-saran
			viewClean = false;                   % keluar dari mode pratinjau bersih
			cleanBtn.Text = 'Olah ulang tanpa frame diabaikan';
			cleanBtn.BackgroundColor = [0.86 0.93 0.99];
			ingestCache();
			autoSuggest();
			persistEntry();                      % tandai qpiv_done di progres
			if ~isempty(onDone); try onDone(); catch; end; end
			setBusy(false, sprintf('QPIV selesai: %d frame. %d disarankan abaikan (ambang %.3g).', ...
				nF, nnz(ignore), thresh));
		catch ME
			setBusy(false, sprintf('GAGAL QPIV: %s', ME.message));
			uialert(fig, ME.message, 'QPIV gagal');
		end
	end

	function ingestCache()
		% Muat cache -> data pivcore, hitung records POT, kymograph, peak.
		S = load(out.cache_file);
		data = pivcore.data.buildDataset(S);
		nF = data.nFrames;
		x1 = pivcore.data.safeFrame(data.x, 1);
		y1 = pivcore.data.safeFrame(data.y, 1);
		[p1, p2] = i_linePoints(out, x1, y1);
		recs = pivcore.pot.step1Collect.collectAlongLine(data, p1, p2, out.iw_max_pass, 'velocity_magnitude');
		[M, posPx] = i_recsMatrix(recs, nF);
		if isempty(M)
			peak = zeros(1, nF);
		else
			peak = max(M, [], 1, 'omitnan'); peak(~isfinite(peak)) = 0;
		end
		if numel(ignore) ~= nF
			ignore = false(1, nF);
			if ~isempty(ign0)
				v = ign0(ign0 >= 1 & ign0 <= nF); ignore(v) = true;
			end
		end
		thresh = i_autoThresh(peak);
		threshField.Value = thresh;
		% Batas atas default = Inf (tak memotong). Auto-saran hanya isi batas bawah;
		% pengguna mengetik batas atas bila ingin membuang lonjakan/outlier.
		if ~isfinite(threshHi); threshHi = Inf; end
		threshHiField.Value = threshHi;
		climVel = i_robustClim(M);
		i_syncClim();
		imgCache = cell(1, nF);
		i_updateDisp();
		syncSlider();
		renderAll();
		refreshTable();
	end

	function i_updateDisp()
		% Tentukan frame mana yang DITAMPILKAN (mode bersih membuang yg diabaikan)
		% dan jaga `frame` (posisi tampilan) tetap valid.
		if viewClean
			dispIdx = find(~ignore);
			if isempty(dispIdx); dispIdx = 1:nF; end   % guard: jangan kosong
		else
			dispIdx = 1:nF;
		end
		if nF < 1; dispIdx = []; frame = 1; return; end
		frame = max(1, min(frame, max(1, numel(dispIdx))));
	end

	function ko = i_origFrame()
		% Indeks frame ASLI dari posisi tampilan `frame`.
		if isempty(dispIdx); ko = max(1, min(frame, max(nF,1))); return; end
		p = max(1, min(frame, numel(dispIdx)));
		ko = dispIdx(p);
	end

	function readCfg()
		orient = orientDd.Value;
		pos    = posField.Value;
		for jj = 1:4; iw(jj) = iwF(jj).Value; end
		npass  = str2double(npassDd.Value);
		seqv   = seqDd.Value;
		skip   = round(skipField.Value);
	end

	function onClimEdit()
		lo = climLoField.Value; hi = climHiField.Value;
		if isfinite(lo) && isfinite(hi) && hi > lo
			climVel = [lo hi];
		else
			i_syncClim();    % tolak input tak valid -> pulihkan tampilan
			return;
		end
		renderMain(); renderPSG();
	end

	function onAutoClim()
		if isempty(M); return; end
		climVel = i_robustClim(M);
		i_syncClim();
		renderMain(); renderPSG();
		setStatus(sprintf('Rentang warna |V| otomatis: [%.3g  %.3g].', climVel(1), climVel(2)));
	end

	function i_syncClim()
		climLoField.Value = climVel(1);
		climHiField.Value = climVel(2);
	end

	function onCfgChange()
		readCfg();
		setStatus('Konfigurasi berubah — klik "Jalankan QPIV" untuk menerapkannya.');
	end

	% ----------------------------- render ------------------------------
	function renderAll()
		renderMain(); renderPSG(); renderPOT();
	end

	function renderMain()
		ax = axMain; cla(ax);
		if isempty(data) || nF == 0; title(ax, 'axMain'); return; end
		k = i_origFrame();        % indeks ASLI frame yang ditampilkan
		x = pivcore.data.safeFrame(data.x, k); y = pivcore.data.safeFrame(data.y, k);
		Z = pivcore.data.safeFrame(data.velocity_magnitude, k);
		if isempty(Z); [Z,~] = pivcore.data.resolveScalar(data, 'velocity_magnitude', k); end
		if isempty(x) || isempty(y) || isempty(Z); return; end
		xExt = [min(x(:)) max(x(:))]; yExt = [min(y(:)) max(y(:))];
		rv = i_viewRoi();          % ROI tampilan (5x lebar), utk latar + batas view
		vx = [rv(1), rv(1)+rv(3)]; vy = [rv(2), rv(2)+rv(4)];
		hold(ax, 'on');
		% Latar foto OPAQUE (area lebar 5x) sbg dasar; |V| di atasnya hanya pada
		% strip, semi-transparan, agar konteks foto tetap jelas.
		haveBg = false;
		if gsOn
			g = i_stripImg(k);     % sudah di-crop ke ROI tampilan lebar
			if ~isempty(g)
				image(ax, 'XData', vx, 'YData', vy, 'CData', g, 'HitTest', 'off');
				haveBg = true;
			end
		end
		hV = imagesc(ax, xExt, yExt, Z);
		colormap(ax, turbo); try clim(ax, climVel); catch; end
		if haveBg; try; set(hV, 'AlphaData', 0.60*ones(size(Z))); catch; end; end
		hold(ax, 'off');
		set(ax, 'YDir', 'reverse'); xlim(ax, vx); ylim(ax, vy);
		daspect(ax, [1 1 1]);     % aspek 1:1 — strip tampil proporsi asli (tak di-stretch)
		ax.XTick = []; ax.YTick = []; box(ax, 'on');
		cb = colorbar(ax); cb.Label.String = '|V| px/frame';
		ttl = sprintf('axMain — frame %d/%d — |V|', k, nF);
		if k <= numel(out.fn2) && ~isempty(out.fn2{k}); ttl = [ttl '  ·  ' out.fn2{k}]; end
		title(ax, ttl, 'Interpreter', 'none');
	end

	function renderPSG()
		ax = axPSG; cla(ax);
		if isempty(M) || isempty(dispIdx); title(ax, 'axPSG'); return; end
		nd = numel(dispIdx);
		imagesc(ax, 1:nd, posPx, M(:, dispIdx));
		colormap(ax, turbo); try clim(ax, climVel); catch; end
		set(ax, 'YDir', 'normal'); axis(ax, 'tight');
		xlabel(ax, i_xlab()); ylabel(ax, 'posisi (px)');
		cb = colorbar(ax); cb.Label.String = '|V|';
		title(ax, ['axPSG — kymograph (kolom gelap = frame ~nol)' i_cleanTag()]);
		drawIgnoreBands(ax); drawFrameLine(ax);
	end

	function renderPOT()
		ax = axPOT; cla(ax); hold(ax, 'on');
		if isempty(M) || isempty(dispIdx)
			title(ax, 'axPOT'); hold(ax, 'off'); return;
		end
		nd = numel(dispIdx);
		for r = 1:size(M, 1)
			plot(ax, 1:nd, M(r, dispIdx), '-', 'Color', [0.6 0.6 0.62]);
		end
		plot(ax, 1:nd, peak(dispIdx), '-', 'Color', [0 0 0], 'LineWidth', 2);   % envelope |V|max
		if isfinite(thresh)   % ambang bawah (merah)
			plot(ax, [1 nd], [thresh thresh], '--', 'Color', [0.85 0.20 0.15], 'LineWidth', 1.2);
		end
		if isfinite(threshHi) % ambang atas (oranye) — frame di atasnya juga dibuang
			plot(ax, [1 nd], [threshHi threshHi], '--', 'Color', [0.95 0.55 0.10], 'LineWidth', 1.2);
		end
		hold(ax, 'off');
		xlabel(ax, i_xlab()); ylabel(ax, '|V| (px/frame)'); grid(ax, 'on');
		if nd > 1; xlim(ax, [1 nd]); end
		if isfinite(threshHi); ambTxt = 'ambang bawah merah · atas oranye'; else; ambTxt = 'ambang bawah merah'; end
		title(ax, sprintf('axPOT — %d kurva · envelope hitam · %s%s', size(M,1), ambTxt, i_cleanTag()));
		drawIgnoreBands(ax); drawFrameLine(ax);
	end

	function s = i_xlab()
		if viewClean; s = 'Frame (tampilan; diabaikan disembunyikan)'; else; s = 'Frame'; end
	end

	function s = i_cleanTag()
		if viewClean; s = sprintf('  [BERSIH: %d/%d]', numel(dispIdx), nF); else; s = ''; end
	end

	function drawFrameLine(axh)
		yl = ylim(axh); hold(axh, 'on');
		plot(axh, [frame frame], yl, '-', 'Color', [0.10 0.45 0.90], 'LineWidth', 1.4, ...
			'HitTest', 'off');
		hold(axh, 'off');
	end

	function drawIgnoreBands(axh)
		% Pita merah pada POSISI tampilan frame yang diabaikan (kosong di mode bersih).
		ig = find(ignore);
		if isempty(ig) || isempty(dispIdx); return; end
		[tf, loc] = ismember(ig, dispIdx);
		bp = loc(tf);
		if isempty(bp); return; end
		yl = ylim(axh); hold(axh, 'on');
		for kk = bp(:)'
			patch(axh, [kk-0.5 kk+0.5 kk+0.5 kk-0.5], [yl(1) yl(1) yl(2) yl(2)], ...
				[1 0.45 0.45], 'FaceAlpha', 0.30, 'EdgeColor', 'none', 'HitTest', 'off');
		end
		hold(axh, 'off');
	end

	% ----------------------------- tabel -------------------------------
	function refreshTable()
		if nF == 0 || isempty(dispIdx)
			frTable.Data = {}; selLbl.Text = '0 frame ditandai.'; return;
		end
		di = dispIdx(:)';
		C = cell(numel(di), 3);
		for r = 1:numel(di)
			ko = di(r);
			C{r,1} = ko;
			C{r,2} = round(peak(ko) * 1000) / 1000;
			C{r,3} = logical(ignore(ko));
		end
		frTable.Data = C;
		% Ceklis hanya dapat diedit di tampilan PENUH (mode bersih = pratinjau).
		frTable.ColumnEditable = [false false ~viewClean];
		if viewClean
			selLbl.Text = sprintf('Pratinjau BERSIH: %d frame (dari %d; %d diabaikan).', ...
				numel(di), nF, nnz(ignore));
		else
			selLbl.Text = sprintf('%d / %d frame ditandai abaikan.', nnz(ignore), nF);
		end
	end

	function onTableEdit(ev)
		if isempty(ev.Indices); return; end
		r = ev.Indices(1); c = ev.Indices(2);
		if c == 3 && r >= 1 && r <= numel(dispIdx)
			ko = dispIdx(r);
			ignore(ko) = logical(ev.NewData);
			i_updateDisp();
			selLbl.Text = sprintf('%d / %d frame ditandai abaikan.', nnz(ignore), nF);
			renderPSG(); renderPOT();
		end
	end

	function onTableSelect(ev)
		if isempty(ev.Indices); return; end
		r = ev.Indices(1);
		if r >= 1 && r <= numel(dispIdx)
			frame = r; syncSlider(); renderAll();
		end
	end

	% --------------------------- saran/ambang --------------------------
	function ig = i_ignoreFromThresh()
		% Mask abaikan dari RENTANG |V| puncak: di bawah batas bawah ATAU di atas
		% batas atas. threshHi = Inf -> hanya batas bawah yang berlaku.
		lo = thresh; hi = threshHi;
		if ~isfinite(lo); lo = 0; end
		ig = (peak < lo) | (peak > hi);
	end

	function s = i_threshDesc()
		% Teks ringkas rentang aktif untuk status bar.
		if isfinite(threshHi)
			s = sprintf('|V| puncak < %.3g atau > %.3g', thresh, threshHi);
		else
			s = sprintf('|V| puncak < %.3g', thresh);
		end
	end

	function autoSuggest()
		thresh = i_autoThresh(peak);
		threshField.Value = thresh;
		threshHi = Inf;                 % run baru: tanpa batas atas (tak memotong)
		threshHiField.Value = threshHi;
		ignore = i_ignoreFromThresh();
		i_updateDisp(); syncSlider();
		refreshTable(); renderAll();
	end

	function onApplySuggest()
		if nF == 0; return; end
		i_readThresh();
		ignore = i_ignoreFromThresh();
		i_updateDisp(); syncSlider();
		refreshTable(); renderAll();
		setStatus(sprintf('%d frame ditandai (%s).', nnz(ignore), i_threshDesc()));
	end

	function i_readThresh()
		% Baca kedua field ambang -> state, dgn validasi min < max.
		thresh = threshField.Value;
		hi = threshHiField.Value;
		if isempty(hi) || ~isfinite(hi); hi = Inf; end
		if hi <= thresh
			% batas atas tak valid (<= batas bawah) -> abaikan batas atas
			hi = Inf; threshHiField.Value = Inf;
			setStatus('Batas atas harus > batas bawah — batas atas diabaikan (Inf).');
		end
		threshHi = hi;
	end

	function onThreshEdit()
		i_readThresh();
		renderPOT();
	end

	function onClearSel()
		ignore = false(1, nF);
		i_updateDisp(); syncSlider();
		refreshTable(); renderAll();
		setStatus('Semua ceklis dibersihkan.');
	end

	% --------------------- modul skip manual (ketik daftar) -------------
	function [vec, bad] = i_readSkipField()
		% Baca & validasi field teks -> indeks frame asli valid (1..nF).
		[vec, bad] = i_parseFrameList(skipFramesField.Value, nF);
	end

	function onAddSkip()
		if nF == 0
			setStatus('Belum ada hasil QPIV — jalankan QPIV dulu sebelum skip manual.'); return;
		end
		[vec, bad] = i_readSkipField();
		if ~isempty(bad)
			uialert(fig, sprintf(['Sebagian masukan di luar jangkauan 1..%d dan diabaikan: %s'], ...
				nF, mat2str(bad)), 'Sebagian tak valid');
		end
		if isempty(vec) && isempty(bad)
			setStatus('Daftar skip kosong / tak terbaca. Contoh: 1,2,5-9'); return;
		end
		ignore(vec) = true;            % GABUNG ke ceklis yang ada
		i_updateDisp(); syncSlider(); refreshTable(); renderAll();
		setStatus(sprintf('Ditambah %d frame ke skip (total %d / %d ditandai).', ...
			numel(vec), nnz(ignore), nF));
	end

	function onSetSkip()
		if nF == 0
			setStatus('Belum ada hasil QPIV — jalankan QPIV dulu sebelum skip manual.'); return;
		end
		[vec, bad] = i_readSkipField();
		if ~isempty(bad)
			uialert(fig, sprintf(['Sebagian masukan di luar jangkauan 1..%d dan diabaikan: %s'], ...
				nF, mat2str(bad)), 'Sebagian tak valid');
		end
		ignore = false(1, nF);         % GANTI seluruh ceklis dengan daftar ini
		ignore(vec) = true;
		i_updateDisp(); syncSlider(); refreshTable(); renderAll();
		setStatus(sprintf('Skip di-set ke %d frame (%d / %d ditandai).', ...
			numel(vec), nnz(ignore), nF));
	end

	% --------------------- olah ulang tanpa frame diabaikan -------------
	function onToggleClean()
		if nF == 0; return; end
		if ~viewClean
			if ~any(ignore)
				uialert(fig, ['Belum ada frame ditandai abaikan. Tandai dulu (atau ' ...
					'"Terapkan saran"), baru olah ulang tanpa frame tsb.'], 'Belum ada ceklis');
				return;
			end
			if ~any(~ignore)
				uialert(fig, 'Semua frame ditandai abaikan — tak ada yang tersisa untuk ditampilkan.', ...
					'Kosong'); return;
			end
			% "Terapkan" = simpan ceklis ke progres lalu tampilkan hasil bersih.
			vec = find(ignore);
			PIVlab_automasi_progress('setIgnore', key, vec);
			persistEntry();
			if ~isempty(onDone); try onDone(); catch; end; end
			viewClean = true;
			cleanBtn.Text = 'Tampilkan semua frame';
			cleanBtn.BackgroundColor = [0.86 0.99 0.86];
			frame = 1; i_updateDisp(); syncSlider(); renderAll(); refreshTable();
			setStatus(sprintf(['Pratinjau hasil tanpa %d frame diabaikan (tersimpan). ' ...
				'Klik "Tampilkan semua frame" untuk edit lagi.'], numel(vec)));
		else
			viewClean = false;
			cleanBtn.Text = 'Olah ulang tanpa frame diabaikan';
			cleanBtn.BackgroundColor = [0.86 0.93 0.99];
			frame = 1; i_updateDisp(); syncSlider(); renderAll(); refreshTable();
			setStatus('Tampilkan semua frame (mode edit). Ceklis dapat diubah lagi.');
		end
	end

	% ----------------------------- frame -------------------------------
	function onSlider()
		if nF == 0 || isempty(dispIdx); return; end
		frame = max(1, min(round(frSlider.Value), numel(dispIdx)));
		frLbl.Text = i_frameLbl();
		renderAll();
	end

	function syncSlider()
		nd = numel(dispIdx);
		if nd < 2
			frSlider.Limits = [1 2]; frSlider.Value = 1; frSlider.Enable = 'off';
		else
			frSlider.Limits = [1 nd]; frSlider.Value = max(1, min(frame, nd)); frSlider.Enable = 'on';
		end
		frLbl.Text = i_frameLbl();
	end

	function s = i_frameLbl()
		nd = max(1, numel(dispIdx));
		ko = i_origFrame();
		if viewClean
			s = sprintf('tampil %d/%d (asli #%d)', max(1,min(frame,nd)), nd, ko);
		else
			s = sprintf('f %d/%d', ko, nF);
		end
	end

	function onToggleGS()
		gsOn = gsCb.Value; renderMain();
	end

	% ----------------------------- simpan ------------------------------
	function onSave()
		if nF == 0
			uialert(fig, 'Belum ada hasil QPIV untuk disimpan.', 'Kosong'); return;
		end
		vec = find(ignore);
		PIVlab_automasi_progress('setIgnore', key, vec);
		persistEntry();
		if ~isempty(onDone); try onDone(); catch; end; end
		setStatus(sprintf('Tersimpan: %d frame diabaikan untuk %s.', numel(vec), expname));
		uialert(fig, sprintf('%d frame ditandai untuk diabaikan saat PIV penuh.', numel(vec)), ...
			'Tersimpan', 'Icon', 'success');
	end

	function persistEntry()
		e = PIVlab_automasi_progress('empty');
		e.expdir = expdir; e.key = key; e.name = expname;
		e.raw_suffix = i_orEmpty(out, 'suffix', suffix); e.sequencing = seqv;
		e.scan_orient = orient; e.scan_pos_pct = pos;
		e.iw_passes = iw; e.num_passes = npass; e.skip = skip;
		e.qpiv_done = true; e.qpiv_cache = cacheFile; e.qpiv_nframes = nF;
		e.qpiv_run_time = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1>
		e.ignore_frames = find(ignore); e.n_drop = nnz(ignore);
		e.pos_hash = PIVlab_automasi_progress('sig', orient, pos, iw, suffix, nF, skip, seqv);
		PIVlab_automasi_progress('set', e);
	end

	function onClose()
		% Beri tahu pemanggil (Step 2) agar membersihkan bongkaran RAW temporer
		% eksperimen yang sedang dibuka, lalu tutup jendela.
		if ~isempty(closeFcn); try closeFcn(); catch; end; end
		delete(fig);
	end

	% --------------------------- util kecil ----------------------------
	function rv = i_viewRoi()
		% ROI TAMPILAN axMain: strip diperlebar 5x pada arah LEBAR (dimensi tipis);
		% arah panjang tetap penuh. Hanya untuk tampilan latar + zoom view — TIDAK
		% mengubah komputasi PIV (out.roi). Clamp ke ukuran gambar.
		VIEW_MULT = 5;
		r = out.roi;                 % [x y w h] (1-based, w/h = span)
		sz = out.imageSize;          % [H W]
		H = sz(1); W = sz(2);
		if strcmpi(out.orient, 'vertical')
			% strip tipis arah-x -> perlebar w
			cx = r(1) + r(3)/2;
			wNew = min(W-1, VIEW_MULT * (r(3)+1) - 1);
			x0 = max(1, min(round(cx - wNew/2), W - wNew));
			rv = [x0, r(2), wNew, r(4)];
		else
			% horizontal: strip tipis arah-y -> perlebar h
			cy = r(2) + r(4)/2;
			hNew = min(H-1, VIEW_MULT * (r(4)+1) - 1);
			y0 = max(1, min(round(cy - hNew/2), H - hNew));
			rv = [r(1), y0, r(3), hNew];
		end
	end

	function g = i_stripImg(kf)
		% Citra frame kf di-crop ke ROI TAMPILAN (5x lebih lebar); cache lazy.
		g = [];
		if kf < 1 || kf > numel(out.fn2) || isempty(out.fn2{kf}); return; end
		if numel(imgCache) >= kf && ~isempty(imgCache{kf}); g = imgCache{kf}; return; end
		p = fullfile(out.raw_folder, out.fn2{kf});
		if ~isfile(p); return; end
		try
			im = imread(p);
			r = i_viewRoi();   % [x y w h] span — ROI tampilan lebar
			rr = r(2):min(size(im,1), r(2)+r(4));
			ccx = r(1):min(size(im,2), r(1)+r(3));
			patch = im(rr, ccx, :);
			% Latar GS "optimum" on-the-fly: CLAHE + auto brightness/contrast
			% (murni tampilan; keluaran 3-kanal kebal colormap |V|). Bila helper
			% absen, jatuh ke patch apa adanya (dipaksa RGB).
			if exist('pivanalyzemat.core.gsClahe', 'file') || ...
					~isempty(which('pivanalyzemat.core.gsClahe'))
				g = pivanalyzemat.core.gsClahe(patch);
			else
				g = patch;
				if size(g, 3) == 1; g = repmat(g, 1, 1, 3); end
			end
		catch
			g = [];
		end
		if numel(imgCache) < nF; imgCache{nF} = []; end
		imgCache{kf} = g;
	end

	function setStatus(msg)
		if ~isvalid(fig); return; end
		statusLbl.Text = msg; drawnow limitrate;
	end

	function setBusy(tf, msg)
		busy = tf;
		ctrls = {runBtn, orientDd, posField, npassDd, seqDd, skipField, applyBtn, clearBtn, saveBtn, ...
			threshField, threshHiField, gsCb, climLoField, climHiField, autoClimBtn, cleanBtn, ...
			skipFramesField, addSkipBtn, setSkipBtn};
		for cc2 = 1:numel(ctrls); try ctrls{cc2}.Enable = i_onoff(~tf); catch; end; end
		for jj = 1:4; try iwF(jj).Enable = i_onoff(~tf); catch; end; end
		% tombol navigasi exp: aktif hanya bila navFcn ada & tidak sibuk
		if ~isempty(nav)
			try prevExpBtn.Enable = i_onoff(~tf); nextExpBtn.Enable = i_onoff(~tf); ...
				saveNextRunBtn.Enable = i_onoff(~tf); catch; end
		end
		if nargin > 1; setStatus(msg); end
		drawnow;
	end

	function i_styleAxes()
		for ax = [axMain axPSG axPOT]
			ax.Color = [1 1 1]; box(ax, 'on');
		end
	end
end

%% ========================= SUBFUNGSI (lokal) =====================
function [p1, p2] = i_linePoints(out, x1, y1)
%I_LINEPOINTS  Endpoint garis POT di ruang axMain ter-flip (cocok collectAlongLine).
yMid = (max(y1(:)) + min(y1(:))) / 2;
H = out.imageSize(1); W = out.imageSize(2);
if strcmpi(out.orient, 'vertical')
	cc = 1 + (out.posPct/100) * (W - 1);
	p1 = [cc, 2*yMid - max(y1(:))];
	p2 = [cc, 2*yMid - min(y1(:))];
else
	rc = 1 + (out.posPct/100) * (H - 1);
	p1 = [min(x1(:)), 2*yMid - rc];
	p2 = [max(x1(:)), 2*yMid - rc];
end
end

function [M, posPx] = i_recsMatrix(recs, nF)
%I_RECSMATRIX  Susun matriks nPts x nF dari records POT + posisi px.
n = numel(recs);
if n == 0; M = []; posPx = []; return; end
M = nan(n, nF); posPx = nan(1, n);
for r = 1:n
	d = recs(r).data(:)';
	L = min(numel(d), nF);
	M(r, 1:L) = d(1:L);
	if isfield(recs(r), 'posPx') && ~isempty(recs(r).posPx); posPx(r) = recs(r).posPx; end
end
bad = ~isfinite(posPx);
if any(bad); posPx(bad) = find(bad); end
end

function t = i_autoThresh(peak)
%I_AUTOTHRESH  Ambang saran: 20% dari persentil-90 |V| puncak (tahan thd frame mati).
v = peak(isfinite(peak));
if isempty(v); t = 0; return; end
p90 = i_pct(v, 90);
t = 0.2 * p90;
if ~(isfinite(t) && t > 0); t = 0.2 * max(v); end
if ~(isfinite(t) && t > 0); t = 0; end
t = round(t * 1000) / 1000;
end

function q = i_pct(v, p)
%I_PCT  Persentil tanpa Statistics Toolbox (interpolasi linear).
v = sort(v(:));
n = numel(v);
if n == 0; q = NaN; return; end
if n == 1; q = v(1); return; end
r = (p/100) * (n - 1) + 1;
lo = floor(r); hi = ceil(r); fr = r - lo;
q = v(lo) * (1 - fr) + v(hi) * fr;
end

function c = i_robustClim(M)
%I_ROBUSTCLIM  Rentang warna [0 p98] dari nilai berhingga.
if isempty(M); c = [0 1]; return; end
v = M(isfinite(M));
if isempty(v); c = [0 1]; return; end
hi = i_pct(v, 98);
if ~(isfinite(hi) && hi > 0); hi = max(v); end
if ~(isfinite(hi) && hi > 0); hi = 1; end
c = [0 hi];
end

function v = i_field(s, f, dflt)
if isstruct(s) && isfield(s, f) && ~isempty(s.(f)); v = s.(f); else; v = dflt; end
end

function [vec, bad] = i_parseFrameList(str, nMax)
%I_PARSEFRAMELIST  Urai "1,2,5-9" -> indeks unik valid (1..nMax). `bad` = di luar
%   jangkauan (untuk peringatan). Pemisah: koma/spasi/titik-koma; rentang: a-b.
vec = []; bad = [];
str = strtrim(char(str));
if isempty(str); return; end
toks = regexp(str, '[,;\s]+', 'split');
all = [];
for k = 1:numel(toks)
	t = strtrim(toks{k});
	if isempty(t); continue; end
	m = regexp(t, '^(\d+)\s*-\s*(\d+)$', 'tokens', 'once');
	if ~isempty(m)
		a = str2double(m{1}); b = str2double(m{2});
		if a > b; tmp = a; a = b; b = tmp; end
		all = [all, a:b]; %#ok<AGROW>
	elseif ~isempty(regexp(t, '^\d+$', 'once'))
		all = [all, str2double(t)]; %#ok<AGROW>
	end
	% token tak dikenal diabaikan diam-diam
end
all = unique(round(all));
bad = all(all < 1 | all > nMax);
vec = all(all >= 1 & all <= nMax);
end

function v = i_orEmpty(s, f, dflt)
if isstruct(s) && isfield(s, f) && ~isempty(s.(f)); v = s.(f); else; v = dflt; end
end

function s = i_capOrient(o)
if strcmpi(o, 'vertical'); s = 'Vertical'; else; s = 'Horizontal'; end
end

function s = i_onoff(tf)
if tf; s = 'on'; else; s = 'off'; end
end
