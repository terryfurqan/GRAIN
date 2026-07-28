function installCallbacks(fig)
%INSTALLCALLBACKS  Pasang semua callback untuk jendela BatchPIVPrep2.
%
%   batchpivprep2.ui.installCallbacks(fig)

    h = guidata(fig);

    % Flag stop (dipakai bersama via appdata).
    setappdata(fig, 'stopRequested', false);
    setappdata(fig, 'isRunning',     false);

    % Folder list
    set(h.btnAddFolder,    'Callback', @(s,e) local_onAddFolder(fig, false));
    set(h.btnAddRecursive, 'Callback', @(s,e) local_onAddFolder(fig, true));
    set(h.btnRemoveFolder, 'Callback', @(s,e) local_onRemove(fig));
    set(h.btnClearFolders, 'Callback', @(s,e) local_onClear(fig));
    set(h.tblFolders,      'CellSelectionCallback', @(s,e) local_onTableSelect(fig, e));
    set(h.tblFolders,      'CellEditCallback',      @(s,e) local_onTableEdit(fig, e));
    if isfield(h, 'btnQpiv')
        set(h.btnQpiv,     'Callback', @(s,e) local_onQpiv(fig));
    end

    % Anchor (stabilisasi)
    set(h.btnNewAnchor,   'Callback', @(s,e) local_onNewAnchor(fig));
    set(h.btnLoadAnchor,  'Callback', @(s,e) local_onLoadAnchor(fig));
    set(h.btnSaveAnchor,  'Callback', @(s,e) local_onSaveAnchor(fig));
    set(h.btnAssignSel,   'Callback', @(s,e) local_onAssign(fig, false));
    set(h.btnAssignAll,   'Callback', @(s,e) local_onAssign(fig, true));
    set(h.btnCheckAnchor, 'Callback', @(s,e) local_onCheckAnchor(fig));

    % Crop (cropping ROI)
    set(h.popCropMode,      'Callback', @(s,e) local_onCropModeChange(fig));
    set(h.btnNewCrop,       'Callback', @(s,e) local_onNewCrop(fig));
    set(h.btnLoadCrop,      'Callback', @(s,e) local_onLoadCrop(fig));
    set(h.btnSaveCrop,      'Callback', @(s,e) local_onSaveCrop(fig));
    set(h.btnAssignCropSel, 'Callback', @(s,e) local_onAssignCrop(fig, false));
    set(h.btnAssignCropAll, 'Callback', @(s,e) local_onAssignCrop(fig, true));
    set(h.btnViewCrop,      'Callback', @(s,e) local_onViewCrop(fig));
    if isfield(h, 'btnNoCropSel')
        set(h.btnNoCropSel, 'Callback', @(s,e) local_onAssignNoCrop(fig, false));
    end
    if isfield(h, 'btnNoCropAll')
        set(h.btnNoCropAll, 'Callback', @(s,e) local_onAssignNoCrop(fig, true));
    end

    % Output
    set(h.edSuffix,    'Callback', @(s,e) local_onSuffixChange(fig));
    set(h.btnPickRoot, 'Callback', @(s,e) local_onPickRoot(fig));

    % Run / Stop
    set(h.btnRun,  'Callback', @(s,e) local_onRun(fig));
    set(h.btnStop, 'Callback', @(s,e) local_onStop(fig));

    % Session / Progress (.mat): Save / Load / Save As
    set(h.btnSaveProgress,   'Callback', @(s,e) local_onSaveProgress(fig));
    set(h.btnLoadProgress,   'Callback', @(s,e) local_onLoadProgress(fig));
    set(h.btnSaveAsProgress, 'Callback', @(s,e) local_onSaveAsProgress(fig));

    % Resize/maximize: jaga konten menempel ke kiri-atas.
    set(fig, 'SizeChangedFcn', @(s,e) local_onFigResize(fig));

    batchpivprep2.ui.refreshFolderTable(fig);
end


% =====================================================================
% Folder list
% =====================================================================
function local_onAddFolder(fig, recursive)
    if recursive
        prompt = 'Pilih folder INDUK (semua subfolder berisi gambar akan ditambahkan)';
    else
        prompt = 'Pilih SATU folder berisi gambar';
    end
    parent = local_pickDir(fig, pwd, prompt);
    if isequal(parent, 0); return; end

    found = batchpivprep2.io.collectFolders(parent, recursive);
    if isempty(found)
        warndlg(sprintf(['Tidak ditemukan folder berisi gambar yang didukung di:\n%s\n\n' ...
            'Format: jpg, jpeg, png, tif, tiff. (Folder RAW_/GS_/EXIF_ dilewati.)'], ...
            parent), 'BatchPIVPrep2');
        return;
    end
    local_appendFolders(fig, found);
end


function local_appendFolders(fig, found)
    h = guidata(fig);
    if isempty(h.folders)
        existing = {};
    else
        existing = {h.folders.path};
    end
    nAdded = 0;
    for i = 1:numel(found)
        if any(strcmpi(found(i).path, existing)); continue; end
        e = struct( ...
            'path',       found(i).path, ...
            'files',      {found(i).files}, ...
            'nImg',       found(i).nImg, ...
            'outName',    local_defaultOutName(found(i).path), ...
            'seqMode',    'consecutive', ...                  % urutan file default
            'seqStep',    1, ...
            'anchor',     h.activeAnchor, ...                 % reuse anchor aktif
            'anchorName', local_presetName(h.activeAnchor), ...
            'crop',       h.activeCrop, ...                   % reuse crop aktif
            'cropName',   local_presetName(h.activeCrop));
        h.folders(end + 1) = e;
        existing{end + 1}  = found(i).path; %#ok<AGROW>
        nAdded = nAdded + 1;
    end
    guidata(fig, h);
    batchpivprep2.ui.refreshFolderTable(fig);
    fprintf('BatchPIVPrep2: %d folder ditambahkan (total %d).\n', nAdded, numel(h.folders));
end


function local_onRemove(fig)
    h = guidata(fig);
    rows = h.selRows;
    if isempty(rows) || isempty(h.folders)
        warndlg('Pilih baris folder di tabel terlebih dahulu.', 'BatchPIVPrep2');
        return;
    end
    rows = rows(rows >= 1 & rows <= numel(h.folders));
    h.folders(rows) = [];
    h.selRows = [];
    guidata(fig, h);
    batchpivprep2.ui.refreshFolderTable(fig);
end


function local_onClear(fig)
    h = guidata(fig);
    if isempty(h.folders); return; end
    h.folders = struct('path', {}, 'files', {}, 'nImg', {}, ...
                       'outName', {}, 'seqMode', {}, 'seqStep', {}, ...
                       'anchor', {}, 'anchorName', {}, ...
                       'crop', {}, 'cropName', {});
    h.selRows = [];
    guidata(fig, h);
    batchpivprep2.ui.refreshFolderTable(fig);
end


function local_onTableSelect(fig, e)
    h = guidata(fig);
    if isempty(e.Indices)
        h.selRows = [];
    else
        h.selRows = unique(e.Indices(:, 1))';
    end
    guidata(fig, h);
end


function local_onTableEdit(fig, e)
%LOCAL_ONTABLEEDIT  Kolom editable: "Output Name" (4) & "Sequencing" (5).
    if isempty(e.Indices); return; end
    row = e.Indices(1);
    col = e.Indices(2);

    h = guidata(fig);
    if row < 1 || row > numel(h.folders); return; end

    switch col
        case 4   % Output Name
            newName = local_sanitizeOutName(strtrim(char(e.NewData)));
            if isempty(newName)
                newName = local_defaultOutName(h.folders(row).path);
            end
            h.folders(row).outName = newName;
        case 5   % Sequencing (urutan file -> metadata di .mat)
            [mode, step] = batchpivprep2.ui.seqOptions('parse', char(e.NewData));
            h.folders(row).seqMode = mode;
            h.folders(row).seqStep = step;
        otherwise
            return;
    end
    guidata(fig, h);
    batchpivprep2.ui.refreshFolderTable(fig);
end


% =====================================================================
% Quick PIV (QPIV) - bersihkan frame mati SEBELUM prep
% =====================================================================
function local_onQpiv(fig)
%LOCAL_ONQPIV  Jalankan jendela Quick PIV pada foto MENTAH folder terpilih.
%   Frame yang ditandai "abaikan" disimpan ke berkas progres global
%   (PIVlab_automasi_progress) berkunci path folder, lalu dibuang dari urutan
%   RAW saat Run (local_onRun) sebelum stabilisasi+crop+pack.
    h = guidata(fig);
    if ~isfield(h, 'selRows') || numel(h.selRows) ~= 1
        errordlg('Pilih TEPAT SATU folder di tabel dulu untuk Quick PIV.', ...
            'Quick PIV');
        return;
    end
    row = h.selRows(1);
    if row < 1 || row > numel(h.folders); return; end
    f = h.folders(row);

    % --- Pastikan engine analyze + pivcore (PIVTerry/core) di path ---
    [okDep, why] = local_ensureQpivDeps();
    if ~okDep
        errordlg(why, 'Quick PIV - dependensi');
        return;
    end

    expdir = f.path;
    key    = PIVlab_automasi_progress('key', expdir);
    e      = PIVlab_automasi_progress('get', key);
    ign    = [];
    if ~isempty(e) && isfield(e, 'ignore_frames'); ign = e.ignore_frames; end

    nm = '';
    if isfield(f, 'outName') && ~isempty(f.outName); nm = f.outName; end
    if isempty(nm); [~, nm] = fileparts(local_strip_sep(f.path)); end

    job = struct( ...
        'raw_folder',   f.path, ...
        'expdir',       expdir, ...
        'name',         nm, ...
        'suffix',       '', ...                 % auto-deteksi
        'sequencing',   'consecutive', ...
        'scan_orient',  'Horizontal', ...
        'scan_pos_pct', 50, ...
        'iw_passes',    [64 32 25 16], ...
        'num_passes',   3, ...
        'cache_file',   '', ...
        'ignore_frames', ign, ...
        'num_workers',  8);

    onDone = @() local_afterQpiv(fig, row, key);
    try
        PIVlab_automasi_qpiv_GUI_V2(job, key, onDone);
    catch ME
        errordlg(sprintf('Quick PIV gagal:\n%s', ME.message), 'Quick PIV');
    end
end


function local_afterQpiv(fig, row, key)
%LOCAL_AFTERQPIV  Dipanggil saat jendela QPIV simpan; perbarui info di GUI.
    if ~ishandle(fig); return; end
    e = PIVlab_automasi_progress('get', key);
    n = 0;
    if ~isempty(e) && isfield(e, 'ignore_frames'); n = numel(e.ignore_frames); end
    h = guidata(fig);
    if isfield(h, 'txtFolderCount') && ishandle(h.txtFolderCount)
        set(h.txtFolderCount, 'String', sprintf('Folder #%d: %d frame ditandai buang', row, n));
    end
    fprintf('[QPIV] Folder #%d: %d frame ditandai untuk dibuang.\n', row, n);
end


function [ok, why] = local_ensureQpivDeps()
%LOCAL_ENSUREQPIVDEPS  Pastikan PIVlab_automasi_qpiv_GUI + pivcore di path.
    ok = true; why = '';
    if isempty(which('PIVlab_automasi_qpiv_GUI_V2'))
        % Coba bootstrap project (menambah 3_analyze ke path).
        if ~isempty(which('pivprepv2_setup'))
            try pivprepv2_setup(); catch; end
        end
    end
    if isempty(which('PIVlab_automasi_qpiv_GUI_V2'))
        ok = false;
        why = ['Engine Quick PIV (PIVlab_automasi_qpiv_GUI_V2 di 3_analyze) tidak ' ...
               'ditemukan di path. Jalankan pivprepv2_setup lebih dulu.'];
        return;
    end
    if isempty(which('pivcore.data.buildDataset'))
        cd0 = local_findPivterryCore();
        if ~isempty(cd0); addpath(cd0); end
    end
    if isempty(which('pivcore.data.buildDataset'))
        ok = false;
        why = ['Paket pivcore (PIVTerry/core) tidak ditemukan di path. Quick PIV ' ...
               'butuh ini untuk plot POT/PSG. Tambahkan folder PIVTerry/core ke path.'];
    end
end


function p = local_findPivterryCore()
%LOCAL_FINDPIVTERRYCORE  Cari folder PIVTerry/core (berisi +pivcore) naik dari sini.
    p = '';
    here = fileparts(mfilename('fullpath'));   % .../+batchpivprep2/+ui
    d = here;
    for up = 1:8
        cand = fullfile(d, 'PIVTerry', 'core');
        if isfolder(fullfile(cand, '+pivcore')); p = cand; return; end
        parent = fileparts(d);
        if isempty(parent) || strcmp(parent, d); break; end
        d = parent;
    end
end


function p = local_strip_sep(p)
    if ~isempty(p) && (p(end) == filesep || p(end) == '/'); p(end) = []; end
end


function folders = local_applyQpivDrops(folders, cfg) %#ok<INUSD>
%LOCAL_APPLYQPIVDROPS  Buang berkas RAW yang ditandai Quick PIV dari urutan.
%   ignore_frames Quick PIV adalah indeks PASANGAN (konvensi 'consecutive':
%   pasangan k = berkas (k, k+1)). Frame "mati" = tak ada gerak pada pasangan
%   itu -> buang berkas KEDUA pasangan (indeks k+1). Sisa berkas tetap urut
%   dan akan dipasangkan ulang otomatis di tahap berikutnya.
    if isempty(which('PIVlab_automasi_progress')); return; end  % tak ada store -> tak ada tanda
    for i = 1:numel(folders)
        try
            key = PIVlab_automasi_progress('key', folders(i).path);
            e   = PIVlab_automasi_progress('get', key);
        catch
            continue;
        end
        if isempty(e) || ~isfield(e, 'ignore_frames') || isempty(e.ignore_frames)
            continue;
        end
        files = folders(i).files;
        n = numel(files);
        ign = round(double(e.ignore_frames(:)'));
        dropIdx = unique(ign + 1);                 % berkas kedua tiap pasangan
        dropIdx = dropIdx(dropIdx >= 1 & dropIdx <= n);
        if isempty(dropIdx); continue; end
        keep = true(1, n); keep(dropIdx) = false;
        folders(i).files = files(keep);
        folders(i).nImg  = sum(keep);
        [~, shortName] = fileparts(local_strip_sep(folders(i).path));
        fprintf('[QPIV] %s: buang %d frame mati (%d -> %d frame).\n', ...
            shortName, numel(dropIdx), n, folders(i).nImg);
    end
end


% =====================================================================
% Anchor (jitter reference / stabilisasi)
% =====================================================================
function local_onNewAnchor(fig)
    h = guidata(fig);
    [fn, fp] = local_pickFile(fig, ...
        {'*.jpg;*.jpeg;*.png;*.tif;*.tiff', 'Images (*.jpg,*.png,*.tif)'}, ...
        'Pilih gambar referensi untuk menggambar anchor stabilisasi');
    if isequal(fn, 0); return; end

    methodList = {'surf', 'phasecorr'};
    method = methodList{get(h.popStabMethod, 'Value')};

    preset = batchpivprep2.io.anchorPreset.createFromImage( ...
        fullfile(fp, fn), method, 5);
    if isempty(preset)
        return;
    end
    local_setActiveAnchor(fig, preset);
end


function local_onLoadAnchor(fig)
    [fn, fp] = local_pickFile(fig, {'*.mat', 'Anchor preset (*.mat)'}, ...
        'Muat preset anchor stabilisasi');
    if isequal(fn, 0); return; end
    try
        preset = batchpivprep2.io.anchorPreset.loadPreset(fullfile(fp, fn));
    catch ME
        errordlg(sprintf('Gagal memuat preset:\n%s', ME.message), 'BatchPIVPrep2');
        return;
    end
    local_setActiveAnchor(fig, preset);
end


function local_onSaveAnchor(fig)
    h = guidata(fig);
    if isempty(h.activeAnchor)
        warndlg('Belum ada anchor aktif untuk disimpan.', 'BatchPIVPrep2');
        return;
    end
    defName = [h.activeAnchor.name '.mat'];
    [fn, fp] = local_putFile(fig, {'*.mat', 'Anchor preset (*.mat)'}, ...
        'Simpan preset anchor', defName);
    if isequal(fn, 0); return; end
    try
        batchpivprep2.io.anchorPreset.savePreset(h.activeAnchor, fullfile(fp, fn));
        fprintf('Anchor disimpan: %s\n', fullfile(fp, fn));
    catch ME
        errordlg(sprintf('Gagal menyimpan:\n%s', ME.message), 'BatchPIVPrep2');
    end
end


function local_setActiveAnchor(fig, preset)
    h = guidata(fig);
    h.activeAnchor = preset;
    guidata(fig, h);

    batchpivprep2.io.anchorPreset.displayInAxes(preset, h.axPreview);
    set(h.txtAnchorInfo, 'String', batchpivprep2.io.anchorPreset.summaryText(preset));

    if isfield(preset, 'method') && ~isempty(preset.method)
        if strcmpi(preset.method, 'phasecorr')
            set(h.popStabMethod, 'Value', 2);
        else
            set(h.popStabMethod, 'Value', 1);
        end
    end
end


function local_onAssign(fig, toAll)
    h = guidata(fig);
    if isempty(h.activeAnchor)
        warndlg('Belum ada anchor aktif. Buat (New) atau muat (Load) dulu.', ...
            'BatchPIVPrep2');
        return;
    end
    if isempty(h.folders)
        warndlg('Belum ada folder di daftar.', 'BatchPIVPrep2');
        return;
    end

    if toAll
        rows = 1:numel(h.folders);
    else
        rows = h.selRows;
        if isempty(rows)
            warndlg('Pilih baris folder di tabel terlebih dahulu.', 'BatchPIVPrep2');
            return;
        end
    end
    rows = rows(rows >= 1 & rows <= numel(h.folders));

    for r = rows
        h.folders(r).anchor     = h.activeAnchor;
        h.folders(r).anchorName = h.activeAnchor.name;
    end
    guidata(fig, h);
    batchpivprep2.ui.refreshFolderTable(fig);
    fprintf('Anchor "%s" di-assign ke %d folder.\n', ...
        h.activeAnchor.name, numel(rows));
end


function local_onCheckAnchor(fig)
    h = guidata(fig);
    if isempty(h.folders)
        warndlg('Belum ada folder di daftar.', 'BatchPIVPrep2');
        return;
    end
    batchpivprep2.ui.viewFirstFrames(fig);
end


% =====================================================================
% Crop (cropping ROI)
% =====================================================================
function local_onCropModeChange(fig)
%LOCAL_ONCROPMODECHANGE  Simpan mode crop aktif (utk ROI baru yang digambar).
    h = guidata(fig);
    h.cropMode = local_cropModeFromPopup(h.popCropMode);
    guidata(fig, h);
end


function local_onNewCrop(fig)
    h = guidata(fig);
    if strcmpi(local_cropModeFromPopup(h.popCropMode), 'none')
        helpdlg(['Mode 0 (tanpa crop) tidak butuh ROI. Pakai tombol ' ...
            '"Set NO-CROP -> SELECTED/ALL" untuk menandai folder.'], ...
            'BatchPIVPrep2 - Mode 0');
        return;
    end
    [fn, fp] = local_pickFile(fig, ...
        {'*.jpg;*.jpeg;*.png;*.tif;*.tiff', 'Images (*.jpg,*.png,*.tif)'}, ...
        'Pilih gambar referensi (belum di-crop) untuk menggambar ROI cropping');
    if isequal(fn, 0); return; end

    cropMode = local_cropModeFromPopup(h.popCropMode);
    preset = batchpivprep2.io.cropPreset.createFromImage( ...
        fullfile(fp, fn), cropMode, 5);
    if isempty(preset)
        return;
    end
    local_setActiveCrop(fig, preset);
end


function local_onLoadCrop(fig)
    [fn, fp] = local_pickFile(fig, {'*.mat', 'Crop ROI preset (*.mat)'}, ...
        'Muat preset ROI cropping');
    if isequal(fn, 0); return; end
    try
        preset = batchpivprep2.io.cropPreset.loadPreset(fullfile(fp, fn));
    catch ME
        errordlg(sprintf('Gagal memuat preset crop:\n%s', ME.message), 'BatchPIVPrep2');
        return;
    end
    local_setActiveCrop(fig, preset);
end


function local_onSaveCrop(fig)
    h = guidata(fig);
    if isempty(h.activeCrop)
        warndlg('Belum ada ROI cropping aktif untuk disimpan.', 'BatchPIVPrep2');
        return;
    end
    defName = [h.activeCrop.name '.mat'];
    [fn, fp] = local_putFile(fig, {'*.mat', 'Crop ROI preset (*.mat)'}, ...
        'Simpan preset ROI cropping', defName);
    if isequal(fn, 0); return; end
    try
        batchpivprep2.io.cropPreset.savePreset(h.activeCrop, fullfile(fp, fn));
        fprintf('Crop ROI disimpan: %s\n', fullfile(fp, fn));
    catch ME
        errordlg(sprintf('Gagal menyimpan:\n%s', ME.message), 'BatchPIVPrep2');
    end
end


function local_setActiveCrop(fig, preset)
    h = guidata(fig);
    h.activeCrop = preset;
    if isfield(preset, 'cropMode') && ~isempty(preset.cropMode)
        h.cropMode = batchpivprep2.io.cropPreset.validMode(preset.cropMode);
    end
    guidata(fig, h);

    batchpivprep2.io.cropPreset.displayInAxes(preset, h.axCropPreview);
    set(h.txtCropInfo, 'String', batchpivprep2.io.cropPreset.summaryText(preset));

    % Selaraskan popup mode dgn preset.
    set(h.popCropMode, 'Value', local_cropModeToPopup(h.cropMode));
end


function local_onAssignCrop(fig, toAll)
    h = guidata(fig);
    if isempty(h.activeCrop)
        warndlg('Belum ada ROI cropping aktif. Buat (New) atau muat (Load) dulu.', ...
            'BatchPIVPrep2');
        return;
    end
    if isempty(h.folders)
        warndlg('Belum ada folder di daftar.', 'BatchPIVPrep2');
        return;
    end

    if toAll
        rows = 1:numel(h.folders);
    else
        rows = h.selRows;
        if isempty(rows)
            warndlg('Pilih baris folder di tabel terlebih dahulu.', 'BatchPIVPrep2');
            return;
        end
    end
    rows = rows(rows >= 1 & rows <= numel(h.folders));

    for r = rows
        h.folders(r).crop     = h.activeCrop;
        h.folders(r).cropName = h.activeCrop.name;
    end
    guidata(fig, h);
    batchpivprep2.ui.refreshFolderTable(fig);
    fprintf('Crop ROI "%s" [%s] di-assign ke %d folder.\n', ...
        h.activeCrop.name, h.activeCrop.cropMode, numel(rows));
end


function local_onAssignNoCrop(fig, toAll)
%LOCAL_ONASSIGNNOCROP  Mode 0: tandai folder TANPA crop (frame penuh).
%   Tak butuh active crop / gambar ROI -- buat preset 'none' lalu assign.
    h = guidata(fig);
    if isempty(h.folders)
        warndlg('Belum ada folder di daftar.', 'BatchPIVPrep2');
        return;
    end
    if toAll
        rows = 1:numel(h.folders);
    else
        rows = h.selRows;
        if isempty(rows)
            warndlg('Pilih baris folder di tabel terlebih dahulu.', 'BatchPIVPrep2');
            return;
        end
    end
    rows = rows(rows >= 1 & rows <= numel(h.folders));

    noCrop = batchpivprep2.io.cropPreset.makeNone('no-crop');
    for r = rows
        h.folders(r).crop     = noCrop;
        h.folders(r).cropName = noCrop.name;
    end
    % Selaraskan mode aktif + popup ke Mode 0 (preview info).
    h.cropMode   = 'none';
    h.activeCrop = noCrop;
    guidata(fig, h);
    set(h.popCropMode, 'Value', local_cropModeToPopup('none'));
    batchpivprep2.io.cropPreset.displayInAxes(noCrop, h.axCropPreview);
    set(h.txtCropInfo, 'String', batchpivprep2.io.cropPreset.summaryText(noCrop));
    batchpivprep2.ui.refreshFolderTable(fig);
    fprintf('Mode 0 (tanpa crop) di-assign ke %d folder.\n', numel(rows));
end


function local_onViewCrop(fig)
    h = guidata(fig);
    if isempty(h.folders)
        warndlg('Belum ada folder di daftar.', 'BatchPIVPrep2');
        return;
    end
    if strcmpi(local_cropModeFromPopup(h.popCropMode), 'none')
        helpdlg(['Mode 0 (tanpa crop) tidak punya ROI untuk digambar/diperiksa. ' ...
            'Keluaran = frame penuh hasil stabilisasi.'], 'BatchPIVPrep2 - Mode 0');
        return;
    end
    batchpivprep2.ui.viewCropFrames(fig);
end


% =====================================================================
% Output settings
% =====================================================================
function local_onSuffixChange(fig)
    h = guidata(fig);
    set(h.txtSuffixPreview, 'String', local_suffixPreview(get(h.edSuffix, 'String')));
end


function local_onPickRoot(fig)
    h = guidata(fig);
    folder = local_pickDir(fig, pwd, 'Pilih folder akar output bersama');
    if isequal(folder, 0); return; end
    h.outputRoot = folder;
    guidata(fig, h);
    disp_str = folder;
    if numel(disp_str) > 64; disp_str = ['...' disp_str(end-61:end)]; end
    set(h.txtRoot, 'String', disp_str);
    set(h.bgOutLoc, 'SelectedObject', h.rbRoot);
end


% =====================================================================
% Run / Stop
% =====================================================================
function local_onStop(fig)
    setappdata(fig, 'stopRequested', true);
    h = guidata(fig);
    if isfield(h, 'btnStop') && ishandle(h.btnStop)
        set(h.btnStop, 'String', 'Stopping...', 'Enable', 'off');
    end
    fprintf('BatchPIVPrep2: STOP diminta. Menghentikan setelah frame berjalan...\n');
    drawnow;
end


function local_onRun(fig)
    h = guidata(fig);

    if getappdata(fig, 'isRunning')
        return;
    end
    if isempty(h.folders)
        errordlg('Tambah minimal satu folder terlebih dahulu.', 'BatchPIVPrep2');
        return;
    end

    % --- Pastikan setiap folder punya ANCHOR (reuse anchor aktif bila ada) ---
    noAnchor = arrayfun(@(f) isempty(f.anchor), h.folders);
    if any(noAnchor)
        if ~isempty(h.activeAnchor)
            for r = find(noAnchor(:)')
                h.folders(r).anchor     = h.activeAnchor;
                h.folders(r).anchorName = h.activeAnchor.name;
            end
        else
            errordlg(sprintf(['%d folder belum memiliki anchor stabilisasi dan ' ...
                'tidak ada anchor aktif.\nBuat/muat anchor lalu "Assign to ALL".'], ...
                sum(noAnchor)), 'BatchPIVPrep2');
            return;
        end
    end

    % --- Pastikan setiap folder punya CROP ROI (reuse crop aktif bila ada) ---
    noCrop = arrayfun(@(f) ~isfield(f, 'crop') || isempty(f.crop), h.folders);
    if any(noCrop)
        if ~isempty(h.activeCrop)
            for r = find(noCrop(:)')
                h.folders(r).crop     = h.activeCrop;
                h.folders(r).cropName = h.activeCrop.name;
            end
        else
            errordlg(sprintf(['%d folder belum memiliki ROI cropping dan tidak ada ' ...
                'crop aktif.\nBuat/muat crop ROI (tab Cropping) lalu "Assign to ALL".'], ...
                sum(noCrop)), 'BatchPIVPrep2');
            return;
        end
    end
    guidata(fig, h);
    batchpivprep2.ui.refreshFolderTable(fig);

    % --- Validasi numerik ---
    rawQual = str2double(get(h.edRawQual, 'String'));
    gsScale = str2double(get(h.edGsScale, 'String'));
    gsQual  = str2double(get(h.edGsQual,  'String'));
    jit     = str2double(get(h.edJitter,  'String'));
    if any(isnan([rawQual, gsScale, gsQual, jit]))
        errordlg('Nilai numerik tidak valid (RAW qual, GS scale/qual, jitter tol).', ...
            'BatchPIVPrep2');
        return;
    end
    if gsScale <= 0 || gsScale > 100
        errordlg('GS scale harus antara 1 dan 100 persen.', 'BatchPIVPrep2');
        return;
    end

    % --- Bangun cfg ---
    cfg = struct();
    cfg.suffix = strtrim(get(h.edSuffix, 'String'));

    methodList     = {'surf', 'phasecorr'};
    cfg.stabMethod = methodList{get(h.popStabMethod, 'Value')};
    cfg.jitterTol  = jit;

    cfg.roiPad       = 50;
    cfg.surfMaxRatio = 0.60;
    cfg.minMatchPts  = 4;

    cfg.marginEnabled = local_field(h, 'marginEnabled', true);
    cfg.marginPx      = local_field(h, 'marginPx', 10);

    rawFmtList    = {'jpg', 'png', 'tif'};
    cfg.rawFormat = rawFmtList{get(h.popRawFmt, 'Value')};
    cfg.rawQuality = rawQual;

    cfg.gsScale   = gsScale / 100;
    cfg.gsQuality = gsQual;

    if get(h.rbRoot, 'Value')
        if isempty(h.outputRoot)
            errordlg('Mode "Common root" dipilih tetapi folder root belum ditentukan.', ...
                'BatchPIVPrep2');
            return;
        end
        cfg.outputMode = 'root';
        cfg.outputRoot = h.outputRoot;
    else
        cfg.outputMode = 'inplace';
        cfg.outputRoot = '';
    end

    % --- Opsi "kemas ke 1 .mat" (gabungan PIVPrep + bridge) ---
    cfg.packSingleMat = isfield(h, 'cbPackMat')   && get(h.cbPackMat, 'Value') == 1;
    cfg.keepFolder    = isfield(h, 'cbKeepFolder') && get(h.cbKeepFolder, 'Value') == 1;
    % .mat ikut pilihan lokasi keluaran: mode 'root' -> simpan di Common root,
    % mode 'inplace' -> '' (simpan di folder input masing-masing).
    if strcmp(cfg.outputMode, 'root')
        cfg.matOutDir = cfg.outputRoot;
    else
        cfg.matOutDir = '';
    end

    % --- Siapkan kontrol Run/Stop ---
    setappdata(fig, 'stopRequested', false);
    setappdata(fig, 'isRunning',     true);
    set(h.btnRun,  'Enable', 'off', 'String', 'Running...');
    set(h.btnStop, 'Enable', 'on',  'String', 'STOP');
    drawnow;
    cleanup = onCleanup(@() local_restoreRunStop(fig)); %#ok<NASGU>

    stopCheck = @() getappdata(fig, 'stopRequested');

    % --- Buang frame RAW yang ditandai Quick PIV (sebelum prep) ---
    runFolders = local_applyQpivDrops(h.folders, cfg);

    try
        results = batchpivprep2.core.runBatch(runFolders, cfg, stopCheck);
        h = guidata(fig);
        h.lastResults = results;
        guidata(fig, h);
    catch ME
        errordlg(sprintf('Batch gagal:\n%s', ME.message), 'BatchPIVPrep2');
        rethrow(ME);
    end
end


function local_restoreRunStop(fig)
    try
        setappdata(fig, 'isRunning', false);
        h = guidata(fig);
        if isfield(h, 'btnRun') && ishandle(h.btnRun)
            set(h.btnRun, 'Enable', 'on', 'String', 'Run Batch (Stabilize + Crop)');
        end
        if isfield(h, 'btnStop') && ishandle(h.btnStop)
            set(h.btnStop, 'Enable', 'off', 'String', 'STOP');
        end
    catch
    end
end


% =====================================================================
% Helpers
% =====================================================================
function nm = local_presetName(preset)
    if isempty(preset)
        nm = '';
    elseif isstruct(preset) && isfield(preset, 'name')
        nm = preset.name;
    else
        nm = 'preset';
    end
end


function m = local_cropModeFromPopup(popHandle)
%LOCAL_CROPMODEFROMPOPUP  Value popup -> 'none' (1) | 'crop' (2) | 'square' (3).
    switch get(popHandle, 'Value')
        case 1
            m = 'none';
        case 3
            m = 'square';
        otherwise
            m = 'crop';
    end
end


function v = local_cropModeToPopup(m)
%LOCAL_CROPMODETOPOPUP  Mode -> Value popup (kebalikan local_cropModeFromPopup).
    switch lower(char(m))
        case 'none';   v = 1;
        case 'square'; v = 3;
        otherwise;     v = 2;
    end
end


function v = local_field(s, fld, def)
    if isstruct(s) && isfield(s, fld) && ~isempty(s.(fld))
        v = s.(fld);
    else
        v = def;
    end
end


function nm = local_defaultOutName(p)
    p = char(p);
    if ~isempty(p) && (p(end) == filesep || p(end) == '/'); p(end) = []; end
    [~, nm] = fileparts(p);
    if isempty(nm); nm = 'Folder'; end
end


function s = local_sanitizeOutName(s)
    s = char(s);
    s = regexprep(s, '[\\/:*?"<>|]', '_');
    s = regexprep(s, '\s+', '_');
end


function s = local_suffixPreview(suffix)
    suffix = strtrim(char(suffix));
    if isempty(suffix)
        s = '-> RAW / GS / EXIF';
    else
        suffix = regexprep(suffix, '[\\/:*?"<>|]', '_');
        suffix = regexprep(suffix, '\s+', '_');
        s = sprintf('-> RAW_%s / GS_%s / EXIF_%s', suffix, suffix, suffix);
    end
end


% =====================================================================
% Session / Progress (.mat): Save / Load / Save As
% =====================================================================
function local_onSaveProgress(fig)
%LOCAL_ONSAVEPROGRESS  Simpan progress. Bila belum ada berkas sesi -> minta
%   lokasi (seperti Save As). Bila sudah ada -> TIMPA berkas itu langsung.
    h = guidata(fig);
    if isempty(h.progressFile)
        local_onSaveAsProgress(fig);
    else
        local_doSaveProgress(fig, h.progressFile);
    end
end


function local_onSaveAsProgress(fig)
%LOCAL_ONSAVEASPROGRESS  Simpan progress ke berkas BARU (selalu tanya lokasi).
%   Berkas baru menjadi berkas sesi aktif (Save berikutnya menimpanya).
    h = guidata(fig);
    defName = 'BatchPIVPrep2_progress.mat';
    if ~isempty(h.progressFile)
        [~, nm, ext] = fileparts(h.progressFile);
        defName = [nm ext];
    end
    [fn, fp] = local_putFile(fig, ...
        {'*.mat', 'BatchPIVPrep2 progress (*.mat)'}, ...
        'Simpan progress sebagai...', defName);
    if isequal(fn, 0); return; end
    local_doSaveProgress(fig, fullfile(fp, fn));
end


function local_doSaveProgress(fig, pathOut)
%LOCAL_DOSAVEPROGRESS  Tulis seluruh state sesi ke berkas .mat (variabel 'progress').
    h = guidata(fig);
    progress = local_buildProgressStruct(h); %#ok<NASGU>
    try
        save(pathOut, 'progress');
    catch ME
        errordlg(sprintf('Gagal menyimpan progress:\n%s', ME.message), 'BatchPIVPrep2');
        return;
    end
    h.progressFile = pathOut;
    guidata(fig, h);
    local_updateProgressStatus(h);
    fprintf('Progress disimpan: %s\n', pathOut);
end


function local_onLoadProgress(fig)
%LOCAL_ONLOADPROGRESS  Muat sesi dari berkas .mat; berkas itu jadi sesi aktif.
    [fn, fp] = local_pickFile(fig, ...
        {'*.mat', 'BatchPIVPrep2 progress (*.mat)'}, 'Muat progress sesi');
    if isequal(fn, 0); return; end
    pathIn = fullfile(fp, fn);
    try
        S = load(pathIn);
    catch ME
        errordlg(sprintf('Gagal memuat berkas:\n%s', ME.message), 'BatchPIVPrep2');
        return;
    end
    if ~isfield(S, 'progress') || ~isstruct(S.progress) || ~isfield(S.progress, 'folders')
        errordlg('Berkas ini bukan progress BatchPIVPrep2 yang valid.', 'BatchPIVPrep2');
        return;
    end
    local_applyProgress(fig, S.progress, pathIn);
end


function progress = local_buildProgressStruct(h)
%LOCAL_BUILDPROGRESSSTRUCT  Kumpulkan seluruh state sesi menjadi satu struct.
    progress = struct();
    progress.type    = 'BatchPIVPrep2Progress';
    progress.version = 1;
    progress.folders       = h.folders;        % termasuk anchor & crop per folder
    progress.activeAnchor  = h.activeAnchor;
    progress.activeCrop    = h.activeCrop;
    progress.cropMode      = h.cropMode;
    progress.marginEnabled = h.marginEnabled;
    progress.marginPx      = h.marginPx;
    progress.outputRoot    = h.outputRoot;
    progress.settings = struct( ...
        'suffix',        get(h.edSuffix,      'String'), ...
        'stabMethodVal', get(h.popStabMethod, 'Value'), ...
        'jitterTol',     get(h.edJitter,      'String'), ...
        'rawFmtVal',     get(h.popRawFmt,     'Value'), ...
        'rawQual',       get(h.edRawQual,     'String'), ...
        'gsScale',       get(h.edGsScale,     'String'), ...
        'gsQual',        get(h.edGsQual,      'String'), ...
        'cropModeVal',   get(h.popCropMode,   'Value'), ...
        'cropModeStr',   local_cropModeFromPopup(h.popCropMode), ...
        'outLocRoot',    get(h.rbRoot,        'Value'));
    progress.savedAt = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
end


function local_applyProgress(fig, prog, pathIn)
%LOCAL_APPLYPROGRESS  Pulihkan state sesi dari struct progress + refresh GUI.
    h = guidata(fig);

    % --- State inti ---
    h.folders       = local_normalizeFolders(local_progField(prog, 'folders', []));
    h.activeAnchor  = local_progField(prog, 'activeAnchor', []);
    h.activeCrop    = local_progField(prog, 'activeCrop', []);
    h.cropMode      = local_progField(prog, 'cropMode', 'crop');
    h.marginEnabled = local_progField(prog, 'marginEnabled', true);
    h.marginPx      = local_progField(prog, 'marginPx', 10);
    h.outputRoot    = local_progField(prog, 'outputRoot', '');
    h.selRows       = [];
    h.progressFile  = pathIn;
    guidata(fig, h);

    % --- Setelan kontrol GUI ---
    if isfield(prog, 'settings') && isstruct(prog.settings)
        s = prog.settings;
        local_setIf(h.edSuffix,      'String', s, 'suffix');
        local_setIf(h.popStabMethod, 'Value',  s, 'stabMethodVal');
        local_setIf(h.edJitter,      'String', s, 'jitterTol');
        local_setIf(h.popRawFmt,     'Value',  s, 'rawFmtVal');
        local_setIf(h.edRawQual,     'String', s, 'rawQual');
        local_setIf(h.edGsScale,     'String', s, 'gsScale');
        local_setIf(h.edGsQual,      'String', s, 'gsQual');
        % Mode crop: utamakan string (tahan thd perubahan urutan popup; progress
        % lama hanya punya cropModeVal 1=crop/2=square -> petakan via fallback).
        if isfield(s, 'cropModeStr') && ~isempty(s.cropModeStr)
            set(h.popCropMode, 'Value', local_cropModeToPopup(s.cropModeStr));
        elseif isfield(s, 'cropModeVal') && ~isempty(s.cropModeVal)
            oldVal = s.cropModeVal;          % skema lama: 1=crop, 2=square
            if oldVal == 2; set(h.popCropMode, 'Value', local_cropModeToPopup('square'));
            else;           set(h.popCropMode, 'Value', local_cropModeToPopup('crop')); end
        end
        if isfield(s, 'outLocRoot') && s.outLocRoot
            set(h.bgOutLoc, 'SelectedObject', h.rbRoot);
        else
            set(h.bgOutLoc, 'SelectedObject', h.rbInplace);
        end
    end

    % --- Refresh tampilan ---
    set(h.txtSuffixPreview, 'String', local_suffixPreview(get(h.edSuffix, 'String')));
    rootStr = '(none)';
    if ~isempty(h.outputRoot)
        rootStr = h.outputRoot;
        if numel(rootStr) > 64; rootStr = ['...' rootStr(end-61:end)]; end
    end
    set(h.txtRoot, 'String', rootStr);

    batchpivprep2.io.anchorPreset.displayInAxes(h.activeAnchor, h.axPreview);
    set(h.txtAnchorInfo, 'String', batchpivprep2.io.anchorPreset.summaryText(h.activeAnchor));
    batchpivprep2.io.cropPreset.displayInAxes(h.activeCrop, h.axCropPreview);
    set(h.txtCropInfo, 'String', batchpivprep2.io.cropPreset.summaryText(h.activeCrop));

    batchpivprep2.ui.refreshFolderTable(fig);
    local_updateProgressStatus(h);
    fprintf('Progress dimuat: %s (%d folder).\n', pathIn, numel(h.folders));
end


function folders = local_normalizeFolders(folders)
%LOCAL_NORMALIZEFOLDERS  Pastikan struct folder punya semua field skema v2.
%   Progress lama (tanpa seqMode/seqStep) dimuat dengan default 'consecutive'.
    if ~isstruct(folders) || isempty(folders)
        folders = struct('path', {}, 'files', {}, 'nImg', {}, 'outName', {}, ...
                         'seqMode', {}, 'seqStep', {}, ...
                         'anchor', {}, 'anchorName', {}, 'crop', {}, 'cropName', {});
        return;
    end
    need = {'path', 'files', 'nImg', 'outName', 'seqMode', 'seqStep', ...
            'anchor', 'anchorName', 'crop', 'cropName'};
    for k = 1:numel(need)
        if ~isfield(folders, need{k})
            [folders.(need{k})] = deal([]);
        end
    end
    % Default urutan file untuk folder yang field-nya kosong (mis. progress lama).
    for i = 1:numel(folders)
        if isempty(folders(i).seqMode); folders(i).seqMode = 'consecutive'; end
        if isempty(folders(i).seqStep); folders(i).seqStep = 1; end
    end
end


function local_updateProgressStatus(h)
%LOCAL_UPDATEPROGRESSSTATUS  Tampilkan nama berkas sesi aktif di header.
    if ~isfield(h, 'txtProgressFile') || ~ishandle(h.txtProgressFile); return; end
    if isempty(h.progressFile)
        set(h.txtProgressFile, 'String', 'Progress: (belum disimpan)', 'TooltipString', '');
    else
        [~, nm, ext] = fileparts(h.progressFile);
        set(h.txtProgressFile, 'String', sprintf('Progress: %s%s', nm, ext), ...
            'TooltipString', h.progressFile);
    end
end


function v = local_progField(s, fld, def)
%LOCAL_PROGFIELD  Ambil field dari struct progress dgn default (terima nilai
%   logical false / 0 yang sah; hanya ganti ke default bila field tak ada).
    if isstruct(s) && isfield(s, fld)
        v = s.(fld);
    else
        v = def;
    end
end


function local_setIf(ctrl, prop, s, fld)
%LOCAL_SETIF  set(ctrl, prop, s.(fld)) bila field ada & handle valid (aman).
    if isstruct(s) && isfield(s, fld) && ishandle(ctrl)
        try
            set(ctrl, prop, s.(fld));
        catch
        end
    end
end


% =====================================================================
% Resize / maximize + folder/file dialog (macOS) helpers
% =====================================================================
function local_onFigResize(fig)
%LOCAL_ONFIGRESIZE  Jaga blok konten menempel ke KIRI-ATAS saat figure
%   di-resize / maximize. Semua anak top-level digeser vertikal sebesar
%   perubahan tinggi figure, sehingga maximize hanya menambah ruang kosong
%   di kanan & bawah (tata letak tidak rusak).
    h = guidata(fig);
    if isempty(h) || ~isstruct(h) || ~isfield(h, 'lastHeight') || isempty(h.lastHeight)
        return;
    end
    % Abaikan event transien (mis. saat figure diminimize untuk dialog) agar
    % tata letak tidak teracak; jangan perbarui lastHeight pada jalur ini.
    try
        if strcmpi(get(fig, 'WindowState'), 'minimized'); return; end
    catch
    end
    p    = get(fig, 'Position');
    curH = p(4);
    if curH < 200
        return;          % tinggi implausibel (transien) -> abaikan
    end
    dy   = curH - h.lastHeight;
    h.lastHeight = curH;
    guidata(fig, h);
    if abs(dy) < 1
        return;
    end
    kids = get(fig, 'Children');
    for k = 1:numel(kids)
        try
            if ~strcmpi(get(kids(k), 'Units'), 'pixels'); continue; end
            pos = get(kids(k), 'Position');
            if numel(pos) == 4
                pos(2) = pos(2) + dy;
                set(kids(k), 'Position', pos);
            end
        catch
        end
    end
end


function out = local_pickDir(fig, startPath, prompt)
%LOCAL_PICKDIR  uigetdir dengan figure utama diminimize sementara agar
%   dialog pilih-folder tampil DI DEPAN (bukan di belakang) di macOS.
    c = local_lowerFig(fig); %#ok<NASGU>  % onCleanup mengembalikan saat keluar
    out = uigetdir(startPath, prompt);
end


function [fn, fp] = local_pickFile(fig, filter, prompt)
%LOCAL_PICKFILE  uigetfile dengan figure diminimize sementara (lihat local_pickDir).
    c = local_lowerFig(fig); %#ok<NASGU>
    [fn, fp] = uigetfile(filter, prompt);
end


function [fn, fp] = local_putFile(fig, filter, prompt, defName)
%LOCAL_PUTFILE  uiputfile dengan figure diminimize sementara (lihat local_pickDir).
    c = local_lowerFig(fig); %#ok<NASGU>
    [fn, fp] = uiputfile(filter, prompt, defName);
end


function c = local_lowerFig(fig)
%LOCAL_LOWERFIG  Minimize figure utama; kembalikan onCleanup yang memulihkan
%   state semula (normal/maximized) saat dialog ditutup -- aman thd error.
    wasState = 'normal';
    try
        wasState = get(fig, 'WindowState');
        set(fig, 'WindowState', 'minimized');
        drawnow;
    catch
    end
    c = onCleanup(@() local_restoreFig(fig, wasState));
end


function local_restoreFig(fig, wasState)
    try
        if isempty(wasState); wasState = 'normal'; end
        if ishandle(fig)
            set(fig, 'WindowState', wasState);
            drawnow;
            figure(fig);
        end
    catch
    end
end
