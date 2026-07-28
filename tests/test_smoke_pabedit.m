function test_smoke_pabedit(rootDir)
%TEST_SMOKE_PABEDIT  Uji headless PABEDIT — editor tampilan WYSIWYG produksi 1
%   gambar spesifik (AXPOT/Net-slip/AX main) + masking. SENYAP, export ke TMP.
%   Cakupan:
%     A engine pabEditProject (defaultOpts/merge/save-load round-trip/mask norm)
%     A2 engine pabEditExport (penamaan file + folder)
%     B build GUI + klik baris exp -> h.fdoc terisi + kanvas non-kosong
%     C 3 mode kanvas (pot/netslip/main) render tanpa error
%     D toggle POI (matikan START, exclude F#) -> jumlah titik nsPoint berubah
%     E AX main: CLim min/max diterapkan + tick kosong (polos)
%     F setpref global round-trip (non-destruktif snap/restore)
%     G export 1 gambar mode aktif -> PNG + sidecar JSON di TMP
%     H masking: tambah kotak+poligon (state) -> patch putih tergambar; hapus semua
%
%   test_smoke_pabedit                 % fixture RAW/PIV_2026-06-24
%   test_smoke_pabedit('/path/folder')

fprintf('==== TEST SMOKE PABEDIT ====\n');
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
roots = pab_setup();
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>
if nargin < 1 || isempty(rootDir)
    rootDir = fullfile(roots.data_root, 'RAW', 'PIV_2026-06-24');
end
if ~isfolder(rootDir)
    fprintf('[SKIP] folder uji tak ada: %s\n', rootDir);
    return;
end
fprintf('[ok] folder: %s\n', rootDir);

% ---- Snapshot pref global agar test tak merusak preferensi user ----
hadPref = ispref('PABEDIT','global'); prefBak = [];
if hadPref, prefBak = getpref('PABEDIT','global'); end
restorePref = onCleanup(@() i_restorePref(hadPref, prefBak)); %#ok<NASGU>

% ============ A. Engine pabEditProject (unit) ============
o = pivcore.io.pabEditProject.defaultOpts();
assert(isfield(o,'poi') && isfield(o.poi,'start') && isfield(o.poi,'end'), 'defaultOpts POI kurang');
assert(strcmp(o.mode,'pot'), 'mode default harus pot');
assert(o.tickPx==false, 'AX main harus POLOS default (tickPx false)');
assert(isfield(o,'masks') && isstruct(o.masks), 'masks harus ada');
% merge: field hilang -> default; masks tetap.
o2 = struct('mode','main','velMult',0.02);
om = pivcore.io.pabEditProject.mergeOpts(o2);
assert(strcmp(om.mode,'main') && abs(om.velMult-0.02)<1e-12, 'mergeOpts nilai user hilang');
assert(isfield(om.poi,'nuc'), 'mergeOpts POI tak dilengkapi');
% save/load round-trip.
tmpDir = tempname; mkdir(tmpDir);
cuTmp = onCleanup(@() i_rmdir(tmpDir));
jp = fullfile(tmpDir,'demo_pabedit.json');
oS = om; oS.title='TES'; oS.climVel=[0 4.2]; oS.poi.start.show=false; oS.poi.nuc.color=[1 0 0];
pivcore.io.pabEditProject.save(jp, oS, fullfile(rootDir,'demo.mat'));
assert(isfile(jp), 'save sidecar gagal');
oL = pivcore.io.pabEditProject.load(jp);
assert(strcmp(oL.title,'TES') && abs(oL.climVel(2)-4.2)<1e-9, 'round-trip nilai salah');
assert(oL.poi.start.show==false && abs(oL.poi.nuc.color(1)-1)<1e-9, 'round-trip POI salah');
% mask norm: rects Nx4, polys cell of Kx2.
mm = pivcore.io.pabEditProject.normMasks(struct('rects',[1 2 3 4],'polys',{{[0 0;1 0;1 1]}}));
assert(size(mm.rects,2)==4 && iscell(mm.polys) && size(mm.polys{1},1)==3, 'normMasks salah');
fprintf('[A] engine pabEditProject OK\n');

% ============ A2. Engine pabEditExport (naming) ============
df = fullfile(rootDir,'MY-EXP.mat');
assert(strcmp(pivcore.io.pabEditExport.imageFile(df,'pot','','png'),'MY-EXP_pot.png'), 'imageFile salah');
assert(strcmp(pivcore.io.pabEditExport.jsonFile(df,'netslip',''),'MY-EXP_netslip.json'), 'jsonFile salah');
rd = pivcore.io.pabEditExport.rootDir('/tmp/x');
assert(~isempty(strfind(rd,'PABEDIT_export')), 'rootDir salah'); %#ok<STREMP>
fprintf('[A2] engine pabEditExport OK\n');

% ============ B. Build GUI + muat exp (fixture nyata) ============
fig = PABEDIT(rootDir, tmpDir);   % arg-2 = folder induk export (TMP)
assert(ishghandle(fig), 'PABEDIT tak mengembalikan figure');
h = guidata(fig);
assert(isfield(h,'ax') && ishghandle(h.ax), 'kanvas h.ax tak ada');
assert(isfield(h,'btnExport') && ishghandle(h.btnExport), 'tombol export tak ada');
% Pilih baris exp pertama -> muat (fallback auto-75% mengisi recs).
i_fireCellSel(h.tbl, [1 1]);
pivui.pab4Shell.loadExperiment(fig, 1);   % eksplisit (noAutoLoadExp aktif)
h = guidata(fig);
assert(isstruct(h.fdoc), 'h.fdoc tak terisi setelah muat');
assert(~isempty(get(h.ax,'Children')), 'kanvas kosong setelah muat');
assert(~isempty(h.recs), 'recs kosong — fallback auto-75% gagal menyampel POT');
fprintf('[B] build + muat exp OK (%d kurva)\n', numel(h.recs));

% ---- Suntik 1 SESAR nyata (HW/FW dari 2 record + 4 POI) ke h.fdoc supaya
%      jalur render kurva/POI sungguhan teruji (PABEDIT read-only: kita isi doc
%      di memori, bukan lewat UI assign). ----
recs = h.recs; nR = numel(recs);
hwRow = max(1, round(nR*0.35)); fwRow = min(nR, round(nR*0.65));
hwPos = recs(hwRow).posPx; fwPos = recs(fwRow).posPx;
nF = h.nF;
f1 = pivcore.io.pab5Faults.faultStruct('F1', hwPos, fwPos, ...
    round(nF*0.4), round(nF*0.6), round(nF*0.2), round(nF*0.85));
f1.uiNum = 1;
h.fdoc = pivcore.io.pab5Faults.upsertFault(h.fdoc, f1);
guidata(fig, h);
i_setMode(fig, 'pot');
h = guidata(fig);
nHW = numel(findall(h.ax,'Tag','hwCurve')) + numel(findall(h.ax,'Tag','fwCurve'));
assert(nHW>=1, 'kurva HW/FW sesar tak tergambar di mode POT');
fprintf('[B2] sesar sintetis -> kurva HW/FW tergambar OK\n');

% ============ I. Chrome shell BERSIH (elemen shell tersembunyi) ============
% Setelah build + muat exp (shell renderMain/renderPOT jalan), pastikan axes &
% strip shell tak tampil -> tak bertabrakan dgn UI PABEDIT.
for fld = {'axMain','axPOT','axACtop','axACbot'}
    if isfield(h,fld{1}) && ishghandle(h.(fld{1}))
        assert(strcmp(get(h.(fld{1}),'Visible'),'off'), sprintf('axes shell %s masih tampil', fld{1}));
        ch = allchild(h.(fld{1}));
        for c = ch(:).'
            if ishghandle(c) && isprop(c,'Visible')
                assert(strcmp(get(c,'Visible'),'off'), sprintf('isi %s masih tampil', fld{1}));
            end
        end
    end
end
% Kanvas PABEDIT sendiri HARUS tampil + panel kiri/kanan tetap ada.
assert(strcmp(get(h.ax,'Visible'),'on') || ~isempty(get(h.ax,'Children')), 'kanvas PABEDIT tak tampil');
assert(isfield(h,'pnlL') && ishghandle(h.pnlL) && strcmp(get(h.pnlL,'Visible'),'on'), 'panel kiri (tabel exp) hilang');
% Strip shell "Vel mag" (btnDisp) ada di panel pnlC -> panel INDUKnya harus off
% (property Visible child tak berubah bila parent panel disembunyikan).
if isfield(h,'btnDisp') && ishghandle(h.btnDisp)
    pnlC = ancestor(h.btnDisp,'uipanel');
    assert(~isempty(pnlC) && strcmp(get(pnlC,'Visible'),'off'), 'strip shell (pnlC Vel-mag) masih tampil');
end
% Tombol kunci shell (btnLock) = anak langsung figure -> Visible off.
if isfield(h,'btnLock') && ishghandle(h.btnLock)
    assert(strcmp(get(h.btnLock,'Visible'),'off'), 'tombol kunci shell masih tampil');
end
fprintf('[I] chrome shell bersih (axes/strip shell tersembunyi) OK\n');

% ============ C. 3 mode kanvas ============
for md = {'pot','netslip','main'}
    i_setMode(fig, md{1});
    h = guidata(fig);
    assert(strcmp(h.o.mode, md{1}), sprintf('mode %s tak set', md{1}));
    % render tak error + ada objek (atau pesan teks bila data kurang).
    assert(~isempty(get(h.ax,'Children')), sprintf('kanvas kosong mode %s', md{1}));
end
fprintf('[C] 3 mode render OK\n');

% ============ D. Toggle POI + exclude ============
i_setMode(fig, 'pot');
h = guidata(fig);
nBefore = numel(findall(h.ax,'Tag','nsPoint'));
% Matikan START.
set(h.poiCtrl.start.chk,'Value',0); i_fireCb(h.poiCtrl.start.chk);
h = guidata(fig);
assert(h.o.poi.start.show==false, 'toggle START gagal');
nAfter = numel(findall(h.ax,'Tag','nsPoint'));
assert(nAfter <= nBefore, 'matikan START harusnya tak menambah titik');
% Nyalakan lagi + exclude F1 dari NUC.
set(h.poiCtrl.start.chk,'Value',1); i_fireCb(h.poiCtrl.start.chk);
set(h.poiCtrl.nuc.edExcl,'String','1'); i_fireCb(h.poiCtrl.nuc.edExcl);
h = guidata(fig);
assert(any(h.o.poi.nuc.exclude==1), 'exclude F1 dari NUC gagal');
fprintf('[D] toggle POI + exclude OK\n');

% ============ E. AX main CLim + polos ============
i_setMode(fig, 'main');
set(h.edClimLo,'String','0'); set(h.edClimHi,'String','2.5'); i_fireCb(h.edClimHi);
set(h.chkTickPx,'Value',0); i_fireCb(h.chkTickPx);
h = guidata(fig);
if ~isempty(h.data)
    cl = get(h.ax,'CLim');
    if strcmp(h.o.scalar,'velmag')
        assert(abs(cl(2)-2.5)<1e-6, sprintf('CLim max tak diterapkan (%.3f)', cl(2)));
    end
    assert(isempty(get(h.ax,'XTick')) && isempty(get(h.ax,'YTick')), 'AX main harus POLOS (tick kosong)');
end
fprintf('[E] AX main CLim + polos OK\n');

% ============ F. setpref global round-trip ============
set(h.edDpi,'String','177'); i_fireCb(h.edDpi);
i_fireCb(h.btnExport);  % tak wajib; lanjut save global
i_click(fig, '⭐ Jadikan default');
assert(ispref('PABEDIT','global'), 'setpref global tak tersimpan');
g = getpref('PABEDIT','global');
assert(round(g.dpi)==177, sprintf('dpi global tak tersimpan (%g)', g.dpi));
fprintf('[F] setpref global round-trip OK\n');

% ============ G. Export 1 gambar + sidecar ============
i_setMode(fig, 'pot');
h = guidata(fig);
i_fireCb(h.btnExport);
imgP = pivcore.io.pabEditExport.imagePath(tmpDir, h.df, 'pot', '', 'png');
jsP  = pivcore.io.pabEditExport.jsonPath(tmpDir, h.df, 'pot', '');
assert(isfile(imgP), sprintf('gambar export tak ada: %s', imgP));
assert(isfile(jsP), 'sidecar JSON export tak ada');
oj = pivcore.io.pabEditProject.load(jsP);
assert(strcmp(oj.mode,'pot'), 'sidecar mode salah');
fprintf('[G] export 1 gambar + sidecar OK\n');

% ============ H. Masking (state + render + hapus) ============
h = guidata(fig);
h.o.masks.rects = [10 10 40 40];
h.o.masks.polys = {[5 5; 50 5; 30 60]};
guidata(fig, h);
i_setMode(fig, 'main');   % masking paling relevan di AX main
h = guidata(fig);
nMask = numel(findall(h.ax,'Tag','pabeditMask'));
if ~isempty(h.data)
    assert(nMask>=2, sprintf('mask patch tak tergambar (%d)', nMask));
end
% Hapus semua kotak.
i_click(fig, '🗑 Kotak');
h = guidata(fig);
assert(isempty(h.o.masks.rects), 'hapus semua kotak gagal');
assert(numel(h.o.masks.polys)==1, 'poligon tak boleh ikut terhapus saat hapus kotak');
% Hapus semua poligon.
i_click(fig, '🗑 Poligon');
h = guidata(fig);
assert(isempty(h.o.masks.polys), 'hapus semua poligon gagal');
fprintf('[H] masking (kotak+poligon render/hapus) OK\n');

try, close(fig); catch, end
fprintf('==== SEMUA TES PABEDIT LULUS ====\n');
end


% ---- helper ----
function i_fireCb(c)
    if ~ishghandle(c), return; end
    cb = get(c,'Callback');
    if ~isempty(cb), cb(c, struct()); end
end

function i_fireCellSel(tbl, idx)
    if ~ishghandle(tbl), return; end
    cb = get(tbl,'CellSelectionCallback');
    if ~isempty(cb), cb(tbl, struct('Indices',idx)); end
end

function i_setMode(fig, mode)
    h = guidata(fig);
    switch mode
        case 'pot',     b = h.btnModePot;
        case 'netslip', b = h.btnModeNs;
        case 'main',    b = h.btnModeMain;
    end
    if ishghandle(b), set(b,'Value',1); i_fireCb(b); end
end

function i_click(fig, str)
    b = findall(fig,'Type','uicontrol','Style','pushbutton');
    for k = 1:numel(b)
        if strcmp(get(b(k),'String'), str)
            cb = get(b(k),'Callback'); if ~isempty(cb), cb(b(k),struct()); end
            return;
        end
    end
    error('tombol "%s" tak ketemu', str);
end

function i_restorePref(had, bak)
    try
        if had, setpref('PABEDIT','global', bak);
        elseif ispref('PABEDIT','global'), rmpref('PABEDIT','global');
        end
    catch
    end
end

function i_rmdir(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
