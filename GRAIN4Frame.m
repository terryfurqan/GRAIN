function figOut = GRAIN4Frame(rootDir, varargin)
%GRAIN4FRAME  Step 4 (turunan GRAIN4) — EKSPOR FRAME (velmag + shear) BERDIRI SENDIRI.
%   Alat khusus untuk mengambil bingkai-bingkai tertentu AX main (Velocity
%   Magnitude & Shear Strain) sebagai gambar, DALAM KONDISI DI-ZOOM/CROP. Fokus:
%     (1) KONTROL UKURAN AX main (lebar/tinggi kotak-plot) — panel kanan.
%     (2) ZOOM + KUNCI PANDANG axMain untuk memangkas sisi kanan gambar yang tak
%         dipakai (eksperimen sering menyisakan ruang kanan kosong).
%     (3) EKSPOR yang MENGIKUTI PERSIS tampilan axMain (crop/zoom + setelan
%         tampilan kolom tengah: CLim/GS/glyph/CLAHE) -> 2 JPG per bingkai.
%
%   PERBEDAAN dari GRAIN4:
%     - SEMUA input DESC (tabel deskripsi, POI, NUC, sesar, taper, dst.) DIBUANG.
%     - axPOT plot di bawah axMain DISINGKIRKAN -> axMain memenuhi ruang vertikal.
%     - Panel kanan HANYA berisi: kontrol ukuran axMain, zoom/kunci pandang,
%       input rentang bingkai + tombol ekspor gambar (velmag/shear), MP4, dan
%       navigasi eksperimen. (Tombol "kolom kanan bagian bawah" GRAIN4 dipertahankan
%       yang relevan: 🖼 rentang / exp ini / semua exp, 🎬 MP4, Prev/Next EXP.)
%
%   Setelan tampilan (kolom TENGAH atas: skalar/CLim/GS/alpha/glyph/CLAHE) tetap
%   LIVE dan DIHORMATI saat ekspor. Ukuran & aspek gambar hasil = kotak-plot
%   axMain (crop XLim/YLim aktif) × "sisi panjang (px)".
%
%   GRAIN4Frame                 % pilih folder ROOT (dialog)
%   GRAIN4Frame(rootDir)        % langsung ke folder
%
%   Jalankan `grain_setup` sekali per sesi. SELALU MATLAB R2025b. TIDAK menulis
%   sidecar apa pun (murni PEMBACA + EKSPOR gambar). Output ke folder ber-versi
%   GRAIN/GRAIN4Frame_export/<exp>/<ddmmyy-HHMMSS>_<psg>_frames|_mp4/.

    figOut = [];
    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivui.grain4Shell'))
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
    end
    if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
        rootDir = uigetdir(pwd, 'Pilih folder berisi .mat PIV (output Step 2 / PIV_<tgl>/)');
        if isequal(rootDir, 0), return; end
    end

    opts = struct();
    opts.Name = 'GRAIN4Frame — Ekspor Frame (velmag + shear, zoom-aware)';
    opts.rightTitle = 'Ekspor Frame (Step 4 — gambar)';
    opts.hooks = struct( ...
        'onExpLoaded',     @i_onExpLoaded, ...
        'afterRenderMain', @i_afterRenderMain);

    h = pivui.grain4Shell.build(opts);

    % --- State minimal (zoom/kunci pandang axMain) -------------------------
    h.df = '';
    h.activePsgId = '';
    h.frameLabelPos  = 'left';   % default 'left' (Kiri atas) atau 'right' (Kanan atas)
    h.axCalR         = struct('dxCm', NaN, 'strainTotalPct', NaN);
    h.axMainViewLock = false;   % kunci pandang aktif -> pertahankan view tiap render
    h.axMainViewLim  = [];      % [xl(1) xl(2) yl(1) yl(2)] view beku
    h.axMainZoomOn   = false;   % mode zoom/pan interaktif aktif (toggle)
    h.axMainLockLsnr = [];      % listener anti-flicker PostSet
    h.frameImgCancel = false;
    h.movieCancel    = false;
    guidata(h.fig, h);

    % --- Singkirkan axPOT + strip kontrol POT (maksimalkan tinggi axMain) ---
    i_stripDownToAxMain(h);

    % --- axMain memenuhi ruang vertikal (axPOT dibuang) --------------------
    % Default: kiri 0.205, bawah 0.075, lebar 0.470 (mepet panel kanan x=0.686),
    % tinggi 0.800 (sampai bawah strip kontrol tampilan pnlC ~0.888). Data 1:1
    % (daspect renderMain) -> whitespace di DALAM box, diatur via zoom/crop +
    % kontrol ukuran box. h.axMainPos diterapkan ULANG tiap afterRenderMain.
    AXMAIN_POS = [0.205 0.075 0.470 0.800];
    h.axMainPos    = AXMAIN_POS;
    h.axMainPosDef = AXMAIN_POS;
    try, set(h.axMain, 'Position', AXMAIN_POS); catch, end
    guidata(h.fig, h);

    % --- Panel kanan: kontrol ukuran + zoom + ekspor -----------------------
    h = i_buildFramePanel(h, h.pnlR);
    guidata(h.fig, h);

    % Ratakan dasar panel kanan dgn kolom kiri + naikkan puncaknya.
    try, set(h.pnlR, 'Position', [0.686 0.010 0.308 0.985]); catch, end

    pivui.grain4Shell.setRoot(h.fig, rootDir);
    figOut = h.fig;
end


% =====================================================================
% LAYOUT — singkirkan axPOT & strip kontrol POT
% =====================================================================
function i_stripDownToAxMain(h)
%I_STRIPDOWNTOAXMAIN  Sembunyikan axPOT + overlay AX-AC + strip kontrol POT
%   (antara axMain & axPOT) supaya area itu bebas dipakai axMain. axPOT tetap
%   ADA (shell renderPOT masih menggambar ke situ tanpa error) tapi INVISIBLE &
%   NON-PICKABLE supaya tak menelan klik zoom/pan di area axMain yang diperbesar.
    fig = h.fig;
    for nm = {'axPOT','axACtop','axACbot'}
        if isfield(h,nm{1}) && ishghandle(h.(nm{1}))
            try
                set(h.(nm{1}), 'Visible','off', 'HitTest','off', 'PickableParts','none');
                kids = get(h.(nm{1}),'Children');
                for j = 1:numel(kids), try, set(kids(j),'Visible','off'); catch, end, end
            catch, end
        end
    end
    % Strip kontrol POT: tombol/edit/slider bernama + 2 label teks tak bernama.
    for nm = {'btnAxView','edSpacing','sldVScale','btnLock'}
        if isfield(h,nm{1}) && ishghandle(h.(nm{1}))
            try, set(h.(nm{1}), 'Visible','off'); catch, end
        end
    end
    try
        tx = findobj(fig,'Type','uicontrol','Style','text');
        for j = 1:numel(tx)
            s = get(tx(j),'String');
            if ischar(s) && any(strcmp(s, {'Spacing px:','Skala-V:'}))
                set(tx(j),'Visible','off');
            end
        end
    catch, end
end


% =====================================================================
% PANEL KANAN — kontrol ukuran axMain, zoom, ekspor
% =====================================================================
function h = i_buildFramePanel(h, P)
%I_BUILDFRAMEPANEL  Isi panel kanan (P = h.pnlR) dengan kontrol GRAIN4Frame.
    WHITE = [1 1 1];
    fig = h.fig;

    % --- (0) Bantuan singkat -------------------------------------------
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.930 0.94 0.055],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',8.5,'ForegroundColor',[0.25 0.25 0.25], ...
        'String',['Atur UKURAN axMain + ZOOM (crop sisi kanan yg tak dipakai), lalu ' ...
        'ekspor bingkai. Gambar hasil MENGIKUTI persis tampilan axMain (crop + CLim/GS/glyph).']);

    % --- (1) UKURAN AX main --------------------------------------------
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.892 0.94 0.028],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontWeight','bold','FontSize',9.5, ...
        'ForegroundColor',[0.15 0.30 0.55],'String','① Ukuran kotak AX main');
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.858 0.20 0.026],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',9,'String','Lebar:');
    h.edAxW = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.22 0.858 0.14 0.030],'String',sprintf('%.3f',h.axMainPos(3)), ...
        'BackgroundColor',WHITE,'FontSize',9,'HorizontalAlignment','center', ...
        'TooltipString','Lebar kotak-plot axMain (fraksi jendela, 0.20–0.475).', ...
        'Callback',@(s,e) i_onApplyAxSize(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.40 0.858 0.18 0.026],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',9,'String','Tinggi:');
    h.edAxH = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.57 0.858 0.14 0.030],'String',sprintf('%.3f',h.axMainPos(4)), ...
        'BackgroundColor',WHITE,'FontSize',9,'HorizontalAlignment','center', ...
        'TooltipString','Tinggi kotak-plot axMain (fraksi jendela, 0.20–0.90).', ...
        'Callback',@(s,e) i_onApplyAxSize(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.72 0.856 0.12 0.032],'String','Terapkan', ...
        'FontSize',8.5,'BackgroundColor',[0.90 0.95 0.90], ...
        'TooltipString','Terapkan ukuran kotak axMain.', ...
        'Callback',@(s,e) i_onApplyAxSize(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.85 0.856 0.12 0.032],'String','Reset', ...
        'FontSize',8.5,'BackgroundColor',[0.96 0.94 0.86], ...
        'TooltipString','Kembalikan ukuran axMain default.', ...
        'Callback',@(s,e) i_onResetAxSize(fig));

    % --- (2) ZOOM & KUNCI PANDANG --------------------------------------
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.814 0.94 0.028],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontWeight','bold','FontSize',9.5, ...
        'ForegroundColor',[0.15 0.30 0.55],'String','② Zoom / crop axMain');
    h.btnAxZoom = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.03 0.774 0.30 0.034],'String','🔍 Zoom','Value',0,'FontWeight','bold', ...
        'TooltipString',['Zoom/pan axMain: ON = scroll utk zoom, drag utk geser. Perbesar area ' ...
        'yang menarik (buang sisi kanan kosong) lalu klik 🔒 utk KUNCI. OFF = tampilan penuh.'], ...
        'Callback',@(s,e) i_onAxMainZoom(fig));
    h.btnAxViewLock = uicontrol('Parent',P,'Style','togglebutton','Units','normalized', ...
        'Position',[0.35 0.774 0.36 0.034],'String','🔒 Kunci pandang','Value',0,'FontWeight','bold', ...
        'TooltipString',['KUNCI PANDANG axMain: bekukan area tampil (zoom/pan) sekarang supaya ' ...
        'TETAP saat ganti frame & saat EKSPOR. Klik lagi = lepas.'], ...
        'Callback',@(s,e) i_onAxMainViewLock(fig));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.73 0.774 0.24 0.034],'String','⟲ Penuh', ...
        'FontSize',8.5,'BackgroundColor',[0.94 0.94 0.94], ...
        'TooltipString','Reset axMain ke tampilan penuh (buang zoom & kunci pandang).', ...
        'Callback',@(s,e) i_onAxMainFull(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.736 0.30 0.026],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',9,'String','Posisi label:');
    vPop = 1;
    if isfield(h,'frameLabelPos') && strcmp(h.frameLabelPos,'right'), vPop = 2; end
    h.popFrameLabelPos = uicontrol('Parent',P,'Style','popupmenu','Units','normalized', ...
        'Position',[0.34 0.734 0.37 0.030],'String',{'Kiri atas', 'Kanan atas'}, ...
        'Value',vPop,'BackgroundColor',WHITE,'FontSize',9, ...
        'TooltipString','Atur posisi label bingkai pada axMain (kiri atas atau kanan atas).', ...
        'Callback',@(s,e) i_onFrameLabelPos(fig));

    % --- (3) EKSPOR GAMBAR ---------------------------------------------
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.690 0.94 0.028],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontWeight','bold','FontSize',9.5, ...
        'ForegroundColor',[0.30 0.15 0.55],'String','③ Ekspor bingkai (velmag + shear)');
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.656 0.32 0.026],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',9,'String','Sisi panjang (px):');
    h.edExportPx = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.34 0.656 0.16 0.030],'String','1600', ...
        'BackgroundColor',WHITE,'FontSize',9,'HorizontalAlignment','center', ...
        'TooltipString','Resolusi ekspor: sisi PANJANG kotak-plot (px). Aspek dari crop axMain.', ...
        'Callback',@(s,e) i_syncExportPx(fig));
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.53 0.656 0.20 0.026],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',9,'String','Rentang:');
    h.edFrameRange = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.72 0.656 0.25 0.030],'String','', ...
        'BackgroundColor',WHITE,'FontSize',9,'HorizontalAlignment','center', ...
        'TooltipString',['Rentang bingkai untuk ekspor. Kosong = bingkai kini. "12" = satu ' ...
        'bingkai. "5-20" atau "5:20" = rentang. Di-clamp ke [1..jumlah frame].']);
    h.btnFrameImg = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.614 0.30 0.036],'String','🖼 rentang', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.90 0.86 0.98],'ForegroundColor',[0.30 0.15 0.55], ...
        'TooltipString',['Ekspor axMain tiap bingkai di RENTANG -> 2 JPG (velmag + shear). ' ...
        'Mengikuti crop/zoom axMain + setelan tampilan (kolom tengah).'], ...
        'Callback',@(s,e) i_onExportFrameImg(fig));
    h.btnFrameExp = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.35 0.614 0.30 0.036],'String','🖼 exp ini', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.86 0.80 0.96],'ForegroundColor',[0.26 0.12 0.50], ...
        'TooltipString','Ekspor SEMUA bingkai (1..akhir) EKSPERIMEN AKTIF -> 2 JPG per bingkai.', ...
        'Callback',@(s,e) i_onExportFramesExpCur(fig));
    h.btnFrameAllExp = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.67 0.614 0.30 0.036],'String','🖼 semua exp', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.80 0.72 0.94],'ForegroundColor',[0.22 0.10 0.46], ...
        'TooltipString','Ekspor SEMUA bingkai untuk SEMUA eksperimen di folder (crop/zoom SAMA).', ...
        'Callback',@(s,e) i_onExportFramesAllExp(fig));
    h.btnFrameImgCancel = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.614 0.94 0.036],'String','✖ CANCEL — hentikan ekspor gambar', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[1.0 0.85 0.85],'ForegroundColor',[0.6 0 0], ...
        'Visible','off','TooltipString','Hentikan ekspor gambar (berhenti di bingkai berikutnya).', ...
        'Callback',@(s,e) i_onFrameImgCancel(fig));

    % --- (4) EKSPOR MP4 -------------------------------------------------
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.558 0.94 0.028],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontWeight','bold','FontSize',9.5, ...
        'ForegroundColor',[0.10 0.40 0.15],'String','④ Ekspor MP4 (semua bingkai)');
    uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.524 0.28 0.026],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',9,'String','Durasi (s):');
    h.edMovieDur = uicontrol('Parent',P,'Style','edit','Units','normalized', ...
        'Position',[0.30 0.524 0.14 0.030],'String','30', ...
        'BackgroundColor',WHITE,'FontSize',9,'HorizontalAlignment','center', ...
        'TooltipString','Target durasi video (s). fps = jumlah frame / durasi. Kosong/0 -> 5 fps.');
    h.btnMovie = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.46 0.522 0.25 0.034],'String','🎬 exp ini', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.86 0.94 0.86],'ForegroundColor',[0.10 0.40 0.15], ...
        'TooltipString','Rakit 2 MP4 (velmag + shear) SEMUA frame EKSPERIMEN AKTIF (crop/zoom axMain).', ...
        'Callback',@(s,e) i_onExportMovie(fig));
    h.btnMovieAll = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.72 0.522 0.25 0.034],'String','🎬 semua', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[0.80 0.90 0.80],'ForegroundColor',[0.08 0.34 0.13], ...
        'TooltipString','Rakit MP4 (velmag + shear) untuk SEMUA eksperimen di folder ini.', ...
        'Callback',@(s,e) i_onExportMovieAll(fig));
    h.btnMovieCancel = uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.46 0.522 0.51 0.034],'String','✖ CANCEL MP4', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',[1.0 0.85 0.85],'ForegroundColor',[0.6 0 0], ...
        'Visible','off','TooltipString','Hentikan pembuatan MP4 (file parsial dihapus).', ...
        'Callback',@(s,e) i_onMovieCancel(fig));

    % --- (5) NAVIGASI + status -----------------------------------------
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.070 0.30 0.040],'String','◀ Prev EXP', ...
        'FontSize',9,'BackgroundColor',[0.92 0.92 0.96], ...
        'TooltipString','Muat eksperimen sebelumnya di daftar kiri.', ...
        'Callback',@(s,e) i_onStepExp(fig,-1));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.35 0.070 0.30 0.040],'String','Next EXP ▶', ...
        'FontSize',9,'BackgroundColor',[0.92 0.92 0.96], ...
        'TooltipString','Muat eksperimen berikutnya di daftar kiri.', ...
        'Callback',@(s,e) i_onStepExp(fig,+1));
    uicontrol('Parent',P,'Style','pushbutton','Units','normalized', ...
        'Position',[0.67 0.070 0.30 0.040],'String','✖ Tutup', ...
        'FontSize',9,'BackgroundColor',[0.96 0.90 0.90], ...
        'TooltipString','Tutup GRAIN4Frame.', ...
        'Callback',@(s,e) i_onClose(fig));
    h.txtFrameStatus = uicontrol('Parent',P,'Style','text','Units','normalized', ...
        'Position',[0.03 0.020 0.94 0.042],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',8.5,'ForegroundColor',[0.20 0.40 0.20], ...
        'String','Pilih folder lalu sebuah eksperimen dari tabel di kiri.');
end


% =====================================================================
% HOOKS shell
% =====================================================================
function i_onExpLoaded(fig)
%I_ONEXPLOADED  Dipanggil shell tiap eksperimen dimuat. Set h.df + reset zoom.
    h = guidata(fig);
    if isfield(h,'realData'), h.df = h.realData; end
    h.activePsgId = '';
    % Reset kunci pandang antar-exp (crop exp lama tak boleh membajak exp baru).
    h.axMainViewLock = false; h.axMainViewLim = [];

    % Baca geometri eksperimen (shortening cm & strain %) untuk label frame
    dxCm = NaN; strTot = NaN;
    try, [strTot, ~, dxCm] = pivcore.export.frameCatalog.readGeom(h.df); catch, end
    h.axCalR = struct('dxCm', dxCm, 'strainTotalPct', strTot);

    guidata(fig, h);
    i_setAxMainLockListener(fig, false);
    try, if isfield(h,'btnAxViewLock') && ishghandle(h.btnAxViewLock), set(h.btnAxViewLock,'Value',0); end, catch, end
    nm = i_baseName(h.df);
    i_status(fig, sprintf('Termuat: %s. Atur ukuran/zoom axMain lalu ekspor bingkai.', nm));
end

function i_afterRenderMain(fig)
%I_AFTERRENDERMAIN  Pasca tiap render axMain: bekukan garis PSG (read-only),
%   terapkan ULANG ukuran axMain (colorbar menyusutkan axes), isi tinggi box,
%   dan pertahankan mode zoom + kunci pandang.
    h = guidata(fig);
    % Garis PSG (bila shell membuat ROI) -> non-interaktif (GRAIN4Frame = pembaca).
    if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi)
        try, h.roi.InteractionsAllowed = 'none'; catch, end
    end
    if isfield(h,'axMainPos') && numel(h.axMainPos)==4 ...
            && isfield(h,'axMain') && ishghandle(h.axMain)
        try
            cur = get(h.axMain,'Position');
            if any(abs(cur - h.axMainPos) > 1e-4)
                set(h.axMain,'Position', h.axMainPos);
            end
        catch, end
    end
    i_fillAxMainHeight(fig);
    i_applyAxMainZoomMode(fig);
    i_applyAxMainViewLock(fig);
end

function i_fillAxMainHeight(fig)
%I_FILLAXMAINHEIGHT  Buat gambar 1:1 MENGISI TINGGI box axMain: perbesar YLim
%   (margin atas-bawah simetris) sampai rasio data == rasio box px. Hormati
%   kunci pandang (skip bila terkunci). (Salinan dari GRAIN4.)
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    if isfield(h,'axMainViewLock') && h.axMainViewLock, return; end
    ax = h.axMain;
    try
        if ~strcmp(get(ax,'DataAspectRatioMode'),'manual'), return; end
        da = get(ax,'DataAspectRatio');
        if ~(numel(da)>=2 && da(1)==da(2)), return; end
    catch, return; end
    oldU = get(ax,'Units');
    try
        set(ax,'Units','pixels'); ppx = get(ax,'Position'); set(ax,'Units',oldU);
    catch
        set(ax,'Units',oldU); return;
    end
    boxW = ppx(3); boxH = ppx(4);
    if ~(boxW>0 && boxH>0), return; end
    boxAspect = boxW / boxH;
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    xspan = diff(xl); yspan = diff(yl);
    if ~(xspan>0 && yspan>0), return; end
    dataAspect = xspan / yspan;
    if dataAspect <= boxAspect + 1e-6, return; end
    yspanTarget = xspan / boxAspect;
    yc = mean(yl);
    try, set(ax,'YLim', [yc - yspanTarget/2, yc + yspanTarget/2]); catch, end
end


% =====================================================================
% KONTROL UKURAN axMain
% =====================================================================
function i_onApplyAxSize(fig)
%I_ONAPPLYAXSIZE  Terapkan lebar/tinggi kotak axMain dari kotak edit (clamp),
%   set Position + render ulang. Kiri/bawah tetap.
    h = guidata(fig);
    w = i_readNum(h.edAxW, h.axMainPos(3));
    ht = i_readNum(h.edAxH, h.axMainPos(4));
    w  = max(0.20, min(0.475, w));
    ht = max(0.20, min(0.90,  ht));
    h.axMainPos = [h.axMainPosDef(1) h.axMainPosDef(2) w ht];
    guidata(fig, h);
    set(h.edAxW,'String',sprintf('%.3f',w));
    set(h.edAxH,'String',sprintf('%.3f',ht));
    try, set(h.axMain,'Position', h.axMainPos); catch, end
    try, pivui.grain4Shell.renderMain(fig); catch, end
    i_status(fig, sprintf('Ukuran axMain: lebar %.3f × tinggi %.3f.', w, ht));
end

function i_onResetAxSize(fig)
    h = guidata(fig);
    h.axMainPos = h.axMainPosDef; guidata(fig, h);
    set(h.edAxW,'String',sprintf('%.3f',h.axMainPos(3)));
    set(h.edAxH,'String',sprintf('%.3f',h.axMainPos(4)));
    try, set(h.axMain,'Position', h.axMainPos); catch, end
    try, pivui.grain4Shell.renderMain(fig); catch, end
    i_status(fig, 'Ukuran axMain dikembalikan ke default.');
end

function i_syncExportPx(fig)
    h = guidata(fig);
    v = i_readNum(h.edExportPx, 1600);
    v = max(300, min(4000, round(v)));
    set(h.edExportPx,'String',sprintf('%d',v));
end

function i_onFrameLabelPos(fig)
%I_ONFRAMELABELPOS  Callback perubahan posisi label bingkai (Kiri atas / Kanan atas)
    h = guidata(fig);
    if isfield(h,'popFrameLabelPos') && ishghandle(h.popFrameLabelPos)
        val = get(h.popFrameLabelPos, 'Value');
        if val == 2
            h.frameLabelPos = 'right';
        else
            h.frameLabelPos = 'left';
        end
        guidata(fig, h);
        if isfield(h,'axMain') && ishghandle(h.axMain)
            try
                nFimg = max(1, pivcore.util.scalarOr(h.imgFrames, h.nF));
                pivui.grain4Shell.drawStrainState(fig, h.axMain, h.frame, nFimg);
            catch, end
        end
    end
end


% =====================================================================
% ZOOM + KUNCI PANDANG axMain (disalin dari GRAIN4)
% =====================================================================
function i_onAxMainZoom(fig)
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain))
        pivui.setStatus(fig,'axMain belum ada.'); return;
    end
    want = ~h.axMainZoomOn;
    if want
        h.axMainZoomOn = true; guidata(fig, h);
        i_applyAxMainZoomMode(fig);
        set(h.btnAxZoom,'Value',1);
        i_status(fig,'Zoom axMain AKTIF: scroll=zoom, drag=geser. Klik 🔒 utk kunci pandang.');
    else
        h.axMainZoomOn = false; h.axMainViewLock = false; h.axMainViewLim = [];
        guidata(fig, h);
        i_setAxMainLockListener(fig, false);
        try, set(h.btnAxViewLock,'Value',0); catch, end
        set(h.btnAxZoom,'Value',0);
        try, pivui.grain4Shell.renderMain(fig); catch, end
        i_status(fig,'Zoom axMain MATI: tampilan penuh dipulihkan.');
    end
end

function i_applyAxMainZoomMode(fig)
    h = guidata(fig);
    if ~(isfield(h,'axMainZoomOn') && h.axMainZoomOn), return; end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    ax = h.axMain;
    try, enableDefaultInteractivity(ax); catch, end
    try
        ax.Interactions = [zoomInteraction('Dimensions','xy'); panInteraction()];
    catch
        try, ax.Interactions = [zoomInteraction; panInteraction]; catch, end
    end
    try, ax.Toolbar = axtoolbar(ax, {'zoomin','zoomout','pan','restoreview'}); catch, end
end

function i_onAxMainViewLock(fig)
    h = guidata(fig);
    if ~(isfield(h,'axMain') && ishghandle(h.axMain))
        pivui.setStatus(fig,'axMain belum ada.'); return;
    end
    want = ~h.axMainViewLock;
    if want
        xl = get(h.axMain,'XLim'); yl = get(h.axMain,'YLim');
        h.axMainViewLock = true; h.axMainViewLim = [xl(1) xl(2) yl(1) yl(2)];
        guidata(fig, h);
        set(h.btnAxViewLock,'Value',1);
        i_setAxMainLockListener(fig, true);
        i_status(fig, sprintf('Pandang axMain DIKUNCI: X[%.0f %.0f] Y[%.0f %.0f] — ekspor mengikuti crop ini.', xl, yl));
    else
        h.axMainViewLock = false; h.axMainViewLim = []; guidata(fig, h);
        set(h.btnAxViewLock,'Value',0);
        i_setAxMainLockListener(fig, false);
        try, pivui.grain4Shell.renderMain(fig); catch, end
        i_status(fig,'Kunci pandang axMain DILEPAS (kembali ke ekstent penuh).');
    end
end

function i_applyAxMainViewLock(fig)
    h = guidata(fig);
    if ~(isfield(h,'axMainViewLock') && h.axMainViewLock), return; end
    if ~(isfield(h,'axMainViewLim') && numel(h.axMainViewLim)==4), return; end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    L = h.axMainViewLim;
    try, set(h.axMain,'XLim',L(1:2),'YLim',L(3:4)); catch, end
end

function i_setAxMainLockListener(fig, on)
    h = guidata(fig);
    if isfield(h,'axMainLockLsnr') && ~isempty(h.axMainLockLsnr)
        try, delete(h.axMainLockLsnr); catch, end
        h.axMainLockLsnr = []; guidata(fig, h);
    end
    if ~on, return; end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    try
        lx = addlistener(h.axMain, 'XLim', 'PostSet', @(s,e) i_onAxMainLimPostSet(fig));
        ly = addlistener(h.axMain, 'YLim', 'PostSet', @(s,e) i_onAxMainLimPostSet(fig));
        h.axMainLockLsnr = [lx, ly];
        guidata(fig, h);
    catch, end
end

function i_onAxMainLimPostSet(fig)
    if ~ishghandle(fig), return; end
    if isappdata(fig,'axMainLockBusy') && getappdata(fig,'axMainLockBusy'), return; end
    h = guidata(fig);
    if ~(isfield(h,'axMainViewLock') && h.axMainViewLock), return; end
    if ~(isfield(h,'axMainViewLim') && numel(h.axMainViewLim)==4), return; end
    if ~(isfield(h,'axMain') && ishghandle(h.axMain)), return; end
    L = h.axMainViewLim; ax = h.axMain;
    cx = get(ax,'XLim'); cy = get(ax,'YLim');
    if isequal(cx(:).',L(1:2)) && isequal(cy(:).',L(3:4)), return; end
    setappdata(fig,'axMainLockBusy',true);
    try, set(ax,'XLim',L(1:2),'YLim',L(3:4)); catch, end
    setappdata(fig,'axMainLockBusy',false);
end

function i_onAxMainFull(fig)
%I_ONAXMAINFULL  Reset axMain ke tampilan penuh (buang zoom + kunci pandang).
    h = guidata(fig);
    h.axMainZoomOn = false; h.axMainViewLock = false; h.axMainViewLim = [];
    guidata(fig, h);
    i_setAxMainLockListener(fig, false);
    try, set(h.btnAxZoom,'Value',0); catch, end
    try, set(h.btnAxViewLock,'Value',0); catch, end
    try, pivui.grain4Shell.renderMain(fig); catch, end
    i_status(fig,'axMain: tampilan penuh dipulihkan.');
end


% =====================================================================
% EKSPOR GAMBAR per-bingkai (zoom-aware)
% =====================================================================
function i_onExportFrameImg(fig)
%I_ONEXPORTFRAMEIMG  Ekspor axMain bingkai (rentang dari kotak) -> 2 JPG.
    h = guidata(fig);
    if isempty(h.df) || isempty(h.data)
        i_status(fig,'Belum ada eksperimen dimuat.'); return;
    end
    nF = i_ensureFullFrames(fig); h = guidata(fig);
    rngTxt = '';
    if isfield(h,'edFrameRange') && ishghandle(h.edFrameRange)
        rngTxt = strtrim(get(h.edFrameRange,'String'));
    end
    frames = i_parseFrameRange(rngTxt, h.frame, nF);
    if isempty(frames)
        i_status(fig,'Rentang bingkai tak valid.'); return;
    end
    i_frameImgBtnState(fig, true);
    cu = onCleanup(@() i_frameImgBtnState(fig, false)); %#ok<NASGU>
    res = i_exportFramesCurExp(fig, frames);
    if isempty(res), i_status(fig,'Ekspor gagal / tak ada data.'); return; end
    if res.cancelled
        i_status(fig, sprintf('Ekspor DIBATALKAN (%d file tertulis).', res.written));
    else
        i_status(fig, sprintf('Selesai: %d bingkai × 2 = %d file -> %s', res.nFr, res.written, res.outDir));
        try, msgbox(sprintf(['Ekspor %d bingkai (velmag + shear) = %d file.\n\nFolder:\n%s'], ...
            res.nFr, res.written, res.outDir), 'GRAIN4Frame — Ekspor frame'); catch, end
    end
end

function i_onExportFramesExpCur(fig)
%I_ONEXPORTFRAMESEXPCUR  Ekspor SEMUA bingkai eksperimen aktif.
    h = guidata(fig);
    if isempty(h.df) || isempty(h.data)
        i_status(fig,'Belum ada eksperimen dimuat.'); return;
    end
    nF = i_ensureFullFrames(fig);
    i_frameImgBtnState(fig, true);
    cu = onCleanup(@() i_frameImgBtnState(fig, false)); %#ok<NASGU>
    res = i_exportFramesCurExp(fig, 1:nF);
    if isempty(res), i_status(fig,'Ekspor gagal / tak ada data.'); return; end
    if res.cancelled
        i_status(fig, sprintf('Ekspor DIBATALKAN (%d file tertulis).', res.written));
    else
        i_status(fig, sprintf('Selesai: %d bingkai × 2 = %d file.', res.nFr, res.written));
        try, msgbox(sprintf(['Ekspor %d bingkai (velmag + shear) = %d file.\n\nFolder:\n%s'], ...
            res.nFr, res.written, res.outDir), 'GRAIN4Frame — Ekspor frame'); catch, end
    end
end

function i_onExportFramesAllExp(fig)
%I_ONEXPORTFRAMESALLEXP  Ekspor SEMUA bingkai untuk SEMUA eksperimen di folder.
%   Crop/zoom & setelan tampilan SAMA. Eksperimen semula dipulihkan.
    h = guidata(fig);
    if ~isfield(h,'list') || isempty(h.list)
        i_status(fig,'Belum ada daftar eksperimen (pilih folder dulu).'); return;
    end
    N = numel(h.list);
    row0 = h.activeRow;
    i_frameImgBtnState(fig, true);
    cu = onCleanup(@() i_frameImgBtnState(fig, false)); %#ok<NASGU>
    totFiles = 0; totFrames = 0; lastDir = ''; cancelled = false;
    for i = 1:N
        hc = guidata(fig);
        if isfield(hc,'frameImgCancel') && hc.frameImgCancel, cancelled = true; break; end
        try, pivui.grain4Shell.loadExperiment(fig, i); catch, continue; end
        nF = i_ensureFullFrames(fig);
        nm = i_baseName(getfield(guidata(fig),'df'));
        res = i_exportFramesCurExp(fig, 1:nF, sprintf('%d/%d: %s', i, N, nm));
        if ~isempty(res)
            totFiles = totFiles + res.written; totFrames = totFrames + res.nFr;
            lastDir = res.outDir;
            if res.cancelled, cancelled = true; break; end
        end
    end
    if row0 >= 1
        try, pivui.grain4Shell.loadExperiment(fig, row0); catch, end
    end
    if cancelled
        i_status(fig, sprintf('Ekspor semua exp DIBATALKAN (%d file).', totFiles));
    else
        i_status(fig, sprintf('Selesai semua exp: %d bingkai = %d file.', totFrames, totFiles));
        try, msgbox(sprintf(['Ekspor SEMUA exp selesai.\n\n%d bingkai × 2 = %d file.\n\n' ...
            'Folder terakhir:\n%s'], totFrames, totFiles, lastDir), 'GRAIN4Frame — Ekspor semua exp'); catch, end
    end
end

function res = i_exportFramesCurExp(fig, frames, tag)
%I_EXPORTFRAMESCUREXP  Render axMain tiap bingkai (velmag + shear) -> 2 JPG ke
%   folder ber-versi. MENGIKUTI crop/zoom axMain aktif (XLim/YLim ditangkap
%   SEKALI di awal) + setelan tampilan kolom tengah (CLim/GS/glyph). Return
%   struct(written,nFr,outDir,cancelled); [] bila tak ada data.
    res = [];
    if nargin < 3, tag = ''; end
    h = guidata(fig);
    if isempty(h.df) || isempty(h.data), return; end

    nF = max(1, pivcore.data.frameCount(h.data));
    frames = frames(frames >= 1 & frames <= nF);
    if isempty(frames), return; end

    cropLim = i_axMainCropLim(h);
    longPx  = i_exportLongPx(h);
    [figW, figH] = i_figSizeFromCrop(cropLim, [0.045 0.070 0.800 0.850], longPx);

    outDir = i_exportDir(h, 'frames');
    if ~isfolder(outDir), mkdir(outDir); end

    strainTot = i_strainTotal(h);
    opts = struct('velMult', i_velMult(h), 'axPos', [0.045 0.070 0.800 0.850], 'cropLim', cropLim);
    opts.gsCache = containers.Map('KeyType','char','ValueType','any');
    cuGs = onCleanup(@() i_mapClear(opts.gsCache)); %#ok<NASGU>

    scalars = pivcore.io.grain4DescExport.scalarNames();   % {'velmag','shear'}
    nFr = numel(frames);
    pfx = ''; if ~isempty(tag), pfx = [char(tag) ' — ']; end
    wb = i_waitbar(sprintf('%sEkspor %d bingkai × 2 (velmag + shear)…', pfx, nFr));
    cuw = onCleanup(@() i_closeWb(wb)); %#ok<NASGU>

    movFig = figure('Visible','off','Color','w','Units','pixels','Position',[100 100 figW figH]);
    try, pivui.forceLightTheme(movFig); catch, end
    set(movFig,'Color','w');
    cuFig = onCleanup(@() i_closeIf(movFig)); %#ok<NASGU>

    frame0 = h.frame;
    written = 0; cancelled = false;
    for ii = 1:nFr
        hc = guidata(fig);
        if isfield(hc,'frameImgCancel') && hc.frameImgCancel, cancelled = true; break; end
        k = frames(ii);
        pivui.grain4Shell.setFrameQuiet(fig, k);
        for si = 1:numel(scalars)
            sc = scalars{si};
            rgb = i_frameRGB(fig, movFig, sc, k, opts, strainTot);
            if isempty(rgb), continue; end
            fn = pivcore.io.grain4DescExport.frameImgFile(h.df, sc, k, 'jpg');
            try, imwrite(rgb, fullfile(outDir, fn), 'jpg', 'Quality', 92); written = written + 1; catch, end
        end
        if ~isempty(wb) && ishghandle(wb)
            try, waitbar(ii/nFr, wb, sprintf('%sFrame %d (%d/%d)…', pfx, k, ii, nFr)); catch, end
        end
    end

    try, pivui.grain4Shell.gotoFrame(fig, frame0); catch, end
    res = struct('written',written, 'nFr',nFr, 'outDir',outDir, 'cancelled',cancelled);
end

function i_onFrameImgCancel(fig)
    h = guidata(fig); h.frameImgCancel = true; guidata(fig, h);
    i_status(fig, 'Membatalkan ekspor gambar…');
    drawnow;
end

function i_frameImgBtnState(fig, running)
    h = guidata(fig);
    ids = {'btnFrameImg','btnFrameExp','btnFrameAllExp'};
    for i = 1:numel(ids)
        if isfield(h,ids{i}) && ishghandle(h.(ids{i}))
            set(h.(ids{i}),'Visible', i_tern(running,'off','on'));
        end
    end
    if isfield(h,'btnFrameImgCancel') && ishghandle(h.btnFrameImgCancel)
        set(h.btnFrameImgCancel,'Visible', i_tern(running,'on','off'));
    end
    if ~running, h.frameImgCancel = false; guidata(fig, h); end
    drawnow limitrate;
end


% =====================================================================
% EKSPOR MP4 (zoom-aware; reuse i_frameRGB)
% =====================================================================
function i_onExportMovie(fig)
    h = guidata(fig);
    if isempty(h.df) || isempty(h.data)
        i_status(fig,'Belum ada eksperimen dimuat.'); return;
    end
    i_movieBtnState(fig, true);
    cu = onCleanup(@() i_movieBtnState(fig, false)); %#ok<NASGU>
    res = i_exportMovieCurExp(fig);
    if isempty(res), i_status(fig,'MP4 gagal / tak ada data.'); return; end
    if res.cancelled
        i_status(fig,'MP4 DIBATALKAN.');
    else
        i_status(fig, sprintf('MP4 selesai: %d file (%.2g fps ≈ %.1fs) -> %s', ...
            numel(res.written), res.fps, res.durActual, res.movDir));
        try, msgbox(sprintf(['MP4 selesai.\n\n%d frame × 2 (velmag + shear), %.2g fps ≈ %.1fs.\n\n' ...
            'Folder:\n%s'], res.nF, res.fps, res.durActual, res.movDir), 'GRAIN4Frame — MP4'); catch, end
    end
end

function i_onExportMovieAll(fig)
    h = guidata(fig);
    if ~isfield(h,'list') || isempty(h.list)
        i_status(fig,'Belum ada daftar eksperimen (pilih folder dulu).'); return;
    end
    N = numel(h.list); row0 = h.activeRow;
    i_movieBtnState(fig, true);
    cu = onCleanup(@() i_movieBtnState(fig, false)); %#ok<NASGU>
    nOk = 0; cancelled = false;
    for i = 1:N
        hc = guidata(fig);
        if isfield(hc,'movieCancel') && hc.movieCancel, cancelled = true; break; end
        try, pivui.grain4Shell.loadExperiment(fig, i); catch, continue; end
        nm = i_baseName(getfield(guidata(fig),'df'));
        res = i_exportMovieCurExp(fig, sprintf('%d/%d: %s', i, N, nm));
        if ~isempty(res)
            nOk = nOk + numel(res.written);
            if res.cancelled, cancelled = true; break; end
        end
    end
    if row0 >= 1, try, pivui.grain4Shell.loadExperiment(fig, row0); catch, end, end
    if cancelled
        i_status(fig, sprintf('MP4 semua exp DIBATALKAN (%d file).', nOk));
    else
        i_status(fig, sprintf('MP4 semua exp selesai: %d file.', nOk));
        try, msgbox(sprintf('MP4 SEMUA exp selesai (%d file).', nOk), 'GRAIN4Frame — MP4 semua exp'); catch, end
    end
end

function res = i_exportMovieCurExp(fig, tag)
%I_EXPORTMOVIECUREXP  Rakit 2 MP4 (velmag + shear) exp aktif; MENGIKUTI crop/zoom
%   axMain. Return struct(written,movDir,fps,durActual,nF,cancelled); [] bila gagal.
    res = [];
    if nargin < 2, tag = ''; end
    h = guidata(fig);
    if isempty(h.df) || isempty(h.data), i_status(fig,'Belum ada eksperimen dimuat.'); return; end
    tagPfx = ''; if ~isempty(tag), tagPfx = [tag ' — ']; end

    if ~pivcore.util.isFullLoaded(h)
        pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
    end
    nF = max(1, pivcore.util.scalarOr(h.imgFrames, h.nF));
    if isfield(h,'movieMaxFrames') && isscalar(h.movieMaxFrames) && h.movieMaxFrames>0
        nF = min(nF, round(h.movieMaxFrames));
    end

    movDir = i_exportDir(h, 'mp4');
    if ~isfolder(movDir), mkdir(movDir); end

    durSec = i_movieTargetDur(h);
    if isfinite(durSec) && durSec > 0, fps = nF / durSec; else, fps = 5; end
    fps = max(0.1, min(120, fps));
    durActual = nF / fps;

    cropLim = i_axMainCropLim(h);
    longPx  = i_exportLongPx(h);
    axPos   = [0.045 0.070 0.800 0.850];
    [figW, figH] = i_figSizeFromCrop(cropLim, axPos, longPx);
    strainTot = i_strainTotal(h);
    opts = struct('velMult', i_velMult(h), 'axPos', axPos, 'cropLim', cropLim);
    opts.gsCache = containers.Map('KeyType','char','ValueType','any');
    cuGs = onCleanup(@() i_mapClear(opts.gsCache)); %#ok<NASGU>

    frame0 = h.frame;
    wb = i_waitbar(sprintf('%sRakit MP4 (%d frame × 2, %.2g fps ≈ %.1fs)…', tagPfx, nF, fps, durActual));
    cuw = onCleanup(@() i_closeWb(wb)); %#ok<NASGU>

    scalars = pivcore.io.grain4DescExport.scalarNames();
    written = {}; cancelled = false;

    vws = struct('sc',{},'vw',{},'file',{},'size',{});
    for si = 1:numel(scalars)
        sc = scalars{si};
        outFile = fullfile(movDir, pivcore.io.grain4DescExport.movieFile(h.df, sc));
        vw = VideoWriter(outFile, 'MPEG-4'); %#ok<TNMLP>
        vw.FrameRate = fps; vw.Quality = 90;
        try, open(vw);
        catch ME
            i_status(fig, sprintf('%sGAGAL buka VideoWriter: %s', tagPfx, ME.message));
            try, close(vw); catch, end
            for j=1:numel(vws), i_movieCloseVw(vws(j).vw); end
            return;
        end
        vws(end+1) = struct('sc',sc,'vw',vw,'file',outFile,'size',[]); %#ok<AGROW>
    end
    cuVws = onCleanup(@() i_movieCloseAll(vws)); %#ok<NASGU>

    movFig = figure('Visible','off','Color','w','Units','pixels','Position',[100 100 figW figH]);
    try, pivui.forceLightTheme(movFig); catch, end
    set(movFig,'Color','w');
    cuFig = onCleanup(@() i_closeIf(movFig)); %#ok<NASGU>

    nWritten = zeros(1,numel(vws));
    for k = 1:nF
        hc = guidata(fig);
        if isfield(hc,'movieCancel') && hc.movieCancel, cancelled = true; break; end
        pivui.grain4Shell.setFrameQuiet(fig, k);
        for si = 1:numel(vws)
            rgb = i_frameRGB(fig, movFig, vws(si).sc, k, opts, strainTot);
            if isempty(rgb), continue; end
            if isempty(vws(si).size)
                vws(si).size = [size(rgb,1) size(rgb,2)];
            elseif ~isequal([size(rgb,1) size(rgb,2)], vws(si).size)
                rgb = i_movieFitSize(rgb, vws(si).size);
            end
            try, writeVideo(vws(si).vw, rgb); nWritten(si)=nWritten(si)+1; catch, end
        end
        if ~isempty(wb) && ishghandle(wb)
            try, waitbar(k/nF, wb, sprintf('%sMP4 frame %d/%d…', tagPfx, k, nF)); catch, end
        end
        if mod(k,8)==0, drawnow limitrate; end
    end

    for si = 1:numel(vws)
        i_movieCloseVw(vws(si).vw);
        if ~cancelled && nWritten(si)>0, written{end+1} = vws(si).file; end %#ok<AGROW>
    end
    if cancelled
        for si = 1:numel(vws)
            try, if isfile(vws(si).file), delete(vws(si).file); end, catch, end
        end
    end
    try, pivui.grain4Shell.gotoFrame(fig, frame0); catch, end
    if cancelled
        try, if isfolder(movDir) && numel(dir(movDir))<=2, rmdir(movDir,'s'); end, catch, end
    end
    res = struct('written',{written}, 'movDir',movDir, 'fps',fps, ...
        'durActual',durActual, 'nF',nF, 'cancelled',cancelled);
end

function i_onMovieCancel(fig)
    h = guidata(fig); h.movieCancel = true; guidata(fig, h);
    i_status(fig,'Membatalkan MP4…'); drawnow;
end

function i_movieBtnState(fig, running)
    h = guidata(fig);
    for nm = {'btnMovie','btnMovieAll'}
        if isfield(h,nm{1}) && ishghandle(h.(nm{1}))
            set(h.(nm{1}),'Visible', i_tern(running,'off','on'));
        end
    end
    if isfield(h,'btnMovieCancel') && ishghandle(h.btnMovieCancel)
        set(h.btnMovieCancel,'Visible', i_tern(running,'on','off'));
    end
    if ~running, h.movieCancel = false; guidata(fig, h); end
    drawnow limitrate;
end

function i_movieCloseAll(vws)
    for i = 1:numel(vws), try, i_movieCloseVw(vws(i).vw); catch, end, end
end
function i_movieCloseVw(vw)
    try, if ~isempty(vw), close(vw); end, catch, end
end
function rgb = i_movieFitSize(rgb, target)
    H = target(1); W = target(2);
    h0 = size(rgb,1); w0 = size(rgb,2);
    if h0 >= H, rgb = rgb(1:H,:,:); else, rgb(h0+1:H,:,:) = 255; end
    if w0 >= W, rgb = rgb(:,1:W,:); else, rgb(:,w0+1:W,:) = 255; end
end
function d = i_movieTargetDur(h)
    d = NaN;
    if isfield(h,'movieTargetDur') && isscalar(h.movieTargetDur) && isnumeric(h.movieTargetDur)
        d = double(h.movieTargetDur); return;
    end
    if isfield(h,'edMovieDur') && ishghandle(h.edMovieDur)
        s = strrep(strtrim(char(get(h.edMovieDur,'String'))), ',', '.');
        v = str2double(s);
        if isscalar(v) && isfinite(v) && v > 0, d = v; end
    end
end


% =====================================================================
% RENDERER inti (zoom-aware) — reuse pivcore.montage.renderScalarPanel
% =====================================================================
function rgb = i_frameRGB(fig, movFig, scalar, k, opts, strainTot) %#ok<INUSD>
%I_FRAMERGB  Render axMain frame k (velmag/shear) ke figure off-screen REUSE ->
%   getframe RGB. MENGIKUTI crop axMain (opts.cropLim = [x1 x2 y1 y2]) + setelan
%   tampilan LIVE (CLim/GS/glyph/CLAHE). Aspek figure = crop -> tanpa letterbox.
    rgb = [];
    h = guidata(fig);
    if isempty(h.data), return; end
    scKey = 'velocity_magnitude'; if strcmp(scalar,'shear'), scKey = 'shear'; end
    kk = max(1, min(round(k), pivcore.util.scalarOr(h.imgFrames,1)));
    velMult = 0.005;
    if isstruct(opts) && isfield(opts,'velMult') && isscalar(opts.velMult) && opts.velMult>0
        velMult = opts.velMult;
    end
    if isempty(movFig) || ~ishghandle(movFig), return; end
    clf(movFig);

    haveAxPos = isstruct(opts) && isfield(opts,'axPos') && numel(opts.axPos)==4;
    if haveAxPos
        ax = axes('Parent',movFig,'Position',opts.axPos(:)');
    else
        ax = axes('Parent',movFig);
    end
    cfg = h; cfg.scalarSrc = scKey;
    cfg.glyphOn = logical(h.glyphOn);   % HORMATI checkbox glyph (kolom tengah)
    if isstruct(opts) && isfield(opts,'gsCache') && isa(opts.gsCache,'containers.Map')
        cfg.gsCache = opts.gsCache;
    end
    isShear = strcmp(scalar,'shear');
    try
        pivcore.montage.renderScalarPanel(ax, h.data, kk, scKey, cfg);
    catch
        return;
    end
    % CROP: ikuti tampilan axMain (XLim/YLim aktif) SETELAH renderScalarPanel
    % (yang menyetel ke ekstent penuh). daspect 1:1 dipertahankan.
    if isstruct(opts) && isfield(opts,'cropLim') && numel(opts.cropLim)==4
        L = opts.cropLim;
        try, set(ax,'XLim',L(1:2),'YLim',L(3:4)); catch, end
    end
    set(ax, 'Color','w', 'XColor',[0 0 0], 'YColor',[0 0 0], 'XTick',[], 'YTick',[]);
    cb = colorbar(ax);
    if isShear
        cb.Label.String = 'shear strain (du/dy+dv/dx)';
    else
        cb.Label.String = '|V| (cm/s)';
        cl = clim(ax); t = get(cb,'Ticks');
        if isempty(t), t = linspace(cl(1), cl(2), 6); set(cb,'Ticks',t); end
        set(cb,'TickLabels', arrayfun(@(v) sprintf('%.3g', v*velMult), t, 'UniformOutput', false));
    end
    set(cb,'Color',[0 0 0]); cb.Label.Color = [0 0 0];
    if haveAxPos
        set(ax, 'Position', opts.axPos(:)');
        p = opts.axPos(:)';
        set(cb, 'Position', [min(0.965, p(1)+p(3)+0.012), p(2), 0.022, p(4)]);
    end
    % Garis PSG (bila ada) — sama seperti GRAIN4.
    hold(ax,'on');
    if ~isempty(h.line) && isfield(h.line,'p1')
        plot(ax, [h.line.p1(1) h.line.p2(1)], [h.line.p1(2) h.line.p2(2)], ...
            '-', 'Color',[1 0.6 0.1], 'LineWidth',0.8);
    end
    hold(ax,'off');
    if isShear, scName = 'Shear Strain'; else, scName = 'Velocity Magnitude'; end
    title(ax, sprintf('%s — %s', scName, i_baseName(h.df)), 'Interpreter','none', 'Color',[0 0 0]);
    try
        nFimg = max(1, pivcore.util.scalarOr(h.imgFrames, h.nF));
        pivui.grain4Shell.drawStrainState(fig, ax, kk, nFimg);
    catch, end
    try, fr = getframe(movFig); rgb = fr.cdata; catch, rgb = []; end
end


% =====================================================================
% Helper geometri crop + ukuran figure
% =====================================================================
function L = i_axMainCropLim(h)
%I_AXMAINCROPLIM  [x1 x2 y1 y2] tampilan axMain aktif (crop/zoom). Bila axMain
%   tak valid -> ekstent penuh grid data.
    L = [];
    if isfield(h,'axMain') && ishghandle(h.axMain)
        try
            xl = get(h.axMain,'XLim'); yl = get(h.axMain,'YLim');
            if numel(xl)==2 && numel(yl)==2 && diff(xl)>0 && diff(yl)>0
                L = [xl(1) xl(2) yl(1) yl(2)];
            end
        catch, end
    end
    if isempty(L)
        try
            xg = pivcore.data.safeFrame(h.data.x, 1);
            yg = pivcore.data.safeFrame(h.data.y, 1);
            L = [min(xg(:)) max(xg(:)) min(yg(:)) max(yg(:))];
        catch
            L = [0 1 0 1];
        end
    end
end

function [figW, figH] = i_figSizeFromCrop(cropLim, axPos, longPx)
%I_FIGSIZEFROMCROP  Ukuran figure (px) supaya kotak-plot (rect axPos) ber-aspek
%   SAMA dgn crop axMain; sisi-panjang kotak-plot = longPx. Dgn daspect 1:1,
%   kotak-plot terisi PENUH -> ekspor = crop, tanpa letterbox.
    figW = 1120; figH = 560;
    try
        cw = cropLim(2) - cropLim(1);
        ch = cropLim(4) - cropLim(3);
        if ~(cw>0 && ch>0), return; end
        if nargin < 3 || ~(isscalar(longPx) && longPx>0), longPx = 1600; end
        s = longPx / max(cw, ch);
        plotW = cw * s; plotH = ch * s;
        aw = axPos(3); ah = axPos(4);
        figW = max(300, min(4000, round(plotW / aw)));
        figH = max(200, min(4000, round(plotH / ah)));
    catch
        figW = 1120; figH = 560;
    end
end

function px = i_exportLongPx(h)
    px = 1600;
    if isfield(h,'exportLongPx') && isscalar(h.exportLongPx) && h.exportLongPx>0
        px = round(h.exportLongPx);
    elseif isfield(h,'edExportPx') && ishghandle(h.edExportPx)
        v = str2double(strtrim(char(get(h.edExportPx,'String'))));
        if isscalar(v) && isfinite(v) && v>0, px = round(v); end
    end
    px = max(300, min(4000, px));
end

function d = i_exportDir(h, kind)
%I_EXPORTDIR  Folder ber-versi GRAIN/GRAIN4Frame_export/<exp>/<ts>_<psg>_<kind>/.
    grainRoot = fileparts(mfilename('fullpath'));
    if isfield(h,'exportRootOverride') && ischar(h.exportRootOverride) && ~isempty(h.exportRootOverride)
        grainRoot = h.exportRootOverride;
        if ~isfolder(grainRoot), try, mkdir(grainRoot); catch, end, end
    end
    ts = pivcore.io.grain4DescExport.stamp();
    if isfield(h,'exportStampOverride') && ~isempty(h.exportStampOverride), ts = h.exportStampOverride; end
    psg = h.activePsgId; if isempty(psg), psg = 'PSG'; end
    psg = pivcore.io.grain4DescExport.safeName(psg);
    ts  = pivcore.io.grain4DescExport.safeName(ts);
    d = fullfile(grainRoot, 'GRAIN4Frame_export', i_baseName(h.df), sprintf('%s_%s_%s', ts, psg, kind));
end


% =====================================================================
% Navigasi + util
% =====================================================================
function i_onStepExp(fig, dir)
    h = guidata(fig);
    if ~isfield(h,'list') || isempty(h.list), return; end
    N = numel(h.list);
    row = h.activeRow; if row < 1, row = 1; end
    row = max(1, min(N, row + dir));
    try, pivui.grain4Shell.loadExperiment(fig, row); catch, end
end

function i_onClose(fig)
    try, delete(fig); catch, end
end

function nF = i_ensureFullFrames(fig)
    h = guidata(fig);
    nTot = max(1, round(pivcore.util.scalarOr(h.nF, 1)));
    if pivcore.data.frameCount(h.data) < nTot
        h.fullLoaded = false; guidata(fig, h);
        pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
    end
    nF = max(1, pivcore.data.frameCount(h.data));
end

function frames = i_parseFrameRange(txt, curFrame, nF)
%I_PARSEFRAMERANGE  "N" | "A-B" | "A:B" -> vektor indeks terurut, clamp [1..nF].
%   Kosong -> [curFrame].
    frames = [];
    txt = strtrim(char(txt));
    if isempty(txt)
        frames = min(max(1, round(curFrame)), max(1,nF)); return;
    end
    txt = strrep(txt, ':', '-');
    parts = strtrim(strsplit(txt, '-'));
    if isempty(parts) || numel(parts) > 2, return; end
    nums = str2double(parts);
    if any(isnan(nums)), return; end
    a = nums(1);
    if numel(nums) >= 2, b = nums(2); else, b = a; end
    if ~isfinite(a) || ~isfinite(b), return; end
    a = round(a); b = round(b);
    if a > b, t = a; a = b; b = t; end
    a = max(1, a); b = min(nF, b);
    if a > b, return; end
    frames = a:b;
end

function v = i_velMult(h)
    v = 0.005;
    if isfield(h,'descVelMult') && isscalar(h.descVelMult) && h.descVelMult>0, v = h.descVelMult; end
end

function pct = i_strainTotal(h)
    pct = NaN;
    try
        if isfield(h,'strainTotal') && isscalar(h.strainTotal) && isfinite(h.strainTotal)
            pct = h.strainTotal; return;
        end
        if isfield(h,'df') && ~isempty(h.df) && isfile(h.df)
            g = pivcore.export.frameCatalog.readGeom(h.df);
            if isscalar(g) && isfinite(g), pct = double(g); end
        end
    catch, end
end

function s = i_baseName(df)
    [~, s] = fileparts(char(df));
end

function v = i_readNum(hEdit, dflt)
    v = dflt;
    if ishghandle(hEdit)
        x = str2double(strrep(strtrim(char(get(hEdit,'String'))), ',', '.'));
        if isscalar(x) && isfinite(x), v = x; end
    end
end

function out = i_tern(c, a, b)
    if c, out = a; else, out = b; end
end

function i_status(fig, msg)
    if ~ishghandle(fig), return; end
    h = guidata(fig);
    if isfield(h,'txtFrameStatus') && ishghandle(h.txtFrameStatus)
        try, set(h.txtFrameStatus,'String',msg); catch, end
    end
    try, pivui.setStatus(fig, msg); catch, end
end

function wb = i_waitbar(msg)
    wb = [];
    if pivui.quiet(), return; end
    try, wb = waitbar(0, msg, 'Name','GRAIN4Frame'); catch, wb = []; end
end
function i_closeWb(wb)
    try, if ~isempty(wb) && ishghandle(wb), close(wb); end, catch, end
end
function i_closeIf(x)
    try, if ~isempty(x) && ishghandle(x), delete(x); end, catch, end
end
function i_mapClear(m)
    try, if isa(m,'containers.Map'), remove(m, keys(m)); end, catch, end
end
