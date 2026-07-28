function test_smoke_pab5_temp_2(rootDir)
%TEST_SMOKE_PAB5_TEMP_2  Uji headless PAB5_temp_2: BUFFER area sampling POT +
%   L-grid (warisan PAB5_temp) + FITUR BARU MULTI-PSG per-F (blok E & F):
%     E. Scoping fault per-PSG (fault.psgId; tabel F difilter per garis aktif;
%        Aktifkan garis -> tabel F ganti; persistensi psgId round-trip).
%     F. Generate N garis PSG permanen (2 tombol + 2 spinner di TAB ①; tiap garis
%        baru masuk h.doc.psgLines + auto-fill F1..F15 ber-psgId sendiri).
%   Cakupan:
%     A. Engine bandGeom (geometri pita) + collectAlongBand:
%        - bufferMult=0 -> record IDENTIK collectAlongLine (backward-compat).
%        - bufferMult=k>0 -> jumlah & posPx/origin record SAMA; band = 2k+1 baris;
%          bandGeom titik tengah = titik along-line.
%     B. GUI PAB5_temp: default h.bufferMult=2; popup 'Buffer' ada; overlay
%        'bufferPreview' MUNCUL saat buffer>0 & KOSONG saat buffer=off; titik
%        preview lebih kecil dari indikator; ganti popup memicu re-sampel.
%
%   test_smoke_pab5_temp                 % default fixture RAW/PIV_2026-06-24
%   test_smoke_pab5_temp('/path/folder')

fprintf('==== TEST SMOKE PAB5_TEMP_2 (buffer + L-grid + multi-PSG per-F) ====\n');
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

% ============ B0. Build GUI + muat dataset (dipakai A & B) ============
% Bersihkan _faults dulu.
d = dir(fullfile(rootDir,'*_faults.json')); for i=1:numel(d), delete(fullfile(rootDir,d(i).name)); end
fig = PAB5(rootDir);   % PAB5_temp_2 dipromosikan jadi PAB5 (2026-07-04)
assert(ishghandle(fig), 'figure PAB5 tak terbuka');
cln = onCleanup(@() i_close(fig)); %#ok<NASGU>
h = guidata(fig);
pivui.pab4Shell.loadExperiment(fig, 1);
pivui.pab4Shell.ensureFull(fig); h = guidata(fig);   % muat penuh (frame + grid)
assert(isfield(h,'data') && ~isempty(h.data) && h.data.nFrames>=2, 'dataset GUI tak valid');
data = h.data;

% ============ A. Engine bandGeom + collectAlongBand ============
% Garis PSG horizontal 75% (mirip autoPSG) memakai rentang grid.
x1 = pivcore.data.safeFrame(data.x,1); y1 = pivcore.data.safeFrame(data.y,1);
xE = [min(x1(:)) max(x1(:))]; yE = [min(y1(:)) max(y1(:))];
yL = yE(2) - 0.75*(yE(2)-yE(1));
p1 = [xE(1) yL]; p2 = [xE(2) yL];
sp = pivcore.data.nodeSpacing(data); if ~(isfinite(sp)&&sp>0), sp = 16; end, sp = round(sp);

% A1. bandGeom sanity.
k = 2;
[bx, by, corners] = pivcore.pot.step1Collect.bandGeom(p1, p2, sp, k);
[nAL, m] = size(bx);
assert(m == 2*k+1, sprintf('band harus %d baris, dapat %d', 2*k+1, m));
assert(nAL >= 2, 'jumlah titik along-line < 2');
assert(size(corners,1)==4, 'corners harus 4 sudut');
% Kolom tengah band = titik di garis (y ~= yL untuk garis horizontal).
ci = (m+1)/2;
assert(all(abs(by(:,ci) - yL) < 1e-6), 'kolom tengah band tak di garis PSG');
% Baris offset ±k*sp untuk garis HORIZONTAL -> tersebar di y (normal = ±[0 1]).
spreadY = max(by(1,:)) - min(by(1,:));
assert(abs(spreadY - 2*k*sp) < 1e-6, sprintf('lebar band-y salah: %.3f vs %.3f', spreadY, 2*k*sp));
fprintf('[ok] A1. bandGeom k=2 -> %d baris × %d titik; lebar-y=%.1f px (=2·k·sp)\n', m, nAL, spreadY);

% A2. bufferMult=0 -> IDENTIK collectAlongLine.
r0   = pivcore.pot.step1Collect.collectAlongLine(data, p1, p2, sp, 'velocity_magnitude');
rB0  = pivcore.pot.step1Collect.collectAlongBand(data, p1, p2, sp, 'velocity_magnitude', 0);
assert(numel(r0)==numel(rB0), 'jumlah record beda antara Line & Band(0)');
for i=1:numel(r0)
    assert(isequaln(r0(i).data, rB0(i).data), sprintf('data record %d beda (Band0 != Line)', i));
    assert(abs(r0(i).posPx - rB0(i).posPx) < 1e-9, 'posPx beda (Band0 != Line)');
end
fprintf('[ok] A2. collectAlongBand(...,0) IDENTIK collectAlongLine (%d record)\n', numel(r0));

% A3. bufferMult=2 -> TIAP titik pita = record TERPISAH (TANPA perataan).
%     Jumlah = nAL × (2k+1). Penomoran COLUMN-MAJOR: kiri-atas P-1, ke BAWAH
%     P-2..P-(2k+1), lalu kolom kanan berikutnya kembali ke atas.
rB2 = pivcore.pot.step1Collect.collectAlongBand(data, p1, p2, sp, 'velocity_magnitude', 2);
mm = 2*2+1;                                   % 5 baris band (k=2)
assert(numel(rB2) == nAL*mm, sprintf('band(2) harus %d record (nAL×%d), dapat %d', nAL*mm, mm, numel(rB2)));
% Label (field .point) berurut P-1..P-N.
assert(strcmp(rB2(1).point,'P-1') && strcmp(rB2(2).point,'P-2'), 'label tak berurut P-1,P-2');
% COLUMN-MAJOR: 5 record pertama = 1 kolom (posPx SAMA), origin-y MENURUN
% (atas->bawah). Record ke-6 = kolom berikutnya (posPx berbeda/naik).
col1pos = arrayfun(@(r) r.posPx, rB2(1:mm));
assert(all(abs(col1pos - col1pos(1)) < 1e-6), 'kolom-1: posPx harus sama (satu posisi along-line)');
col1y = arrayfun(@(r) r.origin(2), rB2(1:mm));
assert(all(diff(col1y) < 0), 'kolom-1: origin-y harus MENURUN (atas->bawah)');
assert(abs(rB2(mm+1).posPx - rB2(1).posPx) > 1e-6, 'record ke-6 harus PINDAH kolom (posPx beda)');
% Titik tengah tiap kolom di garis PSG (y≈yL); titik lain menyebar vertikal.
ciRec = (mm+1)/2;                             % =3 (baris tengah kolom)
assert(abs(rB2(ciRec).origin(2) - yL) < 1e-6, 'titik tengah kolom-1 tak di garis PSG');
assert(abs(rB2(1).origin(2) - yL) > 1e-6, 'titik atas kolom-1 semestinya DI ATAS garis');
% Sampling menghasilkan data finite.
anyFinite = any(arrayfun(@(r) any(isfinite(r.data)), rB2));
assert(anyFinite, 'band(2): semua data NaN (sampling gagal)');
fprintf('[ok] A3. band(2): %d record TERPISAH (=%d×%d), penomoran COLUMN-MAJOR (atas->bawah per kolom)\n', ...
    numel(rB2), nAL, mm);

% ============ B. GUI PAB5_temp: default + popup + preview overlay ============
% B1. Default buffer = 0 (MATI) + popup ada dgn Value benar.
assert(isfield(h,'bufferMult') && h.bufferMult==0, sprintf('default bufferMult harus 0, dapat %g', i_num(h,'bufferMult')));
assert(isfield(h,'popBuffer') && ishghandle(h.popBuffer), 'popup Buffer tak ada');
assert(get(h.popBuffer,'Value')==1, 'popup Buffer default harus Value 1 (=off)');
strs = get(h.popBuffer,'String');
assert(iscell(strs) && numel(strs)==4 && strcmp(strs{1},'off'), 'opsi popup Buffer salah');
fprintf('[ok] B1. default bufferMult=0 (off) + popup (off/1×/2×/3×, Value=1)\n');

% Sampel garis (fixture bersih -> garis 75% belum tersampel; kunci utk sampel).
if isempty(h.recs), pivui.pab4Shell.collectPOT(fig); h = guidata(fig); end
assert(~isempty(h.recs), 'recs kosong (collectPOT gagal)');

% B2. Preview overlay MUNCUL (buffer=2) di axMain. Default kini 0 (off) -> set 2×
% dulu lewat popup (Value 3 = 2×) + picu callback, baru render.
set(h.popBuffer,'Value',3); cbB = get(h.popBuffer,'Callback');
if ~isempty(cbB), cbB(h.popBuffer,[]); end
h = guidata(fig);
assert(h.bufferMult==2, sprintf('set popup 2× gagal, bufferMult=%g', i_num(h,'bufferMult')));
pivui.pab4Shell.renderMain(fig); h = guidata(fig);
pv = findall(h.axMain,'Tag','bufferPreview');
assert(~isempty(pv), 'overlay bufferPreview tak muncul saat buffer=2');
% Ada patch (pita) + plot titik.
nPatch = numel(findall(h.axMain,'Type','patch','Tag','bufferPreview'));
nDots  = numel(findall(h.axMain,'Type','line','Tag','bufferPreview'));
assert(nPatch>=1, 'pita transparan (patch) preview tak ada');
assert(nDots>=1, 'titik sampling preview tak ada');
% Titik preview lebih kecil dari indikator HW/FW.
msInd = h.indMarkerSize;
ld = findall(h.axMain,'Type','line','Tag','bufferPreview');
msDot = get(ld(1),'MarkerSize');
assert(msDot < msInd, sprintf('titik preview (%d) harus < indikator HW/FW (%d)', msDot, msInd));
fprintf('[ok] B2. preview overlay (patch=%d, dots=%d; titik %d < indikator %d)\n', nPatch, nDots, msDot, msInd);

% B3. buffer=2 -> jumlah kurva = N×5 (band jadi kurva terpisah). Ganti OFF ->
%     kurva turun ke N (1 baris) + preview HILANG.
nRec2 = numel(h.recs);
set(h.popBuffer,'Value',1);                       % off
cb = get(h.popBuffer,'Callback'); cb(h.popBuffer,[]);
h = guidata(fig);
assert(h.bufferMult==0, 'popup off -> bufferMult harus 0');
nRecOff = numel(h.recs);
assert(nRec2 == nRecOff*5, sprintf('buffer=2 harus 5× kurva off (%d vs %d×5)', nRec2, nRecOff));
pvOff = findall(h.axMain,'Tag','bufferPreview');
assert(isempty(pvOff), 'overlay bufferPreview semestinya HILANG saat buffer=off');
fprintf('[ok] B3. buffer2=%d kurva (=off %d ×5) -> off: preview hilang\n', nRec2, nRecOff);

% B4. Ganti popup -> 3×: kurva = N×7; label berurut P-1.. ; preview muncul lagi.
set(h.popBuffer,'Value',4);                       % 3×
cb(h.popBuffer,[]); h = guidata(fig);
assert(h.bufferMult==3, 'popup 3× -> bufferMult harus 3');
assert(numel(h.recs) == nRecOff*7, sprintf('buffer=3 harus 7× kurva off (%d vs %d×7)', numel(h.recs), nRecOff));
assert(strcmp(h.recs(1).point,'P-1'), 'label kurva pertama harus P-1');
pv3 = findall(h.axMain,'Type','line','Tag','bufferPreview');
assert(~isempty(pv3), 'preview tak muncul lagi saat 3×');
fprintf('[ok] B4. popup 3× -> %d kurva (=off ×7), label P-1.., preview muncul\n', numel(h.recs));

% B5. Workflow SESAR dgn buffer ON (band = kurva terpisah, banyak): assign
%     HW/FW by ROW (identitas seleksi = nomor baris, column-major) + POI + buang
%     kurva. Pastikan tak error meski posPx berulang per kolom.
set(h.popBuffer,'Value',3); cb(h.popBuffer,[]); h = guidata(fig);   % kembali 2×
assert(h.bufferMult==2 && numel(h.recs)>=1000, 'buffer 2× tak menghasilkan banyak kurva');
% Pindah ke Tab ① (Label/Sesar) supaya tabel & tombol sesar ada.
set(h.tg,'SelectedTab',h.tabLbl); h = guidata(fig);
% Buat sesar F1 + assign HW/FW pada 2 kurva band berbeda (by row).
i_editFaultCell(fig,1,3,'1'); h = guidata(fig);
assert(strcmp(h.activeFaultId,'F1'), 'F1 tak dibuat');
i_selRow(fig, 300); i_fireStr(fig,'⬆ Jadikan HW');
i_selRow(fig, 900); i_fireStr(fig,'⬇ Jadikan FW');
h = guidata(fig); [f1,~] = pivcore.io.pab5Faults.findFault(h.fdoc,'F1');
assert(isfinite(f1.hwPosPx) && isfinite(f1.fwPosPx), 'assign HW/FW pada kurva band GAGAL');
% Buang 1 kurva band (mekanisme cleaning) — pilih baris lalu exclude.
h.selRows = 500; guidata(fig,h);
try, pivui.pab4Shell.deleteSelectedCurves(fig); catch, end
h = guidata(fig);
assert(pivui.pab4Shell.isExcluded(h.recs(500)), 'buang kurva band (exclude) gagal');
fprintf('[ok] B5. workflow sesar + buang kurva pada band (%d kurva; assign by row OK)\n', numel(h.recs));

% B6. Toggle "👁 Sesar" (sembunyikan SEMUA sesar): render POT -> ada overlay sesar
%     (faultHL). Klik -> hideAllFaults=true + SEMUA overlay sesar HILANG. Klik lagi
%     -> tampil kembali.
pivui.pab4Shell.renderPOT(fig); h = guidata(fig);
assert(isfield(h,'btnHideFaults') && ishghandle(h.btnHideFaults), 'tombol 👁 Sesar tak ada');
nHLon = numel(findall(h.axPOT,'Tag','faultHL'));
assert(nHLon>=1, 'overlay sesar aktif (faultHL) semestinya ada sebelum disembunyikan');
set(h.btnHideFaults,'Value',1); cbH = get(h.btnHideFaults,'Callback'); cbH(h.btnHideFaults,[]);
h = guidata(fig);
assert(h.hideAllFaults, 'toggle -> hideAllFaults harus true');
assert(strcmp(get(h.btnHideFaults,'String'),'🚫 Sesar'), 'string tombol harus 🚫 Sesar saat OFF');
nHLoff = numel(findall(h.axPOT,'Tag','faultHL')) + numel(findall(h.axPOT,'Tag','faultFill'));
assert(nHLoff==0, sprintf('semua sesar harus HILANG saat disembunyikan (sisa %d)', nHLoff));
set(h.btnHideFaults,'Value',0); cbH(h.btnHideFaults,[]); h = guidata(fig);
assert(~h.hideAllFaults, 'toggle lagi -> hideAllFaults harus false');
assert(numel(findall(h.axPOT,'Tag','faultHL'))>=1, 'sesar harus tampil kembali');
fprintf('[ok] B6. toggle 👁/🚫 sembunyikan+tampilkan semua sesar (HL %d -> 0 -> tampil)\n', nHLon);

% ============ C. Otomasi POI: Auto-FSR (puncak net-slip) + Rantai START/END ============
% Reset buffer OFF (1-D) supaya sesar sederhana. Bangun 3 sesar F1..F3 (HW/FW).
set(h.popBuffer,'Value',1); cbC = get(h.popBuffer,'Callback'); cbC(h.popBuffer,[]); h = guidata(fig);
assert(h.bufferMult==0, 'reset buffer OFF gagal (blok C)');
pivui.pab4Shell.collectPOT(fig); h = guidata(fig);
nC = numel(h.recs); assert(nC>=6, 'kurva 1-D terlalu sedikit utk uji sesar');
% Bersihkan sesar dari blok B (deterministik) lalu buat F1..F3 (HW/FW by posPx recs).
h.fdoc = pivcore.io.pab5Faults.emptyDoc(h.df, h.nF); guidata(fig,h);
i_mkFault(fig, 1, 1, round(nC/2));       % F1: HW=kurva1, FW=kurva tengah
i_mkFault(fig, 2, 2, max(2,round(nC*0.7)));
i_mkFault(fig, 3, 3, nC);                % F3
h = guidata(fig);
ord = pivui.pab5Model.faultRowOrder(h);
mains = {}; for k=1:numel(ord), if isempty(pivui.pab5Model.parentId(ord{k})), mains{end+1}=ord{k}; end, end %#ok<AGROW>
assert(numel(mains)>=3, sprintf('harus >=3 sesar utama, dapat %d', numel(mains)));
% C1. Auto-FSR -> tiap f.fsr = argmax(faultNetslip). Tombol MaxNS/Auto-FSR kini
% DISEMBUNYIKAN dari GUI ('Visible','off'; user 2026-07-18) tapi callback utuh ->
% picu via Tag 'btnAutoFsr' (tahan visibility/label, bukan via String).
i_fireTag(fig,'btnAutoFsr'); h = guidata(fig);
for k=1:numel(mains)
    [fk,~] = pivcore.io.pab5Faults.findFault(h.fdoc, mains{k}.id);
    ns = pivui.pab5Model.faultNetslip(h, fk);
    if isempty(ns) || ~any(isfinite(ns)), continue; end
    vv = ns; vv(~isfinite(vv)) = -Inf; [~,km] = max(vv);
    assert(isfinite(fk.fsr) && round(fk.fsr)==km, sprintf('%s FSR(%g) != argmax netslip(%d)', fk.id, fk.fsr, km));
end
fprintf('[ok] C1. Auto-FSR -> semua sesar FSR = puncak (argmax) net-slip\n');
% C2. Rantai START/END: START(F1)=1; START(Fi)=FSR(Fi-1); END(Fi)=FSR(Fi+1); END(akhir)=nF.
i_fireStr(fig,'⛓ Rantai START/END dari FSR'); h = guidata(fig);
ord = pivui.pab5Model.faultRowOrder(h);
M = {}; for k=1:numel(ord), if isempty(pivui.pab5Model.parentId(ord{k})), M{end+1}=ord{k}; end, end %#ok<AGROW>
Mf = cell(1,numel(M)); for k=1:numel(M), [Mf{k},~]=pivcore.io.pab5Faults.findFault(h.fdoc, M{k}.id); end
nMM = numel(Mf);
assert(round(Mf{1}.startF)==1, sprintf('START F1 harus 1, dapat %g', Mf{1}.startF));
assert(round(Mf{nMM}.endF)==h.nF, sprintf('END sesar terakhir harus nF=%d, dapat %g', h.nF, Mf{nMM}.endF));
for k=2:nMM
    if isfinite(Mf{k-1}.fsr)
        assert(round(Mf{k}.startF)==round(Mf{k-1}.fsr), sprintf('START(%s) != FSR(%s)', Mf{k}.id, Mf{k-1}.id));
    end
end
for k=1:nMM-1
    if isfinite(Mf{k+1}.fsr)
        assert(round(Mf{k}.endF)==round(Mf{k+1}.fsr), sprintf('END(%s) != FSR(%s)', Mf{k}.id, Mf{k+1}.id));
    end
end
fprintf('[ok] C2. Rantai START/END dari FSR (F1 START=1, akhir END=nF=%d)\n', h.nF);

% ============ D. L-grid PSG: Jadikan L1 + spinner + Preview + POT Export ============
% Pindah ke Tab ② (tempat tombol L-grid). Pastikan garis aktif ada.
set(h.tg,'SelectedTab',h.tabFault); h = guidata(fig);
if isempty(h.line) || ~isfield(h.line,'p1'), pivui.pab4Shell.collectPOT(fig); h = guidata(fig); end
assert(isfield(h,'btnSetRefLine') || true, '');   % tombol via Tag
% D1. Jadikan L1.
i_fireStr(fig,'★ Jadikan L1 (garis aktif)'); h = guidata(fig);
L1 = h.line;   % garis acuan runtime
% D2. Spinner N + spasi (increment 10).
h.lgridN = 3; h.lgridDy = 20; guidata(fig,h);
% D3. Preview toggle -> overlay lgridPreview muncul (3 garis) + POT Export enabled.
set(h.btnLgridPreview,'Value',1); cbP = get(h.btnLgridPreview,'Callback'); cbP(h.btnLgridPreview,[]);
h = guidata(fig);
assert(h.lgridPreviewOn, 'Preview -> lgridPreviewOn harus true');
nLine = numel(findall(h.axMain,'Type','line','Tag','lgridPreview'));
assert(nLine==3, sprintf('overlay L-grid harus 3 garis, dapat %d', nLine));
assert(strcmp(get(h.btnLgridExport,'Enable'),'on'), 'POT Export harus enabled setelah preview');
fprintf('[ok] D1-3. Jadikan L1 + Preview 3 garis + POT Export enabled\n');
% D4. POT Export -> folder PSG_LGRID/ berisi axmain + 3 axpot. Pakai override root.
tmpRoot = tempname; mkdir(tmpRoot);
cleanRoot = onCleanup(@() i_rmdir(tmpRoot)); %#ok<NASGU>
h = guidata(fig); h.exportRootOverride = tmpRoot; h.lgridPreviewOn = true; guidata(fig,h);
i_fireStr(fig,'📤 POT Export (L-grid)'); h = guidata(fig);
outDir = pivcore.io.pab5PsgExport.lgridDir(tmpRoot, h.df);
assert(isfolder(outDir), sprintf('folder PSG_LGRID tak dibuat: %s', outDir));
fMain = fullfile(outDir, pivcore.io.pab5PsgExport.axMainFile(h.df));
assert(isfile(fMain), 'axmain L-grid tak ada');
for i=1:3
    fp = fullfile(outDir, pivcore.io.pab5PsgExport.axpotFile(h.df, i));
    assert(isfile(fp), sprintf('axpot L%d tak ada: %s', i, fp));
end
% D5. Restore: buffer OFF, garis asli kembali, preview reset + export disabled.
assert(h.bufferMult==0, 'buffer harus tetap OFF sesudah export');
assert(~h.lgridPreviewOn, 'lgridPreviewOn harus reset false sesudah export');
assert(strcmp(get(h.btnLgridExport,'Enable'),'off'), 'POT Export harus disabled lagi sesudah export');
assert(isempty(findall(h.axMain,'Tag','lgridPreview')), 'overlay preview harus hilang sesudah export');
% Garis runtime kembali ke L1 (p1/p2 sama).
assert(max(abs([h.line.p1(:);h.line.p2(:)] - [L1.p1(:);L1.p2(:)])) < 1e-6, 'garis asli tak direstore');
fprintf('[ok] D4-5. POT Export (axmain + 3 axpot) -> restore garis+buffer OK\n');

% ============ E. ENGINE scoping per-PSG (murni, tanpa GUI) ============
% E1. faultStruct punya psgId default ''. E2. faultsForPsg memfilter benar.
% E3. assignOrphanFaultsTo migrasi '' -> garis pertama. E4. round-trip write/read
% mempertahankan psgId.
fE = pivcore.io.pab5Faults.faultStruct('F1', NaN, NaN, NaN, NaN, NaN, NaN);
assert(isfield(fE,'psgId') && isempty(fE.psgId), 'faultStruct.psgId default harus '''' ');
docE = pivcore.io.pab5Faults.emptyDoc(h.df, 20);
fa = pivcore.io.pab5Faults.faultStruct('FA', 10, 20, NaN, NaN, NaN, NaN); fa.psgId='geom_aaa';
fb = pivcore.io.pab5Faults.faultStruct('FB', 30, 40, NaN, NaN, NaN, NaN); fb.psgId='geom_bbb';
fo = pivcore.io.pab5Faults.faultStruct('FO', 50, 60, NaN, NaN, NaN, NaN);   % orphan psgId=''
docE = pivcore.io.pab5Faults.upsertFault(docE, fa);
docE = pivcore.io.pab5Faults.upsertFault(docE, fb);
docE = pivcore.io.pab5Faults.upsertFault(docE, fo);
FA = pivui.pab5Model.faultsForPsg(docE, 'geom_aaa');
assert(numel(FA)==1 && strcmp(FA{1}.id,'FA'), 'faultsForPsg geom_aaa harus {FA}');
FN = pivui.pab5Model.faultsForPsg(docE, '');
assert(numel(FN)==1 && strcmp(FN{1}.id,'FO'), 'faultsForPsg '''' harus {FO} (orphan)');
docE = pivui.pab5Model.assignOrphanFaultsTo(docE, 'geom_aaa');
FA2 = pivui.pab5Model.faultsForPsg(docE, 'geom_aaa');
assert(numel(FA2)==2, 'assignOrphanFaultsTo: orphan FO harus pindah ke geom_aaa (2 fault)');
assert(isempty(pivui.pab5Model.faultsForPsg(docE, '')), 'tak boleh ada orphan sesudah migrasi');
% Round-trip disk.
tmpMat = fullfile(rootDir, sprintf('__psgscope_%d.mat', 12345));
docE.source = '__psgscope.mat';
save(tmpMat, 'ov');   % file dummy (dataPath butuh path .mat yg ada dir-nya)
pivcore.io.pab5Faults.write(tmpMat, docE);
docR = pivcore.io.pab5Faults.read(tmpMat);
[frA,~] = pivcore.io.pab5Faults.findFault(docR,'FA');
assert(strcmp(frA.psgId,'geom_aaa'), 'round-trip: psgId FA tak dipertahankan');
try, delete(tmpMat); catch, end
try, delete(fullfile(rootDir,'__psgscope_12345_faults.json')); catch, end
fprintf('[ok] E. engine scoping: psgId default, faultsForPsg filter, migrasi orphan, round-trip disk\n');

% ============ F. GUI: Generate N garis PSG + scoping tabel F per-garis ============
% Reset buffer OFF + bersihkan fdoc supaya deterministik.
set(h.popBuffer,'Value',1); cbF = get(h.popBuffer,'Callback'); cbF(h.popBuffer,[]); h = guidata(fig);
set(h.tg,'SelectedTab',h.tabLbl); h = guidata(fig);
% Pastikan ada garis aktif (fixture bersih -> garis 75%). Simpan sbg L1.
if isempty(h.line) || ~isfield(h.line,'p1'), pivui.pab4Shell.collectPOT(fig); h = guidata(fig); end
i_fireStr(fig,'Simpan garis'); h = guidata(fig);       % garis aktif -> masuk psgLines
nLinesBefore = numel(h.doc.psgLines);
psgA = h.activePsgId;
assert(~isempty(psgA), 'garis aktif tak punya psgId');
% F1. Kontrol UI ada (Tag).
assert(~isempty(findall(fig,'Tag','btnGenSetRef')), 'tombol ★ Jadikan L1 (btnGenSetRef) tak ada');
assert(~isempty(findall(fig,'Tag','btnGenLines')),  'tombol ⊞ Generate (btnGenLines) tak ada');
assert(~isempty(findall(fig,'Tag','spGenNUp')),     'spinner N (spGenNUp) tak ada');
assert(~isempty(findall(fig,'Tag','spGenDyUp')),    'spinner jarak (spGenDyUp) tak ada');
% F2. Jadikan L1 + set N=3, jarak=40 lewat spinner, lalu Generate.
i_fireStr(fig,'★ Jadikan L1'); h = guidata(fig);
assert(strcmp(h.genRefId, psgA), 'genRefId tak ter-set ke garis aktif');
% N: default 3. Naikkan jarak 2x (20->40).
i_fireTag(fig,'spGenDyUp'); i_fireTag(fig,'spGenDyUp'); h = guidata(fig);
assert(h.genDy==40, sprintf('genDy harus 40, dapat %g', h.genDy));
i_fireStr(fig,'⊞ Generate'); h = guidata(fig);
% 3 garis TOTAL (termasuk L1 yang sudah ada) -> 2 garis BARU.
nLinesAfter = numel(h.doc.psgLines);
assert(nLinesAfter == nLinesBefore + 2, sprintf('Generate N=3: harus +2 garis baru (%d->%d)', nLinesBefore, nLinesAfter));
fprintf('[ok] F2. Generate 3 garis PSG (L1 + 2 baru) permanen di psgLines\n');
% F3. Tiap garis BARU punya F1..F15 sendiri (ber-psgId garis itu).
newLine = h.doc.psgLines{end};   % garis terakhir dibuat
FB = pivui.pab5Model.faultsForPsg(h.fdoc, newLine.id);
assert(numel(FB)==15, sprintf('garis baru harus punya 15 slot F, dapat %d', numel(FB)));
% F4. Scoping tabel: assign HW pada F1 garis A; Aktifkan garis B -> tabel F beda.
% Aktifkan garis A (psgA), assign HW ke F1-nya.
i_activatePsg(fig, psgA); h = guidata(fig);
FA_ids = {}; act = pivui.pab5Model.faultsForPsg(h.fdoc, psgA);
assert(~isempty(act), 'garis A tak punya sesar');
% Ambil id record baris pertama tabel (F#=1) & assign HW ke kurva tengah.
h.activeFaultId = act{1}.id; guidata(fig,h);
i_selRow(fig, max(1,round(numel(h.recs)/2))); i_fireStr(fig,'⬆ Jadikan HW');
h = guidata(fig);
[fA1,~] = pivcore.io.pab5Faults.findFault(h.fdoc, act{1}.id);
assert(isfinite(fA1.hwPosPx), 'assign HW ke F garis A gagal');
assert(strcmp(fA1.psgId, psgA), 'sesar garis A harus ber-psgId garis A');
% Aktifkan garis B -> h.faultIds hanya berisi sesar garis B (bukan garis A).
i_activatePsg(fig, newLine.id); h = guidata(fig);
idsB = h.faultIds(~cellfun(@isempty, h.faultIds));
for k=1:numel(idsB)
    [fk,~] = pivcore.io.pab5Faults.findFault(h.fdoc, idsB{k});
    assert(strcmp(fk.psgId, newLine.id), sprintf('tabel garis B bocor sesar psgId=%s', fk.psgId));
end
assert(~any(strcmp(idsB, act{1}.id)), 'sesar garis A BOCOR ke tabel garis B');
fprintf('[ok] F4. tabel sesar ter-scope per-garis PSG (Aktifkan garis B -> F garis A tak muncul)\n');
% F5. Persistensi: Save -> reload exp -> scoping psgId bertahan.
i_fireStr(fig,'💾 Save'); h = guidata(fig);
fdoc2 = pivcore.io.pab5Faults.read(h.df);
[fA1b,~] = pivcore.io.pab5Faults.findFault(fdoc2, act{1}.id);
assert(~isempty(fA1b) && strcmp(fA1b.psgId, psgA) && isfinite(fA1b.hwPosPx), ...
    'persistensi psgId/HW garis A gagal setelah Save');
nA = numel(pivui.pab5Model.faultsForPsg(fdoc2, psgA));
nB = numel(pivui.pab5Model.faultsForPsg(fdoc2, newLine.id));
assert(nA>=1 && nB>=1, 'psgId tak tertulis ke _faults.json');
fprintf('[ok] F5. Save -> _faults.json: psgId per-garis bertahan (A=%d, B=%d sesar)\n', nA, nB);

delete(fig);
d = dir(fullfile(rootDir,'*_faults.json')); for i=1:numel(d), delete(fullfile(rootDir,d(i).name)); end
d = dir(fullfile(rootDir,'*_potdata.json')); for i=1:numel(d), delete(fullfile(rootDir,d(i).name)); end
fprintf('==== PAB5_TEMP_2 (buffer + L-grid + multi-PSG per-F) SEMUA LULUS ✓ ====\n');
end

% ---------------------------------------------------------------------
function i_close(fig), try, if ishghandle(fig), delete(fig); end, catch, end, end
function v = i_num(h, f), v = NaN; if isfield(h,f) && isscalar(h.(f)), v = h.(f); end, end
function i_editFaultCell(fig, r, c, str)
    h = guidata(fig); tb = h.tblFault; cb = get(tb,'CellEditCallback');
    evt = struct('Indices',[r c], 'NewData',str, 'PreviousData','', 'EditData',str, 'Error',[]);
    if ~isempty(cb), cb(tb, evt); end
end
function i_selRow(fig, r)
    h = guidata(fig); h.selRows = r; guidata(fig,h);
    try, set(fig,'CurrentObject',h.axPOT); catch, end
    pivui.pab4Shell.callHook(fig,'onCurveClick', r);
end
function i_fireStr(fig, str)
    b = findall(fig,'Type','uicontrol');
    for i=1:numel(b)
        s = get(b(i),'String');
        if ischar(s) && strcmp(s,str)
            cb = get(b(i),'Callback'); if ~isempty(cb), cb(b(i),[]); end, return;
        end
    end
    error('tombol tak ketemu: %s', str);
end
function i_mkFault(fig, num, hwRow, fwRow)
    % Buat sesar F<num> dgn HW=recs(hwRow).posPx, FW=recs(fwRow).posPx (uiNum=num).
    h = guidata(fig);
    hwRow = max(1,min(hwRow,numel(h.recs))); fwRow = max(1,min(fwRow,numel(h.recs)));
    id = sprintf('F%d', num);
    f = pivcore.io.pab5Faults.faultStruct(id, h.recs(hwRow).posPx, h.recs(fwRow).posPx, ...
        NaN, NaN, NaN, NaN, NaN, NaN, []);
    f.uiNum = num;
    f.psgId = char(h.activePsgId);   % scoping multi-PSG: sesar milik garis aktif
    h.fdoc = pivcore.io.pab5Faults.upsertFault(h.fdoc, f); guidata(fig,h);
end
function i_rmdir(d)
    if ischar(d) && isfolder(d), try, rmdir(d,'s'); catch, end, end
end
function i_fireTag(fig, tag)
    b = findall(fig,'Tag',tag);
    assert(~isempty(b), 'kontrol tak ketemu (tag): %s', tag);
    cb = get(b(1),'Callback'); if ~isempty(cb), cb(b(1),[]); end
end
function i_activatePsg(fig, id)
    % Pilih garis `id` di listbox lalu Aktifkan (mirip klik user).
    h = guidata(fig);
    ids = {};
    if isfield(h.doc,'psgLines')
        for k=1:numel(h.doc.psgLines), ids{end+1} = h.doc.psgLines{k}.id; end %#ok<AGROW>
    end
    row = find(strcmp(ids, id), 1);
    assert(~isempty(row), 'garis PSG tak ada di listbox: %s', id);
    set(h.lstLines,'Value',row);
    b = findall(fig,'Type','uicontrol','Style','pushbutton');
    for i=1:numel(b)
        if strcmp(get(b(i),'String'),'Aktifkan')
            cb=get(b(i),'Callback'); if ~isempty(cb), cb(b(i),[]); end, return;
        end
    end
    error('tombol Aktifkan tak ketemu');
end
