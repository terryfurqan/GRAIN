function viewFirstFrames(mainFig)
%VIEWFIRSTFRAMES  Jendela HUB anchor STABILISASI: gambar / apply / periksa / edit.
%
%   batchpivprep2.ui.viewFirstFrames(mainFig)
%
%   Satu jendela untuk seluruh alur kerja anchor stabilisasi (identik dgn
%   versi 1):
%     1. Navigasi frame pertama tiap folder (Prev / Next).
%     2. "Draw / Redraw polygon": gambar polygon anchor di frame yang tampil.
%        Polygon yang sudah ada juga bisa langsung DI-DRAG untuk diedit.
%     3. "Apply ROI -> ALL / SELECTED": sebarkan ke banyak folder.
%     4. "Save ROI -> THIS folder": simpan sbg anchor folder yang SEDANG TAMPIL.
%     5. Kontrol "Safe margin": jarak aman titik dari tepi (dipakai juga saat Run).
%
%   Anchor stabilisasi diambil dari gambar yang BELUM di-crop.

    h = guidata(mainFig);
    if isempty(h.folders)
        warndlg('Belum ada folder di daftar.', 'BatchPIVPrep2');
        return;
    end

    bg = [0.96 0.96 0.96];
    rfig = figure( ...
        'Name', 'BatchPIVPrep2 - Anchor STABILISASI: Draw / Apply / Check / Edit', ...
        'NumberTitle', 'off', 'Color', bg, ...
        'MenuBar', 'none', 'ToolBar', 'figure', ...
        'Units', 'pixels', 'Position', [90 60 1120 760]);
    try                                  % paksa tema TERANG (abaikan dark mode OS)
        theme(rfig, 'light');
    catch
    end

    R = struct('mainFig', mainFig, 'idx', 1, 'hPoly', [], ...
        'frameImg', [], 'frameSize', [], 'folderName', '');

    R.txtInfo = uicontrol(rfig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03 0.945 0.94 0.045], 'BackgroundColor', bg, ...
        'HorizontalAlignment', 'left', 'FontSize', 10, 'FontWeight', 'bold');

    R.ax = axes('Parent', rfig, 'Units', 'normalized', ...
        'Position', [0.03 0.14 0.61 0.79]);

    % --- Daftar folder target (multi-select) ---
    uicontrol(rfig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.66 0.905 0.32 0.03], 'BackgroundColor', bg, ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold', ...
        'String', 'Folder (centang utk "Apply -> SELECTED"):');
    R.lb = uicontrol(rfig, 'Style', 'listbox', 'Units', 'normalized', ...
        'Position', [0.66 0.55 0.32 0.355], 'Max', 2, 'Min', 0, ...
        'String', local_folderNames(h.folders));

    % --- Tombol utama (kanan) ---
    R.btnSaveThis = uicontrol(rfig, 'Style', 'pushbutton', ...
        'String', 'Save ROI -> THIS folder', ...
        'FontWeight', 'bold', 'BackgroundColor', [0.95 0.92 0.70], ...
        'Units', 'normalized', 'Position', [0.66 0.485 0.32 0.055], ...
        'Callback', @(s,e) local_saveThis(rfig));
    uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Apply ROI -> SELECTED (list)', ...
        'Units', 'normalized', 'Position', [0.66 0.43 0.32 0.05], ...
        'Callback', @(s,e) local_apply(rfig, false));
    uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Apply ROI -> ALL folders', ...
        'FontWeight', 'bold', 'BackgroundColor', [0.92 0.90 0.70], ...
        'Units', 'normalized', 'Position', [0.66 0.375 0.32 0.05], ...
        'Callback', @(s,e) local_apply(rfig, true));
    uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Set as ACTIVE anchor', ...
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
        'String', ['Alur: "Draw" gambar ROI -> "Apply -> ALL/SELECTED" sebar ' ...
                   'ke folder -> periksa tiap folder (Prev/Next) -> bila perlu ' ...
                   'DRAG titik ROI lalu "Save ROI -> THIS folder" (folder yang ' ...
                   'SEDANG TAMPIL). Margin menjaga titik tidak mepet tepi.']);

    % --- Tombol bawah: navigasi / gambar / grid / close ---
    uicontrol(rfig, 'Style', 'pushbutton', 'String', '<< Prev', ...
        'Units', 'normalized', 'Position', [0.03 0.04 0.10 0.06], ...
        'Callback', @(s,e) local_nav(rfig, -1));
    uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Next >>', ...
        'Units', 'normalized', 'Position', [0.14 0.04 0.10 0.06], ...
        'Callback', @(s,e) local_nav(rfig, +1));
    R.btnDraw = uicontrol(rfig, 'Style', 'pushbutton', 'String', 'Draw / Redraw polygon', ...
        'BackgroundColor', [0.92 0.90 0.80], ...
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
    R.hPoly = [];

    if isempty(img)
        axis(R.ax, 'off');
        text(R.ax, 0.5, 0.5, sprintf('Gagal membaca frame pertama:\n%s', errMsg), ...
            'Units', 'normalized', 'HorizontalAlignment', 'center', ...
            'Color', [0.7 0.2 0.2], 'Interpreter', 'none');
        set(R.txtInfo, 'String', sprintf('Frame %d/%d: %s  (GAGAL BACA)', ...
            R.idx, n, nm));
        guidata(rfig, R);
        return;
    end

    R.frameImg  = img;
    R.frameSize = size(img, [1 2]);

    imshow(img, 'Parent', R.ax);
    axes(R.ax);
    hold(R.ax, 'on');

    a = []; src = 'none';
    if ~isempty(f.anchor)
        a = f.anchor; src = 'folder';
    elseif ~isempty(h.activeAnchor)
        a = h.activeAnchor; src = 'active';
    end

    margin = local_getMargin(R);
    fitStr = 'belum ada anchor - klik "Draw / Redraw polygon"';
    if ~isempty(a)
        [ap, fitInfo] = batchpivprep2.io.anchorPreset.fitToImage(a, R.frameSize, margin);
        pts = ap.anchorPts;
        R.hPoly = pivprep.util.utilities.safeDrawPolygon(pts, 'y', 'Anchor');
        fitStr  = local_fitStatus(fitInfo);
    end
    hold(R.ax, 'off');

    set(R.txtInfo, 'String', sprintf( ...
        'Frame %d/%d: %s   |   %d x %d px (W x H)   |   anchor %s   |   %s', ...
        R.idx, n, nm, R.frameSize(2), R.frameSize(1), ...
        local_srcLabel(src), fitStr));

    guidata(rfig, R);
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
function local_drawNew(rfig)
    % Cegah polygon ganda: abaikan klik "Draw" berikutnya selagi satu sesi
    % gambar masih berjalan (re-entrant) -- tombol juga di-nonaktifkan.
    if getappdata(rfig, 'isDrawing'); return; end
    R = guidata(rfig);
    if isempty(R.frameImg)
        warndlg('Tidak ada frame untuk digambar.', 'BatchPIVPrep2');
        return;
    end

    % Hanya boleh SATU polygon: hapus handle lama + sisa objek ROI di axes.
    if ~isempty(R.hPoly) && isvalid(R.hPoly)
        delete(R.hPoly);
    end
    R.hPoly = [];
    local_clearROIs(R.ax);

    setappdata(rfig, 'isDrawing', true);
    if isfield(R, 'btnDraw') && ishandle(R.btnDraw)
        set(R.btnDraw, 'Enable', 'off');
    end
    guidata(rfig, R);
    cleaner = onCleanup(@() local_endDraw(rfig));   %#ok<NASGU>

    axes(R.ax);
    set(R.txtInfo, 'String', sprintf( ...
        'Gambar polygon anchor di frame "%s": klik titik-titik, double-click untuk selesai.', ...
        R.folderName));

    try
        hPoly = pivprep.util.utilities.safeDrawPolygon([], 'y', 'Anchor');
        wait(hPoly);
    catch
        hPoly = [];
    end

    if ~isempty(hPoly) && isvalid(hPoly) && size(hPoly.Position, 1) >= 3
        R.hPoly = hPoly;
        set(R.txtInfo, 'String', sprintf( ...
            ['Polygon baru (%d titik) di "%s". Lalu: "Save ROI -> THIS folder", ' ...
             'atau "Apply -> ALL/SELECTED", atau "Set as ACTIVE anchor".'], ...
            size(hPoly.Position, 1), R.folderName));
    else
        if ~isempty(hPoly) && isvalid(hPoly); delete(hPoly); end
        R.hPoly = [];
        set(R.txtInfo, 'String', 'Penggambaran dibatalkan / polygon < 3 titik.');
    end
    guidata(rfig, R);
end


% =====================================================================
function preset = local_buildPreset(rfig)
%LOCAL_BUILDPRESET  Bangun preset anchor dari polygon yang SEDANG TAMPIL.
    preset = [];
    R = guidata(rfig);
    if isempty(R.hPoly) || ~isvalid(R.hPoly)
        warndlg(['Belum ada polygon di frame ini. Klik "Draw / Redraw ' ...
                 'polygon" dulu.'], 'BatchPIVPrep2');
        return;
    end
    pts = R.hPoly.Position;
    if size(pts, 1) < 3
        warndlg('Polygon minimal 3 titik.', 'BatchPIVPrep2');
        return;
    end
    h = guidata(R.mainFig);
    methodList = {'surf', 'phasecorr'};
    method = methodList{get(h.popStabMethod, 'Value')};
    preset = batchpivprep2.io.anchorPreset.fromPoints( ...
        pts, R.frameSize, method, R.frameImg, ...
        sprintf('anchor-%s', R.folderName), '');
end


% =====================================================================
function local_saveThis(rfig)
%LOCAL_SAVETHIS  Simpan ROI yang tampil sbg anchor folder yang SEDANG TAMPIL.
    preset = local_buildPreset(rfig);
    if isempty(preset); return; end
    R = guidata(rfig);
    h = guidata(R.mainFig);
    n = numel(h.folders);
    if R.idx < 1 || R.idx > n; return; end

    h.folders(R.idx).anchor     = preset;
    h.folders(R.idx).anchorName = preset.name;
    % Ingat ROI ini sebagai anchor AKTIF -> tetap muncul saat pindah folder,
    % sehingga bisa langsung "Save -> THIS folder" lagi utk folder/eksperimen
    % lain TANPA harus menggambar ulang.
    h.activeAnchor = preset;
    guidata(R.mainFig, h);
    batchpivprep2.ui.refreshFolderTable(R.mainFig);
    local_syncMainPreview(R.mainFig, preset);
    local_refreshList(rfig);

    set(R.txtInfo, 'String', sprintf( ...
        'ROI disimpan utk folder INI & jadi anchor AKTIF: "%s"  (folder %d/%d).', ...
        R.folderName, R.idx, n));
    local_showFolder(rfig);
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
%LOCAL_CLEARROIS  Hapus SEMUA objek ROI (polygon/rectangle) yang masih
%   tersisa di axes, agar tidak pernah ada lebih dari satu ROI.
    try
        kids = ax.Children;
        for i = numel(kids):-1:1
            if isa(kids(i), 'images.roi.Polygon') || ...
               isa(kids(i), 'images.roi.Rectangle')
                delete(kids(i));
            end
        end
    catch
    end
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
        h.folders(r).anchor     = preset;
        h.folders(r).anchorName = preset.name;
    end
    h.activeAnchor = preset;
    guidata(R.mainFig, h);
    batchpivprep2.ui.refreshFolderTable(R.mainFig);
    local_syncMainPreview(R.mainFig, preset);
    local_refreshList(rfig);

    if toAll
        set(R.txtInfo, 'String', sprintf( ...
            'Anchor "%s" di-apply ke SEMUA %d folder.', preset.name, n));
    else
        set(R.txtInfo, 'String', sprintf( ...
            'Anchor "%s" di-apply ke %d folder terpilih.', preset.name, numel(rows)));
    end
end


% =====================================================================
function local_setActive(rfig)
    preset = local_buildPreset(rfig);
    if isempty(preset); return; end
    R = guidata(rfig);
    h = guidata(R.mainFig);
    h.activeAnchor = preset;
    guidata(R.mainFig, h);
    local_syncMainPreview(R.mainFig, preset);
    set(R.txtInfo, 'String', sprintf( ...
        'Anchor "%s" dijadikan ANCHOR AKTIF (tampil di jendela utama).', preset.name));
end


% =====================================================================
function local_marginChanged(rfig)
%LOCAL_MARGINCHANGED  Simpan setelan margin ke appdata utama + render ulang.
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
%LOCAL_GRIDPREVIEW  Pratinjau cepat semua frame pertama dalam grid.
    R = guidata(rfig);
    h = guidata(R.mainFig);
    folders = h.folders;

    maxShow = 16; nOrig = numel(folders); truncated = false;
    if nOrig > maxShow
        truncated = true; folders = folders(1:maxShow);
    end
    n = numel(folders);
    cols = ceil(sqrt(n)); rows = ceil(n / cols);

    fg = figure('Name', 'BatchPIVPrep2 - First Frames (grid)', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Units', 'normalized', 'Position', [0.08 0.08 0.84 0.84]);
    try                                  % paksa tema TERANG
        theme(fg, 'light');
    catch
    end
    for i = 1:n
        ax = subplot(rows, cols, i, 'Parent', fg);
        f  = folders(i);
        [~, nm] = fileparts(local_strip(f.path));
        try
            img = imread(fullfile(f.path, f.files{1}));
            imshow(img, 'Parent', ax);
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


function local_syncMainPreview(mainFig, preset)
    h = guidata(mainFig);
    if isfield(h, 'axPreview') && ishandle(h.axPreview)
        batchpivprep2.io.anchorPreset.displayInAxes(preset, h.axPreview);
        set(h.txtAnchorInfo, 'String', ...
            batchpivprep2.io.anchorPreset.summaryText(preset));
    end
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
        if ~isempty(folders(i).anchor)
            mark = '[anchor]';
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
            s = sprintf('DISESUAIKAN: digeser [%.0f %.0f] px ke dalam (aman %dpx dari tepi)', ...
                info.shift(1), info.shift(2), info.margin);
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
        case 'active', s = '(dari anchor aktif)';
        otherwise,     s = '(belum ada)';
    end
end


function p = local_strip(p)
    if ~isempty(p) && (p(end) == filesep || p(end) == '/'); p(end) = []; end
end
