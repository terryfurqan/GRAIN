function MATPIVEDIT(rootDir)
%MATPIVEDIT  Penyunting + QC MAT PIV (output Step 2) — GUI 3 kolom gaya PAB4.
%
%   MATPIVEDIT                % dialog pilih folder berisi .mat PIV
%   MATPIVEDIT(rootDir)       % langsung ke folder ROOT (scan otomatis)
%
%   Satu app untuk MERAWAT berkas MAT PIV yang SUDAH ADA (output Step 2) TANPA
%   menjalankan ulang PIV. Menumpang kerangka BERSAMA `pivui.pab4Shell` (dipakai
%   PAB3/PAB4/PAB5) sehingga visualizer QC (bidang skalar 2D velmag/shear + latar
%   GS + glyph + axPOT + garis PSG + slider frame) TERPAKAI ULANG apa adanya —
%   bukan ditulis ulang. Tema TERANG dipaksa, font hitam (bawaan shell).
%
%   TATA LETAK (3 kolom, dari pab4Shell):
%     KIRI   : tabel berkas .mat PIV (+ kolom Strain% & ✎/masking).
%     TENGAH : axMain (bidang skalar 2D velmag/shear + GS + glyph) di atas,
%              axPOT (kurva POT sepanjang garis PSG) di bawah, + slider frame
%              -> QC SEMUA frame satu-per-satu untuk cari frame error.
%     KANAN  : panel tab MATPIVEDIT —
%              ① Geometri  : ubah X0 / X1 / L_pos (cm) + garis L kosmetik;
%                            Simpan -> recompute strain (pivGeomIO), backup .bak.
%              ② Hapus Frame: tandai frame error (dari slider / daftar) lalu
%                            Simpan -> buang FISIK dari blob (dropframes) + .bak.
%              ③ Masking   : gambar kotak putih (rect_first/rect_last) -> simpan
%                            ke sidecar <nama>_mask.json (engine maskRect).
%
%   Semua operasi berat lewat engine `pivanalyzemat.core.matpivEdit` (perekat
%   tipis atas pivGeomIO / PIVlab_automasi_dropframes / maskSidecar) — GUI ramping.
%
%   CATATAN masking pada MAT PIV: kotak masking BERMAKNA saat PIV dihitung
%   (Step 1/2). Pada MAT PIV, PIV sudah jadi -> sidecar <nama>_mask.json di sini
%   berfungsi sebagai CATATAN region (QC / dipakai ulang bila kembali ke PREP
%   dengan nama sepadan). Latar GS untuk menggambar kotak dibaca dari MAT PIV.
%
%   Lihat memori [[matpivedit-geom-editor]], [[pab-step4-ecosystem]],
%   [[pabmask-nondestructive-masking]], [[pab-step2-mat-input]].

    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivanalyzemat.core.pivGeomIO'))
        addpath(here);
    end
    if isempty(which('pivui.pab4Shell'))
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
    end

    if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
        rootDir = uigetdir(pwd, ...
            'Pilih folder berisi .mat PIV (output Step 2 / PIV_<tgl>/)');
        if isequal(rootDir, 0), return; end
    end

    % --- Bangun kerangka bersama (3 kolom) ---
    opts = struct();
    opts.Name       = pivui.titleWithVersion('MAT PIV Editor — QC · Geometri · Hapus Frame · Masking');
    opts.rightTitle = 'Penyunting MAT PIV';
    opts.hooks = struct( ...
        'onExpLoaded',     @i_onExpLoaded, ...
        'afterRenderMain', @i_afterRenderMain, ...
        'onFrameChanged',  @i_onFrameChanged);
    h = pivui.pab4Shell.build(opts);

    % --- State khusus MATPIVEDIT (di atas state shell) ---
    h.me = i_defaultMeState();
    h.expTableExtra = @(f) i_expExtra(h.fig, f);   % kolom kiri: +Strain% +Δframe +mask

    % --- Isi panel kanan dgn 3 tab ---
    h = i_buildRightTabs(h);

    guidata(h.fig, h);
    set(h.fig, 'CloseRequestFcn', @(s,e) i_onClose(s));

    % Folder + pindai (auto-load exp pertama via shell).
    pivui.pab4Shell.setRoot(h.fig, rootDir);
end

% =====================================================================
%  State khusus MATPIVEDIT
% =====================================================================
function me = i_defaultMeState()
    me = struct();
    me.file    = '';           % path .mat aktif
    me.nF      = 0;            % jumlah frame aktif
    me.geom0   = [NaN NaN NaN];% [X0 X1 Lpos] LAMA (untuk deteksi dirty)
    me.dropSet = [];           % indeks frame ditandai error (1-based, uint)
    me.boxes   = {};           % kotak masking = cell of struct('first',[xywh],'last',[xywh]) DATA
    me.activeBox = 0;          % indeks kotak AKTIF (ROI interaktif)
    me.activeRoi = [];         % handle ROI kotak aktif (regen tiap render)
    me.maskDirty = false;      % ada perubahan kotak belum disimpan
    % garis L kosmetik (ukur posisi dinding pendorong relatif metran)
    me.lines   = {};           % handle ROI garis bantu (regen tiap render)
    me.lShape  = [];           % garis L aktif (handle)
    me.lData   = {};           % geometri garis (cell of Nx2 [x y]) — DATA yg bertahan
end

% =====================================================================
%  Panel kanan: uitabgroup 3 tab
% =====================================================================
function h = i_buildRightTabs(h)
    WHITE = [1 1 1];
    h.tg = uitabgroup('Parent', h.pnlR, 'Units','normalized', ...
        'Position',[0.01 0.01 0.98 0.98]);

    % ---------- TAB ① Geometri ----------
    tG = uitab('Parent',h.tg,'Title','① Geometri','BackgroundColor',WHITE);
    h.me_txtExp = uicontrol('Parent',tG,'Style','text','Units','normalized', ...
        'Position',[0.04 0.93 0.92 0.055],'HorizontalAlignment','left', ...
        'FontWeight','bold','FontSize',11,'BackgroundColor',WHITE, ...
        'ForegroundColor',[0 0 0],'String','(pilih eksperimen di kiri)');

    % X0 / X1 / L_pos
    lab = {'X0','X1','L_pos'};
    yfld = [0.85 0.77 0.69];
    h.me_edGeom = gobjects(1,3);
    for k = 1:3
        uicontrol('Parent',tG,'Style','text','Units','normalized', ...
            'Position',[0.04 yfld(k) 0.16 0.05],'String',lab{k}, ...
            'FontWeight','bold','HorizontalAlignment','left', ...
            'BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
        h.me_edGeom(k) = uicontrol('Parent',tG,'Style','edit','Units','normalized', ...
            'Position',[0.22 yfld(k) 0.30 0.055],'String','', ...
            'BackgroundColor',WHITE,'ForegroundColor',[0 0 0], ...
            'Callback',@(s,e) i_onEditGeom(ancestor(s,'figure')));
    end
    % nudge X0 & X1
    nb = {'X0 −0,1',{1,-0.10}; 'X0 −0,05',{1,-0.05}; 'X0 +0,05',{1,0.05}; 'X0 +0,1',{1,0.10}; ...
          'X1 −0,1',{2,-0.10}; 'X1 −0,05',{2,-0.05}; 'X1 +0,05',{2,0.05}; 'X1 +0,1',{2,0.10}};
    for k = 1:8
        col = mod(k-1,4); rowk = floor((k-1)/4);
        spec = nb{k,2};
        uicontrol('Parent',tG,'Style','pushbutton','Units','normalized', ...
            'Position',[0.55 + col*0.11, 0.83 - rowk*0.08, 0.105, 0.06], ...
            'String',nb{k,1},'FontSize',8, ...
            'Callback',@(s,e) i_bumpGeom(ancestor(s,'figure'), spec{1}, spec{2}));
    end
    % strain live
    h.me_txtStrain = uicontrol('Parent',tG,'Style','text','Units','normalized', ...
        'Position',[0.04 0.58 0.92 0.07],'HorizontalAlignment','left', ...
        'FontSize',10,'BackgroundColor',WHITE,'ForegroundColor',[0 0 0], ...
        'String','strain: —');

    % --- garis L kosmetik (QC dinding pendorong) ---
    pL = uipanel('Parent',tG,'Units','normalized','Position',[0.03 0.34 0.94 0.22], ...
        'Title','Garis L (kosmetik — ukur dinding pendorong)', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    uicontrol('Parent',pL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.68 0.30 0.28],'String','⌐ Garis L', ...
        'BackgroundColor',[0.96 0.93 0.86], ...
        'TooltipString','Munculkan garis L (A-B-C) di axMain — KOSMETIK.', ...
        'Callback',@(s,e) i_spawnL(ancestor(s,'figure')));
    uicontrol('Parent',pL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.35 0.68 0.34 0.28],'String','✏️ 2–3 titik', ...
        'BackgroundColor',[0.96 0.93 0.86], ...
        'Callback',@(s,e) i_drawLine(ancestor(s,'figure')));
    uicontrol('Parent',pL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.71 0.68 0.26 0.28],'String','🧹 Hapus', ...
        'Callback',@(s,e) i_clearLines(ancestor(s,'figure')));
    uicontrol('Parent',pL,'Style','text','Units','normalized', ...
        'Position',[0.03 0.36 0.20 0.24],'String','A-B px','FontSize',8, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'HorizontalAlignment','left');
    h.me_lenF = uicontrol('Parent',pL,'Style','edit','Units','normalized', ...
        'Position',[0.24 0.36 0.20 0.30],'String','300', ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0], ...
        'Callback',@(s,e) i_updateL(ancestor(s,'figure')));
    uicontrol('Parent',pL,'Style','text','Units','normalized', ...
        'Position',[0.48 0.36 0.18 0.24],'String','Sudut°','FontSize',8, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'HorizontalAlignment','left');
    h.me_angF = uicontrol('Parent',pL,'Style','edit','Units','normalized', ...
        'Position',[0.66 0.36 0.20 0.30],'String','220', ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0], ...
        'Callback',@(s,e) i_updateL(ancestor(s,'figure')));
    nud = {'◄',[-10 0]; '▲',[0 -10]; '▼',[0 10]; '►',[10 0]};
    for k = 1:4
        d = nud{k,2};
        uicontrol('Parent',pL,'Style','pushbutton','Units','normalized', ...
            'Position',[0.03 + (k-1)*0.245, 0.03, 0.22, 0.28], ...
            'String',nud{k,1},'TooltipString','Geser garis L 10 px.', ...
            'Callback',@(s,e) i_nudgeL(ancestor(s,'figure'), d(1), d(2)));
    end

    % tombol simpan geometri
    h.me_btnSaveGeom = uicontrol('Parent',tG,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.24 0.44 0.08],'String','💾 Simpan Geometri', ...
        'FontWeight','bold','BackgroundColor',[0.83 0.94 0.83], ...
        'TooltipString','Recompute strain (pivGeomIO) + backup .bak lalu tulis geom ke MAT PIV.', ...
        'Callback',@(s,e) i_onSaveGeom(ancestor(s,'figure')));
    uicontrol('Parent',tG,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.24 0.44 0.08],'String','🗄 Backup (.bak)', ...
        'BackgroundColor',[0.96 0.94 0.82], ...
        'Callback',@(s,e) i_onBackup(ancestor(s,'figure')));

    % ---------- TAB ② Hapus Frame ----------
    tD = uitab('Parent',h.tg,'Title','② Hapus Frame','BackgroundColor',WHITE);
    uicontrol('Parent',tD,'Style','text','Units','normalized', ...
        'Position',[0.04 0.92 0.92 0.06],'HorizontalAlignment','left', ...
        'FontSize',9,'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2], ...
        'String',['Scrub frame di tengah untuk cari frame ERROR, lalu tandai. ' ...
        'Simpan = buang FISIK dari blob (backup .bak dibuat).']);
    uicontrol('Parent',tD,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.84 0.60 0.065],'String','⚑ Tandai frame ini (dari slider)', ...
        'BackgroundColor',[0.98 0.90 0.86],'FontWeight','bold', ...
        'TooltipString','Tandai frame yang sedang tampil di axMain sebagai error.', ...
        'Callback',@(s,e) i_markCurrentFrame(ancestor(s,'figure')));
    uicontrol('Parent',tD,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 0.84 0.30 0.065],'String','✖ Batalkan', ...
        'TooltipString','Hapus tanda error dari frame terpilih di daftar.', ...
        'Callback',@(s,e) i_unmarkSelected(ancestor(s,'figure')));
    h.me_lstDrop = uicontrol('Parent',tD,'Style','listbox','Units','normalized', ...
        'Position',[0.04 0.26 0.92 0.55],'Max',2,'Min',0, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'FontSize',9, ...
        'TooltipString','Klik baris -> lompat ke frame itu di axMain. Tekan "✖ Batalkan" untuk lepas tanda.', ...
        'Callback',@(s,e) i_onPickDrop(ancestor(s,'figure')));
    h.me_txtDrop = uicontrol('Parent',tD,'Style','text','Units','normalized', ...
        'Position',[0.04 0.20 0.92 0.05],'HorizontalAlignment','left', ...
        'FontSize',9,'BackgroundColor',WHITE,'ForegroundColor',[0.6 0.2 0.2], ...
        'String','0 frame ditandai.');
    h.me_btnDrop = uicontrol('Parent',tD,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.09 0.92 0.09],'String','🗑 Buang frame ditandai → Simpan MAT PIV', ...
        'FontWeight','bold','BackgroundColor',[0.95 0.80 0.80], ...
        'TooltipString','Backup .bak lalu buang FISIK frame ditandai dari blob PIV+GS.', ...
        'Callback',@(s,e) i_onDropFrames(ancestor(s,'figure')));
    uicontrol('Parent',tD,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.01 0.92 0.07],'String','🧹 Bersihkan semua tanda', ...
        'Callback',@(s,e) i_clearDrop(ancestor(s,'figure')));

    % ---------- TAB ③ Masking ----------
    tM = uitab('Parent',h.tg,'Title','③ Masking','BackgroundColor',WHITE);
    uicontrol('Parent',tM,'Style','text','Units','normalized', ...
        'Position',[0.04 0.90 0.92 0.08],'HorizontalAlignment','left', ...
        'FontSize',9,'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2], ...
        'String',['Kotak putih NON-DESTRUKTIF (rect_first→rect_last). Gambar di ' ...
        'axMain, geser sudut untuk interpolasi awal↔akhir. Simpan → sidecar _mask.json.']);
    uicontrol('Parent',tM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.82 0.44 0.07],'String','▭ Tambah kotak', ...
        'BackgroundColor',[0.86 0.92 0.98],'FontWeight','bold', ...
        'TooltipString','Tarik satu kotak di axMain (dipakai untuk frame awal & akhir).', ...
        'Callback',@(s,e) i_addMaskBox(ancestor(s,'figure')));
    uicontrol('Parent',tM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.82 0.44 0.07],'String','🗑 Hapus terpilih', ...
        'Callback',@(s,e) i_delMaskBox(ancestor(s,'figure')));
    h.me_lstMask = uicontrol('Parent',tM,'Style','listbox','Units','normalized', ...
        'Position',[0.04 0.44 0.92 0.36],'Max',1,'Min',0, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'FontSize',9, ...
        'TooltipString','Daftar kotak (● = aktif/bisa diseret). Klik untuk mengaktifkan.', ...
        'Callback',@(s,e) i_onPickMask(ancestor(s,'figure')));
    uicontrol('Parent',tM,'Style','text','Units','normalized', ...
        'Position',[0.04 0.37 0.30 0.05],'String','Frame acuan awal/akhir:', ...
        'HorizontalAlignment','left','BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'FontSize',8);
    uicontrol('Parent',tM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.29 0.44 0.06],'String','⟸ Set rect_first = frame ini', ...
        'FontSize',8, ...
        'TooltipString','Jadikan kotak terpilih sebagai bentuk di frame AWAL (dari slider).', ...
        'Callback',@(s,e) i_setMaskRef(ancestor(s,'figure'), 'first'));
    uicontrol('Parent',tM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.29 0.44 0.06],'String','rect_last = frame ini ⟹', ...
        'FontSize',8, ...
        'TooltipString','Jadikan kotak terpilih sebagai bentuk di frame AKHIR (dari slider).', ...
        'Callback',@(s,e) i_setMaskRef(ancestor(s,'figure'), 'last'));
    h.me_chkMaskPrev = uicontrol('Parent',tM,'Style','checkbox','Units','normalized', ...
        'Position',[0.04 0.22 0.92 0.05],'String','Pratinjau tempel putih di axMain', ...
        'Value',0,'BackgroundColor',WHITE,'ForegroundColor',[0 0 0], ...
        'TooltipString','Tampilkan efek masking (isi putih) pada frame tampil.', ...
        'Callback',@(s,e) pivui.pab4Shell.renderMain(ancestor(s,'figure')));
    h.me_btnSaveMask = uicontrol('Parent',tM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.11 0.92 0.09],'String','💾 Simpan masking → sidecar _mask.json', ...
        'FontWeight','bold','BackgroundColor',[0.83 0.94 0.83], ...
        'Callback',@(s,e) i_onSaveMask(ancestor(s,'figure')));
    uicontrol('Parent',tM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.02 0.92 0.07],'String','🧹 Hapus sidecar masking', ...
        'BackgroundColor',[0.97 0.90 0.86], ...
        'TooltipString','Nonaktifkan masking total (hapus _mask.json).', ...
        'Callback',@(s,e) i_onClearMaskSidecar(ancestor(s,'figure')));
end

% =====================================================================
%  HOOKS shell
% =====================================================================
function i_onExpLoaded(fig)
%I_ONEXPLOADED  Eksperimen baru dimuat -> isi geometri + reset drop/mask + kolom.
    h = guidata(fig);
    e = h.list(h.activeRow);
    h.me.file = e.file;
    h.me.nF   = e.nFrames;
    h.me.dropSet = [];
    h.me.lines = {}; h.me.lShape = []; h.me.lData = {};
    % kotak masking baru per-eksperimen (dimuat dari sidecar di bawah).
    h.me.boxes = {}; h.me.activeBox = 0; h.me.activeRoi = [];
    h.me.maskDirty = false;
    guidata(fig, h);

    i_loadGeomFields(fig);
    i_loadMaskFromSidecar(fig);
    i_refreshDropList(fig);
    i_refreshMaskList(fig);

    h = guidata(fig);
    set(h.me_txtExp, 'String', e.name);
    pivui.setStatus(fig, sprintf(['Aktif: %s (%d frame). Scrub untuk QC; ' ...
        'edit di panel kanan.'], e.name, e.nFrames));
end

function i_afterRenderMain(fig)
%I_AFTERRENDERMAIN  axMain baru digambar — shell memanggil cla(ax) yang MENGHAPUS
%   semua child axMain termasuk ROI kita. Jadi gambar ULANG kotak masking + garis
%   L dari STATE tersimpan (bukan handle lama), lalu pratinjau tempel putih.
    h = guidata(fig);
    if isempty(h.data), return; end
    i_redrawMaskROIs(fig);
    i_redrawLROIs(fig);
    try
        if isgraphics(h.me_chkMaskPrev) && get(h.me_chkMaskPrev,'Value')
            i_drawMaskPreview(fig);
        end
    catch
    end
end

function i_onFrameChanged(fig)
%I_ONFRAMECHANGED  Frame di-scrub. Overlay (kotak/garis L/preview) digambar ulang
%   oleh afterRenderMain saat renderMain jalan; tak ada aksi tambahan di sini.
end

% =====================================================================
%  Kolom kiri EXTRA: Strain% + #tandai + mask
% =====================================================================
function vals = i_expExtra(fig, dataFile)
%I_EXPEXTRA  Nilai kolom extra tabel kiri per-eksperimen (atau nama kolom).
    if ischar(dataFile) && strcmp(dataFile, '__names__')
        vals = {'Strain%','mask'};
        return;
    end
    vals = {'',''};
    try
        g = pivanalyzemat.core.matpivEdit.readGeom(dataFile);
        if g.valid, vals{1} = sprintf('%+.3g', g.strain_cumm_pct); else, vals{1} = '—'; end
    catch
        vals{1} = '—';
    end
    try
        if pivanalyzemat.core.maskSidecar.has(dataFile), vals{2} = '▭'; end
    catch
    end
end

% =====================================================================
%  TAB ① Geometri
% =====================================================================
function i_loadGeomFields(fig)
    h = guidata(fig);
    g = pivanalyzemat.core.matpivEdit.readGeom(h.me.file);
    h.me.geom0 = [g.X0_cm g.X1_cm g.Lpos_cm];
    guidata(fig, h);
    set(h.me_edGeom(1), 'String', i_num2str(g.X0_cm));
    set(h.me_edGeom(2), 'String', i_num2str(g.X1_cm));
    set(h.me_edGeom(3), 'String', i_num2str(g.Lpos_cm));
    i_updateStrainLive(fig);
end

function i_onEditGeom(fig)
    i_updateStrainLive(fig);
    i_markGeomDirty(fig);
end

function i_bumpGeom(fig, idx, delta)
    h = guidata(fig);
    v = i_str2num(get(h.me_edGeom(idx),'String'));
    if ~isfinite(v), v = 0; end
    set(h.me_edGeom(idx), 'String', i_num2str(round(v + delta, 4)));
    i_onEditGeom(fig);
end

function i_updateStrainLive(fig)
    h = guidata(fig);
    X0 = i_str2num(get(h.me_edGeom(1),'String'));
    X1 = i_str2num(get(h.me_edGeom(2),'String'));
    Lp = i_str2num(get(h.me_edGeom(3),'String'));
    g = pivanalyze.geom.computeGeometry(X0, X1, Lp);
    if g.valid
        set(h.me_txtStrain,'String', sprintf(['strain = %+.4g %%  (%s)   ' ...
            'L0=%.4g  L1=%.4g  dL=%.4g cm'], g.strain_cumm_pct, g.mode, ...
            g.L0_cm, g.L1_cm, g.dL_cm), 'ForegroundColor',[0 0 0]);
    else
        set(h.me_txtStrain,'String', ...
            'strain: —  (X0/X1/L_pos belum lengkap atau L0≤0)', ...
            'ForegroundColor',[0.6 0.2 0.2]);
    end
end

function i_markGeomDirty(fig)
    h = guidata(fig);
    cur = [i_str2num(get(h.me_edGeom(1),'String')), ...
           i_str2num(get(h.me_edGeom(2),'String')), ...
           i_str2num(get(h.me_edGeom(3),'String'))];
    dirty = ~isequaln(cur, h.me.geom0);
    if dirty, set(h.me_btnSaveGeom,'String','💾 Simpan Geometri ✎');
    else,     set(h.me_btnSaveGeom,'String','💾 Simpan Geometri'); end
end

function i_onSaveGeom(fig)
    h = guidata(fig);
    if isempty(h.me.file), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    X0 = i_str2num(get(h.me_edGeom(1),'String'));
    X1 = i_str2num(get(h.me_edGeom(2),'String'));
    Lp = i_str2num(get(h.me_edGeom(3),'String'));
    try
        [g, bak] = pivanalyzemat.core.matpivEdit.writeGeom(h.me.file, X0, X1, Lp, true);
        h.me.geom0 = [X0 X1 Lp]; guidata(fig, h);
        i_markGeomDirty(fig);
        pivui.pab4Shell.fillTable(fig);   % kolom Strain% ikut segar
        pivui.setStatus(fig, sprintf('Geometri tersimpan: strain %+.4g%% (%s). Backup=%s', ...
            g.strain_cumm_pct, g.mode, i_short(bak)));
    catch ME
        pivui.setStatus(fig, sprintf('Gagal simpan geometri: %s', ME.message));
    end
end

function i_onBackup(fig)
    h = guidata(fig);
    if isempty(h.me.file), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    try
        [bak, made] = pivanalyzemat.core.matpivEdit.backup(h.me.file);
        if made, pivui.setStatus(fig, sprintf('Backup dibuat: %s', i_short(bak)));
        else,    pivui.setStatus(fig, 'Backup gagal.'); end
    catch ME
        pivui.setStatus(fig, sprintf('Backup gagal: %s', ME.message));
    end
end

% =====================================================================
%  TAB ② Hapus Frame
% =====================================================================
function i_markCurrentFrame(fig)
    h = guidata(fig);
    if isempty(h.me.file), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    k = h.frame;
    if ~isfinite(k) || k < 1, return; end
    h.me.dropSet = unique([h.me.dropSet(:); round(k)]);
    guidata(fig, h);
    i_refreshDropList(fig);
end

function i_unmarkSelected(fig)
    h = guidata(fig);
    sel = get(h.me_lstDrop,'Value');
    d = h.me.dropSet;
    sel = sel(sel >= 1 & sel <= numel(d));
    if isempty(sel), return; end
    d(sel) = [];
    h.me.dropSet = d; guidata(fig, h);
    i_refreshDropList(fig);
end

function i_clearDrop(fig)
    h = guidata(fig);
    h.me.dropSet = []; guidata(fig, h);
    i_refreshDropList(fig);
end

function i_onPickDrop(fig)
    h = guidata(fig);
    sel = get(h.me_lstDrop,'Value');
    if isempty(sel) || sel(1) < 1 || sel(1) > numel(h.me.dropSet), return; end
    k = h.me.dropSet(sel(1));
    pivui.pab4Shell.gotoFrame(fig, k);   % lompat ke frame itu di axMain utk verifikasi
end

function i_refreshDropList(fig)
    h = guidata(fig);
    d = sort(h.me.dropSet(:));
    C = cell(numel(d),1);
    for i = 1:numel(d), C{i} = sprintf('Frame %d', d(i)); end
    set(h.me_lstDrop, 'String', C, 'Value', min(max(1,get(h.me_lstDrop,'Value')), max(1,numel(d))));
    if isempty(d)
        set(h.me_txtDrop,'String','0 frame ditandai.');
    else
        set(h.me_txtDrop,'String', sprintf('%d frame ditandai (dari %d). Sisa %d.', ...
            numel(d), h.me.nF, max(0, h.me.nF - numel(d))));
    end
end

function i_onDropFrames(fig)
    h = guidata(fig);
    if isempty(h.me.file), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    d = unique(round(h.me.dropSet(:)));
    d = d(d >= 1 & d <= h.me.nF);
    if isempty(d), pivui.setStatus(fig,'Belum ada frame ditandai.'); return; end
    if numel(d) >= h.me.nF
        pivui.setStatus(fig,'Semua frame akan terbuang — dibatalkan.'); return;
    end
    q = questdlg(sprintf(['Buang %d frame (dari %d) SECARA FISIK dari blob PIV+GS?\n' ...
        'Backup .bak dibuat lebih dulu. Tindakan ini menimpa berkas .mat.'], ...
        numel(d), h.me.nF), 'Buang Frame', 'Buang','Batal','Batal');
    if ~strcmp(q,'Buang'), return; end

    set(fig,'Pointer','watch'); drawnow;
    cleaner = onCleanup(@() set(fig,'Pointer','arrow')); %#ok<NASGU>
    try
        info = pivanalyzemat.core.matpivEdit.dropFrames(h.me.file, d, true);
        pivui.setStatus(fig, sprintf(['Terbuang %d frame; sisa %d. Backup=%s. ' ...
            'Memuat ulang…'], info.nDrop, info.nKept, i_short(info.bak)));
        % Reset tanda + muat ulang eksperimen (jumlah frame berubah).
        h = guidata(fig); h.me.dropSet = []; guidata(fig, h);
        i_reloadActive(fig);
    catch ME
        pivui.setStatus(fig, sprintf('Gagal buang frame: %s', ME.message));
    end
end

function i_reloadActive(fig)
%I_RELOADACTIVE  Muat ulang eksperimen aktif (mis. setelah frame dibuang) —
%   segarkan probe (jumlah frame) lalu loadExperiment lewat shell.
    h = guidata(fig);
    row = h.activeRow;
    if row < 1 || row > numel(h.list), return; end
    try
        [meta, ok] = pivanalyzemat.core.probePivMat(h.list(row).file);
        if ok
            h.list(row).nFrames = meta.nFrames;
            h.list(row).sizeMB  = meta.sizeMB;
            guidata(fig, h);
        end
    catch
    end
    pivui.pab4Shell.fillTable(fig);
    pivui.pab4Shell.loadExperiment(fig, row);
end

% =====================================================================
%  TAB ③ Masking (kotak) — ROI di axMain -> sidecar _mask.json
% =====================================================================
function i_addMaskBox(fig)
%I_ADDMASKBOX  Tarik satu kotak di axMain -> simpan geometrinya sebagai DATA
%   (rect_first=rect_last), lalu jadikan kotak AKTIF (ROI hidup utk diedit).
    h = guidata(fig);
    if isempty(h.data), pivui.setStatus(fig,'Muat eksperimen dulu.'); return; end
    ax = h.axMain;
    try, zoom(ax,'off'); pan(ax,'off'); catch, end %#ok<CTCH>
    try
        roi = drawrectangle(ax, 'Color',[0.15 0.5 0.95], 'FaceAlpha',0.10, ...
            'LineWidth',1.5, 'Label','mask');
    catch ME
        pivui.setStatus(fig, sprintf('Gagal buat kotak: %s', ME.message)); return;
    end
    if isempty(roi) || ~isvalid(roi) || any(roi.Position(3:4) < 2)
        try, delete(roi); catch, end %#ok<CTCH>
        return;
    end
    pos = roi.Position;
    try, delete(roi); catch, end %#ok<CTCH>   % handle sementara; kotak aktif digambar ulang
    h = guidata(fig);
    h.me.boxes{end+1} = struct('first',pos, 'last',pos);   % DATA (bukan handle)
    h.me.activeBox = numel(h.me.boxes);
    h.me.maskDirty = true;
    guidata(fig, h);
    set(h.me_lstMask, 'Value', h.me.activeBox);
    i_refreshMaskList(fig);
    i_redrawMaskROIs(fig);
    pivui.setStatus(fig, sprintf('Kotak masking #%d ditambah (aktif — geser untuk edit).', ...
        numel(h.me.boxes)));
end

function i_onPickMask(fig)
%I_ONPICKMASK  Klik baris daftar -> jadikan kotak itu AKTIF (bisa diseret).
    h = guidata(fig);
    sel = get(h.me_lstMask,'Value');
    if isempty(sel) || sel < 1 || sel > numel(h.me.boxes), return; end
    h.me.activeBox = sel; guidata(fig, h);
    i_refreshMaskList(fig);
    i_redrawMaskROIs(fig);
end

function i_delMaskBox(fig)
    h = guidata(fig);
    sel = get(h.me_lstMask,'Value');
    if isempty(sel) || sel < 1 || sel > numel(h.me.boxes), return; end
    h.me.boxes(sel) = [];
    if h.me.activeBox == sel, h.me.activeBox = min(sel, numel(h.me.boxes)); end
    if h.me.activeBox < 1 && ~isempty(h.me.boxes), h.me.activeBox = 1; end
    h.me.maskDirty = true;
    guidata(fig, h);
    i_refreshMaskList(fig);
    i_redrawMaskROIs(fig);
end

function i_setMaskRef(fig, which)
%I_SETMASKREF  Set rect_first / rect_last kotak AKTIF = posisi ROI hidup sekarang
%   (mengunci bentuk kotak pada frame awal/akhir untuk interpolasi).
    h = guidata(fig);
    sel = get(h.me_lstMask,'Value');
    if isempty(sel) || sel < 1 || sel > numel(h.me.boxes)
        pivui.setStatus(fig,'Pilih kotak di daftar dulu.'); return;
    end
    pos = i_activeRoiPos(h, sel);
    if isempty(pos), pivui.setStatus(fig,'Aktifkan kotak (klik di daftar) lalu geser.'); return; end
    b = h.me.boxes{sel};
    if strcmp(which,'first'), b.first = pos; else, b.last = pos; end
    h.me.boxes{sel} = b; h.me.maskDirty = true;
    guidata(fig, h);
    i_refreshMaskList(fig);
    pivui.setStatus(fig, sprintf('Kotak #%d: rect_%s diset ke frame %d.', sel, which, h.frame));
end

function pos = i_activeRoiPos(h, sel)
%I_ACTIVEROIPOS  Posisi ROI hidup kotak AKTIF (bila kotak sel adalah yg aktif &
%   handle valid), else []. Sinkronkan geometri dari yang sedang diseret user.
    pos = [];
    if isfield(h.me,'activeBox') && h.me.activeBox == sel ...
            && isfield(h.me,'activeRoi') && ~isempty(h.me.activeRoi) ...
            && isvalid(h.me.activeRoi)
        pos = h.me.activeRoi.Position;
    end
end

function i_refreshMaskList(fig)
    h = guidata(fig);
    n = numel(h.me.boxes);
    C = cell(n,1);
    for i = 1:n
        b = h.me.boxes{i};
        rf = b.first; rl = b.last;
        tag = ''; if isfield(h.me,'activeBox') && h.me.activeBox == i, tag = '● '; end
        if isequaln(round(rf), round(rl))
            C{i} = sprintf('%s#%d  [%.0f %.0f %.0f %.0f] statis', tag, i, rf(1),rf(2),rf(3),rf(4));
        else
            C{i} = sprintf('%s#%d  awal[%.0f %.0f %.0f %.0f] → akhir[%.0f %.0f %.0f %.0f]', ...
                tag, i, rf(1),rf(2),rf(3),rf(4), rl(1),rl(2),rl(3),rl(4));
        end
    end
    set(h.me_lstMask, 'String', C, 'Value', min(max(1,get(h.me_lstMask,'Value')), max(1,n)));
end

function i_redrawMaskROIs(fig)
%I_REDRAWMASKROIS  Gambar ULANG kotak masking di axMain dari DATA tersimpan
%   (dipanggil tiap afterRenderMain karena cla menghapus ROI). Kotak AKTIF =
%   ROI interaktif (bisa diseret); lainnya = rectangle statis tipis (penanda).
%   Bentuk yang digambar = interpolasi pada frame tampil (first↔last).
    h = guidata(fig);
    % lepas handle ROI aktif lama (child axMain sudah terhapus cla; buang ref).
    h.me.activeRoi = [];
    ax = h.axMain; k = h.frame; N = max(2, h.me.nF);
    % buang penanda statis lama (bila render dipanggil tanpa cla penuh).
    try, delete(findobj(ax,'Tag','maskGhost')); catch, end %#ok<CTCH>
    if ~isfield(h.me,'activeBox'), h.me.activeBox = 0; end
    for i = 1:numel(h.me.boxes)
        b = h.me.boxes{i};
        pos = i_interpBoxPos(b, k, N);   % [x y w h] pada frame tampil
        if i == h.me.activeBox
            try
                roi = drawrectangle(ax, 'Position', pos, 'Color',[0.15 0.5 0.95], ...
                    'FaceAlpha',0.10, 'LineWidth',1.8, 'Label',sprintf('mask#%d',i), ...
                    'InteractionsAllowed','all');
                addlistener(roi, 'MovingROI', @(s,e) i_onMaskRoiMove(fig, i));
                addlistener(roi, 'ROIMoved',  @(s,e) i_onMaskRoiMove(fig, i));
                h.me.activeRoi = roi;
            catch
            end
        else
            rectangle('Parent',ax,'Position',pos, 'EdgeColor',[0.2 0.55 0.95], ...
                'LineStyle','--','LineWidth',1.0,'Tag','maskGhost');
        end
    end
    guidata(fig, h);
end

function i_onMaskRoiMove(fig, i)
%I_ONMASKROIMOVE  ROI kotak aktif diseret -> perbarui DATA kotak (statis:
%   first=last=posisi; jika sudah punya first≠last, geser first pada frame awal).
    h = guidata(fig);
    if i < 1 || i > numel(h.me.boxes), return; end
    if isempty(h.me.activeRoi) || ~isvalid(h.me.activeRoi), return; end
    pos = h.me.activeRoi.Position;
    b = h.me.boxes{i};
    if isequaln(round(b.first), round(b.last))
        b.first = pos; b.last = pos;   % kotak statis -> keduanya ikut
    else
        % kotak interpolasi: seret memperbarui ujung terdekat frame tampil.
        if h.frame <= (1 + h.me.nF)/2, b.first = pos; else, b.last = pos; end
    end
    h.me.boxes{i} = b; h.me.maskDirty = true;
    guidata(fig, h);
end

function pos = i_interpBoxPos(b, k, N)
%I_INTERPBOXPOS  [x y w h] kotak b pada frame k (linear first->last, clamp).
    if N <= 1, t = 0; else, t = max(0, min(1, (k-1)/(N-1))); end
    pos = b.first + t * (b.last - b.first);
end

function m = i_buildMaskingStruct(fig)
%I_BUILDMASKINGSTRUCT  Rakit struct maskRect dari DATA kotak GUI. rect [x y w h].
%   Sinkron dulu posisi ROI aktif ke DATA (bila user sedang menyeret).
    h = guidata(fig);
    % sinkron kotak aktif dari ROI hidup.
    if isfield(h.me,'activeBox') && h.me.activeBox >= 1 ...
            && h.me.activeBox <= numel(h.me.boxes) ...
            && isfield(h.me,'activeRoi') && ~isempty(h.me.activeRoi) && isvalid(h.me.activeRoi)
        i_onMaskRoiMove(fig, h.me.activeBox);
        h = guidata(fig);
    end
    boxes = struct('rect_first',{},'rect_last',{}, ...
                   'frame_first',{},'frame_last',{},'keyframes',{});
    for i = 1:numel(h.me.boxes)
        b = h.me.boxes{i};
        rf = b.first; rl = b.last;
        if any(rf(3:4) < 1) || any(rl(3:4) < 1), continue; end
        boxes(end+1) = struct('rect_first',rf,'rect_last',rl, ...
            'frame_first',1,'frame_last',NaN,'keyframes',[]); %#ok<AGROW>
    end
    nRef = max(2, h.me.nF);
    m = pivanalyzemat.core.matpivEdit.maskFromBoxes(boxes, 255, nRef);
end

function i_onSaveMask(fig)
    h = guidata(fig);
    if isempty(h.me.file), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
    m = i_buildMaskingStruct(fig);
    try
        ok = pivanalyzemat.core.matpivEdit.writeMask(h.me.file, m);
        if ok
            h.me.maskDirty = false; guidata(fig, h);
            pivui.pab4Shell.fillTable(fig);   % kolom mask ▭ ikut segar
            nb = 0; if pivanalyzemat.core.maskRect.isActive(m), nb = numel(m.boxes); end
            pivui.setStatus(fig, sprintf('Masking tersimpan (%d kotak) → %s_mask.json', ...
                nb, i_baseOnly(h.me.file)));
        else
            pivui.setStatus(fig, 'Gagal menulis sidecar masking.');
        end
    catch ME
        pivui.setStatus(fig, sprintf('Gagal simpan masking: %s', ME.message));
    end
end

function i_onClearMaskSidecar(fig)
    h = guidata(fig);
    if isempty(h.me.file), return; end
    q = questdlg('Hapus sidecar masking (_mask.json) untuk eksperimen ini?', ...
        'Hapus Masking', 'Hapus','Batal','Batal');
    if ~strcmp(q,'Hapus'), return; end
    pivanalyzemat.core.maskSidecar.remove(h.me.file);
    h.me.boxes = {}; h.me.activeBox = 0; h.me.activeRoi = []; h.me.maskDirty = false;
    guidata(fig, h);
    i_refreshMaskList(fig);
    pivui.pab4Shell.fillTable(fig);
    pivui.pab4Shell.renderMain(fig);   % afterRenderMain redraw (kini kosong)
    pivui.setStatus(fig, 'Sidecar masking dihapus (masking nonaktif).');
end

function i_loadMaskFromSidecar(fig)
%I_LOADMASKFROMSIDECAR  Muat kotak dari sidecar -> DATA (bukan handle); ROI
%   digambar oleh i_redrawMaskROIs saat render berikutnya.
    h = guidata(fig);
    h.me.boxes = {}; h.me.activeBox = 0; h.me.activeRoi = [];
    guidata(fig, h);

    m = [];
    try, m = pivanalyzemat.core.matpivEdit.readMask(h.me.file); catch, m = []; end
    if isempty(m) || ~pivanalyzemat.core.maskRect.isActive(m), return; end

    h = guidata(fig);
    for i = 1:numel(m.boxes)
        bx = m.boxes(i);
        h.me.boxes{end+1} = struct('first', bx.rect_first, 'last', bx.rect_last);
    end
    if ~isempty(h.me.boxes), h.me.activeBox = 1; end
    guidata(fig, h);
end

function i_drawMaskPreview(fig)
%I_DRAWMASKPREVIEW  Overlay patch putih di posisi kotak pada frame tampil
%   (visual QC efek masking; TIDAK mengubah data). Bersihkan preview lama dulu.
    h = guidata(fig);
    if isempty(h.me.boxes), return; end
    m = i_buildMaskingStruct(fig);
    if ~pivanalyzemat.core.maskRect.isActive(m), return; end
    ax = h.axMain; k = h.frame; N = max(2, h.me.nF);
    try, delete(findobj(ax,'Tag','maskPrev')); catch, end %#ok<CTCH>
    W = []; H = [];
    try, xl = get(ax,'XLim'); yl = get(ax,'YLim'); W = xl(2); H = yl(2); catch, end
    for i = 1:numel(m.boxes)
        bb = pivanalyzemat.core.matpivEdit.maskBoxAtFrame(m.boxes(i), k, N, W, H, m.n_ref);
        if isempty(bb), continue; end
        x = bb(1); y = bb(2); w = bb(3)-bb(1); hgt = bb(4)-bb(2);
        rectangle('Parent',ax,'Position',[x y w hgt], ...
            'FaceColor',[1 1 1],'EdgeColor',[0.6 0.6 0.6],'Tag','maskPrev');
    end
end

function i_redrawLROIs(fig)
%I_REDRAWLROIS  Garis L kosmetik = ROI Polyline yang juga terhapus cla. Kita
%   simpan geometri terakhir di DATA (h.me.lData) & gambar ulang. Bila belum ada
%   data (belum pernah spawn) -> no-op.
    h = guidata(fig);
    if ~isfield(h.me,'lData') || isempty(h.me.lData), return; end
    ax = h.axMain;
    h.me.lShape = []; h.me.lines = {};
    for i = 1:numel(h.me.lData)
        P = h.me.lData{i};
        if isempty(P) || size(P,1) < 2, continue; end
        try
            roi = images.roi.Polyline(ax, 'Position', P, ...
                'Color',[0.95 0.15 0.15], 'LineWidth',1.5);
            addlistener(roi, 'MovingROI', @(s,e) i_onLRoiMove(fig, i));
            addlistener(roi, 'ROIMoved',  @(s,e) i_onLRoiMove(fig, i));
            h.me.lines{end+1} = roi;
            if i == numel(h.me.lData), h.me.lShape = roi; end
        catch
        end
    end
    guidata(fig, h);
end

function i_onLRoiMove(fig, i)
    h = guidata(fig);
    if ~isfield(h.me,'lines') || i < 1 || i > numel(h.me.lines), return; end
    roi = h.me.lines{i};
    if isempty(roi) || ~isvalid(roi), return; end
    h.me.lData{i} = roi.Position;
    guidata(fig, h);
end

% =====================================================================
%  GARIS L kosmetik (port dari MATPIVEDIT lama, adaptasi axMain shell)
% =====================================================================
function pts = i_lPoints(fig, A)
    h = guidata(fig);
    Lab = 300; th = 220;
    v = i_str2num(get(h.me_lenF,'String')); if isfinite(v), Lab = max(1, v); end
    a = i_str2num(get(h.me_angF,'String')); if isfinite(a), th  = a; end
    thr = th * pi / 180;
    B = A + [0, Lab];
    C = B + Lab * [sin(thr), -cos(thr)];
    pts = [A; B; C];
end

function i_spawnL(fig)
    h = guidata(fig);
    if isempty(h.data), pivui.setStatus(fig,'Muat eksperimen dulu.'); return; end
    ax = h.axMain;
    try, zoom(ax,'off'); pan(ax,'off'); catch, end %#ok<CTCH>
    xl = get(ax,'XLim'); yl = get(ax,'YLim');
    A = [xl(1) + 0.42*diff(xl), yl(1) + 0.30*diff(yl)];
    pts = i_lPoints(fig, A);
    h.me.lData{end+1} = pts;    % DATA (bertahan cla); ROI digambar oleh redraw
    guidata(fig, h);
    i_redrawLROIs(fig);
end

function i_drawLine(fig)
    h = guidata(fig);
    if isempty(h.data), pivui.setStatus(fig,'Muat eksperimen dulu.'); return; end
    ax = h.axMain;
    try, zoom(ax,'off'); pan(ax,'off'); catch, end %#ok<CTCH>
    try
        roi = drawpolyline(ax, 'Color',[0.95 0.15 0.15], 'LineWidth',1.5);
        if isempty(roi) || ~isvalid(roi), return; end
        P = roi.Position;
        try, delete(roi); catch, end %#ok<CTCH>
        if size(P,1) > 3, P = P(1:3,:); end
        if size(P,1) < 2, return; end
        h.me.lData{end+1} = P; guidata(fig, h);
        i_redrawLROIs(fig);
    catch ME
        pivui.setStatus(fig, sprintf('Gagal tarik garis: %s', ME.message));
    end
end

function i_updateL(fig)
%I_UPDATEL  Param A-B/sudut berubah -> perbarui garis L AKTIF (data + ROI).
    h = guidata(fig);
    if isempty(h.me.lData), return; end
    i = numel(h.me.lData);                 % garis terakhir = aktif
    P = h.me.lData{i};
    if isempty(P), return; end
    h.me.lData{i} = i_lPoints(fig, P(1,:));
    guidata(fig, h);
    i_redrawLROIs(fig);
end

function i_nudgeL(fig, dx, dy)
    h = guidata(fig);
    if isempty(h.me.lData)
        pivui.setStatus(fig,'Belum ada garis L.'); return;
    end
    i = numel(h.me.lData);
    P = h.me.lData{i};
    if isempty(P), return; end
    h.me.lData{i} = P + [dx, dy];
    guidata(fig, h);
    i_redrawLROIs(fig);
end

function i_clearLines(fig)
    h = guidata(fig);
    for k = 1:numel(h.me.lines)
        try, if isvalid(h.me.lines{k}), delete(h.me.lines{k}); end; catch, end %#ok<CTCH>
    end
    h.me.lines = {}; h.me.lShape = []; h.me.lData = {};
    guidata(fig, h);
end

% =====================================================================
%  Tutup (prompt bila ada geometri / masking belum disimpan)
% =====================================================================
function i_onClose(fig)
    h = guidata(fig);
    dirty = false;
    try
        cur = [i_str2num(get(h.me_edGeom(1),'String')), ...
               i_str2num(get(h.me_edGeom(2),'String')), ...
               i_str2num(get(h.me_edGeom(3),'String'))];
        dirty = dirty || ~isequaln(cur, h.me.geom0);
    catch
    end
    try, dirty = dirty || h.me.maskDirty; catch, end
    if dirty
        q = questdlg('Ada perubahan (geometri / masking) belum disimpan. Tutup?', ...
            'Tutup MAT PIV Editor', 'Tutup','Batal', 'Batal');
        if ~strcmp(q,'Tutup'), return; end
    end
    delete(fig);
end

% =====================================================================
%  Util numerik / teks
% =====================================================================
function s = i_num2str(v)
    if isempty(v) || ~isnumeric(v) || ~isfinite(v), s = ''; return; end
    s = sprintf('%.4g', double(v));
end

function v = i_str2num(s)
    s = strtrim(char(s));
    if isempty(s), v = NaN; return; end
    s = strrep(s, ',', '.');
    x = str2double(s);
    if isnan(x), v = NaN; else, v = x; end
end

function s = i_short(p)
    p = char(p);
    if isempty(p), s = '(tak ada)'; return; end
    if numel(p) <= 48, s = p; return; end
    s = ['…' p(end-46:end)];
end

function s = i_baseOnly(p)
    [~, b] = fileparts(char(p));
    s = b;
end
