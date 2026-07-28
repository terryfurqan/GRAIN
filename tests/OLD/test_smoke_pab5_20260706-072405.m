function test_smoke_pab5(rootDir)
%TEST_SMOKE_PAB5  Uji headless PAB5 — TAB ⑨ EXPORT SESAR (kanal CLCW).
%   Cakupan: build + TAB ⑨ ada; buat 1 sesar LENGKAP (HW/FW + 4 POI) via edit sel
%   + assign + POI; garis vertikal POI di axPOT (Tag 'poiVline'); export sesar
%   terpilih -> folder PAB5_export/<exp>/F<no>/ (ke TMP override) berisi JSON +
%   gambar; JSON round-trip (POI/kurva/net-slip/daftar gambar); export SEMUA.
%   Engine pab5FaultExport diuji unit (naming/folderTag/buildFaultJson).
%
%   test_smoke_pab5_temp                 % default fixture RAW/PIV_2026-06-24
%   test_smoke_pab5_temp('/path/folder')

fprintf('==== TEST SMOKE PAB5 (TAB ⑨ export sesar) ====\n');
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

% ============ A. Engine pab5FaultExport (unit, headless) ============
fA = struct('id','F3','uiNum',3,'hwPosPx',120,'fwPosPx',200, ...
    'nuc',12,'fsr',16,'startF',5,'endF',20,'area',3.5,'dNet',1.2,'angleDeg',22, ...
    'values',[0 0.1 0.2],'parentId','');
assert(strcmp(pivcore.io.pab5FaultExport.folderTag(fA),'F3'), 'folderTag F3 salah');
% uiNum kosong -> pakai id.
fB = fA; fB.uiNum = NaN; fB.id = 'F7';
assert(strcmp(pivcore.io.pab5FaultExport.folderTag(fB),'F7'), 'folderTag turun-dari-id salah');
% duplikat nomor (uiNum=3 tapi id F12) -> disambiguasi suffix.
fC = fA; fC.id = 'F12';
tagC = pivcore.io.pab5FaultExport.folderTag(fC);
assert(strcmp(tagC,'F3_F12'), sprintf('folderTag disambiguasi salah: %s', tagC));
df = fullfile(rootDir,'MY-EXP.mat');
imnm = pivcore.io.pab5FaultExport.imageFile(df, fA, 'velmag', 'start');
assert(strcmp(imnm,'MY-EXP_F3_velmag_start.png'), sprintf('imageFile salah: %s', imnm));
axnm = pivcore.io.pab5FaultExport.axpotFile(df, fA);
assert(strcmp(axnm,'MY-EXP_F3_axpot.png'), sprintf('axpotFile salah: %s', axnm));
axzn = pivcore.io.pab5FaultExport.axpotZoomFile(df, fA);
assert(strcmp(axzn,'MY-EXP_F3_axpot_zoom.png'), sprintf('axpotZoomFile salah: %s', axzn));
assert(strcmp(pivcore.io.pab5FaultExport.netslipAllFile(df,fA),'MY-EXP_F3_netslip_all.png'), 'netslipAllFile salah');
assert(strcmp(pivcore.io.pab5FaultExport.netslipAllZoomFile(df,fA),'MY-EXP_F3_netslip_all_zoom.png'), 'netslipAllZoomFile salah');
% strainAtFrame: (k-1)/(nF-1)*total. nF=26, total=-40 -> f6 = -8%.
assert(abs(pivcore.io.pab5FaultExport.strainAtFrame(6,26,-40) - (-8)) < 1e-9, 'strainAtFrame salah');
% CALIBRATED JSON (v2): POI in cumulative strain %, netslip in cm/s.
js = pivcore.io.pab5FaultExport.buildFaultJson(df, fA, ...
    struct('nFrames',21,'strainTotalPct',-40,'velMult',0.01,'hwCurveNum',5,'fwCurveNum',9));
assert(js.formatVersion==2, 'JSON harus formatVersion 2 (terkalibrasi)');
assert(strcmp(js.faultId,'F3') && js.faultNumber==3, 'buildFaultJson id/number salah');
% frame 5 of nF=21, total -40% -> (5-1)/20*-40 = -8% ; frame 20 -> 19/20*-40 = -38%.
assert(abs(js.poi.start-(-8))<1e-9 && abs(i_endOf(js.poi)-(-38))<1e-9, 'POI strain% salah');
assert(js.poiFrame.start==5 && i_endOf(js.poiFrame)==20, 'poiFrame (raw) salah');
% netslip cm/s = values(px/frame) * velMult(0.01).
assert(numel(js.netslip)==3 && abs(js.netslip(2)-0.1*0.01)<1e-12, 'netslip cm/s salah');
% area cm/s-scaled = 3.5 * 0.01.
assert(abs(js.area-3.5*0.01)<1e-12, 'area cm/s salah');
assert(js.hw.posPx==120 && js.hw.curveNum==5 && js.fw.curveNum==9, 'HW/FW JSON salah');
assert(strcmp(js.units.netslip,'cm/s') && strcmp(js.units.poi,'cumulative strain (%)'), 'units string salah');
assert(abs(js.calibration.velMult-0.01)<1e-12, 'calibration.velMult salah');
% NaN POI -> null ([]).
fD = fA; fD.nuc = NaN;
jD = pivcore.io.pab5FaultExport.buildFaultJson(df, fD, struct('nFrames',21,'strainTotalPct',-40));
assert(isempty(jD.poi.nuc), 'POI NaN semestinya null ([]) di JSON');
% strainTotalPct unknown -> POI null (tak bisa dikalibrasi).
jN = pivcore.io.pab5FaultExport.buildFaultJson(df, fA, struct('nFrames',21));
assert(isempty(jN.poi.start), 'POI semestinya null saat strainTotalPct tak diketahui');
fprintf('[ok] A. engine pab5FaultExport (folderTag/zoom/strainAtFrame/JSON terkalibrasi cm/s+strain%%)\n');

% Bersihkan _faults dulu (uji ini yang punya).
d = dir(fullfile(rootDir,'*_faults.json')); for i=1:numel(d), delete(fullfile(rootDir,d(i).name)); end

% ============ B. Build GUI + TAB ⑨ ada ============
fig = PAB5(rootDir, 'tab','export');
assert(ishghandle(fig), 'figure PAB5 tak terbuka');
cln = onCleanup(@() i_close(fig)); %#ok<NASGU>
h = guidata(fig);
% AUTO-LOAD exp DIMATIKAN (user pilih manual) -> tak ada exp dimuat saat build.
% Test simulasikan seleksi user: muat eksperimen-1 secara eksplisit.
assert(isempty(h.df), 'auto-load exp semestinya MATI (h.df kosong saat build)');
% Tabel eksperimen (kiri, mode 'exp') punya 2 kolom EXTRA: F id + F ✓.
assert(strcmp(h.leftMode,'exp'), 'saat build leftMode harus exp (belum muat)');
cnExp = get(h.tbl,'ColumnName');
assert(numel(cnExp)==5, sprintf('tabel exp harus 5 kolom (3+2 extra), dapat %d', numel(cnExp)));
assert(any(contains(cnExp,'id')) && any(contains(cnExp,'✓')), 'kolom extra F id / F ✓ tak ada');
% Hook hitung (h.expTableExtra): exp bersih (belum ada _faults) -> 0 id / 0 ✓.
assert(isa(h.expTableExtra,'function_handle'), 'hook expTableExtra tak ada');
ec = h.expTableExtra(h.list(1).file);
assert(iscell(ec) && numel(ec)==2 && strcmp(ec{1},'0') && strcmp(ec{2},'0'), ...
    'hitungan F# awal harus 0/0 (fixture bersih)');
pivui.pab4Shell.loadExperiment(fig, 1); h = guidata(fig);
% Fixture bersih (tanpa _potdata/_autopot) -> garis 75% BELUM disampel (recs=0
% by design; "kunci utk sampel"). Sampel eksplisit supaya test independen dari
% sidecar lokal yang mungkin sudah dihapus run sebelumnya.
if isempty(h.recs)
    pivui.pab4Shell.collectPOT(fig); h = guidata(fig);
end
assert(~isempty(h.recs), 'recs kosong (collectPOT gagal menyampel garis 75%)');
assert(isfield(h,'tabExport') && isvalid(h.tabExport), 'tabExport (TAB ⑨) tak ada');
assert(h.tg.SelectedTab==h.tabExport, "default 'tab','export' tak ke TAB ⑨");
for fn = {'tblExport','btnExpSel','btnExpAll','chkExpVel','chkExpShear','chkExpAxpot','edExpDpi'}
    assert(isfield(h,fn{1}) && ishghandle(h.(fn{1})), sprintf('kontrol %s tak ada', fn{1}));
end
cnE = get(h.tblExport,'ColumnName');
assert(numel(cnE)==9 && strcmp(cnE{1},'F#'), 'kolom tabel export salah');
fprintf('[ok] B. build + TAB ⑨ (kontrol export lengkap; default tab=Export)\n');

% ============ B2. Auto-fill F1..F15 + spinner ukuran titik ============
% Exp fixture (sidecar _faults dibersihkan) -> auto-fill 15 sesar bernomor 1..15.
nAuto = 0; for k=1:numel(h.fdoc.faults), if isfinite(pivui.pab5Model.faultUiNum(h.fdoc.faults{k})), nAuto=nAuto+1; end, end
assert(nAuto>=15, sprintf('auto-fill harus >=15 sesar, dapat %d', nAuto));
for want = {'F1','F8','F15'}
    [~,ix] = pivcore.io.pab5Faults.findFault(h.fdoc, want{1});
    assert(ix>=1, sprintf('auto-fill: %s tak ada', want{1}));
end
% Spinner ukuran titik indikator ada + berfungsi.
assert(isfield(h,'indMarkerSize'), 'state indMarkerSize tak ada');
ms0 = h.indMarkerSize;
bUp = findall(fig,'Tag','spIndUp'); assert(~isempty(bUp), 'spinner ukuran titik (spIndUp) tak ada');
cbu = get(bUp(1),'Callback'); cbu(bUp(1),[]);
h = guidata(fig); assert(h.indMarkerSize>ms0, 'spinner titik tak menaikkan ukuran');
fprintf('[ok] B2. auto-fill F1..F15 (%d) + spinner ukuran titik (%d->%d)\n', nAuto, ms0, h.indMarkerSize);

% ============ B3. Tabel sesar 12 kolom + on/off sesar ============
set(h.tg,'SelectedTab',h.tabLbl); h = guidata(fig);
cn = get(h.tblFault,'ColumnName');
assert(numel(cn)==12 && strcmp(cn{1},'⏻') && strcmp(cn{2},'✓') && strcmp(cn{3},'F#'), ...
    sprintf('tabel sesar harus 12 kolom (⏻/✓/F#...), dapat %d', numel(cn)));
ce = get(h.tblFault,'ColumnEditable');
assert(numel(ce)==12 && ce(3) && ~ce(1) && ~ce(2) && ~ce(4), 'ColumnEditable: hanya F# (kol 3)');
% Default semua sesar ON.
[fA,~] = pivcore.io.pab5Faults.findFault(h.fdoc,'F1');
assert(pivui.pab5Model.faultEnabled(fA), 'sesar F1 default harus ON (enabled)');
% Toggle OFF via klik sel kolom ⏻ (kolom 1).
rF1 = find(strcmp('F1', h.faultIds),1);
cbSel = get(h.tblFault,'CellSelectionCallback'); cbSel(h.tblFault, struct('Indices',[rF1 1]));
h = guidata(fig); [fA,~] = pivcore.io.pab5Faults.findFault(h.fdoc,'F1');
assert(~pivui.pab5Model.faultEnabled(fA), 'klik sel ⏻ tak menonaktifkan F1');
dTbl = get(h.tblFault,'Data'); assert(strcmp(dTbl{rF1,1},'✗'), 'sel ⏻ off harus tampil ✗');
% Toggle ON lagi via tombol ⏻ On/Off (sesar aktif).
h.activeFaultId='F1'; guidata(fig,h);
i_fire(fig,'⏻ On/Off');
h = guidata(fig); [fA,~] = pivcore.io.pab5Faults.findFault(h.fdoc,'F1');
assert(pivui.pab5Model.faultEnabled(fA), 'tombol ⏻ On/Off tak mengaktifkan F1');
fprintf('[ok] B3. tabel 12 kolom + on/off (klik sel ⏻ + tombol On/Off)\n');

df1 = h.df;
faultsP = pivcore.io.pab5Faults.dataPath(df1);
potP = pivcore.io.pab4PotData.dataPath(df1); prePot = isfile(potP);

% ============ C. Buat 1 sesar LENGKAP (HW/FW + 4 POI) ============
% Pindah ke Tab ① utk edit (assign & POI di sana; render tetap tampil).
set(h.tg,'SelectedTab',h.tabLbl); h = guidata(fig);
i_editCell(fig,1,3,'1');                    % F#=1 (kolom 3 skrg; kol1=on/off, kol2=✓POI)
h = guidata(fig); assert(strcmp(h.activeFaultId,'F1'), 'F1 tak dibuat');
i_selCurve(fig,5);  i_fire(fig,'⬆ Jadikan HW');
i_selCurve(fig,25); i_fire(fig,'⬇ Jadikan FW');
i_setFrame(fig,5);  i_fire(fig,'START');
i_setFrame(fig,12); i_fire(fig,'NUC');
i_setFrame(fig,16); i_fire(fig,'FSR');
i_setFrame(fig,20); i_fire(fig,'END');
h = guidata(fig); [f1,~] = pivcore.io.pab5Faults.findFault(h.fdoc,'F1');
assert(isfinite(f1.startF)&&isfinite(f1.nuc)&&isfinite(f1.fsr)&&isfinite(f1.endF), 'POI F1 belum lengkap');
fprintf('[ok] C. sesar F1 lengkap (HW/FW + START=%g NUC=%g FSR=%g END=%g)\n', ...
    f1.startF, f1.nuc, f1.fsr, f1.endF);

% --- C2. Hitungan kolom exp update setelah _faults.json ditulis (F1 lengkap) ---
h = guidata(fig);
pivcore.io.pab5Faults.write(df1, h.fdoc);      % tulis sidecar (simulasi Save)
ec2 = h.expTableExtra(df1);
assert(str2double(ec2{1})>=1, 'F identified harus >=1 setelah F1 ber-HW/FW disimpan');
assert(str2double(ec2{2})>=1, 'F checklist harus >=1 setelah F1 POI-lengkap disimpan');
fprintf('[ok] C2. kolom exp hitung F#: identified=%s checklist=%s\n', ec2{1}, ec2{2});

% ============ D. Garis vertikal POI di axPOT HANYA saat TAB ⑨ aktif ============
h = guidata(fig); h.activeFaultId='F1'; guidata(fig,h);
% Di Tab ① (F# Anlz): garis vertikal POI TAK boleh muncul.
i_gotoTab(fig, h.tabLbl); h = guidata(fig);
pivui.pab4Shell.renderPOT(fig); h = guidata(fig);
vlLbl = findall(h.axPOT,'Tag','poiVline');
assert(isempty(vlLbl), 'garis vertikal POI semestinya TAK muncul di Tab ① (hanya TAB ⑨)');
% Di TAB ⑨ (Export): garis vertikal POI MUNCUL.
i_gotoTab(fig, h.tabExport); h = guidata(fig);
pivui.pab4Shell.renderPOT(fig); h = guidata(fig);
vl = findall(h.axPOT,'Tag','poiVline');
assert(~isempty(vl), 'garis vertikal POI (Tag poiVline) tak ada di axPOT saat TAB ⑨');
assert(numel(vl) >= 8, sprintf('garis+label POI kurang (dapat %d, harap >=8)', numel(vl)));
fprintf('[ok] D. garis vertikal POI: OFF di Tab ①, ON di TAB ⑨ (%d objek)\n', numel(vl));

% ============ D2. Hotkey baru (POI jump / assign / geser kurva) + TAB ⓪ Help ==
% TAB ⓪ Help ada di kanan TAB ⑨ + kontrol hotkey list.
assert(isfield(h,'tabHelp') && isvalid(h.tabHelp), 'tabHelp (TAB ⓪) tak ada');
kids = h.tg.Children; iExp = find(kids==h.tabExport,1); iHlp = find(kids==h.tabHelp,1);
assert(~isempty(iExp) && ~isempty(iHlp) && iHlp==iExp+1, 'TAB ⓪ Help harus tepat di kanan TAB ⑨');
helpEd = findall(h.tabHelp,'Style','edit');
assert(~isempty(helpEd), 'panel daftar hotkey (edit) di Help tab tak ada');
hs = get(helpEd(1),'String');
assert(iscell(hs) && any(contains(hs,'Ctrl + J')) && any(contains(hs,'Ctrl + Q')), 'daftar hotkey tak lengkap');
% Hotkey jump: set POI F1 (START=5, END=20 sudah), pindah tab sesar, uji jump.
set(h.tg,'SelectedTab',h.tabLbl); h = guidata(fig); h.activeFaultId='F1'; guidata(fig,h);
kp = get(fig,'WindowKeyPressFcn');
i_setFrame(fig,1);
kp(fig, FakeKeyData('j','j',{'control'}));   % jump START=5
h = guidata(fig); assert(h.frame==5, sprintf('Ctrl+J (START) harus frame 5, dapat %d', h.frame));
kp(fig, FakeKeyData('k','k',{'control'}));   % jump END=20
h = guidata(fig); assert(h.frame==20, sprintf('Ctrl+K (END) harus frame 20, dapat %d', h.frame));
% Hotkey geser seleksi kurva (mode 'curve' aktif di sini).
h = guidata(fig); h.leftMode='curve'; h.selRows=10; guidata(fig,h);
kp(fig, FakeKeyData('rightbracket',']',{'control'}));   % turun 1 -> 11
h = guidata(fig); assert(h.selRows(1)==11, sprintf('Ctrl+] turun1 harus 11, dapat %d', h.selRows(1)));
kp(fig, FakeKeyData('leftbracket','{',{'control','shift'}));  % naik 5 -> 6
h = guidata(fig); assert(h.selRows(1)==6, sprintf('Ctrl+{ naik5 harus 6, dapat %d', h.selRows(1)));
% Hotkey assign: pilih kurva lalu Ctrl+Q=HW.
h = guidata(fig); h.selRows=8; guidata(fig,h);
try, set(fig,'CurrentObject',h.axPOT); catch, end
pivui.pab4Shell.callHook(fig,'onCurveClick',8);
kp(fig, FakeKeyData('q','q',{'control'}));
h = guidata(fig); [fA1,~]=pivcore.io.pab5Faults.findFault(h.fdoc,'F1');
assert(isfinite(fA1.hwPosPx), 'Ctrl+Q tak meng-assign HW');
% Ctrl+E = klik tombol Hitung sudut sesar (toggle Value flip; headless -> ROI
% batal tapi flip terpanggil). Verifikasi tombol ada + callback tak error.
assert(isfield(h,'btnMeasAngle') && ishghandle(h.btnMeasAngle), 'btnMeasAngle tak ada');
v0 = get(h.btnMeasAngle,'Value');
kp(fig, FakeKeyData('e','e',{'control'}));   % tak error (headless: ON dibatalkan)
h = guidata(fig);
assert(ishghandle(h.btnMeasAngle), 'Ctrl+E merusak tombol sudut');
fprintf('[ok] D2. hotkey POI-jump(J/K)+geser(]/{)+assign(Q)+ukur-sudut(E)+TAB ⓪ Help\n');
% Kembalikan HW F1 ke kurva 5 (asumsi test Export berikutnya).
h = guidata(fig); h.activeFaultId='F1'; guidata(fig,h);
i_selCurve(fig,5); i_fire(fig,'⬆ Jadikan HW');

% ============ E. Export SESAR TERPILIH -> folder TMP ============
tmpRoot = fullfile(tempdir, sprintf('pab5tmp_%d', feature('getpid')));
if isfolder(tmpRoot), rmdir(tmpRoot,'s'); end
mkdir(tmpRoot);
cleanTmp = onCleanup(@() i_rmdir(tmpRoot)); %#ok<NASGU>
h = guidata(fig); h.exportRootOverride = tmpRoot; guidata(fig,h);
% Pilih baris F1 di tabel export (Tab ⑨).
i_gotoTab(fig, h.tabExport); h = guidata(fig);
rF1 = find(strcmp('F1', h.exportIds),1);
assert(~isempty(rF1), 'F1 tak muncul di tabel export');
assert(h.exportReady(rF1), 'F1 semestinya SIAP (HW/FW + 4 POI)');
i_pickExport(fig, rF1);
i_fireH(fig, h.btnExpSel);                   % export sesar terpilih
h = guidata(fig);
% Cek folder + file.
[~, base1] = fileparts(df1);
fdir = fullfile(tmpRoot,'PAB5_export', i_safe(base1), 'F1');
assert(isfolder(fdir), sprintf('folder sesar tak dibuat: %s', fdir));
jsonP = fullfile(fdir, sprintf('%s_F1.json', i_safe(base1)));
assert(isfile(jsonP), '_F1.json tak ditulis');
% Gambar: axpot (full) + axpot_zoom + velmag/shear × 4 POI (asal render tak gagal).
axP = fullfile(fdir, sprintf('%s_F1_axpot.png', i_safe(base1)));
assert(isfile(axP), 'screenshot AX POT (full) tak dibuat');
% Zoom hanya dibuat bila nF > 200; fixture TKS-5 kecil -> zoom mungkin tak ada.
axZ = fullfile(fdir, sprintf('%s_F1_axpot_zoom.png', i_safe(base1)));
hasZoom = isfile(axZ);
% Net-slip plot (HW/FW lengkap -> ada): tunggal + SEMUA sesar.
nsP = fullfile(fdir, sprintf('%s_F1_netslip.png', i_safe(base1)));
assert(isfile(nsP), 'screenshot NET-SLIP (tunggal) tak dibuat');
nsAllP = fullfile(fdir, sprintf('%s_F1_netslip_all.png', i_safe(base1)));
assert(isfile(nsAllP), 'screenshot NET-SLIP ALL (semua sesar) tak dibuat');
velStart = fullfile(fdir, sprintf('%s_F1_velmag_start.png', i_safe(base1)));
assert(isfile(velStart), 'screenshot velmag START tak dibuat');
shearEnd = fullfile(fdir, sprintf('%s_F1_shear_end.png', i_safe(base1)));
assert(isfile(shearEnd), 'screenshot shear END tak dibuat');
fprintf('[ok] E. export terpilih F1 -> folder + JSON + gambar (axpot%s/velmag/shear)\n', ...
    i_tern(hasZoom,'+zoom',''));

% ============ F. JSON round-trip TERKALIBRASI (cm/s + strain%) ============
jd = jsondecode(fileread(jsonP));
assert(strcmp(jd.faultId,'F1'), 'JSON faultId salah');
assert(jd.faultNumber==1, 'JSON faultNumber salah');
assert(jd.formatVersion==2, 'JSON harus v2 (terkalibrasi)');
% poiFrame (raw) SELALU ada.
assert(jd.poiFrame.start==5 && jd.poiFrame.nuc==12 && jd.poiFrame.fsr==16 && i_endOf(jd.poiFrame)==20, ...
    'JSON poiFrame (raw) salah');
% poi (kalibrasi strain%): finite bila strainTotalPct ada, else null.
hasStrain = ~isempty(jd.calibration.strainTotalPct);
if hasStrain
    assert(~isempty(jd.poi.start), 'POI strain% semestinya ada (strainTotalPct ada)');
    st = jd.calibration.strainTotalPct; nF = h.nF;
    expStart = (5-1)/(nF-1)*st;
    assert(abs(jd.poi.start-expStart)<1e-6, 'POI strain% start salah');
else
    assert(isempty(jd.poi.start), 'POI semestinya null (strainTotalPct tak ada)');
end
% netslip cm/s: nilai = px/frame * velMult (default 0.005). Cek magnitudo wajar.
assert(isfield(jd,'netslip') && ~isempty(jd.netslip), 'JSON netslip kosong');
assert(abs(jd.calibration.velMult-0.005)<1e-9, 'velMult default 0.005 salah');
assert(strcmp(jd.units.netslip,'cm/s'), 'satuan netslip bukan cm/s');
assert(isfield(jd,'images') && isfield(jd.images,'axpot'), 'JSON images.axpot tak ada');
assert(isfield(jd.images,'velmag_start'), 'JSON images.velmag_start tak ada');
fprintf('[ok] F. JSON v2 terkalibrasi (poiFrame raw + poi strain%% + netslip cm/s; strain=%d)\n', hasStrain);

% Indeks global ditulis.
idxP = fullfile(tmpRoot,'PAB5_export','_export_index.json');
assert(isfile(idxP), '_export_index.json tak ditulis');
idx = jsondecode(fileread(idxP));
assert(isfield(idx,'entries') && ~isempty(idx.entries), 'indeks entries kosong');
fprintf('[ok] F2. indeks global _export_index.json\n');

% ============ G. Export SEMUA (assign F2 pada slot auto-fill) ============
% Auto-fill F1..F15 -> F2 sudah ADA sbg slot kosong (baris 2). Assign HW/FW/POI.
set(h.tg,'SelectedTab',h.tabLbl); h = guidata(fig);
rF2 = find(strcmp('F2', h.faultIds),1);
assert(~isempty(rF2), 'F2 semestinya ada dari auto-fill');
h.activeFaultId='F2'; guidata(fig,h);
i_selCurve(fig,40); i_fire(fig,'⬆ Jadikan HW');
i_selCurve(fig,60); i_fire(fig,'⬇ Jadikan FW');
i_setFrame(fig,8);  i_fire(fig,'START'); i_setFrame(fig,22); i_fire(fig,'END');
i_gotoTab(fig, h.tabExport);
h = guidata(fig);
i_fireH(fig, h.btnExpAll);                    % export SEMUA (hanya sesar ber-HW)
fdir2 = fullfile(tmpRoot,'PAB5_export', i_safe(base1), 'F2');
assert(isfolder(fdir2), 'export semua: folder F2 tak dibuat');
json2 = fullfile(fdir2, sprintf('%s_F2.json', i_safe(base1)));
assert(isfile(json2), 'export semua: F2 JSON tak ditulis');
% Slot auto-fill KOSONG (mis. F5, tanpa HW) TAK boleh diekspor.
fdirEmpty = fullfile(tmpRoot,'PAB5_export', i_safe(base1), 'F5');
assert(~isfolder(fdirEmpty), 'export semua: slot kosong F5 semestinya DILEWATI (tak ada HW)');
fprintf('[ok] G. export SEMUA (F1 & F2 ber-HW; slot kosong F5 dilewati)\n');

% State semula ter-restore (activeFaultId & frame tak nyangkut di POI terakhir).
h = guidata(fig);
assert(any(strcmp(h.activeFaultId, h.faultIds)) || isempty(h.activeFaultId), 'activeFaultId invalid setelah export');
fprintf('[ok] G2. state sesar aktif ter-restore\n');

delete(fig);
% cleanup sidecar
if ~prePot && isfile(potP), delete(potP); end
d = dir(fullfile(rootDir,'*_faults.json')); for i=1:numel(d), delete(fullfile(rootDir,d(i).name)); end
fprintf('==== PAB5 SEMUA LULUS ✓ ====\n');
end

% ---------------------------------------------------------------------
function i_editCell(fig, r, c, str)
    h = guidata(fig); tb = h.tblFault; cb = get(tb,'CellEditCallback');
    evt = struct('Indices',[r c], 'NewData',str, 'PreviousData','', 'EditData',str, 'Error',[]);
    if ~isempty(cb), cb(tb, evt); end
end
function i_pickExport(fig, r)
    h = guidata(fig); tb = h.tblExport; cb = get(tb,'CellSelectionCallback');
    if ~isempty(cb), cb(tb, struct('Indices',[r 1])); end
end
function i_fire(fig, str)
    b = findall(fig,'Type','uicontrol');
    for i=1:numel(b)
        s = get(b(i),'String');
        if ischar(s) && strcmp(s,str)
            cb = get(b(i),'Callback'); if ~isempty(cb), cb(b(i),[]); end, return;
        end
    end
    error('tombol tak ketemu: %s', str);
end
function i_fireH(fig, hc), cb=get(hc,'Callback'); if ~isempty(cb), cb(hc,[]); end, end
function i_gotoTab(fig, tab)
%I_GOTOTAB  Set tab + PICU SelectionChangedFcn (setSelectedTab tak memicunya).
    h = guidata(fig); set(h.tg,'SelectedTab',tab);
    cb = get(h.tg,'SelectionChangedFcn'); if ~isempty(cb), cb(h.tg,[]); end
end
function i_selCurve(fig, r)
    h = guidata(fig); h.selRows = r; guidata(fig,h);
    try, set(fig,'CurrentObject',h.axPOT); catch, end
    pivui.pab4Shell.callHook(fig,'onCurveClick', r);
end
function i_setFrame(fig, k), h = guidata(fig); h.frame = k; guidata(fig,h); end
function i_close(fig), try, if ishghandle(fig), delete(fig); end, catch, end, end
function i_rmdir(d), try, if isfolder(d), rmdir(d,'s'); end, catch, end, end
function s = i_safe(x)
    s = regexprep(char(x), '[^\w\-\.]+', '_'); s = regexprep(s,'_+','_'); s = regexprep(s,'^_+|_+$','');
    if isempty(s), s='exp'; end
end
function v = i_endOf(poi)
    v = NaN; fn = fieldnames(poi);
    for i=1:numel(fn), if strcmpi(fn{i},'end')||strcmp(fn{i},'x_end'), v = poi.(fn{i}); return; end, end
end
function s = i_tern(c,a,b), if c, s=a; else, s=b; end, end
