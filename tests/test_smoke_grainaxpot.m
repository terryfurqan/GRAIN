function test_smoke_grainaxpot(rootDir)
%TEST_SMOKE_GRAINAXPOT  Uji headless JEMBATAN GRAIN4 -> GRAINAXPOT:
%   (1) GRAIN4 ekspor <base>_axpot.mat (semua kurva, tanpa frame),
%   (2) engine axpotProject round-trip,
%   (3) GRAINAXPOT muat proyek -> tambah titik informasi -> ekspor PNG/JPEG/JSON +
%       simpan proyek (round-trip display+infoPoints+frameRefs).
%
%   test_smoke_grainaxpot                 % default: .../RAW/PIV_2026-06-24
%   test_smoke_grainaxpot('/path/folder')

fprintf('==== TEST SMOKE GRAINAXPOT — jembatan figur ====\n');
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
roots = grain_setup();
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>
% simpan & pulihkan pref layout user (tes tak boleh mengubah preferensi nyata)
prefHad = ispref('GRAINAXPOT','layout'); prefOld = [];
if prefHad, prefOld = getpref('GRAINAXPOT','layout'); end
restorePref = onCleanup(@() i_restorePref(prefHad, prefOld)); %#ok<NASGU>
if nargin < 1 || isempty(rootDir)
    rootDir = fullfile(roots.data_root, 'RAW', 'PIV_2026-06-24');
end
assert(isfolder(rootDir), 'Folder tak ada: %s', rootDir);

% --- engine murni: round-trip ---
tmp = fullfile(tempdir, 'axpot_eng_test.mat');
p = pivcore.io.axpotProject.empty('/x/EXP_demo.mat');
p.nFrames = 5; p.strainTotalPct = -3.0;
p.curves(end+1) = pivcore.io.axpotProject.curveStruct(1,'HW-1',[1 0 0],100,NaN,false,[0 1 2 3 4]);
p.curves(end+1) = pivcore.io.axpotProject.curveStruct(2,'',[0.4 0.4 0.4],120,NaN,false,[0 0.5 1 1.5 2]);
p.hw(end+1) = pivcore.io.axpotProject.hwStruct(1,'HW-1',[1 0 0],[0 1 2 3 4], ...
    struct('startF',2,'nclF',3,'fsrF',4,'endF',5), struct('start',-0.5,'nuc',-1,'fsr',-2,'end',-3));
pivcore.io.axpotProject.save(tmp, p);
q = pivcore.io.axpotProject.load(tmp);
assert(q.nFrames==5 && numel(q.curves)==2 && numel(q.hw)==1, 'round-trip engine gagal');
assert(isequal(q.curves(1).values,[0 1 2 3 4]), 'values kurva tak utuh');
sv = pivcore.io.axpotProject.strainVec(q);
assert(numel(sv)==5 && abs(sv(end)-(-3.0))<1e-9, 'strainVec salah');
try, delete(tmp); catch, end
fprintf('[ok] engine axpotProject: round-trip (2 kurva, 1 HW, strainVec)\n');

% --- GRAIN4: bangun data + ekspor _axpot.mat ---
GRAIN4(rootDir);
fig = findall(0,'Type','figure','-regexp','Name','GRAIN4');
assert(~isempty(fig),'figure GRAIN4 tak terbuka'); fig = fig(1);
cln = onCleanup(@() i_close(fig));
h = guidata(fig);
df1 = h.list(1).file;
axP = pivcore.io.axpotProject.defaultPath(df1);
i_rm(axP);
clnF = onCleanup(@() i_rm(axP));

pivui.grain4Shell.loadExperiment(fig, 1);
pivui.grain4Shell.setPsgLock(fig, true);
h = guidata(fig);
assert(~isempty(h.recs), 'POT tak termuat');
h.recs = pivcore.pot.hwLabel.assign(h.recs, 1, 'HW', 1);
h.recs = pivcore.pot.hwLabel.assign(h.recs, 2, 'HW', 2);
guidata(fig, h);
% titik HW-1
h = guidata(fig);
h.pts = pivcore.pot.snapPoints.setPoint(h.pts, 1, 'start', max(2,round(h.nF*0.3)));
h.pts = pivcore.pot.snapPoints.setPoint(h.pts, 1, 'end', max(3,round(h.nF*0.8)));
guidata(fig, h);

set(h.tg,'SelectedTab',h.tabStory);
i_click(h.tabStory, '💾 Save AX POT → editor GRAINAXPOT');
assert(isfile(axP), '<base>_axpot.mat tak ditulis');
proj = pivcore.io.axpotProject.load(axP);
assert(numel(proj.curves) >= 3, 'kurva di proyek < 3 (=%d)', numel(proj.curves));
assert(numel(proj.hw) == 2, 'HW di proyek != 2 (=%d)', numel(proj.hw));
assert(~isempty(proj.indenter), 'indenter kosong di proyek');
assert(~isempty(proj.recs), 'recs (sumber editan) tak ikut tersimpan');
nLab = sum(arrayfun(@(c) ~isempty(c.label), proj.curves));
assert(nLab >= 2, 'kurva berlabel < 2 di proyek');
assert(proj.nFrames == h.nF, 'nFrames proyek != nF GRAIN4');
fprintf('[ok] GRAIN4 -> %s (%d kurva, %d HW, indenter %d titik)\n', ...
    i_bn(axP), numel(proj.curves), numel(proj.hw), numel(proj.indenter));

% --- GRAINAXPOT: muat -> tambah titik info -> ekspor PNG/JPEG/JSON + simpan ---
GRAINAXPOT(axP);
af = findall(0,'Type','figure','-regexp','Name','GRAINAXPOT');
assert(~isempty(af),'figure GRAINAXPOT tak terbuka'); af = af(1);
clnA = onCleanup(@() i_close(af));
ha = guidata(af);
assert(isfield(ha,'ax') && ishghandle(ha.ax), 'kanvas axes tak ada');
% set ukuran + nama + garis frame
set(ha.edW,'String','12'); set(ha.edH,'String','7'); set(ha.edDPI,'String','150');
set(ha.edFrameLines,'String', num2str(max(2,round(ha.proj.nFrames/2))));
set(ha.edName,'String','uji axpot fig');   % -> uji_axpot_fig
% tambah titik informasi
i_click2(af, '➕ Titik');
ha = guidata(af);
assert(~isempty(ha.proj.infoPoints), 'titik informasi tak tertambah');
% ekspor semua + json
i_click2(af, '📦 Semua');
outdir = fileparts(axP);
png = fullfile(outdir,'uji_axpot_fig.png');
jpg = fullfile(outdir,'uji_axpot_fig.jpg');
js  = fullfile(outdir,'uji_axpot_fig.json');
clnO = onCleanup(@() i_rmMany({png,jpg,js}));
assert(isfile(png), 'PNG tak diekspor');
assert(isfile(jpg), 'JPEG tak diekspor');
assert(isfile(js),  'JSON tak diekspor');
jj = jsondecode(fileread(js));
assert(isfield(jj,'display') && isfield(jj,'infoPoints'), 'JSON tak lengkap');
fprintf('[ok] GRAINAXPOT ekspor: PNG+JPEG+JSON (12×7cm @150dpi)\n');

% --- EDIT KURVA di GRAINAXPOT (trim / assign HW / buang) = turunan dihitung ulang ---
ha = guidata(af);
assert(~isempty(ha.proj.recs), 'recs tak tersedia di GRAINAXPOT (edit mati)');
nHWbefore = numel(ha.proj.hw);
% assign HW-3 ke kurva mentah pertama yang belum berlabel
unl = find(arrayfun(@(c) isempty(c.label), ha.proj.curves), 1);
assert(~isempty(unl), 'tak ada kurva mentah utk diuji assign');
ha.selCurveRows = unl; guidata(af, ha);
set(ha.popType,'Value', find(strcmp(get(ha.popType,'String'),'HW')));
set(ha.edNum,'String','3');
i_click2(af, '🏷 Assign ke terpilih');
ha = guidata(af);
assert(any(arrayfun(@(w) w.num==3, ha.proj.hw)), 'assign HW-3 tak tercermin di turunan hw');
assert(numel(ha.proj.hw) == nHWbefore+1, 'jumlah HW tak bertambah setelah assign');
% trim kurva HW-1 (baris 1) ke max indenter
ha.selCurveRows = 1; guidata(af, ha);
i_click2(af, '✂ Trim → max indenter');
ha = guidata(af);
assert(ha.proj.recs(1).cutManual==true, 'trim tak menandai cutManual');
% buang kurva lalu pulih
ha.selCurveRows = unl; guidata(af, ha);
i_click2(af, '🗑 Buang kurva');
ha = guidata(af);
assert(pivcore.io.axpotProject.recExcluded(ha.proj.recs(unl)), 'buang tak menandai excluded');
ha.selCurveRows = unl; guidata(af, ha);
i_click2(af, '♻ Pulih kurva');
ha = guidata(af);
assert(~pivcore.io.axpotProject.recExcluded(ha.proj.recs(unl)), 'pulih tak melepas excluded');
fprintf('[ok] GRAINAXPOT edit: assign HW-3 + trim + buang/pulih (turunan konsisten)\n');

% --- layout DEFAULT: per-FOLDER (_axpot_defaults.json) + pref global ---
folderDef = fullfile(fileparts(axP), '_axpot_defaults.json');
clnDef = onCleanup(@() i_rm(folderDef)); %#ok<NASGU>
i_click2(af, '⭐ Default folder');
assert(ispref('GRAINAXPOT','layout'), 'layout default global tak tersimpan');
assert(isfile(folderDef), 'default per-folder (_axpot_defaults.json) tak ditulis');
dpref = getpref('GRAINAXPOT','layout');
assert(isstruct(dpref) && isfield(dpref,'widthCm') && ~isfield(dpref,'outName'), ...
    'pref layout salah (harus tanpa outName)');
fprintf('[ok] GRAINAXPOT default folder+global tersimpan (widthCm=%g)\n', dpref.widthCm);

% --- simpan proyek (round-trip display + infoPoints + frameRefs + recs editan) ---
i_click2(af, '💾 Simpan proyek');
proj2 = pivcore.io.axpotProject.load(axP);
assert(isstruct(proj2.display) && isfield(proj2.display,'widthCm') && proj2.display.widthCm==12, ...
    'display tak ter-round-trip (widthCm)');
assert(~isempty(proj2.infoPoints), 'infoPoints tak tersimpan ke proyek');
assert(~isempty(proj2.frameRefs), 'frameRefs tak terisi dari titik info');
assert(~isempty(proj2.recs) && proj2.recs(1).cutManual==true, 'edit recs (trim) tak ter-round-trip');
assert(any(arrayfun(@(w) w.num==3, proj2.hw)), 'assign HW-3 tak ter-round-trip ke proyek');
fprintf('[ok] GRAINAXPOT round-trip: display(12cm) + %d titik info + frameRefs %s + recs editan\n', ...
    numel(proj2.infoPoints), mat2str(proj2.frameRefs));

% --- FITUR BARU: spinner kanvas / judul / Next HW+sorot / X-strain non-flip ---
ha = guidata(af);
% (a) spinner Lebar ±1 (panggil callback tombol ▲ Lebar langsung)
w0 = str2double(get(ha.edW,'String'));
cbW = get(ha.btnWup,'Callback'); cbW(ha.btnWup, struct());
assert(str2double(get(ha.edW,'String'))==w0+1, 'spinner Lebar +1 gagal');
% (b) Judul -> render + round-trip
set(ha.edTitle,'String','AX POT Uji'); i_click2(af, '↻ Terapkan & render');
assert(strcmp(get(get(ha.ax,'Title'),'String'),'AX POT Uji'), 'judul tak terrender');
% (c) Next HW: pilih baris HW + garis sorot MERAH di kanvas (paritas GRAIN4)
i_click2(af, 'Next ▶');
ha = guidata(af);
assert(~isempty(ha.selCurveRows), 'Next HW tak memilih baris kurva');
assert(~isempty(findall(ha.ax,'Tag','selCurve')), 'tak ada sorot merah setelah Next HW');
% (d) sumbu-X strain NEGATIF -> XDir reverse (frame tetap baca kiri->kanan)
if isfinite(ha.proj.strainTotalPct) && ha.proj.strainTotalPct < 0
    set(ha.btnXUnit,'Value',1); cbx = get(ha.btnXUnit,'Callback'); cbx(ha.btnXUnit,[]);
    assert(strcmp(get(ha.ax,'XDir'),'reverse'), 'X-strain negatif harus XDir reverse');
end
fprintf('[ok] GRAINAXPOT fitur baru: spinner ±1 + judul + Next HW(sorot merah) + X-strain non-flip\n');

% --- 4 TAB + tabel kurva POT tampil + seleksi-baris → SOROT MERAH ---
ha = guidata(af);
tabTitles = arrayfun(@(t) string(get(t,'Title')), get(ha.tg,'Children'));
assert(numel(tabTitles)==4, 'harus 4 tab (Tata letak / Layer / Assign / Batch)');
assert(any(contains(tabTitles,'Tata letak')) && any(contains(tabTitles,'Layer')) ...
    && any(contains(tabTitles,'Assign')) && any(contains(tabTitles,'Batch')), ...
    'judul 4 tab salah: %s', strjoin(tabTitles,' | '));
Dc = get(ha.tblCurves,'Data');
assert(~isempty(Dc) && size(Dc,1)==numel(ha.proj.recs), 'tabel kurva POT tak tampil penuh (%d baris)', size(Dc,1));
% klik baris 1 lewat CellSelectionCallback (akses .Indices langsung spt GUI nyata)
cbSel = get(ha.tblCurves,'CellSelectionCallback'); cbSel(ha.tblCurves, struct('Indices',[1 1]));
ha = guidata(af);
assert(isequal(ha.selCurveRows,1), 'seleksi baris-1 tak tercatat (selCurveRows=%s)', mat2str(ha.selCurveRows));
assert(~isempty(findall(ha.ax,'Tag','selCurve')), 'baris terpilih tak menyorot kurva merah di kanvas');
fprintf('[ok] GRAINAXPOT 4 tab + tabel kurva POT (%d baris) + seleksi→sorot merah\n', size(Dc,1));

% --- KALIBRASI sumbu-Y 3 OPSI (px/frame → cm/s, default geom) + JUJUR + tombol melayang ---
ha = guidata(af);
% default sumber = geom (opsi 3)
assert(get(ha.popYSrc,'Value')==3, 'default sumber kalibrasi Y harus geom (opsi 3)');
% jujur: aktif tanpa multiplier/kalibrasi -> tetap px/frame
set(ha.btnYUnit,'Value',1); cbY = get(ha.btnYUnit,'Callback'); cbY(ha.btnYUnit,[]);
% (proyek uji nyata bisa saja TAK punya geom/dt -> harus tetap px/frame; jujur)
% Suntik geom + dt lalu OPSI 3 (geom) lewat engine: dxCm/((nF-1)dt)/indMax
hy = guidata(af);
hy.proj.geomCal = struct('dxCm',1.25,'cmPerPx',0.02,'strainPct',hy.proj.strainTotalPct);
hy.proj.timing  = struct('dtSec',12,'source','exif','medianExifSec',12,'nValidExif',10);
guidata(af, hy);
[mg,~,okG] = pivcore.io.axpotProject.velMult(hy.proj,'geom');
indMax = max(hy.proj.indenter(isfinite(hy.proj.indenter)));
assert(okG && abs(mg - (1.25/((hy.proj.nFrames-1)*12))/indMax) < 1e-9, 'velMult geom salah (%.6g)', mg);
% set ke kontrol + ⚙ Hitung + aktifkan
set(ha.edDt,'String','12'); cbAuto = get(ha.btnAutoMult,'Callback'); cbAuto(0,0);
set(ha.btnYUnit,'Value',1); cbY(ha.btnYUnit,[]);
[fy,laby,okY] = pivcore.io.axpotProject.yFactor(guidata(af).proj,'px');
assert(okY && abs(fy-mg)<1e-6 && contains(laby,'cm/s'), 'yFactor geom GUI salah (f=%.6g)', fy);
% 3 tombol melayang ada, diparent ke FIGURE (overlay), warna sesuai
assert(isequal(get(ha.btnFloatSave,'Parent'),af), 'tombol Save harus melayang (parent=figure)');
assert(isequal(get(ha.btnFloatSave,'BackgroundColor'),[0.20 0.65 0.25]), 'Save bukan hijau');
assert(isequal(get(ha.btnFloatClose,'BackgroundColor'),[0.80 0.15 0.15]), 'Close bukan merah');
fprintf('[ok] GRAINAXPOT kalibrasi Y 3-opsi (geom default, cm/s, f=%.4g) + 3 tombol melayang\n', fy);

% --- Tab④ Batch + Export single (folder AXPOT_jpg/AXPOT_<ts>/, nama AXPOT_<exp>_<ts>.jpg) ---
ha = guidata(af);
axpDir = fileparts(axP);
jpgRoot = fullfile(axpDir, 'AXPOT_jpg');
clnJpg = onCleanup(@() i_rmDirSafe(jpgRoot)); %#ok<NASGU>
% single
cbSingle = get(findobj(af,'String','🖼 Export single (uji)'),'Callback'); cbSingle(0,0);
dS = dir(fullfile(jpgRoot,'AXPOT_*'));
assert(~isempty(dS), 'Export single tak membuat folder AXPOT_jpg/AXPOT_<ts>');
jS = dir(fullfile(jpgRoot, dS(1).name, 'AXPOT_*.jpg'));
assert(~isempty(jS) && startsWith(jS(1).name,'AXPOT_'), 'nama berkas single salah: %s', jS(1).name);
% batch (proyek ini saja)
ha = guidata(af); ha.batchFiles = {axP}; guidata(af, ha);
cbRun = get(ha.btnBatchRun,'Callback'); cbRun(0,0);
dB = dir(fullfile(jpgRoot,'AXPOT_*')); assert(numel(dB)>=2, 'batch tak membuat folder baru');
nJpg = 0; for k=1:numel(dB), nJpg = nJpg + numel(dir(fullfile(jpgRoot,dB(k).name,'*.jpg'))); end
assert(nJpg>=2, 'batch+single harusnya >=2 jpg (%d)', nJpg);
fprintf('[ok] GRAINAXPOT tab④ Batch + Export single → AXPOT_jpg/AXPOT_<ts>/ (%d jpg)\n', nJpg);

% --- Tombol 📂 Open: muat proyek lain di jendela yg SAMA (in-place) — TERAKHIR ---
ha = guidata(af);
assert(ishghandle(ha.btnFloatOpen) && isequal(get(ha.btnFloatOpen,'Parent'),af), ...
    'tombol Open tak ada / tak melayang');
p2dir = tempname; mkdir(p2dir);
p2 = fullfile(p2dir, 'EXP_LOAD2_axpot.mat');
clnP2 = onCleanup(@() i_rmDirSafe(p2dir)); %#ok<NASGU>
q = pivcore.io.axpotProject.empty('/x/EXP_LOAD2.mat'); q.nFrames = 7; q.strainTotalPct = 2;
q.curves(end+1) = pivcore.io.axpotProject.curveStruct(1,'',[0.4 0.4 0.4],100,NaN,false,[0 1 2 3 4 5 6]);
pivcore.io.axpotProject.save(p2, q);
setappdata(af,'grainaxpotOpenOverride', p2);
cbOpen = get(ha.btnFloatOpen,'Callback'); cbOpen(0,0);
hb = guidata(af);
assert(strcmp(hb.projFile, p2), 'projFile tak berganti setelah Open (%s)', hb.projFile);
assert(hb.proj.nFrames==7, 'proyek baru tak termuat (nF=%d)', hb.proj.nFrames);
assert(strcmp(get(hb.edTitle,'String'),'EXP_LOAD2'), 'judul tak ikut proyek baru: %s', get(hb.edTitle,'String'));
fprintf('[ok] GRAINAXPOT 📂 Open muat proyek lain in-place (nF 7, judul EXP_LOAD2)\n');

fprintf('==== GRAINAXPOT SEMUA LULUS ✓ ====\n');
end

function i_rmDirSafe(d)
    try, if ~isempty(d) && isfolder(d), rmdir(d,'s'); end, catch, end
end

function i_restorePref(had, old)
    try
        if had, setpref('GRAINAXPOT','layout', old);
        elseif ispref('GRAINAXPOT','layout'), rmpref('GRAINAXPOT','layout');
        end
    catch
    end
end


% ---------------------------------------------------------------------
function i_click(parent, str)
    b = findobj(parent,'Style','pushbutton','String',str);
    assert(~isempty(b), 'tombol "%s" tak ada', str);
    cb = get(b(1),'Callback'); if ~isempty(cb), feval(cb, b(1), struct()); end
end
function i_click2(fig, str)   % cari tombol di seluruh figure
    b = findobj(fig,'Style','pushbutton','String',str);
    assert(~isempty(b), 'tombol "%s" tak ada', str);
    cb = get(b(1),'Callback'); if ~isempty(cb), feval(cb, b(1), struct()); end
end
function i_close(fig), try, if ishghandle(fig), delete(fig); end, catch, end, end
function i_rm(f), try, if ~isempty(f)&&isfile(f), delete(f); end, catch, end, end
function i_rmMany(C), for k=1:numel(C), i_rm(C{k}); end, end
function b = i_bn(p), [~,n,e] = fileparts(p); b = [n e]; end
