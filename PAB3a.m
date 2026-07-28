function PAB3a(rootDir)
%PAB3A  Assign kurva POT -> HW-# atas berkas .mat output Step 2 (PABSA2).
%
%   PAB3a                 % pilih folder ROOT berisi .mat PIV (dialog)
%   PAB3a(rootDir)        % langsung ke folder ROOT
%
%   = PABSA3a, varian Step 3 seri PAB_SA. Menggabungkan:
%     - PIVTerry StandAlone `step2.m`  : ASSIGN kurva POT -> label (HW-#/F-#/
%       F0/FFW), tabel kurva, Trim ke max indenter, simpan progres -> SAVE.
%     - PAB_step_3 (PABSA3, PRATINJAU) : INPUT = berkas <expname>.mat PIVlab
%       standar (vektor + GS tersemat) di subfolder PIV_<tgl>/ atau folder
%       .mat bebas, POT disampel ON-THE-FLY dari garis PSG (tanpa Step 1).
%
%   Beda dgn step2 asli: step2 butuh "records" hasil PIVTerry Step 1 +
%   sidecar _autopot. PABSA3a TIDAK — ia menyampel POT sendiri dari .mat
%   (garis PSG OTOMATIS 70%, sama PABSA3), lalu kurva itu yg di-assign.
%   Progres assignment + garis PSG DISIMPAN ke <base>_autopot.mat (sebelah
%   berkas .mat) -> FORMAT KOMPATIBEL dgn step2 / suite PIVTerry (read-
%   modify-write; tak menyentuh vektor PIV).
%
%   DUA baris axes (paradigma step2 / PABSA3):
%     - axMain (ATAS) = validasi: bidang skalar (velocity_magnitude ATAU shear
%       strain bertanda du/dy+dv/dx) + overlay GS (grayscale +CLAHE +auto
%       kontras) + glyph vektor; slider frame men-scrub citra. Garis PSG =
%       ROI interaktif (oranye, draggable) — geser -> POT di-sampel ulang.
%       Penanda HW/F permanen di titik origin kurva ter-assign.
%     - axPOT (BAWAH) = spaghetti semua kurva POT + envelope MAX (indenter) +
%       indikator frame. Klik kurva -> terpilih + tersorot merah; Assign.
%
%   Engine ilmiah dipakai-ulang dari +pivcore / +pivui (di-addpath lewat
%   pab_setup). Jalankan `pab_setup` sekali per sesi lebih dulu.
%
%   Orientasi: identik PABSA3/step2 — grid PIVlab y menaik ke bawah; axMain
%   di-flip-V (imagesc YData [ymax ymin] + YDir normal) supaya TEGAK &
%   konsisten dgn flip step1Collect saat sampling -> garis & kurva sejajar.

    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivcore.data.buildDataset'))
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
    end

    if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
        rootDir = uigetdir(pwd, ...
            'Pilih folder berisi .mat PIV (output Step 2 / PIV_<tgl>/)');
        if isequal(rootDir, 0), return; end
    end

    h            = struct();
    h.root       = rootDir;
    h.list       = struct('name',{},'file',{},'sizeMB',{},'nFrames',{});
    h.activeRow  = 0;
    h.realData   = '';        % path .mat eksperimen aktif
    h.data       = [];        % dataset aktif (bingkai-1 ringan / penuh)
    h.fullLoaded = false;     % true bila h.data = SEMUA bingkai (scrub)
    h.imgFrames  = 1;         % jumlah bingkai citra termuat
    h.recs       = [];        % records POT (on-the-fly; punya color/assignLabel)
    h.assign     = pivcore.pot.assign.empty();   % agregat label (kompatibel saveAssignments)
    h.selRows    = [];        % indeks record terseleksi (sorot)
    h.viewMode   = 'raw';     % 'raw' | 'assigned'
    h.nF         = 1;         % panjang deret POT (= rentang slider frame)
    h.frame      = 1;         % bingkai aktif (indikator + scrub axMain)
    cD = pivcore.util.climDefaults();   % default warna/CLim bersama
    gD = pivcore.util.glyphDefaults();  % default glyph bersama
    pD = pivcore.util.potDefaults();    % default POT/PSG bersama
    h.scalarSrc  = 'velocity_magnitude';  % 'velocity_magnitude' | 'shear'
    h.climVel    = cD.velCLim;  % [min max] untuk velocity
    h.shearAbs   = cD.shearAbs;  % ±X untuk shear (CLim simetris [-X X])
    h.gsOn       = true;      % overlay grayscale aktif
    h.gsAlpha    = pD.gsAlpha;  % transparansi overlay grayscale
    h.claheOn    = true;      % CLAHE (kontras lokal) GS aktif (DEFAULT ON)
    h.adjOn      = true;      % auto kontras+brightness GS aktif (DEFAULT ON)
    h.glyphOn    = true;      % overlay glyph vektor (panah) aktif (DEFAULT ON)
    h.glyphLW    = gD.lineWidth;  % tebal garis glyph (default 1.2)
    h.glyphSp    = gD.spacing;    % spacing/decimation glyph (default tiap-3 node)
    h.markersOn  = true;      % penanda PERMANEN lokasi HW/F (kotak) di axMain
    h.xExt       = [];        % extent grid sumbu-x aktif
    h.yExt       = [];        % extent grid sumbu-y aktif
    h.line       = [];        % garis PSG aktif: struct('p1',[x y],'p2',[x y])
    h.roi        = [];        % images.roi.Line interaktif (draggable) di axMain
    h.psgFrac    = pD.psgFrac;  % fraksi tinggi garis PSG otomatis (0=atas,1=bawah)
    h.spacing    = NaN;       % spacing sampling titik POT (px); auto bila NaN
    h.indenter   = [];        % envelope MAX kurva (1xnF)
    h.trimMinPct = 70;        % gerbang tinggi "Trim ke indenter" (% puncak)
    h.yBase      = [];        % [ymin ymax] dasar axPOT
    h.vScale     = 1;         % skala vertikal axPOT

    h = i_buildUI(h);
    guidata(h.fig, h);
    i_initIndex(h.fig);
end


% =====================================================================
% UI (tema TERANG dipaksa)
% =====================================================================
function h = i_buildUI(h)
    WHITE = [1 1 1];
    h.fig = figure('Name',pivui.titleWithVersion('PABSA3a — Assign kurva POT -> HW-# (input .mat Step 2)'), ...
        'NumberTitle','off','Color',WHITE, ...
        'Units','pixels','Position',[60 50 1420 800], ...
        'MenuBar','none','ToolBar','figure');
    pivui.forceLightTheme(h.fig);
    fig = h.fig;

    % --- Panel kiri: folder + tabel eksperimen -----------------------
    pnlL = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.006 0.01 0.185 0.985],'Title','Berkas PIV (.mat)', ...
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
        'ColumnName',{'Eksperimen','MB','Asg'}, ...
        'ColumnWidth',{135 38 42}, ...
        'ColumnEditable',[false false false], ...
        'RowName',[],'FontSize',9, ...
        'CellSelectionCallback',@(s,e) i_onSelectRow(fig, e));

    % --- Strip kontrol tampilan (atas axMain, TIGA baris) ------------
    pnlC = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.197 0.895 0.560 0.098],'BackgroundColor',WHITE);
    % Baris 1 (atas): bidang skalar + penanda HW + rentang warna + GS alpha.
    h.btnDisp = uicontrol('Parent',pnlC,'Style','togglebutton', ...
        'Units','normalized','Position',[0.01 0.69 0.135 0.27], ...
        'String','Vel mag','Value',0,'FontWeight','bold', ...
        'TooltipString','Tukar bidang skalar axMain: Vel mag <-> Shear strain.', ...
        'Callback',@(s,e) i_onDisp(fig));
    h.btnMarkers = uicontrol('Parent',pnlC,'Style','togglebutton', ...
        'Units','normalized','Position',[0.15 0.69 0.135 0.27], ...
        'String','Penanda HW','Value',1,'FontWeight','bold', ...
        'TooltipString',['On/off kotak penanda lokasi tiap kurva ter-assign ', ...
                         '(HW-#/F/F0/FFW) di axMain, berwarna sesuai label.'], ...
        'Callback',@(s,e) i_onToggleMarkers(fig));
    h.txtLo = uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.29 0.69 0.05 0.26],'String','min:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE);
    h.edLo = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
        'Position',[0.345 0.70 0.075 0.26],'String','0', ...
        'TooltipString','Batas bawah warna (velocity).', ...
        'Callback',@(s,e) i_onClim(fig));
    h.txtHi = uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.425 0.69 0.05 0.26],'String','max:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE);
    h.edHi = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
        'Position',[0.48 0.70 0.075 0.26],'String','5', ...
        'TooltipString',['Velocity: batas atas warna. ', ...
                         'Shear: SATU angka ±X -> CLim [-X X] (simetris).'], ...
        'Callback',@(s,e) i_onClim(fig));
    uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.56 0.69 0.075 0.27],'String','Auto', ...
        'TooltipString',['Vel mag: batas atas = maks kurva indenter (bulat ke ', ...
                         'atas 0.5). Tanpa POT/shear: robustCLim bingkai aktif.'], ...
        'Callback',@(s,e) i_onAutoClim(fig));
    h.chkGS = uicontrol('Parent',pnlC,'Style','checkbox','Units','normalized', ...
        'Position',[0.645 0.70 0.135 0.26],'String','GS overlay','Value',1, ...
        'BackgroundColor',WHITE, ...
        'TooltipString','Overlay citra grayscale (dipaksa abu-abu) di atas bidang skalar.', ...
        'Callback',@(s,e) i_onGS(fig));
    uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.795 0.69 0.08 0.25],'String','alpha:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    h.edAlpha = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
        'Position',[0.875 0.70 0.075 0.26],'String',sprintf('%.2f',h.gsAlpha), ...
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
    % Baris 3 (bawah): slider frame + label + muat semua bingkai.
    uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.01 0.06 0.075 0.24],'String','Frame:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE);
    h.sldFrame = uicontrol('Parent',pnlC,'Style','slider','Units','normalized', ...
        'Position',[0.09 0.07 0.55 0.23],'Min',1,'Max',2,'Value',1, ...
        'SliderStep',[1 10]/1, ...
        'TooltipString','Geser untuk men-scrub bingkai citra axMain (validasi).', ...
        'Callback',@(s,e) i_onFrameSlider(fig));
    h.txtFrame = uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
        'Position',[0.645 0.06 0.085 0.24],'String','f 1/1', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
    uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
        'Position',[0.745 0.065 0.155 0.25],'String','Muat semua', ...
        'TooltipString','Muat seluruh bingkai -> slider men-scrub citra (sekali, agak lama).', ...
        'Callback',@(s,e) i_onLoadFull(fig));

    % --- axMain (atas) + axPOT (bawah) -------------------------------
    h.axMain = axes('Parent',fig,'Units','normalized', ...
        'Position',[0.225 0.505 0.515 0.385]);
    i_lockAxInteractions(h.axMain);
    title(h.axMain,'axMain — pilih eksperimen di kiri');
    h.axPOT = axes('Parent',fig,'Units','normalized', ...
        'Position',[0.225 0.065 0.515 0.325]);
    title(h.axPOT,'axPOT — POT (garis PSG OTOMATIS saat eksperimen dimuat)');
    xlabel(h.axPOT,'Frame'); ylabel(h.axPOT,'|V| (px/frame)');

    % --- Strip kontrol POT (antara axMain & axPOT) -------------------
    h.txtIndLeg = uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.197 0.430 0.115 0.034],'String','— max indenter (auto)', ...
        'HorizontalAlignment','left','FontWeight','bold','FontSize',8, ...
        'ForegroundColor',[0 0 0],'BackgroundColor',WHITE, ...
        'TooltipString','Envelope MAX semua kurva POT -> garis hitam tebal di axPOT.');
    uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.314 0.432 0.096 0.036],'String','Tarik garis PSG', ...
        'TooltipString',['Seret garis PSG baru di axMain (rubber-band), lalu kurva ', ...
                         '|V| di-sampel ulang & ditampilkan di axPOT.'], ...
        'Callback',@(s,e) i_onDrawLine(fig));
    uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.412 0.432 0.050 0.036],'String','Trim', ...
        'TooltipString',['Pilih kurva (klik plot / baris tabel) lalu klik: potong ', ...
                         '(non-destruktif) di titik kurva menyentuh max indenter.'], ...
        'Callback',@(s,e) i_onTrimToIndenter(fig));
    uicontrol('Parent',fig,'Style','pushbutton','Units','normalized', ...
        'Position',[0.464 0.432 0.050 0.036],'String','Pulih', ...
        'TooltipString',['Pulihkan kurva terpilih ke versi ASLI (batalkan trim). ', ...
                         'Tanpa seleksi = pulihkan SEMUA kurva.'], ...
        'Callback',@(s,e) i_onClearTrim(fig));
    uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.516 0.430 0.046 0.034],'String','Trim≥', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString',['Gerbang tinggi "Trim": kurva dipotong di titik sentuh ', ...
                         'indenter SETELAH naik >= X% puncak indenter.']);
    h.edTrimPct = uicontrol('Parent',fig,'Style','edit','Units','normalized', ...
        'Position',[0.564 0.432 0.032 0.034],'String',num2str(h.trimMinPct), ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Persen (0–100) puncak indenter sbg gerbang tinggi trim.', ...
        'Callback',@(s,e) i_onTrimThreshold(fig));
    uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.598 0.430 0.052 0.034],'String','Spacing:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Jarak antar titik sampel sepanjang garis (px). Kosong = auto.');
    h.edSpacing = uicontrol('Parent',fig,'Style','edit','Units','normalized', ...
        'Position',[0.652 0.432 0.034 0.034],'String','auto', ...
        'BackgroundColor',WHITE,'FontSize',8, ...
        'TooltipString','Spacing sampling (px). "auto" = nodeSpacing data.', ...
        'Callback',@(s,e) i_onSpacing(fig));
    uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.688 0.430 0.046 0.034],'String','Skala-V:', ...
        'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
    Lv = pivcore.pot.vscale.levels();
    h.sldVScale = uicontrol('Parent',fig,'Style','slider','Units','normalized', ...
        'Position',[0.736 0.434 0.034 0.032], ...
        'Min',Lv(1),'Max',Lv(end),'Value',pivcore.pot.vscale.defaultLevel(), ...
        'SliderStep',[0.25 0.5]/(Lv(end)-Lv(1)), ...
        'TooltipString','Skala vertikal axPOT (snap 0.25..2x). Sumbu-frame dijaga.', ...
        'Callback',@(s,e) i_onVScale(fig));

    % --- Panel kanan: assignment + tabel kurva -----------------------
    pnlR = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.792 0.01 0.203 0.985],'Title','Assign kurva -> HW-#', ...
        'FontWeight','bold','BackgroundColor',WHITE);
    % --- Baris Type + nomor (preview label) --------------------------
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 0.950 0.15 0.030],'String','Type:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE);
    h.popType = uicontrol('Parent',pnlR,'Style','popupmenu','Units','normalized', ...
        'Position',[0.20 0.947 0.77 0.038], ...
        'String',{'HW (Hanging Wall)','F (Fault)','F0 (sesar pertama)','FFW (Final Footwall)'}, ...
        'Value',1,'Callback',@(s,e) i_onLabelPreview(fig), ...
        'TooltipString',['HW = hanging wall (kurva naik). F = bidang sesar. ', ...
                         'F0 = sesar pertama (num=0). FFW = Final Footwall (num=0).']);
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.04 0.905 0.06 0.030],'String','#:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE);
    h.btnNumDn = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.11 0.902 0.11 0.038],'String',char(8722), ...
        'FontWeight','bold','Callback',@(s,e) i_onNumStep(fig,-1));
    h.edNum = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.23 0.902 0.17 0.038],'String','1', ...
        'HorizontalAlignment','center','Callback',@(s,e) i_onLabelPreview(fig));
    h.btnNumUp = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.41 0.902 0.11 0.038],'String','+', ...
        'FontWeight','bold','Callback',@(s,e) i_onNumStep(fig,+1));
    h.txtLblPrev = uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.55 0.905 0.43 0.030],'String','-> HW-1', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'FontWeight','bold');

    % --- Toolbar tombol: [v] assign  [x] unassign  RAW  SAVE ---------
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.030 0.848 0.180 0.050],'String',char(10003), ...
        'FontSize',13,'FontWeight','bold','ForegroundColor',[0.05 0.45 0.10], ...
        'BackgroundColor',[0.80 0.95 0.80], ...
        'TooltipString','Assign kurva terpilih -> label (Type+#).', ...
        'Callback',@(s,e) i_onAssign(fig));
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.220 0.848 0.180 0.050],'String',char(10007), ...
        'FontSize',13,'FontWeight','bold','ForegroundColor',[0.70 0.10 0.10], ...
        'BackgroundColor',[0.98 0.85 0.82], ...
        'TooltipString','Unassign kurva terpilih (hapus label).', ...
        'Callback',@(s,e) i_onUnassign(fig));
    h.btnView = uicontrol('Parent',pnlR,'Style','togglebutton','Units','normalized', ...
        'Position',[0.410 0.848 0.200 0.050],'String','RAW','Value',0, ...
        'FontWeight','bold','BackgroundColor',[0.92 0.92 0.86], ...
        'TooltipString','Tukar tabel+plot: SEMUA kurva (RAW) <-> hanya ter-assign (ASG).', ...
        'Callback',@(s,e) i_onViewToggle(fig));
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.620 0.848 0.350 0.050],'String','SAVE', ...
        'FontWeight','bold','BackgroundColor',[1.00 0.85 0.20], ...
        'TooltipString','Simpan assignment + garis PSG ke <base>_autopot.mat.', ...
        'Callback',@(s,e) i_onSave(fig));

    % --- Tabel kurva: RAMPING (# + Label saja) -----------------------
    h.tblCurve = uitable('Parent',pnlR,'Units','normalized', ...
        'Position',[0.03 0.082 0.94 0.748], ...
        'ColumnName',{'#','Label'}, ...
        'ColumnWidth',{46 180}, ...
        'RowName',[],'Tag','tblCurve', ...
        'CellSelectionCallback',@(s,e) i_onSelectCurveRow(fig, e));
    try, set(h.tblCurve,'Multiselect','on'); catch, end
    try, set(h.tblCurve,'SelectionType','row'); catch, end
    try
        set(h.tblCurve,'TooltipString', ['Daftar kurva: # = indeks record, ', ...
            'Label = assignment. * = di-trim ke max indenter.']);
    catch
    end

    % --- Exit & Save All: simpan assignment lalu TUTUP --------------
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.020 0.94 0.052],'String','Exit & Save All', ...
        'FontWeight','bold','FontSize',11, ...
        'ForegroundColor',[1 1 1],'BackgroundColor',[0.80 0.30 0.20], ...
        'TooltipString',['Simpan assignment + garis PSG ke <base>_autopot.mat ', ...
                         'lalu tutup (auto-simpan sudah jalan tiap aksi).'], ...
        'Callback',@(s,e) i_onExitSaveAll(fig));

    % --- Status (strip bawah) ----------------------------------------
    h.txtStatus = uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.197 0.008 0.560 0.03], ...
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
        i_setStatus(fig, sprintf('%d berkas PIV ditemukan. Pilih satu untuk meng-assign.', ...
            numel(list)));
    end
end


% --- pemindai .mat keluaran Step 2: forwarder ke pivanalyzemat.core (satu sumber) ---
function files = i_collectMats(root),  files = pivanalyzemat.core.scanPivMats(root);  end
function [meta, ok] = i_probeMat(f),   [meta, ok] = pivanalyzemat.core.probePivMat(f); end


function i_fillTable(fig)
%I_FILLTABLE  Isi tabel: Eksperimen + MB + jumlah label tersimpan (Asg).
%   Asg = berapa kurva ter-assign di <base>_autopot.mat (probe murah), supaya
%   pengguna lihat progres mana yg sudah/belum di-assign sebelum membuka.
    h = guidata(fig);
    n = numel(h.list);
    C = cell(n, 3);
    for i = 1:n
        e = h.list(i);
        C{i,1} = e.name;
        C{i,2} = sprintf('%.0f', e.sizeMB);
        C{i,3} = i_assignCountStr(e.file);
    end
    set(h.tbl, 'Data', C);
end


function s = i_assignCountStr(dataFile)
%I_ASSIGNCOUNTSTR  '' bila tak ada assignment; jumlah label bila ada. Probe
%   ringan (loadAssignments hanya baca _autopot, tak sentuh berkas data).
    s = '';
    try
        a = pivcore.io.step1Session.loadAssignments(dataFile);
        if ~isempty(a) && isstruct(a), s = num2str(numel(a)); end
    catch
    end
end


function i_onSelectRow(fig, evt)
    if isempty(evt) || isempty(evt.Indices), return; end
    row = evt.Indices(1,1);
    h = guidata(fig);
    if row < 1 || row > numel(h.list), return; end
    i_loadExperiment(fig, row);
end


% =====================================================================
% Muat eksperimen (bingkai-1 ringan; auto-PSG + POT + restore assignment)
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
    h.assign     = pivcore.pot.assign.empty();
    h.selRows    = [];
    h.viewMode   = 'raw';
    if isfield(h,'btnView') && ishghandle(h.btnView)
        set(h.btnView,'Value',0,'String','RAW');
    end
    h.frame      = 1;
    h.line       = [];
    if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
    h.roi        = [];
    h.indenter   = [];
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
    h.imgFrames = pivcore.data.frameCount(data1);
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

    % --- Garis PSG: pulihkan dari _autopot bila ADA, jika tidak AUTO 70% ---
    %   Restore garis tersimpan -> sampling identik -> assignment (curveIdx)
    %   ter-petakan benar. Tanpa garis tersimpan -> auto 70% (pratinjau cepat).
    L = [];
    try, L = pivcore.io.step1Session.loadLine(df); catch, end
    if ~isempty(L) && isfield(L,'p1') && isfield(L,'p2') ...
            && numel(L.p1) == 2 && numel(L.p2) == 2 ...
            && all(isfinite(L.p1)) && all(isfinite(L.p2))
        h.line = struct('p1', L.p1(:).', 'p2', L.p2(:).');
        guidata(fig, h);
        i_ensureROI(fig);
        i_collectPOT(fig);
        i_setStatus(fig, sprintf('%s: garis PSG tersimpan dipulihkan -> POT siap.', base));
    else
        i_autoPSG(fig);
    end

    % --- Pulihkan assignment tersimpan -> records.assignLabel --------
    h = guidata(fig);
    if ~isempty(h.recs)
        h.recs = i_restoreAssign(df, h.recs);
        h.assign = pivcore.pot.assign.fromRecords(i_recsForFeatures(h));
        h.recs = pivcore.pot.records.applyColors(h.recs);
        guidata(fig, h);
        i_renderPOT(fig);
        i_refreshCurveTable(fig);
        i_renderAssignMarkers(fig);
    end

    h = guidata(fig);
    i_setStatus(fig, sprintf(['%s: %d bingkai, %d kurva POT. Klik kurva di plot / ', ...
        'baris tabel, lalu Assign ke HW-#.'], base, h.imgFrames, numel(h.recs)));
end


function i_autoPSG(fig)
%I_AUTOPSG  Buat garis PSG horizontal end-to-end (default 70% tinggi) sebagai
%   ROI INTERAKTIF, muat semua bingkai, sampel POT otomatis.
    h = guidata(fig);
    if isempty(h.data), return; end
    xE = h.xExt; yE = h.yExt;
    if isempty(xE) || isempty(yE), return; end
    frac = h.psgFrac; if ~(isfinite(frac) && frac >= 0 && frac <= 1), frac = 0.70; end
    yL = yE(1) + frac * (yE(2) - yE(1));
    h.line = struct('p1',[xE(1) yL], 'p2',[xE(2) yL]);
    guidata(fig, h);
    i_ensureROI(fig);
    i_collectPOT(fig);
end


function i_ensureROI(fig)
%I_ENSUREROI  Buat/segarkan garis PSG INTERAKTIF (images.roi.Line) di axMain
%   dari h.line — DRAGGABLE, oranye, marker lingkaran. Geser -> re-sampel POT.
    h = guidata(fig);
    if isempty(h.line) || ~ishghandle(h.axMain), return; end
    if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
    % ROI garis PSG (gaya dari pivui.potStyle) + listener re-sampel POT saat digeser.
    roi = pivui.makePsgLineROI(h.axMain, h.line.p1, h.line.p2, @() i_onROIMoved(fig));
    h.roi = roi; guidata(fig, h);
end


function i_onROIMoved(fig)
%I_ONROIMOVED  ROI garis PSG selesai digeser -> re-sampel POT. Assignment
%   yang ada DIBUANG (kurva berubah -> indeks tak lagi cocok); pengguna
%   meng-assign ulang. axMain tak di-render ulang (ROI sudah bergerak).
    h = guidata(fig);
    L = i_currentLine(h);
    if isempty(L), return; end
    h.line = L; guidata(fig, h);
    i_collectPOT(fig);
end


function L = i_currentLine(h)
%I_CURRENTLINE  Posisi garis PSG TERKINI — forwarder ke pivui.currentLineFromROI.
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
% Render axMain (overlay skalar + GS + glyph + ROI + penanda HW)
% =====================================================================
function i_renderMain(fig)
    h = guidata(fig);
    ax = h.axMain;
    if isempty(h.data), return; end
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
    % box/Layer). TAK menggambar colorbar/label/teks-kosong/judul/penanda — itu
    % chrome khas GUI yang TETAP di sini (lihat di bawah). h memuat semua field
    % cfg (gsOn/gsAlpha/claheOn/adjOn/glyphOn/glyphLW/glyphSp/shearAbs/climVel).
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
    xlim(ax, xExt); ylim(ax, yExt);
    daspect(ax, [1 1 1]); set(ax, 'Layer','top'); box(ax,'on');
    i_lockAxInteractions(ax);
    title(ax, sprintf('axMain — %s — bingkai %d/%d', i_baseName(h.realData), ...
        k, h.imgFrames), 'Interpreter','none');

    h.xExt = xExt; h.yExt = yExt;
    guidata(fig, h);
    if ~isempty(h.line), i_ensureROI(fig); end
    i_renderAssignMarkers(fig);     % penanda HW/F permanen (di bawah seleksi)
    i_highlightSelMain(fig);
end


% =====================================================================
% Penanda HW/F permanen + seleksi di axMain
% =====================================================================
function i_renderAssignMarkers(fig)
%I_RENDERASSIGNMARKERS  Penanda PERMANEN lokasi origin tiap kurva ter-assign
%   di axMain: kotak berwarna (sesuai label) + teks label. On/off h.markersOn.
    h = guidata(fig);
    ax = h.axMain;
    if ~ishghandle(ax), return; end
    try, delete(findall(ax,'Tag','asgMarker')); catch, end
    if ~h.markersOn || isempty(h.recs) || isempty(h.xExt) || isempty(h.yExt)
        return;
    end
    base = min(abs(diff(h.xExt)), abs(diff(h.yExt)));
    if ~(isfinite(base) && base > 0), return; end
    sz = base * 0.024;
    hs = ishold(ax); hold(ax,'on');
    for r = 1:numel(h.recs)
        rec = h.recs(r);
        lbl = pivcore.pot.records.label(rec);
        if isempty(lbl), continue; end
        o = rec.origin;
        if numel(o) ~= 2 || ~all(isfinite(o)), continue; end
        col = rec.color;
        if numel(col) ~= 3 || ~all(isfinite(col))
            [ty, num] = pivcore.pot.labels.parseLabel(lbl);
            col = pivcore.pot.labels.labelColor(ty, num);
        end
        rectangle(ax, 'Position',[o(1)-sz/2, o(2)-sz/2, sz, sz], ...
            'EdgeColor',col,'LineWidth',1.8,'FaceColor','none', ...
            'Tag','asgMarker','HitTest','off','PickableParts','none');
        text(ax, o(1), o(2)+sz*0.70, lbl, 'Color',col, ...
            'FontSize',8,'FontWeight','bold','Clipping','on', ...
            'HorizontalAlignment','center','VerticalAlignment','bottom', ...
            'Tag','asgMarker','HitTest','off','PickableParts','none');
    end
    if ~hs, hold(ax,'off'); end
end


function i_highlightSelMain(fig)
%I_HIGHLIGHTSELMAIN  Tandai origin record terseleksi di axMain (persegi merah).
    h = guidata(fig);
    ax = h.axMain;
    if ~ishghandle(ax), return; end
    try, delete(findall(ax,'Tag','selMain')); catch, end
    rows = h.selRows(:).';
    rows = rows(rows >= 1 & rows <= numel(h.recs));
    if isempty(rows) || isempty(h.xExt) || isempty(h.yExt), return; end
    base = min(abs(diff(h.xExt)), abs(diff(h.yExt)));
    if ~(isfinite(base) && base > 0), return; end
    sz = base * 0.02;
    for r = rows
        o = h.recs(r).origin;
        if numel(o) ~= 2 || ~all(isfinite(o)), continue; end
        rectangle(ax, 'Position',[o(1)-sz/2, o(2)-sz/2, sz, sz], ...
            'EdgeColor',[1 0 0],'LineWidth',1.3,'FaceColor','none', ...
            'Tag','selMain','HitTest','off','PickableParts','none');
    end
end


function i_onToggleMarkers(fig)
    h = guidata(fig);
    h.markersOn = get(h.btnMarkers,'Value') == 1;
    guidata(fig, h);
    i_renderAssignMarkers(fig);
    if h.markersOn
        i_setStatus(fig,'Penanda lokasi HW/F di axMain: ON.');
    else
        i_setStatus(fig,'Penanda lokasi HW/F di axMain: OFF.');
    end
end


% =====================================================================
% Garis PSG di axMain -> POT on-the-fly
% =====================================================================
function i_onDrawLine(fig)
%I_ONDRAWLINE  Tarik garis PSG baru (DRAWLINE rubber-band) -> ROI draggable
%   yang langsung re-sampel POT.
    h = guidata(fig);
    if isempty(h.data)
        i_setStatus(fig, 'Pilih eksperimen dulu sebelum menarik garis.');
        return;
    end
    if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
    i_clearFigModes(fig);
    i_setStatus(fig, 'Seret garis PSG di axMain (klik-tahan dari ujung ke ujung)…');
    ps = pivui.potStyle().psgLine;   % warna/LW/MS PSG dari sumber gaya bersama
    roi = drawline(h.axMain, 'Color',ps.color, 'LineWidth',ps.lineWidth, ...
        'MarkerSize',ps.markerSize, 'Label','PSG', 'LabelVisible','hover');
    if isempty(roi) || ~isvalid(roi) || isempty(roi.Position)
        guidata(fig, h); i_ensureROI(fig);
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


function i_collectPOT(fig)
%I_COLLECTPOT  Sampel kurva POT sepanjang garis PSG aktif (semua bingkai) via
%   pivcore.pot.step1Collect — IDENTIK PIVTerry Step 1 (zero duplikasi).
    h = guidata(fig);
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
    h.recs    = recs;
    h.selRows = [];
    h.assign  = pivcore.pot.assign.empty();   % kurva baru -> assignment lama batal
    nF = 0;
    for r = 1:numel(recs), nF = max(nF, numel(recs(r).data)); end
    h.nF = max(1, nF);
    guidata(fig, h);
    i_syncFrameSlider(fig);
    i_renderPOT(fig);                 % set h.indenter (envelope MAX)
    i_climFromIndenter(fig);          % CLim Vel mag atas = ceil(maks indenter,0.5)
    i_refreshCurveTable(fig);
    i_renderAssignMarkers(fig);
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

    order = i_viewOrder(h);
    if isempty(order)
        if isempty(h.recs)
            msg = 'Tarik garis PSG di axMain untuk POT analysis';
        else
            msg = 'Tak ada kurva ter-assign (view ASG)';
        end
        text(ax,0.5,0.5,msg, 'Units','normalized','HorizontalAlignment','center', ...
            'Color',[0.5 0.5 0.5]);
        hold(ax,'off'); xlabel(ax,'Frame'); ylabel(ax,'|V| (px/frame)');
        grid(ax,'on'); title(ax,'axPOT — POT analysis');
        h.indenter = []; h.yBase = []; guidata(fig, h);
        return;
    end
    nF = h.nF;
    env = i_indenterEnvelope(h);

    ymin = inf; ymax = -inf;
    for r = order(:).'
        [xv, yv] = pivcore.pot.records.curveXY(h.recs(r), nF);
        yv = i_applyTrim(h, h.recs(r), yv, env);
        g = isfinite(xv) & isfinite(yv); if ~any(g), continue; end
        col = h.recs(r).color; if numel(col) ~= 3, col = [0.4 0.4 0.4]; end
        plot(ax, xv(g), yv(g), '-', 'Color', col, 'LineWidth', i_lineWidthFor(h.recs(r)), ...
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
%I_INDENTERENVELOPE  Envelope MAX semua kurva (di-MA via curveXY) per frame.
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
%I_CLIMFROMINDENTER  Set batas ATAS CLim Vel mag = ceil(maks indenter, 0.5).
    h = guidata(fig);
    if isempty(h.indenter), return; end
    mx = max(h.indenter(isfinite(h.indenter)));
    if isempty(mx) || ~isfinite(mx) || mx <= 0, return; end
    hi = pivcore.util.snapClim(mx);     % bulat ke atas kelipatan 0.5 (kernel bersama)
    if hi <= 0, return; end
    h.climVel = [0 hi];
    guidata(fig, h);
    i_syncClimControls(h);
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
%I_HIGHLIGHTSELPOT  Sorot kurva terseleksi -> MERAH TEBAL.
    h = guidata(fig);
    ax = h.axPOT;
    if ~ishghandle(ax), return; end
    try, delete(findall(ax,'Tag','selCurve')); catch, end
    rows = h.selRows(:).';
    rows = rows(rows >= 1 & rows <= numel(h.recs));
    if isempty(rows), return; end
    nF = h.nF; env = h.indenter;
    hs = ishold(ax); hold(ax,'on');
    for r = rows
        [xv, yv] = pivcore.pot.records.curveXY(h.recs(r), nF);
        yv = i_applyTrim(h, h.recs(r), yv, env);
        g = isfinite(xv) & isfinite(yv); if ~any(g), continue; end
        plot(ax, xv(g), yv(g), '-', 'Color',[1 0 0], 'LineWidth',3.0, ...
            'Tag','selCurve','HitTest','off','PickableParts','none');
    end
    if ~hs, hold(ax,'off'); end
end


function i_applyVScale(fig)
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
% Klik kurva / pilih baris tabel
% =====================================================================
function i_onCurveClick(fig, src)
    if ~ishghandle(src), return; end
    r = get(src,'UserData');
    if ~isscalar(r) || ~isfinite(r), return; end
    h = guidata(fig);
    if r < 1 || r > numel(h.recs), return; end
    h.selRows = r; guidata(fig, h);
    i_highlightSelPOT(fig);
    i_highlightSelMain(fig);
    vr = i_recordRowToView(h, r);
    pivui.selectTableRow(h.tblCurve, vr);
    pt = h.recs(r).point; if isempty(pt), pt = sprintf('P-%d', r); end
    if vr >= 1
        i_setStatus(fig, sprintf( ...
            'Kurva "%s" (record %d) -> baris tabel %d. Set Type+# lalu Assign.', pt, r, vr));
    else
        i_setStatus(fig, sprintf( ...
            'Kurva "%s" (record %d) terpilih (tak tampil di view Assigned).', pt, r));
    end
end


function i_onSelectCurveRow(fig, evt)
    if isempty(evt) || ~(isprop(evt,'Indices') || isfield(evt,'Indices')) ...
            || isempty(evt.Indices)
        return;
    end
    viewRows = unique(evt.Indices(:,1)).';
    h = guidata(fig);
    order = i_viewOrder(h);
    recRows = [];
    for vr = viewRows
        if vr >= 1 && vr <= numel(order), recRows(end+1) = order(vr); end %#ok<AGROW>
    end
    h.selRows = recRows; guidata(fig, h);
    i_highlightSelPOT(fig);
    i_highlightSelMain(fig);
    i_setStatus(fig, sprintf('%d kurva terpilih. Set Type+# lalu Assign.', numel(recRows)));
end


function vr = i_recordRowToView(h, r)
    vr = 0;
    order = i_viewOrder(h);
    k = find(order == r, 1);
    if ~isempty(k), vr = k; end
end


function order = i_viewOrder(h)
%I_VIEWORDER  Indeks record yg tampil: raw = semua; assigned = ter-label saja.
    order = [];
    if isempty(h.recs), return; end
    if strcmp(h.viewMode, 'assigned')
        for r = 1:numel(h.recs)
            if ~isempty(pivcore.pot.records.label(h.recs(r))), order(end+1) = r; end %#ok<AGROW>
        end
    else
        order = 1:numel(h.recs);
    end
end


function i_onViewToggle(fig)
    h = guidata(fig);
    if get(h.btnView,'Value') == 1
        h.viewMode = 'assigned'; set(h.btnView,'String','ASG');
    else
        h.viewMode = 'raw'; set(h.btnView,'String','RAW');
    end
    guidata(fig, h);
    i_renderPOT(fig);
    i_refreshCurveTable(fig);
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
% Assignment
% =====================================================================
function i_onLabelPreview(fig)
    h = guidata(fig);
    [ty, num] = i_typeNum(h);
    if strcmp(ty,'F0') || strcmp(ty,'FFW')
        set(h.edNum,'String','0','Enable','off');
        set(h.btnNumUp,'Enable','off'); set(h.btnNumDn,'Enable','off');
    else
        set(h.edNum,'Enable','on');
        set(h.btnNumUp,'Enable','on'); set(h.btnNumDn,'Enable','on');
    end
    set(h.txtLblPrev,'String', sprintf('-> %s', pivcore.pot.labels.makeLabel(ty, num)));
end


function i_onNumStep(fig, dir)
    h = guidata(fig);
    [ty, num] = i_typeNum(h);
    if strcmp(ty,'F0') || strcmp(ty,'FFW'), return; end
    num = max(1, num + dir);
    set(h.edNum,'String', num2str(num));
    i_onLabelPreview(fig);
end


function i_onAssign(fig)
    h = guidata(fig);
    rows = h.selRows(:).';
    rows = rows(rows >= 1 & rows <= numel(h.recs));
    if isempty(rows)
        i_setStatus(fig,'Belum ada kurva terpilih. Klik kurva di plot / baris tabel.');
        return;
    end
    [ty, num] = i_typeNum(h);
    lbl = pivcore.pot.labels.makeLabel(ty, num);
    if isempty(lbl), i_setStatus(fig,'Label tidak valid.'); return; end
    for r = rows, h.recs(r).assignLabel = lbl; end
    h.assign = pivcore.pot.assign.fromRecords(i_recsForFeatures(h));
    h.recs = pivcore.pot.records.applyColors(h.recs);
    guidata(fig, h);
    i_renderPOT(fig);
    i_refreshCurveTable(fig);
    i_renderAssignMarkers(fig);
    i_onNumStep(fig, +1);
    if i_autoSaveAssign(fig)
        [tyNext, numNext] = i_typeNum(guidata(fig));
        nextLbl = pivcore.pot.labels.makeLabel(tyNext, numNext);
        if isempty(nextLbl)
            i_setStatus(fig, sprintf('%d kurva -> %s (tersimpan).', numel(rows), lbl));
        else
            i_setStatus(fig, sprintf('%d kurva -> %s (tersimpan). Berikutnya: %s.', ...
                numel(rows), lbl, nextLbl));
        end
    end
    i_updateAssignCount(fig);
end


function i_onUnassign(fig)
    h = guidata(fig);
    rows = h.selRows(:).';
    rows = rows(rows >= 1 & rows <= numel(h.recs));
    if isempty(rows), i_setStatus(fig,'Belum ada kurva terpilih.'); return; end
    for r = rows, h.recs(r).assignLabel = ''; end
    h.assign = pivcore.pot.assign.fromRecords(i_recsForFeatures(h));
    h.recs = pivcore.pot.records.applyColors(h.recs);
    guidata(fig, h);
    i_renderPOT(fig);
    i_refreshCurveTable(fig);
    i_renderAssignMarkers(fig);
    if i_autoSaveAssign(fig)
        i_setStatus(fig, sprintf('%d kurva di-unassign (tersimpan).', numel(rows)));
    end
    i_updateAssignCount(fig);
end


function recs = i_restoreAssign(df, recs)
%I_RESTOREASSIGN  Pulihkan assignLabel dari ap.step3Assign bila records belum
%   punya label (mapping curveIdx -> label via assign.applySaved).
    has = false;
    for r = 1:numel(recs)
        if ~isempty(pivcore.pot.records.label(recs(r))), has = true; break; end
    end
    if has, return; end
    saved = [];
    try
        saved = pivcore.io.step1Session.loadAssignments(df);
    catch
    end
    recs = pivcore.pot.assign.applySaved(recs, saved);
end


% =====================================================================
% Tabel kurva
% =====================================================================
function i_refreshCurveTable(fig)
    h = guidata(fig);
    order = i_viewOrder(h);
    n = numel(order);
    data = cell(n, 2);
    bgRows = ones(n,3); fgRows = zeros(n,3);
    for i = 1:n
        r = order(i);
        rec = h.recs(r);
        lbl = pivcore.pot.records.label(rec);
        lblShow = lbl; if i_isTrimmed(rec), lblShow = [lbl '*']; end %#ok<AGROW>
        data{i,1} = num2str(r);
        data{i,2} = lblShow;
        [ty, num] = pivcore.pot.labels.parseLabel(lbl);
        if isempty(ty), bgRows(i,:) = [1 1 1]; else, bgRows(i,:) = pivcore.pot.labels.labelColor(ty,num); end
        if mean(bgRows(i,:)) < 0.5, fgRows(i,:) = [1 1 1]; else, fgRows(i,:) = [0 0 0]; end
    end
    set(h.tblCurve,'Data',data);
    pivui.applyRowStyles(h.tblCurve, bgRows, fgRows);
    try
        vsel = [];
        for rr = h.selRows(:).'
            vr = i_recordRowToView(h, rr);
            if vr >= 1, vsel(end+1) = vr; end %#ok<AGROW>
        end
        if ~isempty(vsel)
            set(h.tblCurve,'Selection',vsel);
            try, scroll(h.tblCurve, 'row', vsel(1)); catch, end
        end
    catch
    end
end


function i_updateAssignCount(fig)
%I_UPDATEASSIGNCOUNT  Perbarui kolom "Asg" tabel kiri utk eksperimen aktif.
    h = guidata(fig);
    if h.activeRow < 1 || h.activeRow > numel(h.list), return; end
    C = get(h.tbl,'Data');
    if isempty(C) || size(C,1) < h.activeRow, return; end
    nlab = 0;
    if ~isempty(h.assign) && isstruct(h.assign), nlab = numel(h.assign); end
    if nlab > 0, C{h.activeRow,3} = num2str(nlab); else, C{h.activeRow,3} = ''; end
    set(h.tbl,'Data',C);
end


% =====================================================================
% Simpan progres
% =====================================================================
function i_onSave(fig)
    h = guidata(fig);
    if isempty(h.realData), i_setStatus(fig,'Pilih eksperimen dulu.'); return; end
    if isempty(h.recs)
        i_setStatus(fig,'Belum ada kurva POT. Tarik garis PSG dulu.');
        return;
    end
    try
        i_saveAll(h);
    catch ME
        i_setStatus(fig, sprintf('GAGAL menyimpan: %s', ME.message));
        return;
    end
    f = pivcore.io.step1Session.autopotPath(h.realData);
    i_setStatus(fig, sprintf('%d label + garis PSG tersimpan: %s', numel(h.assign), f));
end


function i_onExitSaveAll(fig)
%I_ONEXITSAVEALL  Flush terakhir lalu TUTUP. Bila simpan GAGAL, jangan tutup.
    h = guidata(fig);
    if ~isempty(h.realData) && ~isempty(h.recs)
        try
            i_saveAll(h);
        catch ME
            i_setStatus(fig, sprintf('GAGAL simpan saat keluar: %s (tidak ditutup).', ...
                ME.message));
            try
                uiwait(warndlg(sprintf(['Gagal menyimpan:\n%s\n\nPABSA3a TIDAK ', ...
                    'ditutup supaya progres tak hilang.'], ME.message), ...
                    'Exit & Save All', 'modal'));
            catch
            end
            return;
        end
    end
    delete(fig);
end


function i_saveAll(h)
%I_SAVEALL  Simpan garis PSG + assignment + records + envelope indenter ke
%   <base>_autopot.mat (read-modify-write; tak menyentuh vektor PIV). Garis
%   disimpan SEBELUM assignment supaya reload menyampel ulang IDENTIK ->
%   curveIdx assignment ter-petakan benar.
    if ~isempty(h.line) && isfield(h.line,'p1') && isfield(h.line,'p2')
        pivcore.io.step1Session.saveLine(h.realData, h.line.p1, h.line.p2, struct(), true);
    end
    if isempty(h.indenter)
        pivcore.io.step1Session.saveAssignments(h.realData, h.assign, h.recs);
    else
        pivcore.io.step1Session.saveAssignments(h.realData, h.assign, h.recs, h.indenter);
    end
end


function ok = i_autoSaveAssign(fig)
%I_AUTOSAVEASSIGN  Auto-save SEGERA tiap mutasi assignment / trim. SENYAP saat
%   sukses; set status GAGAL + return false bila error / tak ada exp aktif.
    ok = false;
    h = guidata(fig);
    if isempty(h.realData) || isempty(h.recs), return; end
    try
        i_saveAll(h);
        ok = true;
    catch ME
        i_setStatus(fig, sprintf('Auto-simpan GAGAL: %s', ME.message));
    end
end


% =====================================================================
% Trim ke max indenter (non-destruktif)
% =====================================================================
function tf = i_isTrimmed(rec)
    tf = isstruct(rec) && isfield(rec,'cutManual') && isscalar(rec.cutManual) ...
         && logical(rec.cutManual);
end


function w = i_lineWidthFor(rec)
%I_LINEWIDTHFOR  Tebal garis: HW-# paling TEBAL, F/F0/FFW sedang, belum tipis.
    [ty, ~] = pivcore.pot.labels.parseLabel(pivcore.pot.records.label(rec));
    if strcmp(ty,'HW'), w = 2.6;
    elseif ~isempty(ty), w = 1.6;
    else, w = 0.8;
    end
end


function df = i_dieFrame(h, rec, env)
%I_DIEFRAME  Frame "kematian" trim: cutFrame beku bila ada, jika tidak derive
%   dari envelope. NaN bila tak ditandai / tak menyentuh indenter.
    df = NaN;
    if ~i_isTrimmed(rec), return; end
    if isfield(rec,'cutFrame') && isscalar(rec.cutFrame) && isfinite(rec.cutFrame)
        df = rec.cutFrame; return;
    end
    if nargin < 3 || isempty(env), env = i_indenterEnvelope(h); end
    if isempty(env), return; end
    [~, yv] = pivcore.pot.records.curveXY(rec, h.nF);
    [~, df] = pivcore.pot.hw0Clean.cutAtIndenter(yv, env, i_trimOpts(h));
end


function yv = i_applyTrim(h, rec, yv, env)
%I_APPLYTRIM  Terapkan trim ke max indenter pada deret tampil (NaN setelah
%   frame potong). No-op bila record tak ditandai trim.
    if nargin < 4, env = []; end
    df = i_dieFrame(h, rec, env);
    if isfinite(df) && df >= 1 && df < numel(yv)
        yv(df+1:end) = NaN;
    end
end


function recs = i_recsForFeatures(h)
%I_RECSFORFEATURES  Salinan records dgn `.data` DI-TRIM di max indenter untuk
%   record bertanda cutManual (non-destruktif thd h.recs).
    recs = h.recs;
    if isempty(recs), return; end
    env = i_indenterEnvelope(h);
    for r = 1:numel(recs)
        if ~i_isTrimmed(recs(r)), continue; end
        dieF = i_dieFrame(h, recs(r), env);
        if isfinite(dieF)
            v = recs(r).data(:).';
            if dieF >= 1 && dieF < numel(v), v(dieF+1:end) = NaN; end
            recs(r).data = v;
        end
    end
end


function i_onTrimToIndenter(fig)
%I_ONTRIMTOINDENTER  Tandai kurva terpilih utk DI-TRIM ke max indenter.
    h = guidata(fig);
    rows = h.selRows(:).';
    rows = rows(rows >= 1 & rows <= numel(h.recs));
    if isempty(rows)
        i_setStatus(fig,'Pilih kurva dulu (klik di plot / baris tabel), lalu Trim.');
        return;
    end
    env = h.indenter;
    if isempty(env), env = i_indenterEnvelope(h); end
    if isempty(env)
        i_setStatus(fig,'Max indenter belum terhitung (belum ada kurva).');
        return;
    end
    nHit = 0;
    for r = rows
        [~, yv] = pivcore.pot.records.curveXY(h.recs(r), h.nF);
        [~, dieF] = pivcore.pot.hw0Clean.cutAtIndenter(yv, env, i_trimOpts(h));
        h.recs(r).cutManual = true;
        h.recs(r).cutFrame  = dieF;
        v = h.recs(r).data(:).';
        if isfinite(dieF) && dieF >= 1 && dieF < numel(v), v(dieF+1:end) = NaN; end
        h.recs(r).dataCut = v;
        if isfinite(dieF), nHit = nHit + 1; end
    end
    h.assign = pivcore.pot.assign.fromRecords(i_recsForFeatures(h));
    guidata(fig, h);
    i_renderPOT(fig);
    i_refreshCurveTable(fig);
    if i_autoSaveAssign(fig)
        i_setStatus(fig, sprintf(['Trim ke max indenter: %d kurva ditandai ', ...
            '(%d menyentuh indenter, tersimpan).'], numel(rows), nHit));
    end
end


function opt = i_trimOpts(h)
    pct = 70;
    if isfield(h,'trimMinPct') && isscalar(h.trimMinPct) && isfinite(h.trimMinPct)
        pct = min(max(h.trimMinPct, 0), 100);
    end
    opt = struct('minHeightFrac', pct/100, 'tolFrac', 0.01, 'minHold', 1);
end


function i_onTrimThreshold(fig)
    h = guidata(fig);
    raw = str2double(get(h.edTrimPct,'String'));
    if ~isscalar(raw) || ~isfinite(raw)
        set(h.edTrimPct,'String',num2str(h.trimMinPct));
        i_setStatus(fig,'Nilai trim harus angka 0–100. Dikembalikan.');
        return;
    end
    pct = min(max(raw, 0), 100);
    h.trimMinPct = pct; guidata(fig, h);
    set(h.edTrimPct,'String',num2str(pct));
    i_setStatus(fig, sprintf(['Gerbang Trim = %g%% puncak indenter (berlaku utk ', ...
        'Trim berikutnya; kurva ter-trim: Pulih lalu Trim ulang).'], pct));
end


function i_onClearTrim(fig)
%I_ONCLEARTRIM  Batalkan trim: kurva terpilih dikembalikan utuh. Tanpa seleksi
%   -> batalkan SEMUA trim.
    h = guidata(fig);
    rows = h.selRows(:).';
    rows = rows(rows >= 1 & rows <= numel(h.recs));
    if isempty(rows)
        rows = 1:numel(h.recs); scope = 'semua';
    else
        scope = 'terpilih';
    end
    nClr = 0;
    for r = rows
        if i_isTrimmed(h.recs(r)), nClr = nClr + 1; end
        h.recs(r).cutManual = false;
        h.recs(r).cutFrame  = NaN;
        h.recs(r).dataCut   = [];
    end
    h.assign = pivcore.pot.assign.fromRecords(i_recsForFeatures(h));
    guidata(fig, h);
    i_renderPOT(fig);
    i_refreshCurveTable(fig);
    if i_autoSaveAssign(fig)
        i_setStatus(fig, sprintf('Batal trim (%s): %d kurva dikembalikan utuh (tersimpan).', scope, nClr));
    end
end


% =====================================================================
% Helper label (KOMPATIBEL dgn step2 / suite PIVTerry)
% =====================================================================
function [ty, num] = i_typeNum(h)
    ty = 'HW'; num = 1;
    switch get(h.popType,'Value')
        case 1, ty = 'HW';
        case 2, ty = 'F';
        case 3, ty = 'F0';
        case 4, ty = 'FFW';
    end
    v = str2double(get(h.edNum,'String'));
    if isfinite(v), num = round(v); end
    if strcmp(ty,'F0') || strcmp(ty,'FFW'), num = 0; end
end


% =====================================================================
% Helper lokal
% =====================================================================
% --- helper generik bersama: forwarder ke +pivcore.util (satu sumber) ---
function b = i_baseName(p),        b = pivcore.util.baseName(p);          end
function v = i_scalar(x, varargin), v = pivcore.util.scalarOr(x, varargin{:}); end
function tf = i_isFull(h),         tf = pivcore.util.isFullLoaded(h);      end


% --- chrome GUI bersama: tipis forwarder ke +pivui (satu sumber kebenaran) ---
function i_lockAxInteractions(ax),  pivui.lockAxInteractions(ax);  end
function i_clearFigModes(fig),      pivui.clearFigModes(fig);      end
function i_setStatus(fig, msg),     pivui.setStatus(fig, msg);     end
function i_minimize(fig),           pivui.minimizeForDialog(fig);  end
function i_restore(fig),            pivui.restoreAfterDialog(fig); end
