function GRAINMASK(rootDir)
%GRAINMASK  Editor masking persegi NON-DESTRUKTIF pada MAT PREP (output Step 1).
%
%   GRAINMASK                 % dialog pilih folder berisi .mat PREP
%   GRAINMASK(rootDir)        % langsung ke folder ROOT (scan otomatis)
%
%   TUJUAN. Setelah GRAIN0→GRAIN1 (stabilisasi, jitter < 1 px), masih ada gangguan
%   ESTETIKA pada hasil PIV: area belakang dinding pendorong & area bukan-pasir
%   memunculkan vektor yang mengotori analisis. Modul ini menutupinya dengan
%   KOTAK PUTIH borderless yang ukurannya DIINTERPOLASI per-frame antara kondisi
%   AWAL & AKHIR (air/pasir masuk → area berubah mulus).
%
%   NON-DESTRUKTIF. Yang disimpan hanyalah RESEP (koordinat kotak awal+akhir) di
%   field `prep.masking` MAT PREP — blob JPEG asli TAK disentuh. Kotak putih
%   ditempel saat DECODE (unpackMat / readMatFrame) ke citra yang dimakan PIV,
%   jadi GRAIN2 tetap menerima JPEG ter-masking, sambil frame asli bisa dipulihkan
%   & kotak diedit ulang kapan saja. GS regen dari RAW ter-masking → ikut bersih.
%
%   Persegi = STRETCH sisi/sudut (ubah panjang & tinggi), BUKAN polygon. v1 =
%   SATU kotak (skema `boxes` array sudah siap diperluas ke banyak kotak nanti).
%
%   TATA LETAK (2 kolom):
%     KIRI  (sempit) : tabel eksperimen (MAT PREP) + tindakan
%                      [💾 Simpan masking] [🧹 Hapus masking] [✕ Tutup]
%     KANAN (lebar)  : viewer frame AWAL/AKHIR (BERSIH) + tarik kotak + slider
%                      pratinjau interpolasi tiap frame.
%
%   Tema TERANG dipaksa (idiom MATPIVEDIT/GRAINEXPORT: figure+uicontrol klasik;
%   headless-safe). Simpan = tulis resep ke berkas SIDECAR '<nama>_mask.json'
%   (kecil, JSON) di samping MAT PREP — INSTAN, MAT PREP (blob RAW, bisa 1,4 GB)
%   TAK PERNAH ditulis ulang. Tanpa backup .bak (mubazir: non-destruktif). GRAIN2
%   & decoder mendeteksi sidecar otomatis. Satu sidecar dipakai bersama GRAINMASK2
%   (polygon+keyframe) nanti. Engine: pivanalyzemat.core.maskSidecar.
%   Lihat memori [[grainsa-pipeline-architecture]], [[matpivedit-geom-editor]];
%   engine pivanalyzemat.core.maskRect.

    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivanalyzemat.core.readMatFrame')) ...
            || isempty(which('pivanalyzemat.core.maskRect'))
        try, grain_setup(); catch, addpath(here); end %#ok<CTCH>
    end
    if isempty(which('pivui.forceLightTheme'))
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
    end

    if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
        rootDir = uigetdir(pwd, ...
            'Pilih folder: JPG mentah (urutan baru) atau .mat PREP (lama)');
        if isequal(rootDir, 0), return; end
    end

    h = struct();
    h.root   = rootDir;
    h.busy   = false;
    % MODE SUMBER: 'jpg' = folder foto mentah (urutan baru GRAIN0->GRAINMASK->GRAIN1),
    %              'mat' = folder .mat PREP (alur lama GRAIN1->GRAINMASK->GRAIN2).
    % Auto-deteksi saat scan (i_detectMode); default 'jpg' bila ambigu.
    h.srcMode = 'jpg';
    % Daftar eksperimen. Resep masking hidup di field. path/files diisi mode 'jpg'
    % (folder + daftar JPG lolos QPIV); mode 'mat' pakai file (path .mat).
    h.list   = struct('name',{},'file',{},'nFrames',{}, ...
                      'path',{},'files',{}, ...
                      'enabled',{},'rectFirst',{},'rectLast',{}, ...
                      'keyframes',{},'fill',{},'orig',{},'dirty',{});
    h.activeRow = 0;
    % Cache frame exp aktif (BERSIH, tanpa masking — editor menggambar di atas ini).
    h.imgFirst = []; h.imgLast = []; h.imSz = [];
    h.viewMode = 'first';          % 'first'|'last' (edit kotak) | 'preview' (lihat frame tengah)
    h.imh = [];
    h.roi  = [];                   % images.roi.Rectangle aktif (frame awal/akhir)
    h.editTarget = 'first';        % kotak mana yang sedang diedit: 'first'|'last'
    h.previewFrame = 1;            % frame untuk pratinjau interpolasi
    h.imgPrev = []; h.prevLoaded = 0;   % cache frame pratinjau on-demand (BERSIH) + indeksnya
    h.ovl = [];                    % patch overlay pratinjau interpolasi
    h.wb  = [];                    % handle waitbar progress verbose (bersama)

    h = i_buildUI(h);
    guidata(h.fig, h);
    i_scan(h.fig);
end

% =====================================================================
%  UI (tema TERANG) — 2 kolom: KIRI tabel+aksi (sempit), KANAN viewer
% =====================================================================
function h = i_buildUI(h)
    WHITE = [1 1 1];
    vis = 'on'; try, if pivui.quiet(), vis = 'off'; end; catch, end %#ok<CTCH>
    h.fig = figure('Name',pivui.titleWithVersion('GRAIN Masking — kotak putih non-destruktif (MAT PREP)'), ...
        'NumberTitle','off','Color',WHITE, ...
        'Units','pixels','Position',[60 60 1280 760], ...
        'MenuBar','none','ToolBar','figure','Visible',vis, ...
        'CloseRequestFcn',@(s,e) i_onClose(s));
    try, pivui.forceLightTheme(h.fig); catch, end %#ok<CTCH>
    fig = h.fig;

    % ================= KIRI: tabel eksperimen + tindakan =================
    pnlL = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.006 0.01 0.278 0.985],'Title','Eksperimen (.mat PREP)', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);

    h.txtRoot = uicontrol('Parent',pnlL,'Style','text', ...
        'Units','normalized','Position',[0.03 0.955 0.94 0.035], ...
        'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'String',h.root);
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.905 0.46 0.045],'String','📂 Ganti folder…', ...
        'Callback',@(s,e) i_onChangeRoot(fig));
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.905 0.46 0.045],'String','🔄 Pindai ulang', ...
        'TooltipString','Pindai folder + baca resep masking tiap MAT PREP.', ...
        'Callback',@(s,e) i_scan(fig));

    h.tbl = uitable('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.545 0.94 0.350], ...
        'ColumnName',{'Eksperimen','#frame','Masking','Simpan'}, ...
        'ColumnWidth',{140 50 60 56}, ...
        'ColumnFormat',{'char','char','char','char'}, ...
        'ColumnEditable',[false false false false], ...
        'RowName',[],'FontSize',8,'Multiselect','off', ...
        'CellSelectionCallback',@(s,e) i_onSelect(fig, e));
    uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
        'Position',[0.03 0.522 0.94 0.020],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'FontSize',7,'ForegroundColor',[0.4 0.4 0.4], ...
        'String','Simpan: BIRU=tersimpan · MERAH=belum. Klik baris→muat frame.');

    % --- panel Navigasi antar-exp + SALIN kotak ---
    %   Alur khas: kerjakan exp #1, lalu #2..#N pakai masking yang sama →
    %   "Salin ke SEMUA" sekali, tinggal edit per-exp bila perlu.
    pNav = uipanel('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.362 0.94 0.150],'Title','Navigasi & salin kotak', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    uicontrol('Parent',pNav,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.67 0.46 0.29],'String','◀ Exp sebelumnya', ...
        'BackgroundColor',[0.92 0.94 0.99], ...
        'TooltipString','Pindah ke eksperimen di baris atas (muat frame awal/akhir).', ...
        'Callback',@(s,e) i_onPrevExp(fig));
    uicontrol('Parent',pNav,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.67 0.46 0.29],'String','Exp berikutnya ▶', ...
        'BackgroundColor',[0.92 0.94 0.99], ...
        'TooltipString','Pindah ke eksperimen di baris bawah TANPA menyimpan (muat frame awal/akhir).', ...
        'Callback',@(s,e) i_onNextExp(fig));
    % Tombol "Exp berikutnya" di-SPLIT: satu polos (atas) + satu simpan-lalu-maju.
    uicontrol('Parent',pNav,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.36 0.94 0.29],'String','💾 Simpan + Exp berikutnya ▶', ...
        'FontWeight','bold','BackgroundColor',[0.80 0.92 0.82], ...
        'TooltipString','Simpan masking exp ini (sidecar/progres) LALU pindah ke exp berikutnya. Sapu cepat.', ...
        'Callback',@(s,e) i_onSaveNextExp(fig));
    uicontrol('Parent',pNav,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.04 0.46 0.29],'String','📥 Salin dari sebelumnya', ...
        'BackgroundColor',[0.90 0.96 0.90], ...
        'TooltipString','Salin kotak AWAL+AKHIR+keyframe (+isi/aktif) dari eksperimen baris atas ke exp ini.', ...
        'Callback',@(s,e) i_onCopyFromPrev(fig));
    uicontrol('Parent',pNav,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.04 0.46 0.29],'String','📤 Salin ke SEMUA', ...
        'FontWeight','bold','BackgroundColor',[0.86 0.94 0.86], ...
        'TooltipString','Salin kotak AWAL+AKHIR+keyframe (+isi/aktif) exp ini ke SEMUA eksperimen lain (belum disimpan).', ...
        'Callback',@(s,e) i_onCopyToAll(fig));

    % --- panel Progress (state kerja per-ROOT) ---
    %   <ROOT>/PABMASK_progress.mat menyimpan resep masking SELURUH exp (termasuk
    %   yang belum di-Simpan ke .mat) + tanda dirty → lanjut kerja lintas sesi.
    %   Auto-load saat scan. Beda dari resep FINAL di prep.masking tiap .mat.
    pPrg = uipanel('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.272 0.94 0.085],'Title','Progress (per-folder)', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    uicontrol('Parent',pPrg,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.12 0.46 0.74],'String','💾 Simpan Progress', ...
        'BackgroundColor',[0.86 0.92 0.98], ...
        'TooltipString','Timpa <ROOT>/PABMASK_progress.mat (resep semua exp). Tanpa dialog.', ...
        'Callback',@(s,e) i_onSaveProgress(fig));
    uicontrol('Parent',pPrg,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.12 0.46 0.74],'String','📂 Muat Progress', ...
        'BackgroundColor',[0.90 0.94 0.99], ...
        'TooltipString','Muat <ROOT>/PABMASK_progress.mat (atau pilih berkas) — lanjut kerja.', ...
        'Callback',@(s,e) i_onLoadProgress(fig, true));

    % --- panel tindakan ---
    %   4 baris: (1) Simpan masking / Simpan SEMUA, (2) Hapus / Tutup,
    %   (3) Transfer -> GRAIN2 (Step 2) = pola Simpan-Tutup-Lanjut alur kanonik
    %       GRAIN0 -> GRAIN1 -> GRAINMASK -> GRAIN2, (4) Transfer -> GRAINMASK2 (placeholder,
    %       project masa depan: masking POLYGON berubah bentuk per-frame + keyframe).
    %   Backup (.bak) DIHAPUS: sistem NON-DESTRUKTIF (resep di sidecar JSON,
    %   MAT PREP tak diubah) -> salinan .bak mubazir.
    pAct = uipanel('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.075 0.94 0.195],'Title','Tindakan', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    h.btnSave = uicontrol('Parent',pAct,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.80 0.46 0.17],'String','💾 Simpan masking', ...
        'FontWeight','bold','BackgroundColor',[0.83 0.94 0.83], ...
        'TooltipString','Tulis resep masking exp ini ke sidecar — instan, MAT PREP tak disentuh.', ...
        'Callback',@(s,e) i_onSaveActive(fig));
    h.btnSaveAll = uicontrol('Parent',pAct,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.80 0.46 0.17],'String','💾 Simpan SEMUA', ...
        'FontWeight','bold','BackgroundColor',[0.74 0.90 0.78], ...
        'TooltipString','Tulis resep masking SEMUA exp yang punya kotak ke sidecar masing-masing.', ...
        'Callback',@(s,e) i_onSaveAll(fig));
    h.btnClear = uicontrol('Parent',pAct,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.61 0.46 0.17],'String','🧹 Hapus masking', ...
        'BackgroundColor',[0.96 0.92 0.86], ...
        'TooltipString','Nonaktifkan masking exp ini (frame kembali utuh).', ...
        'Callback',@(s,e) i_onClearMask(fig));
    uicontrol('Parent',pAct,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.61 0.46 0.17],'String','✕ Tutup', ...
        'BackgroundColor',[0.97 0.86 0.86], ...
        'Callback',@(s,e) i_onClose(fig));
    h.btnToStep2 = uicontrol('Parent',pAct,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.32 0.94 0.20],'String','Transfer → GRAIN2 (Step 2) ▶', ...
        'FontWeight','bold','BackgroundColor',[0.90 0.94 0.99], ...
        'TooltipString',['Simpan progress masking, tutup GRAINMASK, lalu buka Step 2 (GRAIN2) ', ...
                         'menunjuk folder MAT PREP ini. Alur: GRAIN1 -> GRAINMASK -> GRAIN2.'], ...
        'Callback',@(s,e) i_onTransferToStep2(fig));
    % GRAINMASK2 = project masa depan (belum dibuat): masking area dgn POLYGON yang
    % BERUBAH BENTUK setiap saat + indikator KEYFRAME. Tombol placeholder: buka
    % dialog "belum tersedia" bila fungsi GRAINMASK2 tak ada di path.
    h.btnToMask2 = uicontrol('Parent',pAct,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.04 0.94 0.20],'String','Transfer → GRAINMASK2 (polygon + keyframe) ▶', ...
        'FontWeight','bold','BackgroundColor',[0.93 0.90 0.98], ...
        'TooltipString',['(Segera) Masking area dgn POLYGON berubah bentuk per-frame ', ...
                         '+ indikator keyframe. GRAINMASK2 belum tersedia.'], ...
        'Callback',@(s,e) i_onTransferToMask2(fig));

    h.status = uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
        'Position',[0.03 0.015 0.94 0.05],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2],'String','Siap.');

    % ================= KANAN: viewer frame + kotak masking =================
    pnlR = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.29 0.01 0.705 0.985],'BackgroundColor',WHITE, ...
        'BorderType','none');

    h.txtExp = uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.01 0.955 0.98 0.04],'HorizontalAlignment','left', ...
        'FontWeight','bold','FontSize',13,'BackgroundColor',WHITE, ...
        'ForegroundColor',[0 0 0],'String','(pilih eksperimen di kiri)');

    % kanvas frame
    pnlAx = uipanel('Parent',pnlR,'Units','normalized', ...
        'Position',[0.01 0.345 0.98 0.60],'BackgroundColor',WHITE, ...
        'BorderType','line','HighlightColor',[0.8 0.8 0.8]);
    h.ax = axes('Parent',pnlAx,'Units','normalized','Position',[0.04 0.06 0.92 0.90]);
    set(h.ax,'XTick',[],'YTick',[],'Box','on','Color',[0.96 0.96 0.96]);

    % --- baris 1: pilih frame acuan AWAL/AKHIR + tarik kotak ---
    h.btnFirst = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.01 0.298 0.155 0.040],'String','◀ Kotak AWAL', ...
        'FontWeight','bold','BackgroundColor',[0.85 0.90 0.98], ...
        'TooltipString','Tampilkan frame AWAL & edit kotak kondisi awal.', ...
        'Callback',@(s,e) i_setEditTarget(fig,'first'));
    h.btnLast = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.17 0.298 0.155 0.040],'String','Kotak AKHIR ▶', ...
        'BackgroundColor',[0.95 0.95 0.95], ...
        'TooltipString','Tampilkan frame AKHIR & edit kotak kondisi akhir.', ...
        'Callback',@(s,e) i_setEditTarget(fig,'last'));
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.335 0.298 0.15 0.040],'String','▭ Tarik kotak', ...
        'BackgroundColor',[0.86 0.93 0.86], ...
        'TooltipString','Tarik kotak persegi (stretch sisi/sudut) di frame yang tampil.', ...
        'Callback',@(s,e) i_onDrawRect(fig));
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.49 0.298 0.135 0.040],'String','📋 Salin awal→akhir', ...
        'TooltipString','Pakai kotak frame awal sebagai kotak frame akhir (kotak statis).', ...
        'Callback',@(s,e) i_onCopyFirstToLast(fig));
    h.txtRect = uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.63 0.298 0.36 0.036],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2],'String','');

    % --- baris 2: pratinjau interpolasi (slider frame) ---
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.01 0.250 0.14 0.034],'HorizontalAlignment','left', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0], ...
        'String','Pratinjau frame:');
    h.sld = uicontrol('Parent',pnlR,'Style','slider','Units','normalized', ...
        'Position',[0.15 0.252 0.40 0.030],'Min',1,'Max',2,'Value',1, ...
        'SliderStep',[1 10]/1, ...
        'Callback',@(s,e) i_onSlider(fig));
    h.txtPrev = uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.555 0.250 0.115 0.034],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2],'String','');
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.675 0.250 0.165 0.040],'String','🖼 Tampilkan frame ini', ...
        'BackgroundColor',[0.86 0.90 0.98], ...
        'TooltipString',['Muat frame nyata (sesuai slider) ke kanvas — on-demand, ' ...
        '1 frame saja, BUKAN dump seluruh MAT PREP. Kotak interpolasi digambar pas.'], ...
        'Callback',@(s,e) i_onShowFrame(fig));
    uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.845 0.250 0.145 0.040],'String','↩ Kembali awal/akhir', ...
        'TooltipString','Kembali ke tampilan frame awal/akhir untuk mengedit kotak.', ...
        'Callback',@(s,e) i_setEditTarget(fig, []));

    % panel info / catatan + KEYFRAME
    pInfo = uipanel('Parent',pnlR,'Units','normalized', ...
        'Position',[0.01 0.01 0.98 0.225], ...
        'Title','Masking kotak putih — interpolasi + keyframe tengah', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    % --- KIRI: aktifkan + catatan singkat ---
    h.chkEnable = uicontrol('Parent',pInfo,'Style','checkbox','Units','normalized', ...
        'Position',[0.02 0.83 0.46 0.14],'String','Aktifkan masking exp ini', ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'Value',0, ...
        'Callback',@(s,e) i_onToggleEnable(fig));
    h.txtInfo = uicontrol('Parent',pInfo,'Style','text','Units','normalized', ...
        'Position',[0.02 0.04 0.46 0.75],'HorizontalAlignment','left', ...
        'FontSize',9,'BackgroundColor',WHITE,'ForegroundColor',[0 0 0], ...
        'String',['Tarik kotak AWAL lalu AKHIR. Bila kotak tak menyusut lurus ' ...
        '(distorsi), tampilkan frame tengah → Tarik kotak koreksi → ＋Set KF: ' ...
        'interpolasi jadi patah mengikuti keyframe. Non-destruktif.']);
    % --- KANAN: tabel keyframe + tombol ---
    uicontrol('Parent',pInfo,'Style','text','Units','normalized', ...
        'Position',[0.50 0.86 0.48 0.12],'HorizontalAlignment','left', ...
        'FontWeight','bold','FontSize',9,'BackgroundColor',WHITE, ...
        'ForegroundColor',[0 0 0],'String','Keyframe (node ukuran kotak)');
    h.kfTbl = uitable('Parent',pInfo,'Units','normalized', ...
        'Position',[0.50 0.42 0.48 0.44], ...
        'ColumnName',{'Frame','Titik','Kotak wxh'}, ...
        'ColumnWidth',{50 56 74}, ...
        'ColumnEditable',[false false false], ...
        'RowName',[],'FontSize',8,'Multiselect','off', ...
        'CellSelectionCallback',@(s,e) i_onKfSelect(fig, e));
    h.btnPrevKf = uicontrol('Parent',pInfo,'Style','pushbutton','Units','normalized', ...
        'Position',[0.50 0.22 0.235 0.17],'String','◀ KF', ...
        'BackgroundColor',[0.90 0.94 0.99], ...
        'TooltipString','Loncat ke keyframe sebelum frame ini (tanpa scan frame-by-frame).', ...
        'Callback',@(s,e) i_onPrevKeyframe(fig));
    h.btnNextKf = uicontrol('Parent',pInfo,'Style','pushbutton','Units','normalized', ...
        'Position',[0.745 0.22 0.235 0.17],'String','KF ▶', ...
        'BackgroundColor',[0.90 0.94 0.99], ...
        'TooltipString','Loncat ke keyframe setelah frame ini (tanpa scan frame-by-frame).', ...
        'Callback',@(s,e) i_onNextKeyframe(fig));
    h.btnSetKf = uicontrol('Parent',pInfo,'Style','pushbutton','Units','normalized', ...
        'Position',[0.50 0.03 0.235 0.17],'String','＋ Set KF', ...
        'FontWeight','bold','BackgroundColor',[0.83 0.94 0.83], ...
        'TooltipString',['Jadikan kotak pada frame yang tampil sebagai keyframe. ' ...
                         'Frame 1=AWAL, frame N=AKHIR, selainnya=keyframe tengah.'], ...
        'Callback',@(s,e) i_onSetKeyframe(fig));
    h.btnDelKf = uicontrol('Parent',pInfo,'Style','pushbutton','Units','normalized', ...
        'Position',[0.745 0.03 0.235 0.17],'String','－ Hapus KF', ...
        'BackgroundColor',[0.96 0.90 0.86], ...
        'TooltipString','Hapus keyframe TENGAH pada frame ini (endpoint AWAL/AKHIR tak bisa dihapus).', ...
        'Callback',@(s,e) i_onDelKeyframe(fig));
end

% =====================================================================
%  Pindai folder -> daftar MAT PREP (pivprep_single_v1)
% =====================================================================
function i_scan(fig)
    h = guidata(fig);
    set(h.txtRoot, 'String', h.root);
    % AUTO-DETEKSI mode sumber: .mat PREP (lama) vs folder JPG mentah (baru).
    h.srcMode = i_detectMode(h.root);
    guidata(fig, h);
    if strcmp(h.srcMode, 'jpg')
        i_scanJpg(fig);
    else
        i_scanMat(fig);
    end
end

function mode = i_detectMode(root)
%I_DETECTMODE  'mat' bila folder berisi MAT PREP (pivprep_single_v1); selain itu
%   'jpg' (folder foto mentah + progres QPIV). Deteksi ringan (tanpa muat blob).
    mode = 'jpg';
    try
        exps = pivanalyzemat.core.scanMats(root);
        if ~isempty(exps); mode = 'mat'; end
    catch
        mode = 'jpg';
    end
end

function i_scanMat(fig)
%I_SCANMAT  Pindai folder MAT PREP (mode LAMA, tak berubah perilaku).
    h = guidata(fig);
    i_progOpen(fig, 'GRAINMASK — memindai folder', ...
        sprintf('Memindai folder MAT PREP…\n%s', i_short(h.root)));
    exps = struct([]);
    try
        exps = pivanalyzemat.core.scanMats(h.root);
    catch
        exps = struct([]);
    end

    L = i_emptyList();
    nExp = numel(exps);
    for i = 1:nExp
        f = exps(i).matfile;
        base = exps(i).name;
        nF = i_field(exps(i), 'count', 0);
        i_progStep(fig, i/max(1,nExp), ...
            sprintf('Baca resep masking %d/%d:\n%s', i, nExp, base));
        [en, rf, rl, fl, kf] = i_readMasking(f);
        L(end+1) = i_mkRow(base, f, '', {}, nF, en, rf, rl, fl, kf); %#ok<AGROW>
    end
    i_progClose(fig);
    i_finishScan(fig, L, sprintf('%d MAT PREP ditemukan. Pilih satu untuk diberi masking.', numel(L)), ...
        'Tidak ada MAT PREP ditemukan di folder ini.');
end

function i_scanJpg(fig)
%I_SCANJPG  Pindai folder FOTO MENTAH -> daftar eksperimen JPG lolos QPIV.
%   URUTAN BARU (GRAIN0->GRAINMASK->GRAIN1): masking digambar di frame MENTAH sebelum
%   jitter/MAT PREP. Hanya frame LOLOS QPIV (frame mati dibuang, konsisten output).
%   Resep dibaca dari progres terpadu (PIVlab_automasi_progress: getmask).
    h = guidata(fig);
    i_progOpen(fig, 'GRAINMASK — memindai foto mentah', ...
        sprintf('Memindai subfolder foto…\n%s', i_short(h.root)));
    % Arahkan engine progres ke <root>/PAB0_progress.mat (acuan QPIV+masking).
    pf = fullfile(h.root, 'PAB0_progress.mat');
    try, if isfile(pf); PIVlab_automasi_progress('setfile', pf); end; catch, end %#ok<CTCH>
    found = struct('path',{},'files',{},'nImg',{});
    try
        found = batchpivprep2.io.collectFolders(h.root, true);
    catch
        found = struct('path',{},'files',{},'nImg',{});
    end

    L = i_emptyList();
    nExp = numel(found);
    for i = 1:nExp
        p = found(i).path;
        base = i_relName(h.root, p);
        i_progStep(fig, i/max(1,nExp), sprintf('Saring QPIV %d/%d:\n%s', i, nExp, base));
        % Saring hanya gambar LOLOS QPIV (Step 0). Frame mati dibuang.
        keptFiles = i_qpivKept(p, found(i).files);
        nF = numel(keptFiles);
        if nF < 1; continue; end
        % Resep masking dari progres terpadu (bila sudah pernah digambar).
        [en, rf, rl, fl, kf] = i_recipeFromProgress(p);
        L(end+1) = i_mkRow(base, p, p, keptFiles, nF, en, rf, rl, fl, kf); %#ok<AGROW>
    end
    i_progClose(fig);
    i_finishScan(fig, L, ...
        sprintf('%d eksperimen (foto mentah, lolos QPIV). Pilih satu untuk masking.', numel(L)), ...
        'Tak ada subfolder foto lolos QPIV. Jalankan GRAIN0 (QPIV) dulu.');
end

function i_finishScan(fig, L, okMsg, emptyMsg)
%I_FINISHSCAN  Muat daftar hasil scan ke GUI (bersama kedua mode).
    h = guidata(fig);
    h.list = L; h.activeRow = 0;
    guidata(fig, h);
    % Label tombol transfer ikut mode: 'jpg' -> GRAIN1, 'mat' -> GRAIN2.
    try
        if strcmp(h.srcMode,'jpg')
            set(h.btnToStep2,'String','Transfer → GRAIN1 (jitter + MAT PREP) ▶');
        else
            set(h.btnToStep2,'String','Transfer → GRAIN2 (Step 2) ▶');
        end
    catch
    end
    i_refreshTable(fig);
    i_clearViewer(fig);
    h = guidata(fig);
    if isempty(L)
        set(h.status,'String', emptyMsg); return;
    end
    set(h.status,'String', okMsg);
    if isfile(fullfile(h.root,'PABMASK_progress.mat'))
        try, i_onLoadProgress(fig, false); catch, end %#ok<CTCH>
    end
end

function L = i_emptyList()
    L = struct('name',{},'file',{},'nFrames',{}, ...
               'path',{},'files',{}, ...
               'enabled',{},'rectFirst',{},'rectLast',{}, ...
               'keyframes',{},'fill',{},'orig',{},'dirty',{});
end

function row = i_mkRow(name, file, path, files, nF, en, rf, rl, fl, kf)
    if nargin < 10 || isempty(kf); kf = i_emptyKf(); end
    row = struct('name',name, 'file',file, 'nFrames',nF, ...
        'path',path, 'files',{files}, ...
        'enabled',en, 'rectFirst',rf, 'rectLast',rl, ...
        'keyframes',{kf}, 'fill',fl, ...
        'orig',i_recipeKey(en,rf,rl,fl,kf), 'dirty',false);
end

function kf = i_emptyKf()
%I_EMPTYKF  Array keyframe TENGAH kosong {frame_index, rect [x y w h]}.
    kf = struct('frame_index',{},'rect',{});
end

function kf = i_kfFromSaved(src)
%I_KFFROMSAVED  Pulihkan keyframe dari progres/engine (struct-array atau cell) ke
%   bentuk baris {frame_index, rect}; buang yang invalid; urut by frame_index.
    kf = i_emptyKf();
    if isempty(src); return; end
    for i = 1:numel(src)
        if iscell(src); one = src{i}; else; one = src(i); end
        if ~isstruct(one) || ~isfield(one,'frame_index') || ~isfield(one,'rect'); continue; end
        fi = double(one.frame_index(1)); rc = i_xywh(one.rect);
        if ~isfinite(fi) || fi < 1 || isempty(rc); continue; end
        kf(end+1) = struct('frame_index',round(fi),'rect',rc); %#ok<AGROW>
    end
    if ~isempty(kf); [~,ord] = sort([kf.frame_index]); kf = kf(ord); end
end

function kf = i_upsertKf(kf, frameIdx, rect)
%I_UPSERTKF  Sisip/timpa keyframe TENGAH di frameIdx; jaga terurut by frame_index.
    if isempty(kf) || ~isstruct(kf); kf = i_emptyKf(); end
    fi  = round(double(frameIdx));
    one = struct('frame_index',fi,'rect',double(rect(:)).');
    if isempty(kf); kf = one; return; end
    idx = find([kf.frame_index] == fi, 1);
    if isempty(idx); kf(end+1) = one; else; kf(idx) = one; end
    [~,ord] = sort([kf.frame_index]); kf = kf(ord);
end

function nodes = i_kfNodes(e, N)
%I_KFNODES  Daftar frame node terurut unik: [1(AWAL), keyframe tengah…, N(AKHIR)].
    nodes = [1 N];
    if ~isempty(e.keyframes); nodes = [nodes, [e.keyframes.frame_index]]; end
    nodes = unique(round(double(nodes)));
    nodes = nodes(nodes >= 1 & nodes <= N);
end

function [rc, kind] = i_nodeRect(e, fr, N)
%I_NODERECT  Kotak & label ('AWAL'|'tengah'|'AKHIR') pada frame node fr.
    rc = []; kind = 'tengah';
    if fr <= 1
        rc = e.rectFirst; kind = 'AWAL'; return;
    end
    if fr >= N
        rc = e.rectLast; if isempty(rc); rc = e.rectFirst; end; kind = 'AKHIR'; return;
    end
    if ~isempty(e.keyframes)
        idx = find([e.keyframes.frame_index] == fr, 1);
        if ~isempty(idx); rc = e.keyframes(idx).rect; end
    end
end

function nm = i_relName(root, p)
%I_RELNAME  Nama exp = path relatif thd root (atau basename bila = root).
    root = regexprep(char(root),'[\\/]+$',''); p = regexprep(char(p),'[\\/]+$','');
    if strcmpi(root, p); [~, nm] = fileparts(p); return; end
    rel = p;
    if startsWith(lower(p), lower(root))
        rel = p(numel(root)+1:end); rel = regexprep(rel, '^[\\/]+', '');
    end
    nm = strrep(rel, filesep, '/'); if isempty(nm); nm = 'exp'; end
end

function keptFiles = i_qpivKept(expPath, files)
%I_QPIVKEPT  Subset `files` yang LOLOS QPIV via progres (qpiv_kept_names / ignore_
%   names / fallback indeks). Mirror ringkas GRAIN1/i_qpivKeptImages (buang by-nama).
    files = files(:); keptFiles = files;
    try, e = PIVlab_automasi_progress('get', expPath); catch, e = []; end
    if isempty(e) || ~isfield(e,'qpiv_done') || ~e.qpiv_done; return; end
    baseAll = i_baseLower(files);
    keptN = i_cellStr(i_getf(e,'qpiv_kept_names'));
    if ~isempty(keptN)
        want = i_baseLower(keptN);
        [tf, loc] = ismember(want, baseAll);
        hit = loc(tf); kf = files(hit);
        if ~isempty(kf); keptFiles = kf; end
        return;
    end
    ignN = i_cellStr(i_getf(e,'ignore_names'));
    if ~isempty(ignN)
        skip = 0; if isfield(e,'skip') && ~isempty(e.skip); skip = round(double(e.skip)); end
        stride = max(1, skip+1); if stride>1; files = files(1:stride:end); end
        drop = ismember(i_baseLower(files), i_baseLower(ignN));
        keptFiles = files(~drop);
    end
end

function [en, rf, rl, fl, kf] = i_recipeFromProgress(expPath)
%I_RECIPEFROMPROGRESS  Baca resep kotak dari progres terpadu (getmask).
    en = false; rf = []; rl = []; fl = 255; kf = i_emptyKf();
    try, m = PIVlab_automasi_progress('getmask', expPath); catch, m = []; end
    if isempty(m) || ~isstruct(m); return; end
    try
        m = pivanalyzemat.core.maskRect.normalize(m);
        en = logical(i_field(m,'enabled',false));
        fl = i_field(m,'fill',255);
        if isfield(m,'boxes') && ~isempty(m.boxes)
            b = m.boxes(1);
            rf = i_field(b,'rect_first',[]);
            rl = i_field(b,'rect_last',[]);
            if isempty(rl); rl = rf; end
            if isfield(b,'keyframes'), kf = i_kfFromSaved(b.keyframes); end
        end
    catch
    end
end

% -- util nama (mode jpg) --
function v = i_getf(s,f); if isstruct(s)&&isfield(s,f); v=s.(f); else; v=[]; end; end
function c = i_cellStr(x)
    c={}; if isempty(x); return; end
    if ischar(x); c={x}; return; end
    if isstring(x); x=cellstr(x); end
    if iscell(x); x=x(:)'; k=cellfun(@(z) ischar(z)&&~isempty(z), x); c=x(k); end
end
function b = i_baseLower(names)
    names=i_cellStr(names); b=cell(1,numel(names));
    for i=1:numel(names); [~,nm,ext]=fileparts(char(names{i})); b{i}=lower([nm ext]); end
end

function i_refreshTable(fig)
    h = guidata(fig);
    n = numel(h.list);
    C = cell(n, 4);
    for i = 1:n
        e = h.list(i);
        C{i,1} = e.name;
        C{i,2} = sprintf('%d', e.nFrames);
        if e.enabled && ~isempty(e.rectFirst)
            C{i,3} = 'ON';
        else
            C{i,3} = '—';
        end
        % Kolom Simpan: BIRU = masking sudah dibuat DAN tersimpan (sidecar ada &
        % tak dirty); MERAH = selainnya (belum ada masking / belum disimpan).
        saved = e.enabled && ~isempty(e.rectFirst) && ~e.dirty ...
            && i_isSaved(h, e);
        C{i,4} = i_cellBadge(saved);
    end
    set(h.tbl, 'Data', C);
end

function s = i_cellBadge(saved)
%I_CELLBADGE  Sel berwarna (uitable klasik dukung HTML): biru=tersimpan,
%   merah=belum. Teks kontras di atas latar berwarna.
    if saved
        s = ['<html><div style="background-color:#1565C0;color:#FFFFFF;' ...
             'text-align:center;">&nbsp;tersimpan&nbsp;</div></html>'];
    else
        s = ['<html><div style="background-color:#C62828;color:#FFFFFF;' ...
             'text-align:center;">&nbsp;belum&nbsp;</div></html>'];
    end
end

function tf = i_isSaved(h, e)
%I_ISSAVED  true bila resep masking sudah tersimpan. Mode 'jpg' -> cek progres
%   terpadu (getmask non-kosong); mode 'mat' -> cek sidecar '<nama>_mask.json'.
    tf = false;
    try
        if strcmp(h.srcMode,'jpg')
            i_pointProgress(h.root);
            m = PIVlab_automasi_progress('getmask', e.path);
            tf = ~isempty(m) && isstruct(m);
        else
            tf = pivanalyzemat.core.maskSidecar.has(e.file);
        end
    catch
    end
end

% =====================================================================
%  Pilih baris -> muat frame awal/akhir (BERSIH) + kotak tersimpan
% =====================================================================
function i_onSelect(fig, e)
    if isempty(e.Indices), return; end
    row = e.Indices(1);
    h = guidata(fig);
    if row < 1 || row > numel(h.list), return; end
    h.activeRow = row;
    guidata(fig, h);
    i_loadActive(fig);
end

% =====================================================================
%  Navigasi antar-exp (Prev/Next) + salin kotak antar-eksperimen
% =====================================================================
function i_gotoRow(fig, row)
    h = guidata(fig);
    n = numel(h.list);
    if n < 1, set(h.status,'String','Belum ada eksperimen.'); return; end
    row = max(1, min(n, row));
    h.activeRow = row;
    guidata(fig, h);
    % Sorot baris di tabel (uifigure) bila didukung; klasik → abaikan diam-diam.
    try, set(h.tbl, 'Selection', row); catch, end %#ok<CTCH>
    i_loadActive(fig);
    h = guidata(fig);
    set(h.status,'String', sprintf('Eksperimen %d / %d: %s', ...
        row, n, h.list(row).name));
end

function i_onPrevExp(fig)
    h = guidata(fig);
    if h.activeRow < 1, i_gotoRow(fig, 1); return; end
    if h.activeRow <= 1
        set(h.status,'String','Sudah di eksperimen pertama.'); return;
    end
    i_gotoRow(fig, h.activeRow - 1);
end

function i_onNextExp(fig)
    h = guidata(fig);
    if h.activeRow < 1, i_gotoRow(fig, 1); return; end
    if h.activeRow >= numel(h.list)
        set(h.status,'String','Sudah di eksperimen terakhir.'); return;
    end
    i_gotoRow(fig, h.activeRow + 1);
end

function i_onSaveNextExp(fig)
%I_ONSAVENEXTEXP  Simpan masking exp aktif LALU maju ke exp berikutnya.
%   Split dari "Exp berikutnya": alur sapu cepat (simpan → maju) tanpa
%   dua klik terpisah. Bila sudah di exp terakhir, tetap disimpan.
    h = guidata(fig);
    if h.activeRow < 1, i_gotoRow(fig, 1); return; end
    i_onSaveActive(fig);                 % simpan (sidecar / progres) + tandai bersih
    h = guidata(fig);
    if h.activeRow < numel(h.list)
        i_gotoRow(fig, h.activeRow + 1);
    else
        set(h.status,'String','Tersimpan. Sudah di eksperimen terakhir.');
    end
end

function i_onCopyFromPrev(fig)
%I_ONCOPYFROMPREV  Salin kotak AWAL+AKHIR (+isi/aktif) dari exp baris atas.
    h = guidata(fig);
    row = h.activeRow;
    if row < 1, set(h.status,'String','Pilih eksperimen dulu.'); return; end
    if row < 2, set(h.status,'String','Tidak ada eksperimen sebelumnya.'); return; end
    src = h.list(row-1);
    if isempty(src.rectFirst)
        set(h.status,'String', sprintf('Exp sebelumnya ("%s") belum punya kotak.', src.name));
        return;
    end
    h.list(row).rectFirst = src.rectFirst;
    h.list(row).rectLast  = src.rectLast;
    h.list(row).keyframes = src.keyframes;
    h.list(row).fill      = src.fill;
    h.list(row).enabled   = src.enabled;
    h = i_markDirty(h);
    guidata(fig, h);
    set(h.chkEnable,'Value', double(h.list(row).enabled));
    i_refreshTable(fig);
    i_refreshKfTable(fig);
    i_render(fig);
    i_updateInfo(fig);
    set(h.status,'String', sprintf('Kotak disalin dari "%s". Edit bila perlu, lalu Simpan.', src.name));
end

function i_onCopyToAll(fig)
%I_ONCOPYTOALL  Salin kotak exp aktif ke SEMUA eksperimen lain (belum ditulis
%   ke .mat — ditandai ✎; user tinggal Simpan / Simpan Progress).
    h = guidata(fig);
    row = h.activeRow;
    if row < 1, set(h.status,'String','Pilih eksperimen sumber dulu.'); return; end
    src = h.list(row);
    if isempty(src.rectFirst)
        set(h.status,'String','Exp aktif belum punya kotak untuk disalin.'); return;
    end
    n = numel(h.list); cnt = 0;
    for i = 1:n
        if i == row, continue; end
        h.list(i).rectFirst = src.rectFirst;
        h.list(i).rectLast  = src.rectLast;
        h.list(i).keyframes = src.keyframes;
        h.list(i).fill      = src.fill;
        h.list(i).enabled   = src.enabled;
        key = i_recipeKey(h.list(i).enabled, h.list(i).rectFirst, ...
                          h.list(i).rectLast, h.list(i).fill, h.list(i).keyframes);
        h.list(i).dirty = ~isequal(key, h.list(i).orig);
        cnt = cnt + 1;
    end
    guidata(fig, h);
    i_refreshTable(fig);
    set(h.status,'String', sprintf(['Kotak "%s" disalin ke %d exp lain (belum disimpan). ' ...
        'Cek per-exp, lalu Simpan / Simpan Progress.'], src.name, cnt));
end

function i_loadActive(fig)
    h = guidata(fig);
    row = h.activeRow;
    if row < 1 || row > numel(h.list), return; end
    e = h.list(row);

    h.imgFirst = []; h.imgLast = []; h.imSz = []; nF = e.nFrames;
    isJpg = strcmp(h.srcMode,'jpg');
    if isJpg
        srcMsg = 'Membuka foto mentah (frame awal+akhir)…';
    else
        srcMsg = 'Membuka MAT PREP (frame awal+akhir)…';
    end
    i_progOpen(fig, 'GRAINMASK — memuat eksperimen', sprintf('%s\n%s', e.name, srcMsg));
    try
        % FRAME BERSIH — editor menggambar kotak di atasnya.
        i_progStep(fig, 0.15, sprintf('%s\nDekode frame awal+akhir…', e.name));
        if isJpg
            % MODE JPG: frame awal = file pertama, akhir = file terakhir (lolos QPIV).
            ff = e.files; if isempty(ff); error('GRAINMASK:noFiles','Daftar foto kosong.'); end
            h.imgFirst = imread(fullfile(e.path, ff{1}));
            h.imgLast  = imread(fullfile(e.path, ff{end}));
            nF = numel(ff);
        else
            % readMatFramePair = SATU load() utk dua frame; blob besar didekompresi 1x.
            [h.imgFirst, h.imgLast, ~, ~, nF] = ...
                pivanalyzemat.core.readMatFramePair(e.file, false);
        end
        i_progStep(fig, 1.00, sprintf('%s\nSelesai memuat.', e.name));
    catch ME
        set(h.status,'String', sprintf('Gagal baca frame: %s', ME.message));
    end
    i_progClose(fig);
    h.activeRow = row;   % i_progClose menulis guidata; jaga h tetap konsisten
    if ~isempty(h.imgFirst)
        h.imSz = [size(h.imgFirst,1) size(h.imgFirst,2)];   % [H W]
    end
    h.list(row).nFrames = nF;

    % Resep masking dibaca murah saat SCAN. Mode 'mat': baca ulang (allowSlow juga
    % menangkap prep.masking warisan). Mode 'jpg': resep sudah dari progres terpadu
    % saat scan; jangan baca .mat (tak ada). Jangan timpa bila sudah punya kotak.
    if ~isJpg && isempty(h.list(row).rectFirst) && ~h.list(row).dirty
        [en2, rf2, rl2, fl2, kf2] = i_readMasking(e.file, true);
        if en2 || ~isempty(rf2)
            h.list(row).enabled   = en2;
            h.list(row).rectFirst = rf2;
            h.list(row).rectLast  = rl2;
            h.list(row).keyframes = kf2;
            h.list(row).fill      = fl2;
            h.list(row).orig      = i_recipeKey(en2, rf2, rl2, fl2, kf2);
            e = h.list(row);
        end
    end
    h.viewMode = 'first'; h.imh = []; h.roi = []; h.ovl = [];
    h.editTarget = 'first';
    h.previewFrame = 1;
    h.imgPrev = []; h.prevLoaded = 0;   % buang cache pratinjau exp lama

    set(h.txtExp,'String', e.name);
    set(h.chkEnable,'Value', double(e.enabled));

    % konfigurasi slider pratinjau
    nFs = max(2, nF);
    set(h.sld,'Min',1,'Max',nFs,'Value',1, ...
        'SliderStep',[1/(nFs-1) max(2/(nFs-1), 0.1)]);
    h.previewFrame = 1;

    guidata(fig, h);
    i_render(fig);
    i_refreshKfTable(fig);
    i_updateInfo(fig);
    set(h.status,'String', ...
        sprintf('Aktif: %s (%d frame). Tarik kotak AWAL & AKHIR; keyframe tengah opsional.', e.name, nF));
end

function i_setEditTarget(fig, tgt)
    h = guidata(fig);
    if h.activeRow < 1, return; end
    if isempty(tgt)                       % "↩ Kembali awal/akhir": pakai target terakhir
        tgt = h.editTarget; if isempty(tgt), tgt = 'first'; end
    end
    h.editTarget = tgt;
    h.viewMode = tgt;                     % 'first' | 'last' (mode edit kotak)
    guidata(fig, h);
    i_render(fig);
end

function i_render(fig)
    h = guidata(fig);
    ax = h.ax;
    switch h.viewMode
        case 'last',    img = h.imgLast;
        case 'preview', img = h.imgPrev;
        otherwise,      img = h.imgFirst;
    end

    % buang overlay/roi lama sebelum gambar ulang
    i_deleteRoi(h); i_deleteOvl(h);
    h = guidata(fig);   % i_delete* tak ubah h, tapi jaga konsistensi

    if isempty(img)
        cla(ax); h.imh = [];
        text(0.5,0.5,'(tak ada frame pada MAT PREP ini)','Parent',ax, ...
            'Units','normalized','HorizontalAlignment','center', ...
            'Color',[0.4 0.4 0.4]);
        set(ax,'XTick',[],'YTick',[]);
        guidata(fig,h); return;
    end

    reuse = ~isempty(h.imh) && isgraphics(h.imh) && ...
        isequal(size(get(h.imh,'CData')), size(img));
    if reuse
        set(h.imh,'CData',img);
    else
        cla(ax);
        h.imh = image(img,'Parent',ax);
        axis(ax,'image'); set(ax,'YDir','reverse');
        set(ax,'XTick',[],'YTick',[]);
    end
    if ndims(img) == 2 %#ok<ISMAT>
        colormap(ax, gray(256));
    end

    switch h.viewMode
        case 'last'
            set(h.btnFirst,'BackgroundColor',[0.95 0.95 0.95]);
            set(h.btnLast, 'BackgroundColor',[0.85 0.90 0.98]);
            title(ax,'FRAME AKHIR — kotak kondisi akhir','Color',[0 0 0]);
        case 'preview'
            set(h.btnFirst,'BackgroundColor',[0.95 0.95 0.95]);
            set(h.btnLast, 'BackgroundColor',[0.95 0.95 0.95]);
            title(ax, sprintf('PRATINJAU FRAME %d / %d — kotak interpolasi (tak bisa diedit)', ...
                h.prevLoaded, max(1,h.list(h.activeRow).nFrames)), 'Color',[0.1 0.2 0.5]);
        otherwise
            set(h.btnFirst,'BackgroundColor',[0.85 0.90 0.98]);
            set(h.btnLast, 'BackgroundColor',[0.95 0.95 0.95]);
            title(ax,'FRAME AWAL — kotak kondisi awal','Color',[0 0 0]);
    end
    guidata(fig,h);

    % Mode edit (first/last): kotak tersimpan sbg ROI draggable + overlay
    % pratinjau interpolasi. Mode preview: HANYA overlay kotak frame itu (no ROI).
    if ~strcmp(h.viewMode,'preview')
        i_drawStoredRect(fig);
    end
    i_drawPreviewOverlay(fig);
    i_updateRectLabel(fig);
end

function i_drawStoredRect(fig)
    h = guidata(fig);
    if h.activeRow < 1, return; end
    e = h.list(h.activeRow);
    if strcmp(h.editTarget,'last'), rect = e.rectLast; else, rect = e.rectFirst; end
    i_deleteRoi(h);
    if isempty(rect), guidata(fig,h); return; end
    try
        roi = images.roi.Rectangle('Parent',h.ax,'Position',rect, ...
            'Color',[0.10 0.65 0.10],'LineWidth',1.5,'FaceAlpha',0.12, ...
            'Label','mask','LabelVisible','hover');
        addlistener(roi,'ROIMoved',@(s,ev) i_onRoiMoved(fig));
        addlistener(roi,'MovingROI',@(s,ev) i_onRoiMoving(fig));
        h.roi = roi;
    catch
        h.roi = [];
    end
    guidata(fig,h);
end

function i_onDrawRect(fig)
    h = guidata(fig);
    if h.activeRow < 1 || isempty(h.imh) || ~isgraphics(h.imh)
        set(h.status,'String','Pilih eksperimen & frame dulu.'); return;
    end
    try, zoom(h.ax,'off'); catch, end %#ok<CTCH>
    try, pan(h.ax,'off');  catch, end %#ok<CTCH>
    i_deleteRoi(h);
    % drawrectangle: BLOCKING, stretch sisi/sudut (bukan polygon). Gambar
    % LANGSUNG di axes modul (parent eksplisit) agar tak nyasar ke gca lain.
    try
        roi = drawrectangle(h.ax,'Color',[0.10 0.65 0.10],'LineWidth',1.5, ...
            'Label','mask','LabelVisible','hover');
    catch
        roi = pivprep.util.utilities.safeDrawRectangle([], [0.10 0.65 0.10], 'mask');
    end
    if isempty(roi) || ~isvalid(roi), return; end
    rect = i_clampRect(roi.Position, h.imSz);
    roi.Position = rect;
    addlistener(roi,'ROIMoved',@(s,ev) i_onRoiMoved(fig));
    addlistener(roi,'MovingROI',@(s,ev) i_onRoiMoving(fig));
    h = guidata(fig); h.roi = roi;
    if strcmp(h.viewMode,'preview')
        % Mode preview (frame tengah): kotak KANDIDAT keyframe — JANGAN tulis ke
        % rectFirst/rectLast. Tekan "＋ Set KF" untuk menyimpannya jadi keyframe.
        guidata(fig,h);
        i_updateRectLabel(fig);
        set(h.status,'String', sprintf(['Kotak digambar untuk frame %d. Geser bila ' ...
            'perlu, lalu tekan ＋ Set KF.'], h.previewFrame));
        return;
    end
    % simpan ke target aktif (mode edit AWAL/AKHIR)
    if strcmp(h.editTarget,'last'), h.list(h.activeRow).rectLast = rect;
    else,                            h.list(h.activeRow).rectFirst = rect; end
    h.list(h.activeRow).enabled = true;
    set(h.chkEnable,'Value',1);
    h = i_markDirty(h);
    guidata(fig,h);
    i_refreshTable(fig);
    i_refreshKfTable(fig);
    i_drawPreviewOverlay(fig);
    i_updateRectLabel(fig);
    i_updateInfo(fig);
end

function i_onRoiMoving(fig)
    % live: perbarui overlay pratinjau saja (ringan), commit saat ROIMoved.
    i_commitRoi(fig, false);
end

function i_onRoiMoved(fig)
    i_commitRoi(fig, true);
end

function i_commitRoi(fig, doDirty)
    h = guidata(fig);
    if h.activeRow < 1 || isempty(h.roi) || ~isvalid(h.roi), return; end
    rect = i_clampRect(h.roi.Position, h.imSz);
    if doDirty, h.roi.Position = rect; end
    if strcmp(h.viewMode,'preview')
        % kandidat keyframe: jangan tulis ke list; hanya perbarui label.
        i_updateRectLabel(fig); return;
    end
    if strcmp(h.editTarget,'last'), h.list(h.activeRow).rectLast = rect;
    else,                            h.list(h.activeRow).rectFirst = rect; end
    if doDirty
        h = i_markDirty(h);
        guidata(fig,h);
        i_refreshTable(fig);
        i_updateInfo(fig);
    else
        guidata(fig,h);
    end
    i_drawPreviewOverlay(fig);
    i_updateRectLabel(fig);
end

function i_onCopyFirstToLast(fig)
    h = guidata(fig);
    if h.activeRow < 1, return; end
    rf = h.list(h.activeRow).rectFirst;
    if isempty(rf)
        set(h.status,'String','Belum ada kotak AWAL untuk disalin.'); return;
    end
    h.list(h.activeRow).rectLast = rf;
    h.list(h.activeRow).enabled = true;
    set(h.chkEnable,'Value',1);
    h = i_markDirty(h);
    guidata(fig,h);
    i_refreshTable(fig);
    i_render(fig);
    i_updateInfo(fig);
    set(h.status,'String','Kotak awal disalin ke akhir (kotak statis).');
end

% =====================================================================
%  Pratinjau interpolasi
% =====================================================================
function i_onSlider(fig)
    h = guidata(fig);
    if h.activeRow < 1, return; end
    h.previewFrame = round(get(h.sld,'Value'));
    guidata(fig,h);
    i_drawPreviewOverlay(fig);
    i_updatePreviewLabel(fig);
end

function i_onShowFrame(fig)
%I_ONSHOWFRAME  Muat frame nyata (sesuai slider) ON-DEMAND ke kanvas + kotak
%   interpolasi untuk frame itu. BUKAN dump seluruh MAT PREP — readMatFrame baca
%   1 blob. Resolusi PENUH (ukuran piksel = frame awal/akhir) → kotak pas.
    h = guidata(fig);
    if h.activeRow < 1
        set(h.status,'String','Pilih eksperimen dulu.'); return;
    end
    e = h.list(h.activeRow);
    k = round(get(h.sld,'Value'));
    k = max(1, min(max(1,e.nFrames), k));
    h.previewFrame = k;
    % cache: hanya decode bila frame berbeda dari yang sudah dimuat.
    if h.prevLoaded ~= k || isempty(h.imgPrev)
        set(h.status,'String', sprintf('Memuat frame %d…', k));
        i_progOpen(fig, 'GRAINMASK — memuat frame', ...
            sprintf('%s\nDekode frame %d / %d…', e.name, k, max(1,e.nFrames)));
        i_progStep(fig, 0.35, sprintf('%s\nDekode frame %d / %d…', e.name, k, max(1,e.nFrames)));
        try
            % FRAME BERSIH — kotak digambar sbg overlay, bukan dibakar.
            if strcmp(h.srcMode,'jpg')
                kk = max(1, min(numel(e.files), k));
                img = imread(fullfile(e.path, e.files{kk}));
            else
                img = pivanalyzemat.core.readMatFrame(e.file, k, false);
            end
        catch ME
            i_progClose(fig);
            set(h.status,'String', sprintf('Gagal muat frame %d: %s', k, ME.message));
            guidata(fig,h); return;
        end
        i_progStep(fig, 1.00, sprintf('%s\nFrame %d dimuat.', e.name, k));
        i_progClose(fig);
        if isempty(img)
            set(h.status,'String', sprintf('Frame %d kosong.', k));
            guidata(fig,h); return;
        end
        h.imgPrev = img; h.prevLoaded = k;
        % ukuran frame nyata = ukuran kanvas referensi (kotak pakai koordinat ini).
        if isempty(h.imSz), h.imSz = [size(img,1) size(img,2)]; end
    end
    h.viewMode = 'preview';
    h.imh = [];                  % paksa image baru (ukuran bisa beda dari ROI sblmnya)
    guidata(fig,h);
    i_render(fig);
    i_updatePreviewLabel(fig);
    set(h.status,'String', sprintf('Menampilkan frame %d / %d (kotak interpolasi).', ...
        k, max(1,e.nFrames)));
end

function i_drawPreviewOverlay(fig)
    h = guidata(fig);
    i_deleteOvl(h);
    if h.activeRow < 1, return; end
    e = h.list(h.activeRow);
    % Di mode preview tampilkan kotak walau enable belum dicentang (informatif);
    % di mode edit hanya bila aktif (hindari ramai saat baru menggambar).
    if isempty(e.rectFirst), guidata(fig,h); return; end
    if ~strcmp(h.viewMode,'preview') && ~e.enabled, guidata(fig,h); return; end
    box = i_boxStruct(e, e.nFrames);
    N = max(2, e.nFrames);
    W = []; Hh = [];
    if ~isempty(h.imSz), W = h.imSz(2); Hh = h.imSz(1); end
    bb = pivanalyzemat.core.maskRect.interpRect(box, h.previewFrame, N, W, Hh);
    if isempty(bb), guidata(fig,h); return; end
    px = [bb(1) bb(3) bb(3) bb(1)];
    py = [bb(2) bb(2) bb(4) bb(4)];
    try
        h.ovl = patch('Parent',h.ax,'XData',px,'YData',py, ...
            'FaceColor',[1 1 1],'FaceAlpha',0.55, ...
            'EdgeColor',[0.85 0.20 0.20],'LineStyle','--','LineWidth',1.2);
    catch
        h.ovl = [];
    end
    guidata(fig,h);
end

% =====================================================================
%  Keyframe TENGAH (koreksi ukuran kotak per-frame; endpoint AWAL/AKHIR tetap)
% =====================================================================
function i_refreshKfTable(fig)
%I_REFRESHKFTABLE  Isi tabel keyframe: node [1(AWAL)…tengah…N(AKHIR)] + ukuran.
    h = guidata(fig);
    C = {};
    if h.activeRow >= 1
        e = h.list(h.activeRow);
        N = max(2, e.nFrames);
        nodes = i_kfNodes(e, N);
        C = cell(numel(nodes), 3);
        for i = 1:numel(nodes)
            fr = nodes(i);
            [rc, kind] = i_nodeRect(e, fr, N);
            C{i,1} = sprintf('%d', fr);
            C{i,2} = kind;
            if isempty(rc)
                C{i,3} = '—';
            else
                C{i,3} = sprintf('%d×%d', round(rc(3)), round(rc(4)));
            end
        end
    end
    try, set(h.kfTbl, 'Data', C); catch, end %#ok<CTCH>
end

function i_onKfSelect(fig, ev)
%I_ONKFSELECT  Klik baris tabel keyframe → loncat + tampilkan frame node itu.
    if isempty(ev.Indices), return; end
    h = guidata(fig);
    if h.activeRow < 1, return; end
    e = h.list(h.activeRow); N = max(2, e.nFrames);
    nodes = i_kfNodes(e, N);
    rowi = ev.Indices(1);
    if rowi < 1 || rowi > numel(nodes), return; end
    i_jumpToFrame(fig, nodes(rowi));
end

function i_onSetKeyframe(fig)
%I_ONSETKEYFRAME  Jadikan kotak pada frame yang tampil sebagai keyframe.
%   frame 1 → AWAL (rectFirst); frame N → AKHIR (rectLast); selainnya → keyframe
%   TENGAH (upsert). Sumber kotak: ROI baru digambar bila ada, else interpolasi
%   di frame itu (nudge). Endpoint & keyframe di-hash dirty → tandai belum-simpan.
    h = guidata(fig);
    r = h.activeRow;
    if r < 1, set(h.status,'String','Pilih eksperimen dulu.'); return; end
    e = h.list(r);
    N = max(2, e.nFrames);
    k = round(h.previewFrame); k = max(1, min(N, k));

    rect = [];
    if ~isempty(h.roi) && isvalid(h.roi)
        rect = i_clampRect(h.roi.Position, h.imSz);          % ROI baru digambar
    elseif ~isempty(e.rectFirst)
        box = i_boxStruct(e, N);                              % nudge dari interpolasi
        W = []; Hh = [];
        if ~isempty(h.imSz), W = h.imSz(2); Hh = h.imSz(1); end
        bb = pivanalyzemat.core.maskRect.interpRect(box, k, N, W, Hh);
        if ~isempty(bb), rect = [bb(1) bb(2) bb(3)-bb(1) bb(4)-bb(2)]; end
    end
    if isempty(rect)
        set(h.status,'String','Belum ada kotak — Tarik kotak dulu di frame ini.'); return;
    end

    if k <= 1
        h.list(r).rectFirst = rect;   kind = 'AWAL';
    elseif k >= N
        h.list(r).rectLast  = rect;   kind = 'AKHIR';
    else
        h.list(r).keyframes = i_upsertKf(e.keyframes, k, rect); kind = 'tengah';
    end
    h.list(r).enabled = true;
    set(h.chkEnable,'Value',1);
    h = i_markDirty(h);
    i_deleteRoi(h); h.roi = [];        % kandidat → jadi overlay interpolasi
    guidata(fig, h);
    i_refreshKfTable(fig);
    i_refreshTable(fig);
    i_render(fig);
    set(h.status,'String', sprintf('Keyframe %s frame %d di-set (w=%d h=%d). Simpan untuk menulis.', ...
        kind, k, round(rect(3)), round(rect(4))));
end

function i_onDelKeyframe(fig)
%I_ONDELKEYFRAME  Hapus keyframe TENGAH pada frame yang tampil (endpoint tetap).
    h = guidata(fig);
    r = h.activeRow;
    if r < 1, set(h.status,'String','Pilih eksperimen dulu.'); return; end
    e = h.list(r);
    N = max(2, e.nFrames);
    k = round(h.previewFrame);
    if k <= 1 || k >= N
        set(h.status,'String','Endpoint AWAL/AKHIR tak bisa dihapus — cukup di-Set ulang.'); return;
    end
    if isempty(e.keyframes)
        set(h.status,'String','Tak ada keyframe tengah.'); return;
    end
    idx = find([e.keyframes.frame_index] == k, 1);
    if isempty(idx)
        set(h.status,'String', sprintf('Tak ada keyframe di frame %d.', k)); return;
    end
    e.keyframes(idx) = [];
    h.list(r).keyframes = e.keyframes;
    h = i_markDirty(h);
    guidata(fig, h);
    i_refreshKfTable(fig);
    i_refreshTable(fig);
    i_render(fig);
    set(h.status,'String', sprintf('Keyframe frame %d dihapus.', k));
end

function i_onPrevKeyframe(fig), i_stepKeyframe(fig, -1); end
function i_onNextKeyframe(fig), i_stepKeyframe(fig, +1); end

function i_stepKeyframe(fig, dir)
%I_STEPKEYFRAME  Loncat ke node keyframe sebelum/sesudah frame kini (tanpa scan).
    h = guidata(fig);
    r = h.activeRow;
    if r < 1, set(h.status,'String','Pilih eksperimen dulu.'); return; end
    e = h.list(r); N = max(2, e.nFrames);
    nodes = i_kfNodes(e, N);
    cur = round(h.previewFrame);
    if dir < 0
        cand = nodes(nodes < cur);
        if isempty(cand), set(h.status,'String','Sudah di keyframe pertama (AWAL).'); return; end
        target = cand(end);
    else
        cand = nodes(nodes > cur);
        if isempty(cand), set(h.status,'String','Sudah di keyframe terakhir (AKHIR).'); return; end
        target = cand(1);
    end
    i_jumpToFrame(fig, target);
end

function i_jumpToFrame(fig, k)
%I_JUMPTOFRAME  Set slider ke frame k lalu tampilkan frame NYATA (i_onShowFrame).
    h = guidata(fig);
    if h.activeRow < 1, return; end
    N = max(2, h.list(h.activeRow).nFrames);
    k = max(1, min(N, round(k)));
    try, set(h.sld, 'Value', k); catch, end %#ok<CTCH>
    h.previewFrame = k; guidata(fig, h);
    i_onShowFrame(fig);
end

% =====================================================================
%  Enable toggle / hapus / simpan
% =====================================================================
function i_onToggleEnable(fig)
    h = guidata(fig);
    if h.activeRow < 1, set(h.chkEnable,'Value',0); return; end
    h.list(h.activeRow).enabled = logical(get(h.chkEnable,'Value'));
    h = i_markDirty(h);
    guidata(fig,h);
    i_refreshTable(fig);
    i_render(fig);
    i_updateInfo(fig);
end

function i_onClearMask(fig)
    h = guidata(fig);
    if h.activeRow < 1
        set(h.status,'String','Pilih satu eksperimen dulu.'); return;
    end
    h.list(h.activeRow).enabled = false;
    h.list(h.activeRow).rectFirst = [];
    h.list(h.activeRow).rectLast = [];
    h.list(h.activeRow).keyframes = i_emptyKf();
    set(h.chkEnable,'Value',0);
    h = i_markDirty(h);
    guidata(fig,h);
    i_refreshTable(fig);
    i_refreshKfTable(fig);
    i_render(fig);
    i_updateInfo(fig);
    set(h.status,'String','Masking dinonaktifkan (simpan untuk menulis ke .mat).');
end

function i_onSaveActive(fig)
    h = guidata(fig);
    row = h.activeRow;
    if row < 1 || row > numel(h.list)
        set(h.status,'String','Pilih satu eksperimen dulu.'); return;
    end
    e = h.list(row);
    if e.enabled && isempty(e.rectFirst)
        set(h.status,'String','Aktif tapi belum ada kotak — tarik kotak dulu.');
        return;
    end
    h.busy = true; guidata(fig,h);
    % NON-DESTRUKTIF: mode 'mat' -> resep ke SIDECAR '<nama>_mask.json' (kecil,
    % MAT PREP tak ditulis ulang). Mode 'jpg' (urutan baru) -> resep ke PROGRES
    % TERPADU (PIVlab_automasi_progress:setmask); GRAIN1 nanti tulis sidecar di
    % samping MAT PREP saat produksi. Instan; tak ada .bak.
    isJpg = strcmp(h.srcMode,'jpg');
    if isJpg; tgtMsg = 'Menyimpan resep ke progres terpadu…'; else; tgtMsg = 'Menulis resep ke sidecar…'; end
    i_progOpen(fig, 'GRAINMASK — menyimpan resep masking', sprintf('%s\n%s', e.name, tgtMsg));
    try
        i_progStep(fig, 0.30, sprintf('%s\nMenyusun resep masking…', e.name));
        i_progStep(fig, 0.60, sprintf('%s\n%s', e.name, tgtMsg));
        if e.enabled && ~isempty(e.rectFirst)
            i_persistRecipe(h, e, i_buildMaskingStruct(e));
        else
            i_removeRecipe(h, e);   % nonaktif/kosong -> buang resep
        end
        i_progStep(fig, 1.00, sprintf('%s\nSelesai disimpan.', e.name));
        i_progClose(fig);
        h = guidata(fig);
        h.list(row).orig = i_recipeKey(e.enabled, e.rectFirst, e.rectLast, e.fill, e.keyframes);
        h.list(row).dirty = false;
        h.busy = false; guidata(fig,h);
        i_refreshTable(fig);
        set(h.status,'String', sprintf('Tersimpan: %s', e.name));
        fprintf('[GRAINMASK] simpan masking %s: enabled=%d\n', e.name, e.enabled);
    catch ME
        i_progClose(fig);
        h = guidata(fig);
        h.busy = false; guidata(fig,h);
        set(h.status,'String', sprintf('GAGAL simpan: %s', ME.message));
    end
end

function i_onSaveAll(fig)
%I_ONSAVEALL  Simpan resep masking SEMUA eksperimen yang punya kotak ke sidecar
%   masing-masing (instan, MAT PREP tak disentuh). Exp tanpa kotak dilewati; exp
%   yang masking-nya dinonaktifkan -> sidecar dihapus. Dengan progress bar.
    h = guidata(fig);
    n = numel(h.list);
    if n < 1
        set(h.status,'String','Belum ada eksperimen. Pindai folder dulu.'); return;
    end
    h.busy = true; guidata(fig,h);
    i_progOpen(fig, 'GRAINMASK — menyimpan SEMUA masking', ...
        sprintf('Menyimpan resep %d eksperimen ke sidecar…', n));
    % Snapshot daftar (i_prog* menulis guidata; hindari state basi).
    lst = h.list;
    nSaved = 0; nCleared = 0; nFail = 0;
    for i = 1:n
        e = lst(i);
        i_progStep(fig, i/max(1,n), sprintf('%d/%d: %s', i, n, e.name));
        try
            if e.enabled && ~isempty(e.rectFirst)
                i_persistRecipe(h, e, i_buildMaskingStruct(e));
                nSaved = nSaved + 1;
            else
                % masking nonaktif/kosong -> buang resep (sidecar / progres).
                i_removeRecipe(h, e);
                nCleared = nCleared + 1;
            end
            lst(i).orig  = i_recipeKey(e.enabled, e.rectFirst, e.rectLast, e.fill, e.keyframes);
            lst(i).dirty = false;
        catch
            nFail = nFail + 1;
        end
    end
    i_progClose(fig);
    h = guidata(fig);           % re-fetch (progClose menulis guidata)
    h.list = lst;               % terapkan pembersihan dirty/orig
    h.busy = false; guidata(fig,h);
    i_refreshTable(fig);
    msg = sprintf('Simpan SEMUA: %d ber-masking disimpan, %d tanpa-masking dibersihkan', ...
        nSaved, nCleared);
    if nFail > 0, msg = sprintf('%s, %d GAGAL', msg, nFail); end
    set(h.status,'String', msg);
    fprintf('[GRAINMASK] simpan SEMUA: saved=%d cleared=%d fail=%d\n', nSaved, nCleared, nFail);
end

% =====================================================================
%  I/O resep masking (SIDECAR <nama>_mask.json — MAT PREP tak disentuh)
% =====================================================================
function [en, rf, rl, fl, kf] = i_readMasking(matFile, allowSlow)
%I_READMASKING  Baca resep masking (kotak pertama); default kosong. Sumber:
%   SIDECAR '<nama>_mask.json' (instan) diprioritaskan; fallback warisan
%   pmasking/prep.masking. allowSlow (default false): bila true izinkan fallback
%   prep.masking (memuat prep — HANYA saat MEMBUKA exp, bukan saat pindai daftar).
    if nargin < 2 || isempty(allowSlow); allowSlow = false; end
    en = false; rf = []; rl = []; fl = 255; kf = i_emptyKf();
    raw = [];
    try
        raw = pivanalyzemat.core.prepBlobStore.readMasking(matFile, allowSlow);
    catch
        raw = [];
    end
    if isempty(raw), return; end
    m = pivanalyzemat.core.maskRect.normalize(raw);
    fl = m.fill;
    if ~m.enabled || isempty(m.boxes), return; end
    en = true;
    b = m.boxes(1);
    rf = i_xywh(b.rect_first);
    rl = i_xywh(b.rect_last);
    if isfield(b,'keyframes'), kf = i_kfFromSaved(b.keyframes); end
end

function i_writeMasking(matFile, masking)
%I_WRITEMASKING  Tulis resep masking ke SIDECAR '<nama>_mask.json' (kecil;
%   pivanalyzemat.core.prepBlobStore.writeMasking -> maskSidecar). MAT PREP (blob
%   RAW) TAK PERNAH ditulis ulang. Decoder (readMatFrame/unpackMat) & GRAIN2
%   membaca sidecar otomatis. Instan & non-destruktif.
    if isempty(matFile) || ~ischar(matFile)
        error('GRAINMASK:badFile','Path MAT PREP tak sah.');
    end
    ok = false;
    try
        ok = pivanalyzemat.core.prepBlobStore.writeMasking(matFile, masking);
    catch ME
        error('GRAINMASK:writeMask','Gagal tulis sidecar masking: %s', ME.message);
    end
    if ~ok
        error('GRAINMASK:writeMask','Gagal tulis sidecar masking untuk:\n%s', matFile);
    end
end

function i_persistRecipe(h, e, masking)
%I_PERSISTRECIPE  Simpan resep sesuai MODE sumber:
%   'jpg' -> progres terpadu (PIVlab_automasi_progress:setmask by folder exp).
%            GRAIN1 baca ini saat produksi & tulis sidecar di samping MAT PREP.
%   'mat' -> sidecar '<nama>_mask.json' langsung (perilaku lama).
    if strcmp(h.srcMode,'jpg')
        i_pointProgress(h.root);
        PIVlab_automasi_progress('setmask', e.path, masking);
    else
        i_writeMasking(e.file, masking);
    end
end

function i_removeRecipe(h, e)
%I_REMOVERECIPE  Hapus resep (masking nonaktif) sesuai mode.
    if strcmp(h.srcMode,'jpg')
        i_pointProgress(h.root);
        try, PIVlab_automasi_progress('setmask', e.path, []); catch, end %#ok<CTCH>
    else
        try, pivanalyzemat.core.maskSidecar.remove(e.file); catch, end %#ok<CTCH>
    end
end

function i_pointProgress(root)
%I_POINTPROGRESS  Arahkan engine progres ke <root>/PAB0_progress.mat (acuan terpadu).
    try
        pf = fullfile(root, 'PAB0_progress.mat');
        PIVlab_automasi_progress('setfile', pf);
    catch
    end
end

function m = i_buildMaskingStruct(e)
%I_BUILDMASKINGSTRUCT  Bentuk prep.masking dari state baris (1 kotak).
    if ~e.enabled || isempty(e.rectFirst)
        m = struct('enabled',false,'fill',e.fill, ...
            'boxes', struct('rect_first',{},'rect_last',{}, ...
                            'frame_first',{},'frame_last',{}));
        return;
    end
    rl = e.rectLast; if isempty(rl), rl = e.rectFirst; end
    box = struct('rect_first',e.rectFirst(:).', 'rect_last',rl(:).', ...
        'frame_first',1, 'frame_last',max(2,e.nFrames), ...
        'keyframes',{e.keyframes});   % {..} cegah broadcast struct-array
    % n_ref = jumlah frame acuan saat resep dibuat (frame lolos QPIV). Bila MAT
    % PREP nanti punya nFrames berbeda (mis. beda pemetaan skip/nama), decoder
    % menskala indeks acuan ke N aktual -> posisi RELATIF kotak terjaga.
    m = struct('enabled',true,'fill',e.fill,'n_ref',max(2,e.nFrames),'boxes',box);
    % normalize utk jaminan skema (juga buang kotak invalid).
    m = pivanalyzemat.core.maskRect.normalize(m);
end

% =====================================================================
%  Progress per-ROOT  (<ROOT>/PABMASK_progress.mat) — state kerja resep
%  SEMUA exp (termasuk yg belum di-Simpan ke .mat). Beda dari prep.masking
%  FINAL di tiap .mat. Match by file path. Auto-load saat scan.
% =====================================================================
function i_onSaveProgress(fig)
%I_ONSAVEPROGRESS  Timpa <ROOT>/PABMASK_progress.mat (tanpa dialog).
    h = guidata(fig);
    if isempty(h.list)
        set(h.status,'String','Belum ada eksperimen untuk disimpan.'); return;
    end
    out = fullfile(h.root, 'PABMASK_progress.mat');
    pabmask = i_progState(h); %#ok<NASGU>
    try
        save(out, 'pabmask');
        nOn = sum(arrayfun(@(e) e.enabled && ~isempty(e.rectFirst), h.list));
        set(h.status,'String', sprintf('Progress disimpan: %s (%d exp, %d ber-masking).', ...
            i_short(out), numel(h.list), nOn));
    catch ME
        set(h.status,'String', sprintf('Gagal simpan progress: %s', ME.message));
    end
end

function i_onLoadProgress(fig, ask)
%I_ONLOADPROGRESS  Muat <ROOT>/PABMASK_progress.mat. ask=true → bila berkas
%   default tak ada, tawarkan dialog; ask=false (auto-load saat scan) → diam
%   bila tak ada. Resep dipulihkan ke baris dengan file yang cocok.
    if nargin < 2, ask = true; end
    h = guidata(fig);
    def = fullfile(h.root, 'PABMASK_progress.mat');
    if isfile(def)
        pf = def;
    elseif ask
        try, pivui.minimizeForDialog(h.fig); catch, end %#ok<CTCH>
        [fn, fp] = uigetfile({'*.mat','Progress GRAINMASK (*.mat)'}, ...
            'Muat progress GRAINMASK', h.root);
        try, pivui.restoreAfterDialog(h.fig); catch, end %#ok<CTCH>
        if isequal(fn,0), return; end
        pf = fullfile(fp, fn);
    else
        return;
    end
    try
        S = load(pf);
    catch ME
        if ask, set(h.status,'String', sprintf('Gagal baca progress: %s', ME.message)); end
        return;
    end
    if ~isfield(S,'pabmask') || ~isfield(S.pabmask,'exps')
        if ask, set(h.status,'String','Berkas bukan progress GRAINMASK yang sah.'); end
        return;
    end
    saved = S.pabmask.exps;
    nApplied = 0;
    for i = 1:numel(h.list)
        idx = find(strcmp({saved.file}, h.list(i).file), 1);
        if isempty(idx), continue; end
        s = saved(idx);
        h.list(i).enabled   = logical(s.enabled);
        h.list(i).rectFirst = i_xywh(s.rectFirst);
        h.list(i).rectLast  = i_xywh(s.rectLast);
        if isfield(s,'keyframes'), h.list(i).keyframes = i_kfFromSaved(s.keyframes); end
        if isfield(s,'fill') && ~isempty(s.fill), h.list(i).fill = s.fill; end
        h.list(i).dirty = ~isequal( ...
            i_recipeKey(h.list(i).enabled, h.list(i).rectFirst, h.list(i).rectLast, ...
                        h.list(i).fill, h.list(i).keyframes), ...
            h.list(i).orig);
        nApplied = nApplied + 1;
    end
    guidata(fig, h);
    i_refreshTable(fig);
    if h.activeRow >= 1 && h.activeRow <= numel(h.list), i_loadActive(fig); end
    set(h.status,'String', sprintf('Progress dimuat: %d/%d exp dipulihkan dari %s', ...
        nApplied, numel(h.list), i_short(pf)));
end

function pabmask = i_progState(h)
%I_PROGSTATE  Struct ringkas state GRAINMASK (resep per-exp) untuk disimpan.
    flds = {'file','name','nFrames','enabled','rectFirst','rectLast','keyframes','fill','dirty'};
    se = struct();
    for i = numel(h.list):-1:1
        for f = flds
            se(i).(f{1}) = h.list(i).(f{1});
        end
    end
    pabmask = struct('type','PABMASKProgress','version',1, ...
        'root', h.root, 'exps', se, ...
        'savedAt', char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
end

% =====================================================================
%  Label / info / util
% =====================================================================
function i_updateRectLabel(fig)
    h = guidata(fig);
    if h.activeRow < 1, set(h.txtRect,'String',''); return; end
    e = h.list(h.activeRow);
    if strcmp(h.viewMode,'preview')
        if ~isempty(h.roi) && isvalid(h.roi)
            r = h.roi.Position;
            set(h.txtRect,'String', sprintf('kotak KF f%d: x=%d y=%d w=%d h=%d', ...
                h.previewFrame, round(r(1)), round(r(2)), round(r(3)), round(r(4))));
        else
            set(h.txtRect,'String', sprintf('frame %d (interpolasi — Tarik kotak utk keyframe)', ...
                h.previewFrame));
        end
        return;
    end
    if strcmp(h.editTarget,'last'), r = e.rectLast; lbl = 'akhir';
    else,                            r = e.rectFirst; lbl = 'awal'; end
    if isempty(r)
        set(h.txtRect,'String', sprintf('kotak %s: (belum ada)', lbl));
    else
        set(h.txtRect,'String', sprintf('kotak %s: x=%d y=%d w=%d h=%d', ...
            lbl, round(r(1)), round(r(2)), round(r(3)), round(r(4))));
    end
end

function i_updatePreviewLabel(fig)
    h = guidata(fig);
    if h.activeRow < 1, set(h.txtPrev,'String',''); return; end
    set(h.txtPrev,'String', sprintf('frame %d / %d', ...
        h.previewFrame, max(1,h.list(h.activeRow).nFrames)));
end

function i_updateInfo(fig)
    h = guidata(fig);
    i_updatePreviewLabel(fig);
    if h.activeRow < 1, return; end
    e = h.list(h.activeRow);
    if e.enabled && ~isempty(e.rectFirst)
        st = 'AKTIF';
    elseif e.enabled
        st = 'aktif (kotak belum lengkap)';
    else
        st = 'nonaktif';
    end
    set(h.status,'String', sprintf('%s — masking: %s', e.name, st));
end

function i_clearViewer(fig)
    h = guidata(fig);
    i_deleteRoi(h); i_deleteOvl(h);
    h.imgFirst = []; h.imgLast = []; h.imSz = []; h.imh = [];
    h.imgPrev = []; h.prevLoaded = 0;
    h.viewMode = 'first'; h.roi = []; h.ovl = [];
    cla(h.ax); set(h.ax,'XTick',[],'YTick',[]);
    set(h.txtExp,'String','(pilih eksperimen di kiri)');
    set(h.txtRect,'String',''); set(h.txtPrev,'String','');
    set(h.chkEnable,'Value',0);
    try, set(h.kfTbl,'Data',{}); catch, end %#ok<CTCH>
    guidata(fig,h);
end

function i_onChangeRoot(fig)
    h = guidata(fig);
    try, pivui.minimizeForDialog(h.fig); catch, end %#ok<CTCH>
    nd = uigetdir(h.root, 'Pilih folder berisi .mat PREP');
    try, pivui.restoreAfterDialog(h.fig); catch, end %#ok<CTCH>
    if isequal(nd, 0), return; end
    h.root = nd; guidata(fig,h);
    i_scan(fig);
end

function i_onClose(fig)
    h = guidata(fig);
    dirtyN = 0; if ~isempty(h.list), dirtyN = sum([h.list.dirty]); end
    if dirtyN > 0
        q = questdlg(sprintf(['%d eksperimen punya masking belum disimpan. ' ...
            'Tutup?'], dirtyN), 'Tutup GRAIN Masking', ...
            'Simpan aktif & tutup','Tutup tanpa simpan','Batal', 'Simpan aktif & tutup');
        switch q
            case 'Simpan aktif & tutup'
                i_onSaveActive(fig);
            case 'Batal'
                return;
            otherwise
                if isempty(q), return; end
        end
    end
    delete(fig);
end

function i_onTransferToStep2(fig)
%I_ONTRANSFERTOSTEP2  Pola SIMPAN-TUTUP-LANJUT. Tujuan bergantung MODE sumber:
%   'jpg' (urutan baru GRAIN0->GRAINMASK->GRAIN1): lanjut ke GRAIN1 (hitung jitter +
%          produksi MAT PREP; resep masking dari progres terpadu ditulis sbg
%          sidecar di samping MAT PREP saat produksi -> ter-decode GRAIN2).
%   'mat' (alur lama GRAIN1->GRAINMASK->GRAIN2): lanjut ke GRAIN2 (produksi MAT PIV;
%          masking ter-decode dari sidecar, blob asli utuh).
    h = guidata(fig);
    isJpg = strcmp(h.srcMode,'jpg');
    if isempty(h.list)
        set(h.status,'String','Belum ada eksperimen. Pindai folder dulu.'); return;
    end

    % (1) Bila ada resep belum disimpan, tawarkan simpan dulu (agar hilir memakai
    %     kotak terbaru).
    dirtyN = sum([h.list.dirty]);
    if dirtyN > 0
        if isJpg; tujuan = 'GRAIN1 (Step 1)'; else; tujuan = 'Step 2'; end
        q = questdlg(sprintf(['%d eksperimen punya masking belum disimpan. ' ...
            'Simpan sebelum lanjut ke %s?'], dirtyN, tujuan), 'Transfer', ...
            'Simpan aktif & lanjut','Lanjut tanpa simpan','Batal', 'Simpan aktif & lanjut');
        switch q
            case 'Simpan aktif & lanjut'
                i_onSaveActive(fig);
                h = guidata(fig);         % refresh (i_onSaveActive ubah state)
            case 'Batal'
                return;
            otherwise
                if isempty(q), return; end % tutup dialog = batal
        end
    end

    % (2) Simpan progress GRAINMASK per-folder (tanpa dialog) — jejak lintas sesi.
    try, i_onSaveProgress(fig); h = guidata(fig); catch, end %#ok<CTCH>

    root = h.root;
    if isempty(root) || ~isfolder(root)
        set(h.status,'String','Folder tidak valid — modul lanjut tak diluncurkan.');
        return;
    end

    % (3) TUTUP GRAINMASK, lalu (4) LANJUT ke modul berikut.
    if isJpg
        set(h.status,'String','Meluncurkan GRAIN1 (jitter + produksi MAT PREP)…'); drawnow;
        try, delete(fig); catch, end %#ok<CTCH>
        try
            GRAIN1(root);
        catch ME
            warning('GRAINMASK:openStep1', 'GRAIN1 gagal dibuka utk %s: %s', root, ME.message);
        end
    else
        set(h.status,'String','Meluncurkan Step 2 (GRAIN2)…'); drawnow;
        try, delete(fig); catch, end %#ok<CTCH>
        try
            GRAIN2(root, true);          % autoSave=true: pindai + simpan progres otomatis
        catch ME
            warning('GRAINMASK:openStep2', 'MAT PREP di %s tapi GRAIN2 gagal dibuka: %s', ...
                root, ME.message);
        end
    end
end

function i_onTransferToMask2(fig)
%I_ONTRANSFERTOMASK2  Transfer ke GRAINMASK2 (PLACEHOLDER — project masa depan).
%   GRAINMASK2 = masking area dgn POLYGON yang berubah bentuk setiap saat +
%   indikator KEYFRAME (belum dibuat). Pola SIMPAN-TUTUP-LANJUT sama seperti
%   Transfer->GRAIN2: bila fungsi GRAINMASK2 sudah ada di path -> simpan progress,
%   tutup, buka GRAINMASK2(root). Bila belum ada -> beri tahu "segera hadir".
    h = guidata(fig);
    if isempty(h.list)
        set(h.status,'String','Belum ada MAT PREP. Pindai folder dulu.'); return;
    end

    % Belum tersedia: GRAINMASK2 belum dibuat -> info, jangan transfer.
    if isempty(which('GRAINMASK2'))
        msg = ['GRAINMASK2 belum tersedia.' newline newline ...
               'Rencana: masking AREA dengan POLYGON yang berubah bentuk ' ...
               'setiap saat (bukan kotak), plus indikator KEYFRAME untuk ' ...
               'menandai bentuk pada frame kunci lalu diinterpolasi.'];
        try
            uiwait(msgbox(msg, 'Transfer → GRAINMASK2 (segera hadir)', 'help', 'modal'));
        catch
            set(h.status,'String','GRAINMASK2 belum tersedia (polygon + keyframe — segera).');
        end
        return;
    end

    % (sudah ada di masa depan) Pola SIMPAN-TUTUP-LANJUT ke GRAINMASK2.
    dirtyN = sum([h.list.dirty]);
    if dirtyN > 0
        q = questdlg(sprintf(['%d eksperimen punya masking belum disimpan. ' ...
            'Simpan sebelum lanjut ke GRAINMASK2?'], dirtyN), 'Transfer ke GRAINMASK2', ...
            'Simpan aktif & lanjut','Lanjut tanpa simpan','Batal', 'Simpan aktif & lanjut');
        switch q
            case 'Simpan aktif & lanjut'
                i_onSaveActive(fig); h = guidata(fig);
            case 'Batal'
                return;
            otherwise
                if isempty(q), return; end
        end
    end
    try, i_onSaveProgress(fig); h = guidata(fig); catch, end %#ok<CTCH>
    root = h.root;
    if isempty(root) || ~isfolder(root)
        set(h.status,'String','Folder MAT PREP tidak valid — GRAINMASK2 tak diluncurkan.');
        return;
    end
    set(h.status,'String','Meluncurkan GRAINMASK2…'); drawnow;
    try, delete(fig); catch, end %#ok<CTCH>
    try
        GRAINMASK2(root);
    catch ME
        warning('GRAINMASK:openMask2', 'GRAINMASK2 gagal dibuka: %s', ME.message);
    end
end

% --------------------------- helper murni ---------------------------
function h = i_markDirty(h)
    r = h.activeRow;
    e = h.list(r);
    key = i_recipeKey(e.enabled, e.rectFirst, e.rectLast, e.fill, e.keyframes);
    h.list(r).dirty = ~isequal(key, e.orig);
end

function k = i_recipeKey(en, rf, rl, fl, kf)
%I_RECIPEKEY  Kunci pembanding dirty (resep ter-bulat agar stabil).
%   kf (opsional) = keyframe TENGAH; ikut di-hash agar edit keyframe menandai dirty.
    if nargin < 5, kf = []; end
    k = struct('en',logical(en), 'rf',i_rkey(rf), 'rl',i_rkey(rl), ...
        'fl',round(fl), 'kf',i_kfkey(kf));
end

function r = i_rkey(rect)
    if isempty(rect) || numel(rect) ~= 4, r = []; else, r = round(double(rect(:)).'); end
end

function m = i_kfkey(kf)
%I_KFKEY  Matriks [frame_index x y w h] ter-bulat & terurut (kunci dirty stabil).
    m = [];
    if isempty(kf) || ~isstruct(kf); return; end
    rows = zeros(numel(kf), 5);
    for i = 1:numel(kf)
        rc = i_rkey(kf(i).rect); if isempty(rc), rc = [0 0 0 0]; end
        rows(i,:) = [round(double(kf(i).frame_index)), rc];
    end
    m = sortrows(rows, 1);
end

function r = i_xywh(rect)
    if isempty(rect) || numel(rect) ~= 4, r = []; else, r = double(rect(:)).'; end
end

function box = i_boxStruct(e, nF)
    rl = e.rectLast; if isempty(rl), rl = e.rectFirst; end
    box = struct('rect_first',e.rectFirst(:).','rect_last',rl(:).', ...
        'frame_first',1,'frame_last',max(2,nF), ...
        'keyframes',{e.keyframes});   % {..} cegah broadcast struct-array
end

function rect = i_clampRect(rect, imSz)
%I_CLAMPRECT  Jepit [x y w h] ke dalam [1..W]x[1..H]; w,h minimal 1.
    if isempty(rect) || numel(rect) ~= 4, rect = []; return; end
    rect = double(rect(:)).';
    if isempty(imSz), return; end
    H = imSz(1); W = imSz(2);
    x = max(1, rect(1)); y = max(1, rect(2));
    w = max(1, rect(3)); hgt = max(1, rect(4));
    if x + w - 1 > W, w = max(1, W - x + 1); end
    if y + hgt - 1 > H, hgt = max(1, H - y + 1); end
    rect = [x y w hgt];
end

function i_deleteRoi(h)
    if isfield(h,'roi') && ~isempty(h.roi)
        try, if isvalid(h.roi), delete(h.roi); end; catch, end %#ok<CTCH>
    end
end

function i_deleteOvl(h)
    if isfield(h,'ovl') && ~isempty(h.ovl)
        try, if isgraphics(h.ovl), delete(h.ovl); end; catch, end %#ok<CTCH>
    end
end

function v = i_field(s, name, dflt)
    v = dflt;
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name)), v = s.(name); end
end

function s = i_short(p)
    p = char(p);
    if numel(p) <= 48, s = p; return; end
    s = ['…' p(end-46:end)];
end


% =====================================================================
%  Progress bar VERBOSE — supaya tak pernah ada fase "diam tanpa info".
%  i_progOpen  : buka/pakai-ulang waitbar (tema terang), set judul.
%  i_progStep  : update fraksi 0..1 + pesan detail (langsung tampak).
%  i_progClose : tutup waitbar.
%  Setiap pemanggil membungkus operasi lambat (baca .mat, pindai folder,
%  decode frame) dengan open→step…→close, dan SELALU close di catch.
% =====================================================================
function wb = i_progOpen(fig, titleStr, msg)
    if nargin < 3 || isempty(msg), msg = 'Menyiapkan…'; end
    wb = [];
    try
        h = guidata(fig);
        msg = i_msgSafe(msg);
        if isfield(h,'wb') && ~isempty(h.wb) && isgraphics(h.wb)
            wb = h.wb;                       % pakai-ulang bila masih hidup
            waitbar(0, wb, msg);
            set(wb, 'Name', titleStr);
        else
            wb = waitbar(0, msg, 'Name', titleStr);
        end
        try, set(wb,'Color',[1 1 1]); catch, end %#ok<CTCH>
        i_progNoTex(wb);                     % path Windows (H:\...) jangan ditafsir TeX
        h.wb = wb; guidata(fig, h);
        drawnow limitrate;
    catch
        wb = [];
    end
end

function i_progStep(fig, frac, msg)
    try
        h = guidata(fig);
        if ~isfield(h,'wb') || isempty(h.wb) || ~isgraphics(h.wb), return; end
        frac = max(0, min(1, frac));
        if nargin >= 3 && ~isempty(msg)
            waitbar(frac, h.wb, i_msgSafe(msg));
            i_progNoTex(h.wb);
        else
            waitbar(frac, h.wb);
        end
        drawnow limitrate;
    catch
    end
end

function s = i_msgSafe(s)
%I_MSGSAFE  Pesan waitbar aman: satu baris, tanpa karakter yang memicu TeX.
%   Path Windows (mis H:\IDRIVE\...\F\M) mengandung '\I','\F','\M' yang ditafsir
%   waitbar sebagai perintah LaTeX -> "valid interpreter syntax" error/crash.
%   Kita paksa Interpreter='none' pada label (i_progNoTex), TAPI newline pun bisa
%   memicu warna default callback; ganti newline dgn spasi utk stabil.
    s = char(s);
    s = regexprep(s, '[\r\n]+', '  ');
end

function i_progNoTex(wb)
%I_PROGNOTEX  Paksa label teks di dalam waitbar TIDAK ditafsir sbg TeX/LaTeX,
%   supaya backslash path Windows (H:\...) tak dianggap perintah interpreter.
    try
        t = findall(wb, 'Type', 'text');
        if ~isempty(t), set(t, 'Interpreter', 'none'); end
    catch
    end
end

function i_progClose(fig)
    try
        h = guidata(fig);
        if isfield(h,'wb') && ~isempty(h.wb) && isgraphics(h.wb)
            delete(h.wb);
        end
        h.wb = []; guidata(fig, h);
    catch
    end
end
