function GRAINEXPORT(rootDir, grainRoot)
%GRAINEXPORT  GRAIN Exporter — WYSIWYG editor + KATALOG gambar AX main (velmag+shear).
%
%   GRAINEXPORT                % dialog pilih folder .mat PIV (output Step 2)
%   GRAINEXPORT(rootDir)       % langsung ke folder ROOT
%   GRAINEXPORT(rootDir,grainRoot)% override folder induk katalog (default = folder GRAIN/)
%
%   Modul STANDALONE (1 file GUI). Pola WYSIWYG ala GRAIN4/GRAINAXPOT: LIHAT DULU
%   gambar AX main yang akan diproduksi di KANVAS (1 bingkai aktif + slider,
%   tukar velmag<->shear), ATUR tata letak & setelan render sampai puas, BARU
%   tombol EXPORT di akhir -> render SEMUA bingkai eksperimen aktif ke katalog.
%   "what you see = what you get": kanvas & berkas memakai renderer BERSAMA
%   (pivcore.export.frameCatalog.drawScalarPanel).
%
%   SETELAN:
%     - GLOBAL (ke FILE, lintas-sesi via setpref 'GRAINEXPORT'): gaya render rumah
%       = DPI, kualitas JPEG, ukuran kanvas cm, toggle GS/glyph/CLAHE/auto,
%       dekorasi (garis PSG/colorbar/judul). Tombol "⭐ Jadikan default".
%     - SESSION (hilang saat tutup): eksperimen tercentang, frame aktif, skalar
%       tampil, CLim per-exp (auto dari indenter), garis PSG (auto).
%
%   STRUKTUR OUTPUT (di root GRAIN/):
%       PAB_export/<exp>/velmag/<exp>_velmag_f001.jpg ...
%       PAB_export/<exp>/shear/ <exp>_shear_f001.jpg  ...
%       PAB_export/<exp>/manifest.json + PAB_export/_catalog.json (indeks global)
%
%   KONTRAK IMMUTABLE: GRAIN Exporter SATU-SATUNYA penulis folder katalog. User
%   sebaiknya HANYA mengkopi keluar. Export selalu regenerate BERSIH (purge).
%   Garis PSG & CLim AUTO: _potdata.json (GRAIN4) -> _autopot (GRAIN3a) -> autoPSG
%   75% + CLim |V| indenter-max. Tema TERANG. Lihat [[grainexport-catalog]].

    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivcore.export.frameCatalog'))
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
    end

    if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
        rootDir = uigetdir(pwd, ...
            'Pilih folder berisi .mat PIV (output Step 2 / PIV_<tgl>/)');
        if isequal(rootDir, 0), return; end
    end

    h = struct();
    h.root    = rootDir;     % folder sumber .mat PIV
    if nargin >= 2 && ~isempty(grainRoot) && ischar(grainRoot)
        h.grainRoot = grainRoot; % override (tes / lokasi katalog kustom)
    else
        h.grainRoot = here;    % induk folder katalog (GRAIN/) -> PAB_export/
    end
    h.list    = struct('name',{},'file',{},'sizeMB',{},'nFrames',{}, ...
                       'sel',{},'status',{},'count',{});
    h.busy    = false;
    h.cancel  = false;

    % --- SESSION state (per-exp; hilang saat tutup) ---
    h.activeRow = 0;
    h.realData  = '';
    h.data      = [];        % dataset aktif (bingkai-1 ringan / penuh)
    h.fullLoaded= false;
    h.imgFrames = 1;
    h.nF        = 1;
    h.frame     = 1;
    h.scalar    = 'velmag';  % skalar tampil di kanvas: 'velmag' | 'shear'
    h.resolve   = [];        % hasil resolveRender exp aktif (line/clim/...)

    % --- GLOBAL setelan (default; ditimpa pref bila ada) ---
    h.g = i_defaultGlobal();
    h.g = i_loadGlobalPref(h.g);

    h = i_buildUI(h);
    guidata(h.fig, h);
    i_applyGlobalToControls(h.fig);
    i_rescan(h.fig);
    i_loadProgress(h.fig);   % pulihkan progres sesi (centang + setelan) bila ada
end


% =====================================================================
% SETELAN GLOBAL (ke FILE lintas-sesi)
% =====================================================================
function g = i_defaultGlobal()
    pD = pivcore.util.glyphDefaults();
    g = struct();
    g.dpi        = 200;          % cukup jelas + ringan (paper bila perlu naikkan)
    g.jpegQ      = 80;           % q80 = file kecil, kualitas masih jelas
    g.maxLongPx  = 2000;         % batas sisi-panjang piksel (cegah file raksasa/hang)
    g.widthCm    = 18;           % ukuran kanvas fisik (preview & relatif ekspor)
    g.heightCm   = 10;
    g.gsOn       = true;
    g.glyphOn    = true;
    g.claheOn    = true;
    g.adjOn      = true;
    g.gsAlpha    = 0.5;
    g.glyphLW    = pD.lineWidth;
    g.glyphSp    = pD.spacing;
    g.glyphColor = [0 0 0];      % warna panah glyph (velmag): hitam
    g.glyphColorShear = [1 1 1]; % warna panah glyph KHUSUS shear: putih (beda)
    g.tickPx     = true;         % tampilkan tickmark posisi pixel (XTick/YTick)
    g.showPSG    = true;         % dekorasi: garis PSG oranye
    g.showColorbar = true;
    g.showTitle  = true;         % judul = nama eksperimen
    g.strainShow = true;         % caption strain kiri-bawah
    g.strainPosX = 0.02;         % posisi caption (normalized x)
    g.strainPosY = 0.04;         % posisi caption (normalized y)
    g.strainColor = [0 0 0];     % warna tulisan caption
    g.strainBg   = [1 1 1];      % warna latar caption
    g.multSource = 'manual';     % sumber multiplier: 'manual'|'calxy'|'geom'
    g.doVel      = true;         % skalar mana yang DIEKSPOR (kanvas tampil 1 saja)
    g.doShear    = true;
    g.parallel   = false;        % ⚡ export paralel (parfor); default OFF (serial-reuse sdh 2.6x)
    g.maxWorkers = 5;            % worker bila paralel (user: 5 biar tak berat)
    % Satuan vel mag -> cm/s (override). velMult dipakai bila velUnit='cms'.
    g.velUnit    = 'pxframe';    % 'pxframe' | 'cms'
    g.velMult    = 1;            % pengali |V| px/frame -> cm/s
    g.cmPerPx    = NaN;          % skala spasial (cm/px) — input override
    g.dtSec      = NaN;          % dt detik/frame — input override (auto EXIF)
end

function g = i_loadGlobalPref(g)
    try
        if ispref('GRAINEXPORT','global')
            p = getpref('GRAINEXPORT','global');
            f = fieldnames(g);
            for i = 1:numel(f)
                if isfield(p, f{i}) && ~isempty(p.(f{i})), g.(f{i}) = p.(f{i}); end
            end
        end
    catch
    end
end

function i_onSaveGlobal(fig)
    h = guidata(fig);
    i_readControlsToGlobal(fig); h = guidata(fig);
    try
        setpref('GRAINEXPORT','global', h.g);
        i_status(fig, '⭐ Setelan render disimpan sebagai DEFAULT (lintas-sesi).');
    catch ME
        i_status(fig, sprintf('Gagal simpan default: %s', ME.message));
    end
end

function i_onResetGlobal(fig)
    h = guidata(fig);
    h.g = i_defaultGlobal(); guidata(fig, h);
    i_applyGlobalToControls(fig);
    i_apply(fig);
    i_status(fig, 'Setelan render dikembalikan ke bawaan pabrik (belum disimpan).');
end


% =====================================================================
% UI (tema TERANG dipaksa) — 3 kolom: KIRI exp+slider, TENGAH kanvas, KANAN set
% =====================================================================
function h = i_buildUI(h)
    WHITE = [1 1 1];
    vis = 'on'; if pivui.quiet(), vis = 'off'; end
    h.fig = figure('Name',pivui.titleWithVersion('GRAIN Exporter — WYSIWYG gambar AX main (velmag + shear)'), ...
        'NumberTitle','off','Color',WHITE, ...
        'Units','pixels','Position',[40 40 1380 800], ...
        'MenuBar','none','ToolBar','none','Visible',vis, ...
        'CloseRequestFcn',@(s,e) i_onClose(s));
    pivui.forceLightTheme(h.fig);
    fig = h.fig;

    % --- Panel KIRI: sumber + tabel exp (centang) ---------------------
    pnlL = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.005 0.01 0.215 0.985],'Title','Eksperimen (.mat PIV)', ...
        'FontWeight','bold','BackgroundColor',WHITE);
    h.txtRoot = uicontrol('Parent',pnlL,'Style','text', ...
        'Units','normalized','Position',[0.03 0.955 0.94 0.035], ...
        'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'String',h.root);
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.905 0.46 0.045],'String','Pilih Folder…', ...
        'Callback',@(s,e) i_onPickFolder(fig));
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.905 0.46 0.045],'String','Segarkan', ...
        'TooltipString','Pindai ulang + status katalog.', ...
        'Callback',@(s,e) i_rescan(fig));
    h.tbl = uitable('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.07 0.94 0.825], ...
        'ColumnName',{'✓','Eksperimen','Fr','Status'}, ...
        'ColumnWidth',{24 116 32 78}, ...
        'ColumnFormat',{'logical','char','char','char'}, ...
        'ColumnEditable',[true false false false], ...
        'RowName',[],'FontSize',8, ...
        'CellEditCallback',@(s,e) i_onCellEdit(fig, e), ...
        'CellSelectionCallback',@(s,e) i_onSelectRow(fig, e));
    uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
        'Position',[0.03 0.035 0.94 0.028],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',7,'ForegroundColor',[0.4 0.4 0.4], ...
        'String','Klik baris → muat ke kanvas. Centang ✓ → batch ekspor.');
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.005 0.94 0.026],'String','✓ Centang semua', ...
        'FontSize',8,'Callback',@(s,e) i_onToggleAll(fig));

    % --- Panel TENGAH: KANVAS WYSIWYG + slider frame ------------------
    pnlC = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.225 0.10 0.515 0.885],'Title','Kanvas (what you see = what you get)', ...
        'FontWeight','bold','BackgroundColor',WHITE);
    h.pnlCanvas = uipanel('Parent',pnlC,'Units','normalized', ...
        'Position',[0.01 0.165 0.98 0.825],'BackgroundColor',WHITE,'BorderType','none');
    h.ax = axes('Parent',h.pnlCanvas,'Units','normalized','Position',[0.07 0.12 0.83 0.80]);
    % Baris tombol Save / Save & Close / Close + Save Progress (kolom tengah).
    h.btnSave = uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.01 0.095 0.20 0.060],'String','💾 Save setelan','FontSize',9, ...
        'BackgroundColor',[0.90 0.94 0.99], ...
        'TooltipString','Simpan setelan render exp aktif ke sidecar <base>_exportcfg.json.', ...
        'Callback',@(s,e) i_onSaveCfg(fig, false));
    h.btnSaveClose = uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.22 0.095 0.21 0.060],'String','💾 Save & Close','FontSize',9, ...
        'TooltipString','Simpan setelan exp aktif lalu tutup GRAIN Exporter.', ...
        'Callback',@(s,e) i_onSaveCfg(fig, true));
    h.btnCloseOnly = uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.44 0.095 0.16 0.060],'String','✖ Close','FontSize',9, ...
        'TooltipString','Tutup tanpa menyimpan setelan.', ...
        'Callback',@(s,e) i_onCloseBtn(fig));
    h.btnSaveProg = uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.62 0.095 0.20 0.060],'String','🗂 Save Progress','FontSize',9, ...
        'BackgroundColor',[0.93 0.97 0.90], ...
        'TooltipString','Simpan progres sesi (exp tercentang + setelan global) ke PAB_export/_export_progress.json.', ...
        'Callback',@(s,e) i_onSaveProgress(fig));
    h.btnLoadProg = uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.83 0.095 0.16 0.060],'String','📂 Load','FontSize',9, ...
        'BackgroundColor',[0.93 0.97 0.90], ...
        'TooltipString','Muat ulang progres sesi (centang + setelan) dari _export_progress.json.', ...
        'Callback',@(s,e) i_onLoadProgress(fig));
    % Strip bawah kanvas: toggle skalar + test-1-frame + slider frame.
    h.btnScalar = uicontrol('Parent',pnlC,'Style','togglebutton','Units','normalized', ...
        'Position',[0.01 0.015 0.12 0.065],'String','Vel mag','FontWeight','bold', ...
        'TooltipString','Tukar tampilan kanvas: Vel mag <-> Shear strain.', ...
        'Callback',@(s,e) i_onToggleScalar(fig));
    h.btnTest1 = uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.135 0.015 0.135 0.065],'String','📸 Test 1 frame','FontSize',9, ...
        'BackgroundColor',[0.99 0.97 0.86], ...
        'TooltipString','Render frame aktif (kanvas) ke PAB_export/_preview/ untuk cek hasil — TIDAK mengisi katalog.', ...
        'Callback',@(s,e) i_onTestFrame(fig));
    h.btnFrame2 = uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.275 0.015 0.165 0.065],'String','⬇ Ekspor frame ini','FontSize',9, ...
        'FontWeight','bold','BackgroundColor',[0.82 0.92 0.82], ...
        'TooltipString',['Ekspor bingkai aktif → 2 berkas (velmag + shear) ke ' ...
                         'PAB_export/<exp>/_frame/ memakai setelan render saat ini.'], ...
        'Callback',@(s,e) i_onExportThisFrame(fig));
    h.sldFrame = uicontrol('Parent',pnlC,'Style','slider','Units','normalized', ...
        'Position',[0.445 0.025 0.365 0.045],'Min',1,'Max',2,'Value',1, ...
        'TooltipString','Geser bingkai aktif (preview kanvas).', ...
        'Callback',@(s,e) i_onFrameSlider(fig));
    h.txtFrame = uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.82 0.02 0.17 0.05],'String','f 1/1', ...
        'HorizontalAlignment','center','BackgroundColor',WHITE,'FontWeight','bold');

    % --- Panel KANAN: setelan render (GLOBAL) + export ---------------
    pnlR = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.745 0.10 0.250 0.885],'Title','Setelan render (default→file)', ...
        'FontWeight','bold','BackgroundColor',WHITE);
    y = 0.965; dy = 0.040; hdr = 0.030;   % lebih rapat (banyak kontrol)
    % Skalar diekspor
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 y 0.92 0.028],'String','Skalar diekspor:', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE); y=y-hdr;
    h.chkVel = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.06 y 0.44 0.032],'String','velmag','BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_onPrefs(fig));
    h.chkShear = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.52 y 0.44 0.032],'String','shear','BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_onPrefs(fig)); y=y-dy;
    % Overlay
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 y 0.92 0.028],'String','Overlay:', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE); y=y-hdr;
    h.chkGS = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.06 y 0.44 0.032],'String','Grayscale','BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_onPrefs(fig));
    h.chkGlyph = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.52 y 0.44 0.032],'String','Glyph','BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_onPrefs(fig)); y=y-dy;
    h.chkCLAHE = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.06 y 0.44 0.032],'String','CLAHE','BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_onPrefs(fig));
    h.chkAdj = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.52 y 0.46 0.032],'String','Auto kontras','BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_onPrefs(fig)); y=y-dy;
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.06 y 0.26 0.028],'String','alpha GS:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edAlpha = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.34 y 0.18 0.030],'BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_onPrefs(fig)); y=y-dy;
    % Glyph (tebal/spacing + warna velmag/shear) — seperti GRAIN4.
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 y 0.92 0.028],'String','Glyph (panah):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE); y=y-hdr;
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.06 y 0.18 0.028],'String','tebal:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edGlyphLW = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.25 y 0.16 0.030],'BackgroundColor',WHITE, ...
        'TooltipString','Tebal garis panah glyph.','Callback',@(s,e) i_onPrefs(fig));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.45 y 0.22 0.028],'String','spacing:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edGlyphSp = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.70 y 0.16 0.030],'BackgroundColor',WHITE, ...
        'TooltipString','Ambil tiap-N node (decimation glyph).','Callback',@(s,e) i_onPrefs(fig)); y=y-dy;
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.06 y 0.30 0.028],'String','warna velmag:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.btnGlyphCol = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.38 y 0.13 0.030],'String','', ...
        'TooltipString','Klik: pilih warna panah glyph velmag.', ...
        'Callback',@(s,e) i_onGlyphColor(fig,'vel'));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.54 y 0.26 0.028],'String','shear:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.btnGlyphColShear = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.80 y 0.13 0.030],'String','', ...
        'TooltipString','Klik: pilih warna panah glyph KHUSUS shear.', ...
        'Callback',@(s,e) i_onGlyphColor(fig,'shear')); y=y-dy;
    % Dekorasi: tickmark pixel + PSG + colorbar + judul
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 y 0.92 0.028],'String','Dekorasi (di gambar):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE); y=y-hdr;
    h.chkTick = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.06 y 0.50 0.032],'String','Tickmark pixel','BackgroundColor',WHITE, ...
        'TooltipString','Tampilkan angka posisi pixel (XTick/YTick).', ...
        'Callback',@(s,e) i_onPrefs(fig));
    h.chkTitle = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.56 y 0.42 0.032],'String','Judul exp','BackgroundColor',WHITE, ...
        'TooltipString','Judul = nama eksperimen.','Callback',@(s,e) i_onPrefs(fig)); y=y-dy;
    h.chkPSG = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.06 y 0.44 0.032],'String','Garis PSG','BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_onPrefs(fig));
    h.chkCB = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.56 y 0.42 0.032],'String','Colorbar','BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_onPrefs(fig)); y=y-dy;
    % Caption strain: checkbox + spinner x/y (±0.01) + warna teks/latar.
    h.chkStrain = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.06 y 0.40 0.032],'String','Caption strain','BackgroundColor',WHITE, ...
        'TooltipString','Teks "<strain%> (frame/total)" kiri-bawah AX main.', ...
        'Callback',@(s,e) i_onPrefs(fig));
    % x: edit + ▲/▼ (±0.01)
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.45 y 0.04 0.028],'String','x','HorizontalAlignment','right', ...
        'BackgroundColor',WHITE,'FontSize',8);
    h.edStrainX = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.50 y 0.13 0.030],'BackgroundColor',WHITE, ...
        'TooltipString','Posisi caption x (0..1).','Callback',@(s,e) i_onPrefs(fig));
    h.btnSXup = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.635 y+0.016 0.05 0.016],'String','▲','FontSize',6, ...
        'TooltipString','x +0.01','Callback',@(s,e) i_onSpinCap(fig,'x',+0.01));
    h.btnSXdn = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.635 y 0.05 0.016],'String','▼','FontSize',6, ...
        'TooltipString','x -0.01','Callback',@(s,e) i_onSpinCap(fig,'x',-0.01));
    % y: edit + ▲/▼ (±0.01)
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.69 y 0.04 0.028],'String','y','HorizontalAlignment','right', ...
        'BackgroundColor',WHITE,'FontSize',8);
    h.edStrainY = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.74 y 0.13 0.030],'BackgroundColor',WHITE, ...
        'TooltipString','Posisi caption y (0..1).','Callback',@(s,e) i_onPrefs(fig));
    h.btnSYup = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.875 y+0.016 0.05 0.016],'String','▲','FontSize',6, ...
        'TooltipString','y +0.01','Callback',@(s,e) i_onSpinCap(fig,'y',+0.01));
    h.btnSYdn = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.875 y 0.05 0.016],'String','▼','FontSize',6, ...
        'TooltipString','y -0.01','Callback',@(s,e) i_onSpinCap(fig,'y',-0.01)); y=y-dy;
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.06 y 0.26 0.028],'String','warna teks:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.btnStrainCol = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.34 y 0.10 0.030],'String','', ...
        'TooltipString','Warna tulisan caption.','Callback',@(s,e) i_onCapColor(fig,'text'));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.50 y 0.22 0.028],'String','latar:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.btnStrainBg = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.74 y 0.10 0.030],'String','', ...
        'TooltipString','Warna latar caption.','Callback',@(s,e) i_onCapColor(fig,'bg')); y=y-dy;
    % Satuan vel mag cm/s (override) + 3 OPSI sumber multiplier.
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 y 0.92 0.028],'String','Satuan vel mag → cm/s:', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE); y=y-hdr;
    h.chkCms = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.06 y 0.90 0.032],'String','Tampilkan |V| dalam cm/s (×multiplier)', ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Colorbar jadi cm/s; angka tick = px/frame × multiplier.', ...
        'Callback',@(s,e) i_onPrefs(fig)); y=y-dy;
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.06 y 0.18 0.028],'String','sumber:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.popMultSrc = uicontrol('Parent',pnlR,'Style','popupmenu','Units','normalized', ...
        'Position',[0.26 y 0.50 0.032],'BackgroundColor',WHITE,'FontSize',8, ...
        'String',{'1) Manual cm/px ÷ dt','2) Kalibrasi calxy','3) Geometri X0/X1 + dt'}, ...
        'TooltipString','Cara menentukan multiplier cm/s.', ...
        'Callback',@(s,e) i_onMultSource(fig));
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.78 y 0.18 0.032],'String','↻ hitung','FontSize',7, ...
        'TooltipString','Hitung multiplier sesuai sumber dari exp aktif.', ...
        'Callback',@(s,e) i_onAutoMult(fig)); y=y-dy;
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.06 y 0.20 0.028],'String','cm/px:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edCmPx = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.27 y 0.16 0.030],'BackgroundColor',WHITE, ...
        'TooltipString','Skala spasial cm/px (opsi 1/2).','Callback',@(s,e) i_onPrefs(fig));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.47 y 0.14 0.028],'String','dt(s):', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edDt = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.63 y 0.16 0.030],'BackgroundColor',WHITE, ...
        'TooltipString','dt detik/frame (auto EXIF).','Callback',@(s,e) i_onPrefs(fig));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.81 y 0.10 0.028],'String','×','HorizontalAlignment','center', ...
        'BackgroundColor',WHITE,'FontSize',8); y=y-dy;
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.06 y 0.24 0.028],'String','multiplier:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8,'FontWeight','bold');
    h.edMult = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.33 y 0.22 0.030],'BackgroundColor',WHITE, ...
        'TooltipString','Pengali |V|→cm/s (hasil sumber, bisa di-override manual).', ...
        'Callback',@(s,e) i_onPrefs(fig));
    h.txtMultInfo = uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.57 y 0.40 0.030],'String','','HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',7,'ForegroundColor',[0.3 0.3 0.3]); y=y-dy;
    % Kanvas cm
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 y 0.92 0.028],'String','Ukuran kanvas (cm):', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE); y=y-hdr;
    % Lebar: label + edit + spinner ▲/▼ (klik langsung +/-1 cm, re-render).
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 y 0.12 0.035],'String','lebar:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edW = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.17 y 0.13 0.032],'BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_onPrefs(fig));
    h.btnWup = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.305 y+0.016 0.075 0.016],'String','▲','FontSize',6, ...
        'TooltipString','Lebar +1 cm','Callback',@(s,e) i_onSpinSize(fig,'w',+1));
    h.btnWdn = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.305 y 0.075 0.016],'String','▼','FontSize',6, ...
        'TooltipString','Lebar -1 cm','Callback',@(s,e) i_onSpinSize(fig,'w',-1));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.46 y 0.12 0.028],'String','tinggi:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edH = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.59 y 0.13 0.032],'BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_onPrefs(fig));
    h.btnHup = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.725 y+0.016 0.075 0.016],'String','▲','FontSize',6, ...
        'TooltipString','Tinggi +1 cm','Callback',@(s,e) i_onSpinSize(fig,'h',+1));
    h.btnHdn = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.725 y 0.075 0.016],'String','▼','FontSize',6, ...
        'TooltipString','Tinggi -1 cm','Callback',@(s,e) i_onSpinSize(fig,'h',-1)); y=y-dy;
    % DPI + JPEG quality + tombol default file (1 baris rapat).
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 y 0.09 0.028],'String','DPI:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontWeight','bold');
    h.edDPI = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.14 y 0.11 0.032],'BackgroundColor',WHITE, ...
        'TooltipString','Resolusi render. 200 cukup jelas; naikkan utk paper tajam.', ...
        'Callback',@(s,e) i_onPrefs(fig));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.28 y 0.12 0.028],'String','JPEGq:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edJQ = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.42 y 0.10 0.032],'BackgroundColor',WHITE, ...
        'TooltipString','Kualitas JPEG 1..100 (80 = ringan & jelas).', ...
        'Callback',@(s,e) i_onPrefs(fig));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.55 y 0.16 0.028],'String','maks px:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edMaxPx = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.74 y 0.13 0.032],'BackgroundColor',WHITE, ...
        'TooltipString','Batas sisi-panjang piksel output (0/kosong = tak dibatasi).', ...
        'Callback',@(s,e) i_onPrefs(fig)); y=y-dy;
    % ⚡ Paralel (parfor) — default OFF; serial-reuse sudah 2.6x lebih cepat.
    % Catatan: paralel start pool ~40s & broadcast data -> menang hanya utk
    % batch BESAR; TAK bisa dibatalkan di tengah (parfor tak bisa diinterupsi).
    h.chkPar = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.06 y 0.62 0.030],'String','⚡ Paralel (parfor)','BackgroundColor',WHITE, ...
        'FontSize',8, ...
        'TooltipString',['Export paralel (banyak worker). Start pool ~40s sekali; ' ...
                         'menang utk batch BESAR. TAK bisa dibatalkan di tengah.'], ...
        'Callback',@(s,e) i_onPrefs(fig));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.70 y 0.14 0.028],'String','worker:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    h.edWorkers = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.86 y 0.12 0.032],'BackgroundColor',WHITE, ...
        'TooltipString','Jumlah worker paralel (default 5).','Callback',@(s,e) i_onPrefs(fig)); y=y-dy;
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.06 y 0.56 0.034],'String','⭐ Jadikan default', ...
        'FontSize',8,'TooltipString','Simpan setelan ini ke FILE (lintas-sesi).', ...
        'Callback',@(s,e) i_onSaveGlobal(fig));
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.64 y 0.30 0.034],'String','Reset','FontSize',8, ...
        'TooltipString','Kembalikan ke bawaan pabrik.', ...
        'Callback',@(s,e) i_onResetGlobal(fig)); y=y-dy-0.005;
    % Info exp aktif (ringkas, sisa ruang bawah panel).
    h.txtInfo = uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 0.01 0.92 max(0.05,y-0.01)],'HorizontalAlignment','left', ...
        'BackgroundColor',[0.97 0.97 0.97], ...
        'FontSize',8,'String','(belum ada eksperimen termuat)');

    % --- TOMBOL EXPORT (DI AKHIR, paling bawah, menonjol) ------------
    h.btnExport = uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.225 0.012 0.330 0.078],'String','📤 EXPORT semua bingkai exp aktif →', ...
        'FontWeight','bold','FontSize',12,'BackgroundColor',[0.82 0.92 0.82], ...
        'TooltipString','Render SEMUA bingkai eksperimen di kanvas ke PAB_export/ (regenerate bersih).', ...
        'Callback',@(s,e) i_onExportActive(fig));
    h.btnExportBatch = uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.560 0.012 0.180 0.078],'String','📦 Export batch (✓)', ...
        'FontSize',10,'BackgroundColor',[0.90 0.93 0.97], ...
        'TooltipString','Render semua exp TERCENTANG pakai setelan yang sama.', ...
        'Callback',@(s,e) i_onExportBatch(fig));
    uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.745 0.012 0.115 0.078],'String','📂 Folder katalog', ...
        'FontSize',9,'Callback',@(s,e) i_onOpenFolder(fig));
    h.btnCancel = uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.865 0.012 0.130 0.078],'String','■ Batalkan', ...
        'FontSize',9,'Enable','off','Callback',@(s,e) i_onCancel(fig));

    % --- Status bawah + progress -------------------------------------
    h.prog = uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.225 0.092 0.770 0.018],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',8,'String','');
    h.txtStatus = uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.005 0.000 0.990 0.010],'HorizontalAlignment','left', ...
        'BackgroundColor',[0.95 0.95 0.95],'FontSize',8, ...
        'String','Siap. Pilih folder lalu KLIK baris eksperimen untuk melihat di kanvas.');
end


% =====================================================================
% SINKRON kontrol <-> global
% =====================================================================
function i_applyGlobalToControls(fig)
    h = guidata(fig); g = h.g;
    set(h.chkVel,'Value',g.doVel); set(h.chkShear,'Value',g.doShear);
    set(h.chkGS,'Value',g.gsOn); set(h.chkGlyph,'Value',g.glyphOn);
    set(h.chkCLAHE,'Value',g.claheOn); set(h.chkAdj,'Value',g.adjOn);
    set(h.edAlpha,'String',sprintf('%.2f',g.gsAlpha));
    set(h.edGlyphLW,'String',num2str(g.glyphLW)); set(h.edGlyphSp,'String',num2str(g.glyphSp));
    set(h.btnGlyphCol,'BackgroundColor', i_clampColor(g.glyphColor));
    set(h.btnGlyphColShear,'BackgroundColor', i_clampColor(g.glyphColorShear));
    set(h.chkTick,'Value',g.tickPx);
    set(h.chkPSG,'Value',g.showPSG); set(h.chkCB,'Value',g.showColorbar);
    set(h.chkTitle,'Value',g.showTitle);
    set(h.chkStrain,'Value',g.strainShow);
    set(h.edStrainX,'String',sprintf('%.3g',g.strainPosX));
    set(h.edStrainY,'String',sprintf('%.3g',g.strainPosY));
    set(h.btnStrainCol,'BackgroundColor', i_clampColor(g.strainColor));
    set(h.btnStrainBg, 'BackgroundColor', i_clampColor(g.strainBg));
    set(h.chkCms,'Value', strcmpi(g.velUnit,'cms'));
    set(h.popMultSrc,'Value', i_multSrcIdx(g.multSource));
    set(h.edCmPx,'String', i_numOrEmpty(g.cmPerPx));
    set(h.edDt,'String', i_numOrEmpty(g.dtSec));
    if isfield(h,'chkPar'), set(h.chkPar,'Value',g.parallel); end
    if isfield(h,'edWorkers'), set(h.edWorkers,'String',num2str(g.maxWorkers)); end
    set(h.edMult,'String', sprintf('%.5g',g.velMult));
    set(h.edW,'String',num2str(g.widthCm)); set(h.edH,'String',num2str(g.heightCm));
    set(h.edDPI,'String',num2str(g.dpi)); set(h.edJQ,'String',num2str(g.jpegQ));
    if isfield(h,'edMaxPx'), set(h.edMaxPx,'String', i_numOrEmpty0(g.maxLongPx)); end
end

function idx = i_multSrcIdx(s)
    switch lower(char(s))
        case 'calxy', idx = 2;
        case 'geom',  idx = 3;
        otherwise,    idx = 1;   % manual
    end
end

function s = i_multSrcName(idx)
    switch idx, case 2, s='calxy'; case 3, s='geom'; otherwise, s='manual'; end
end

function i_onSpinCap(fig, which, step)
%I_ONSPINCAP  Spinner ▲/▼ posisi caption strain (±0.01). Klik langsung geser.
    h = guidata(fig);
    if strcmp(which,'x'), ed = h.edStrainX; else, ed = h.edStrainY; end
    v = i_numf(get(ed,'String'), 0, 0, 1) + step;
    v = max(0, min(1, v));
    set(ed,'String', sprintf('%.3g', v));
    i_readControlsToGlobal(fig); i_apply(fig);
end

function i_onCapColor(fig, which)
%I_ONCAPCOLOR  Pilih warna teks / latar caption strain -> re-render.
    h = guidata(fig);
    if strcmp(which,'bg'), cur = h.g.strainBg; else, cur = h.g.strainColor; end
    cur = i_clampColor(cur);
    if ~pivui.quiet()
        c = uisetcolor(cur, 'Warna caption strain');
        if isscalar(c) && c == 0, return; end
        if numel(c)==3, cur = c(:).'; end
    end
    if strcmp(which,'bg'), h.g.strainBg = cur; set(h.btnStrainBg,'BackgroundColor',cur);
    else, h.g.strainColor = cur; set(h.btnStrainCol,'BackgroundColor',cur); end
    guidata(fig, h);
    i_apply(fig); i_refreshCatalogStatus(fig); i_refreshTable(fig);
end

function i_onMultSource(fig)
%I_ONMULTSOURCE  Ganti sumber multiplier (dropdown) -> hitung ulang.
    h = guidata(fig);
    h.g.multSource = i_multSrcName(get(h.popMultSrc,'Value'));
    guidata(fig, h);
    i_onAutoMult(fig);
end

function i_onGlyphColor(fig, which)
%I_ONGLYPHCOLOR  Dialog pilih warna panah glyph (velmag/shear) -> langsung
%   re-render kanvas. Pakai uisetcolor; senyap saat quiet (tes).
    h = guidata(fig);
    if strcmp(which,'shear'), cur = h.g.glyphColorShear; else, cur = h.g.glyphColor; end
    cur = i_clampColor(cur);
    if ~pivui.quiet()
        c = uisetcolor(cur, 'Warna panah glyph');
        if isscalar(c) && c == 0, return; end   % batal
        if numel(c)==3, cur = c(:).'; end
    end
    if strcmp(which,'shear'), h.g.glyphColorShear = cur; set(h.btnGlyphColShear,'BackgroundColor',cur);
    else, h.g.glyphColor = cur; set(h.btnGlyphCol,'BackgroundColor',cur); end
    guidata(fig, h);
    i_apply(fig); i_refreshCatalogStatus(fig); i_refreshTable(fig);
end

function i_onAutoMult(fig)
%I_ONAUTOMULT  Hitung multiplier cm/s sesuai SUMBER (h.g.multSource):
%   1) manual : cm/px (input) ÷ dt (input/EXIF)
%   2) calxy  : cm/px (calxy kalibrasi PIVlab) ÷ dt  -> R.velMultCal
%   3) geom   : (|X0-X1| / ((nF-1)·dt)) / indenterMax -> R.velMultGeom
%      = kec.fisik indenter (cm/s) ÷ |V| indenter (px/frame)
    h = guidata(fig);
    src = h.g.multSource; R = h.resolve;
    cmpx = i_numf(get(h.edCmPx,'String'), NaN, 0, inf);
    dt   = i_numf(get(h.edDt,'String'),   NaN, 0, inf);
    mult = NaN; info = '';
    switch src
        case 'calxy'
            if ~isempty(R) && isfinite(R.cmPerPx)
                cmpx = R.cmPerPx; set(h.edCmPx,'String',sprintf('%.5g',cmpx));
            end
            if ~isfinite(dt) && ~isempty(R) && isfinite(R.dtSec)
                dt = R.dtSec; set(h.edDt,'String',sprintf('%.5g',dt));
            end
            if isfinite(cmpx) && isfinite(dt) && dt>0
                mult = cmpx/dt; info = sprintf('calxy: %.4g cm/px ÷ %.4g s', cmpx, dt);
            else, info = 'calxy tak tersedia (calxy=1 / belum dikalibrasi)';
            end
        case 'geom'
            if ~isempty(R) && isfinite(R.velMultGeom)
                mult = R.velMultGeom;
                vInd = R.dxCm/((R.nFrames-1)*R.dtSec);
                info = sprintf('geom: %.4gcm/%.4gs ÷ %.4gpx/fr', R.dxCm, (R.nFrames-1)*R.dtSec, R.indenterMax);
                if ~isfinite(dt) && isfinite(R.dtSec), set(h.edDt,'String',sprintf('%.5g',R.dtSec)); end
                i_status(fig, sprintf('Kec. indenter = %.4g cm/s; |V| indenter = %.4g px/fr.', vInd, R.indenterMax));
            else
                info = 'geom butuh X0/X1 + dt(EXIF) + indenter';
            end
        otherwise   % manual
            if ~isfinite(dt) && ~isempty(R) && isfinite(R.dtSec)
                dt = R.dtSec; set(h.edDt,'String',sprintf('%.5g',dt));
            end
            if isfinite(cmpx) && isfinite(dt) && dt>0
                mult = cmpx/dt; info = sprintf('manual: %.4g cm/px ÷ %.4g s', cmpx, dt);
            else, info = 'manual: isi cm/px & dt';
            end
    end
    if isfinite(mult) && mult > 0
        set(h.edMult,'String', sprintf('%.5g', mult));
        set(h.txtMultInfo,'String', info);
    else
        set(h.txtMultInfo,'String', info);
        i_status(fig, ['Multiplier tak terhitung — ' info '.']);
    end
    i_onPrefs(fig);
end

function i_readControlsToGlobal(fig)
    h = guidata(fig); g = h.g;
    g.doVel    = logical(get(h.chkVel,'Value'));
    g.doShear  = logical(get(h.chkShear,'Value'));
    if ~g.doVel && ~g.doShear, g.doVel = true; set(h.chkVel,'Value',1); end
    g.gsOn     = logical(get(h.chkGS,'Value'));
    g.glyphOn  = logical(get(h.chkGlyph,'Value'));
    g.claheOn  = logical(get(h.chkCLAHE,'Value'));
    g.adjOn    = logical(get(h.chkAdj,'Value'));
    g.gsAlpha  = i_numf(get(h.edAlpha,'String'), g.gsAlpha, 0, 1);
    g.showPSG  = logical(get(h.chkPSG,'Value'));
    g.showColorbar = logical(get(h.chkCB,'Value'));
    g.showTitle = logical(get(h.chkTitle,'Value'));
    g.widthCm  = i_numf(get(h.edW,'String'), g.widthCm, 2, 60);
    g.heightCm = i_numf(get(h.edH,'String'), g.heightCm, 2, 60);
    g.dpi      = i_num(get(h.edDPI,'String'), g.dpi, 30, 1200);
    g.jpegQ    = i_num(get(h.edJQ,'String'), g.jpegQ, 1, 100);
    % Glyph (tebal/spacing) + tickmark + caption strain.
    g.glyphLW  = i_numf(get(h.edGlyphLW,'String'), g.glyphLW, 0.1, 10);
    g.glyphSp  = i_num(get(h.edGlyphSp,'String'), g.glyphSp, 1, 50);
    g.tickPx   = logical(get(h.chkTick,'Value'));
    g.strainShow = logical(get(h.chkStrain,'Value'));
    g.strainPosX = i_numf(get(h.edStrainX,'String'), g.strainPosX, 0, 1);
    g.strainPosY = i_numf(get(h.edStrainY,'String'), g.strainPosY, 0, 1);
    % strainColor/strainBg di-set lewat callback warna (state) -> ikut g lewat
    % salinan g=h.g di atas; tak dibaca dari kontrol.
    g.multSource = i_multSrcName(get(h.popMultSrc,'Value'));
    % Satuan vel mag cm/s: unit + cm/px + dt + multiplier (auto bila keduanya ada).
    g.velUnit  = i_tern(logical(get(h.chkCms,'Value')), 'cms', 'pxframe');
    g.cmPerPx  = i_numf(get(h.edCmPx,'String'), NaN, 0, inf);
    g.dtSec    = i_numf(get(h.edDt,'String'), NaN, 0, inf);
    % velMult: pakai input langsung bila ada; else auto = cmPerPx/dtSec.
    vm = i_numf(get(h.edMult,'String'), NaN, 0, inf);
    if ~isfinite(vm) && isfinite(g.cmPerPx) && isfinite(g.dtSec) && g.dtSec>0
        vm = g.cmPerPx / g.dtSec;
    end
    if isfinite(vm) && vm > 0, g.velMult = vm; end
    if isfield(h,'edMaxPx')
        g.maxLongPx = i_num(get(h.edMaxPx,'String'), 0, 0, 20000);  % 0 = tak dibatasi
    end
    if isfield(h,'chkPar'), g.parallel = logical(get(h.chkPar,'Value')); end
    if isfield(h,'edWorkers'), g.maxWorkers = i_num(get(h.edWorkers,'String'), g.maxWorkers, 1, 64); end
    set(h.edAlpha,'String',sprintf('%.2f',g.gsAlpha));
    set(h.edW,'String',num2str(g.widthCm)); set(h.edH,'String',num2str(g.heightCm));
    set(h.edDPI,'String',num2str(g.dpi)); set(h.edJQ,'String',num2str(g.jpegQ));
    set(h.edGlyphLW,'String',num2str(g.glyphLW)); set(h.edGlyphSp,'String',num2str(g.glyphSp));
    set(h.edMult,'String',sprintf('%.5g',g.velMult));
    h.g = g; guidata(fig, h);
end

function i_onPrefs(fig)
    i_readControlsToGlobal(fig);
    i_apply(fig);                  % WYSIWYG: kanvas ikut berubah
    i_refreshCatalogStatus(fig);   % fingerprint berubah -> ⚠BASI bisa muncul
    i_refreshTable(fig);
end

function i_onSpinSize(fig, which, step)
%I_ONSPINSIZE  Tombol ▲/▼ ukuran kanvas (cm). Klik LANGSUNG ubah edit + global
%   + re-render kanvas (pola GRAINAXPOT i_onSpin). min 2 cm. Ukuran kanvas TAK
%   memengaruhi fingerprint (bukan rupa piksel), jadi tak picu refresh status.
    h = guidata(fig);
    if strcmp(which,'w'), ed = h.edW; else, ed = h.edH; end
    v = i_numf(get(ed,'String'), 0, 2, 60) + step;
    if v < 2, v = 2; end
    set(ed,'String', num2str(v));
    i_readControlsToGlobal(fig);   % serap ke h.g
    i_apply(fig);                  % WYSIWYG: kanvas langsung berubah
end


% =====================================================================
% userPrefs (untuk engine) dari global
% =====================================================================
function up = i_userPrefs(h)
    sc = {};
    if h.g.doVel,   sc{end+1} = 'velmag'; end
    if h.g.doShear, sc{end+1} = 'shear';  end
    if isempty(sc), sc = {'velmag'}; end
    up = struct('scalars',{sc}, 'gsOn',h.g.gsOn, 'claheOn',h.g.claheOn, ...
        'adjOn',h.g.adjOn, 'gsAlpha',h.g.gsAlpha, 'glyphOn',h.g.glyphOn, ...
        'glyphLW',h.g.glyphLW, 'glyphSp',h.g.glyphSp, 'glyphColor',h.g.glyphColor, ...
        'glyphColorShear',h.g.glyphColorShear, 'tickPx',h.g.tickPx, ...
        'velUnit',h.g.velUnit, 'velMult',h.g.velMult, ...
        'strainShow',h.g.strainShow, 'strainPos',[h.g.strainPosX h.g.strainPosY], ...
        'strainColor',h.g.strainColor, 'strainBg',h.g.strainBg, ...
        'showPSG',h.g.showPSG, 'showColorbar',h.g.showColorbar, 'showTitle',h.g.showTitle);
end


% =====================================================================
% KANVAS WYSIWYG (renderer BERSAMA dgn ekspor)
% =====================================================================
function i_apply(fig)
%I_APPLY  Render bingkai aktif ke kanvas memakai drawScalarPanel (sama dgn yg
%   dipakai ekspor). Ukuran kanvas fisik (cm) -> WYSIWYG. Tanpa exp -> kosong.
    h = guidata(fig);
    if ~ishghandle(h.ax), return; end
    if isempty(h.data) || isempty(h.resolve)
        cla(h.ax,'reset'); axis(h.ax,'off');
        text(h.ax,0.5,0.5,'Klik baris eksperimen di kiri untuk melihat gambar AX main', ...
            'Units','normalized','HorizontalAlignment','center','Color',[0.5 0.5 0.5]);
        return;
    end
    % Pastikan bingkai aktif termuat penuh bila k>1.
    k = max(1, min(round(h.frame), max(1,h.imgFrames)));
    if k > 1 && ~h.fullLoaded
        i_ensureFull(fig); h = guidata(fig);
    end
    k = max(1, min(round(h.frame), max(1,h.imgFrames)));

    % Ukuran kanvas fisik cm -> OuterPosition axes (WYSIWYG seperti GRAINAXPOT).
    pp = getpixelposition(h.pnlCanvas);
    cm2px = get(0,'ScreenPixelsPerInch')/2.54;
    wpx = h.g.widthCm*cm2px; hpx = h.g.heightCm*cm2px;
    set(h.ax,'Units','pixels');
    mx = max((pp(3)-wpx)/2, 6); my = max((pp(4)-hpx)/2, 6);
    set(h.ax,'OuterPosition',[mx my min(wpx,pp(3)-10) min(hpx,pp(4)-10)]);
    set(h.ax,'Units','normalized');
    cla(h.ax,'reset');

    up = i_userPrefs(h);
    spec = pivcore.export.frameCatalog.specFromResolve(h.resolve, up);
    cfg = pivcore.export.frameCatalog.renderCfg(spec);
    % decOpts dari SPEC (single source, sama dgn ekspor) -> WYSIWYG penuh
    % (tickmark/cm-s/glyph shear/caption strain ikut tampil di kanvas).
    decOpts = pivcore.export.frameCatalog.decOptsFromSpec(spec, up);
    [~, base] = fileparts(h.realData);
    pivcore.export.frameCatalog.drawScalarPanel(h.ax, h.data, k, h.scalar, cfg, ...
        h.resolve, base, decOpts);
end


% =====================================================================
% LOAD EKSPERIMEN ke kanvas (session)
% =====================================================================
function i_loadExperiment(fig, row)
    h = guidata(fig);
    if row < 1 || row > numel(h.list), return; end
    df = h.list(row).file; [~, base] = fileparts(df);
    h.activeRow = row; h.realData = df;
    h.data = []; h.fullLoaded = false; h.imgFrames = 1; h.nF = 1; h.frame = 1;
    h.resolve = []; guidata(fig, h);

    i_setBusy(fig, true);
    i_status(fig, sprintf('Memuat %s (bingkai-1 + garis PSG + CLim)…', base));
    drawnow;
    try
        data1 = pivcore.io.step1Session.loadFrame1(df);
        R = pivcore.export.frameCatalog.resolveRender(df);
    catch ME
        i_setBusy(fig, false);
        i_status(fig, sprintf('GAGAL memuat %s: %s', base, ME.message));
        return;
    end
    h = guidata(fig);
    h.data = data1;
    h.imgFrames = pivcore.data.frameCount(data1);
    h.resolve = R;
    h.nF = max([1, h.imgFrames, R.nFrames]);
    h.frame = 1;
    guidata(fig, h);

    % Muat sidecar setelan per-exp bila ada (Save per-exp) -> timpa h.g.
    cfg = pivcore.io.grainExportCatalog.readCfg(df);
    if isstruct(cfg) && isfield(cfg,'global') && isstruct(cfg.global)
        h = guidata(fig);
        f = fieldnames(h.g);
        for i = 1:numel(f)
            if isfield(cfg.global, f{i}) && ~isempty(cfg.global.(f{i}))
                h.g.(f{i}) = cfg.global.(f{i});
            end
        end
        guidata(fig, h);
        i_applyGlobalToControls(fig);
    end

    % Auto-suggest cm/px & dt dari geom/EXIF ke field (HANYA bila masih kosong).
    h = guidata(fig);
    if ~isfinite(h.g.cmPerPx) && isfinite(R.cmPerPx)
        set(h.edCmPx,'String',sprintf('%.5g',R.cmPerPx));
    end
    if ~isfinite(h.g.dtSec) && isfinite(R.dtSec)
        set(h.edDt,'String',sprintf('%.5g',R.dtSec));
    end
    i_readControlsToGlobal(fig);

    i_setBusy(fig, false);
    i_syncFrameSlider(fig);
    i_apply(fig);
    i_updateInfo(fig);
    cmsNote = '';
    if isfinite(R.velMultAuto), cmsNote = sprintf(' velMult auto=%.4g (cm/s).', R.velMultAuto); end
    i_status(fig, sprintf('%s dimuat: %d bingkai, PSG=%s, strain=%.2f%%.%s', ...
        base, R.nFrames, R.psgSource, R.strainTotalPct, cmsNote));
end

function ok = i_ensureFull(fig)
    h = guidata(fig); ok = false;
    if h.fullLoaded, ok = true; return; end
    if isempty(h.realData), return; end
    i_status(fig, 'Memuat semua bingkai untuk preview…'); drawnow;
    try
        dataAll = pivcore.io.step1Session.loadAllFrames(h.realData);
    catch ME
        i_status(fig, sprintf('Gagal muat semua bingkai: %s', ME.message)); return;
    end
    h = guidata(fig);
    h.data = dataAll; h.fullLoaded = true;
    h.imgFrames = pivcore.data.frameCount(dataAll);
    guidata(fig, h); ok = true;
end

function i_onFrameSlider(fig)
    h = guidata(fig);
    if isempty(h.data), return; end
    k = round(get(h.sldFrame,'Value'));
    k = max(1, min(k, max(1,h.nF)));
    h.frame = k; guidata(fig, h);
    if k > 1 && ~h.fullLoaded, i_ensureFull(fig); h = guidata(fig); end
    i_apply(fig);
    set(h.txtFrame,'String', sprintf('f %d/%d', max(1,min(h.frame,h.nF)), h.nF));
end

function i_syncFrameSlider(fig)
    h = guidata(fig);
    nF = max(1, h.nF);
    if nF > 1, step = [1 10]/(nF-1); else, step = [1 1]; end
    set(h.sldFrame,'Min',1,'Max',nF,'Value',max(1,min(h.frame,nF)),'SliderStep',step);
    set(h.txtFrame,'String', sprintf('f %d/%d', max(1,min(h.frame,nF)), nF));
end

function i_onToggleScalar(fig)
    h = guidata(fig);
    if get(h.btnScalar,'Value')
        h.scalar = 'shear'; set(h.btnScalar,'String','Shear');
    else
        h.scalar = 'velmag'; set(h.btnScalar,'String','Vel mag');
    end
    guidata(fig, h);
    i_apply(fig);
end

function i_updateInfo(fig)
    h = guidata(fig);
    if isempty(h.realData), set(h.txtInfo,'String','(belum ada eksperimen termuat)'); return; end
    [~, base] = fileparts(h.realData);
    R = h.resolve;
    lines = { sprintf('Exp: %s', base), ...
              sprintf('Bingkai: %d', R.nFrames), ...
              sprintf('Garis PSG: %s', R.psgSource), ...
              sprintf('CLim |V|: [%.2f %.2f]', R.climVel(1), R.climVel(2)), ...
              sprintf('CLim shear: ±%.3g', R.shearAbs) };
    if isfinite(R.indenterMax)
        lines{end+1} = sprintf('Maks |V| (indenter): %.3g', R.indenterMax);
    end
    lines{end+1} = '';
    lines{end+1} = sprintf('Status katalog: %s', h.list(h.activeRow).status);
    set(h.txtInfo,'String',lines);
end


% =====================================================================
% PEMINDAIAN & TABEL & STATUS KATALOG
% =====================================================================
function i_rescan(fig)
    h = guidata(fig);
    if h.busy, return; end
    files = pivanalyzemat.core.scanPivMats(h.root);
    list = struct('name',{},'file',{},'sizeMB',{},'nFrames',{},'sel',{},'status',{},'count',{});
    for i = 1:numel(files)
        [~, base] = fileparts(files{i});
        nf = i_probeFrames(files{i});
        d = dir(files{i}); mb = 0; if ~isempty(d), mb = d(1).bytes/1e6; end
        list(end+1) = struct('name',base,'file',files{i}, ...
            'sizeMB',mb,'nFrames',nf,'sel',false,'status','—','count',[0 0]); %#ok<AGROW>
    end
    h.list = list; h.activeRow = 0; guidata(fig, h);
    i_refreshCatalogStatus(fig);
    i_refreshTable(fig);
    h = guidata(fig);
    if isempty(h.list)
        i_status(fig, 'Tak ada .mat PIV ditemukan. Coba folder berisi PIV_<tgl>/.');
    else
        i_status(fig, sprintf('%d eksperimen. Klik baris untuk melihat di kanvas.', numel(h.list)));
    end
end

function nf = i_probeFrames(matFile)
    nf = 1;
    try
        info = whos('-file', matFile);
        names = {info.name};
        cand = {'u_original','u_filtered','x','velocity_magnitude'};
        for c = 1:numel(cand)
            idx = find(strcmp(names, cand{c}), 1);
            if ~isempty(idx)
                sz = info(idx).size;
                if numel(sz) >= 2 && max(sz) > 1, nf = max(sz); end
                break;
            end
        end
    catch
    end
end

function i_refreshCatalogStatus(fig)
    h = guidata(fig);
    up = i_userPrefs(h);
    for i = 1:numel(h.list)
        df = h.list(i).file;
        m = pivcore.io.grainExportCatalog.read(h.grainRoot, df);
        nv = 0; ns = 0;
        if isfield(m,'scalars') && isstruct(m.scalars)
            if isfield(m.scalars,'velmag'), nv = pivcore.io.grainExportCatalog.scalCount(m.scalars.velmag); end
            if isfield(m.scalars,'shear'),  ns = pivcore.io.grainExportCatalog.scalCount(m.scalars.shear); end
        end
        h.list(i).count = [nv ns];
        if nv == 0 && ns == 0
            h.list(i).status = 'Belum';
        else
            liveFp = i_liveFingerprint(up, m);
            stale = true;
            if isfield(m,'spec') && isstruct(m.spec) && isfield(m.spec,'fingerprint')
                stale = ~strcmp(char(m.spec.fingerprint), liveFp);
            end
            tag = sprintf('OK v%d/s%d', nv, ns);
            if stale, tag = ['⚠BASI ' tag]; end
            h.list(i).status = tag;
        end
    end
    guidata(fig, h);
end

function fp = i_liveFingerprint(up, manifest)
    p = struct();
    p.scalars = up.scalars;
    p.gsOn = up.gsOn; p.claheOn = up.claheOn; p.adjOn = up.adjOn; p.gsAlpha = up.gsAlpha;
    p.glyphOn = up.glyphOn; p.glyphLW = up.glyphLW; p.glyphSp = up.glyphSp; p.glyphColor = up.glyphColor;
    % Field BARU yg masuk fingerprint (HARUS padan dgn specStruct/fingerprint
    % supaya status BASI tak salah-positif setelah export).
    p.glyphColorShear = up.glyphColorShear; p.tickPx = up.tickPx;
    p.velUnit = up.velUnit; p.velMult = up.velMult;
    p.strainShow = up.strainShow; p.strainPos = up.strainPos;
    if isfield(manifest,'spec') && isstruct(manifest.spec)
        ms = manifest.spec;
        if isfield(ms,'climVel'),  p.climVel  = ms.climVel;  end
        if isfield(ms,'shearAbs'), p.shearAbs = ms.shearAbs; end
        if isfield(ms,'psgP1'),    p.psgP1    = ms.psgP1;    end
        if isfield(ms,'psgP2'),    p.psgP2    = ms.psgP2;    end
    end
    spec = pivcore.io.grainExportCatalog.specStruct(p);
    fp = spec.fingerprint;
end

function i_refreshTable(fig)
    h = guidata(fig);
    n = numel(h.list); C = cell(n, 4);
    for i = 1:n
        C{i,1} = logical(h.list(i).sel);
        C{i,2} = h.list(i).name;
        C{i,3} = num2str(h.list(i).nFrames);
        C{i,4} = h.list(i).status;
    end
    set(h.tbl, 'Data', C);
end


% =====================================================================
% CALLBACK TABEL / TOMBOL
% =====================================================================
function i_onCellEdit(fig, e)
    h = guidata(fig);
    try
        r = e.Indices(1); c = e.Indices(2);
        if c == 1 && r >= 1 && r <= numel(h.list)
            h.list(r).sel = logical(e.NewData); guidata(fig, h);
        end
    catch
    end
end

function i_onSelectRow(fig, e)
    h = guidata(fig);
    if h.busy, return; end
    try
        if isempty(e.Indices), return; end
        r = e.Indices(1);
        if r >= 1 && r <= numel(h.list) && r ~= h.activeRow
            i_loadExperiment(fig, r);
        end
    catch
    end
end

function i_onToggleAll(fig)
    h = guidata(fig);
    if isempty(h.list), return; end
    anyOff = any(~[h.list.sel]);
    for i = 1:numel(h.list), h.list(i).sel = anyOff; end
    guidata(fig, h); i_refreshTable(fig);
end

function i_onPickFolder(fig)
    h = guidata(fig);
    pivui.minimizeForDialog(fig);
    d = uigetdir(h.root, 'Pilih folder berisi .mat PIV (output Step 2)');
    pivui.restoreAfterDialog(fig);
    if isequal(d, 0), return; end
    h.root = d; set(h.txtRoot,'String',d); guidata(fig, h);
    i_rescan(fig);
end

function i_onOpenFolder(fig)
    h = guidata(fig);
    r = pivcore.io.grainExportCatalog.rootDir(h.grainRoot);
    if ~isfolder(r), mkdir(r); end
    try
        if ismac, system(['open "' r '" &']);
        elseif ispc, winopen(r);
        else, system(['xdg-open "' r '" &']); end
    catch
        i_status(fig, ['Folder katalog: ' r]);
    end
end


% =====================================================================
% EXPORT (DI AKHIR)
% =====================================================================
function i_onExportActive(fig)
    h = guidata(fig);
    if isempty(h.realData)
        i_status(fig, 'Belum ada eksperimen termuat. Klik baris dulu.'); return;
    end
    i_runExport(fig, h.activeRow);
end

function i_onTestFrame(fig)
%I_ONTESTFRAME  Render HANYA frame aktif (skalar kanvas) ke PAB_export/_preview/
%   untuk cek hasil sebelum export semua. TIDAK mengisi katalog resmi.
    h = guidata(fig);
    if isempty(h.realData) || isempty(h.resolve)
        i_status(fig, 'Belum ada eksperimen termuat. Klik baris dulu.'); return;
    end
    i_readControlsToGlobal(fig); h = guidata(fig);
    if h.frame > 1 && ~h.fullLoaded, i_ensureFull(fig); h = guidata(fig); end
    up = i_userPrefs(h);
    opts = struct('dpi',h.g.dpi,'jpegQuality',h.g.jpegQ,'userPrefs',up, ...
        'resolve',h.resolve,'dataAll',h.data);
    set(fig,'Pointer','watch'); drawnow;
    try
        f = pivcore.export.frameCatalog.previewFrame(h.grainRoot, h.realData, ...
            h.frame, h.scalar, opts);
    catch ME
        set(fig,'Pointer','arrow');
        i_status(fig, sprintf('Gagal test frame: %s', ME.message)); return;
    end
    set(fig,'Pointer','arrow');
    [~,nm,ext] = fileparts(f);
    i_status(fig, sprintf('📸 Test frame disimpan: _preview/%s%s (f%d, %s, %d DPI).', ...
        nm, ext, h.frame, h.scalar, h.g.dpi));
end

function i_onExportThisFrame(fig)
%I_ONEXPORTTHISFRAME  Ekspor bingkai aktif -> 2 berkas (velmag+shear) ke
%   PAB_export/<exp>/_frame/. Setelan render = kolom tengah/kanan saat ini
%   (userPrefs+global), identik dgn ekspor batch. Berkas NYATA (bukan preview).
    h = guidata(fig);
    if isempty(h.realData) || isempty(h.resolve)
        i_status(fig, 'Belum ada eksperimen termuat. Klik baris dulu.'); return;
    end
    i_readControlsToGlobal(fig); h = guidata(fig);
    if h.frame > 1 && ~h.fullLoaded, i_ensureFull(fig); h = guidata(fig); end
    up = i_userPrefs(h);
    opts = struct('dpi',h.g.dpi,'jpegQuality',h.g.jpegQ,'userPrefs',up, ...
        'resolve',h.resolve,'dataAll',h.data);
    set(fig,'Pointer','watch'); drawnow;
    try
        files = pivcore.export.frameCatalog.exportSingleFrame(h.grainRoot, ...
            h.realData, h.frame, opts);
    catch ME
        set(fig,'Pointer','arrow');
        i_status(fig, sprintf('Gagal ekspor frame: %s', ME.message)); return;
    end
    set(fig,'Pointer','arrow');
    [~,n1,e1] = fileparts(files{1}); [~,n2,e2] = fileparts(files{2});
    i_status(fig, sprintf('⬇ Frame %d diekspor: _frame/%s%s + %s%s (%d DPI).', ...
        h.frame, n1, e1, n2, e2, h.g.dpi));
end

function i_onExportBatch(fig)
    h = guidata(fig);
    sel = find([h.list.sel]);
    if isempty(sel)
        i_status(fig, 'Tak ada exp tercentang. Centang ✓ minimal satu.'); return;
    end
    if ~pivui.quiet()
        q = questdlg(sprintf('Export %d eksperimen tercentang (semua bingkai) ke katalog?', ...
            numel(sel)), 'Export batch', 'Ya','Batal','Batal');
        if ~strcmp(q,'Ya'), return; end
    end
    i_runExport(fig, sel);
end

function i_runExport(fig, rows)
    h = guidata(fig);
    if h.busy, return; end
    i_readControlsToGlobal(fig); h = guidata(fig);
    up = i_userPrefs(h);
    stamp = datestr(now, 'yyyy-mm-dd HH:MM'); %#ok<TNOW1,DATST>

    h.busy = true; h.cancel = false;
    % --- PROGRESS BAR visual (waitbar) — wajib utk kerja berulang/panjang.
    % Senyap saat tes (pivui.quiet) supaya tak rebut fokus.
    h.wb = [];
    if ~pivui.quiet()
        h.wb = waitbar(0, 'Menyiapkan export…', 'Name','GRAIN Exporter — Export', ...
            'CreateCancelBtn', @(s,e) i_onWbCancel(fig));
        try, pivui.forceLightTheme(h.wb); catch, end
    end
    guidata(fig, h);
    cleanWb = onCleanup(@() i_closeWb(fig));   % pastikan waitbar tertutup
    i_setBusy(fig, true);

    n = numel(rows);
    for ii = 1:n
        h = guidata(fig); if h.cancel, break; end
        idx = rows(ii); df = h.list(idx).file; base = h.list(idx).name;
        i_status(fig, sprintf('[%d/%d] %s — menyiapkan…', ii, n, base));
        i_wb(fig, (ii-1)/n, sprintf('[%d/%d] %s — menyiapkan…', ii, n, base));
        drawnow;
        % Reuse resolve exp aktif bila sama (hemat sampling POT ulang).
        if idx == h.activeRow && ~isempty(h.resolve), R = h.resolve; else
            try, R = pivcore.export.frameCatalog.resolveRender(df);
            catch ME, i_status(fig, sprintf('GAGAL siapkan %s: %s', base, ME.message)); continue; end
        end
        % progFcn: update bar fraksi GLOBAL ((exp selesai + frac exp ini)/n).
        progFcn = @(k,nn,sc) i_progress(fig, ii, n, base, sc, k, nn);
        % cancelFcn: dicek tiap frame di engine (mode serial) -> Batalkan responsif.
        cancelFcn = @() i_isCancelled(fig);
        opts = struct('dpi',h.g.dpi, 'jpegQuality',h.g.jpegQ, 'userPrefs',up, ...
            'producedAt',stamp, 'purge',true, 'progressFcn',progFcn, 'resolve',R, ...
            'parallel',h.g.parallel, 'maxWorkers',h.g.maxWorkers, 'cancelFcn',cancelFcn, ...
            'maxLongPx',h.g.maxLongPx);
        try
            pivcore.export.frameCatalog.renderExperiment(h.grainRoot, df, opts);
        catch ME
            i_status(fig, sprintf('GAGAL render %s: %s', base, ME.message)); continue;
        end
        i_refreshCatalogStatus(fig); i_refreshTable(fig);
    end

    h = guidata(fig); h.busy = false; guidata(fig, h);
    i_closeWb(fig);
    i_setBusy(fig, false); set(h.prog,'String','');
    if h.activeRow >= 1, i_updateInfo(fig); end
    if h.cancel
        i_status(fig, 'Dibatalkan. Katalog yang sudah ditulis tetap tersimpan.');
    else
        i_status(fig, sprintf('Selesai. %d eksperimen diekspor ke PAB_export/.', n));
    end
end

function i_progress(fig, ei, nE, base, scalar, k, n)
    if ~ishghandle(fig), return; end
    h = guidata(fig);
    % Fraksi GLOBAL: exp sebelumnya selesai + progres exp ini.
    fracExp = 0; if n > 0, fracExp = k/n; end
    frac = ((ei-1) + fracExp) / max(1,nE);
    msg = sprintf('[%d/%d] %s — %s: bingkai %d/%d', ei, nE, base, scalar, k, n);
    i_wb(fig, frac, msg);
    set(h.prog, 'String', msg);
    drawnow limitrate;
end

function i_wb(fig, frac, msg)
%I_WB  Update progress bar (waitbar) bila ada. Aman bila kosong (tes senyap).
%   frac non-finite -> abaikan update bar (cukup status text).
    if ~isfinite(frac), return; end
    h = guidata(fig);
    if isfield(h,'wb') && ~isempty(h.wb) && ishghandle(h.wb)
        try, waitbar(max(0,min(1,frac)), h.wb, msg); catch, end
    end
end

function i_closeWb(fig)
%I_CLOSEWB  Tutup progress bar + bersihkan handle.
    if ~ishghandle(fig), return; end
    h = guidata(fig);
    if isfield(h,'wb') && ~isempty(h.wb)
        if ishghandle(h.wb), try, delete(h.wb); catch, end, end
        h.wb = []; guidata(fig, h);
    end
end

function i_onWbCancel(fig)
%I_ONWBCANCEL  Tombol Cancel di waitbar -> sama dgn Batalkan.
    if ~ishghandle(fig), return; end
    h = guidata(fig); h.cancel = true; guidata(fig, h);
    i_status(fig, 'Membatalkan setelah bingkai ini…');
    i_wb(fig, NaN, 'Membatalkan…');
end

function tf = i_isCancelled(fig)
%I_ISCANCELLED  true bila user klik Batalkan. drawnow MEMPROSES event tombol
%   (tanpa ini, klik tak terbaca selagi loop sibuk). Dicek engine tiap frame.
    tf = false;
    if ~ishghandle(fig), tf = true; return; end
    drawnow;                       % proses klik Batalkan yg tertunda
    h = guidata(fig);
    if isfield(h,'cancel') && h.cancel, tf = true; end
end

function i_setBusy(fig, busy)
    h = guidata(fig);
    en = 'on'; if busy, en = 'off'; end
    for c = {h.btnExport, h.btnExportBatch, h.tbl, h.sldFrame, h.btnScalar}
        if ishghandle(c{1}), set(c{1}, 'Enable', en); end
    end
    if ishghandle(h.btnCancel)
        set(h.btnCancel,'Enable', i_tern(busy,'on','off'));
    end
    set(fig, 'Pointer', i_tern(busy,'watch','arrow')); drawnow;
end

function i_onCancel(fig)
    h = guidata(fig); h.cancel = true; guidata(fig, h);
    i_status(fig, 'Membatalkan setelah bingkai ini…');
end

function i_onClose(fig)
    h = guidata(fig);
    if isfield(h,'busy') && h.busy
        h.cancel = true; guidata(fig, h); return;
    end
    delete(fig);
end


% =====================================================================
% SAVE setelan per-exp (sidecar) / Save & Close / Close / Save Progress
% =====================================================================
function i_onSaveCfg(fig, alsoClose)
%I_ONSAVECFG  Simpan setelan render exp AKTIF ke sidecar <base>_exportcfg.json
%   (di samping .mat). alsoClose=true -> tutup setelah simpan.
    h = guidata(fig);
    if isempty(h.realData)
        i_status(fig, 'Belum ada eksperimen termuat — tak ada setelan untuk disimpan.');
        return;
    end
    i_readControlsToGlobal(fig); h = guidata(fig);
    cfg = struct('global', h.g);
    try
        pivcore.io.grainExportCatalog.writeCfg(h.realData, cfg);
        [~, base] = fileparts(h.realData);
        i_status(fig, sprintf('💾 Setelan exp %s disimpan ke %s_exportcfg.json.', base, base));
    catch ME
        i_status(fig, sprintf('Gagal simpan setelan: %s', ME.message));
        return;
    end
    if alsoClose, delete(fig); end
end

function i_onCloseBtn(fig)
%I_ONCLOSEBTN  Tutup tanpa simpan (tombol ✖ Close kolom tengah).
    h = guidata(fig);
    if isfield(h,'busy') && h.busy
        h.cancel = true; guidata(fig, h);
        i_status(fig, 'Render berjalan — dibatalkan; klik Close lagi untuk tutup.');
        return;
    end
    delete(fig);
end

function i_onSaveProgress(fig)
%I_ONSAVEPROGRESS  Simpan progres SESI (exp tercentang + setelan global) ke
%   PAB_export/_export_progress.json. State kerja lintas-sesi.
    h = guidata(fig);
    i_readControlsToGlobal(fig); h = guidata(fig);
    sel = {};
    for i = 1:numel(h.list)
        if h.list(i).sel, sel{end+1} = h.list(i).file; end %#ok<AGROW>
    end
    prog = struct();
    prog.root     = h.root;
    prog.savedAt  = datestr(now, 'yyyy-mm-dd HH:MM'); %#ok<TNOW1,DATST>
    prog.global   = h.g;
    prog.selected = sel;
    if ~isempty(h.realData), prog.activeExp = h.realData; end
    try
        pivcore.io.grainExportCatalog.writeProgress(h.grainRoot, prog);
        i_status(fig, sprintf('🗂 Progres sesi disimpan (%d exp tercentang) ke PAB_export/_export_progress.json.', ...
            numel(sel)));
    catch ME
        i_status(fig, sprintf('Gagal simpan progres: %s', ME.message));
    end
end

function ok = i_loadProgress(fig)
%I_LOADPROGRESS  Pulihkan progres sesi (setelan global + centang) bila ada.
%   Dipanggil saat init setelah rescan. Senyap bila tak ada. ok=true bila ada.
    ok = false;
    h = guidata(fig);
    prog = pivcore.io.grainExportCatalog.readProgress(h.grainRoot);
    if ~isstruct(prog) || ~isfield(prog,'global') || ~isstruct(prog.global), return; end
    f = fieldnames(h.g);
    for i = 1:numel(f)
        if isfield(prog.global, f{i}) && ~isempty(prog.global.(f{i}))
            h.g.(f{i}) = prog.global.(f{i});
        end
    end
    % Pulihkan centang berdasarkan path file.
    nSel = 0;
    if isfield(prog,'selected')
        sel = prog.selected; if ~iscell(sel), sel = {}; end
        for i = 1:numel(h.list)
            h.list(i).sel = any(strcmp(h.list(i).file, sel));
            if h.list(i).sel, nSel = nSel + 1; end
        end
    end
    guidata(fig, h);
    i_applyGlobalToControls(fig);
    i_refreshTable(fig);
    ok = true;
end

function i_onLoadProgress(fig)
%I_ONLOADPROGRESS  Tombol "📂 Load" — muat progres sesi + re-render kanvas.
    h = guidata(fig);
    ppath = pivcore.io.grainExportCatalog.progressPath(h.grainRoot);
    if ~isfile(ppath)
        i_status(fig, 'Belum ada progres tersimpan (PAB_export/_export_progress.json).');
        return;
    end
    ok = i_loadProgress(fig);
    if ok
        i_apply(fig);   % setelan berubah -> kanvas ikut
        i_refreshCatalogStatus(fig); i_refreshTable(fig);
        i_status(fig, '📂 Progres sesi dimuat (centang + setelan dipulihkan).');
    else
        i_status(fig, 'Gagal memuat progres (berkas rusak / kosong).');
    end
end


% =====================================================================
% UTIL
% =====================================================================
function i_status(fig, msg)
    h = guidata(fig);
    if isfield(h,'txtStatus') && ishghandle(h.txtStatus)
        set(h.txtStatus, 'String', msg); drawnow limitrate;
    end
end

function v = i_num(s, def, lo, hi)
    v = str2double(s); if ~isfinite(v), v = def; end
    v = max(lo, min(hi, round(v)));
end

function v = i_numf(s, def, lo, hi)
    v = str2double(s); if ~isfinite(v), v = def; end
    v = max(lo, min(hi, v));
end

function out = i_tern(c, a, b), if c, out = a; else, out = b; end, end

function c = i_clampColor(c)
    c = double(c(:).');
    if numel(c) ~= 3 || any(~isfinite(c)), c = [0 0 0]; end
    c = max(0, min(1, c));
end

function s = i_numOrEmpty(v)
    if isscalar(v) && isfinite(v), s = sprintf('%.5g', v); else, s = ''; end
end

function s = i_numOrEmpty0(v)
%I_NUMOREMPTY0  Seperti i_numOrEmpty tapi 0 -> '' (tak dibatasi).
    if isscalar(v) && isfinite(v) && v > 0, s = sprintf('%g', v); else, s = ''; end
end
