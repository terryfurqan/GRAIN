function PABLINK(refFile, tgtFile)
%PABLINK  Pengikat strain antar-view — MENGIKAT 2 MAT PIV: view ACUAN (penampang
%   P1, geometri X0/X1/Lpos diketahui = strain Truth) dengan view TARGET (tampak
%   peta M, tanpa geometri). Hasil: sidecar "georeferensi" `<tgt_base>_link.json`.
%
%   PABLINK                      % pilih 2 MAT lewat tombol 📂
%   PABLINK(refFile, tgtFile)    % praedukasi langsung (acuan, target)
%
%   CARA KERJA. Peristiwa sesar yang sama (FSR pertama & FSR terakhir) terlihat di
%   kedua view pada momen fisik yang sama → strain yang sama. Scrub kedua viewer
%   (PIV velmag + GS) untuk memvalidasi kapan FSR terbentuk, lalu tandai frame-nya
%   di tiap view. Strain titik ikat dihitung OTOMATIS dari geometri acuan
%   (linear: sRef(f)=(f-1)/(nF-1)*strainTotalPct, bertanda). Dengan 2 titik ikat,
%   strain seluruh frame view peta dikalibrasi linear (interp + ekstrapolasi).
%
%   Penafsir/penampil-bersamaan = PABSYNC (baca sidecar yang sama).
%   Engine murni: pivcore.io.pabLink. Viewer bersama: pivui.linkView.
%   Tema TERANG dipaksa (idiom figure+uicontrol klasik, sama MATPIVEDIT/PABEXPORT).

    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivcore.io.pabLink'))
        pivc = fullfile(here, 'pivcore_lib');
        if isfolder(pivc), addpath(pivc); end
        addpath(here);
    end

    h = struct();
    h.refFile = '';
    h.tgtFile = '';
    h.lastDir = pwd;
    h.doc     = pivcore.io.pabLink.emptyDoc('','');
    h.pnRef   = [];
    h.pnTgt   = [];
    h.faultsDoc = pivcore.io.pab5Faults.emptyDoc('');   % FSR penampang (Tab ②)
    h.pabRoot   = here;                                  % root utk folder PABLINK_export
    h.exportDir = '';                                    % override folder ekspor (kosong = pabRoot)

    h = i_buildUI(h);
    guidata(h.fig, h);

    % Praedukasi opsional.
    if nargin >= 1 && ~isempty(refFile) && ischar(refFile) && isfile(refFile)
        i_loadFile(h.fig, 'ref', refFile);
    end
    if nargin >= 2 && ~isempty(tgtFile) && ischar(tgtFile) && isfile(tgtFile)
        i_loadFile(h.fig, 'tgt', tgtFile);
    end
end

% =====================================================================
%  UI — KIRI kontrol (sempit), KANAN dua viewer berdampingan (lebar)
% =====================================================================
function h = i_buildUI(h)
    WHITE = [1 1 1];
    vis = 'on'; try, if pivui.quiet(), vis = 'off'; end; catch, end %#ok<CTCH>
    h.fig = figure('Name',pivui.titleWithVersion('PAB Link — Pengikat strain penampang ↔ peta'), ...
        'NumberTitle','off','Color',WHITE, ...
        'Units','pixels','Position',[50 50 1400 800], ...
        'MenuBar','none','ToolBar','none','Visible',vis, ...
        'CloseRequestFcn',@(s,e) i_onClose(s));
    try, pivui.forceLightTheme(h.fig); catch, end %#ok<CTCH>
    fig = h.fig;

    % ================= KIRI: kontrol (tabgroup 2 tab) =================
    h.tg = uitabgroup('Parent',fig,'Units','normalized', ...
        'Position',[0.006 0.01 0.300 0.985]);
    h.tabIkat  = uitab('Parent',h.tg,'Title','① Ikat','BackgroundColor',WHITE);
    h.tabFault = uitab('Parent',h.tg,'Title','② Sesar & Ekspor','BackgroundColor',WHITE);
    pnlL = h.tabIkat;   % semua kontrol ikat lama tinggal di Tab ①

    % --- pemilih berkas ---
    pFile = uipanel('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.74 0.94 0.245],'Title','Berkas (2 MAT PIV)', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    uicontrol('Parent',pFile,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.80 0.62 0.16],'String','📂 Acuan (penampang)…', ...
        'BackgroundColor',[0.85 0.90 0.98],'FontWeight','bold', ...
        'Callback',@(s,e) i_onPick(fig,'ref'));
    h.txtRef = uicontrol('Parent',pFile,'Style','text','Units','normalized', ...
        'Position',[0.66 0.80 0.32 0.16],'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2],'String','(belum)');
    h.lblRef = uicontrol('Parent',pFile,'Style','text','Units','normalized', ...
        'Position',[0.03 0.62 0.95 0.16],'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'String','—');
    uicontrol('Parent',pFile,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.40 0.62 0.16],'String','📂 Target (tampak peta)…', ...
        'BackgroundColor',[0.98 0.92 0.85],'FontWeight','bold', ...
        'Callback',@(s,e) i_onPick(fig,'tgt'));
    h.txtTgt = uicontrol('Parent',pFile,'Style','text','Units','normalized', ...
        'Position',[0.66 0.40 0.32 0.16],'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2],'String','(belum)');
    h.lblTgt = uicontrol('Parent',pFile,'Style','text','Units','normalized', ...
        'Position',[0.03 0.22 0.95 0.16],'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'String','—');
    uicontrol('Parent',pFile,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.02 0.50 0.16],'String','⇄ Tukar acuan↔target', ...
        'TooltipString','Tukar peran (mis. geometri ternyata ada di berkas yang lain).', ...
        'Callback',@(s,e) i_onSwap(fig));

    % --- titik ikat ---
    pTie = uipanel('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.40 0.94 0.335],'Title','Titik ikat (FSR pertama & terakhir)', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    uicontrol('Parent',pTie,'Style','text','Units','normalized', ...
        'Position',[0.03 0.86 0.30 0.10],'String','Titik ikat:','FontSize',9, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'HorizontalAlignment','left');
    h.popTie = uicontrol('Parent',pTie,'Style','popupmenu','Units','normalized', ...
        'Position',[0.33 0.85 0.64 0.12],'String',i_tieNames(), ...
        'Callback',@(s,e) i_onTieSelect(fig));
    uicontrol('Parent',pTie,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.68 0.47 0.14],'String','⬇ Tandai dari penampang', ...
        'TooltipString','Ambil frame penampang aktif sebagai frame FSR (acuan).', ...
        'BackgroundColor',[0.88 0.93 0.99], ...
        'Callback',@(s,e) i_onMark(fig,'ref'));
    h.btnMarkTgt = uicontrol('Parent',pTie,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.68 0.47 0.14],'String','⬇ Tandai dari peta', ...
        'TooltipString','Ambil frame peta aktif sebagai frame FSR (target).', ...
        'BackgroundColor',[0.99 0.94 0.88], ...
        'Callback',@(s,e) i_onMark(fig,'tgt'));
    h.tblTie = uitable('Parent',pTie,'Units','normalized', ...
        'Position',[0.03 0.16 0.94 0.46], ...
        'ColumnName',{'Titik ikat','f penampang','strain%','f peta'}, ...
        'ColumnWidth',{96 78 70 60}, 'ColumnFormat',repmat({'char'},1,4), ...
        'ColumnEditable',false(1,4),'RowName',[],'FontSize',8,'Multiselect','off', ...
        'CellSelectionCallback',@(s,e) i_onTieRow(fig,e));
    uicontrol('Parent',pTie,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.02 0.47 0.12],'String','✗ Hapus tanda', ...
        'Callback',@(s,e) i_onClearTie(fig));
    uicontrol('Parent',pTie,'Style','text','Units','normalized', ...
        'Position',[0.51 0.01 0.47 0.13],'HorizontalAlignment','left','FontSize',7, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.4 0.4 0.4], ...
        'String','Klik baris → loncat ke frame.');

    % --- rasio sanity ---
    pRat = uipanel('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.235 0.94 0.16],'Title','Rasio strain/frame (sanity)', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    h.txtRatio = uicontrol('Parent',pRat,'Style','text','Units','normalized', ...
        'Position',[0.03 0.05 0.94 0.90],'HorizontalAlignment','left','FontSize',9, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0], ...
        'String',['Tandai 2 titik ikat untuk melihat rasio.' newline ...
                  '(laju akuisisi ~sama → rasio peta/penampang ≈ 1)']);

    % --- aksi ---
    h.btnSave = uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.155 0.62 0.06],'String','💾 Simpan ikatan', ...
        'FontWeight','bold','BackgroundColor',[0.83 0.94 0.83], ...
        'Callback',@(s,e) i_onSave(fig));
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 0.155 0.31 0.06],'String','✕ Tutup', ...
        'BackgroundColor',[0.97 0.86 0.86],'Callback',@(s,e) i_onClose(fig));
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.085 0.94 0.055],'String','▶ Buka di PABSYNC (penafsir)', ...
        'TooltipString','Simpan lalu buka penampil tersinkron (strain master).', ...
        'BackgroundColor',[0.90 0.90 0.98],'Callback',@(s,e) i_onGoSync(fig));

    h.status = uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
        'Position',[0.03 0.012 0.94 0.065],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2], ...
        'String','Pilih MAT penampang (acuan) & MAT peta (target).');

    % ============ Tab ②: SESAR (dari _faults.json) & EKSPOR ============
    tF = h.tabFault;

    % --- sesar ---
    pSes = uipanel('Parent',tF,'Units','normalized', ...
        'Position',[0.03 0.44 0.94 0.545],'Title','Sesar (FSR dari penampang)', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    h.btnLoadFaults = uicontrol('Parent',pSes,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.90 0.60 0.075],'String','📂 Muat _faults penampang', ...
        'TooltipString','Baca <base>_faults.json di samping MAT penampang (dibuat di PAB5).', ...
        'BackgroundColor',[0.88 0.93 0.99],'FontWeight','bold', ...
        'Callback',@(s,e) i_onLoadFaults(fig));
    h.txtFaultInfo = uicontrol('Parent',pSes,'Style','text','Units','normalized', ...
        'Position',[0.64 0.90 0.34 0.075],'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2],'String','(belum)');
    h.tblFault = uitable('Parent',pSes,'Units','normalized', ...
        'Position',[0.03 0.14 0.94 0.72], ...
        'ColumnName',{'Sesar','f pnp','strain%','f peta','status'}, ...
        'ColumnWidth',{60 56 66 56 70}, 'ColumnFormat',repmat({'char'},1,5), ...
        'ColumnEditable',false(1,5),'RowName',[],'FontSize',8,'Multiselect','off', ...
        'CellSelectionCallback',@(s,e) i_onFaultRow(fig,e));
    uicontrol('Parent',pSes,'Style','text','Units','normalized', ...
        'Position',[0.03 0.01 0.94 0.11],'HorizontalAlignment','left','FontSize',7, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.4 0.4 0.4], ...
        'String','Klik baris → kedua viewer loncat (penampang=FSR, peta=hasil kalibrasi).');

    % --- ekspor ---
    pExp = uipanel('Parent',tF,'Units','normalized', ...
        'Position',[0.03 0.10 0.94 0.325],'Title','Ekspor batch foto peta @ FSR', ...
        'FontWeight','bold','BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    h.chkGS = uicontrol('Parent',pExp,'Style','checkbox','Units','normalized', ...
        'Position',[0.03 0.80 0.46 0.15],'String','Foto GS asli','Value',1, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    h.chkPanel = uicontrol('Parent',pExp,'Style','checkbox','Units','normalized', ...
        'Position',[0.50 0.80 0.48 0.15],'String','Panel velmag+shear','Value',1, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0 0 0]);
    h.txtExpDir = uicontrol('Parent',pExp,'Style','text','Units','normalized', ...
        'Position',[0.03 0.60 0.72 0.14],'HorizontalAlignment','left','FontSize',7, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.3 0.3 0.3], ...
        'String', sprintf('Folder: %s/PABLINK_export/', i_short(h.pabRoot)));
    uicontrol('Parent',pExp,'Style','pushbutton','Units','normalized', ...
        'Position',[0.76 0.58 0.22 0.18],'String','📁 Pilih…', ...
        'Callback',@(s,e) i_onPickExportDir(fig));
    h.btnExportAll = uicontrol('Parent',pExp,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.30 0.60 0.22],'String','▶ Ekspor SEMUA sesar siap', ...
        'FontWeight','bold','BackgroundColor',[0.83 0.94 0.83],'Enable','off', ...
        'Callback',@(s,e) i_onExport(fig,'all'));
    h.btnExportSel = uicontrol('Parent',pExp,'Style','pushbutton','Units','normalized', ...
        'Position',[0.65 0.30 0.33 0.22],'String','▶ Sesar terpilih', ...
        'BackgroundColor',[0.90 0.96 0.90],'Enable','off', ...
        'Callback',@(s,e) i_onExport(fig,'sel'));
    h.txtExpStatus = uicontrol('Parent',pExp,'Style','text','Units','normalized', ...
        'Position',[0.03 0.02 0.95 0.24],'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2], ...
        'String','Kalibrasi valid + ≥1 sesar ber-FSR → tombol ekspor aktif.');

    h.selFaultId = '';   % id sesar terpilih (untuk ekspor "terpilih")

    % ================= KANAN: dua viewer =================
    pnlR = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.312 0.01 0.682 0.985],'BackgroundColor',WHITE,'BorderType','none');
    h.pnRef = pivui.linkView.build(pnlR, [0.005 0.01 0.492 0.985], ...
        'PENAMPANG (acuan) — (pilih MAT)');
    h.pnTgt = pivui.linkView.build(pnlR, [0.503 0.01 0.492 0.985], ...
        'TAMPAK PETA (target) — (pilih MAT)');
    set(h.pnRef.slider, 'Callback', @(s,e) i_onSlider(fig,'ref'));
    set(h.pnTgt.slider, 'Callback', @(s,e) i_onSlider(fig,'tgt'));

    % Simpan handle tombol "Tandai dari penampang" untuk tes (cari by string).
    h.btnMarkRef = findobj(pTie,'Style','pushbutton','String','⬇ Tandai dari penampang');
end

% =====================================================================
%  Pemilih berkas & muat
% =====================================================================
function i_onPick(fig, side)
    h = guidata(fig);
    try, pivui.minimizeForDialog(h.fig); catch, end %#ok<CTCH>
    [fn, fp] = uigetfile({'*.mat','MAT PIV (*.mat)'}, ...
        sprintf('Pilih MAT PIV — %s', i_sideLabel(side)), h.lastDir);
    try, pivui.restoreAfterDialog(h.fig); catch, end %#ok<CTCH>
    if isequal(fn,0), return; end
    i_loadFile(fig, side, fullfile(fp, fn));
end

function i_loadFile(fig, side, file)
    h = guidata(fig);
    h.lastDir = fileparts(file);
    [~, ok] = pivanalyzemat.core.probePivMat(file);
    if ~ok
        set(h.status,'String', sprintf('Bukan MAT PIV: %s', i_short(file)));
        guidata(fig,h); return;
    end
    set(h.status,'String', sprintf('Memuat %s…', i_short(file))); drawnow;
    try
        if strcmp(side,'ref')
            h.refFile = file;
            h.pnRef = pivui.linkView.loadMat(h.pnRef, file);
            set(h.pnRef.txtTitle, 'String', sprintf('PENAMPANG (acuan) — %s', i_baseOf(file)));
        else
            h.tgtFile = file;
            h.pnTgt = pivui.linkView.loadMat(h.pnTgt, file);
            set(h.pnTgt.txtTitle, 'String', sprintf('TAMPAK PETA (target) — %s', i_baseOf(file)));
        end
    catch ME
        set(h.status,'String', sprintf('GAGAL muat: %s', ME.message));
        guidata(fig,h); return;
    end
    guidata(fig, h);
    i_rebuildDoc(fig);
end

% Bangun ulang doc dari kedua berkas (restore tie dari sidecar target).
function i_rebuildDoc(fig)
    h = guidata(fig);
    if ~isempty(h.tgtFile)
        doc = pivcore.io.pabLink.read(h.tgtFile);    % restore tie bila ada
    else
        doc = pivcore.io.pabLink.emptyDoc('','');
    end

    % Identitas + geometri acuan.
    if ~isempty(h.refFile)
        gi = pivcore.io.pabLink.geomInfo(h.refFile);
        [~, rb] = fileparts(h.refFile);
        doc.reference.path           = h.refFile;
        doc.reference.basename       = rb;
        doc.reference.nFrames        = h.pnRef.nF;
        doc.reference.strainTotalPct = gi.strainTotalPct;
        doc.reference.geomValid      = gi.valid;
        doc.reference.X0_cm          = gi.X0_cm;
        doc.reference.X1_cm          = gi.X1_cm;
        doc.reference.Lpos_cm        = gi.Lpos_cm;
        set(h.txtRef,'String', sprintf('strain %s', i_pctStr(gi.strainTotalPct)));
        set(h.lblRef,'String', sprintf('%s  (%d frame, geom %s)', rb, h.pnRef.nF, ...
            i_validStr(gi.valid)));
    end
    % Identitas target.
    if ~isempty(h.tgtFile)
        gt = pivcore.io.pabLink.geomInfo(h.tgtFile);
        [~, tb] = fileparts(h.tgtFile);
        doc.target.path      = h.tgtFile;
        doc.target.basename  = tb;
        doc.target.nFrames   = h.pnTgt.nF;
        doc.target.geomValid = gt.valid;
        set(h.txtTgt,'String', sprintf('%d frame', h.pnTgt.nF));
        set(h.lblTgt,'String', sprintf('%s  (%d frame, geom %s)', tb, h.pnTgt.nF, ...
            i_validStr(gt.valid)));
    end

    doc = i_canonTies(doc);                    % pastikan 2 tie urut tetap
    doc = pivcore.io.pabLink.calibrate(doc);
    h.doc = doc;
    guidata(fig, h);

    i_refreshTie(fig);
    i_refreshRatio(fig);
    i_rerenderTgt(fig);
    i_rerenderRef(fig);

    % Tab ②: muat FSR penampang (bila refFile ada) + segarkan tabel sesar.
    if ~isempty(h.refFile), i_onLoadFaults(fig); else, i_refreshFaultTable(fig); end

    h = guidata(fig);
    if ~isempty(h.refFile) && ~isempty(h.tgtFile)
        gi = pivcore.io.pabLink.geomInfo(h.refFile);
        gt = pivcore.io.pabLink.geomInfo(h.tgtFile);
        if ~gi.valid && gt.valid
            set(h.status,'String', ...
                'Acuan tak punya geometri, tapi target punya → klik "⇄ Tukar".');
        elseif ~gi.valid
            set(h.status,'String', ...
                'Acuan belum punya geometri valid (X0/X1/Lpos). Isi di PAB2/MATPIVEDIT.');
        else
            set(h.status,'String', ...
                'Scrub kedua viewer ke FSR → Tandai. Lalu Simpan ikatan.');
        end
    end
end

function i_onSwap(fig)
    h = guidata(fig);
    if isempty(h.refFile) && isempty(h.tgtFile), return; end
    % Tukar identitas berkas; panel kiri tetap "penampang/acuan".
    rf = h.refFile; h.refFile = h.tgtFile; h.tgtFile = rf;
    guidata(fig, h);
    if ~isempty(h.refFile), i_loadFile(fig,'ref',h.refFile); end
    h = guidata(fig);
    if ~isempty(h.tgtFile), i_loadFile(fig,'tgt',h.tgtFile); end
    % Tukar membatalkan makna frame tie → kosongkan, lalu rebuild.
    h = guidata(fig);
    h.doc = i_canonTies(pivcore.io.pabLink.emptyDoc(h.refFile, h.tgtFile));
    guidata(fig, h);
    i_rebuildDoc(fig);
    h = guidata(fig);
    set(h.status,'String','Peran ditukar. Titik ikat lama dikosongkan.');
end

% =====================================================================
%  Slider / render
% =====================================================================
function i_onSlider(fig, side)
    h = guidata(fig);
    if strcmp(side,'ref')
        if isempty(h.refFile), return; end
        k = round(get(h.pnRef.slider,'Value'));
        h.pnRef = pivui.linkView.gotoFrame(h.pnRef, k, i_refStrain(h.doc, k));
    else
        if isempty(h.tgtFile), return; end
        k = round(get(h.pnTgt.slider,'Value'));
        h.pnTgt = pivui.linkView.gotoFrame(h.pnTgt, k, i_tgtStrain(h.doc, k));
    end
    guidata(fig, h);
end

function i_rerenderRef(fig)
    h = guidata(fig);
    if isempty(h.refFile), return; end
    h.pnRef = pivui.linkView.render(h.pnRef, i_refStrain(h.doc, h.pnRef.frame));
    guidata(fig, h);
end

function i_rerenderTgt(fig)
    h = guidata(fig);
    if isempty(h.tgtFile), return; end
    h.pnTgt = pivui.linkView.render(h.pnTgt, i_tgtStrain(h.doc, h.pnTgt.frame));
    guidata(fig, h);
end

function s = i_refStrain(doc, k)
    s = pivcore.io.pabLink.strainAtRef(doc, k);   % NaN bila geom invalid
end
function s = i_tgtStrain(doc, k)
    s = pivcore.io.pabLink.strainAtTgt(doc, k);   % NaN bila belum kalibrasi
end

% =====================================================================
%  Titik ikat
% =====================================================================
function i_onMark(fig, side)
    h = guidata(fig);
    name = i_activeTieName(fig);
    [tie, ~] = i_findTie(h.doc, name);
    if isempty(tie), tie = pivcore.io.pabLink.tieStruct(name, NaN, NaN, NaN); end
    if strcmp(side,'ref')
        if isempty(h.refFile)
            set(h.status,'String','Belum ada MAT penampang.'); return;
        end
        tie.refFrame = h.pnRef.frame;
        tie.refStrainPct = pivcore.io.pabLink.strainAtRef(h.doc, tie.refFrame);
    else
        if isempty(h.tgtFile)
            set(h.status,'String','Belum ada MAT peta.'); return;
        end
        tie.tgtFrame = h.pnTgt.frame;
    end
    h.doc = pivcore.io.pabLink.setTie(h.doc, tie);
    h.doc = i_canonTies(h.doc);
    h.doc = pivcore.io.pabLink.calibrate(h.doc);
    guidata(fig, h);
    i_refreshTie(fig); i_refreshRatio(fig); i_rerenderTgt(fig);
    i_refreshFaultTable(fig);   % kolom "f peta" ikut kalibrasi
    h = guidata(fig);
    set(h.status,'String', sprintf('Ditandai %s: %s.', name, i_sideLabel(side)));
end

function i_onClearTie(fig)
    h = guidata(fig);
    name = i_activeTieName(fig);
    tie = pivcore.io.pabLink.tieStruct(name, NaN, NaN, NaN);
    h.doc = pivcore.io.pabLink.setTie(h.doc, tie);
    h.doc = i_canonTies(h.doc);
    h.doc = pivcore.io.pabLink.calibrate(h.doc);
    guidata(fig, h);
    i_refreshTie(fig); i_refreshRatio(fig); i_rerenderTgt(fig);
    i_refreshFaultTable(fig);
end

function i_onTieSelect(fig)
    i_onTieRowGoto(fig);   % loncat ke frame tie terpilih (bila ada)
end

function i_onTieRow(fig, e)
    if isempty(e.Indices), return; end
    h = guidata(fig);
    set(h.popTie, 'Value', min(e.Indices(1), numel(i_tieNames())));
    guidata(fig, h);
    i_onTieRowGoto(fig);
end

function i_onTieRowGoto(fig)
    h = guidata(fig);
    name = i_activeTieName(fig);
    [tie, ~] = i_findTie(h.doc, name);
    if isempty(tie), return; end
    if ~isempty(h.refFile) && isfinite(tie.refFrame)
        h.pnRef = pivui.linkView.gotoFrame(h.pnRef, tie.refFrame, ...
            i_refStrain(h.doc, tie.refFrame));
    end
    if ~isempty(h.tgtFile) && isfinite(tie.tgtFrame)
        h.pnTgt = pivui.linkView.gotoFrame(h.pnTgt, tie.tgtFrame, ...
            i_tgtStrain(h.doc, tie.tgtFrame));
    end
    guidata(fig, h);
end

function i_refreshTie(fig)
    h = guidata(fig);
    names = i_tieNames();
    C = cell(numel(names),4);
    for i = 1:numel(names)
        [t, ~] = i_findTie(h.doc, names{i});
        C{i,1} = names{i};
        if isempty(t)
            C{i,2}='—'; C{i,3}='—'; C{i,4}='—';
        else
            C{i,2} = i_frStr(t.refFrame);
            C{i,3} = i_pctStr(t.refStrainPct);
            C{i,4} = i_frStr(t.tgtFrame);
        end
    end
    set(h.tblTie, 'Data', C);
end

function i_refreshRatio(fig)
    h = guidata(fig);
    cal = h.doc.calibration;
    rpf = cal.refStrainPerFrame; b = cal.slopePctPerFrame;
    if isfinite(rpf) && isfinite(b)
        rat = b / rpf;
        msg = sprintf(['penampang: %+.4g %%/frame\npeta: %+.4g %%/frame\n' ...
            'peta/penampang = %.3f  (ideal ≈ 1)'], rpf, b, rat);
        col = [0 0 0];
        if isfinite(rat) && (rat < 0.5 || rat > 2)
            col = [0.6 0.2 0.2];
            msg = [msg '  ⚠ jauh dari 1'];
        end
        set(h.txtRatio,'String',msg,'ForegroundColor',col);
    elseif isfinite(rpf)
        set(h.txtRatio,'String', sprintf(['penampang: %+.4g %%/frame\n' ...
            'peta: — (tandai 2 titik ikat lengkap)'], rpf),'ForegroundColor',[0 0 0]);
    else
        set(h.txtRatio,'String', ...
            ['Tandai 2 titik ikat untuk melihat rasio.' newline ...
             '(laju akuisisi ~sama → rasio peta/penampang ≈ 1)'], ...
            'ForegroundColor',[0.4 0.4 0.4]);
    end
end

% =====================================================================
%  Tab ②: Sesar (FSR penampang) & ekspor batch
% =====================================================================
function i_onLoadFaults(fig)
    h = guidata(fig);
    if isempty(h.refFile)
        set(h.txtFaultInfo,'String','(pilih penampang dulu)');
        return;
    end
    h.faultsDoc = pivcore.io.pab5Faults.read(h.refFile);
    guidata(fig, h);
    i_refreshFaultTable(fig);
    h = guidata(fig);
    n = 0; if isfield(h.faultsDoc,'faults'), n = numel(h.faultsDoc.faults); end
    if n == 0
        set(h.txtFaultInfo,'String','tak ada _faults.json (buat FSR di PAB5).', ...
            'ForegroundColor',[0.6 0.2 0.2]);
    else
        rows = pivcore.io.pabLinkExport.planRows(h.doc, h.faultsDoc);
        nReady = sum([rows.ready]);
        set(h.txtFaultInfo,'String', sprintf('%d sesar, %d siap ekspor', n, nReady), ...
            'ForegroundColor',[0.2 0.2 0.2]);
    end
end

function i_refreshFaultTable(fig)
    h = guidata(fig);
    if ~isfield(h,'tblFault') || ~ishghandle(h.tblFault), return; end
    rows = pivcore.io.pabLinkExport.planRows(h.doc, h.faultsDoc);
    C = cell(numel(rows), 5);
    for i = 1:numel(rows)
        r = rows(i);
        C{i,1} = r.faultId;
        C{i,2} = i_frStr(r.fsrRef);
        C{i,3} = i_pctStr(r.strainPct);
        C{i,4} = i_frStr(r.frameTgt);
        if r.ready
            if r.clamped, C{i,5} = '✓ (tepi)'; else, C{i,5} = '✓ siap'; end
        else
            C{i,5} = ['⚠ ' i_shortReason(r.reason)];
        end
    end
    set(h.tblFault, 'Data', C);
    guidata(fig, h);
    i_updateExportEnable(fig);
end

function i_onFaultRow(fig, e)
    if isempty(e.Indices), return; end
    h = guidata(fig);
    ridx = e.Indices(1);
    rows = pivcore.io.pabLinkExport.planRows(h.doc, h.faultsDoc);
    if ridx < 1 || ridx > numel(rows), return; end
    r = rows(ridx);
    h.selFaultId = r.faultId;
    % Penampang → frame FSR.
    if ~isempty(h.refFile) && isfinite(r.fsrRef)
        h.pnRef = pivui.linkView.gotoFrame(h.pnRef, r.fsrRef, ...
            pivcore.io.pabLink.strainAtRef(h.doc, r.fsrRef));
    end
    % Peta → frame hasil kalibrasi (bila siap).
    if ~isempty(h.tgtFile) && isfinite(r.frameTgt)
        h.pnTgt = pivui.linkView.gotoFrame(h.pnTgt, r.frameTgt, r.strainPct);
    end
    guidata(fig, h);
    if r.ready
        set(h.txtExpStatus,'String', sprintf('%s: FSR pnp f%d → peta f%d (strain %s).', ...
            r.faultId, r.fsrRef, r.frameTgt, i_pctStr(r.strainPct)), ...
            'ForegroundColor',[0.2 0.2 0.2]);
    else
        set(h.txtExpStatus,'String', sprintf('%s: %s', r.faultId, r.reason), ...
            'ForegroundColor',[0.6 0.2 0.2]);
    end
    i_updateExportEnable(fig);
end

function i_updateExportEnable(fig)
    h = guidata(fig);
    rows = pivcore.io.pabLinkExport.planRows(h.doc, h.faultsDoc);
    anyReady = ~isempty(rows) && any([rows.ready]);
    enAll = i_en(anyReady);
    selReady = false;
    if ~isempty(h.selFaultId)
        for i = 1:numel(rows)
            if strcmp(rows(i).faultId, h.selFaultId) && rows(i).ready, selReady = true; break; end
        end
    end
    if isfield(h,'btnExportAll') && ishghandle(h.btnExportAll)
        set(h.btnExportAll,'Enable',enAll);
    end
    if isfield(h,'btnExportSel') && ishghandle(h.btnExportSel)
        set(h.btnExportSel,'Enable', i_en(selReady));
    end
end

function i_onPickExportDir(fig)
    h = guidata(fig);
    try, pivui.minimizeForDialog(h.fig); catch, end %#ok<CTCH>
    d = uigetdir(i_defExportRoot(h), 'Folder induk untuk PABLINK_export/');
    try, pivui.restoreAfterDialog(h.fig); catch, end %#ok<CTCH>
    if isequal(d,0), return; end
    h.exportDir = d;
    guidata(fig, h);
    set(h.txtExpDir,'String', sprintf('Folder: %s/PABLINK_export/', i_short(d)));
end

function i_onExport(fig, mode)
    h = guidata(fig);
    if isempty(h.refFile) || isempty(h.tgtFile)
        set(h.txtExpStatus,'String','Pilih penampang & peta dulu.', ...
            'ForegroundColor',[0.6 0.2 0.2]); return;
    end
    [missing, why] = i_calibMissing(h.doc);
    if missing
        set(h.txtExpStatus,'String', sprintf('Belum bisa ekspor: %s', why), ...
            'ForegroundColor',[0.6 0.2 0.2]); return;
    end
    only = {};
    if strcmp(mode,'sel')
        if isempty(h.selFaultId)
            set(h.txtExpStatus,'String','Pilih baris sesar dulu.', ...
                'ForegroundColor',[0.6 0.2 0.2]); return;
        end
        only = {h.selFaultId};
    end

    doGS    = logical(get(h.chkGS,'Value'));
    doPanel = logical(get(h.chkPanel,'Value'));
    if ~doGS && ~doPanel
        set(h.txtExpStatus,'String','Centang minimal 1 jenis ekspor (GS / panel).', ...
            'ForegroundColor',[0.6 0.2 0.2]); return;
    end

    set(h.txtExpStatus,'String','Menyiapkan (memuat semua bingkai peta)…', ...
        'ForegroundColor',[0.2 0.2 0.2]); drawnow;

    % Pastikan dataset peta penuh (bg_images) untuk GS + render frame k>1.
    % Bila peta punya >1 bingkai tapi ensureFull GAGAL (OOM/korup), dataset
    % tetap bingkai-1 → foto/panel akan salah frame → HENTIKAN (jangan diam).
    h.pnTgt = pivui.linkView.ensureFull(h.pnTgt);
    guidata(fig, h);
    if h.pnTgt.nF > 1 && ~h.pnTgt.fullLoaded
        set(h.txtExpStatus,'String', ...
            'GAGAL: tak bisa memuat semua bingkai peta (dataset besar/rusak).', ...
            'ForegroundColor',[0.6 0.2 0.2]); return;
    end
    dataTgtAll = h.pnTgt.data;

    pabRoot = i_defExportRoot(h);
    stamp   = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
    progFcn = @(i,n,fid) i_expProgress(fig, i, n, fid);

    % Bangun opts sbg VARIABEL lalu set field cell (onlyFaultIds) SETELAHNYA —
    % hindari semantik struct('f',{cell}) yang halus (cell kosong / nested).
    eopts = struct('doGS',doGS, 'doPanel',doPanel, 'userPrefs',h.pnTgt.up, ...
                   'producedAt',stamp, 'resolve',h.pnTgt.resolve, ...
                   'progressFcn',progFcn);
    eopts.onlyFaultIds = only;
    try
        manifest = pivcore.io.pabLinkExport.exportFSR( ...
            pabRoot, h.refFile, h.tgtFile, h.doc, h.faultsDoc, dataTgtAll, eopts);
    catch ME
        set(h.txtExpStatus,'String', sprintf('GAGAL ekspor: %s', ME.message), ...
            'ForegroundColor',[0.6 0.2 0.2]); return;
    end

    pdir = pivcore.io.pabLinkExport.pairDir(pabRoot, h.refFile, h.tgtFile);
    set(h.txtExpStatus,'String', sprintf('Selesai: %d sesar diekspor → %s', ...
        manifest.nExported, i_short(pdir)), 'ForegroundColor',[0.1 0.4 0.1]);
end

function i_expProgress(fig, i, n, fid)
    h = guidata(fig);
    if isfield(h,'txtExpStatus') && ishghandle(h.txtExpStatus)
        set(h.txtExpStatus,'String', sprintf('Ekspor %s (%d/%d)…', fid, i, n));
        drawnow;
    end
end

function r = i_defExportRoot(h)
    if isfield(h,'exportDir') && ~isempty(h.exportDir) && isfolder(h.exportDir)
        r = h.exportDir;
    else
        r = h.pabRoot;
    end
end

function s = i_shortReason(str)
    str = char(str);
    if isempty(str), s = ''; return; end
    if numel(str) > 12, s = [str(1:11) '…']; else, s = str; end
end

function s = i_en(tf)
    if tf, s = 'on'; else, s = 'off'; end
end

% =====================================================================
%  Simpan / pindah / tutup
% =====================================================================
function ok = i_onSave(fig)
    ok = false;
    h = guidata(fig);
    if isempty(h.tgtFile)
        set(h.status,'String','Belum ada MAT peta (target) untuk disimpan.'); return;
    end
    [missing, why] = i_calibMissing(h.doc);
    if missing
        set(h.status,'String', sprintf('Belum bisa simpan: %s', why));
        % tetap simpan dokumen (titik ikat parsial) supaya progres tak hilang?
        % -> Simpan saja; kalibrasi invalid tercatat. Beri peringatan.
    end
    try
        pivcore.io.pabLink.write(h.tgtFile, h.doc);
        p = pivcore.io.pabLink.dataPath(h.tgtFile);
        if missing
            set(h.status,'String', sprintf('Tersimpan (kalibrasi BELUM lengkap): %s', i_short(p)));
        else
            set(h.status,'String', sprintf('Ikatan tersimpan: %s', i_short(p)));
        end
        ok = true;
    catch ME
        set(h.status,'String', sprintf('GAGAL simpan: %s', ME.message));
    end
end

function i_onGoSync(fig)
    h = guidata(fig);
    if isempty(h.tgtFile)
        set(h.status,'String','Pilih kedua MAT & tandai titik ikat dulu.'); return;
    end
    ok = i_onSave(fig);
    if ~ok, return; end
    tgt = h.tgtFile;
    delete(h.fig);
    try
        PABSYNC(pivcore.io.pabLink.dataPath(tgt));
    catch ME
        warning('PABLINK:goSync','Gagal buka PABSYNC: %s', ME.message);
    end
end

function i_onClose(fig)
    delete(fig);
end

% =====================================================================
%  Helper titik ikat / format
% =====================================================================
function names = i_tieNames()
    names = {'FSR pertama','FSR terakhir'};
end

function name = i_activeTieName(fig)
    h = guidata(fig);
    names = i_tieNames();
    v = max(1, min(get(h.popTie,'Value'), numel(names)));
    name = names{v};
end

function [tie, idx] = i_findTie(doc, name)
    tie = []; idx = 0;
    if ~isstruct(doc) || ~isfield(doc,'tiePoints'), return; end
    for k = 1:numel(doc.tiePoints)
        t = doc.tiePoints{k};
        if isstruct(t) && isfield(t,'name') && strcmp(t.name, name)
            tie = t; idx = k; return;
        end
    end
end

% Pastikan doc.tiePoints = persis 2 tie BERURUT (FSR pertama, FSR terakhir).
function doc = i_canonTies(doc)
    names = i_tieNames();
    out = cell(1, numel(names));
    for i = 1:numel(names)
        [t, ~] = i_findTie(doc, names{i});
        if isempty(t), t = pivcore.io.pabLink.tieStruct(names{i}, NaN, NaN, NaN); end
        t.name = names{i};
        out{i} = t;
    end
    doc.tiePoints = out;
end

function [missing, why] = i_calibMissing(doc)
    missing = false; why = '';
    if ~doc.reference.geomValid || ~isfinite(doc.reference.strainTotalPct)
        missing = true; why = 'acuan belum punya geometri/strain valid'; return;
    end
    [t1,~] = i_findTie(doc, 'FSR pertama');
    [t2,~] = i_findTie(doc, 'FSR terakhir');
    if isempty(t1) || isempty(t2) || ~isfinite(t1.refFrame) || ~isfinite(t1.tgtFrame) ...
            || ~isfinite(t2.refFrame) || ~isfinite(t2.tgtFrame)
        missing = true; why = '2 titik ikat belum lengkap (penampang+peta)'; return;
    end
    if t1.tgtFrame == t2.tgtFrame
        missing = true; why = 'frame peta kedua titik ikat sama (tak bisa kalibrasi)'; return;
    end
end

function s = i_sideLabel(side)
    if strcmp(side,'ref'), s = 'penampang (acuan)'; else, s = 'tampak peta (target)'; end
end
function s = i_validStr(tf)
    if tf, s = 'valid'; else, s = '—'; end
end
function s = i_pctStr(v)
    if isempty(v) || ~isnumeric(v) || ~isfinite(v), s = '—'; else, s = sprintf('%+.4g%%', v); end
end
function s = i_frStr(v)
    if isempty(v) || ~isnumeric(v) || ~isfinite(v), s = '—'; else, s = sprintf('%d', round(v)); end
end
function s = i_baseOf(f)
    [~, s] = fileparts(char(f));
end
function s = i_short(p)
    p = char(p);
    if numel(p) <= 46, s = p; return; end
    s = ['…' p(end-44:end)];
end
