function GRAIN3(rootDir)
%GRAIN3  PRATINJAU hasil Step 2 (PIV .mat) — axMain validasi + POT analysis.
%
%   GRAIN3                 % pilih folder ROOT berisi .mat PIV (dialog)
%   GRAIN3(rootDir)        % langsung ke folder ROOT
%
%   = GRAINSA3, modul KETIGA seri GRAIN_SA. TUJUAN: pratinjau cepat output Step 2
%   (PAB_step_2) — berkas <expname>.mat (vektor PIV + GS tersemat, skema PIVlab
%   standar) di subfolder PIV_<tgl>/ atau folder .mat bebas. READ-ONLY: tak
%   meng-assign, tak menyimpan, tak menyentuh berkas. Sekadar LIHAT.
%
%   DUA baris axes (paradigma PIVTerry StandAlone step2):
%     - axMain (ATAS) = citra VALIDASI: bidang skalar (velocity_magnitude ATAU
%       shear strain bertanda du/dy+dv/dx) + overlay grayscale (alpha). Rentang
%       warna diatur; SLIDER FRAME men-scrub citra tiap bingkai. Di sinilah
%       GARIS PSG ditarik (klik 2 titik) — dasar POT analysis.
%     - axPOT (BAWAH) = POT analysis: kurva |V| sepanjang garis PSG, disampel
%       ON-THE-FLY dari .mat (pivcore.pot.step1Collect, IDENTIK PIVTerry Step 1
%       — ZERO duplikasi logika). Spaghetti semua titik + envelope MAX
%       (indenter) + indikator frame. TANPA koleksi/PIVTerry Step 1 lebih dulu.
%
%   Engine ilmiah dipakai-ulang dari +pivcore / +pivui (sudah di-addpath lewat
%   grain_setup). Jalankan `grain_setup` sekali per sesi lebih dulu.
%
%   Orientasi: identik step2 — grid PIVlab y menaik ke bawah; axMain di-flip-V
%   (imagesc YData [ymax ymin] + YDir normal) supaya TEGAK & konsisten dgn flip
%   yang dilakukan step1Collect saat sampling -> garis & kurva sejajar citra.

    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivcore.data.buildDataset'))
        % Pastikan +pivcore/+pivui di path (idempotent; grain_setup biasanya
        % sudah dijalankan, tapi jaga-jaga bila dipanggil langsung).
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
    end

    if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
        % Minimize tak relevan (belum ada figure utama); pilih folder.
        rootDir = uigetdir(pwd, ...
            'Pilih folder berisi .mat PIV (output Step 2 / PIV_<tgl>/)');
        if isequal(rootDir, 0), return; end
    end

    h           = struct();
    h.root      = rootDir;
    h.list      = struct('name',{},'file',{},'sizeMB',{},'nFrames',{});
    h.activeRow = 0;
    h.realData  = '';        % path .mat eksperimen aktif
    h.data      = [];        % dataset aktif (bingkai-1 ringan / penuh)
    h.fullLoaded= false;     % true bila h.data = SEMUA bingkai (scrub)
    h.imgFrames = 1;         % jumlah bingkai citra termuat
    h.recs      = [];        % records POT (on-the-fly; punya color)
    h.selRows   = [];        % indeks record terseleksi (sorot)
    h.nF        = 1;         % panjang deret POT (= rentang slider frame)
    cD = pivcore.util.climDefaults();   % default warna/CLim bersama
    gD = pivcore.util.glyphDefaults();  % default glyph bersama
    pD = pivcore.util.potDefaults();    % default POT/PSG bersama
    h.frame     = 1;         % bingkai aktif (indikator + scrub axMain)
    h.scalarSrc = 'velocity_magnitude';  % 'velocity_magnitude' | 'shear'
    h.climVel   = cD.velCLim;  % [min max] untuk velocity
    h.shearAbs  = cD.shearAbs;  % ±X untuk shear (CLim simetris [-X X])
    h.gsOn      = true;      % overlay grayscale aktif
    h.gsAlpha   = pD.gsAlpha;  % transparansi overlay grayscale
    h.claheOn   = true;      % CLAHE (kontras lokal) GS aktif (DEFAULT ON)
    h.adjOn     = true;      % auto kontras+brightness GS aktif (DEFAULT ON)
    h.glyphOn   = true;      % overlay glyph vektor (panah) aktif (DEFAULT ON)
    h.glyphLW   = gD.lineWidth;  % tebal garis glyph (default 1.2)
    h.glyphSp   = gD.spacing;    % spacing/decimation glyph (default tiap-3 node)
    h.xExt      = [];        % extent grid sumbu-x aktif
    h.yExt      = [];        % extent grid sumbu-y aktif
    h.line      = [];        % garis PSG aktif: struct('p1',[x y],'p2',[x y])
    h.roi       = [];        % images.roi.Line interaktif (draggable) di axMain
    h.psgFrac   = pD.psgFrac;  % fraksi tinggi garis PSG otomatis (0=atas,1=bawah)
    h.spacing   = NaN;       % spacing sampling titik POT (px); auto bila NaN
    h.indenter  = [];        % envelope MAX kurva (1xnF)
    h.yBase     = [];        % [ymin ymax] dasar axPOT
    h.vScale    = 1;         % skala vertikal axPOT
    h.geom      = [];        % geometri eksperimen (experiment_geometry .mat) / []

    h = i_buildUI(h);
    guidata(h.fig, h);
    i_initIndex(h.fig);
end


% =====================================================================
% UI (tema TERANG dipaksa)
% =====================================================================
function h = i_buildUI(h)
    WHITE = [1 1 1];
    h.fig = figure('Name',pivui.titleWithVersion('GRAINSA3 — Pratinjau output Step 2 (axMain + POT)'), ...
        'NumberTitle','off','Color',WHITE, ...
        'Units','pixels','Position',[60 50 1320 800], ...
        'MenuBar','none','ToolBar','figure');
    pivui.forceLightTheme(h.fig);
    fig = h.fig;

    % --- Panel kiri: folder + tabel eksperimen -----------------------
    pnlL = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.006 0.01 0.205 0.985],'Title','Berkas PIV (.mat)', ...
        'FontWeight','bold','BackgroundColor',WHITE);
    h.txtRoot = uicontrol('Parent',pnlL,'Style','text', ...
        'Units','normalized','Position',[0.03 0.945 0.94 0.045], ...
        'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'String',h.root);
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.90 0.46 0.045],'String','Pilih Folder…', ...
        'TooltipString','Pilih folder berisi .mat PIV (output Step 2).', ...
        'Callback',@(s,e) i_onPickFolder(fig));
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.90 0.46 0.045],'String','Segarkan', ...
        'TooltipString','Pindai ulang folder (termasuk subfolder PIV_<tgl>/).', ...
        'Callback',@(s,e) i_rescan(fig));
    h.tbl = uitable('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.02 0.94 0.86], ...
        'ColumnName',{'Eksperimen','MB','Frame'}, ...
        'ColumnWidth',{150 40 46}, ...
        'ColumnEditable',[false false false], ...
        'RowName',[],'FontSize',9, ...
        'CellSelectionCallback',@(s,e) i_onSelectRow(fig, e));

    % --- Strip kontrol tampilan (atas axMain, TIGA baris) ------------
    pnlC = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.220 0.895 0.560 0.098],'BackgroundColor',WHITE);
    % Baris 1 (atas): bidang skalar + rentang warna + GS alpha.
    h.btnDisp = uicontrol('Parent',pnlC,'Style','togglebutton', ...
        'Units','normalized','Position',[0.01 0.69 0.165 0.27], ...
        'String','Vel mag','Value',0,'FontWeight','bold', ...
        'TooltipString','Tukar bidang skalar axMain: Vel mag <-> Shear strain.', ...
        'Callback',@(s,e) i_onDisp(fig));
    h.txtLo = uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.19 0.69 0.06 0.26],'String','min:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE);
    h.edLo = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
        'Position',[0.255 0.70 0.085 0.26],'String','0', ...
        'TooltipString','Batas bawah warna (velocity).', ...
        'Callback',@(s,e) i_onClim(fig));
    h.txtHi = uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.345 0.69 0.06 0.26],'String','max:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE);
    h.edHi = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
        'Position',[0.41 0.70 0.085 0.26],'String','5', ...
        'TooltipString',['Velocity: batas atas warna. ', ...
                         'Shear: SATU angka ±X -> CLim [-X X] (simetris).'], ...
        'Callback',@(s,e) i_onClim(fig));
    uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.50 0.69 0.085 0.27],'String','Auto', ...
        'TooltipString',['Vel mag: batas atas = maks kurva indenter (bulat ke ', ...
                         'atas 0.5). Tanpa POT/shear: robustCLim bingkai aktif.'], ...
        'Callback',@(s,e) i_onAutoClim(fig));
    h.chkGS = uicontrol('Parent',pnlC,'Style','checkbox','Units','normalized', ...
        'Position',[0.60 0.70 0.155 0.26],'String','GS overlay','Value',1, ...
        'BackgroundColor',WHITE, ...
        'TooltipString','Overlay citra grayscale (dipaksa abu-abu) di atas bidang skalar.', ...
        'Callback',@(s,e) i_onGS(fig));
    uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.76 0.69 0.085 0.25],'String','alpha:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.edAlpha = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
        'Position',[0.85 0.70 0.085 0.26],'String',sprintf('%.2f',h.gsAlpha), ...
        'TooltipString','Transparansi overlay grayscale (0..1).', ...
        'Callback',@(s,e) i_onGS(fig));
    % Baris 2 (tengah): toggle GLYPH + CLAHE + auto kontras/brightness.
    h.chkGlyph = uicontrol('Parent',pnlC,'Style','checkbox','Units','normalized', ...
        'Position',[0.01 0.385 0.10 0.25],'String','Glyph','Value',1, ...
        'BackgroundColor',WHITE,'FontWeight','bold', ...
        'TooltipString','Overlay glyph vektor (panah) medan kecepatan. DEFAULT ON.', ...
        'Callback',@(s,e) i_onGlyph(fig));
    uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.155 0.385 0.05 0.24],'String','tebal:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.edGlyphLW = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
        'Position',[0.20 0.40 0.055 0.24],'String',sprintf('%g',h.glyphLW), ...
        'TooltipString','Tebal garis glyph (default 1.2).', ...
        'Callback',@(s,e) i_onGlyph(fig));
    uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.26 0.385 0.07 0.24],'String','spacing:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.edGlyphSp = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
        'Position',[0.335 0.40 0.05 0.24],'String',sprintf('%g',h.glyphSp), ...
        'TooltipString','Spacing glyph: ambil tiap-N node (default 3).', ...
        'Callback',@(s,e) i_onGlyph(fig));
    h.chkCLAHE = uicontrol('Parent',pnlC,'Style','checkbox','Units','normalized', ...
        'Position',[0.42 0.385 0.18 0.25],'String','CLAHE','Value',1, ...
        'BackgroundColor',WHITE, ...
        'TooltipString','CLAHE: kontras lokal adaptif GS. DEFAULT ON.', ...
        'Callback',@(s,e) i_onGS(fig));
    h.chkAdj = uicontrol('Parent',pnlC,'Style','checkbox','Units','normalized', ...
        'Position',[0.61 0.385 0.36 0.25],'String','Auto kontras+brightness', ...
        'Value',1,'BackgroundColor',WHITE, ...
        'TooltipString','Regang intensitas GS ke rentang optimum (imadjust). DEFAULT ON.', ...
        'Callback',@(s,e) i_onGS(fig));
    % Baris 3 (bawah): slider frame + label + muat semua bingkai + montase.
    uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.01 0.06 0.075 0.24],'String','Frame:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE);
    h.sldFrame = uicontrol('Parent',pnlC,'Style','slider','Units','normalized', ...
        'Position',[0.09 0.07 0.50 0.23],'Min',1,'Max',2,'Value',1, ...
        'SliderStep',[1 10]/1, ...
        'TooltipString','Geser untuk men-scrub bingkai citra axMain (validasi).', ...
        'Callback',@(s,e) i_onFrameSlider(fig));
    h.txtFrame = uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.595 0.06 0.080 0.24],'String','f 1/1', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.69 0.065 0.155 0.25],'String','Muat semua', ...
        'TooltipString','Muat seluruh bingkai -> slider men-scrub citra (sekali, agak lama).', ...
        'Callback',@(s,e) i_onLoadFull(fig));
    uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.85 0.065 0.14 0.25],'String','Montase…', ...
        'FontWeight','bold', ...
        'TooltipString',['Susun montase panel-panel (grid kustom / 2-kolom ', ...
                         'vel|shear) dari bingkai eksperimen aktif -> simpan PNG.'], ...
        'Callback',@(s,e) i_onMontage(fig));

    % --- axMain (atas) + axPOT (bawah) -------------------------------
    h.axMain = axes('Parent',fig,'Units','normalized', ...
        'Position',[0.250 0.505 0.520 0.385]);
    % axMain HANYA untuk mengatur garis PSG: matikan pan/zoom interaktif
    % (scroll-zoom, drag-pan, datatip) supaya klik tak menggeser tampilan.
    % Tampilan dikunci zoom-fit (xlim/ylim = extent penuh) di i_renderMain.
    i_lockAxInteractions(h.axMain);
    title(h.axMain,'axMain — pilih eksperimen di kiri');
    h.axPOT = axes('Parent',fig,'Units','normalized', ...
        'Position',[0.250 0.065 0.520 0.325]);
    title(h.axPOT,'axPOT — POT analysis (tarik garis PSG di axMain)');
    xlabel(h.axPOT,'Frame'); ylabel(h.axPOT,'|V| (px/frame)');

    % --- Strip kontrol POT (antara axMain & axPOT) -------------------
    uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.220 0.430 0.130 0.034],'String','— max indenter (auto)', ...
        'HorizontalAlignment','left','FontWeight','bold','FontSize',8, ...
        'ForegroundColor',[0 0 0],'BackgroundColor',WHITE, ...
        'TooltipString','Envelope MAX semua kurva POT -> garis hitam tebal di axPOT.');
    uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.355 0.432 0.110 0.036],'String','Tarik garis PSG', ...
        'TooltipString',['Klik 2 titik di axMain untuk menetapkan garis sampling ', ...
                         'POT, lalu kurva |V| dihitung & ditampilkan di axPOT.'], ...
        'Callback',@(s,e) i_onDrawLine(fig));
    uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.467 0.432 0.060 0.036],'String','Hapus', ...
        'TooltipString','Hapus garis PSG & kosongkan axPOT.', ...
        'Callback',@(s,e) i_onClearLine(fig));
    uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.532 0.430 0.070 0.034],'String','Spacing px:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Jarak antar titik sampel sepanjang garis (px). Kosong = auto.');
    h.edSpacing = uicontrol('Parent',fig,'Style','edit','Units','normalized', ...
        'Position',[0.604 0.432 0.040 0.034],'String','auto', ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Spacing sampling (px). "auto" = nodeSpacing data.', ...
        'Callback',@(s,e) i_onSpacing(fig));
    uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.650 0.430 0.054 0.034],'String','Skala-V:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    Lv = pivcore.pot.vscale.levels();
    h.sldVScale = uicontrol('Parent',fig,'Style','slider','Units','normalized', ...
        'Position',[0.706 0.434 0.064 0.032], ...
        'Min',Lv(1),'Max',Lv(end),'Value',pivcore.pot.vscale.defaultLevel(), ...
        'SliderStep',[0.25 0.5]/(Lv(end)-Lv(1)), ...
        'TooltipString','Skala vertikal axPOT (snap 0.25..2x). Sumbu-frame dijaga.', ...
        'Callback',@(s,e) i_onVScale(fig));

    % --- Panel kanan: info ringkas ----------------------------------
    pnlR = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.782 0.01 0.213 0.985],'Title','Info', ...
        'FontWeight','bold','BackgroundColor',WHITE);
    h.txtInfo = uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 0.04 0.92 0.93],'HorizontalAlignment','left', ...
        'FontSize',9,'BackgroundColor',WHITE, ...
        'String',{'Pratinjau READ-ONLY output Step 2.', '', ...
                  '1. Pilih folder & eksperimen.', ...
                  '2. axMain = validasi |V|/shear + GS.', ...
                  '3. Garis PSG OTOMATIS (70%) + POT', ...
                  '   langsung disampel & diplot.', ...
                  '4. Edit garis: "Tarik garis PSG".', ...
                  '5. "Montase…" -> simpan PNG panel.', '', ...
                  'Tak ada perubahan disimpan.'});

    % --- Status (strip bawah) ----------------------------------------
    h.txtStatus = uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.220 0.008 0.560 0.03], ...
        'HorizontalAlignment','left','FontSize',9, ...
        'BackgroundColor',WHITE, ...
        'String','Pilih folder lalu sebuah eksperimen dari tabel di kiri.');

    i_syncClimControls(h);
end


% =====================================================================
% Pindai folder -> daftar .mat PIV (termasuk subfolder PIV_<tgl>/)
% =====================================================================
function i_onPickFolder(fig)
    h = guidata(fig);
    i_minimize(fig);
    d = uigetdir(h.root, 'Pilih folder berisi .mat PIV (output Step 2)');
    i_restore(fig);
    if isequal(d, 0), return; end
    h.root = d; set(h.txtRoot,'String',d);
    guidata(fig, h);
    i_initIndex(fig);
end


function i_initIndex(fig)
    i_rescan(fig);
end


function i_rescan(fig)
%I_RESCAN  Pindai folder root (+ subfolder PIV_*) -> daftar .mat PIVlab.
%   "PIV .mat" = berkas .mat dgn variabel x ATAU velocity_magnitude (deteksi
%   murah via whos, tanpa load isi). Berkas progres (_autopot, *progress*)
%   diabaikan. Metadata ringan: ukuran MB + jumlah bingkai (panjang cell x).
    h = guidata(fig);
    i_setStatus(fig, 'Memindai folder…'); set(fig,'Pointer','watch'); drawnow;
    cleaner = onCleanup(@() set(fig,'Pointer','arrow'));

    files = i_collectMats(h.root);
    list  = struct('name',{},'file',{},'sizeMB',{},'nFrames',{});
    for i = 1:numel(files)
        f = files{i};
        [meta, ok] = i_probeMat(f);
        if ~ok, continue; end
        [~, base] = fileparts(f);
        list(end+1) = struct('name', base, 'file', f, ...
            'sizeMB', meta.sizeMB, 'nFrames', meta.nFrames); %#ok<AGROW>
    end
    h.list = list; guidata(fig, h);
    i_fillTable(fig);
    if isempty(list)
        i_setStatus(fig, 'Tak ada .mat PIV ditemukan. Coba folder PIV_<tgl>/ output Step 2.');
    else
        i_setStatus(fig, sprintf('%d berkas PIV ditemukan. Pilih satu untuk pratinjau.', ...
            numel(list)));
    end
end


% --- pemindai .mat keluaran Step 2: forwarder ke pivanalyzemat.core (satu sumber) ---
function files = i_collectMats(root),  files = pivanalyzemat.core.scanPivMats(root);  end
function [meta, ok] = i_probeMat(f),   [meta, ok] = pivanalyzemat.core.probePivMat(f); end


function i_fillTable(fig)
    h = guidata(fig);
    n = numel(h.list);
    C = cell(n, 3);
    for i = 1:n
        e = h.list(i);
        C{i,1} = e.name;
        C{i,2} = sprintf('%.0f', e.sizeMB);
        C{i,3} = num2str(e.nFrames);
    end
    set(h.tbl, 'Data', C);
end


function i_onSelectRow(fig, evt)
    if isempty(evt) || isempty(evt.Indices), return; end
    row = evt.Indices(1,1);
    h = guidata(fig);
    if row < 1 || row > numel(h.list), return; end
    i_loadExperiment(fig, row);
end


% =====================================================================
% Muat eksperimen (bingkai-1 ringan; reset garis POT)
% =====================================================================
function i_loadExperiment(fig, row)
    h = guidata(fig);
    df = h.list(row).file;
    [~, base] = fileparts(df);

    h.activeRow  = row;
    h.realData   = df;
    h.data       = [];
    h.fullLoaded = false;
    h.imgFrames  = 1;
    h.recs       = [];
    h.selRows    = [];
    h.frame      = 1;
    h.line       = [];
    if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
    h.roi        = [];
    h.indenter   = [];
    h.geom       = i_loadGeom(df);   % geometri X0/X1/L_pos (strain) bila ada
    guidata(fig, h);

    i_setStatus(fig, sprintf('Memuat bingkai-1: %s …', base));
    set(fig,'Pointer','watch'); drawnow;
    cleaner = onCleanup(@() set(fig,'Pointer','arrow'));
    try
        data1 = pivcore.io.step1Session.loadFrame1(df);
    catch ME
        i_setStatus(fig, sprintf('GAGAL memuat %s: %s', base, ME.message));
        return;
    end

    h = guidata(fig);
    h.data      = data1;
    h.imgFrames = pivcore.data.frameCount(data1);   % bingkai citra TERMUAT (=1, lazy)
    % Rentang slider = jumlah bingkai SEBENARNYA di berkas (dari probe tabel),
    % bukan yg termuat (1). Geser slider > imgFrames -> i_ensureFull memuat penuh.
    nfTrue = 1;
    if row >= 1 && row <= numel(h.list)
        nfTrue = i_scalar(h.list(row).nFrames, 1);
    end
    h.nF        = max(1, max(nfTrue, h.imgFrames));
    h.frame     = 1;
    x = pivcore.data.safeFrame(data1.x, 1);
    y = pivcore.data.safeFrame(data1.y, 1);
    if ~isempty(x) && ~isempty(y)
        h.xExt = [min(x(:)) max(x(:))];
        h.yExt = [min(y(:)) max(y(:))];
    end
    guidata(fig, h);

    i_autoClimFromFrame(fig, 1);
    i_syncFrameSlider(fig);
    i_renderMain(fig);

    % --- AUTO PSG: garis horizontal end-to-end di 70% tinggi (dari atas) ---
    % Tujuan modul ini PRATINJAU: garis dibuat OTOMATIS (bukan diminta tarik),
    % semua bingkai dimuat, POT langsung disampel & diplot. User tinggal EDIT
    % garis bila perlu (drag/Tarik ulang). Grid y menaik ke bawah -> 70% ke
    % bawah = yExt(1) + 0.70*(yExt(2)-yExt(1)).
    i_autoPSG(fig);

    i_updateInfo(fig);
    h = guidata(fig);
    i_setStatus(fig, sprintf(['%s: %d bingkai. Garis PSG OTOMATIS (70%%) -> POT ', ...
        'siap. Edit garis lewat "Tarik garis PSG" bila perlu.'], base, h.imgFrames));
end


function i_autoPSG(fig)
%I_AUTOPSG  Buat garis PSG horizontal end-to-end (default 70% tinggi) sebagai
%   ROI INTERAKTIF (draggable, marker lingkaran di ujung — pola PIVTerry Step1),
%   muat semua bingkai, lalu sampel POT otomatis. Dipakai saat eksperimen
%   dimuat — meniadakan langkah "tarik garis" manual untuk pratinjau cepat.
    h = guidata(fig);
    if isempty(h.data), return; end
    xE = h.xExt; yE = h.yExt;
    if isempty(xE) || isempty(yE), return; end
    frac = h.psgFrac; if ~(isfinite(frac) && frac >= 0 && frac <= 1), frac = 0.70; end
    yL = yE(1) + frac * (yE(2) - yE(1));
    h.line = struct('p1',[xE(1) yL], 'p2',[xE(2) yL]);
    guidata(fig, h);
    i_ensureROI(fig);           % ROI draggable orange (bukan garis statis)
    i_collectPOT(fig);          % muat semua bingkai (i_ensureFull) + sampel POT
end


function i_ensureROI(fig)
%I_ENSUREROI  Buat/segarkan garis PSG INTERAKTIF (images.roi.Line) di axMain
%   dari h.line — DRAGGABLE, warna oranye, marker LINGKARAN di ujung. Pola
%   identik PIVTerry StandAlone Step 1 (cara tarik garis terbaik). Geser ujung
%   -> listener re-sampel POT otomatis (i_onROIMoved).
    h = guidata(fig);
    if isempty(h.line) || ~ishghandle(h.axMain), return; end
    if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
    % Buat ROI garis PSG (warna/LW/MS dari pivui.potStyle) + listener ROIMoved
    % -> re-sampel POT begitu user SELESAI menggeser (bukan tiap piksel -> ringan).
    roi = pivui.makePsgLineROI(h.axMain, h.line.p1, h.line.p2, @() i_onROIMoved(fig));
    h.roi = roi; guidata(fig, h);
end


function i_onROIMoved(fig)
%I_ONROIMOVED  Dipicu saat ROI garis PSG selesai digeser -> ambil posisi
%   terkini -> re-sampel POT. Tampilan axMain TAK di-render ulang (ROI sudah
%   bergerak sendiri) supaya mulus.
    h = guidata(fig);
    L = i_currentLine(h);
    if isempty(L), return; end
    h.line = L; guidata(fig, h);
    i_collectPOT(fig);
end


function L = i_currentLine(h)
%I_CURRENTLINE  Posisi garis PSG TERKINI — forwarder ke pivui.currentLineFromROI
%   (utamakan ROI yang mungkin sudah digeser user; fallback h.line tersimpan).
    roi = [];
    if isfield(h,'roi'), roi = h.roi; end
    L = pivui.currentLineFromROI(roi, h.line);
end


% =====================================================================
% Muat semua bingkai (lazy) — scrub citra axMain & sampling POT penuh
% =====================================================================
function ok = i_ensureFull(fig)
    ok = false;
    h = guidata(fig);
    if i_isFull(h) && ~isempty(h.data), ok = true; return; end
    if isempty(h.realData), return; end
    [~, base] = fileparts(h.realData);
    i_setStatus(fig, sprintf('Memuat SEMUA bingkai: %s …', base));
    set(fig,'Pointer','watch'); drawnow;
    cleaner = onCleanup(@() set(fig,'Pointer','arrow'));
    if pivui.quiet(), wb = []; else   % tes senyap: tanpa waitbar
        wb = waitbar(0.2, sprintf('Memuat semua bingkai %s…', base)); pivui.forceLightTheme(wb);
    end
    try
        data = pivcore.io.step1Session.loadAllFrames(h.realData);
    catch ME
        pivcore.util.safeCloseWb(wb);
        i_setStatus(fig, sprintf('GAGAL memuat semua bingkai: %s', ME.message));
        return;
    end
    pivcore.util.safeCloseWb(wb);
    h = guidata(fig);
    h.data       = data;
    h.fullLoaded = true;
    h.imgFrames  = pivcore.data.frameCount(data);
    x = pivcore.data.safeFrame(data.x, 1);
    y = pivcore.data.safeFrame(data.y, 1);
    if ~isempty(x) && ~isempty(y)
        h.xExt = [min(x(:)) max(x(:))];
        h.yExt = [min(y(:)) max(y(:))];
    end
    guidata(fig, h);
    ok = true;
end


function i_onLoadFull(fig)
    h = guidata(fig);
    if isempty(h.realData), i_setStatus(fig,'Pilih eksperimen dulu.'); return; end
    if ~i_ensureFull(fig), return; end
    i_renderMain(fig);
    h = guidata(fig);
    i_setStatus(fig, sprintf('Semua %d bingkai dimuat. Geser slider untuk men-scrub.', ...
        h.imgFrames));
end


% =====================================================================
% Render axMain (overlay skalar + grayscale alpha) — sama pola step2
% =====================================================================
function i_renderMain(fig)
    h = guidata(fig);
    ax = h.axMain;
    if isempty(h.data), return; end
    % Tangkap posisi ROI TERKINI (mungkin baru digeser) sebelum cla() menghapus
    % ROI -> garis dibuat ulang di posisi terbaru, bukan posisi lama.
    L = i_currentLine(h);
    if ~isempty(L), h.line = L; guidata(fig, h); end
    k = max(1, min(i_scalar(h.frame,1), i_scalar(h.imgFrames,1)));

    x = pivcore.data.safeFrame(h.data.x, k);
    y = pivcore.data.safeFrame(h.data.y, k);
    if isempty(x) || isempty(y)
        x = pivcore.data.safeFrame(h.data.x, 1);
        y = pivcore.data.safeFrame(h.data.y, 1);
        k = 1;
    end
    if isempty(x) || isempty(y), return; end
    xExt = [min(x(:)) max(x(:))];
    yExt = [min(y(:)) max(y(:))];

    cla(ax); colorbar(ax,'off');

    % --- Inti lukis (skalar+GS+glyph) via SUMBER TUNGGAL bersama montase ---
    % pivcore.montage.renderScalarPanel = pola identik i_drawPanel montase: ia
    % menggambar imagesc(flip-V)+GS+glyph & menata sumbu (YDir/xlim/ylim/daspect/
    % box/Layer). TAK menggambar colorbar/label/teks-kosong/judul — itu chrome
    % khas GUI yang TETAP di sini (lihat di bawah). h memuat semua field cfg
    % (gsOn/gsAlpha/claheOn/adjOn/glyphOn/glyphLW/glyphSp/shearAbs/climVel).
    pivcore.montage.renderScalarPanel(ax, h.data, k, h.scalarSrc, h);

    % Chrome GUI: colorbar+label bila skalar ada, atau teks "kosong" bila tidak.
    % Z di-resolve ulang (ringan vs render) HANYA utk cek kosong & ambil label;
    % frame k = identik dgn yang dipakai core -> konsisten.
    if strcmp(h.scalarSrc, 'shear')
        Z = pivcore.data.computeShearRate(h.data, k, 'mode','engineering');
        lab = 'shear strain (du/dy+dv/dx)';
    else
        [Z, lab] = pivcore.data.resolveScalar(h.data, 'velocity_magnitude', k);
    end
    if ~isempty(Z)
        cb = colorbar(ax); cb.Label.String = lab;
    else
        text(ax, 0.5, 0.5, sprintf('Bidang "%s" kosong di bingkai %d', lab, k), ...
            'Units','normalized','HorizontalAlignment','center');
    end

    set(ax, 'YDir','normal');
    xlim(ax, xExt); ylim(ax, yExt);        % zoom-fit: selalu tampil area penuh
    daspect(ax, [1 1 1]); set(ax, 'Layer','top'); box(ax,'on');
    i_lockAxInteractions(ax);              % cla() bisa reset -> kunci ulang
    title(ax, sprintf('axMain — %s — bingkai %d/%d', i_baseName(h.realData), ...
        k, h.imgFrames), 'Interpreter','none');

    h.xExt = xExt; h.yExt = yExt;
    guidata(fig, h);
    % cla() di atas menghapus ROI -> buat ulang ROI interaktif (bukan garis
    % statis) supaya tetap draggable setelah scrub frame / ganti skalar.
    if ~isempty(h.line), i_ensureROI(fig); end
end


% =====================================================================
% Garis PSG di axMain -> POT on-the-fly
% =====================================================================
function i_onDrawLine(fig)
%I_ONDRAWLINE  Tarik garis PSG baru dengan DRAWLINE (rubber-band, kursor jadi
%   silang) — pola PIVTerry Step 1: klik-tahan-seret 2 ujung. Hasilnya ROI
%   draggable (marker lingkaran) yang langsung re-sampel POT. JAUH lebih
%   mudah daripada klik-2-titik lama.
    h = guidata(fig);
    if isempty(h.data)
        i_setStatus(fig, 'Pilih eksperimen dulu sebelum menarik garis.');
        return;
    end
    if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
    i_clearFigModes(fig);   % pastikan tak ada mode pan/zoom aktif saat menarik
    i_setStatus(fig, 'Seret garis PSG di axMain (klik-tahan dari ujung ke ujung)…');
    ps = pivui.potStyle().psgLine;   % warna/LW/MS PSG dari sumber gaya bersama
    roi = drawline(h.axMain, 'Color',ps.color, 'LineWidth',ps.lineWidth, ...
        'MarkerSize',ps.markerSize, 'Label','PSG', 'LabelVisible','hover');
    if isempty(roi) || ~isvalid(roi) || isempty(roi.Position)
        guidata(fig, h); i_ensureROI(fig);       % batal -> pulihkan garis lama
        i_setStatus(fig, 'Batal menarik garis (garis lama dipulihkan).');
        return;
    end
    addlistener(roi, 'ROIMoved', @(s,e) i_onROIMoved(fig));
    h.roi  = roi;
    h.line = struct('p1', roi.Position(1,:), 'p2', roi.Position(2,:));
    guidata(fig, h);
    i_collectPOT(fig);
    i_setStatus(fig, 'Garis PSG ditetapkan. Seret ujungnya untuk menyetel.');
end


function i_onClearLine(fig)
    h = guidata(fig);
    h.line = []; h.recs = []; h.selRows = []; h.indenter = [];
    if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
    h.roi = [];
    guidata(fig, h);
    try, delete(findall(h.axMain,'Tag','psgLine')); catch, end
    i_renderPOT(fig);
    i_setStatus(fig, 'Garis PSG dihapus.');
end


function i_collectPOT(fig)
%I_COLLECTPOT  Sampel kurva POT sepanjang garis PSG aktif (semua bingkai) via
%   pivcore.pot.step1Collect — IDENTIK PIVTerry Step 1 (zero duplikasi). Butuh
%   semua bingkai -> i_ensureFull.
    h = guidata(fig);
    % Pakai posisi ROI terkini bila ada (sumber kebenaran garis saat digeser).
    L = i_currentLine(h);
    if ~isempty(L), h.line = L; guidata(fig, h); end
    if isempty(h.line) || isempty(h.realData), return; end
    if ~i_ensureFull(fig), return; end
    h = guidata(fig);

    sp = i_scalar(h.spacing, NaN);
    if ~(isfinite(sp) && sp > 0)
        dd = pivcore.data.nodeSpacing(h.data);
        if isfinite(dd) && dd > 0, sp = round(dd); else, sp = 10; end
    end

    i_setStatus(fig, 'Menyampel POT sepanjang garis PSG…');
    set(fig,'Pointer','watch'); drawnow;
    cleaner = onCleanup(@() set(fig,'Pointer','arrow'));
    try
        recs = pivcore.pot.step1Collect.collectAlongLine( ...
            h.data, h.line.p1, h.line.p2, sp, 'velocity_magnitude');
    catch ME
        i_setStatus(fig, sprintf('GAGAL menyampel POT: %s', ME.message));
        return;
    end
    recs = pivcore.pot.records.normalize(recs);
    recs = pivcore.pot.records.applyColors(recs);

    h = guidata(fig);
    h.recs = recs;
    nF = 0;
    for r = 1:numel(recs), nF = max(nF, numel(recs(r).data)); end
    h.nF = max(1, nF);
    guidata(fig, h);
    i_syncFrameSlider(fig);
    i_renderPOT(fig);                 % set h.indenter (envelope MAX)
    i_climFromIndenter(fig);          % CLim Vel mag atas = ceil(maks indenter,0.5)
    i_updateInfo(fig);
    i_setStatus(fig, sprintf('POT: %d titik sepanjang garis (spacing %d px).', ...
        numel(recs), sp));
end


% =====================================================================
% Render axPOT (spaghetti + indikator frame + klik kurva)
% =====================================================================
function i_renderPOT(fig)
    h = guidata(fig);
    ax = h.axPOT;
    cla(ax);
    set(ax,'Color','w','XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
           'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top');
    hold(ax,'on');

    if isempty(h.recs)
        text(ax,0.5,0.5,'Tarik garis PSG di axMain untuk POT analysis', ...
            'Units','normalized','HorizontalAlignment','center', ...
            'Color',[0.5 0.5 0.5]);
        hold(ax,'off'); xlabel(ax,'Frame'); ylabel(ax,'|V| (px/frame)');
        grid(ax,'on'); title(ax,'axPOT — POT analysis');
        h.indenter = []; h.yBase = []; guidata(fig, h);
        return;
    end
    nF = h.nF;
    env = i_indenterEnvelope(h);

    ymin = inf; ymax = -inf;
    order = 1:numel(h.recs);
    for r = order
        [xv, yv] = pivcore.pot.records.curveXY(h.recs(r), nF);
        g = isfinite(xv) & isfinite(yv); if ~any(g), continue; end
        col = h.recs(r).color; if numel(col) ~= 3, col = [0.4 0.4 0.4]; end
        plot(ax, xv(g), yv(g), '-', 'Color', col, 'LineWidth',1.0, ...
            'UserData', r, 'Tag','potCurve', ...
            'ButtonDownFcn', @(s,e) i_onCurveClick(fig, s));
        ymin = min(ymin, min(yv(g))); ymax = max(ymax, max(yv(g)));
    end

    if ~isempty(env)
        xe = 1:numel(env); ge = isfinite(env);
        if any(ge)
            plot(ax, xe(ge), env(ge), '-', 'Color',[0 0 0], 'LineWidth',3, ...
                'Tag','potIndenter','HitTest','off','PickableParts','none');
            ymin = min(ymin, min(env(ge))); ymax = max(ymax, max(env(ge)));
        end
    end

    hold(ax,'off');
    xlabel(ax,'Frame'); ylabel(ax,'|V| (px/frame)');
    title(ax, sprintf('axPOT — %d kurva (garis hitam = max indenter)', ...
            numel(order)), 'Color',[0 0 0]);
    grid(ax,'on');
    set(ax,'ButtonDownFcn',@(s,e) i_onAxPotClick(fig));
    if nF > 1, xlim(ax, [1 nF]); end

    if isfinite(ymin) && isfinite(ymax) && ymax > ymin
        h.yBase = [ymin ymax];
    else
        h.yBase = [];
    end
    h.indenter = env;
    guidata(fig, h);

    i_applyVScale(fig);
    i_highlightSelPOT(fig);
    i_updateFrameLine(fig);
end


function env = i_indenterEnvelope(h)
%I_INDENTERENVELOPE  Envelope MAX semua kurva (di-MA via curveXY) pada tiap
%   frame -> 1 x nF. [] bila tak ada kurva.
    env = [];
    if isempty(h.recs), return; end
    nF = h.nF;
    M = -inf(1, nF);
    any_ = false;
    for r = 1:numel(h.recs)
        [~, yv] = pivcore.pot.records.curveXY(h.recs(r), nF);
        if isempty(yv), continue; end
        m = numel(yv);
        seg = M(1:m);
        g = isfinite(yv);
        seg(g) = max(seg(g), yv(g));
        M(1:m) = seg; any_ = true;
    end
    if ~any_, return; end
    M(~isfinite(M)) = NaN;
    env = M;
end


function i_climFromIndenter(fig)
%I_CLIMFROMINDENTER  Set batas ATAS CLim Vel mag dari MAKS kurva indenter-max
%   (envelope POT), dibulatkan KE ATAS ke kelipatan 0.5 (3.3->3.5, 4.7->5.0).
%   Batas bawah tetap 0. Dipanggil otomatis tiap POT (re)disampel. Bila skalar
%   aktif = Vel mag, axMain di-render ulang agar warna langsung mengikuti.
    h = guidata(fig);
    if isempty(h.indenter), return; end
    mx = max(h.indenter(isfinite(h.indenter)));
    if isempty(mx) || ~isfinite(mx) || mx <= 0, return; end
    hi = pivcore.util.snapClim(mx);     % bulat ke atas kelipatan 0.5 (kernel bersama)
    if hi <= 0, return; end
    h.climVel = [0 hi];
    guidata(fig, h);
    i_syncClimControls(h);              % perbarui kotak min/max bila vel aktif
    if strcmp(h.scalarSrc, 'velocity_magnitude') && ~isempty(h.data)
        i_renderMain(fig);
    end
end


function i_updateFrameLine(fig)
    h = guidata(fig);
    ax = h.axPOT;
    if ~ishghandle(ax), return; end
    try
        delete(findall(ax,'Tag','frameLine'));
        delete(findall(ax,'Tag','frameTxt'));
    catch
    end
    if isempty(h.recs), return; end
    yl = get(ax,'YLim');
    k = max(1, min(h.frame, h.nF));
    hs = ishold(ax); hold(ax,'on');
    plot(ax, [k k], yl, '-', 'Color',[0.10 0.45 0.90], 'LineWidth',1.4, ...
        'Tag','frameLine','HitTest','off','PickableParts','none');
    text(ax, k, yl(2), sprintf(' f%d', k), 'Color',[0.10 0.45 0.90], ...
        'VerticalAlignment','top','FontSize',8,'FontWeight','bold', ...
        'Tag','frameTxt','HitTest','off','PickableParts','none');
    if ~hs, hold(ax,'off'); end
end


function i_highlightSelPOT(fig)
    h = guidata(fig);
    ax = h.axPOT;
    if ~ishghandle(ax), return; end
    try, delete(findall(ax,'Tag','selCurve')); catch, end
    rows = h.selRows(:).';
    rows = rows(rows >= 1 & rows <= numel(h.recs));
    if isempty(rows), return; end
    nF = h.nF;
    hs = ishold(ax); hold(ax,'on');
    for r = rows
        [xv, yv] = pivcore.pot.records.curveXY(h.recs(r), nF);
        g = isfinite(xv) & isfinite(yv); if ~any(g), continue; end
        plot(ax, xv(g), yv(g), '-', 'Color',[1 0 0], 'LineWidth',3.0, ...
            'Tag','selCurve','HitTest','off','PickableParts','none');
    end
    if ~hs, hold(ax,'off'); end
end


function i_applyVScale(fig)
%I_APPLYVSCALE  Set YLim axPOT sesuai skala vertikal (XLim tak disentuh).
%   Skala <1 mengecil (zoom-out), >1 memperbesar (zoom-in) relatif yBase.
    h = guidata(fig);
    ax = h.axPOT;
    if ~ishghandle(ax) || isempty(h.yBase), return; end
    yb = h.yBase; c = (yb(1)+yb(2))/2; half = (yb(2)-yb(1))/2;
    s = h.vScale; if ~(isfinite(s) && s > 0), s = 1; end
    half = half / s;
    if half <= 0, return; end
    ylim(ax, [c-half c+half]);
end


function i_onVScale(fig)
    h = guidata(fig);
    v = get(h.sldVScale,'Value');
    v = pivcore.pot.vscale.snap(v);
    set(h.sldVScale,'Value',v);
    h.vScale = v; guidata(fig, h);
    i_applyVScale(fig);
    i_updateFrameLine(fig);
end


% =====================================================================
% Klik kurva / klik area kosong axPOT
% =====================================================================
function i_onCurveClick(fig, src)
    if ~ishghandle(src), return; end
    r = get(src,'UserData');
    if ~isscalar(r) || ~isfinite(r), return; end
    h = guidata(fig);
    if r < 1 || r > numel(h.recs), return; end
    h.selRows = r; guidata(fig, h);
    i_highlightSelPOT(fig);
    pt = h.recs(r).point; if isempty(pt), pt = sprintf('P-%d', r); end
    i_setStatus(fig, sprintf('Kurva "%s" (titik %d) terpilih.', pt, r));
end


function i_onAxPotClick(fig)
%I_ONAXPOTCLICK  Klik area kosong axPOT -> pindahkan indikator frame.
    h = guidata(fig);
    if isempty(h.recs), return; end
    cp = get(h.axPOT,'CurrentPoint');
    k = round(cp(1,1));
    k = i_scalar(k, 1);
    k = max(1, min(k, i_scalar(h.nF,1)));
    h.frame = k; guidata(fig, h);
    if k > 1 && ~i_isFull(h), i_ensureFull(fig); end
    i_renderMain(fig);
    i_updateFrameLine(fig);
    i_syncFrameSlider(fig);
    h = guidata(fig);
    set(h.txtFrame,'String', sprintf('f %d/%d', i_scalar(h.frame,1), i_scalar(h.nF,1)));
end


% =====================================================================
% Kontrol tampilan
% =====================================================================
function i_onDisp(fig)
    h = guidata(fig);
    if get(h.btnDisp,'Value') == 1
        h.scalarSrc = 'shear';              set(h.btnDisp,'String','Shear strain');
    else
        h.scalarSrc = 'velocity_magnitude'; set(h.btnDisp,'String','Vel mag');
    end
    guidata(fig, h);
    i_syncClimControls(h);
    if isempty(h.data), return; end
    i_renderMain(fig);
end


function i_onClim(fig)
    h = guidata(fig);
    lo = str2double(get(h.edLo,'String'));
    hi = str2double(get(h.edHi,'String'));
    if strcmp(h.scalarSrc, 'shear')
        if isfinite(hi) && hi > 0, h.shearAbs = hi; end
    else
        if isfinite(lo) && isfinite(hi) && hi > lo, h.climVel = [lo hi]; end
    end
    guidata(fig, h);
    i_syncClimControls(h);
    i_renderMain(fig);
end


function i_onAutoClim(fig)
    h = guidata(fig);
    if isempty(h.data), return; end
    % Vel mag: utamakan indenter-max (ceil 0.5) bila POT sudah ada -> konsisten
    % dgn auto-CLim otomatis. Tanpa POT (atau mode shear) -> robustCLim frame.
    if strcmp(h.scalarSrc,'velocity_magnitude') && ~isempty(h.indenter) ...
            && any(isfinite(h.indenter))
        i_climFromIndenter(fig);
        return;
    end
    i_autoClimFromFrame(fig, max(1, min(h.frame, h.imgFrames)));
    h = guidata(fig);
    i_syncClimControls(h);
    i_renderMain(fig);
end


function i_autoClimFromFrame(fig, k)
    h = guidata(fig);
    if isempty(h.data), return; end
    if strcmp(h.scalarSrc, 'shear')
        Z = pivcore.data.computeShearRate(h.data, k, 'mode','engineering');
        if any(isfinite(Z(:)))
            c = pivcore.util.robustCLim(abs(Z));
            if c(2) > 0, h.shearAbs = c(2); end
        end
    else
        Z = pivcore.data.resolveScalar(h.data, 'velocity_magnitude', k);
        if any(isfinite(Z(:))), h.climVel = pivcore.util.robustCLim(Z); end
    end
    guidata(fig, h);
end


function i_syncClimControls(h)
    if strcmp(h.scalarSrc, 'shear')
        set(h.txtLo,'String','±:');
        set(h.edLo,'String', sprintf('-%g', h.shearAbs), 'Enable','off');
        set(h.txtHi,'String','X:');
        set(h.edHi,'String', sprintf('%g', h.shearAbs), 'Enable','on');
    else
        set(h.txtLo,'String','min:');
        set(h.edLo,'String', sprintf('%g', h.climVel(1)), 'Enable','on');
        set(h.txtHi,'String','max:');
        set(h.edHi,'String', sprintf('%g', h.climVel(2)), 'Enable','on');
    end
end


function i_onGS(fig)
    h = guidata(fig);
    h.gsOn = get(h.chkGS,'Value') == 1;
    a = str2double(get(h.edAlpha,'String'));
    if isfinite(a) && a >= 0 && a <= 1, h.gsAlpha = a; end
    set(h.edAlpha,'String', sprintf('%.2f', h.gsAlpha));
    % Toggle CLAHE & auto kontras/brightness (keduanya untuk overlay GS).
    if isfield(h,'chkCLAHE') && ishghandle(h.chkCLAHE)
        h.claheOn = get(h.chkCLAHE,'Value') == 1;
    end
    if isfield(h,'chkAdj') && ishghandle(h.chkAdj)
        h.adjOn = get(h.chkAdj,'Value') == 1;
    end
    guidata(fig, h);
    if isempty(h.data), return; end
    i_renderMain(fig);
end


function i_onGlyph(fig)
%I_ONGLYPH  Toggle glyph + baca tebal garis & spacing.
    h = guidata(fig);
    h.glyphOn = get(h.chkGlyph,'Value') == 1;
    lw = str2double(get(h.edGlyphLW,'String'));
    if isfinite(lw) && lw > 0, h.glyphLW = lw; end
    set(h.edGlyphLW,'String', sprintf('%g', h.glyphLW));
    sp = str2double(get(h.edGlyphSp,'String'));
    if isfinite(sp) && sp >= 1, h.glyphSp = round(sp); end
    set(h.edGlyphSp,'String', num2str(h.glyphSp));
    guidata(fig, h);
    if isempty(h.data), return; end
    i_renderMain(fig);
end


function i_onSpacing(fig)
    h = guidata(fig);
    s = strtrim(get(h.edSpacing,'String'));
    if isempty(s) || strcmpi(s,'auto')
        h.spacing = NaN; set(h.edSpacing,'String','auto');
    else
        v = str2double(s);
        if isfinite(v) && v > 0, h.spacing = v; set(h.edSpacing,'String',num2str(v));
        else, h.spacing = NaN; set(h.edSpacing,'String','auto'); end
    end
    guidata(fig, h);
    % Re-sampel bila sudah ada garis (spacing baru).
    if ~isempty(h.line), i_collectPOT(fig); end
end


function i_onFrameSlider(fig)
    h = guidata(fig);
    if isempty(h.data), return; end
    k = round(get(h.sldFrame,'Value'));
    k = i_scalar(k, 1);
    k = max(1, min(k, i_scalar(h.nF, 1)));
    h.frame = k; guidata(fig, h);
    if k > 1 && ~i_isFull(h), i_ensureFull(fig); end
    i_renderMain(fig);
    i_updateFrameLine(fig);
    h = guidata(fig);
    set(h.txtFrame,'String', sprintf('f %d/%d', i_scalar(h.frame,1), i_scalar(h.nF,1)));
end


function i_syncFrameSlider(fig)
    h = guidata(fig);
    nF = max(1, h.nF);
    if nF > 1, step = [1 10]/(nF-1); else, step = [1 1]; end
    set(h.sldFrame,'Min',1,'Max',nF,'Value',max(1,min(h.frame,nF)), ...
        'SliderStep',step);
    set(h.txtFrame,'String', sprintf('f %d/%d', max(1,min(h.frame,nF)), nF));
end


% =====================================================================
% Info & status
% =====================================================================
function i_updateInfo(fig)
    h = guidata(fig);
    if isempty(h.realData), return; end
    [~, base] = fileparts(h.realData);
    lines = { sprintf('Exp: %s', base), ...
              sprintf('Bingkai: %d', h.imgFrames), ...
              sprintf('Skalar: %s', h.scalarSrc) };
    if ~isempty(h.line)
        L = hypot(h.line.p2(1)-h.line.p1(1), h.line.p2(2)-h.line.p1(2));
        lines{end+1} = sprintf('Garis PSG: %.0f px', L);
        lines{end+1} = sprintf('Titik POT: %d', numel(h.recs));
        if ~isempty(h.indenter)
            mx = max(h.indenter(isfinite(h.indenter)));
            if ~isempty(mx), lines{end+1} = sprintf('Maks |V|: %.3g', mx); end
        end
    else
        lines{end+1} = 'Garis PSG: (belum)';
    end
    lines{end+1} = '';
    lines{end+1} = 'READ-ONLY — tak ada yg disimpan.';
    set(h.txtInfo,'String',lines);
end


% =====================================================================
% Geometri / strain (X0/X1/L_pos) — untuk penomoran montase POT
% =====================================================================
function g = i_loadGeom(matFile)
%I_LOADGEOM  Baca variabel experiment_geometry dari .mat (output Step 2) bila
%   ada. Mengembalikan struct geometri (lihat pivanalyze.geom.computeGeometry,
%   field strain_cumm_pct/X0_cm/X1_cm/Lpos_cm/valid) atau [] bila tak ada/tak
%   valid. Murah: matfile() lazy, hanya variabel kecil ini yang dibaca.
    g = [];
    if isempty(matFile) || ~isfile(matFile), return; end
    try
        mf = matfile(matFile);
        info = whos(mf);
        if ~ismember('experiment_geometry', {info.name}), return; end
        g = mf.experiment_geometry;
    catch
        g = [];
    end
end


function tf = i_geomHasStrain(g)
%I_GEOMHASSTRAIN  true bila geometri lengkap & strain kumulatif valid (X0/X1/
%   L_pos terisi -> strain_cumm_pct berhingga). Perhitungan strain per-bingkai
%   (interpolasi linier) dilakukan di pivcore.montage.buildMontagePOT.
    tf = isstruct(g) && isfield(g,'strain_cumm_pct') && ...
         isscalar(g.strain_cumm_pct) && isfinite(g.strain_cumm_pct) && ...
         (~isfield(g,'valid') || isempty(g.valid) || logical(g.valid));
end


% =====================================================================
% MONTASE — dialog konfigurasi + render off-screen ke PNG
% =====================================================================
function i_onMontage(fig)
%I_ONMONTAGE  Buka dialog konfigurasi montase untuk eksperimen AKTIF.
%   Memerlukan eksperimen termuat. Montase dirakit dari bingkai exp aktif
%   (1 .mat) -> butuh SEMUA bingkai (i_ensureFull). CLim SAMA semua panel
%   (climVel/shearAbs aktif). Output: PNG off-screen ke folder PIV.
    h = guidata(fig);
    if isempty(h.data) || isempty(h.realData)
        i_setStatus(fig, 'Pilih eksperimen dulu sebelum membuat montase.');
        return;
    end
    if ~i_ensureFull(fig), return; end
    h = guidata(fig);
    i_montageDialog(fig, h);
end


function i_montageDialog(fig, h)
%I_MONTAGEDIALOG  Jendela modal-ringan: pilih mode (grid/2-kolom), dimensi,
%   pemilihan bingkai (rata / selektif), label, lalu Render -> PNG.
    WHITE = [1 1 1];
    nF = max(1, i_scalar(h.imgFrames,1));
    [~, base] = fileparts(h.realData);

    dlg = figure('Name',sprintf('Montase — %s', base),'NumberTitle','off', ...
        'Color',WHITE,'Units','pixels','Position',[120 120 460 668], ...
        'MenuBar','none','ToolBar','none','WindowStyle','normal');
    try, pivui.forceLightTheme(dlg); catch, end

    y = 628;  % kursor vertikal (px dari bawah, turun bertahap)
    uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[16 y 430 22],'String', ...
        sprintf('Eksperimen: %s  (%d bingkai)', base, nF), ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE);

    % --- Mode montase ---
    y = y - 34;
    uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[16 y 80 22],'String','Mode:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE);
    d.popMode = uicontrol('Parent',dlg,'Style','popupmenu','Units','pixels', ...
        'Position',[100 y+2 346 24], ...
        'String',{'Grid kustom (kolom x baris)', ...
                  '2-kolom (kiri Vel | kanan Shear)', ...
                  'Grid + plot POT (garis vertikal per foto)'}, ...
        'BackgroundColor',WHITE, ...
        'Callback',@(s,e) i_mtgMode(dlg));

    % --- Skalar (grid saja) ---
    y = y - 34;
    d.txtScalar = uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[16 y 80 22],'String','Skalar:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE);
    d.popScalar = uicontrol('Parent',dlg,'Style','popupmenu','Units','pixels', ...
        'Position',[100 y+2 346 24], ...
        'String',{'Velocity magnitude','Shear strain'}, ...
        'BackgroundColor',WHITE);

    % --- Dimensi grid ---
    y = y - 36;
    uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[16 y 80 22],'String','Kolom:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE);
    d.edCols = uicontrol('Parent',dlg,'Style','edit','Units','pixels', ...
        'Position',[100 y+2 60 24],'String','4','BackgroundColor',WHITE);
    uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[180 y 80 22],'String','Baris:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE);
    d.edRows = uicontrol('Parent',dlg,'Style','edit','Units','pixels', ...
        'Position',[230 y+2 60 24],'String','2','BackgroundColor',WHITE);

    % --- Pemilihan bingkai ---
    y = y - 40;
    uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[16 y 430 22],'String','Pemilihan bingkai:', ...
        'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE);
    y = y - 26;
    d.rbEven = uicontrol('Parent',dlg,'Style','radiobutton','Units','pixels', ...
        'Position',[24 y 410 22],'String','a. Dibagi rata (even spacing, sesuai kolom x baris)', ...
        'Value',1,'BackgroundColor',WHITE);
    y = y - 24;
    d.rbSel = uicontrol('Parent',dlg,'Style','radiobutton','Units','pixels', ...
        'Position',[24 y 410 22],'String','b. Selektif (tentukan bingkai sendiri)', ...
        'Value',0,'BackgroundColor',WHITE);
    y = y - 28;
    uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[40 y 90 22],'String','Bingkai (selektif):', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    d.edFrames = uicontrol('Parent',dlg,'Style','edit','Units','pixels', ...
        'Position',[135 y+2 311 24],'String',num2str(pivcore.montage.evenFrames(nF,8)), ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Daftar indeks bingkai dipisah spasi/koma, mis. "1 6 11 16".', ...
        'Enable','off');
    % Radio mutual-exclusive + enable kotak selektif.
    set(d.rbEven,'Callback',@(s,e) i_mtgRadio(dlg, 'even'));
    set(d.rbSel, 'Callback',@(s,e) i_mtgRadio(dlg, 'sel'));

    % --- Label panel ---
    y = y - 38;
    uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[16 y 80 22],'String','Label:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE);
    d.popLabel = uicontrol('Parent',dlg,'Style','popupmenu','Units','pixels', ...
        'Position',[100 y+2 346 24], ...
        'String',{'Huruf + frame (a, b, c…)','Nomor frame saja (f12)','Tanpa label'}, ...
        'BackgroundColor',WHITE);

    % --- Penomoran garis POT (mode "Grid + plot POT" saja) ---
    % Tiga opsi: nomor frame, strain hasil interpolasi posisi (X0/X1/L_pos),
    % atau strain override manual (isi sendiri per foto di kotak di bawah).
    hasStrain = i_geomHasStrain(h.geom);
    y = y - 34;
    d.txtMark = uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[16 y 84 22],'String','Penomoran POT:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    if hasStrain
        sgeom = sprintf('Strain dari posisi (X0/X1/L_pos, strain penuh %+.2f%%)', ...
            h.geom.strain_cumm_pct);
    else
        sgeom = 'Strain dari posisi (TAK ADA X0/X1/L_pos di .mat)';
    end
    d.popMark = uicontrol('Parent',dlg,'Style','popupmenu','Units','pixels', ...
        'Position',[104 y+2 342 24], ...
        'String',{'Nomor frame (f12)', sgeom, 'Strain override (isi manual)'}, ...
        'BackgroundColor',WHITE, ...
        'TooltipString',['Angka di atas tiap garis vertikal merah di plot POT. ', ...
                         'Strain posisi = (k-1)/(N-1) x strain penuh.'], ...
        'Callback',@(s,e) i_mtgMark(dlg));
    % Simpan flag ketersediaan strain posisi untuk validasi saat render.
    d.hasStrain = hasStrain;
    y = y - 28;
    d.txtOverride = uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[16 y 88 22],'String','Override (%):', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    d.edOverride = uicontrol('Parent',dlg,'Style','edit','Units','pixels', ...
        'Position',[108 y+2 338 24],'String','', ...
        'BackgroundColor',WHITE,'FontSize',8,'Enable','off', ...
        'TooltipString',['Nilai strain (%) per foto, dipisah spasi/koma, sejajar ', ...
                         'urutan bingkai. Mis. "0 1.5 3.0 4.2". Kosong/kurang -> fallback f#.']);

    % --- GS overlay + alpha (warisi state aktif) ---
    y = y - 34;
    d.chkGS = uicontrol('Parent',dlg,'Style','checkbox','Units','pixels', ...
        'Position',[16 y 150 22],'String','Overlay grayscale', ...
        'Value',double(logical(h.gsOn)),'BackgroundColor',WHITE);
    uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[180 y 50 22],'String','alpha:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE);
    d.edAlpha = uicontrol('Parent',dlg,'Style','edit','Units','pixels', ...
        'Position',[234 y+2 56 24],'String',sprintf('%.2f',h.gsAlpha), ...
        'BackgroundColor',WHITE);

    % --- DPI ---
    y = y - 34;
    uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[16 y 80 22],'String','DPI:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE);
    d.edDpi = uicontrol('Parent',dlg,'Style','edit','Units','pixels', ...
        'Position',[100 y+2 60 24],'String','200','BackgroundColor',WHITE);

    % --- Info CLim (sama semua panel) ---
    y = y - 30;
    uicontrol('Parent',dlg,'Style','text','Units','pixels', ...
        'Position',[16 y 430 22],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',8,'ForegroundColor',[0.3 0.3 0.3], ...
        'String',sprintf('CLim (sama semua panel): vel [%g %g], shear ±%g', ...
            h.climVel(1), h.climVel(2), h.shearAbs));

    % --- Tombol Render / Batal ---
    y = y - 44;
    uicontrol('Parent',dlg,'Style','pushbutton','Units','pixels', ...
        'Position',[100 y 150 30],'String','Render & Simpan PNG', ...
        'FontWeight','bold', ...
        'Callback',@(s,e) i_mtgRender(fig, dlg, d, h));
    uicontrol('Parent',dlg,'Style','pushbutton','Units','pixels', ...
        'Position',[260 y 90 30],'String','Tutup', ...
        'Callback',@(s,e) close(dlg));

    setappdata(dlg,'d',d);
    i_mtgMode(dlg);     % set enable-state awal sesuai mode default (grid)
end


function i_mtgMode(dlg)
%I_MTGMODE  Aktif/non-aktifkan kontrol sesuai mode. Mode 2-kolom: skalar &
%   kolom tak relevan (kolom dipaksa 2, kiri vel|kanan shear), hanya "Baris"
%   + pemilihan bingkai yang berlaku. Mode "Grid + plot POT" (3): aktifkan
%   kontrol penomoran POT (frame/strain/override).
    d = getappdata(dlg,'d');
    modeIdx  = get(d.popMode,'Value');
    isTwoCol = (modeIdx == 2);
    isPOT    = (modeIdx == 3);
    if isTwoCol
        set(d.popScalar,'Enable','off');
        set(d.edCols,'Enable','off','String','2');
        set(d.txtScalar,'Enable','off');
    else
        set(d.popScalar,'Enable','on');
        set(d.edCols,'Enable','on');
        set(d.txtScalar,'Enable','on');
    end
    % Penomoran POT hanya relevan di mode "Grid + plot POT".
    onoff = i_enStr(isPOT);
    set(d.txtMark,'Enable',onoff);
    set(d.popMark,'Enable',onoff);
    set(d.txtOverride,'Enable',onoff);
    i_mtgMark(dlg);   % sinkronkan enable kotak override sesuai pilihan
end


function i_mtgMark(dlg)
%I_MTGMARK  Aktifkan kotak override HANYA saat mode POT + penomoran 'override'.
    d = getappdata(dlg,'d');
    isPOT = (get(d.popMode,'Value') == 3);
    isOvr = (get(d.popMark,'Value') == 3);
    set(d.edOverride,'Enable', i_enStr(isPOT && isOvr));
end


function s = i_enStr(tf)
    if tf, s = 'on'; else, s = 'off'; end
end


function i_mtgRadio(dlg, which)
%I_MTGRADIO  Eksklusivitas radio even/selektif + enable kotak bingkai.
    d = getappdata(dlg,'d');
    if strcmp(which,'even')
        set(d.rbEven,'Value',1); set(d.rbSel,'Value',0);
        set(d.edFrames,'Enable','off');
    else
        set(d.rbEven,'Value',0); set(d.rbSel,'Value',1);
        set(d.edFrames,'Enable','on');
    end
end


function i_mtgRender(fig, dlg, d, h)
%I_MTGRENDER  Baca dialog -> cfg -> pivcore.montage.buildMontage -> PNG.
    nF = max(1, i_scalar(h.imgFrames,1));
    modeIdx  = get(d.popMode,'Value');
    isTwoCol = (modeIdx == 2);
    isPOT    = (modeIdx == 3);
    cols = i_pInt(get(d.edCols,'String'), 4);
    rows = i_pInt(get(d.edRows,'String'), 2);
    nPanels = max(1, cols*rows);
    if isTwoCol
        % 2-kolom: jumlah panel = jumlah baris (kolom dipaksa 2, 1 frame/baris).
        nPanels = max(1, rows);
    end
    % Mode POT butuh kurva POT (garis PSG) sudah ada.
    if isPOT && (isempty(h.recs) || numel(h.recs) < 1)
        i_mtgStatus(dlg, 'Tarik garis PSG dulu (plot POT kosong).');
        i_setStatus(fig, 'Montase POT batal: belum ada garis PSG / kurva POT.');
        return;
    end

    % Pemilihan bingkai.
    if get(d.rbSel,'Value') == 1
        frames = i_parseFrames(get(d.edFrames,'String'), nF);
        if isempty(frames)
            i_mtgStatus(dlg,'Daftar bingkai selektif kosong/invalid.'); return;
        end
    else
        frames = pivcore.montage.evenFrames(nF, nPanels);
    end

    % Label.
    switch get(d.popLabel,'Value')
        case 2, lab = 'frame';
        case 3, lab = 'none';
        otherwise, lab = 'letter';
    end

    a = str2double(get(d.edAlpha,'String'));
    if ~(isfinite(a) && a >= 0 && a <= 1), a = h.gsAlpha; end
    dpi = i_pInt(get(d.edDpi,'String'), 200);

    cfg = struct();
    cfg.frames   = frames;
    cfg.rows     = rows;
    cfg.cols     = cols;
    cfg.climVel  = h.climVel;
    cfg.shearAbs = h.shearAbs;
    cfg.gsOn     = (get(d.chkGS,'Value') == 1);
    cfg.gsAlpha  = a;
    % Warisi pengaturan tampilan aktif (CLAHE, auto kontras, glyph) dari GUI.
    cfg.claheOn  = logical(h.claheOn);
    cfg.adjOn    = logical(h.adjOn);
    cfg.glyphOn  = logical(h.glyphOn);
    cfg.glyphLW  = h.glyphLW;
    cfg.glyphSp  = h.glyphSp;
    cfg.label    = lab;
    cfg.dpi      = dpi;

    [~, base] = fileparts(h.realData);
    outDir = fileparts(h.realData);
    usePOT = false;
    if isTwoCol
        cfg.mode = 'twocol';
        cfg.title = sprintf('%s — Vel|Shear (%d baris)', base, numel(frames));
        suffix = sprintf('montage_2col_%dx2', numel(frames));
    elseif isPOT
        usePOT = true;
        if get(d.popScalar,'Value') == 2, cfg.scalar = 'shear'; sc = 'shear';
        else, cfg.scalar = 'velocity_magnitude'; sc = 'vel'; end
        % Data POT dari sesi aktif (sumber tunggal axPOT).
        cfg.potRecs     = h.recs;
        cfg.potNF       = h.nF;
        cfg.potIndenter = h.indenter;
        cfg.geom        = h.geom;
        % Penomoran garis vertikal POT: 1=frame, 2=strain posisi, 3=override.
        switch get(d.popMark,'Value')
            case 2
                if i_geomHasStrain(h.geom), cfg.markMode = 'strain'; mk = 'strain';
                else, cfg.markMode = 'frame'; mk = 'frame';   % tak ada geometri -> fallback
                    i_setStatus(fig, 'Tak ada X0/X1/L_pos -> penomoran POT mundur ke nomor frame.');
                end
            case 3
                cfg.markMode = 'override'; mk = 'override';
                cfg.overrides = i_parseOverrides(get(d.edOverride,'String'), numel(frames));
            otherwise
                cfg.markMode = 'frame'; mk = 'frame';
        end
        cfg.title = sprintf('%s — %s grid %dx%d + POT (%s)', base, sc, rows, cols, mk);
        suffix = sprintf('montage_pot_%s_%dx%d_%s', sc, rows, cols, mk);
    else
        cfg.mode = 'grid';
        if get(d.popScalar,'Value') == 2, cfg.scalar = 'shear'; sc = 'shear';
        else, cfg.scalar = 'velocity_magnitude'; sc = 'vel'; end
        cfg.title = sprintf('%s — %s grid %dx%d', base, sc, rows, cols);
        suffix = sprintf('montage_%s_%dx%d', sc, rows, cols);
    end
    cfg.outFile = fullfile(outDir, sprintf('%s_%s.png', base, suffix));

    i_mtgStatus(dlg, 'Merender montase (off-screen)…');
    set(dlg,'Pointer','watch'); drawnow;
    cleaner = onCleanup(@() set(dlg,'Pointer','arrow'));
    try
        if usePOT
            outFile = pivcore.montage.buildMontagePOT(h.data, cfg);
        else
            outFile = pivcore.montage.buildMontage(h.data, cfg);
        end
    catch ME
        i_mtgStatus(dlg, sprintf('GAGAL: %s', ME.message));
        i_setStatus(fig, sprintf('Montase GAGAL: %s', ME.message));
        return;
    end
    [~, on, oe] = fileparts(outFile);
    i_mtgStatus(dlg, sprintf('Tersimpan: %s%s', on, oe));
    i_setStatus(fig, sprintf('Montase tersimpan: %s', outFile));
end


function i_mtgStatus(dlg, msg)
%I_MTGSTATUS  Tampilkan pesan singkat di judul dialog (tanpa label khusus).
    if ishghandle(dlg)
        set(dlg,'Name', sprintf('Montase — %s', msg));
        drawnow limitrate;
    end
end


function fr = i_parseFrames(str, nF)
%I_PARSEFRAMES  Urai "1 6, 11; 16" -> vektor indeks unik valid 1..nF.
    fr = [];
    if isempty(str), return; end
    s = regexprep(str, '[,;]', ' ');
    v = sscanf(s, '%g');
    if isempty(v), return; end
    v = round(v(:).');
    v = v(isfinite(v) & v >= 1 & v <= nF);
    fr = unique(v, 'stable');
end


function v = i_pInt(str, def)
%I_PINT  Parse integer positif dari string; def bila gagal/<=0.
    v = str2double(str);
    if ~(isfinite(v) && v >= 1), v = def; else, v = round(v); end
end


function ov = i_parseOverrides(str, nWant)
%I_PARSEOVERRIDES  Urai nilai strain override "0 1.5, 3.0; 4.2" -> vektor 1xnWant.
%   Boleh bertanda/desimal/negatif. Bila kurang dari nWant -> sisanya NaN
%   (builder POT mundur ke "f#" untuk slot NaN). Kelebihan dipotong.
    ov = nan(1, max(0, nWant));
    if isempty(str), return; end
    s = regexprep(str, '[,;]', ' ');
    v = sscanf(s, '%g');
    if isempty(v), return; end
    v = v(:).';
    m = min(numel(v), nWant);
    ov(1:m) = v(1:m);
end


function i_setStatus(fig, msg),  pivui.setStatus(fig, msg);  end  % forwarder -> +pivui


% =====================================================================
% Helper lokal
% =====================================================================
% --- helper generik bersama: forwarder ke +pivcore.util (satu sumber) ---
function b = i_baseName(p),        b = pivcore.util.baseName(p);          end
function v = i_scalar(x, varargin), v = pivcore.util.scalarOr(x, varargin{:}); end
function tf = i_isFull(h),         tf = pivcore.util.isFullLoaded(h);      end


% --- chrome axMain bersama: forwarder ke +pivui (satu sumber kebenaran) ---
function i_lockAxInteractions(ax),  pivui.lockAxInteractions(ax);  end
function i_clearFigModes(fig),      pivui.clearFigModes(fig);      end


% =====================================================================
% Minimize / restore (saat dialog berkas) -> forwarder +pivui
% =====================================================================
function i_minimize(fig),  pivui.minimizeForDialog(fig);  end

function i_restore(fig),   pivui.restoreAfterDialog(fig);
end
