function test_smoke_grainlink(rootDir)
%TEST_SMOKE_GRAINLINK  Verifikasi pengikat strain antar-view: engine pivcore.io.grainLink
%   (golden 2-titik linear + round-trip JSON, tanda-aman shortening) + GUI GRAINLINK
%   (tandai 2 titik ikat → simpan sidecar) + GUI GRAINSYNC (strain master → frame).
%
%   test_smoke_grainlink                  % default: .../RAW/PIV_2026-06-24
%   test_smoke_grainlink('/path/folder')  % override folder berisi >=2 MAT PIV
%
%   Bagian engine MURNI (tak butuh data). Bagian GUI SKIP graceful bila <2 MAT.
%   Sidecar `<tgt>_link.json` yang dibuat dibersihkan.

fprintf('==== TEST SMOKE GRAINLINK ====\n');
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
roots = grain_setup(); %#ok<NASGU>

ov = get(0,'DefaultFigureVisible');
set(0,'DefaultFigureVisible','off');
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

% =================================================================
% A) ENGINE GOLDEN (linear 2-titik, shortening / strain NEGATIF)
% =================================================================
fprintf('-- A) engine golden --\n');
doc = pivcore.io.grainLink.emptyDoc('penampang.mat','peta.mat');
doc.reference.nFrames        = 111;
doc.reference.strainTotalPct = -2.94;     % shortening (sandbox anjak)
doc.reference.geomValid      = true;
doc.target.nFrames           = 110;
doc.target.geomValid         = false;

% strain acuan per frame (manual) untuk dibandingkan
sRefManual = @(f) (f-1)/(111-1) * (-2.94);
assert(abs(pivcore.io.grainLink.strainAtRef(doc,30) - sRefManual(30)) < 1e-9, 'strainAtRef salah');
assert(abs(pivcore.io.grainLink.frameAtRef(doc, sRefManual(77)) - 77) < 1e-6, 'frameAtRef inverse salah');

doc = pivcore.io.grainLink.setTie(doc, pivcore.io.grainLink.tieStruct('FSR pertama', 30, NaN, 31));
doc = pivcore.io.grainLink.setTie(doc, pivcore.io.grainLink.tieStruct('FSR terakhir',100, NaN, 99));
doc = pivcore.io.grainLink.calibrate(doc);

s1 = sRefManual(30); s2 = sRefManual(100);
bGold = (s2 - s1) / (99 - 31);
assert(doc.calibration.valid, 'kalibrasi seharusnya valid');
assert(abs(doc.calibration.slopePctPerFrame - bGold) < 1e-9, 'slope salah');
assert(abs(doc.calibration.refStrainPerFrame - (-2.94/110)) < 1e-9, 'refStrainPerFrame salah');
% tie.refStrainPct di-recompute dari refFrame
assert(abs(doc.tiePoints{1}.refStrainPct - s1) < 1e-9, 'refStrainPct tie1 salah');

% strainAtTgt di titik ikat = strain acuan; frameAtTgt inverse
assert(abs(pivcore.io.grainLink.strainAtTgt(doc,31) - s1) < 1e-9, 'strainAtTgt(31) salah');
assert(abs(pivcore.io.grainLink.strainAtTgt(doc,99) - s2) < 1e-9, 'strainAtTgt(99) salah');
assert(abs(pivcore.io.grainLink.frameAtTgt(doc, s1) - 31) < 1e-6, 'frameAtTgt(s1) salah');
% round-trip strain<->frame target
for f = [10 31 50 99 130]
    sf = pivcore.io.grainLink.strainAtTgt(doc, f);
    ff = pivcore.io.grainLink.frameAtTgt(doc, sf);
    assert(abs(ff - f) < 1e-6, 'round-trip strain<->frame target gagal');
end
% ekstrapolasi: frame target < frame0 dan > nF boleh keluar (tak di-clamp di strainAtTgt)
assert(isfinite(pivcore.io.grainLink.strainAtTgt(doc, 1)), 'ekstrapolasi frame1 NaN');
fprintf('   [ok] golden linear + inverse + recompute strain\n');

% sync table monoton & panjang benar
sv = pivcore.io.grainLink.defaultStrainVec(doc, 0.5);
assert(~isempty(sv) && all(diff(sv) > 0), 'defaultStrainVec tak monoton naik');
T = pivcore.io.grainLink.syncTable(doc, sv);
assert(numel(T) == numel(sv), 'syncTable panjang salah');
fRefs = [T.frameRef]; fTgts = [T.frameTgt];
assert(all(fRefs >= 1 & fRefs <= 111), 'frameRef di luar 1..nF');
assert(all(fTgts >= 1 & fTgts <= 110), 'frameTgt di luar 1..nF');
fprintf('   [ok] syncTable %d baris, frame ter-clamp\n', numel(T));

% guard: frame peta kedua titik ikat SAMA -> kalibrasi invalid, tak crash
docBad = pivcore.io.grainLink.setTie(doc, pivcore.io.grainLink.tieStruct('FSR terakhir',100,NaN,31));
docBad = pivcore.io.grainLink.calibrate(docBad);
assert(~docBad.calibration.valid, 'kalibrasi harusnya invalid saat frame peta sama');
assert(isnan(pivcore.io.grainLink.strainAtTgt(docBad, 50)), 'strainAtTgt harus NaN saat invalid');
fprintf('   [ok] guard frame-peta-sama → invalid (tak crash)\n');

% round-trip write -> read (NaN<->null, calibration di-recompute)
tmpTgt = [tempname '.mat'];
doc.target.path = tmpTgt;
pivcore.io.grainLink.write(tmpTgt, doc);
jp = pivcore.io.grainLink.dataPath(tmpTgt);
cleanJp = onCleanup(@() i_rm(jp)); %#ok<NASGU>
assert(isfile(jp), 'sidecar _link.json tak tertulis');
doc2 = pivcore.io.grainLink.read(tmpTgt);
assert(doc2.calibration.valid, 'kalibrasi hilang saat read');
assert(abs(doc2.calibration.slopePctPerFrame - bGold) < 1e-9, 'slope tak konsisten round-trip');
assert(numel(doc2.tiePoints) == 2, 'tiePoints tak lengkap round-trip');
assert(abs(doc2.reference.strainTotalPct - (-2.94)) < 1e-12, 'strainTotal tak konsisten');
assert(strcmp(doc2.target.basename, 'peta') || ~isempty(doc2.target.basename), 'basename hilang');
fprintf('   [ok] round-trip write->read konsisten\n');

% =================================================================
% D1) ENGINE EKSPOR: grainLinkExport.planRows (murni, tanpa GUI/MAT)
% =================================================================
fprintf('-- D1) engine grainLinkExport.planRows (golden) --\n');
% Pakai `doc` yang sudah terkalibrasi (nFref=111, nFtgt=110, slope bGold).
fd = pivcore.io.grain5Faults.emptyDoc('penampang.mat', 111);
fd.faults = { ...
    pivcore.io.grain5Faults.faultStruct('F1', 1700, 2200, 20, 40, 5, 80), ...   % fsr=40
    pivcore.io.grain5Faults.faultStruct('F2', 2200, 2700, 60, 90, 46, 128), ... % fsr=90
    pivcore.io.grain5Faults.faultStruct('F3', 2800, 3100, NaN, NaN, 67, 163)};  % fsr NaN -> skip
rows = pivcore.io.grainLinkExport.planRows(doc, fd);
assert(numel(rows) == 3, 'planRows harus 3 baris');
% F1: frameTgt = clamp(round(frameAtTgt(strainAtRef(40))))
for ii = 1:2
    fsr = rows(ii).fsrRef;
    sExp = pivcore.io.grainLink.strainAtRef(doc, fsr);
    fExp = round(pivcore.io.grainLink.frameAtTgt(doc, sExp));
    fExp = min(max(fExp,1), 110);
    assert(rows(ii).ready, sprintf('%s harus ready', rows(ii).faultId));
    assert(abs(rows(ii).strainPct - sExp) < 1e-9, 'strainPct planRows salah');
    assert(rows(ii).frameTgt == fExp, sprintf('frameTgt %d != %d', rows(ii).frameTgt, fExp));
    assert(rows(ii).frameTgt >= 1 && rows(ii).frameTgt <= 110, 'frameTgt di luar 1..nF');
end
assert(~rows(3).ready && contains(rows(3).reason,'fsr'), 'F3 fsr NaN harus skip');
fprintf('   [ok] planRows: F1/F2 ready (f%d,f%d), F3 skip (%s)\n', ...
    rows(1).frameTgt, rows(2).frameTgt, rows(3).reason);

% kalibrasi invalid -> semua ready=false reason 'kalibrasi'
docInv = pivcore.io.grainLink.emptyDoc('p.mat','m.mat');
docInv.reference.nFrames=111; docInv.reference.strainTotalPct=-2.94;
docInv.reference.geomValid=true; docInv.target.nFrames=110;
docInv = pivcore.io.grainLink.calibrate(docInv);   % tanpa tie -> invalid
rowsInv = pivcore.io.grainLinkExport.planRows(docInv, fd);
assert(all(~[rowsInv([1 2]).ready]), 'tanpa kalibrasi F1/F2 harus tak-ready');
assert(contains(rowsInv(1).reason,'kalibrasi'), 'reason harus kalibrasi invalid');
fprintf('   [ok] kalibrasi invalid → semua sesar skip\n');

% penamaan deterministik
gsn = pivcore.io.grainLinkExport.gsFileName('/x/peta.mat', 'F1', 61);
pvn = pivcore.io.grainLinkExport.panelFileName('/x/peta.mat', 'F1', 61, 'velmag');
assert(contains(gsn,'F1') && contains(gsn,'f061') && endsWith(gsn,'_gs.png'), 'nama GS salah');
assert(contains(pvn,'velmag') && endsWith(pvn,'.jpg'), 'nama panel salah');
fprintf('   [ok] penamaan: %s | %s\n', gsn, pvn);

% =================================================================
% B) GUI GRAINLINK + GRAINSYNC (butuh >=2 MAT PIV)
% =================================================================
fprintf('-- B) GUI GRAINLINK + GRAINSYNC --\n');
roots = grain_setup();
if nargin < 1 || isempty(rootDir)
    rootDir = fullfile(roots.data_root, 'RAW', 'PIV_2026-06-24');
end
if ~isfolder(rootDir)
    fprintf('[SKIP] folder uji tak ada: %s\n', rootDir); return;
end
files = pivanalyzemat.core.scanPivMats(rootDir);
files = i_keepGeom(files);
if numel(files) < 2
    fprintf('[SKIP] butuh >=2 MAT PIV bergeometri di %s (ada %d)\n', rootDir, numel(files));
    return;
end
refF = files{1}; tgtF = files{2};
linkJson = pivcore.io.grainLink.dataPath(tgtF);
i_rm(linkJson);
cleanLink = onCleanup(@() i_rm(linkJson)); %#ok<NASGU>
fprintf('   ref=%s\n   tgt=%s\n', i_b(refF), i_b(tgtF));

% --- buka GRAINLINK dengan 2 berkas praedukasi ---
GRAINLINK(refF, tgtF);
figL = findall(0,'Type','figure','-regexp','Name','GRAIN Link');
assert(~isempty(figL), 'figure GRAINLINK tak terbuka'); figL = figL(1);
clnL = onCleanup(@() i_close(figL)); %#ok<NASGU>
hL = guidata(figL);
assert(~isempty(hL.refFile) && ~isempty(hL.tgtFile), 'kedua berkas tak termuat');
nFref = hL.pnRef.nF; nFtgt = hL.pnTgt.nF;
assert(nFref > 1 && nFtgt > 1, 'nF view < 2');
assert(hL.doc.reference.geomValid, 'acuan tak bergeometri (fixture salah?)');
fprintf('   [ok] GRAINLINK terbuka, nFref=%d nFtgt=%d\n', nFref, nFtgt);

% --- tandai FSR pertama (frame ~25%) ---
rf1 = max(2, round(0.25*nFref)); tf1 = max(2, round(0.25*nFtgt));
rf2 = max(rf1+1, round(0.75*nFref)); tf2 = max(tf1+1, round(0.75*nFtgt));
i_setFrames(figL, rf1, tf1); i_selTie(figL, 1);
i_click(hL.btnMarkRef); i_click(hL.btnMarkTgt);
hL = guidata(figL);
i_setFrames(figL, rf2, tf2); i_selTie(figL, 2);
hL = guidata(figL);
i_click(hL.btnMarkRef); i_click(hL.btnMarkTgt);
hL = guidata(figL);
assert(hL.doc.calibration.valid, 'kalibrasi GRAINLINK invalid setelah 2 tie');
fprintf('   [ok] 2 titik ikat ditandai, kalibrasi valid (slope %+.4g %%/frame)\n', ...
    hL.doc.calibration.slopePctPerFrame);

% --- simpan sidecar ---
i_click(hL.btnSave);
assert(isfile(linkJson), 'sidecar _link.json tak dibuat oleh GRAINLINK');
docL = pivcore.io.grainLink.read(tgtF);
assert(docL.calibration.valid, 'sidecar tersimpan tapi kalibrasi invalid');
fprintf('   [ok] sidecar tersimpan: %s\n', i_b(linkJson));

% =================================================================
% C) GRAINSYNC — strain master -> frame kedua view
% =================================================================
GRAINSYNC(linkJson);
figS = findall(0,'Type','figure','-regexp','Name','GRAIN Sync');
assert(~isempty(figS), 'figure GRAINSYNC tak terbuka'); figS = figS(1);
clnS = onCleanup(@() i_close(figS)); %#ok<NASGU>
hS = guidata(figS);
assert(strcmp(get(hS.sld,'Enable'),'on'), 'slider strain master tak aktif');

% geser strain master ke nilai di tengah rentang -> cek frame ref/tgt
smin = get(hS.sld,'Min'); smax = get(hS.sld,'Max');
sMid = smin + 0.5*(smax - smin);
set(hS.sld,'Value', sMid);
i_click(hS.sld);                         % picu callback master
hS = guidata(figS);
expR = i_clamp(pivcore.io.grainLink.frameAtRef(hS.doc, sMid), hS.pnRef.nF);
expT = i_clamp(pivcore.io.grainLink.frameAtTgt(hS.doc, sMid), hS.pnTgt.nF);
assert(hS.pnRef.frame == expR, sprintf('frame penampang %d != %d', hS.pnRef.frame, expR));
assert(hS.pnTgt.frame == expT, sprintf('frame peta %d != %d', hS.pnTgt.frame, expT));
fprintf('   [ok] strain %+.3g%% → penampang f%d, peta f%d\n', sMid, expR, expT);

% tabel sinkronisasi terisi
dataT = get(hS.tbl,'Data');
assert(~isempty(dataT), 'tabel sinkronisasi kosong');
fprintf('   [ok] tabel sinkronisasi %d baris\n', size(dataT,1));

% =================================================================
% D2) EKSPOR BATCH FSR via GUI GRAINLINK (faults sintetik → foto + manifest)
% =================================================================
fprintf('-- D2) ekspor batch FSR (GUI) --\n');
% Buat _faults.json sintetik di samping PENAMPANG (refF). LINDUNGI data user:
% skip menulis bila sudah ada _faults.json milik user.
faultJson = pivcore.io.grain5Faults.dataPath(refF);
if isfile(faultJson)
    fprintf('[SKIP] _faults.json sudah ada (milik user): %s — tak menimpa.\n', i_b(faultJson));
else
    % 2 sesar ber-FSR di frame yang aman (dalam 2..nFref-1) + 1 sesar fsr NaN.
    fsr1 = max(2, round(0.35*nFref));
    fsr2 = max(fsr1+1, round(0.65*nFref));
    fdoc = pivcore.io.grain5Faults.emptyDoc(refF, nFref);
    fdoc.faults = { ...
        pivcore.io.grain5Faults.faultStruct('F1', 100, 200, fsr1-3, fsr1, 1, nFref), ...
        pivcore.io.grain5Faults.faultStruct('F2', 300, 400, fsr2-3, fsr2, fsr1, nFref), ...
        pivcore.io.grain5Faults.faultStruct('F3', 500, 600, NaN, NaN, 1, nFref)};
    pivcore.io.grain5Faults.write(refF, fdoc);
    cleanFaults = onCleanup(@() i_rm(faultJson)); %#ok<NASGU>

    % Muat faults ke GUI (klik tombol "Muat _faults") + ekspor semua sesar siap.
    hL = guidata(figL);
    assert(isfield(hL,'btnLoadFaults'),'handle tombol Muat faults tak ada');
    i_click(hL.btnLoadFaults);
    hL = guidata(figL);
    rowsChk = pivcore.io.grainLinkExport.planRows(hL.doc, hL.faultsDoc);
    nReady = sum([rowsChk.ready]);
    assert(nReady >= 2, sprintf('harus ≥2 sesar siap, ada %d', nReady));
    fprintf('   [ok] faults dimuat: %d sesar, %d siap\n', numel(rowsChk), nReady);

    % Arahkan folder ekspor ke temp supaya tak mengotori repo.
    tmpRoot = fullfile(tempdir, sprintf('grainlink_export_test_%d', feature('getpid')));
    if isfolder(tmpRoot), rmdir(tmpRoot,'s'); end
    mkdir(tmpRoot);
    cleanTmp = onCleanup(@() i_rmdir(tmpRoot)); %#ok<NASGU>
    hL.exportDir = tmpRoot; guidata(figL, hL);

    % Tombol ekspor semua siap harus aktif.
    assert(strcmp(get(hL.btnExportAll,'Enable'),'on'), 'tombol ekspor tak aktif');
    i_click(hL.btnExportAll);

    % Verifikasi: folder pair + manifest + foto GS & panel.
    pdir = pivcore.io.grainLinkExport.pairDir(tmpRoot, refF, tgtF);
    mpath = pivcore.io.grainLinkExport.manifestPath(tmpRoot, refF, tgtF);
    assert(isfolder(pdir), 'folder pasangan tak dibuat');
    assert(isfile(mpath), 'manifest_fsr.json tak dibuat');
    man = pivcore.io.grainLinkExport.read(tmpRoot, refF, tgtF);
    assert(man.nExported == nReady, sprintf('nExported %d != %d', man.nExported, nReady));
    assert(numel(man.exports) == numel(rowsChk), 'jumlah exports != jumlah sesar');

    % Tiap sesar READY punya GS + 2 panel di disk.
    nGS = numel(dir(fullfile(pdir,'gs','*_gs.png')));
    nPV = numel(dir(fullfile(pdir,'panel','*_velmag.jpg')));
    nPS = numel(dir(fullfile(pdir,'panel','*_shear.jpg')));
    assert(nGS == nReady, sprintf('foto GS %d != %d', nGS, nReady));
    assert(nPV == nReady && nPS == nReady, sprintf('panel v/s %d/%d != %d', nPV, nPS, nReady));

    % Sesar fsr NaN tercatat skip dgn alasan.
    exC = man.exports; if ~iscell(exC), exC = num2cell(exC); end
    skipCount = 0;
    for ii = 1:numel(exC)
        e = exC{ii};
        if isfield(e,'skipped') && e.skipped
            skipCount = skipCount + 1;
            assert(~isempty(e.reason), 'skip tanpa alasan');
        end
    end
    assert(skipCount >= 1, 'sesar fsr NaN harus tercatat skip');
    fprintf('   [ok] ekspor SEMUA: %d GS + %d velmag + %d shear, %d skip; manifest OK\n', ...
        nGS, nPV, nPS, skipCount);

    % --- mode 'sel' (1 sesar) — pastikan onlyFaultIds tak nested/kosong ---
    tmpRoot2 = fullfile(tempdir, sprintf('grainlink_sel_test_%d', feature('getpid')));
    if isfolder(tmpRoot2), rmdir(tmpRoot2,'s'); end
    mkdir(tmpRoot2);
    cleanTmp2 = onCleanup(@() i_rmdir(tmpRoot2)); %#ok<NASGU>
    hL = guidata(figL);
    hL.exportDir = tmpRoot2; hL.selFaultId = 'F1'; guidata(figL, hL);
    set(hL.btnExportSel,'Enable','on');   % test: aktifkan langsung (normal via klik baris)
    i_click(hL.btnExportSel);
    man2 = pivcore.io.grainLinkExport.read(tmpRoot2, refF, tgtF);
    % Hanya F1 yang diproduksi (nExported==1), sesar lain tak muncul.
    assert(man2.nExported == 1, sprintf('mode sel harus 1 ekspor, ada %d', man2.nExported));
    ex2 = man2.exports; if ~iscell(ex2), ex2 = num2cell(ex2); end
    assert(numel(ex2) == 1 && strcmp(ex2{1}.faultId,'F1'), 'mode sel bukan F1');
    pdir2 = pivcore.io.grainLinkExport.pairDir(tmpRoot2, refF, tgtF);
    assert(numel(dir(fullfile(pdir2,'gs','*_gs.png'))) == 1, 'mode sel GS != 1');
    fprintf('   [ok] ekspor SEL: hanya F1 (nExported=1)\n');
end

fprintf('==== SEMUA LULUS ====\n');
end

function i_rmdir(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end

% ============================ helpers ============================
function files = i_keepGeom(files)
    keep = false(1, numel(files));
    for i = 1:numel(files)
        gi = pivcore.io.grainLink.geomInfo(files{i});
        keep(i) = gi.valid;
    end
    f2 = files(keep);
    if numel(f2) >= 2, files = f2; end   % bila ada >=2 bergeometri, pakai itu
end

function i_setFrames(fig, kRef, kTgt)
    h = guidata(fig);
    h.pnRef.frame = kRef; h.pnTgt.frame = kTgt;
    guidata(fig, h);
end

function i_selTie(fig, idx)
    h = guidata(fig);
    set(h.popTie, 'Value', idx);
    guidata(fig, h);
end

function i_click(hObj)
    cb = get(hObj, 'Callback');
    if isempty(cb), return; end
    feval(cb, hObj, struct('Source',hObj));
end

function fr = i_clamp(f, nF)
    fr = round(f);
    if isfinite(nF) && nF >= 1, fr = min(max(fr,1), nF); else, fr = max(fr,1); end
end

function s = i_b(f)
    [~, n, e] = fileparts(char(f)); s = [n e];
end

function i_close(fig)
    try, if ishghandle(fig), delete(fig); end, catch, end
end

function i_rm(p)
    try, if isfile(p), delete(p); end, catch, end
end
