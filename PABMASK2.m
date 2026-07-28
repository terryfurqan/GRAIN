function PABMASK2(rootDir)
%PABMASK2  Editor masking POLYGON berkeyframe (layer-2, ala After Effects) pada
%   FOTO MENTAH. Pelengkap PABMASK (kotak, layer-1). NON-DESTRUKTIF: resep polygon
%   disimpan di progres terpadu (PIVlab_automasi_progress:setpoly) & ditempel saat
%   decode (readMatFrame/unpackMat via maskPoly), blob asli utuh.
%
%   ALUR KERJA (restorasi mundur): pilih eksperimen -> geser ke FRAME AKHIR ->
%   "Gambar polygon" -> "Set keyframe". Lalu MUNDUR (mis. -30 frame), sesuaikan
%   bentuk, "Set keyframe" lagi. Ulang sampai frame pertama. Antar-keyframe =
%   interpolasi LINEAR vertex (maskPoly.interpVerts). Syarat: jumlah vertex SAMA
%   antar-keyframe (turunkan keyframe baru dgn menyalin+geser -> otomatis terjaga).
%
%   Alur modul: PAB0 -> PABMASK (kotak) -> PABMASK2 (polygon) -> PAB1 -> PAB2.
%   Lihat: pivanalyzemat.core.maskPoly, maskSidecar (v2_poly), PABMASK.

    here = fileparts(mfilename('fullpath'));
    if isempty(which('pivanalyzemat.core.maskPoly'))
        try, pab_setup(); catch, addpath(here); end %#ok<CTCH>
    end
    if isempty(which('pivui.forceLightTheme'))
        pivc = fullfile(here, 'pivcore_lib'); if isfolder(pivc), addpath(pivc); end
    end
    if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
        rootDir = uigetdir(pwd, 'Pilih folder foto mentah (setelah PAB0/PABMASK)');
        if isequal(rootDir, 0), return; end
    end

    h = struct();
    h.root = rootDir; h.busy = false;
    h.list = struct('name',{},'path',{},'files',{},'nFrames',{}, ...
                    'polygon',{},'dirty',{});   % polygon = struct maskPoly.polygons(1) atau []
    h.activeRow = 0;
    h.curFrame = 1; h.img = []; h.imSz = [];
    h.roi = [];                 % images.roi.Polygon aktif (editable)
    h.roiBaseV = [];            % snapshot vertex ROI saat dibuat (utk deteksi tambah/hapus titik)
    h.imh = []; h.ovl = [];
    h = i_buildUI(h);
    guidata(h.fig, h);
    i_scan(h.fig);
end

% =====================================================================
function h = i_buildUI(h)
    vis = 'on'; try, if pivui.quiet(), vis = 'off'; end; catch, end %#ok<CTCH>
    W = 1180; H = 720;
    h.fig = figure('Name','', 'NumberTitle','off', 'MenuBar','none', ...
        'ToolBar','none', 'Color',[1 1 1], 'Units','pixels', ...
        'Position',[80 80 W H], 'Visible',vis, 'CloseRequestFcn',@(s,e) i_onClose(s));
    try, h.fig.Name = pivui.titleWithVersion('PAB Masking 2 — polygon keyframe (non-destruktif)'); catch, h.fig.Name = 'PAB Masking 2'; end %#ok<CTCH>
    try, pivui.forceLightTheme(h.fig); catch, end %#ok<CTCH>

    % KIRI: daftar exp + tombol
    pL = uipanel('Parent',h.fig,'Units','normalized','Position',[0.006 0.01 0.28 0.98], ...
        'BackgroundColor',[1 1 1],'BorderType','line');
    uicontrol('Parent',pL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.955 0.45 0.035],'String','📂 Ganti folder…', ...
        'Callback',@(s,e) i_onChangeRoot(h.fig));
    uicontrol('Parent',pL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.955 0.45 0.035],'String','🔄 Pindai ulang', ...
        'Callback',@(s,e) i_scan(h.fig));
    h.txtRoot = uicontrol('Parent',pL,'Style','text','Units','normalized', ...
        'Position',[0.03 0.925 0.94 0.025],'String',h.root, ...
        'HorizontalAlignment','left','BackgroundColor',[1 1 1],'FontSize',8);
    h.tbl = uitable('Parent',pL,'Units','normalized','Position',[0.03 0.45 0.94 0.46], ...
        'ColumnName',{'Eksperimen','#frame','poly'},'ColumnEditable',[false false false], ...
        'ColumnWidth',{150 55 45}, 'RowName',[], ...
        'CellSelectionCallback',@(s,ev) i_onSelect(h.fig, ev));
    h.kfTbl = uitable('Parent',pL,'Units','normalized','Position',[0.03 0.14 0.94 0.29], ...
        'ColumnName',{'Keyframe','#vertex'},'ColumnEditable',[false false], ...
        'ColumnWidth',{110 70}, 'RowName',[]);
    uicontrol('Parent',pL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.075 0.45 0.05],'String','💾 Simpan resep', ...
        'FontWeight','bold','BackgroundColor',[0.88 0.95 0.88], ...
        'Callback',@(s,e) i_onSave(h.fig));
    uicontrol('Parent',pL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.075 0.45 0.05],'String','Transfer → PAB1 ▶', ...
        'FontWeight','bold','BackgroundColor',[0.90 0.94 0.99], ...
        'Callback',@(s,e) i_onTransfer(h.fig));
    uicontrol('Parent',pL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.02 0.45 0.045],'String','🗑 Hapus polygon', ...
        'Callback',@(s,e) i_onClear(h.fig));
    uicontrol('Parent',pL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.02 0.45 0.045],'String','✕ Tutup', ...
        'Callback',@(s,e) i_onClose(h.fig));

    % KANAN: kanvas + kontrol keyframe
    pR = uipanel('Parent',h.fig,'Units','normalized','Position',[0.29 0.01 0.705 0.98], ...
        'BackgroundColor',[1 1 1],'BorderType','line');
    h.ax = axes('Parent',pR,'Units','normalized','Position',[0.04 0.16 0.93 0.80]);
    axis(h.ax,'off');
    h.txtExp = uicontrol('Parent',pR,'Style','text','Units','normalized', ...
        'Position',[0.04 0.965 0.92 0.028],'String','(pilih eksperimen)', ...
        'HorizontalAlignment','left','BackgroundColor',[1 1 1],'FontWeight','bold');
    h.sld = uicontrol('Parent',pR,'Style','slider','Units','normalized', ...
        'Position',[0.04 0.105 0.60 0.03],'Min',1,'Max',2,'Value',1, ...
        'Callback',@(s,e) i_onSlider(h.fig));
    h.txtFrame = uicontrol('Parent',pR,'Style','text','Units','normalized', ...
        'Position',[0.66 0.10 0.32 0.032],'String','frame 1 / 1', ...
        'HorizontalAlignment','left','BackgroundColor',[1 1 1]);
    uicontrol('Parent',pR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.04 0.055 0.16 0.04],'String','▭ Gambar polygon', ...
        'TooltipString',['Gambar polygon BARU dari nol. Di frame yang PERSIS ' ...
        'sebuah keyframe, polygon sudah bisa langsung ditarik titiknya (tak perlu gambar ulang).'], ...
        'Callback',@(s,e) i_onDrawPoly(h.fig));
    uicontrol('Parent',pR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.21 0.055 0.17 0.04],'String','＋ Set keyframe (frame ini)', ...
        'FontWeight','bold', ...
        'TooltipString',['Simpan bentuk polygon frame ini sebagai keyframe. Titik yang ' ...
        'DITAMBAH (klik-kanan ROI ▸ Add Waypoint) / DIHAPUS (Delete Vertex) otomatis ' ...
        'merambat ke semua keyframe lain agar animasi tetap mulus.'], ...
        'Callback',@(s,e) i_onSetKeyframe(h.fig));
    uicontrol('Parent',pR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.39 0.055 0.15 0.04],'String','－ Hapus keyframe ini', ...
        'Callback',@(s,e) i_onDelKeyframe(h.fig));
    uicontrol('Parent',pR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.55 0.055 0.14 0.04],'String','⤒ Ke frame AKHIR', ...
        'Callback',@(s,e) i_gotoLast(h.fig));
    h.status = uicontrol('Parent',pR,'Style','text','Units','normalized', ...
        'Position',[0.04 0.01 0.93 0.035],'String','Siap.', ...
        'HorizontalAlignment','left','BackgroundColor',[0.96 0.96 0.98]);
end

% =====================================================================
function i_scan(fig)
    h = guidata(fig);
    set(h.txtRoot,'String',h.root);
    i_pointProgress(h.root);
    found = struct('path',{},'files',{},'nImg',{});
    try, found = batchpivprep2.io.collectFolders(h.root, true); catch, end %#ok<CTCH>
    L = struct('name',{},'path',{},'files',{},'nFrames',{},'polygon',{},'dirty',{});
    for i = 1:numel(found)
        p = found(i).path;
        kept = i_qpivKept(p, found(i).files);
        if numel(kept) < 1; continue; end
        pg = i_loadPolygon(p);
        L(end+1) = struct('name',i_relName(h.root,p),'path',p,'files',{kept}, ...
            'nFrames',numel(kept),'polygon',pg,'dirty',false); %#ok<AGROW>
    end
    h.list = L; h.activeRow = 0; guidata(fig,h);
    i_refreshTable(fig); i_clearViewer(fig);
    h = guidata(fig);
    if isempty(L)
        set(h.status,'String','Tak ada eksperimen foto lolos QPIV. Jalankan PAB0 dulu.');
    else
        set(h.status,'String',sprintf('%d eksperimen. Pilih satu, ke frame AKHIR, gambar polygon.', numel(L)));
    end
end

function i_refreshTable(fig)
    h = guidata(fig);
    n = numel(h.list); C = cell(n,3);
    for i = 1:n
        e = h.list(i);
        C{i,1} = e.name; C{i,2} = sprintf('%d', e.nFrames);
        nk = 0; if ~isempty(e.polygon) && isfield(e.polygon,'keyframes'); nk = numel(e.polygon.keyframes); end
        if nk > 0; C{i,3} = sprintf('%dkf', nk); else; C{i,3} = '—'; end
    end
    set(h.tbl,'Data',C);
end

function i_refreshKfTable(fig)
    h = guidata(fig); C = {};
    if h.activeRow >= 1
        e = h.list(h.activeRow);
        if ~isempty(e.polygon) && isfield(e.polygon,'keyframes')
            kf = e.polygon.keyframes; C = cell(numel(kf),2);
            for i = 1:numel(kf)
                C{i,1} = sprintf('frame %d', kf(i).frame_index);
                C{i,2} = sprintf('%d', size(kf(i).vertices,1));
            end
        end
    end
    set(h.kfTbl,'Data',C);
end

% =====================================================================
function i_onSelect(fig, ev)
    if isempty(ev.Indices), return; end
    h = guidata(fig); row = ev.Indices(1);
    if row < 1 || row > numel(h.list), return; end
    i_deleteRoi(h);
    h.activeRow = row; h.roi = []; h.roiBaseV = []; guidata(fig,h);
    % Mulai di frame AKHIR (alur restorasi).
    i_setFrame(fig, h.list(row).nFrames);
    i_refreshKfTable(fig);
    h = guidata(fig);
    set(h.txtExp,'String',sprintf('%s (%d frame)', h.list(row).name, h.list(row).nFrames));
    nF = max(2, h.list(row).nFrames);
    set(h.sld,'Min',1,'Max',nF,'Value',h.curFrame, ...
        'SliderStep',[1/(nF-1) max(2/(nF-1),0.1)]);
    set(h.status,'String',['Ke FRAME AKHIR. "Gambar polygon" lalu "Set keyframe". Mundur & ulangi. ' ...
        'Di frame keyframe: tarik titik / klik-kanan Add-Delete waypoint, lalu Set keyframe.']);
end

function i_setFrame(fig, k)
    h = guidata(fig);
    if h.activeRow < 1, return; end
    e = h.list(h.activeRow);
    k = max(1, min(e.nFrames, round(k)));
    h.curFrame = k;
    try, h.img = imread(fullfile(e.path, e.files{k})); catch, h.img = []; end
    if ~isempty(h.img); h.imSz = [size(h.img,1) size(h.img,2)]; end
    guidata(fig,h);
    i_render(fig);
    set(h.txtFrame,'String',sprintf('frame %d / %d', k, e.nFrames));
end

function i_render(fig)
    h = guidata(fig); ax = h.ax;
    i_deleteOvl(h);
    i_deleteRoi(h);
    if isempty(h.img); cla(ax); axis(ax,'off'); h.roi=[]; h.roiBaseV=[]; guidata(fig,h); return; end
    h.imh = image(h.img,'Parent',ax); axis(ax,'image'); set(ax,'YDir','reverse');
    if size(h.img,3)==1, colormap(ax, gray(256)); end
    set(ax,'XTick',[],'YTick',[]);
    h.roi = []; h.roiBaseV = [];
    guidata(fig,h);
    % Bila frame ini PERSIS sebuah keyframe -> tampilkan polygon sbg ROI EDITABLE
    % (titik bisa ditarik; klik-kanan Add/Delete waypoint). Selainnya -> patch statis.
    if h.activeRow >= 1
        e = h.list(h.activeRow);
        kfIdx = i_keyframeAt(e.polygon, h.curFrame);
        if kfIdx >= 1
            i_makeEditableRoi(fig, e.polygon.keyframes(kfIdx).vertices);
            return;
        end
    end
    i_drawInterpOverlay(fig);
end

function i_makeEditableRoi(fig, V)
%I_MAKEEDITABLEROI  Buat drawpolygon interaktif dari vertex V (keyframe di frame ini).
%   Simpan snapshot V ke h.roiBaseV sbg acuan deteksi tambah/hapus titik saat Set.
    h = guidata(fig);
    try
        roi = images.roi.Polygon('Parent',h.ax,'Position',double(V), ...
            'Color',[0.1 0.6 1],'FaceAlpha',0.20,'LineWidth',1.5);
        addlistener(roi,'ROIMoved',@(s,ev) i_onRoiMoved(fig));
        addlistener(roi,'VertexAdded',@(s,ev) i_onRoiMoved(fig));
        addlistener(roi,'VertexDeleted',@(s,ev) i_onRoiMoved(fig));
    catch ME
        set(h.status,'String',sprintf('ROI editable gagal: %s', ME.message)); return;
    end
    h.roi = roi; h.roiBaseV = double(V); guidata(fig,h);
end

function i_onRoiMoved(fig)
%I_ONROIMOVED  Tandai dirty saat user menarik/menambah/menghapus titik ROI.
    h = guidata(fig);
    if h.activeRow >= 1
        h.list(h.activeRow).dirty = true; guidata(fig,h);
        set(h.status,'String','Titik diubah. Tekan "Set keyframe" utk menyimpan.');
    end
end

function i_deleteRoi(h)
    try, if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end, catch, end %#ok<CTCH>
end

function i_drawInterpOverlay(fig)
    h = guidata(fig);
    if h.activeRow < 1, return; end
    e = h.list(h.activeRow);
    if isempty(e.polygon) || ~isfield(e.polygon,'keyframes') || isempty(e.polygon.keyframes), return; end
    V = pivanalyzemat.core.maskPoly.interpVerts(e.polygon, h.curFrame, e.nFrames);
    if isempty(V), return; end
    hold(h.ax,'on');
    h.ovl = patch('Parent',h.ax,'XData',V(:,1),'YData',V(:,2), ...
        'FaceColor',[1 1 1],'FaceAlpha',0.45,'EdgeColor',[0.1 0.6 1],'LineWidth',1.5);
    hold(h.ax,'off');
    guidata(fig,h);
end

function i_deleteOvl(h)
    try, if ~isempty(h.ovl) && isgraphics(h.ovl), delete(h.ovl); end, catch, end %#ok<CTCH>
end

function i_clearViewer(fig)
    h = guidata(fig); i_deleteOvl(h); i_deleteRoi(h);
    cla(h.ax); axis(h.ax,'off'); h.img = []; h.imh = [];
    h.roi = []; h.roiBaseV = []; guidata(fig,h);
    set(h.txtExp,'String','(pilih eksperimen)');
end

% =====================================================================
function i_onSlider(fig)
    h = guidata(fig);
    if h.activeRow < 1, return; end
    i_setFrame(fig, round(get(h.sld,'Value')));
end

function i_gotoLast(fig)
    h = guidata(fig);
    if h.activeRow < 1, return; end
    i_setFrame(fig, h.list(h.activeRow).nFrames);
    h = guidata(fig); set(h.sld,'Value',h.curFrame);
end

function i_onDrawPoly(fig)
    h = guidata(fig);
    if h.activeRow < 1 || isempty(h.img)
        set(h.status,'String','Pilih eksperimen dulu.'); return;
    end
    try, if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end, catch, end %#ok<CTCH>
    set(h.status,'String','Klik titik-titik polygon; klik-ganda/Enter utk selesai.');
    try
        roi = drawpolygon(h.ax,'Color',[0.1 0.6 1],'FaceAlpha',0.2);
    catch ME
        set(h.status,'String',sprintf('Gagal drawpolygon: %s', ME.message)); return;
    end
    if isempty(roi) || ~isvalid(roi) || size(roi.Position,1) < 3
        set(h.status,'String','Polygon batal / < 3 titik.'); return;
    end
    % Polygon SEGAR (bukan hasil edit keyframe) -> tak ada acuan lama.
    h.roi = roi; h.roiBaseV = []; guidata(fig,h);
    set(h.status,'String',sprintf('Polygon %d titik siap. Tekan "Set keyframe".', size(roi.Position,1)));
end

function i_onSetKeyframe(fig)
    h = guidata(fig);
    if h.activeRow < 1, return; end
    e = h.list(h.activeRow);
    % Sumber vertex baru (Vnew): ROI aktif (digambar/diedit) ATAU interpolasi frame ini.
    V = []; Vbase = h.roiBaseV;
    if ~isempty(h.roi) && isvalid(h.roi) && size(h.roi.Position,1) >= 3
        V = h.roi.Position;
    elseif ~isempty(e.polygon) && isfield(e.polygon,'keyframes') && ~isempty(e.polygon.keyframes)
        V = pivanalyzemat.core.maskPoly.interpVerts(e.polygon, h.curFrame, e.nFrames);
    end
    if isempty(V) || size(V,1) < 3
        set(h.status,'String','Gambar polygon dulu (min 3 titik).'); return;
    end
    extraMsg = '';
    hasKf = ~isempty(e.polygon) && isfield(e.polygon,'keyframes') && ~isempty(e.polygon.keyframes);
    if hasKf
        Kref = size(e.polygon.keyframes(1).vertices,1);
        if size(V,1) ~= Kref
            % Jumlah titik berubah -> selaraskan (sisip/hapus) ke SEMUA keyframe lain.
            % Acuan bentuk lama (Vold): snapshot ROI editable, atau interpolasi frame ini.
            if isempty(Vbase) || size(Vbase,1) ~= Kref
                Vbase = pivanalyzemat.core.maskPoly.interpVerts(e.polygon, h.curFrame, e.nFrames);
            end
            if isempty(Vbase) || size(Vbase,1) ~= Kref
                set(h.status,'String', ...
                    sprintf('Tak bisa selaraskan titik (butuh acuan %d titik). Batal.', Kref));
                return;
            end
            [e.polygon, extraMsg] = i_reconcileVertexCount(e.polygon, h.curFrame, Vbase, V);
        end
    end
    e.polygon = i_upsertKeyframe(e.polygon, h.curFrame, V);
    h.list(h.activeRow) = e; h.list(h.activeRow).dirty = true;
    guidata(fig,h);
    % i_render membuat ulang ROI editable utk frame keyframe ini (buang ROI lama dulu).
    i_refreshKfTable(fig); i_refreshTable(fig); i_render(fig);
    baseMsg = sprintf('Keyframe frame %d disimpan (%d titik).', h.curFrame, size(V,1));
    if isempty(extraMsg)
        set(h.status,'String',[baseMsg ' Mundur & ulangi.']);
    else
        set(h.status,'String',[baseMsg ' ' extraMsg]);
    end
end

function pg = i_upsertKeyframe(pg, frameIdx, V)
%I_UPSERTKEYFRAME  Sisip/timpa keyframe di frameIdx; jaga terurut.
    kf1 = struct('frame_index',round(frameIdx),'vertices',double(V));
    if isempty(pg) || ~isstruct(pg) || ~isfield(pg,'keyframes') || isempty(pg.keyframes)
        pg = struct('enabled',true,'fill',[],'keyframes',kf1); return;
    end
    kf = pg.keyframes;
    idx = find([kf.frame_index] == round(frameIdx), 1);
    if isempty(idx); kf(end+1) = kf1; else; kf(idx) = kf1; end
    [~,ord] = sort([kf.frame_index]); pg.keyframes = kf(ord);
    pg.enabled = true;
end

% ---------------------------------------------------------------------
% Sinkronisasi jumlah vertex (tambah/hapus titik merambat ke semua keyframe)
% ---------------------------------------------------------------------
function idx = i_keyframeAt(pg, frameIdx)
%I_KEYFRAMEAT  Indeks keyframe yg frame_index-nya = frameIdx (0 bila tak ada).
    idx = 0;
    if isempty(pg) || ~isstruct(pg) || ~isfield(pg,'keyframes') || isempty(pg.keyframes)
        return;
    end
    j = find([pg.keyframes.frame_index] == round(frameIdx), 1);
    if ~isempty(j); idx = j; end
end

function [pg, msg] = i_reconcileVertexCount(pg, curFrame, Vold, Vnew)
%I_RECONCILEVERTEXCOUNT  Delegasi tipis ke engine murni maskPoly.reconcileVertexCount.
    [pg, msg] = pivanalyzemat.core.maskPoly.reconcileVertexCount(pg, curFrame, Vold, Vnew);
end

function i_onDelKeyframe(fig)
    h = guidata(fig);
    if h.activeRow < 1, return; end
    e = h.list(h.activeRow);
    if isempty(e.polygon) || ~isfield(e.polygon,'keyframes') || isempty(e.polygon.keyframes)
        set(h.status,'String','Tak ada keyframe.'); return;
    end
    kf = e.polygon.keyframes;
    idx = find([kf.frame_index] == h.curFrame, 1);
    if isempty(idx)
        set(h.status,'String',sprintf('Tak ada keyframe di frame %d.', h.curFrame)); return;
    end
    kf(idx) = [];
    if isempty(kf); e.polygon = []; else; e.polygon.keyframes = kf; end
    h.list(h.activeRow) = e; h.list(h.activeRow).dirty = true; guidata(fig,h);
    i_refreshKfTable(fig); i_refreshTable(fig); i_render(fig);
    set(h.status,'String',sprintf('Keyframe frame %d dihapus.', h.curFrame));
end

function i_onClear(fig)
    h = guidata(fig);
    if h.activeRow < 1, return; end
    h.list(h.activeRow).polygon = [];
    h.list(h.activeRow).dirty = true; guidata(fig,h);
    i_refreshKfTable(fig); i_refreshTable(fig); i_render(fig);
    set(h.status,'String','Polygon dihapus (simpan untuk menulis).');
end

% =====================================================================
function i_onSave(fig)
    h = guidata(fig);
    if h.activeRow < 1, set(h.status,'String','Pilih eksperimen dulu.'); return; end
    e = h.list(h.activeRow);
    i_pointProgress(h.root);
    poly = i_buildPoly(e.polygon, e.nFrames);
    try
        if isempty(poly)
            PIVlab_automasi_progress('setpoly', e.path, []);
        else
            PIVlab_automasi_progress('setpoly', e.path, poly);
        end
        h.list(h.activeRow).dirty = false; guidata(fig,h);
        i_refreshTable(fig);
        set(h.status,'String',sprintf('Resep polygon tersimpan: %s', e.name));
    catch ME
        set(h.status,'String',sprintf('GAGAL simpan: %s', ME.message));
    end
end

function poly = i_buildPoly(pg, nFrames)
%I_BUILDPOLY  Bungkus polygon tunggal -> struct maskPoly (atau [] bila kosong).
%   n_ref = jumlah frame acuan (frame lolos QPIV) supaya decoder bisa menskala
%   frame_index ke N MAT PREP bila berbeda.
    poly = [];
    if isempty(pg) || ~isfield(pg,'keyframes') || isempty(pg.keyframes); return; end
    if nargin < 2 || isempty(nFrames) || ~isfinite(nFrames); nFrames = 0; end
    poly = struct('enabled',true,'fill',255,'n_ref',max(2,round(double(nFrames))),'polygons',pg);
    poly = pivanalyzemat.core.maskPoly.normalize(poly);
    if ~poly.enabled; poly = []; end
end

function pg = i_loadPolygon(expPath)
%I_LOADPOLYGON  Muat polygon (1 pertama) dari progres terpadu -> struct polygons(1).
    pg = [];
    try, m = PIVlab_automasi_progress('getpoly', expPath); catch, m = []; end
    if isempty(m) || ~isstruct(m); return; end
    try
        p = pivanalyzemat.core.maskPoly.normalize(m);
        if p.enabled && ~isempty(p.polygons); pg = p.polygons(1); end
    catch
    end
end

function i_onTransfer(fig)
    h = guidata(fig);
    dirtyN = 0; if ~isempty(h.list); dirtyN = sum([h.list.dirty]); end
    if dirtyN > 0
        i_onSave(fig); h = guidata(fig);   % simpan aktif
    end
    root = h.root;
    if isempty(root) || ~isfolder(root)
        set(h.status,'String','Folder tak valid.'); return;
    end
    set(h.status,'String','Meluncurkan PAB1 (jitter + MAT PREP)…'); drawnow;
    try, delete(fig); catch, end %#ok<CTCH>
    try, PAB1(root); catch ME
        warning('PABMASK2:openPab1','PAB1 gagal dibuka: %s', ME.message);
    end
end

function i_onChangeRoot(fig)
    h = guidata(fig);
    try, pivui.minimizeForDialog(h.fig); catch, end %#ok<CTCH>
    d = uigetdir(h.root, 'Pilih folder foto mentah');
    try, pivui.restoreAfterDialog(h.fig); catch, end %#ok<CTCH>
    if isequal(d,0), return; end
    h.root = d; guidata(fig,h); i_scan(fig);
end

function i_onClose(fig)
    try, delete(fig); catch, end %#ok<CTCH>
end

% =====================================================================
% Util (mirror PABMASK jpg-mode)
% =====================================================================
function i_pointProgress(root)
    try
        pf = fullfile(root,'PAB0_progress.mat');
        PIVlab_automasi_progress('setfile', pf);
    catch
    end
end

function keptFiles = i_qpivKept(expPath, files)
    files = files(:); keptFiles = files;
    try, e = PIVlab_automasi_progress('get', expPath); catch, e = []; end
    if isempty(e) || ~isfield(e,'qpiv_done') || ~e.qpiv_done; return; end
    baseAll = i_baseLower(files);
    keptN = i_cellStr(i_getf(e,'qpiv_kept_names'));
    if ~isempty(keptN)
        want = i_baseLower(keptN); [tf,loc] = ismember(want, baseAll);
        kf = files(loc(tf)); if ~isempty(kf); keptFiles = kf; end
        return;
    end
    ignN = i_cellStr(i_getf(e,'ignore_names'));
    if ~isempty(ignN)
        skip = 0; if isfield(e,'skip') && ~isempty(e.skip); skip = round(double(e.skip)); end
        stride = max(1,skip+1); if stride>1; files = files(1:stride:end); end
        drop = ismember(i_baseLower(files), i_baseLower(ignN));
        keptFiles = files(~drop);
    end
end

function v = i_getf(s,f); if isstruct(s)&&isfield(s,f); v=s.(f); else; v=[]; end; end
function c = i_cellStr(x)
    c={}; if isempty(x); return; end
    if ischar(x); c={x}; return; end
    if isstring(x); x=cellstr(x); end
    if iscell(x); x=x(:)'; k=cellfun(@(z) ischar(z)&&~isempty(z),x); c=x(k); end
end
function b = i_baseLower(names)
    names=i_cellStr(names); b=cell(1,numel(names));
    for i=1:numel(names); [~,nm,ext]=fileparts(char(names{i})); b{i}=lower([nm ext]); end
end
function nm = i_relName(root,p)
    root=regexprep(char(root),'[\\/]+$',''); p=regexprep(char(p),'[\\/]+$','');
    if strcmpi(root,p); [~,nm]=fileparts(p); return; end
    rel=p; if startsWith(lower(p),lower(root)); rel=p(numel(root)+1:end); rel=regexprep(rel,'^[\\/]+',''); end
    nm=strrep(rel,filesep,'/'); if isempty(nm); nm='exp'; end
end
