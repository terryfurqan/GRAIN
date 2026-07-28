function GRAIN2(rootArg, autoSaveArg)
%GRAIN2  Step 2 GRAIN_SA = Analisis PIV PENUH dengan INPUT .mat (bukan folder).
%
%   GRAIN2
%   GRAIN2(rootFolder)            -> buka langsung menunjuk folder MAT PREP,
%                                  pindai otomatis (metadata saja, tanpa dump).
%   GRAIN2(rootFolder, true)      -> idem + simpan progres OTOMATIS ke
%                                  <root>/PABSA2_progress_<namaroot>.mat tanpa
%                                  dialog. Dipakai oleh tombol "Lanjutkan ke
%                                  Step 2" GRAIN1 supaya kerja bisa dilanjutkan
%                                  lain waktu (Muat Progres).
%
%   Padanan PERSIS PIVlab_automasi_batch_GUI_V4 (PIV + GS + waktu EXIF +
%   geometri + Quick PIV + buang frame mati), TAPI unit input bukan folder
%   eksperimen RAW/GS, melainkan BERKAS .mat keluaran Step 1 (skema
%   'pivprep_single_v1' dari pivprepPackFolder). Satu .mat = satu eksperimen
%   lengkap (blob RAW + GS + EXIF + jitter).
%
%   ALUR
%     1. INPUT UTAMA = FOLDER ROOT berisi beberapa .mat. Begitu dipilih (atau
%        diketik), folder dipindai OTOMATIS -> semua eksperimen terdaftar.
%        "Tambah .mat" (tunggal/banyak) hanya AKTIF setelah root ditentukan.
%     2. Isi geometri X0/X1/L_pos (klik sel tabel atau panel), atur IW/opsi
%        GS-EXIF, jalankan Quick PIV utk menandai frame mati — SEMUA identik V4.
%        "Simpan Progres" menyimpan SELURUH keadaan (daftar, geometri, setting,
%        koleksi QPIV) ke satu .mat (default: PABSA2_progress_<namaroot>.mat);
%        "Muat Progres" memulihkannya.
%     3. "Mulai Batch": tiap .mat dibongkar ke subfolder ber-HASH DI DALAM folder
%        root ('.grainsa2_unpack_<hash>/', sengaja tertinggal sbg cache lintas-sesi)
%        lalu engine V4/+pivanalyze dijalankan APA ADANYA. Hasil .mat PIV
%        ditaruh di subfolder  PIV_<tgl-analisis>/  DI DALAM folder root.
%
%   Logika ilmiah TIDAK diduplikasi: pembongkaran + perutean di +pivanalyzemat,
%   analisis di +pivanalyze (sama persis V4/V5). Tema TERANG dipaksa; jendela
%   utama di-minimize saat dialog berkas. SELALU MATLAB R2025b.
%
%   Lihat juga: PAB_step_1, pivanalyzemat.core.processBatchMat,
%               pivanalyze.core.processBatch, PIVlab_automasi_batch_GUI_V4

grain_setup();

%% ----------------------------------------------------------- variabel scope
EMPTY = struct('matfile', {}, 'path', {}, 'gsdir', {}, 'expdir', {}, ...
	'relpath', {}, 'name', {}, 'count', {}, 'gscount', {}, 'suffix', {}, ...
	'npairs', {}, 'outname', {}, 'seqmode', {}, 'seqstep', {}, 'has_exif', {}, ...
	'unpacked', {}, 'exifdir', {}, 'X0', {}, 'X1', {}, 'Lpos', {}, 'pab_src', {});
procList     = EMPTY;
selectedRows = [];
logLines     = {};
abortReq     = false;
rootFolder   = '';
qpivRow      = 0;        % baris exp yang sedang dibuka di jendela Quick PIV
qpivTmpDir   = '';       % folder bongkaran RAW TEMPORER exp QPIV aktif (dihapus
						 % saat pindah exp / tutup jendela QPIV)

pv = struct('fig', [], 'ax', [], 'idx', 0, 'last', false, ...
	'expLbl', [], 'frLbl', [], 'geomLbl', [], 'toggleBtn', [], ...
	'prevBtn', [], 'nextBtn', [], 'imgA', [], 'imgB', [], ...
	'firstPath', '', 'lastPath', '', 'nframes', 0, ...
	'x0Field', [], 'x1Field', [], 'lposField', [], 'lposAllBtn', [], ...
	'imh', [], 'lines', [], 'resetNext', true, ...
	'lShape', [], 'lenField', [], 'angField', [], ...   % +garis L parametrik (A-B-C)
	'showGS', true, 'imgAgs', [], 'imgBgs', [], 'gsBtn', [], ...   % +tampilan GS/RAW
	'zoomLock', false, 'lockXLim', [], 'lockYLim', [], 'lockBtn', [], ...   % +kunci zoom
	'closeSaveBtn', [], 'closeNoSaveBtn', []);   % +tombol tutup (simpan / tanpa simpan)
	% zoomLock=paksa batas zoom tetap (lockXLim/lockYLim) walau render ulang/ganti exp
	% showGS=tampilkan latar GS (CLAHE) bukan RAW penuh; imgAgs/imgBgs=cache GS
	% imh=handel gambar in-place;
	                                               % lines=ROI garis kosmetik;
	                                               % resetNext=paksa zoom penuh
	                                               % di render berikut (ganti exp)
pv.lines = {};   % cell handel drawline (bersihkan saat ganti exp / tombol)

% Kolom tabel (EXIF/QPIV/Skip/#drop dibuang; +strain/#pair & cm/#pair)
COL_NPAIR = 4; ...
	COL_X0 = 5; COL_X1 = 6; COL_LPOS = 7; COL_STRAIN = 8; ...
	COL_SPP = 9; COL_CPP = 10; COL_MODE = 11; COL_NAME = 12;

styMissing  = uistyle('BackgroundColor', [1.00 0.80 0.80]);
styLengthen = uistyle('BackgroundColor', [0.82 0.94 0.82]);
styShorten  = uistyle('BackgroundColor', [1.00 0.90 0.74]);
styBadL0    = uistyle('BackgroundColor', [1.00 0.62 0.62], 'FontColor', [0.55 0 0]);

%% --------------------------------------------------------------- figure
% TATA-LETAK LANDSCAPE 1400×860 (muat di monitor 1440×900):
%   - KOLOM KIRI (x=14, lebar 560): semua kontrol setup, ditumpuk dari atas.
%   - SISI KANAN (x=586, lebar 800): ringkasan + TABEL VERTIKAL (tinggi penuh).
%   - STRIP BAWAH (lebar penuh): Run/Abort + progress + status + log.
fig = uifigure('Name', pivui.titleWithVersion('Automasi PIV Lab — Step 2 (INPUT .mat: PIV + GS + EXIF + geometri + Quick PIV)'), ...
	'Position', [20 20 1400 800], 'Resize', 'off', ...
	'CloseRequestFcn', @(~,~) onClose());
pivui.forceLightTheme(fig);   % paksa tema terang (satu sumber +pivui)

% Tempatkan jendela di sudut KIRI-ATAS layar (jangan tenggelam di bawah).
try
	scr = get(groot, 'ScreenSize');           % [x y w h]
	fp  = fig.Position;
	margin = 8;
	fig.Position = [margin, scr(4) - fp(4) - 40, fp(3), fp(4)];
catch
end

% Geometri kolom
LX  = 14;   LW  = 510;          % kolom kiri (kontrol)
RX  = 536;  RW  = 850;          % sisi kanan (tabel) → ujung kanan x=1386
TOP = 771;                      % baris paling atas kolom kiri (srcPanel top)

uilabel(fig, 'Position', [LX 775 RX+RW-LX 22], ...
	'Text', 'PIV Lab automation — Step 2  (.mat PIVPrep → PIV → GS + EXIF + geometry + Quick PIV)', ...
	'FontSize', 16, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

%% ===================== KOLOM KIRI: kontrol setup =====================

%% --------------------------------------- sumber: folder root berisi .mat
srcPanel = uipanel(fig, 'Position', [LX 651 LW 120], 'Title', 'Source: root folder holding .mat files');
uilabel(srcPanel, 'Position', [12 70 88 22], 'Text', 'Root folder:');
parentField = uieditfield(srcPanel, 'text', 'Position', [104 70 296 26], ...
	'Placeholder', 'Root folder of Step 1 .mat files (pivprep_single_v1)...', ...
	'ValueChangedFcn', @(~,~) onParentTyped());
parentBrowse = uibutton(srcPanel, 'Position', [406 69 92 28], 'Text', 'Browse...', ...
	'ButtonPushedFcn', @(~,~) onBrowseParent());
scanBtn = uibutton(srcPanel, 'Position', [104 38 296 28], 'Text', 'Scan .mat & add to list', ...
	'ButtonPushedFcn', @(~,~) onScan());
recursiveCb = uicheckbox(srcPanel, 'Position', [406 40 92 24], 'Text', 'Recursive', 'Value', true);

uilabel(srcPanel, 'Position', [12 8 56 22], 'Text', 'Pairing:');
seqDropdown = uidropdown(srcPanel, 'Position', [72 7 200 26], ...
	'Items',     {'Overlapping: 1-2, 2-3, ... (N→N-1)', 'Non-overlapping: 1-2, 3-4, ... (N→N/2)'}, ...
	'ItemsData', {'consecutive', 'pairs'}, 'Value', 'consecutive', ...
	'Tooltip', ['Overlapping: every consecutive image is paired -> N images ' ...
	'give N-1 PIV vector fields. Non-overlapping: disjoint pairs -> N/2 fields. ' ...
	'A .mat carrying its own sequencing metadata still wins.'], ...
	'ValueChangedFcn', @(~,~) refreshTable());
uilabel(srcPanel, 'Position', [276 8 30 22], 'Text', 'Skip:');
skipField = uieditfield(srcPanel, 'numeric', 'Position', [306 7 34 26], ...
	'Value', 0, 'Limits', [0 Inf], 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d', ...
	'Tooltip', '0 = every photo; 1 = every 2nd photo; 2 = every 3rd.', ...
	'ValueChangedFcn', @(~,~) refreshTable());
uilabel(srcPanel, 'Position', [344 8 48 22], 'Text', 'Workers:', 'HorizontalAlignment', 'right');
workersField = uieditfield(srcPanel, 'numeric', 'Position', [394 7 38 26], ...
	'Value', 8, 'Limits', [1 256], 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d');
uilabel(srcPanel, 'Position', [436 8 28 22], 'Text', 'Min:', 'HorizontalAlignment', 'right', ...
	'Tooltip', 'Min. frames');
minField = uieditfield(srcPanel, 'numeric', 'Position', [466 7 38 26], ...
	'Value', 2, 'Limits', [2 Inf], 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d', ...
	'Tooltip', 'Min. frames');

%% --------------------------------------- kelola daftar
mgmtPanel = uipanel(fig, 'Position', [LX 545 LW 102], 'Title', 'Manage list');
addBtn = uibutton(mgmtPanel, 'Position', [12 48 165 28], 'Text', 'Add single .mat...', ...
	'ButtonPushedFcn', @(~,~) onAddSingle());
addMultiBtn = uibutton(mgmtPanel, 'Position', [185 48 180 28], 'Text', 'Add several .mat...', ...
	'ButtonPushedFcn', @(~,~) onAddMulti());
removeBtn = uibutton(mgmtPanel, 'Position', [373 48 125 28], 'Text', 'Remove selected', ...
	'ButtonPushedFcn', @(~,~) onRemove());
clearBtn = uibutton(mgmtPanel, 'Position', [12 12 165 28], 'Text', 'Clear list', ...
	'ButtonPushedFcn', @(~,~) onClear());
saveProgBtn = uibutton(mgmtPanel, 'Position', [185 12 155 28], 'Text', '💾 Save progress', ...
	'FontWeight', 'bold', 'BackgroundColor', [0.86 0.93 0.99], 'Enable', 'off', ...
	'Tooltip', ['Save ALL progress into one .mat: the file list, X0/X1/L_pos geometry, ' ...
	'the IW/GS/EXIF/skip settings, and the QPIV collection (config + dead frames). Default name: ' ...
	'PABSA2_progress_<namafolder root>.'], ...
	'ButtonPushedFcn', @(~,~) onSaveProgress());
loadProgBtn = uibutton(mgmtPanel, 'Position', [348 12 150 28], 'Text', '📂 Load progress', ...
	'FontWeight', 'bold', 'BackgroundColor', [0.90 0.93 0.86], ...
	'Tooltip', 'Load a previously saved GRAINSA2 progress file (restores list + settings + QPIV).', ...
	'ButtonPushedFcn', @(~,~) onLoadProgress());

%% --------------------------------------- opsi GS & EXIF
gsPanel = uipanel(fig, 'Position', [LX 439 LW 102], 'Title', 'GS (background) & EXIF (timing) options');
uilabel(gsPanel, 'Position', [12 58 130 22], 'Text', 'GS JPEG quality:');
gsQualField = uieditfield(gsPanel, 'numeric', 'Position', [142 59 56 24], ...
	'Value', 92, 'Limits', [1 100], 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d');
dropFirstCb = uicheckbox(gsPanel, 'Position', [210 59 288 24], ...
	'Text', 'Ignore the first GS image (PIVlab)', 'Value', true);
reencodeCb = uicheckbox(gsPanel, 'Position', [12 32 360 24], ...
	'Text', 'Re-encode GS .jpg (default: as-is)', 'Value', false);
embedTimeCb = uicheckbox(gsPanel, 'Position', [12 6 238 24], ...
	'Text', 'Embed dt timing from EXIF', 'Value', true);
embedTableCb = uicheckbox(gsPanel, 'Position', [256 6 242 24], ...
	'Text', 'Embed the full EXIF table', 'Value', true);

%% --------------------------------------- PIV lanjutan (IW) & Quick PIV
pivPanel = uipanel(fig, 'Position', [LX 317 LW 118], ...
	'Title', 'Advanced PIV (interrogation window) & Quick PIV');
uilabel(pivPanel, 'Position', [12 72 120 22], 'Text', 'IW pass 1–4 (px):');
iwF = gobjects(1,4);
defIW = [64 32 25 16];
for j = 1:4
	iwF(j) = uieditfield(pivPanel, 'numeric', 'Position', [134 + (j-1)*52 73 46 24], ...
		'Value', defIW(j), 'Limits', [8 512], 'RoundFractionalValues', 'on', ...
		'ValueDisplayFormat', '%d', ...
		'Tooltip', sprintf('Interrogation window size for pass %d (px).', j));
end
uilabel(pivPanel, 'Position', [350 72 56 22], 'Text', '# pass:');
npassDd = uidropdown(pivPanel, 'Position', [406 73 50 24], 'Items', {'1','2','3','4'}, 'Value', '3');
uilabel(pivPanel, 'Position', [12 48 486 20], 'FontAngle', 'italic', 'FontColor', [0.35 0.35 0.35], ...
	'Text', 'IW is used by the full PIV and as the Quick PIV default. Strip = 2× the last IW.');

uilabel(pivPanel, 'Position', [12 12 76 22], 'Text', 'Scan line:');
scanOrientDd = uidropdown(pivPanel, 'Position', [90 13 96 24], ...
	'Items', {'Horizontal', 'Vertical'}, 'Value', 'Horizontal');
uilabel(pivPanel, 'Position', [192 12 48 22], 'Text', 'Position %:');
scanPosField = uieditfield(pivPanel, 'numeric', 'Position', [242 13 42 24], 'Value', 50, ...
	'Limits', [0 100], 'ValueDisplayFormat', '%g', ...
	'Tooltip', '0% = left/top, 100% = right/bottom.');
quickBtn = uibutton(pivPanel, 'Position', [294 11 204 28], 'Text', 'Quick PIV (selected row)...', ...
	'FontWeight', 'bold', 'BackgroundColor', [0.86 0.93 0.99], ...
	'Tooltip', ['Unpack the selected .mat then open the Quick PIV window: POT + PSG ' ...
	'kymograph + frame table, to flag frames with ~zero displacement.'], ...
	'ButtonPushedFcn', @(~,~) onQuickPIV());

%% --------------------------------------- folder output (PIV_<tgl> di root)
outPanel = uipanel(fig, 'Position', [LX 249 LW 64], 'Title', 'Output folder');
outField = uieditfield(outPanel, 'text', 'Position', [12 8 294 26], ...
	'Placeholder', 'Empty = PIV_<date> inside the .mat root folder', ...
	'ValueChangedFcn', @(~,~) refreshTable());
outBrowse = uibutton(outPanel, 'Position', [312 7 88 28], 'Text', 'Browse...', ...
	'ButtonPushedFcn', @(~,~) onBrowseOut());
outClearBtn = uibutton(outPanel, 'Position', [406 7 92 28], 'Text', 'Clear', ...
	'ButtonPushedFcn', @(~,~) onClearOut());

%% --------------------------------------- geometri eksperimen
geomPanel = uipanel(fig, 'Position', [LX 139 LW 106], 'Title', 'Experiment geometry (cm)');
uilabel(geomPanel, 'Position', [12 62 486 20], 'FontAngle', 'italic', 'FontColor', [0.35 0.35 0.35], ...
	'Text', ['Click an X0/X1/L_pos cell in the table (RED cell = not filled in yet). ' ...
	'Strain%: + lengthening, − shortening.']);
uilabel(geomPanel, 'Position', [12 34 26 22], 'Text', 'X0:');
x0Field = uieditfield(geomPanel, 'text', 'Position', [40 35 64 24], 'Placeholder', 'cm');
uilabel(geomPanel, 'Position', [114 34 26 22], 'Text', 'X1:');
x1Field = uieditfield(geomPanel, 'text', 'Position', [142 35 64 24], 'Placeholder', 'cm');
uilabel(geomPanel, 'Position', [216 34 46 22], 'Text', 'L_pos:');
lposField = uieditfield(geomPanel, 'text', 'Position', [264 35 60 24], 'Placeholder', 'cm');
previewBtn = uibutton(geomPanel, 'Position', [330 34 168 26], ...
	'Text', 'View first/last photo', 'FontWeight', 'bold', ...
	'BackgroundColor', [0.90 0.93 0.86], 'ButtonPushedFcn', @(~,~) onPreview());
applySelBtn = uibutton(geomPanel, 'Position', [12 6 310 26], ...
	'Text', 'Apply X0/X1/L_pos to the selected rows', ...
	'ButtonPushedFcn', @(~,~) onApplySel());
applyLposAllBtn = uibutton(geomPanel, 'Position', [330 6 168 26], ...
	'Text', 'Apply L_pos to ALL', 'FontWeight', 'bold', ...
	'BackgroundColor', [0.84 0.91 0.97], 'ButtonPushedFcn', @(~,~) onApplyLposAll());

%% ===================== SISI KANAN: TABEL VERTIKAL =====================
scanSummary = uilabel(fig, 'Position', [RX 748 RW-160 24], ...
	'Text', 'List is empty. Scan a .mat root folder or add a single .mat file.', ...
	'FontAngle', 'italic');
uibutton(fig, 'Position', [RX + RW - 150, 746, 150, 26], 'Text', '✕ Close GRAIN2', ...
	'FontWeight', 'bold', 'BackgroundColor', [0.90 0.55 0.50], 'FontColor', [1 1 1], ...
	'Tooltip', 'Close the GRAIN2 window (you are asked to save progress first).', ...
	'ButtonPushedFcn', @(~,~) onClose());
% Tombol mulai eksperimen baru: simpan progres (opsional) → tutup GRAIN2 →
% buka GRAIN0 KOSONG untuk QPIV/preprocessing eksperimen berikut (daftar
% bersih, tak ada sisa root/pemindaian eksperimen sebelumnya).
uibutton(fig, 'Position', [RX + RW - 310, 746, 154, 26], 'Text', '↩ New experiment → GRAIN0', ...
	'FontWeight', 'bold', 'BackgroundColor', [0.62 0.78 0.62], 'FontColor', [1 1 1], ...
	'Tooltip', 'Start another experiment: back to GRAIN0 (you are asked to save progress first).', ...
	'ButtonPushedFcn', @(~,~) onBackToGRAIN0());
% TABEL diperpendek: top tetap di y=746, bawah dinaikkan ke y=300 supaya
% strip aksi (CSV / batch / progress / status / log) muat di bawahnya — semua
% berada di SISI KANAN, tidak lagi melintang penuh ke bawah jendela.
folderTable = uitable(fig, 'Position', [RX 300 RW 446], ...
	'ColumnName', {'No', 'Experiment (.mat)', '#RAW', '#pair', 'X0', 'X1', 'L_pos', ...
	'Strain%', 'strain/#pair', 'cm/#pair', 'Mode', 'Output name'}, ...
	'ColumnWidth', {30, 150, 44, 44, 46, 46, 50, 50, 78, 72, 76, 128}, 'RowName', {}, ...
	'ColumnEditable', [false false false false true true true false false false false true], ...
	'CellSelectionCallback', @(~, ev) onSelect(ev), ...
	'CellEditCallback', @(~, ev) onEdit(ev));

%% ===== SISI KANAN, DI BAWAH TABEL: aksi + progres + log =====
% Lebar kerja sisi kanan = RW (850), mulai x=RX (536), ujung kanan x=1386.

% Tombol CSV geometri (X0/X1/L_pos)
csvExportBtn = uibutton(fig, 'Position', [RX 266 (RW-8)/2 28], ...
	'Text', '⬇ Export X0/X1/L_pos (CSV)', ...
	'Tooltip', 'Save X0/X1/L_pos of every experiment to CSV for editing elsewhere.', ...
	'BackgroundColor', [0.90 0.93 0.86], 'ButtonPushedFcn', @(~,~) onExportGeomCsv());
csvImportBtn = uibutton(fig, 'Position', [RX + (RW-8)/2 + 8, 266, (RW-8)/2, 28], ...
	'Text', '⬆ Import X0/X1/L_pos (CSV)', ...
	'Tooltip', 'Load X0/X1/L_pos from CSV (matched by experiment name).', ...
	'BackgroundColor', [0.84 0.91 0.97], 'ButtonPushedFcn', @(~,~) onImportGeomCsv());

% Tombol aksi utama + Abort
runBtn = uibutton(fig, 'Position', [RX 224 RW-140 36], ...
	'Text', 'Start Step 2 batch (.mat → PIV + GS + EXIF + geometry + drop dead frames)', ...
	'FontSize', 13, 'FontWeight', 'bold', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) onRun());
abortBtn = uibutton(fig, 'Position', [RX + RW - 130, 224, 130, 36], 'Text', 'Abort', ...
	'FontSize', 13, 'FontWeight', 'bold', 'Enable', 'off', ...
	'BackgroundColor', [0.85 0.33 0.27], 'FontColor', [1 1 1], 'ButtonPushedFcn', @(~,~) onAbort());

% Progress bar
barBG = uipanel(fig, 'Position', [RX 196 RW 22], 'BackgroundColor', [0.86 0.86 0.86], 'BorderType', 'line');
barFill = uipanel(barBG, 'Units', 'pixels', 'Position', [2 2 1 16], ...
	'BackgroundColor', [0.20 0.60 0.90], 'BorderType', 'none');
pctLabel = uilabel(barBG, 'Position', [1 1 RW-4 18], 'Text', '0%', ...
	'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'BackgroundColor', 'none');

% Status
statusLabel = uilabel(fig, 'Position', [RX 174 RW 20], 'Text', 'Ready.', ...
	'HorizontalAlignment', 'left', 'FontAngle', 'italic');

% Log
logArea = uitextarea(fig, 'Position', [RX 8 RW 162], 'Editable', 'off', ...
	'FontName', 'monospaced', 'Value', {''});

% Gerbang awal: "Tambah .mat" & "Simpan Progres" mati sampai folder root dipilih.
i_updateRootGated();

% --- Pembukaan terprogram (dari GRAIN1 "Lanjutkan ke Step 2") ---
% Bila dipanggil dgn folder root MAT PREP, tunjuk + pindai otomatis (metadata
% saja, tanpa dump). Bila autoSave=true, simpan progres SEGERA tanpa dialog
% sehingga sesi berikutnya tinggal "Muat Progres" untuk melanjutkan kerja.
if nargin >= 1 && ~isempty(rootArg) && ischar(rootArg) && isfolder(rootArg)
	autoSave = nargin >= 2 && ~isempty(autoSaveArg) && autoSaveArg;
	try
		setRoot(rootArg);
		onScan();
		if autoSave && ~isempty(procList)
			i_saveProgressSilent();
		end
	catch ME
		appendLog(sprintf('Programmatic open failed: %s', ME.message));
	end
end

%% ============================ FUNGSI NESTED =============================
	function np = i_effPairs(cnt, skip, nDrop, seqmode)
		% Hitung #pasangan FINAL dengan urutan yang benar:
		%   1) jumlah file SETELAH skip: stride = skip+1 -> nFiles = numel(1:stride:cnt)
		%   2) buang frame mati (QPIV): nUsed = max(0, nFiles - nDrop)
		%   3) pasangkan menurut mode:
		%        overlap (non-overlapping=false): tiap file berurutan -> nUsed-1 data
		%        non-overlap:                     pasangan terpisah    -> floor(nUsed/2)
		if nargin < 2 || isempty(skip);   skip   = 0; end
		if nargin < 3 || isempty(nDrop);  nDrop  = 0; end
		if nargin < 4 || isempty(seqmode); seqmode = 'consecutive'; end
		stride = max(1, round(skip) + 1);
		nFiles = numel(1:stride:max(round(cnt),0));
		nUsed  = max(0, nFiles - max(0, round(nDrop)));
		if strcmpi(seqmode, 'pairs')
			np = floor(nUsed / 2);          % non-overlapping: 1-2, 3-4, ...
		else
			np = max(0, nUsed - 1);         % overlapping: 1-2, 2-3, ...
		end
	end

	function e = normEntry(src)
		pabSrc = '';
		if isfield(src, 'pab_src'); pabSrc = src.pab_src; end
		e = struct('matfile', src.matfile, 'path', '', 'gsdir', '', ...
			'expdir', src.matfile, 'relpath', src.relpath, 'name', src.name, ...
			'count', src.count, 'gscount', src.gscount, 'suffix', src.suffix, ...
			'npairs', src.npairs, 'outname', src.outname, ...
			'seqmode', src.seqmode, 'seqstep', src.seqstep, 'has_exif', src.has_exif, ...
			'unpacked', '', 'exifdir', '', 'X0', NaN, 'X1', NaN, 'Lpos', NaN, ...
			'pab_src', pabSrc);
		if isfield(src, 'X0');   e.X0   = src.X0;   end
		if isfield(src, 'X1');   e.X1   = src.X1;   end
		if isfield(src, 'Lpos'); e.Lpos = src.Lpos; end
	end

	function addEntries(newE)
		if isempty(newE); return; end
		existing = {procList.matfile};
		added = 0; skipped = 0;
		for i = 1:numel(newE)
			if any(strcmp(newE(i).matfile, existing)); skipped = skipped + 1; continue; end
			procList(end+1) = normEntry(newE(i)); %#ok<AGROW>
			existing{end+1} = newE(i).matfile; %#ok<AGROW>
			added = added + 1;
		end
		refreshTable();
		if skipped > 0
			appendLog(sprintf('Added %d experiments; %d skipped (already listed).', added, skipped));
		elseif added > 0
			appendLog(sprintf('Added %d .mat experiments to the list.', added));
		end
	end

	function refreshTable()
		n = numel(procList);
		removeStyle(folderTable);
		if n == 0
			folderTable.Data = {};
			runBtn.Enable = 'off';
			scanSummary.Text = 'List is empty. Scan a .mat root folder or add a single .mat file.';
			return;
		end
		destRoot = i_outRoot();
		destdirs = repmat({destRoot}, 1, n);
		% (npairs dihitung per-baris di loop bawah, memakai skip/drop/mode efektif.)
		names = PIVlab_automasi_uniquenames(destdirs, {procList.outname});
		for i = 1:n; procList(i).outname = names{i}; end

		data = cell(n, 12);
		nGeom = 0;
		missCells = zeros(0, 2); lenCells = zeros(0, 2); shoCells = zeros(0, 2);
		badCells = zeros(0, 2);
		for i = 1:n
			data{i,1} = i;
			data{i,2} = procList(i).relpath;
			data{i,3} = procList(i).count;
			data{i,COL_X0}   = num2disp(procList(i).X0);
			data{i,COL_X1}   = num2disp(procList(i).X1);
			data{i,COL_LPOS} = num2disp(procList(i).Lpos);
			[stxt, scat] = pivanalyze.geom.strainText(procList(i).X0, procList(i).X1, procList(i).Lpos);
			data{i,COL_STRAIN} = stxt;

			% GRAIN2: input dari GRAIN1 sudah bersih (frame mati difilter di Step 1),
			% jadi TIDAK ada drop/eksklusi (nd=0). Mode pasangan & Skip mengikuti
			% input GUI GRAIN2 (dinamik): ubah OVL/NOVL atau Skip → #pair ikut berubah.
			eSeq  = i_seqOf(procList(i));
			eSkip = i_skipOf(procList(i));
			nd = 0;
			data{i,COL_MODE} = i_modeLabel(eSeq);
			% #pair efektif: (1) jumlah file setelah SKIP, (2) pasangkan menurut mode.
			procList(i).npairs = i_effPairs(procList(i).count, eSkip, nd, eSeq);
			data{i,COL_NPAIR} = procList(i).npairs;
			% Spasi antar-frame: strain & perpindahan (cm) DIBAGI #pair → untuk
			% membandingkan keseragaman langkah antar-eksperimen.
			[spp, cpp] = i_perPair(procList(i).X0, procList(i).X1, procList(i).Lpos, procList(i).npairs);
			data{i,COL_SPP} = spp;
			data{i,COL_CPP} = cpp;
			data{i,COL_NAME} = procList(i).outname;

			if isnan(procList(i).X0);   missCells(end+1,:) = [i COL_X0];   end %#ok<AGROW>
			if isnan(procList(i).X1);   missCells(end+1,:) = [i COL_X1];   end %#ok<AGROW>
			if isnan(procList(i).Lpos); missCells(end+1,:) = [i COL_LPOS]; end %#ok<AGROW>
			switch scat
				case 'lengthening'; lenCells(end+1,:) = [i COL_STRAIN]; nGeom = nGeom + 1; %#ok<AGROW>
				case 'shortening';  shoCells(end+1,:) = [i COL_STRAIN]; nGeom = nGeom + 1; %#ok<AGROW>
				case 'badL0';       badCells(end+1,:) = [i COL_STRAIN]; %#ok<AGROW>
			end
		end
		folderTable.Data = data;

		if ~isempty(missCells); addStyle(folderTable, styMissing,  'cell', missCells); end
		if ~isempty(lenCells);  addStyle(folderTable, styLengthen, 'cell', lenCells);  end
		if ~isempty(shoCells);  addStyle(folderTable, styShorten,  'cell', shoCells);  end
		if ~isempty(badCells);  addStyle(folderTable, styBadL0,    'cell', badCells);  end

		totalFiles = sum([procList.count]);
		totalPairs = sum([procList.npairs]);
		scanSummary.Text = sprintf(['%d experiments | %d RAW | %d pairs | ' ...
			'geometry:%d/%d | output → %s'], ...
			n, totalFiles, totalPairs, nGeom, n, destRoot);
		runBtn.Enable = 'on';

		if ~isempty(pv.fig) && isvalid(pv.fig); pvSyncGeom(); end
	end

	function r = i_outRoot()
		% Folder tujuan .mat hasil. Kosong -> PIV_<tgl> di dalam root .mat
		% (atau folder berkas .mat pertama bila root belum dipilih).
		ov = strtrim(outField.Value);
		if ~isempty(ov); r = ov; return; end
		base = rootFolder;
		if isempty(base) || ~isfolder(base)
			if ~isempty(procList); base = fileparts(procList(1).matfile); else; base = pwd; end
		end
		r = pivanalyzemat.core.pivOutDir(base);   % <base>/PIV_<tgl> (kontrak bersama)
	end

	function onBrowseParent()
		try
			start = i_safeDir(parentField.Value);
			minFig();
			try
				sel = uigetdir(start, 'Pick the root folder holding the .mat files (Step 1)');
			catch
				% R2025b kadang menolak startpath di uigetdir -> coba TANPA path.
				sel = uigetdir('', 'Pick the root folder holding the .mat files (Step 1)');
			end
			restoreFig();
			if ischar(sel) && ~isempty(sel)
				setRoot(sel);
				onScan();   % folder root = input utama -> pindai metadata SAJA (tanpa dump)
			end
		catch ME
			restoreFig();
			uialert(fig, sprintf('Failed to pick the folder:\n\n%s', ME.message), 'Error');
		end
	end

	function d = i_safeDir(cand)
		% Folder awal yang DIJAMIN char valid utk dialog: kandidat -> rootFolder
		% -> home -> pwd. Selalu char baris, tanpa kegagalan.
		d = '';
		cands = {char(string(cand)), char(rootFolder), char(java.lang.System.getProperty('user.home')), pwd};
		for i = 1:numel(cands)
			c = cands{i};
			if ~isempty(c) && ischar(c) && isfolder(c); d = c; return; end
		end
		d = pwd;   % fallback terakhir
	end

	function setRoot(folder)
		% Tetapkan folder root aktif + buka kunci tombol yang butuh root.
		rootFolder = char(folder);
		parentField.Value = rootFolder;
		i_updateRootGated();
		refreshTable();
	end

	function tf = i_haveRoot()
		tf = ~isempty(rootFolder) && isfolder(rootFolder);
	end

	function i_updateRootGated()
		% "Tambah .mat" hanya boleh dipakai bila folder root sudah ditentukan
		% (unpack & output selalu relatif terhadap root tsb).
		st = 'off'; if i_haveRoot(); st = 'on'; end
		addBtn.Enable      = st;
		addMultiBtn.Enable = st;
		saveProgBtn.Enable = st;
	end

	function r = i_unpackRoot()
		% Folder induk bongkaran .mat: subfolder hashed DI DALAM folder root.
		r = pivanalyzemat.core.rootUnpackRoot(rootFolder);
	end

	function e = i_unpackWithProgress(entry, parentFig)
		% Bongkar satu .mat dgn progress bar (saat pertama kali dump isi ke folder).
		% Cache hit -> dump dilewati, dialog hanya berkedip sebentar (100%).
		if nargin < 2 || isempty(parentFig) || ~isvalid(parentFig); parentFig = fig; end
		dlg = uiprogressdlg(parentFig, 'Title', 'Loading .mat into the work folder', ...
			'Message', sprintf('Membongkar %s ...', entry.name), ...
			'Indeterminate', 'off', 'Value', 0, 'Cancelable', 'off');
		cleaner = onCleanup(@() i_closeDlg(dlg)); %#ok<NASGU>
		e = pivanalyzemat.core.unpackMat(entry, 'LogFcn', @appendLog, ...
			'RootTmp', i_unpackRoot(), ...
			'ProgressFcn', @(f, m) i_dlgTick(dlg, f, m));
	end

	function i_dlgTick(dlg, f, m)
		if isempty(dlg) || ~isvalid(dlg); return; end
		dlg.Value = max(0, min(1, f));
		if nargin > 2 && ~isempty(m); dlg.Message = char(m); end
		drawnow limitrate;
	end

	function i_closeDlg(dlg)
		try if ~isempty(dlg) && isvalid(dlg); close(dlg); end; catch; end
	end

	function onParentTyped()
		% Folder root diketik manual -> tetapkan & pindai otomatis bila valid.
		parent = strtrim(parentField.Value);
		if isempty(parent); rootFolder = ''; i_updateRootGated(); return; end
		if ~isfolder(parent)
			i_updateRootGated();
			uialert(fig, 'Root folder is not valid.', 'Invalid folder', 'Icon', 'warning');
			return;
		end
		setRoot(parent);
		onScan();   % folder root diketik = input utama -> pindai metadata SAJA (tanpa dump)
	end

	function onScan()
		parent = strtrim(parentField.Value);
		if isempty(parent) || ~isfolder(parent)
			uialert(fig, 'Pick a valid root folder first.', 'Invalid folder');
			return;
		end
		setRoot(parent);
		scanSummary.Text = 'Scanning PIVPrep .mat files (pivprep_single_v1)...'; drawnow;
		% Pindai + susun tabel bisa lama (banyak .mat / berkas besar) → bilah tunggu
		% modal supaya tidak terasa "hang". Ditutup otomatis di semua jalur keluar.
		dlg = [];
		try
			dlg = uiprogressdlg(fig, 'Title', 'Scanning experiments', 'Indeterminate', 'on', ...
				'Message', sprintf('Scanning .mat files & building the experiment table...\n\n%s', parent));
		catch; end
		closer = onCleanup(@() i_closeDlg(dlg));   %#ok<NASGU>
		drawnow;
		try
			sc = pivanalyzemat.core.scanMats(parent, 'Recursive', recursiveCb.Value, ...
				'MinFrames', round(minField.Value), 'Sequencing', seqDropdown.Value);
		catch ME
			uialert(fig, sprintf('Scan failed:\n%s', ME.message), 'Error');
			return;
		end
		if isempty(sc)
			uialert(fig, sprintf('No pivprep_single_v1 .mat file found under:\n%s', parent), ...
				'No .mat found', 'Icon', 'warning');
			refreshTable();
			return;
		end
		if ~isempty(dlg) && isvalid(dlg)
			dlg.Message = sprintf('Building the table for %d experiments...', numel(sc));
			drawnow;
		end
		addEntries(sc);
	end

	function onAddSingle()
		if ~i_requireRoot(); return; end
		try
			start = fullfile(i_safeDir(i_startDir()), '*.mat');   % dir DIJAMIN valid
			minFig();
			[fn, fp] = uigetfile({'*.mat', 'PIVPrep single (.mat)'}, ...
				'Pick one .mat file (pivprep_single_v1)', start);
			restoreFig();
			if isequal(fn, 0); return; end
			ent = i_resolveMat(fullfile(fp, fn));
			if isempty(ent)
				uialert(fig, sprintf('This file is not a valid pivprep_single_v1:\n%s', fullfile(fp, fn)), ...
					'Bukan .mat valid', 'Icon', 'warning');
				return;
			end
			addEntries(ent);
		catch ME
			restoreFig();
			uialert(fig, sprintf('Failed to add the .mat:\n\n%s', ME.message), 'Error');
		end
	end

	function onAddMulti()
		if ~i_requireRoot(); return; end
		try
			start = fullfile(i_safeDir(i_startDir()), '*.mat');   % dir DIJAMIN valid
			minFig();
			[fns, fp] = uigetfile({'*.mat', 'PIVPrep single (.mat)'}, ...
				'Pick several .mat files (Ctrl/Shift-click)', start, 'MultiSelect', 'on');
			restoreFig();
			if isequal(fns, 0); return; end
			if ischar(fns); fns = {fns}; end
			before0 = numel(procList);
			for i = 1:numel(fns)
				ent = i_resolveMat(fullfile(fp, fns{i}));
				if isempty(ent)
					appendLog(sprintf('  (skipped — not pivprep_single_v1) %s', fns{i}));
				else
					addEntries(ent);
				end
			end
			appendLog(sprintf('"Add several" done: %d experiments out of %d selected files.', ...
				numel(procList) - before0, numel(fns)));
		catch ME
			restoreFig();
			uialert(fig, sprintf('Failed to add the .mat:\n\n%s', ME.message), 'Error');
		end
	end

	function ent = i_resolveMat(matPath)
		% Pindai folder berkas tsb lalu ambil entry yang cocok (membaca metadata).
		ent = [];
		fpdir = fileparts(matPath);
		sc = pivanalyzemat.core.scanMats(fpdir, 'Recursive', false, ...
			'MinFrames', round(minField.Value), 'Sequencing', seqDropdown.Value);
		for i = 1:numel(sc)
			if strcmp(sc(i).matfile, matPath); ent = sc(i); return; end
		end
	end

	function s = i_startDir()
		s = parentField.Value;
		if isempty(s) || ~isfolder(s)
			if ~isempty(procList); s = fileparts(procList(end).matfile); else; s = pwd; end
		end
	end

	function tf = i_requireRoot()
		tf = i_haveRoot();
		if ~tf
			uialert(fig, ['Set the ROOT FOLDER (holding the .mat files) first. ' ...
				'The "Add .mat" buttons only light up once a root folder is picked — ' ...
				'unpacking & output are always relative to that root folder.'], ...
				'No root folder set', 'Icon', 'warning');
		end
	end

	function onRemove()
		if isempty(selectedRows)
			uialert(fig, 'Click the experiment rows you want to remove in the table first.', 'Nothing selected');
			return;
		end
		keep = true(1, numel(procList));
		sr = selectedRows(selectedRows >= 1 & selectedRows <= numel(procList));
		keep(sr) = false;
		procList = procList(keep);
		selectedRows = [];
		refreshTable();
	end

	function onClear()
		procList = EMPTY; selectedRows = []; refreshTable();
	end

	% ----------------------- simpan / muat progres -----------------------
	function onSaveProgress()
		if ~i_requireRoot(); return; end
		if isempty(procList)
			uialert(fig, 'List is empty — there is no progress to save.', 'Empty', 'Icon', 'warning');
			return;
		end
		% Lokasi DIPAKSA di folder root terpilih (tanpa dialog navigasi); nama
		% default PABSA2_progress_<namaroot>.mat. Konfirmasi bila menimpa.
		defName  = sprintf('PABSA2_progress_%s.mat', i_rootLeaf());
		destPath = fullfile(rootFolder, defName);
		try
			if isfile(destPath)
				sel = uiconfirm(fig, sprintf(['A progress file already exists in the root folder:\n\n%s\n\n' ...
					'Overwrite?'], destPath), 'Overwrite progress?', ...
					'Options', {'Overwrite', 'Cancel'}, 'DefaultOption', 1, ...
					'CancelOption', 2, 'Icon', 'warning');
				if ~strcmp(sel, 'Overwrite'); return; end
			end
			prog = i_buildSnapshot(); %#ok<NASGU>
			save(destPath, 'prog', '-v7');
			appendLog(sprintf('Progress saved: %s  (%d experiments, %d with QPIV).', ...
				destPath, numel(prog.entries), nnz(i_qpivDoneMask())));
			statusLabel.Text = sprintf('Progress saved → %s', defName);
		catch ME
			uialert(fig, sprintf('Failed to save the progress:\n\n%s', ME.message), 'Error');
		end
	end

	function i_saveProgressSilent()
		% Simpan progres SEGERA ke <root>/PABSA2_progress_<namaroot>.mat TANPA
		% dialog/konfirmasi (timpa bila ada). Dipakai saat GRAIN2 dibuka dari GRAIN1
		% agar kerja bisa dilanjutkan lain waktu. Diam bila gagal (cuma log).
		if ~i_haveRoot() || isempty(procList); return; end
		defName  = sprintf('PABSA2_progress_%s.mat', i_rootLeaf());
		destPath = fullfile(rootFolder, defName);
		try
			prog = i_buildSnapshot(); %#ok<NASGU>
			save(destPath, 'prog', '-v7');
			appendLog(sprintf('Initial progress saved automatically: %s  (%d experiments).', ...
				destPath, numel(prog.entries)));
			statusLabel.Text = sprintf('Progress saved automatically → %s', defName);
		catch ME
			appendLog(sprintf('Automatic progress save failed: %s', ME.message));
		end
	end

	function onLoadProgress()
		try
			% dir DIJAMIN valid (rootFolder -> home -> pwd); + pola berkas.
			startSpec = fullfile(i_safeDir(rootFolder), '*.mat');
			minFig();
			[fn, fp] = uigetfile({'*.mat', 'GRAINSA2 progress (.mat)'}, ...
				'Load GRAINSA2 progress', startSpec);
			restoreFig();
			if isequal(fn, 0); return; end
			L = load(fullfile(fp, fn));
			if ~isfield(L, 'prog') || ~isfield(L.prog, 'format') || ...
					~strcmp(L.prog.format, 'pabsa2_progress_v1')
				uialert(fig, sprintf('This file is not a valid GRAINSA2 progress:\n%s', ...
					fullfile(fp, fn)), 'Not a GRAINSA2 progress', 'Icon', 'warning');
				return;
			end
			i_applySnapshot(L.prog);
			appendLog(sprintf('Progress loaded: %s  (%d experiments).', ...
				fullfile(fp, fn), numel(procList)));
			statusLabel.Text = sprintf('Progress loaded ← %s', fn);
		catch ME
			restoreFig();
			uialert(fig, sprintf('Failed to load the progress:\n\n%s', ME.message), 'Error');
		end
	end

	function leaf = i_rootLeaf()
		leaf = '';
		if ~isempty(rootFolder)
			[~, b, e] = fileparts(regexprep(char(rootFolder), '[\\/]+$', ''));
			leaf = [b e];
		end
		leaf = regexprep(leaf, '[^\w\-]', '_');
		if isempty(leaf); leaf = 'root'; end
	end

	function prog = i_buildSnapshot()
		% Snapshot SELURUH keadaan: daftar berkas, geometri, setting PIV/GS/EXIF,
		% + koleksi QPIV (entry progres lintas-sesi untuk tiap .mat di daftar).
		prog = struct();
		prog.format     = 'pabsa2_progress_v1';
		prog.saved_at   = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1>
		prog.root       = rootFolder;
		prog.out_field  = outField.Value;
		prog.entries    = procList;            % seluruh daftar (incl. X0/X1/Lpos/outname)
		prog.settings   = struct( ...
			'recursive',   recursiveCb.Value, ...
			'sequencing',  seqDropdown.Value, ...
			'skip',        skipField.Value, ...
			'workers',     workersField.Value, ...
			'minframes',   minField.Value, ...
			'gs_quality',  gsQualField.Value, ...
			'drop_first',  dropFirstCb.Value, ...
			'reencode',    reencodeCb.Value, ...
			'embed_time',  embedTimeCb.Value, ...
			'embed_table', embedTableCb.Value, ...
			'iw_passes',   [iwF(1).Value iwF(2).Value iwF(3).Value iwF(4).Value], ...
			'num_passes',  npassDd.Value, ...
			'scan_orient', scanOrientDd.Value, ...
			'scan_pos',    scanPosField.Value);
		% Koleksi QPIV: entry progres (config + frame mati) per .mat di daftar.
		qp = PIVlab_automasi_progress('empty'); qp(:) = [];
		for i = 1:numel(procList)
			pe = PIVlab_automasi_progress('get', procList(i).expdir, procList(i).pab_src);
			if ~isempty(pe); qp(end+1) = pe; end %#ok<AGROW>
		end
		prog.qpiv = qp;
	end

	function i_applySnapshot(prog)
		% Pulihkan setting GUI, koleksi QPIV, lalu daftar berkas.
		% 1) setting umum
		if isfield(prog, 'settings')
			s = prog.settings;
			i_setIf(@() set(recursiveCb,  'Value', logical(s.recursive)),  isfield(s,'recursive'));
			i_setIf(@() set(seqDropdown,  'Value', s.sequencing),          isfield(s,'sequencing'));
			i_setIf(@() set(skipField,    'Value', s.skip),                isfield(s,'skip'));
			i_setIf(@() set(workersField, 'Value', s.workers),             isfield(s,'workers'));
			i_setIf(@() set(minField,     'Value', s.minframes),           isfield(s,'minframes'));
			i_setIf(@() set(gsQualField,  'Value', s.gs_quality),          isfield(s,'gs_quality'));
			i_setIf(@() set(dropFirstCb,  'Value', logical(s.drop_first)), isfield(s,'drop_first'));
			i_setIf(@() set(reencodeCb,   'Value', logical(s.reencode)),   isfield(s,'reencode'));
			i_setIf(@() set(embedTimeCb,  'Value', logical(s.embed_time)), isfield(s,'embed_time'));
			i_setIf(@() set(embedTableCb, 'Value', logical(s.embed_table)),isfield(s,'embed_table'));
			i_setIf(@() set(scanOrientDd, 'Value', s.scan_orient),         isfield(s,'scan_orient'));
			i_setIf(@() set(scanPosField, 'Value', s.scan_pos),            isfield(s,'scan_pos'));
			if isfield(s, 'iw_passes') && numel(s.iw_passes) >= 4
				for jj = 1:4; iwF(jj).Value = s.iw_passes(jj); end
			end
			if isfield(s, 'num_passes')
				try npassDd.Value = char(string(s.num_passes)); catch; end
			end
		end
		% 2) folder root + output
		if isfield(prog, 'root') && ~isempty(prog.root) && isfolder(prog.root)
			setRoot(prog.root);
		elseif isfield(prog, 'root') && ~isempty(prog.root)
			parentField.Value = prog.root; rootFolder = prog.root; i_updateRootGated();
			appendLog(sprintf('[!] Saved root folder not found: %s', prog.root));
		end
		if isfield(prog, 'out_field'); outField.Value = char(prog.out_field); end
		% 3) koleksi QPIV -> tulis ke berkas progres lintas-sesi (upsert per entry)
		if isfield(prog, 'qpiv') && ~isempty(prog.qpiv)
			nq = 0;
			for i = 1:numel(prog.qpiv)
				try PIVlab_automasi_progress('set', prog.qpiv(i)); nq = nq + 1; catch; end
			end
			appendLog(sprintf('Koleksi QPIV dipulihkan: %d entry.', nq));
		end
		% 4) daftar berkas
		if isfield(prog, 'entries') && ~isempty(prog.entries)
			procList = i_coerceList(prog.entries);
		else
			procList = EMPTY;
		end
		selectedRows = [];
		refreshTable();
	end

	function i_setIf(fn, cond)
		if cond; try fn(); catch; end; end
	end

	function out = i_coerceList(entries)
		% Selaraskan entry tersimpan ke skema procList kini (normEntry per elemen).
		out = EMPTY;
		for i = 1:numel(entries)
			out(end+1) = normEntry(entries(i)); %#ok<AGROW>
		end
	end

	function onBrowseOut()
		try
			start = i_safeDir(outField.Value);
			minFig();
			try
				sel = uigetdir(start, 'Pick the output folder for the PIV .mat results');
			catch
				sel = uigetdir('', 'Pick the output folder for the PIV .mat results');
			end
			restoreFig();
			if ischar(sel) && ~isempty(sel); outField.Value = sel; refreshTable(); end
		catch ME
			restoreFig();
			uialert(fig, sprintf('Failed to pick the folder:\n\n%s', ME.message), 'Error');
		end
	end

	function onClearOut()
		outField.Value = ''; refreshTable();
	end

	function onApplySel()
		if isempty(selectedRows)
			uialert(fig, 'Select a row in the table first, then click this button.', 'Nothing selected'); return;
		end
		v0 = parseField(x0Field.Value); v1 = parseField(x1Field.Value); vL = parseField(lposField.Value);
		if isnan(v0) && isnan(v1) && isnan(vL)
			uialert(fig, 'Fill in at least one of X0 / X1 / L_pos.', 'Empty'); return;
		end
		sr = selectedRows(selectedRows >= 1 & selectedRows <= numel(procList));
		for r = sr(:)'
			if ~isnan(v0); procList(r).X0   = v0; end
			if ~isnan(v1); procList(r).X1   = v1; end
			if ~isnan(vL); procList(r).Lpos = vL; end
		end
		refreshTable();
		appendLog(sprintf('Geometry applied to %d selected rows.', numel(sr)));
	end

	function onApplyLposAll()
		vL = parseField(lposField.Value);
		if isnan(vL); uialert(fig, 'Fill in the L_pos value (cm) first.', 'L_pos empty'); return; end
		if isempty(procList); uialert(fig, 'The list is still empty.', 'Empty'); return; end
		for r = 1:numel(procList); procList(r).Lpos = vL; end
		refreshTable();
		appendLog(sprintf('L_pos = %.4g cm applied to ALL %d experiments.', vL, numel(procList)));
	end

	function onSelect(ev)
		if isempty(ev.Indices); selectedRows = []; else; selectedRows = unique(ev.Indices(:, 1)); end
	end

	% ------------------- CSV geometri (X0/X1/L_pos) -----------------------
	function onExportGeomCsv()
		if isempty(procList)
			uialert(fig, 'The list is still empty. Scan/add a .mat first.', 'Empty'); return;
		end
		def = 'geometri_X0X1Lpos.csv';
		minFig();
		[fn, fp] = uiputfile({'*.csv', 'Geometry CSV (*.csv)'}, ...
			'Save X0/X1/L_pos to CSV', fullfile(i_startDir(), def));
		restoreFig();
		if isequal(fn, 0); return; end
		dest = fullfile(fp, fn);

		n = numel(procList);
		Eksperimen = strings(n, 1);
		X0 = strings(n, 1); X1 = strings(n, 1); L_pos = strings(n, 1);
		for i = 1:n
			Eksperimen(i) = string(procList(i).relpath);
			X0(i)    = i_numToCsv(procList(i).X0);
			X1(i)    = i_numToCsv(procList(i).X1);
			L_pos(i) = i_numToCsv(procList(i).Lpos);
		end
		T = table(Eksperimen, X0, X1, L_pos);
		try
			writetable(T, dest);
		catch err
			uialert(fig, sprintf('Failed to write the CSV:\n%s', err.message), 'Error'); return;
		end
		appendLog(sprintf('Exported geometry of %d experiments → %s', n, dest));
		statusLabel.Text = sprintf('Geometry CSV saved: %s', fn);
	end

	function onImportGeomCsv()
		if isempty(procList)
			uialert(fig, 'The list is still empty. Scan/add a .mat before importing.', 'Empty'); return;
		end
		minFig();
		[fn, fp] = uigetfile({'*.csv', 'Geometry CSV (*.csv)'}, ...
			'Load X0/X1/L_pos from CSV', i_startDir());
		restoreFig();
		if isequal(fn, 0); return; end
		src = fullfile(fp, fn);
		try
			T = readtable(src, 'TextType', 'string');
		catch err
			uialert(fig, sprintf('Failed to read the CSV:\n%s', err.message), 'Error'); return;
		end
		need = {'Eksperimen', 'X0', 'X1', 'L_pos'};
		vn = string(T.Properties.VariableNames);
		if ~all(ismember(need, vn))
			uialert(fig, sprintf(['CSV columns must be: %s\nFound: %s\n\n' ...
				'Use the Export button first to produce a recognised format.'], ...
				strjoin(need, ', '), strjoin(cellstr(vn), ', ')), 'Unrecognised format'); return;
		end
		keyCsv = i_normName(string(T.Eksperimen));
		nMatch = 0; nMiss = 0; missList = strings(0, 1);
		for i = 1:numel(procList)
			k = i_normName(string(procList(i).relpath));
			j = find(keyCsv == k, 1);
			if isempty(j); nMiss = nMiss + 1; missList(end+1) = string(procList(i).relpath); continue; end %#ok<AGROW>
			procList(i).X0   = i_csvToNum(T.X0(j));
			procList(i).X1   = i_csvToNum(T.X1(j));
			procList(i).Lpos = i_csvToNum(T.L_pos(j));
			nMatch = nMatch + 1;
		end
		refreshTable();
		appendLog(sprintf('Geometry import from %s: %d matched, %d missing from the CSV.', fn, nMatch, nMiss));
		if nMiss > 0
			uialert(fig, sprintf(['%d rows updated. %d experiments are missing from the CSV (skipped):\n%s'], ...
				nMatch, nMiss, strjoin(cellstr(missList), ', ')), 'Partly skipped', 'Icon', 'warning');
		else
			statusLabel.Text = sprintf('Geometry import done: %d rows updated.', nMatch);
		end
	end

	function onEdit(ev)
		r = ev.Indices(1); c = ev.Indices(2);
		if r < 1 || r > numel(procList); return; end
		switch c
			case COL_X0;   procList(r).X0   = parseCell(ev.NewData);
			case COL_X1;   procList(r).X1   = parseCell(ev.NewData);
			case COL_LPOS; procList(r).Lpos = parseCell(ev.NewData);
			case COL_NAME; procList(r).outname = char(string(ev.NewData));
		end
		refreshTable();
	end

	% --------------------------- Quick PIV --------------------------------
	function onQuickPIV()
		sr = selectedRows(selectedRows >= 1 & selectedRows <= numel(procList));
		if isempty(sr)
			uialert(fig, 'Select one experiment row in the table first, then click Quick PIV.', ...
				'Belum ada pilihan'); return;
		end
		[job, key] = i_buildQpivJob(sr(1));
		if isempty(job); return; end
		qpivRow = sr(1);
		job.close_fcn = @i_qpivCleanupTmp;   % tutup jendela QPIV -> hapus bongkaran temporer
		try
			PIVlab_automasi_qpiv_GUI_V2(job, key, @refreshTable, @i_qpivNav);
		catch ME
			i_qpivCleanupTmp();
			uialert(fig, sprintf('Failed to open Quick PIV:\n\n%s', ME.message), 'Error');
		end
	end

	function i_qpivCleanupTmp()
		% Hapus folder bongkaran RAW temporer exp QPIV yang sedang/terakhir dibuka.
		% Aman dipanggil berkali-kali (no-op bila sudah kosong). Bersihkan juga
		% jejak path di procList agar tak menunjuk folder yang sudah dihapus.
		d = qpivTmpDir; qpivTmpDir = '';
		if isempty(d) || ~isfolder(d); return; end
		try
			rmdir(d, 's');
			appendLog(sprintf('Bongkaran QPIV (temporer) dihapus: %s', d));
		catch ME
			appendLog(sprintf('[!] Failed to delete the QPIV unpack folder: %s', ME.message));
		end
		% lupakan path RAW yang kini tak ada (biar refresh/preview tak salah baca)
		for i = 1:numel(procList)
			if ~isempty(procList(i).unpacked) && strcmp(procList(i).unpacked, d)
				procList(i).unpacked = ''; procList(i).path = '';
				procList(i).gsdir = ''; procList(i).exifdir = '';
			end
		end
	end

	function [job, key] = i_buildQpivJob(r)
		% Bongkar exp baris r (RAW penuh, TEMPORER) lalu rakit struct job QPIV.
		% Bongkaran exp QPIV SEBELUMNYA dihapus dulu — hanya SATU exp menempati
		% disk pada satu waktu (dump on-demand & temporer). job=[] bila gagal.
		job = []; key = '';
		if r < 1 || r > numel(procList); return; end
		i_qpivCleanupTmp();   % hapus bongkaran exp QPIV sebelumnya (bila ada)
		statusLabel.Text = sprintf('Unpacking %s for Quick PIV...', procList(r).name); drawnow;
		try
			e = i_unpackWithProgress(procList(r));
		catch ME
			statusLabel.Text = 'Ready.';
			uialert(fig, sprintf('Failed to unpack the .mat:\n\n%s', ME.message), 'Error'); return;
		end
		procList(r).unpacked = e.unpacked;
		procList(r).path     = e.path;
		procList(r).gsdir    = e.gsdir;
		procList(r).exifdir  = e.exifdir;
		qpivTmpDir = e.unpacked;   % tandai utk dihapus saat pindah/tutup QPIV
		statusLabel.Text = 'Ready.';

		key   = PIVlab_automasi_progress('key', procList(r).expdir);   % key = .mat (stabil)
		saved = PIVlab_automasi_progress('get', key, procList(r).pab_src);  % fallback: folder RAW Step 0

		% QPIV diagnostik: param PIV (IW/#pass/skip/overlap) SELALU dari main GUI
		% (sama dgn produksi). Hanya garis-scan (orient/pos) & ignore_frames yang
		% dipulihkan dari progres tersimpan bila ada.
		job = struct();
		job.raw_folder  = e.path;             % folder RAW sementara
		job.expdir      = procList(r).expdir; % .mat (kunci progres)
		job.name        = procList(r).relpath;
		job.suffix      = procList(r).suffix;
		job.num_workers = round(workersField.Value);
		job.cache_file  = fullfile(e.unpacked, [procList(r).outname '_QPIV_cache.mat']);
		% --- param produksi (main GUI) ---
		job.sequencing  = seqDropdown.Value;
		job.skip        = round(skipField.Value);
		job.iw_passes   = [iwF(1).Value iwF(2).Value iwF(3).Value iwF(4).Value];
		job.num_passes  = str2double(npassDd.Value);
		% --- garis scan + frame mati: pulihkan dari progres bila ada ---
		if ~isempty(saved)
			job.scan_orient   = saved.scan_orient;
			job.scan_pos_pct  = saved.scan_pos_pct;
			job.ignore_frames = saved.ignore_frames;
		else
			job.scan_orient   = scanOrientDd.Value;
			job.scan_pos_pct  = scanPosField.Value;
			job.ignore_frames = [];
		end
	end

	function newJob = i_qpivNav(dirn)
		% Callback navigasi dari jendela QPIV: pindah ke exp berikut/sebelumnya
		% (wrap-around) lalu kembalikan job-nya. [] bila tak ada/ gagal.
		newJob = [];
		n = numel(procList);
		if n == 0; return; end
		nextR = mod((qpivRow - 1) + sign(dirn), n) + 1;   % wrap 1..n
		[j, ~] = i_buildQpivJob(nextR);
		if isempty(j); return; end
		qpivRow = nextR;
		% sorot baris baru di tabel induk agar konteks jelas
		selectedRows = nextR;
		newJob = j;
	end

	function s = i_seqOf(p)
		% Sequencing efektif baris: 'skip'/'pairs' dari .mat menang; else dropdown.
		if strcmpi(p.seqmode, 'pairs'); s = 'pairs';
		else; s = 'consecutive'; end
		if strcmpi(p.seqmode, 'consecutive') && ~strcmpi(seqDropdown.Value, 'consecutive')
			s = seqDropdown.Value;   % .mat netral -> ikut pilihan GUI
		end
	end

	function k = i_skipOf(p)
		if strcmpi(p.seqmode, 'skip'); k = max(0, round(p.seqstep) - 1);
		else; k = round(skipField.Value); end
	end

	function m = i_qpivDoneMask()
		% Mask: eksperimen mana yang sudah dievaluasi & disimpan Quick PIV.
		n = numel(procList);
		m = false(1, n);
		allProg = PIVlab_automasi_progress('all');
		for i = 1:n
			pe = i_findProg(allProg, procList(i).expdir, procList(i).pab_src);
			m(i) = ~isempty(pe) && isfield(pe, 'qpiv_done') && logical(pe.qpiv_done);
		end
	end

	function out = i_decorateNames(list, seq, skip, npass, intAreas)
		% Bentuk nama output: [BASE]-[A]-[B]-[C]-[D]
		%   [A] OVL (overlap) | NOVL (non-overlap)
		%   [B] S<skip>            (selalu ada, mis S0, S2)
		%   [C] <fileAsli>to<pasanganFinal>  (pasangan = i_effPairs incl skip+drop)
		%   [D] <#pass>p<px_pass_terakhir>px (mis 3p25px) — dari main GUI
		out = list;
		if strcmpi(seq, 'pairs'); aTag = 'NOVL'; else; aTag = 'OVL'; end
		bTag = sprintf('S%d', round(skip));
		np = max(1, min(4, round(npass)));
		pxLast = round(intAreas(np));           % px pass TERAKHIR yang dipakai
		dTag = sprintf('%dp%dpx', np, pxLast);
		for i = 1:numel(out)
			% GRAIN2 tanpa drop/eksklusi: pasangan = fungsi(count, skip, mode) saja.
			nPair = i_effPairs(out(i).count, skip, 0, seq);
			cTag  = sprintf('%dto%d', round(out(i).count), nPair);
			base  = char(out(i).outname);       % nama dasar (kolom Nama Output)
			out(i).outname = sprintf('%s-%s-%s-%s-%s', base, aTag, bTag, cTag, dTag);
		end
	end

	function onRun()
		if isempty(procList)
			uialert(fig, 'The experiment list is empty.', 'Empty list'); return;
		end
		% QPIV = diagnostik MURNI: hanya menyumbang daftar frame mati (ignore_frames).
		% SEMUA param produksi (IW/#pass/skip/overlap) diambil dari main GUI ini,
		% sama untuk semua eksperimen — tak ada lagi gating "semua wajib QPIV".
		nw  = round(workersField.Value);
		seq = seqDropdown.Value;
		outRoot = i_outRoot();
		intAreas = [iwF(1).Value iwF(2).Value iwF(3).Value iwF(4).Value];
		numPasses = str2double(npassDd.Value);
		skipGlobal = round(skipField.Value);
		if ~isfolder(outRoot)
			[ok, msg] = mkdir(outRoot);
			if ~ok
				uialert(fig, sprintf('Could not create the output folder:\n%s\n%s', outRoot, msg), 'Error'); return;
			end
		end

		nIncomplete = sum(arrayfun(@(e) isnan(e.X0)||isnan(e.X1)||isnan(e.Lpos), procList));
		if nIncomplete > 0
			sel = uiconfirm(fig, sprintf(['%d of %d experiments do NOT have complete X0/X1/L_pos ' ...
				'(stored as NaN).\n\nContinue the batch?'], nIncomplete, numel(procList)), ...
				'Incomplete geometry', 'Options', {'Continue', 'Cancel'}, ...
				'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'warning');
			if ~strcmp(sel, 'Continue'); return; end
		end

		abortReq = false;
		setEnabled('off');
		abortBtn.Enable = 'on';
		logLines = {}; logArea.Value = {''};
		resetProgress();
		statusLabel.Text = 'Starting the Step 2 batch...';
		drawnow;

		nTotal = numel(procList);
		cleanupObj = onCleanup(@() finishRun()); %#ok<NASGU>
		try
			cfg = pivanalyze.config( ...
				'Folders',        [], ...
				'NumWorkers',     nw, ...
				'Sequencing',     seq, ...
				'OutputFolder',   outRoot, ...
				'GSQuality',      round(gsQualField.Value), ...
				'DropFirstGS',    dropFirstCb.Value, ...
				'ReencodeJpeg',   reencodeCb.Value, ...
				'EmbedExifTime',  embedTimeCb.Value, ...
				'EmbedExifTable', embedTableCb.Value, ...
				'IntAreas',       intAreas, ...
				'NumPasses',      numPasses, ...
				'Skip',           skipGlobal, ...
				'ReadProgress',   false, ...      % GRAIN2: input dari GRAIN1 sudah bersih -> TIDAK baca daftar abaikan QPIV (tanpa drop/eksklusi)
				'QpivParamsOverride', false, ...  % QPIV diagnostik: param produksi dari GUI ini saja
				'Confirm',        false, ...
				'Provenance',     'GRAIN2', ...
				'ProgressFcn',    @updateProgress, ...
				'LogFcn',         @appendLog, ...
				'CheckAbort',     @checkAbort);
			% Bongkar .mat ke subfolder hashed DI DALAM folder root (bukan tempdir).
			cfg.UnpackRoot = i_unpackRoot();

			% Hiasi nama output: <base>-[OVL|NOVL]-S<skip>-<asli>to<pair>-<#pass>p<px>px
			batchList = i_decorateNames(procList, seq, skipGlobal, numPasses, intAreas);
			[res, wasAborted] = pivanalyzemat.core.processBatchMat(batchList, cfg);
			if isempty(res)
				statusLabel.Text = 'Done (no results).';
			else
				nOK = sum(~strcmp({res.status}, 'GAGAL'));
				nGS = sum([res.n_gs_embedded]);
				nDt = sum([res.n_dt_valid]);
				nGeomOK = sum([res.geom_valid]);
				nDrop = sum([res.n_dropped]);
				if wasAborted
					statusLabel.Text = sprintf('Cancelled: %d/%d experiments processed.', numel(res), nTotal);
					uialert(fig, sprintf('Batch CANCELLED.\n\n%d of %d finished (%d succeeded).', ...
						numel(res), nTotal, nOK), 'Cancelled', 'Icon', 'warning');
				else
					updateProgress(1, 'Done.');
					uialert(fig, sprintf(['Step 2 batch finished.\n\n%d of %d experiments succeeded.\n' ...
						'• %d frames with a GS background\n• %d frames with dt timing (EXIF)\n' ...
						'• %d experiments with complete geometry\n• %d dead frames dropped in total\n\n' ...
						'Output → %s'], ...
						nOK, numel(res), nGS, nDt, nGeomOK, nDrop, outRoot), 'Done', 'Icon', 'success');
				end
			end
			refreshTable();
		catch ME
			statusLabel.Text = 'Failed.';
			uialert(fig, sprintf('An error occurred:\n\n%s', ME.message), 'Error');
		end
	end

	function onAbort()
		abortReq = true;
		abortBtn.Enable = 'off';
		statusLabel.Text = 'Cancelling... the running experiment is finished first.';
		drawnow;
	end

	function tf = checkAbort()
		drawnow; tf = abortReq;
	end

	function finishRun()
		setEnabled('on'); abortBtn.Enable = 'off'; drawnow;
	end

	function minFig()
		try fig.WindowState = 'minimized'; drawnow; catch; end
	end

	function restoreFig()
		try fig.WindowState = 'normal'; drawnow; figure(fig); catch; end
	end

	function setEnabled(state)
		ctrls = {runBtn, scanBtn, addBtn, addMultiBtn, removeBtn, clearBtn, parentBrowse, ...
			outBrowse, outClearBtn, parentField, seqDropdown, workersField, ...
			minField, recursiveCb, outField, gsQualField, dropFirstCb, reencodeCb, ...
			embedTimeCb, embedTableCb, x0Field, x1Field, lposField, applySelBtn, applyLposAllBtn, ...
			previewBtn, quickBtn, scanOrientDd, scanPosField, npassDd, skipField, ...
			saveProgBtn, loadProgBtn, ...
			iwF(1), iwF(2), iwF(3), iwF(4)};
		for k = 1:numel(ctrls); ctrls{k}.Enable = state; end
		% Tombol bergantung-root: jaga gerbang root walau state='on'.
		if strcmpi(state, 'on'); i_updateRootGated(); end
		drawnow;
	end

	function resetProgress()
		barFill.Position(3) = 1; pctLabel.Text = '0%'; drawnow;
	end

	function updateProgress(frac, msg)
		if ~isvalid(fig); return; end
		frac = max(0, min(1, frac));
		innerW = barBG.Position(3) - 4;
		barFill.Position(3) = max(1, frac * innerW);
		pctLabel.Text = sprintf('%.0f%%', frac * 100);
		if nargin > 1 && ~isempty(msg); statusLabel.Text = msg; end
		drawnow limitrate;
	end

	function appendLog(str)
		if ~isvalid(fig); return; end
		logLines{end+1} = char(string(str));
		if numel(logLines) > 500; logLines = logLines(end-499:end); end
		logArea.Value = logLines;
		try scroll(logArea, 'bottom'); catch; end
		drawnow limitrate;
	end

	% --------------------- pratinjau foto awal/akhir ----------------------
	function onPreview()
		if isempty(procList)
			uialert(fig, 'The list is still empty. Scan/add a .mat first.', 'No experiment yet'); return;
		end
		startIdx = 1;
		sr = selectedRows(selectedRows >= 1 & selectedRows <= numel(procList));
		if ~isempty(sr); startIdx = sr(1); end
		if isempty(pv.fig) || ~isvalid(pv.fig); pvBuild(); end
		try pv.fig.WindowState = 'maximized'; catch; end   % langsung maximize saat dibuka
		pv.idx = startIdx; pv.last = false;
		pvLoadExp(); pvRender();   % view & garis dipertahankan; gambar pertama auto-fit
		figure(pv.fig);
	end

	function pvBuild()
		pv.fig = uifigure('Name', 'Pratinjau Foto Awal/Akhir — isi X0 / X1 / L_pos langsung di sini', ...
			'Position', [120 40 900 860], 'AutoResizeChildren', 'off');
		% AutoResizeChildren WAJIB 'off' supaya SizeChangedFcn (pvLayout) jalan —
		% kalau 'on', MATLAB menskala anak proporsional saat maximize (foto jadi
		% tidak penuh / melenceng) dan pvLayout diabaikan diam-diam.
		pivui.forceLightTheme(pv.fig);   % paksa tema terang (satu sumber +pivui)
		pv.lines = {};
		pv.expLbl = uilabel(pv.fig, 'Position', [20 820 540 28], 'FontSize', 15, ...
			'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'Text', '');
		% Tombol tutup (kanan-atas) — tak perlu menekan silang paksa di pojok window.
		pv.closeSaveBtn = uibutton(pv.fig, 'Position', [566 818 160 30], ...
			'Text', '✔ Save & close', 'FontWeight', 'bold', ...
			'BackgroundColor', [0.82 0.93 0.82], ...
			'Tooltip', 'Write this row''s X0/X1/L_pos to the main table, then close the preview.', ...
			'ButtonPushedFcn', @(~,~) pvCloseSave());
		pv.closeNoSaveBtn = uibutton(pv.fig, 'Position', [730 818 150 30], ...
			'Text', '✕ Close without saving', 'FontWeight', 'bold', ...
			'BackgroundColor', [0.95 0.86 0.86], ...
			'Tooltip', 'Close the preview WITHOUT saving the row edits that are not committed yet.', ...
			'ButtonPushedFcn', @(~,~) pvCloseNoSave());
		pv.ax = uiaxes(pv.fig, 'Position', [20 300 860 510]);
		pv.ax.XTick = []; pv.ax.YTick = []; pv.ax.Box = 'on'; title(pv.ax, '');
		pv.ax.YDir = 'reverse'; pv.ax.DataAspectRatio = [1 1 1];
		colormap(pv.ax, gray(256));            % untuk frame 1-kanal (grayscale)
		try enableDefaultInteractivity(pv.ax); catch; end
		try axtoolbar(pv.ax, {'zoomin','zoomout','pan','restoreview'}); catch; end

		% --- Baris alat tampilan: zoom area / pan / reset + garis kosmetik ---
		uibutton(pv.fig, 'Position', [20 262 92 32], 'Text', '🔍 Zoom', ...
			'Tooltip', 'Drag a box on the image to magnify a specific area.', ...
			'ButtonPushedFcn', @(~,~) pvZoomMode());
		uibutton(pv.fig, 'Position', [116 262 84 32], 'Text', '✋ Pan', ...
			'Tooltip', 'Drag the image to move around while zoomed in.', ...
			'ButtonPushedFcn', @(~,~) pvPanMode());
		uibutton(pv.fig, 'Position', [204 262 116 32], 'Text', '↺ Reset zoom', ...
			'Tooltip', 'Back to the full view (reset zoom/pan).', ...
			'ButtonPushedFcn', @(~,~) pvResetView());
		uibutton(pv.fig, 'Position', [324 262 120 32], 'Text', '✏️ 2–3 point line', ...
			'Tooltip', ['Draw a guide line for observation — click 2–3 points (an L shape works), ' ...
			'double-click/Enter to finish. Cosmetic only (NOT an X0/X1/L_pos input). ' ...
			'It survives the first/last toggle AND switching experiments.'], ...
			'BackgroundColor', [0.96 0.93 0.86], 'ButtonPushedFcn', @(~,~) pvDrawLine());
		uibutton(pv.fig, 'Position', [448 262 118 32], 'Text', '⌐ L line', ...
			'Tooltip', ['Drop a ready-made L line (3 points) in the middle of the current view ' ...
			'— then drag its points wherever you need them.'], ...
			'BackgroundColor', [0.96 0.93 0.86], 'ButtonPushedFcn', @(~,~) pvSpawnL());
		uibutton(pv.fig, 'Position', [570 262 130 32], 'Text', '🧹 Clear all', ...
			'Tooltip', 'Delete ALL guide lines.', ...
			'ButtonPushedFcn', @(~,~) pvClearLines());
		% Geser SELURUH garis L (kalau seret dgn mouse sulit). Nudge 10 px.
		uibutton(pv.fig, 'Position', [706 262 40 32], 'Text', '◄', ...
			'Tooltip', 'Nudge the L line 10 px left', 'ButtonPushedFcn', @(~,~) pvNudgeL(-10, 0));
		uibutton(pv.fig, 'Position', [748 262 40 32], 'Text', '▲', ...
			'Tooltip', 'Nudge the L line 10 px up', 'ButtonPushedFcn', @(~,~) pvNudgeL(0, -10));
		uibutton(pv.fig, 'Position', [790 262 40 32], 'Text', '▼', ...
			'Tooltip', 'Nudge the L line 10 px down', 'ButtonPushedFcn', @(~,~) pvNudgeL(0, +10));
		uibutton(pv.fig, 'Position', [832 262 40 32], 'Text', '►', ...
			'Tooltip', 'Nudge the L line 10 px right', 'ButtonPushedFcn', @(~,~) pvNudgeL(+10, 0));

		pv.frLbl = uilabel(pv.fig, 'Position', [20 232 520 22], ...
			'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'FontSize', 13, 'Text', '');
		pv.lockBtn = uibutton(pv.fig, 'Position', [548 230 152 26], ...
			'Text', '🔓 Lock zoom', 'FontWeight', 'bold', ...
			'BackgroundColor', [0.92 0.92 0.86], ...
			'Tooltip', ['Lock the current zoom limits → they stay put across the first/last toggle, ' ...
			'switching experiment, or switching GS/RAW. Click again to unlock.'], ...
			'ButtonPushedFcn', @(~,~) pvToggleZoomLock());
		pv.gsBtn = uibutton(pv.fig, 'Position', [708 230 172 26], ...
			'Text', '🌗 View: GS', 'FontWeight', 'bold', ...
			'BackgroundColor', [0.88 0.90 0.95], ...
			'Tooltip', ['Swap the background: GS (grayscale CLAHE, light) ⇄ RAW (full photo). ' ...
			'If GS looks bad, go back to RAW.'], 'ButtonPushedFcn', @(~,~) pvToggleGS());
		pv.geomLbl = uilabel(pv.fig, 'Position', [20 206 860 24], ...
			'HorizontalAlignment', 'center', 'FontColor', [0.25 0.25 0.25], 'FontWeight', 'bold', 'Text', '');
		uilabel(pv.fig, 'Position', [20 182 860 20], 'FontAngle', 'italic', ...
			'FontColor', [0.35 0.35 0.35], 'HorizontalAlignment', 'center', ...
			'Text', 'Type a value (cm) then press Enter — or use the ∓0.05 buttons. Saved straight into the main list.');

		% --- Baris geometri: X0 / X1 (dgn ∓0,05) + L_pos ---
		uilabel(pv.fig, 'Position', [20 148 28 22], 'Text', 'X0:', 'FontWeight', 'bold');
		pv.x0Field = uieditfield(pv.fig, 'text', 'Position', [50 146 76 28], ...
			'Placeholder', 'cm', 'ValueChangedFcn', @(~,~) pvApplyFields());
		uibutton(pv.fig, 'Position', [128 146 48 28], 'Text', '−0,05', ...
			'Tooltip', 'X0 − 0.05 cm', 'ButtonPushedFcn', @(~,~) pvBumpX('X0', -0.05));
		uibutton(pv.fig, 'Position', [178 146 48 28], 'Text', '+0,05', ...
			'Tooltip', 'X0 + 0.05 cm', 'ButtonPushedFcn', @(~,~) pvBumpX('X0', +0.05));
		uibutton(pv.fig, 'Position', [128 112 48 28], 'Text', '−0,1', ...
			'Tooltip', 'X0 − 0.1 cm', 'ButtonPushedFcn', @(~,~) pvBumpX('X0', -0.1));
		uibutton(pv.fig, 'Position', [178 112 48 28], 'Text', '+0,1', ...
			'Tooltip', 'X0 + 0.1 cm', 'ButtonPushedFcn', @(~,~) pvBumpX('X0', +0.1));

		uilabel(pv.fig, 'Position', [246 148 28 22], 'Text', 'X1:', 'FontWeight', 'bold');
		pv.x1Field = uieditfield(pv.fig, 'text', 'Position', [276 146 76 28], ...
			'Placeholder', 'cm', 'ValueChangedFcn', @(~,~) pvApplyFields());
		uibutton(pv.fig, 'Position', [354 146 48 28], 'Text', '−0,05', ...
			'Tooltip', 'X1 − 0.05 cm', 'ButtonPushedFcn', @(~,~) pvBumpX('X1', -0.05));
		uibutton(pv.fig, 'Position', [404 146 48 28], 'Text', '+0,05', ...
			'Tooltip', 'X1 + 0.05 cm', 'ButtonPushedFcn', @(~,~) pvBumpX('X1', +0.05));
		uibutton(pv.fig, 'Position', [354 112 48 28], 'Text', '−0,1', ...
			'Tooltip', 'X1 − 0.1 cm', 'ButtonPushedFcn', @(~,~) pvBumpX('X1', -0.1));
		uibutton(pv.fig, 'Position', [404 112 48 28], 'Text', '+0,1', ...
			'Tooltip', 'X1 + 0.1 cm', 'ButtonPushedFcn', @(~,~) pvBumpX('X1', +0.1));

		uilabel(pv.fig, 'Position', [472 148 46 22], 'Text', 'L_pos:', 'FontWeight', 'bold');
		pv.lposField = uieditfield(pv.fig, 'text', 'Position', [520 146 76 28], ...
			'Placeholder', 'cm', 'ValueChangedFcn', @(~,~) pvApplyFields());
		% Tombol GABUNGAN (X0+X1+L_pos sekaligus → semua exp) menggantikan tombol
		% "L_pos → SEMUA" lama, di samping "Simpan ke tabel".
		uibutton(pv.fig, 'Position', [604 145 124 30], ...
			'Text', '📋 All three → ALL', 'FontWeight', 'bold', ...
			'BackgroundColor', [0.90 0.93 0.86], ...
			'Tooltip', ['Copy this row''s X0, X1 AND L_pos to EVERY experiment. ' ...
			'Empty values are skipped. Fine-tune each exp afterwards with the ∓ buttons.'], ...
			'ButtonPushedFcn', @(~,~) pvAllGeom());
		uibutton(pv.fig, 'Position', [736 145 144 30], 'Text', '💾 Save to table', ...
			'FontWeight', 'bold', 'BackgroundColor', [0.82 0.91 0.97], ...
			'Tooltip', 'Write this row''s X0/X1/L_pos into the main table now.', ...
			'ButtonPushedFcn', @(~,~) pvSave());

		% --- Tombol "→ semua exp" PER-FIELD, tepat di bawah tiap kotak input ---
		uibutton(pv.fig, 'Position', [20 112 104 28], 'Text', 'X0 → all exps', ...
			'BackgroundColor', [0.90 0.93 0.86], ...
			'Tooltip', 'Copy this row''s X0 value to EVERY experiment.', ...
			'ButtonPushedFcn', @(~,~) pvFieldAll('X0'));
		uibutton(pv.fig, 'Position', [246 112 104 28], 'Text', 'X1 → all exps', ...
			'BackgroundColor', [0.90 0.93 0.86], ...
			'Tooltip', 'Copy this row''s X1 value to EVERY experiment.', ...
			'ButtonPushedFcn', @(~,~) pvFieldAll('X1'));
		pv.lposAllBtn = uibutton(pv.fig, 'Position', [472 112 124 28], ...
			'Text', 'L_pos → all exps', 'BackgroundColor', [0.90 0.93 0.86], ...
			'Tooltip', 'Copy this row''s L_pos value to EVERY experiment.', ...
			'ButtonPushedFcn', @(~,~) pvLposAll());

		% --- Parameter Garis L (A-B-C): panjang A-B & sudut tumpul di B ---
		uilabel(pv.fig, 'Position', [20 74 52 22], 'Text', 'L line:', 'FontWeight', 'bold');
		uilabel(pv.fig, 'Position', [74 74 48 22], 'Text', 'A-B px:');
		pv.lenField = uieditfield(pv.fig, 'numeric', 'Position', [122 72 50 26], ...
			'Value', 300, 'Limits', [1 Inf], 'RoundFractionalValues', 'off', ...
			'Tooltip', 'Length A→B (px). B is 180° (straight down) from A.', ...
			'ValueChangedFcn', @(~,~) pvUpdateL());
		uibutton(pv.fig, 'Position', [174 72 40 26], 'Text', '−10', ...
			'Tooltip', 'A-B − 10 px', 'ButtonPushedFcn', @(~,~) pvBumpLen(-10));
		uibutton(pv.fig, 'Position', [216 72 40 26], 'Text', '+10', ...
			'Tooltip', 'A-B + 10 px', 'ButtonPushedFcn', @(~,~) pvBumpLen(+10));
		uilabel(pv.fig, 'Position', [264 74 46 22], 'Text', 'Angle°:');
		pv.angField = uieditfield(pv.fig, 'numeric', 'Position', [312 72 50 26], ...
			'Value', 220, ...
			'Tooltip', ['Angle A-B-C at point B (degrees); A & B stay put → C rotates. ' ...
			'Range 1–359; >359 is clamped to 359, <1 to 1.'], ...
			'ValueChangedFcn', @(~,~) pvSetAngle(pv.angField.Value));
		uibutton(pv.fig, 'Position', [364 72 40 26], 'Text', '−1°', ...
			'Tooltip', 'Angle − 1°', 'ButtonPushedFcn', @(~,~) pvBumpAngle(-1));
		uibutton(pv.fig, 'Position', [406 72 40 26], 'Text', '+1°', ...
			'Tooltip', 'Angle + 1°', 'ButtonPushedFcn', @(~,~) pvBumpAngle(+1));
		uilabel(pv.fig, 'Position', [454 74 432 22], 'FontAngle', 'italic', ...
			'FontColor', [0.4 0.4 0.4], ...
			'Text', 'The "⌐ L line" button spawns a line from these parameters.');

		pv.prevBtn = uibutton(pv.fig, 'Position', [20 24 200 40], ...
			'Text', '‹ Previous experiment', 'ButtonPushedFcn', @(~,~) pvStep(-1));
		pv.toggleBtn = uibutton(pv.fig, 'Position', [232 24 436 40], ...
			'Text', 'View LAST FRAME  ⇄', 'FontSize', 15, 'FontWeight', 'bold', ...
			'BackgroundColor', [0.84 0.91 0.97], 'ButtonPushedFcn', @(~,~) pvToggle());
		pv.nextBtn = uibutton(pv.fig, 'Position', [680 24 200 40], ...
			'Text', 'Next experiment ›', 'ButtonPushedFcn', @(~,~) pvStep(1));

		% Baris kontrol diankur di BAWAH (posisi tetap); hanya gambar + judul atas
		% yang melar mengisi ruang → enak saat jendela di-maximize.
		pv.fig.SizeChangedFcn = @(~,~) pvLayout();
		pvLayout();
	end

	function pvLayout()
		if isempty(pv.fig) || ~isvalid(pv.fig); return; end
		P = pv.fig.Position; W = P(3); H = P(4);
		axBottom = 300; topMargin = 50;          % ruang utk judul exp di atas
		axH = max(140, H - axBottom - topMargin);
		if ~isempty(pv.ax) && isvalid(pv.ax)
			pv.ax.Position = [20, axBottom, max(220, W - 40), axH];
		end
		% Tombol tutup diankur di kanan-atas; judul exp mengisi sisa ruang kiri.
		btnW = 160; btnW2 = 150; gap = 4; y = H - 42;
		if ~isempty(pv.closeNoSaveBtn) && isvalid(pv.closeNoSaveBtn)
			pv.closeNoSaveBtn.Position = [W - 20 - btnW2, y, btnW2, 30];
		end
		if ~isempty(pv.closeSaveBtn) && isvalid(pv.closeSaveBtn)
			pv.closeSaveBtn.Position = [W - 20 - btnW2 - gap - btnW, y, btnW, 30];
		end
		if ~isempty(pv.expLbl) && isvalid(pv.expLbl)
			lblW = max(220, (W - 20 - btnW2 - gap - btnW) - 40);
			pv.expLbl.Position = [20, H - 40, lblW, 28];
		end
		% Baris kontrol bawah: prev di kiri, next di kanan, toggle DI TENGAH
		% (ikut lebar window supaya tetap center saat di-maximize).
		if ~isempty(pv.prevBtn) && isvalid(pv.prevBtn)
			pv.prevBtn.Position = [20, 24, 200, 40];
		end
		if ~isempty(pv.nextBtn) && isvalid(pv.nextBtn)
			pv.nextBtn.Position = [max(240, W - 220), 24, 200, 40];
		end
		if ~isempty(pv.toggleBtn) && isvalid(pv.toggleBtn)
			tw = 436;
			pv.toggleBtn.Position = [max(232, (W - tw) / 2), 24, tw, 40];
		end
	end

	function pvLoadExp()
		% Pratinjau hanya butuh DUA frame (awal & akhir). Baca LANGSUNG dari blob
		% .mat tanpa membongkar seluruh eksperimen ke disk (hemat space & waktu).
		n = numel(procList);
		pv.imgA = []; pv.imgB = [];
		pv.imgAgs = []; pv.imgBgs = [];   % cache GS dibuang tiap ganti exp
		pv.firstPath = ''; pv.lastPath = ''; pv.nframes = 0;
		if n == 0; return; end
		if pv.idx < 1; pv.idx = 1; elseif pv.idx > n; pv.idx = n; end
		if ~isempty(pv.frLbl) && isvalid(pv.frLbl); pv.frLbl.Text = 'Loading the first/last frame from the .mat...'; drawnow; end
		% .mat besar bisa lama dibaca → tampilkan bilah tunggu modal supaya tidak
		% terasa "hang". Ditutup otomatis (onCleanup) walau terjadi error.
		dlg = [];
		try
			dlg = uiprogressdlg(pv.fig, 'Title', 'Loading preview', 'Indeterminate', 'on', ...
				'Message', sprintf('Membaca frame awal & akhir dari .mat (bisa lama untuk berkas besar)...\n\n%s', ...
				procList(pv.idx).relpath));
		catch; end
		closer = onCleanup(@() i_closeDlg(dlg));   %#ok<NASGU>
		drawnow;
		try
			% Baca frame awal+akhir dalam SATU load (hindari memuat seluruh blob
			% .mat ke RAM dua kali — penyebab pratinjau terasa sangat lambat).
			[pv.imgA, pv.imgB, nm1, nm2, nF] = ...
				pivanalyzemat.core.readMatFramePair(procList(pv.idx));
			pv.firstPath = nm1; pv.lastPath = nm2; pv.nframes = nF;
		catch ME
			pv.frLbl.Text = sprintf('Failed to load the frame: %s', ME.message); return;
		end
	end


	function pvRender()
		if isempty(pv.fig) || ~isvalid(pv.fig); return; end
		if numel(procList) == 0
			if ~isempty(pv.imh) && isvalid(pv.imh); delete(pv.imh); pv.imh = []; end
			cla(pv.ax); pvRefreshInfo(); return;
		end
		img = pvCurImg();
		% Toggle awal/akhir = swap CData GAMBAR YANG SAMA → zoom/pan & garis
		% kosmetik dipertahankan persis. Hanya ganti exp (resetNext) yg reset zoom.
		pvShowImg(img, pv.resetNext);
		pv.resetNext = false;
		pvRefreshInfo();
	end

	function img = pvCurImg()
		% Pilih citra yang ditampilkan: GS (CLAHE, ringan) atau RAW penuh, sesuai
		% pv.showGS dan frame awal/akhir. GS dihitung sekali lalu di-cache.
		if pv.last; raw = pv.imgB; else; raw = pv.imgA; end
		if ~pv.showGS || isempty(raw); img = raw; return; end
		if pv.last
			if isempty(pv.imgBgs); pv.imgBgs = i_safeGs(raw); end
			img = pv.imgBgs;
		else
			if isempty(pv.imgAgs); pv.imgAgs = i_safeGs(raw); end
			img = pv.imgAgs;
		end
	end

	function g = i_safeGs(raw)
		% GS on-the-fly; bila gagal, kembalikan RAW agar tetap tampil.
		g = raw;
		try g = pivanalyzemat.core.gsClahe(raw); catch; end
	end

	function pvToggleZoomLock()
		pv.zoomLock = ~pv.zoomLock;
		if pv.zoomLock
			% Rekam batas zoom SAAT INI sebagai patokan kunci.
			if ~isempty(pv.ax) && isvalid(pv.ax)
				pv.lockXLim = pv.ax.XLim; pv.lockYLim = pv.ax.YLim;
			end
			if ~isempty(pv.lockBtn) && isvalid(pv.lockBtn)
				pv.lockBtn.Text = '🔒 Zoom locked';
				pv.lockBtn.BackgroundColor = [0.86 0.93 0.82];
			end
		else
			if ~isempty(pv.lockBtn) && isvalid(pv.lockBtn)
				pv.lockBtn.Text = '🔓 Lock zoom';
				pv.lockBtn.BackgroundColor = [0.92 0.92 0.86];
			end
		end
	end

	function pvToggleGS()
		pv.showGS = ~pv.showGS;
		if ~isempty(pv.gsBtn) && isvalid(pv.gsBtn)
			if pv.showGS; pv.gsBtn.Text = '🌗 View: GS';
			else;         pv.gsBtn.Text = '🌗 View: RAW'; end
		end
		pvRender();   % zoom & garis dipertahankan (CData diswap)
	end

	function pvShowImg(img, resetView)
		if isempty(img)
			if ~isempty(pv.imh) && isvalid(pv.imh); delete(pv.imh); pv.imh = []; end
			cla(pv.ax);
			text(pv.ax, 0.5, 0.5, '(gambar tidak dapat dibaca / tidak ada)', ...
				'Units', 'normalized', 'HorizontalAlignment', 'center', ...
				'FontSize', 13, 'Color', [0.6 0 0]);
			pv.ax.XTick = []; pv.ax.YTick = []; pv.ax.XLim = [0 1]; pv.ax.YLim = [0 1];
			return;
		end
		if isempty(pv.imh) || ~isvalid(pv.imh)
			pv.imh = image(pv.ax, 'CData', img);
			pv.ax.YDir = 'reverse'; pv.ax.DataAspectRatio = [1 1 1];
			pv.ax.XTick = []; pv.ax.YTick = []; pv.ax.Box = 'on';
			resetView = true;
		else
			% Hanya tukar piksel — JANGAN reset zoom walau ukuran exp baru beda
			% (user minta zoom & garis L tetap saat pindah exp). Batas lama dibiarkan.
			pv.imh.CData = img;
		end
		if pv.zoomLock && ~isempty(pv.lockXLim)
			% Kunci aktif → paksa batas tersimpan, abaikan permintaan reset.
			pv.ax.XLim = pv.lockXLim; pv.ax.YLim = pv.lockYLim; return;
		end
		if resetView
			w = size(img, 2); h = size(img, 1);
			pv.ax.XLim = [0.5 w+0.5]; pv.ax.YLim = [0.5 h+0.5];
		end
	end

	function pvZoomMode()
		try pan(pv.ax, 'off'); catch; end
		try zoom(pv.ax, 'on');
		catch
			uialert(pv.fig, ['Interactive box-zoom mode is unavailable. Use the ' ...
				'magnifier icon in the toolbar at the top-right of the image, or scroll.'], ...
				'Zoom');
		end
	end

	function pvPanMode()
		try zoom(pv.ax, 'off'); catch; end
		try pan(pv.ax, 'on');
		catch
			uialert(pv.fig, ['Pan mode is unavailable. Use the hand icon in the toolbar ' ...
				'at the top-right of the image.'], 'Pan');
		end
	end

	function pvResetView()
		try zoom(pv.ax, 'off'); catch; end
		try pan(pv.ax, 'off'); catch; end
		wasLock = pv.zoomLock; pv.zoomLock = false;   % izinkan reset walau terkunci
		pvShowImg(pvCurImg(), true);                  % kembali ke tampilan penuh
		if wasLock                                     % kalau tadi terkunci, kunci ulang
			pv.zoomLock = true;
			if ~isempty(pv.ax) && isvalid(pv.ax)
				pv.lockXLim = pv.ax.XLim; pv.lockYLim = pv.ax.YLim;
			end
		end
	end

	function pvDrawLine()
		if isempty(pv.imh) || ~isvalid(pv.imh)
			uialert(pv.fig, 'There is no image to draw on yet.', 'No image'); return;
		end
		try zoom(pv.ax, 'off'); catch; end
		try pan(pv.ax, 'off'); catch; end
		try
			% Polyline MAKS 3 titik → cukup untuk bentuk L. Klik 2 atau 3 titik,
			% lalu klik-ganda / Enter untuk selesai. Jika lebih dari 3 → dipangkas.
			h = drawpolyline(pv.ax, 'Color', [0.95 0.15 0.15], 'LineWidth', 1.5);
			if isempty(h) || ~isvalid(h); return; end
			if size(h.Position, 1) > 3; h.Position = h.Position(1:3, :); end
			if size(h.Position, 1) < 2; delete(h); return; end   % garis perlu >=2 titik
			pv.lines{end+1} = h;
		catch ME
			uialert(pv.fig, sprintf('Failed to draw the line: %s', ME.message), 'Line');
		end
	end

	function pts = pvLPoints(A)
		% Geometri garis L 3-titik A-B-C dari parameter (panjang A-B & sudut di B).
		%   A = titik atas (acuan).
		%   B = A + (0, +Lab)         → 180° lurus KE BAWAH dari A (y-layar +ke bawah).
		%   C = B + Lab*(sinθ, -cosθ) → sudut A-B-C = θ di titik B (θ>90° = tumpul).
		%       θ=90°→C lurus ke kanan (siku); θ=135°→kanan-bawah; θ=180°→lurus bawah.
		Lab = 300; th = 220;
		if ~isempty(pv.lenField) && isvalid(pv.lenField); Lab = max(1, pv.lenField.Value); end
		if ~isempty(pv.angField) && isvalid(pv.angField); th  = pv.angField.Value; end
		thr = th * pi / 180;
		B = A + [0, Lab];
		C = B + Lab * [sin(thr), -cos(thr)];
		pts = [A; B; C];
	end

	function pvSpawnL()
		% Munculkan garis L parametrik (A-B-C) di TENGAH tampilan sekarang.
		% Titik A diletakkan agak ke atas agar L (turun lalu menyudut) muat di layar.
		if isempty(pv.imh) || ~isvalid(pv.imh)
			uialert(pv.fig, 'There is no image to draw on yet.', 'No image'); return;
		end
		try zoom(pv.ax, 'off'); catch; end
		try pan(pv.ax, 'off'); catch; end
		xl = pv.ax.XLim; yl = pv.ax.YLim;
		A = [xl(1) + 0.42 * diff(xl), yl(1) + 0.30 * diff(yl)];   % titik atas
		pts = pvLPoints(A);
		try
			roi = images.roi.Polyline(pv.ax, 'Position', pts, ...
				'Color', [0.95 0.15 0.15], 'LineWidth', 1.5);
			pv.lShape = roi;          % L "aktif" → param berikutnya mengubah ini
			pv.lines{end+1} = roi;    % ikut terhapus oleh "Hapus semua"
		catch ME
			uialert(pv.fig, sprintf('Failed to create the L line: %s', ME.message), 'L line');
		end
	end

	function pvUpdateL()
		% Param diubah → perbarui garis L aktif (jika ada & masih hidup), titik A
		% (vertex pertama, bisa sudah digeser user) DIPERTAHANKAN sebagai acuan.
		if isempty(pv.lShape) || ~isvalid(pv.lShape); return; end
		P = pv.lShape.Position;
		if isempty(P); return; end
		A = P(1, :);
		pv.lShape.Position = pvLPoints(A);
	end

	function pvSetAngle(v)
		% Clamp ke [1,359] TANPA crash (mentokin), lalu perbarui garis L.
		if isempty(pv.angField) || ~isvalid(pv.angField); return; end
		if isempty(v) || ~isfinite(v); v = pv.angField.Value; end
		nv = min(359, max(1, v));
		pv.angField.Value = nv;
		pvUpdateL();
	end

	function pvBumpAngle(d)
		if isempty(pv.angField) || ~isvalid(pv.angField); return; end
		pvSetAngle(pv.angField.Value + d);
	end

	function pvBumpLen(d)
		% Ubah panjang A-B (px), minimal 1, lalu perbarui garis L aktif.
		if isempty(pv.lenField) || ~isvalid(pv.lenField); return; end
		pv.lenField.Value = max(1, pv.lenField.Value + d);
		pvUpdateL();
	end

	function pvNudgeL(dx, dy)
		% Geser SELURUH garis L aktif sebesar (dx,dy) px (koordinat gambar:
		% x→kanan, y→bawah). Berguna bila menyeret dgn mouse terasa sulit.
		if isempty(pv.lShape) || ~isvalid(pv.lShape)
			uialert(pv.fig, 'There is no L line yet. Press "⌐ L line" first.', 'L line'); return;
		end
		P = pv.lShape.Position;
		if isempty(P); return; end
		pv.lShape.Position = P + [dx, dy];
	end

	function pvClearLines()
		if ~iscell(pv.lines); pv.lines = {}; return; end
		for k = 1:numel(pv.lines)
			try if isvalid(pv.lines{k}); delete(pv.lines{k}); end; catch; end
		end
		pv.lines = {};
	end

	function pvBumpX(field, d)
		n = numel(procList);
		if n == 0 || pv.idx < 1 || pv.idx > n; return; end
		if strcmp(field, 'X0'); cur = parseField(pv.x0Field.Value);
		else;                   cur = parseField(pv.x1Field.Value); end
		if isnan(cur); cur = 0; end
		nv = round(cur + d, 4);   % buang derau pecahan biner (mis. 0,15000001)
		s  = num2str(nv, '%g');
		if strcmp(field, 'X0'); pv.x0Field.Value = s; else; pv.x1Field.Value = s; end
		pvApplyFields();
		pvRefreshInfo();
	end

	function pvRefreshInfo()
		if isempty(pv.fig) || ~isvalid(pv.fig); return; end
		n = numel(procList);
		if n == 0
			pv.expLbl.Text = '(list is empty)'; pv.frLbl.Text = ''; pv.geomLbl.Text = '';
			pv.x0Field.Value = ''; pv.x1Field.Value = ''; pv.lposField.Value = ''; return;
		end
		if pv.idx < 1; pv.idx = 1; elseif pv.idx > n; pv.idx = n; end
		e = procList(pv.idx);
		pv.expLbl.Text = sprintf('Experiment %d / %d   —   %s', pv.idx, n, e.relpath);
		if pv.last
			pv.frLbl.Text = sprintf('LAST FRAME  (#%d):   %s', pv.nframes, pv_leaf(pv.lastPath));
			pv.toggleBtn.Text = '⇄  Back to FIRST FRAME (1)';
		else
			pv.frLbl.Text = sprintf('FIRST FRAME  (#1):   %s', pv_leaf(pv.firstPath));
			pv.toggleBtn.Text = 'View LAST FRAME  ⇄';
		end
		pv.x0Field.Value   = num2disp(e.X0);
		pv.x1Field.Value   = num2disp(e.X1);
		pv.lposField.Value = num2disp(e.Lpos);
		if pv.last
			pv.x1Field.BackgroundColor = [1 1 0.78]; pv.x0Field.BackgroundColor = [1 1 1];
		else
			pv.x0Field.BackgroundColor = [1 1 0.78]; pv.x1Field.BackgroundColor = [1 1 1];
		end
		[stxt, scat] = pivanalyze.geom.strainText(e.X0, e.X1, e.Lpos);
		pv.geomLbl.Text = pvGeomStr(e, stxt);
		switch scat
			case 'lengthening'; pv.geomLbl.FontColor = [0.00 0.45 0.00];
			case 'shortening';  pv.geomLbl.FontColor = [0.80 0.45 0.00];
			case 'badL0';       pv.geomLbl.FontColor = [0.70 0.00 0.00];
			otherwise;          pv.geomLbl.FontColor = [0.25 0.25 0.25];
		end
	end

	function pvApplyFields()
		n = numel(procList);
		if n == 0 || pv.idx < 1 || pv.idx > n; return; end
		procList(pv.idx).X0   = parseField(pv.x0Field.Value);
		procList(pv.idx).X1   = parseField(pv.x1Field.Value);
		procList(pv.idx).Lpos = parseField(pv.lposField.Value);
		refreshTable();
	end

	function pvSave()
		% Tulis X0/X1/L_pos yang sedang tampil ke tabel utama + beri konfirmasi.
		n = numel(procList);
		if n == 0 || pv.idx < 1 || pv.idx > n
			uialert(pv.fig, 'There is no active experiment to save.', 'Empty'); return;
		end
		pvApplyFields();          % transfer ke procList + refreshTable
		pvRefreshInfo();          % rapikan tampilan field & strain
		e = procList(pv.idx);
		msg = sprintf('Tersimpan ke tabel — exp %d/%d: X0=%s  X1=%s  L_pos=%s', ...
			pv.idx, n, num2disp(e.X0), num2disp(e.X1), num2disp(e.Lpos));
		appendLog(msg);
		if ~isempty(pv.frLbl) && isvalid(pv.frLbl)
			pv.frLbl.Text = ['✔ ' msg]; drawnow;
			t = timer('StartDelay', 1.6, 'TimerFcn', @(tm,~) i_restoreFr(tm));
			start(t);
		end
	end

	function i_restoreFr(tm)
		try stop(tm); delete(tm); catch; end
		try
			if ~isempty(pv.fig) && isvalid(pv.fig) && ~isempty(pv.frLbl) && isvalid(pv.frLbl)
				pvRefreshInfo();   % kembalikan teks frame sesuai keadaan
			end
		catch; end
	end

	function pvFieldAll(field)
		% Salin nilai SATU field (X0 atau X1) baris ini ke SEMUA eksperimen.
		switch field
			case 'X0'; v = parseField(pv.x0Field.Value);
			case 'X1'; v = parseField(pv.x1Field.Value);
			otherwise; return;
		end
		if isnan(v)
			uialert(pv.fig, sprintf('Fill in the %s value (cm) first.', field), [field ' empty']); return;
		end
		if isempty(procList); return; end
		for r = 1:numel(procList); procList(r).(field) = v; end
		refreshTable(); pvRefreshInfo();
		appendLog(sprintf('%s = %.4g cm applied to ALL %d experiments (from the preview).', ...
			field, v, numel(procList)));
	end

	function pvLposAll()
		vL = parseField(pv.lposField.Value);
		if isnan(vL); uialert(pv.fig, 'Fill in the L_pos value (cm) first.', 'L_pos empty'); return; end
		if isempty(procList); return; end
		for r = 1:numel(procList); procList(r).Lpos = vL; end
		refreshTable();
		appendLog(sprintf('L_pos = %.4g cm applied to ALL %d experiments (from the preview).', ...
			vL, numel(procList)));
	end

	function pvAllGeom()
		% Salin X0, X1, L_pos baris ini ke SEMUA eksperimen sekaligus. Nilai yang
		% KOSONG (NaN) dilewati agar tak menimpa data yang sudah ada dgn kosong.
		if isempty(procList); return; end
		v0 = parseField(pv.x0Field.Value);
		v1 = parseField(pv.x1Field.Value);
		vL = parseField(pv.lposField.Value);
		if isnan(v0) && isnan(v1) && isnan(vL)
			uialert(pv.fig, 'Fill in at least one of X0 / X1 / L_pos first.', 'Empty'); return;
		end
		for r = 1:numel(procList)
			if ~isnan(v0); procList(r).X0   = v0; end
			if ~isnan(v1); procList(r).X1   = v1; end
			if ~isnan(vL); procList(r).Lpos = vL; end
		end
		refreshTable(); pvRefreshInfo();
		appendLog(sprintf(['X0/X1/L_pos = [%s / %s / %s] cm copied to ALL %d ' ...
			'experiments (from the preview).'], num2disp(v0), num2disp(v1), num2disp(vL), ...
			numel(procList)));
	end

	function pvToggle()
		pv.last = ~pv.last; pvRender();
	end

	function pvCloseSave()
		% Commit X0/X1/L_pos baris ini ke tabel utama, lalu tutup jendela pratinjau.
		pvApplyFields();
		appendLog('Preview closed (changes saved to the table).');
		i_closePvFig();
	end

	function pvCloseNoSave()
		% Tutup TANPA commit editan baris yang belum tersimpan (yang sudah ter-Enter
		% / pindah exp tetap di tabel — itu memang sudah tersimpan sebelumnya).
		appendLog('Preview closed without saving the last row edits.');
		i_closePvFig();
	end

	function i_closePvFig()
		try if ~isempty(pv.fig) && isvalid(pv.fig); delete(pv.fig); end; catch; end
		pv.fig = [];
	end

	function pvStep(d)
		n = numel(procList);
		if n == 0; return; end
		pvApplyFields();   % commit X0/X1/L_pos baris ini ke tabel SEBELUM pindah exp
		pv.idx = mod(pv.idx - 1 + d, n) + 1;   % pv.last DIPERTAHANKAN: kalau lagi lihat
		                                       % frame akhir, exp baru jg tampil akhir.
		% Pindah exp: zoom & garis SENGAJA dipertahankan.
		pvLoadExp(); pvRender();
	end

	function pvSyncGeom()
		if isempty(pv.fig) || ~isvalid(pv.fig); return; end
		pvRefreshInfo();
	end

	function onClose()
		% Tanya simpan dulu (bila ada yg bisa disimpan). Ya → simpan + tutup;
		% Tidak → tutup segera; Batal → jangan tutup.
		if i_haveRoot() && ~isempty(procList)
			sel = uiconfirm(fig, 'Save the progress before closing GRAIN2?', 'Close GRAIN2', ...
				'Options', {'Save & close', 'Close without saving', 'Cancel'}, ...
				'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');
			switch sel
				case 'Save & close';        i_saveProgressSilent();
				case 'Close without saving' % langsung tutup
				otherwise;                  return;   % Batal → batalkan penutupan
			end
		end
		i_finalizeClose();
	end

	function onBackToGRAIN0()
		% "Eksperimen baru": tawarkan simpan progres dulu (seperti onClose),
		% lalu tutup GRAIN2 dan buka GRAIN0 dgn root saat ini sbg titik awal.
		if i_haveRoot() && ~isempty(procList)
			sel = uiconfirm(fig, ['Save the GRAIN2 progress before starting a ', ...
				'new experiment (back to GRAIN0)?'], 'New experiment → GRAIN0', ...
				'Options', {'Save & continue', 'Continue without saving', 'Cancel'}, ...
				'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');
			switch sel
				case 'Save & continue';      i_saveProgressSilent();
				case 'Continue without saving' % langsung lanjut
				otherwise;                   return;   % Batal
			end
		end
		% Buka GRAIN0 KOSONG (tanpa root) supaya sesi eksperimen baru bersih —
		% tak ada daftar/pemindaian dari eksperimen sebelumnya yang terbawa.
		i_finalizeClose();
		try
			GRAIN0();
		catch ME
			uialert(uifigure('Name', 'GRAIN0'), ...
				sprintf('Failed to open GRAIN0:\n%s', ME.message), 'Error');
		end
	end

	function i_finalizeClose()
		try if ~isempty(pv.fig) && isvalid(pv.fig); delete(pv.fig); end; catch; end
		% Bersihkan SEMUA bongkaran temporer: QPIV exp aktif + folder kerja
		% (.grainsa2_unpack_<hash> di bawah root) + tempdir sesi. Tak ada artefak
		% tertinggal — dump benar-benar temporer.
		try i_qpivCleanupTmp(); catch; end
		try
			ur = i_unpackRoot();
			if ~isempty(ur) && isfolder(ur); rmdir(ur, 's'); end
		catch; end
		try pivanalyzemat.core.cleanupTmp(); catch; end
		delete(fig);
	end
end

%% ========================= SUBFUNGSI (lokal) =====================
function e = i_findProg(allProg, expdir, pabSrc)
% Cari entry progres: key .mat dulu, lalu folder RAW asli (pab_src) sbg
% jembatan QPIV Step 0 -> Step 2. pabSrc kosong/absen -> perilaku lama.
if nargin < 3; pabSrc = ''; end
e = [];
if isempty(allProg); return; end
key = PIVlab_automasi_progress('key', expdir);
idx = find(strcmp({allProg.key}, key), 1);
if isempty(idx) && ~isempty(pabSrc)
	key2 = PIVlab_automasi_progress('key', pabSrc);
	idx  = find(strcmp({allProg.key}, key2), 1);
end
if ~isempty(idx); e = allProg(idx); end
end

function tag = i_dateTag()   % forwarder -> pivanalyzemat.core (satu sumber kontrak)
tag = pivanalyzemat.core.dateTag();
end


function s = i_modeLabel(seq)
%I_MODELABEL  Label mode pasangan (istilah literatur PIV):
%   'consecutive' -> 'overlap'     (overlapping pairs: 1-2, 2-3, ...)
%   'pairs'       -> 'non-overlap' (non-overlapping pairs: 1-2, 3-4, ...)
if strcmpi(seq, 'pairs'); s = 'non-overlap'; else; s = 'overlap'; end
end

function s = num2disp(v)
if isempty(v) || ~isnumeric(v) || isnan(v); s = ''; else; s = num2str(v, '%g'); end
end

function [spp, cpp] = i_perPair(X0, X1, Lpos, np)
% Spasi antar-frame untuk uji keseragaman langkah antar-eksperimen:
%   cpp = perpindahan dinding per pasangan (cm/#pair) = dL / #pair
%   spp = strain persen per pasangan (strain%/#pair) = strainPct / #pair
% dL & strainPct memakai definisi SAMA dgn kolom Strain% (pivanalyze.geom).
% Kembalikan '' bila tak terhitung (geometri belum lengkap / #pair ≤ 0).
spp = ''; cpp = '';
if isempty(np) || ~isnumeric(np) || isnan(np) || np <= 0; return; end
if isnan(X0) || isnan(X1); return; end
dL = X0 - X1;                               % = (Lpos-X1) - (Lpos-X0), cm
cpp = sprintf('%+.4g', dL / np);
if ~isnan(Lpos)
	L0 = Lpos - X0;
	if L0 > 0; spp = sprintf('%+.4g', (dL / L0 * 100) / np); end
end
end

function v = parseCell(x)
if isnumeric(x)
	if isempty(x); v = NaN; else; v = double(x(1)); end
	return;
end
v = parseField(x);
end

function v = parseField(x)
s = strtrim(char(string(x)));
if isempty(s); v = NaN; return; end
v = str2double(s);
end

% --------- helper CSV geometri (X0/X1/L_pos) ---------
function s = i_numToCsv(v)
% Angka -> string CSV; NaN/kosong jadi sel kosong.
if isempty(v) || all(isnan(double(v))); s = ""; return; end
s = string(num2str(double(v(1)), '%.6g'));
end

function v = i_csvToNum(x)
% Sel CSV (string/numeric/kosong) -> double; kosong jadi NaN.
if isnumeric(x)
	if isempty(x); v = NaN; else; v = double(x(1)); end
	return;
end
s = strtrim(char(string(x)));
if isempty(s) || strcmpi(s, "NaN"); v = NaN; return; end
v = str2double(s);
end

function k = i_normName(s)
% Normalisasi nama eksperimen untuk pencocokan: buang .mat, trim, lowercase.
k = lower(strtrim(erase(string(s), ".mat")));
end

% (strainText lokal DIHAPUS — kini pakai pivanalyze.geom.strainText, satu sumber)

%% ------------------- subfungsi pratinjau foto awal/akhir -----------------
function nm = pv_leaf(p)
if isempty(p); nm = ''; return; end
[~, b, e] = fileparts(p); nm = [b e];
end

function s = pv_numlabel(v)
if isempty(v) || ~isnumeric(v) || isnan(v); s = '—'; else; s = num2str(v, '%g'); end
end

function s = pvGeomStr(e, stxt)
if isempty(e.X0) || isempty(e.X1) || isempty(e.Lpos) || isnan(e.X0) || isnan(e.X1) || isnan(e.Lpos)
	s = sprintf('X0 = %s    |    X1 = %s    |    L_pos = %s    (cm)   —   lengkapi untuk hitung strain', ...
		pv_numlabel(e.X0), pv_numlabel(e.X1), pv_numlabel(e.Lpos));
	return;
end
L0 = e.Lpos - e.X0; L1 = e.Lpos - e.X1; dL = L1 - L0;
if isempty(stxt); strpart = '—'; else; strpart = [stxt '%']; end
s = sprintf('L0 = %.3g cm    |    L1 = %.3g cm    |    dL = %+.3g cm    |    Strain = %s', ...
	L0, L1, dL, strpart);
end
