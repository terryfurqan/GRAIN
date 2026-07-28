function viewCropFrames(mainFig)
%VIEWCROPFRAMES  Jendela HUB ROI CROPPING: gambar / apply / periksa / edit.
%
%   batchpivprep2.ui.viewCropFrames(mainFig)
%
%   Analog dengan hub anchor (viewFirstFrames) tetapi untuk ROI CROPPING,
%   yang mendukung DUA MODE:
%     Mode 1 'crop'   -> kotak resizable (rectangle crop apa adanya).
%     Mode 2 'square' -> polygon 4 titik (squaring / normalisasi geometris).
%
%   ROI cropping digambar pada frame pertama tiap folder (gambar yang BELUM
%   di-crop, koordinat sama dengan yang dipakai stabilisasi). Alur:
%     1. Pilih mode crop (popup) -> "Draw / Redraw ROI".
%     2. "Apply ROI -> ALL / SELECTED" sebar ke folder.
%     3. Periksa tiap folder (Prev/Next); bila perlu DRAG ROI lalu
%        "Save ROI -> THIS folder".
%
%   Catatan: ROI cropping TERPISAH dari ROI stabilisasi.

    h = guidata(mainFig);
    if isempty(h.folders)
        warndlg('Belum ada folder di daftar.', 'BatchPIVPrep2');
        return;
    end

    bg = [0.96 0.96 0.96];
    rfig = figure( ...
        'Name', 'BatchPIVPrep2 - ROI CROPPING: Draw / Apply / Check / Edit', ...
        'NumberTitle', 'off', 'Color', bg, ...
        'MenuBar', 'none', 'ToolBar', 'figure', ...
        'Units', 'pixels', 'Position', [110 50 1120 770]);
    try                                  % paksa tema TERANG (abaikan dark mode OS)
        theme(rfig, 'light');
    catch
    end

    R = struct('mainFig', mainFig, 'idx', 1, 'hROI', [], 'roiMode', '', ...
        'frameImg', [], 'frameSize', [], 'folderName', '');

    R.txtInfo = uicontrol(rfig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03 0.945 0.94 0.045], 'BackgroundColor', bg, ...
        'HorizontalAlignment', 'left', 'FontSize', 10, 'FontWeight', 'bold');

    R.ax = axes('Parent', rfig, 'Units', 'normalized', ...
        'Position', [0.03 0.14 0.61 0.79]);

    % --- Mode crop (untuk Draw baru) ---
    uicontrol(rfig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.66 0.905 0.32 0.03], 'BackgroundColor', bg, ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold', ...
        'String', 'Crop mode (untuk "Draw / Redraw"):');
    initVal = 1;
    if isfield(h, 'cropMode') && strcmpi(h.cropMode, 'square'); initVal = 2; end
    R.popMode = uicontrol(rfig, 'Style', 'popupmenu', 'Units', 'normalized', ...
        'Position', [0.66 0.862 0.32 0.042], 'Value', initVal, ...
        'String', {'Mode 1 - Rectangle crop (apa adanya)', ...
                   'Mode 2 - Polygon squaring (4-titik)'}, ...
        'Callback', @(s,e) local_modeChanged(rfig));

    % --- Daftar folder target (multi-select) ---
    uicontrol(rfig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.66 0.83 0.32 0.028], 'BackgroundColor', bg, ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold', ...
        'String', 'Folder (centang utk "Apply -> SELECTED"):');
    R.lb = uicontrol(rfig, 'Style', 'listbox', 'Units', 'normalized', ...
        'Position', [0.66 0.55 0.32 0.275], 'Max', 2, 'Min', 0, ...
        'String', local_folderNames(h.folders));

    % --- Tombol utama (kanan) ---
    R.btnSaveThis = uicontrol(rfig, 'Style', 'pushbutton', ...
        'String', 'Save ROI -> THIS folder', ...
        'FontWeight', 'bold', 'BackgroundColor', [0.78 0.94 0.96], ...
        'Units', 'normalized', 'Position', [0.66 0.485 0.32 0.055], ...
        'Callback', @(s,e) local_saveThis(rfig));
    uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Apply ROI -> SELECTED (list)', ...
        'Units', 'normalized', 'Position', [0.66 0.43 0.32 0.05], ...
        'Callback', @(s,e) local_apply(rfig, false));
    uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Apply ROI -> ALL folders', ...
        'FontWeight', 'bold', 'BackgroundColor', [0.78 0.94 0.96], ...
        'Units', 'normalized', 'Position', [0.66 0.375 0.32 0.05], ...
        'Callback', @(s,e) local_apply(rfig, true));
    uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Set as ACTIVE crop', ...
        'Units', 'normalized', 'Position', [0.66 0.32 0.32 0.05], ...
        'Callback', @(s,e) local_setActive(rfig));

    % --- Kontrol margin (jarak aman dari tepi) ---
    mEn = local_initMarginEnabled(h);
    mPx = local_initMarginPx(h);
    R.cbMargin = uicontrol(rfig, 'Style', 'checkbox', ...
        'String', 'Safe margin from edge (px):', 'Value', mEn, ...
        'Units', 'normalized', 'Position', [0.66 0.262 0.245 0.045], ...
        'BackgroundColor', bg, 'Callback', @(s,e) local_marginChanged(rfig));
    R.edMargin = uicontrol(rfig, 'Style', 'edit', 'String', num2str(mPx), ...
        'Units', 'normalized', 'Position', [0.915 0.262 0.065 0.045], ...
        'Enable', local_onoff(mEn), 'Callback', @(s,e) local_marginChanged(rfig));

    uicontrol(rfig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.66 0.145 0.32 0.105], 'BackgroundColor', bg, ...
        'HorizontalAlignment', 'left', 'FontSize', 8, ...
        'ForegroundColor', [0.4 0.4 0.4], ...
        'String', ['Mode 2 (squaring): klik 4 sudut objek BERURUTAN ' ...
                   '(kiri-atas, kanan-atas, kanan-bawah, kiri-bawah); gambar ' ...
                   'dipaksa jadi kotak ber-sudut 90 derajat. Mode 1 (rectangle): ' ...
                   'tarik kotak. Backend: stabilisasi -> (squaring) -> crop.']);

    % --- Tombol bawah ---
    uicontrol(rfig, 'Style', 'pushbutton', 'String', '<< Prev', ...
        'Units', 'normalized', 'Position', [0.03 0.04 0.10 0.06], ...
        'Callback', @(s,e) local_nav(rfig, -1));
    uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Next >>', ...
        'Units', 'normalized', 'Position', [0.14 0.04 0.10 0.06], ...
        'Callback', @(s,e) local_nav(rfig, +1));
    R.btnDraw = uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Draw / Redraw ROI', ...
        'BackgroundColor', [0.80 0.92 0.94], ...
        'Units', 'normalized', 'Position', [0.27 0.04 0.18 0.06], ...
        'Callback', @(s,e) local_drawNew(rfig));
    uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Grid preview (all)', ...
        'Units', 'normalized', 'Position', [0.46 0.04 0.16 0.06], ...
        'Callback', @(s,e) local_gridPreview(rfig));
    uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Close', ...
        'Units', 'normalized', 'Position', [0.86 0.04 0.12 0.06], ...
        'Callback', @(s,e) close(rfig));

    guidata(rfig, R);
    local_showFolder(rfig);
end


% =====================================================================
function local_showFolder(rfig)
    R = guidata(rfig);
    h = guidata(R.mainFig);
    n = numel(h.folders);
    if n == 0
        close(rfig);
        return;
    end
    R.idx = max(1, min(R.idx, n));
    f = h.folders(R.idx);
    [~, nm] = fileparts(local_strip(f.path));
    R.folderName = nm;

    img = []; errMsg = '';
    try
        img = imread(fullfile(f.path, f.files{1}));
    catch ME
        errMsg = ME.message;
    end

    cla(R.ax, 'reset');
    R.hROI = []; R.roiMode = '';

    if isempty(img)
        axis(R.ax, 'off');
        text(R.ax, 0.5, 0.5, sprintf('Gagal membaca frame pertama:\n%s', errMsg), ...
            'Units', 'normalized', 'HorizontalAlignment', 'center', ...
            'Color', [0.7 0.2 0.2], 'Interpreter', 'none');
        set(R.txtInfo, 'String', sprintf('Frame %d/%d: %s  (GAGAL BACA)', R.idx, n, nm));
        guidata(rfig, R);
        return;
    end

    R.frameImg  = img;
    R.frameSize = size(img, [1 2]);

    imshow(img, 'Parent', R.ax);
    axes(R.ax);
    hold(R.ax, 'on');

    c = []; src = 'none';
    if isfield(f, 'crop') && ~isempty(f.crop)
        c = f.crop; src = 'folder';
    elseif ~isempty(h.activeCrop)
        c = h.activeCrop; src = 'active';
    end

    margin = local_getMargin(R);
    fitStr = 'belum ada crop ROI - pilih mode lalu "Draw / Redraw ROI"';
    if ~isempty(c)
        [cf, fitInfo] = batchpivprep2.io.cropPreset.fitToImage(c, R.frameSize, margin);
        R.roiMode = batchpivprep2.io.cropPreset.validMode(cf.cropMode);
        if strcmpi(R.roiMode, 'none')
            % Mode 0: tidak ada ROI yang digambar (keluaran = frame penuh).
            R.hROI = [];
            fitStr = 'NONE | tanpa crop (frame penuh)';
        else
            R.hROI = local_drawPresetROI(cf);   % gambar pada current axes (R.ax)
            fitStr = sprintf('%s | %s', upper(R.roiMode), local_fitStatus(fitInfo));
            % Selaraskan popup mode hub ke crop yang sedang tampil.
            local_setPopMode(R.popMode, R.roiMode);
        end
    end
    hold(R.ax, 'off');

    set(R.txtInfo, 'String', sprintf( ...
        'Frame %d/%d: %s   |   %d x %d px (W x H)   |   crop %s   |   %s', ...
        R.idx, n, nm, R.frameSize(2), R.frameSize(1), ...
        local_srcLabel(src), fitStr));

    guidata(rfig, R);
end


% =====================================================================
function hROI = local_drawPresetROI(cf)
%LOCAL_DRAWPRESETROI  Gambar ROI preset (rect/quad) yang bisa di-drag pada
%   axes yang sedang aktif (current axes). Pemanggil wajib sudah meng-set
%   axes target sebagai current (mis. via axes(R.ax)).
    util = pivprep.util.utilities;
    col  = batchpivprep2.io.cropPreset.Color;
    if strcmpi(cf.cropMode, 'square')
        hROI = util.safeDrawPolygon(cf.framePts, col, 'Crop (squaring)');
    else
        r = cf.frameROI;          % [x y w h]
        hROI = util.safeDrawRectangle(r, col, 'Crop (rectangle)');
    end
end


% =====================================================================
function local_endDraw(rfig)
%LOCAL_ENDDRAW  Akhiri sesi gambar: bersihkan flag & aktifkan lagi tombol Draw.
%   Dipanggil via onCleanup sehingga selalu jalan walau draw dibatalkan/error.
    try
        setappdata(rfig, 'isDrawing', false);
        R = guidata(rfig);
        if isstruct(R) && isfield(R, 'btnDraw') && ishandle(R.btnDraw)
            set(R.btnDraw, 'Enable', 'on');
        end
    catch
    end
end


% =====================================================================
function local_clearROIs(ax)
%LOCAL_CLEARROIS  Hapus SEMUA objek ROI (rectangle/polygon) yang masih
%   tersisa di axes, agar tidak pernah ada lebih dari satu ROI.
    try
        kids = ax.Children;
        for i = numel(kids):-1:1
            if isa(kids(i), 'images.roi.Rectangle') || ...
               isa(kids(i), 'images.roi.Polygon')
                delete(kids(i));
            end
        end
    catch
    end
end


% =====================================================================
function local_nav(rfig, delta)
    if getappdata(rfig, 'isDrawing'); return; end   % jangan pindah saat menggambar
    R = guidata(rfig);
    R.idx = R.idx + delta;
    guidata(rfig, R);
    local_showFolder(rfig);
end


% =====================================================================
function local_modeChanged(rfig)
%LOCAL_MODECHANGED  Simpan mode aktif ke appdata utama (utk Draw baru).
    R = guidata(rfig);
    m = local_popMode(R.popMode);
    h = guidata(R.mainFig);
    h.cropMode = m;
    if isfield(h, 'popCropMode') && ishandle(h.popCropMode)
        set(h.popCropMode, 'Value', local_mainPopVal(m));
    end
    guidata(R.mainFig, h);
end


% =====================================================================
function v = local_mainPopVal(m)
%LOCAL_MAINPOPVAL  Mode -> Value popup Crop mode JENDELA UTAMA
%   (1='none', 2='crop', 3='square'). Hub ini hanya menggambar crop/square.
    switch lower(char(m))
        case 'none';   v = 1;
        case 'square'; v = 3;
        otherwise;     v = 2;
    end
end


% =====================================================================
function local_drawNew(rfig)
    % Cegah ROI ganda: abaikan klik "Draw" berikutnya selagi satu sesi
    % gambar masih berjalan (re-entrant) -- tombol juga di-nonaktifkan.
    if getappdata(rfig, 'isDrawing'); return; end
    R = guidata(rfig);
    if isempty(R.frameImg)
        warndlg('Tidak ada frame untuk digambar.', 'BatchPIVPrep2');
        return;
    end

    % Hanya boleh SATU ROI: hapus handle lama + sisa objek ROI di axes.
    if ~isempty(R.hROI) && isvalid(R.hROI)
        delete(R.hROI);
    end
    R.hROI = [];
    local_clearROIs(R.ax);

    setappdata(rfig, 'isDrawing', true);
    if isfield(R, 'btnDraw') && ishandle(R.btnDraw)
        set(R.btnDraw, 'Enable', 'off');
    end
    guidata(rfig, R);
    cleaner = onCleanup(@() local_endDraw(rfig));   %#ok<NASGU>

    util = pivprep.util.utilities;
    col  = batchpivprep2.io.cropPreset.Color;
    mode = local_popMode(R.popMode);
    R.roiMode = mode;

    axes(R.ax);
    if strcmpi(mode, 'square')
        set(R.txtInfo, 'String', sprintf( ...
            ['Mode SQUARING di "%s": klik 4 sudut BERURUTAN (kiri-atas, kanan-atas, ' ...
             'kanan-bawah, kiri-bawah), double-click utk selesai.'], R.folderName));
        try
            % Posisi KOSONG ([]) -> masuk mode MENGGAMBAR interaktif (klik
            % titik), sama seperti hub anchor (viewFirstFrames). ROI yang
            % dibuat ber-'Position' default lalu wait() TIDAK bisa di-ambil/
            % di-edit di R2026a -- itu sumber bug "ga bisa ambil ROI".
            hROI = util.safeDrawPolygon([], col, 'Crop (squaring)');
            wait(hROI);
        catch
            hROI = [];
        end
    else
        set(R.txtInfo, 'String', sprintf( ...
            ['Mode RECTANGLE di "%s": klik-seret untuk menggambar kotak baru; ' ...
             'double-click utk selesai.'], R.folderName));
        try
            hROI = util.safeDrawRectangle([], col, 'Crop (rectangle)');
            wait(hROI);
        catch
            hROI = [];
        end
    end

    okPts = ~isempty(hROI) && isvalid(hROI);
    if okPts && strcmpi(mode, 'square')
        okPts = size(hROI.Position, 1) >= 4;   % squaring wajib >= 4 sudut
    end
    if okPts
        R.hROI = hROI;
        set(R.txtInfo, 'String', sprintf( ...
            ['ROI %s baru di "%s". Lalu: "Save ROI -> THIS folder", "Apply -> ' ...
             'ALL/SELECTED", atau "Set as ACTIVE crop".'], upper(mode), R.folderName));
    else
        if ~isempty(hROI) && isvalid(hROI); delete(hROI); end
        R.hROI = [];
        if strcmpi(mode, 'square')
            set(R.txtInfo, 'String', ...
                'Dibatalkan / mode squaring perlu 4 sudut.');
        else
            set(R.txtInfo, 'String', 'Penggambaran dibatalkan.');
        end
    end
    guidata(rfig, R);
end


% =====================================================================
function preset = local_buildPreset(rfig)
%LOCAL_BUILDPRESET  Bangun preset crop dari ROI yang SEDANG TAMPIL.
    preset = [];
    R = guidata(rfig);
    if isempty(R.hROI) || ~isvalid(R.hROI)
        warndlg('Belum ada ROI di frame ini. Klik "Draw / Redraw ROI" dulu.', ...
            'BatchPIVPrep2');
        return;
    end
    util = pivprep.util.utilities;
    mode = batchpivprep2.io.cropPreset.validMode(R.roiMode);

    pos = R.hROI.Position;
    if strcmpi(mode, 'square')
        pts = batchpivprep2.io.cropPreset.coerceQuad(pos);
        if isempty(pts); return; end
    else
        % rectangle: Position = [x y w h]
        if numel(pos) ~= 4
            warndlg('ROI rectangle tidak valid.', 'BatchPIVPrep2');
            return;
        end
        pts = util.rectToCorners(pos);
    end

    preset = batchpivprep2.io.cropPreset.fromPoints( ...
        pts, R.frameSize, mode, R.frameImg, ...
        sprintf('crop-%s', R.folderName), '');
end


% =====================================================================
function local_saveThis(rfig)
%LOCAL_SAVETHIS  Simpan ROI yang tampil sbg crop folder yang SEDANG TAMPIL.
    preset = local_buildPreset(rfig);
    if isempty(preset); return; end
    R = guidata(rfig);
    h = guidata(R.mainFig);
    n = numel(h.folders);
    if R.idx < 1 || R.idx > n; return; end

    h.folders(R.idx).crop     = preset;
    h.folders(R.idx).cropName = preset.name;
    % Ingat ROI ini sebagai crop AKTIF -> tetap muncul saat pindah folder,
    % sehingga bisa langsung "Save -> THIS folder" lagi utk folder/eksperimen
    % lain TANPA harus menggambar ulang.
    h.activeCrop = preset;
    h.cropMode   = batchpivprep2.io.cropPreset.validMode(preset.cropMode);
    guidata(R.mainFig, h);
    batchpivprep2.ui.refreshFolderTable(R.mainFig);
    local_syncMainCropPreview(R.mainFig, preset);
    local_refreshList(rfig);

    set(R.txtInfo, 'String', sprintf( ...
        'ROI crop disimpan utk folder INI & jadi crop AKTIF: "%s" [%s]  (folder %d/%d).', ...
        R.folderName, upper(preset.cropMode), R.idx, n));
    local_showFolder(rfig);
end


% =====================================================================
function local_apply(rfig, toAll)
%LOCAL_APPLY  Sebarkan ROI yang tampil ke ALL / SELECTED (listbox).
    preset = local_buildPreset(rfig);
    if isempty(preset); return; end

    R = guidata(rfig);
    h = guidata(R.mainFig);
    n = numel(h.folders);

    if toAll
        rows = 1:n;
    else
        rows = get(R.lb, 'Value');
        rows = rows(rows >= 1 & rows <= n);
        if isempty(rows)
            warndlg('Centang dulu folder target di daftar (multi-select).', ...
                'BatchPIVPrep2');
            return;
        end
    end

    for r = rows
        h.folders(r).crop     = preset;
        h.folders(r).cropName = preset.name;
    end
    h.activeCrop = preset;
    h.cropMode   = batchpivprep2.io.cropPreset.validMode(preset.cropMode);
    guidata(R.mainFig, h);
    batchpivprep2.ui.refreshFolderTable(R.mainFig);
    local_syncMainCropPreview(R.mainFig, preset);
    local_refreshList(rfig);

    if toAll
        set(R.txtInfo, 'String', sprintf( ...
            'Crop "%s" [%s] di-apply ke SEMUA %d folder.', ...
            preset.name, upper(preset.cropMode), n));
    else
        set(R.txtInfo, 'String', sprintf( ...
            'Crop "%s" [%s] di-apply ke %d folder terpilih.', ...
            preset.name, upper(preset.cropMode), numel(rows)));
    end
end


% =====================================================================
function local_setActive(rfig)
    preset = local_buildPreset(rfig);
    if isempty(preset); return; end
    R = guidata(rfig);
    h = guidata(R.mainFig);
    h.activeCrop = preset;
    h.cropMode   = batchpivprep2.io.cropPreset.validMode(preset.cropMode);
    guidata(R.mainFig, h);
    local_syncMainCropPreview(R.mainFig, preset);
    set(R.txtInfo, 'String', sprintf( ...
        'Crop "%s" [%s] dijadikan CROP AKTIF (tampil di jendela utama).', ...
        preset.name, upper(preset.cropMode)));
end


% =====================================================================
function local_marginChanged(rfig)
    R  = guidata(rfig);
    en = logical(get(R.cbMargin, 'Value'));
    val = str2double(get(R.edMargin, 'String'));
    if isnan(val) || val < 0
        val = 0;
        set(R.edMargin, 'String', '0');
    end
    set(R.edMargin, 'Enable', local_onoff(en));

    h = guidata(R.mainFig);
    h.marginEnabled = en;
    h.marginPx      = val;
    guidata(R.mainFig, h);

    local_showFolder(rfig);
end


% =====================================================================
function local_gridPreview(rfig)
    R = guidata(rfig);
    h = guidata(R.mainFig);
    folders = h.folders;

    maxShow = 16; nOrig = numel(folders); truncated = false;
    if nOrig > maxShow
        truncated = true; folders = folders(1:maxShow);
    end
    n = numel(folders);
    cols = ceil(sqrt(n)); rows = ceil(n / cols);

    fg = figure('Name', 'BatchPIVPrep2 - First Frames + Crop ROI (grid)', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Units', 'normalized', 'Position', [0.08 0.08 0.84 0.84]);
    try                                  % paksa tema TERANG
        theme(fg, 'light');
    catch
    end
    col = batchpivprep2.io.cropPreset.Color;
    for i = 1:n
        ax = subplot(rows, cols, i, 'Parent', fg);
        f  = folders(i);
        [~, nm] = fileparts(local_strip(f.path));
        try
            img = imread(fullfile(f.path, f.files{1}));
            imshow(img, 'Parent', ax);
            hold(ax, 'on');
            cc = [];
            if isfield(f, 'crop') && ~isempty(f.crop); cc = f.crop;
            elseif ~isempty(h.activeCrop);             cc = h.activeCrop; end
            if ~isempty(cc)
                cf = batchpivprep2.io.cropPreset.fitToImage(cc, size(img, [1 2]), 0);
                p  = cf.framePts;
                plot(ax, [p(:,1); p(1,1)], [p(:,2); p(1,2)], '-', ...
                    'Color', col, 'LineWidth', 1.4);
            end
            hold(ax, 'off');
            title(ax, sprintf('%s (%dx%d)', nm, size(img,2), size(img,1)), ...
                'Interpreter', 'none', 'FontSize', 9);
        catch ME
            axis(ax, 'off');
            text(ax, 0.5, 0.5, sprintf('%s\n(gagal: %s)', nm, ME.message), ...
                'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                'Color', [0.7 0.2 0.2], 'Interpreter', 'none', 'FontSize', 8);
        end
    end
    if truncated
        try
            sgtitle(fg, sprintf('Menampilkan %d folder pertama (dari %d).', ...
                maxShow, nOrig), 'Color', [0.6 0.3 0.1]);
        catch
        end
    end
end


% =====================================================================
% Helpers
% =====================================================================
function local_refreshList(rfig)
    R = guidata(rfig);
    h = guidata(R.mainFig);
    n = numel(h.folders);
    val = get(R.lb, 'Value');
    set(R.lb, 'String', local_folderNames(h.folders));
    set(R.lb, 'Value', val(val >= 1 & val <= n));
end


function local_syncMainCropPreview(mainFig, preset)
    h = guidata(mainFig);
    if isfield(h, 'axCropPreview') && ishandle(h.axCropPreview)
        batchpivprep2.io.cropPreset.displayInAxes(preset, h.axCropPreview);
        set(h.txtCropInfo, 'String', ...
            batchpivprep2.io.cropPreset.summaryText(preset));
    end
    if isfield(h, 'popCropMode') && ishandle(h.popCropMode)
        set(h.popCropMode, 'Value', local_mainPopVal(preset.cropMode));
    end
end


function m = local_popMode(popHandle)
    if get(popHandle, 'Value') == 2; m = 'square'; else; m = 'crop'; end
end


function local_setPopMode(popHandle, mode)
    if strcmpi(mode, 'square'); set(popHandle, 'Value', 2);
    else;                       set(popHandle, 'Value', 1); end
end


function m = local_getMargin(R)
    m = 0;
    if isfield(R, 'cbMargin') && ishandle(R.cbMargin) && get(R.cbMargin, 'Value')
        m = str2double(get(R.edMargin, 'String'));
        if isnan(m) || m < 0; m = 0; end
    end
end


function en = local_initMarginEnabled(h)
    en = true;
    if isfield(h, 'marginEnabled') && ~isempty(h.marginEnabled)
        en = logical(h.marginEnabled);
    end
end


function px = local_initMarginPx(h)
    px = 10;
    if isfield(h, 'marginPx') && ~isempty(h.marginPx)
        px = h.marginPx;
    end
end


function s = local_onoff(tf)
    if tf; s = 'on'; else; s = 'off'; end
end


function names = local_folderNames(folders)
    n = numel(folders);
    names = cell(n, 1);
    for i = 1:n
        [~, nm] = fileparts(local_strip(folders(i).path));
        if isfield(folders(i), 'crop') && ~isempty(folders(i).crop)
            mk = folders(i).crop.cropMode;
            mark = sprintf('[crop:%s]', upper(mk));
        else
            mark = '[-]';
        end
        names{i} = sprintf('%2d. %s  %s', i, nm, mark);
    end
end


function s = local_fitStatus(info)
    switch info.status
        case 'ok'
            s = sprintf('posisi OK (identik, jarak >= %dpx dari tepi)', info.margin);
        case 'shifted'
            s = sprintf('DISESUAIKAN: digeser [%.0f %.0f] px ke dalam', ...
                info.shift(1), info.shift(2));
        case 'shrunk'
            s = sprintf('DISESUAIKAN: diperkecil x%.3f agar muat', info.scale);
        otherwise
            s = sprintf('DISESUAIKAN: diperkecil x%.3f + digeser [%.0f %.0f] px', ...
                info.scale, info.shift(1), info.shift(2));
    end
end


function s = local_srcLabel(src)
    switch src
        case 'folder', s = '(dari folder)';
        case 'active', s = '(dari crop aktif)';
        otherwise,     s = '(belum ada)';
    end
end


function p = local_strip(p)
    if ~isempty(p) && (p(end) == filesep || p(end) == '/'); p(end) = []; end
end
