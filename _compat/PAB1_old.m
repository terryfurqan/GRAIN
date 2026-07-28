function PAB1_old(progressPath)
%GRAIN1_OLD  GUI BatchPIVPrep2 (PPB2) PENUH — produksi .mat (kini "Step 2").
%
%   PAB1_old                 % luncurkan GUI kosong
%   PAB1_old(progressPath)   % luncurkan + AUTO-LOAD progress .mat (mis. dari
%                            % GRAIN1 (ROI jitter): daftar exp + anchor termuat)
%
%   CATATAN RENAME (2026-06-25): dulu bernama GRAIN1. Karena tool ROI jitter
%   (dulu GRAIN0_old) kini jadi GRAIN1 ("true Step 1"), GUI BatchPIVPrep2 ini
%   turun nama jadi PAB1_old (langkah produksi .mat sesudah ROI jitter).
%
%   Ia meluncurkan langsung
%   GUI BatchPIVPrep2 (PPB2) yang sudah matang & lengkap — semua fungsi dasar
%   ada di sana:
%     * Tabel "Folders to Process" (Add Folder / Add Subfolders rekursif /
%       Remove / Clear) + kolom Anchor & Crop per folder.
%     * Tab "Stabilization Anchor" : preset anchor (New/Load/Save), metode
%       SURF/PhaseCorr, jitter tol, Assign ke SELECTED/ALL, View/Draw/Edit
%       on Frame 1.
%     * Tab "Cropping ROI" : Mode 1 rectangle / Mode 2 polygon-squaring,
%       preset (New/Load/Save), Assign ke SELECTED/ALL, View/Draw/Edit.
%     * Output Settings : suffix, RAW format/quality, GS scale/quality,
%       lokasi output, dan **"Kemas tiap eksperimen -> 1 .mat"**
%       (pivprep_single_v1) — INI yang menjamin output single .mat.
%     * Quick PIV / Bersihkan (WQPIV) untuk menandai & buang frame mati.
%     * Save / Load / Save As Progress (.mat).
%
%   AUTO-LOAD PROGRESS (argumen progressPath): bila diberi path berkas progress
%   BatchPIVPrep2 (variabel 'progress'), Step 1 langsung memuatnya setelah GUI
%   siap — ini jalur "Buka di Step 1" dari PAB_step_0. Pemuatan memakai
%   API PUBLIK paket (refreshFolderTable + displayInAxes), jadi paket bersama
%   +batchpivprep2 TIDAK perlu diubah.
%
%   Semua paket (+pivprep, +batchpivprep2, lib/) sudah di-addpath oleh
%   grain_setup. SELALU MATLAB R2025b.

roots = grain_setup(); %#ok<NASGU>

% Pastikan komponen PPB2 tersedia (sudah disalin ke GRAIN_SA/+batchpivprep2).
if isempty(which('batchpivprep2.ui.buildGUI'))
	error('PAB1_old:noPPB2', ...
		'Komponen BatchPIVPrep2 (+batchpivprep2/+ui/buildGUI) tidak ditemukan di path.');
end

% Aktifkan opsi single .mat secara default kalau pengguna lupa: PPB2 sudah
% mengatur cbPackMat=1 by default di buildGUI, jadi cukup luncurkan.
appdata = batchpivprep2.ui.buildGUI();
guidata(appdata.fig, appdata);
batchpivprep2.ui.installCallbacks(appdata.fig);

% Paksa centang "Kemas -> 1 .mat" (output single .mat = tujuan Step 1).
try
	if isfield(appdata, 'cbPackMat'); set(appdata.cbPackMat, 'Value', 1); end
catch
end

% Auto-load progress bila path diberikan (jalur dari PAB_step_0).
if nargin >= 1 && ~isempty(progressPath)
	i_autoLoadProgress(appdata.fig, progressPath);
end

fprintf(['[PAB1_old] GUI BatchPIVPrep2 siap. Tambah folder foto mentah, ' ...
	'set anchor + crop ROI, pastikan "Kemas -> 1 .mat" tercentang, lalu Run.\n']);
end


% =====================================================================
function i_autoLoadProgress(fig, pathIn)
%I_AUTOLOADPROGRESS  Muat progress BatchPIVPrep2 ke GUI lewat API PUBLIK.
%   Memulihkan state inti (folders + anchor + setelan jitter/metode) lalu
%   me-refresh tabel & preview. Tidak menyentuh paket bersama +batchpivprep2.
	if ~ischar(pathIn) && ~isstring(pathIn), return; end
	pathIn = char(pathIn);
	if exist(pathIn,'file') ~= 2
		warning('PAB1_old:noProgress','Berkas progress tak ditemukan: %s', pathIn);
		return;
	end
	try
		S = load(pathIn);
	catch ME
		warning('PAB1_old:loadFail','Gagal memuat progress: %s', ME.message);
		return;
	end
	if ~isfield(S,'progress') || ~isstruct(S.progress) || ~isfield(S.progress,'folders')
		warning('PAB1_old:badProgress','Berkas bukan progress BatchPIVPrep2 valid: %s', pathIn);
		return;
	end
	prog = S.progress;

	h = guidata(fig);
	h.folders      = i_normFolders(i_field(prog,'folders',[]));
	h.activeAnchor = i_field(prog,'activeAnchor',[]);
	h.activeCrop   = i_field(prog,'activeCrop',[]);
	h.cropMode     = i_field(prog,'cropMode','crop');
	h.marginEnabled= i_field(prog,'marginEnabled',true);
	h.marginPx     = i_field(prog,'marginPx',10);
	h.outputRoot   = i_field(prog,'outputRoot','');
	h.progressFile = pathIn;
	guidata(fig, h);

	% Setelan kontrol (best-effort, hanya yang relevan).
	if isfield(prog,'settings') && isstruct(prog.settings)
		s = prog.settings;
		i_setIf(h,'edJitter','String',s,'jitterTol');
		i_setIf(h,'popStabMethod','Value',s,'stabMethodVal');
		i_setIf(h,'edSuffix','String',s,'suffix');
	end

	% Refresh tampilan via API PUBLIK paket.
	try, batchpivprep2.ui.refreshFolderTable(fig); catch, end
	try
		batchpivprep2.io.anchorPreset.displayInAxes(h.activeAnchor, h.axPreview);
		set(h.txtAnchorInfo,'String', batchpivprep2.io.anchorPreset.summaryText(h.activeAnchor));
	catch
	end
	try
		if ~isempty(h.outputRoot)
			rootStr = h.outputRoot;
			if numel(rootStr) > 64, rootStr = ['...' rootStr(end-61:end)]; end
			set(h.txtRoot,'String',rootStr);
		end
	catch
	end
	try
		[~, nm, ext] = fileparts(pathIn);
		set(h.txtProgressFile,'String', sprintf('Progress: %s%s', nm, ext));
	catch
	end
	fprintf('[PAB1_old] Progress dimuat: %s (%d folder).\n', pathIn, numel(h.folders));
end


function folders = i_normFolders(folders)
%I_NORMFOLDERS  Pastikan struct folder punya field skema v2 (mirip paket).
	need = {'path','files','nImg','outName','seqMode','seqStep', ...
	        'anchor','anchorName','crop','cropName'};
	if ~isstruct(folders) || isempty(folders)
		args = [need; repmat({{}},1,numel(need))];
		folders = struct(args{:});
		return;
	end
	for k = 1:numel(need)
		if ~isfield(folders, need{k}); [folders.(need{k})] = deal([]); end
	end
	for i = 1:numel(folders)
		if isempty(folders(i).seqMode); folders(i).seqMode = 'consecutive'; end
		if isempty(folders(i).seqStep); folders(i).seqStep = 1; end
	end
end


function v = i_field(s, f, def)
	if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
end


function i_setIf(h, handleField, prop, s, srcField)
	if isfield(h, handleField) && ishghandle(h.(handleField)) ...
			&& isfield(s, srcField) && ~isempty(s.(srcField))
		try, set(h.(handleField), prop, s.(srcField)); catch, end
	end
end
