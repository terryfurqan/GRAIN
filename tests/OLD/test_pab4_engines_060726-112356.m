function test_pab4_engines()
%TEST_PAB4_ENGINES  Unit test engine PAB4 (MURNI, tanpa GUI/data nyata):
%   psgId, pab4PotData (round-trip + atomic), pab4Notes (round-trip + cursor),
%   netslip (GOLDEN sintetik), snapPoints, hwLabel. SELALU MATLAB R2025b.
%
%   "Golden" netslip = nilai yang dihitung-tangan dari kasus sintetik kecil
%   (bukan diff terhadap tabStep4 yang read-only + GUI). Lihat PAB4_PLAN §6.

fprintf('==== TEST PAB4 ENGINES ====\n');

here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
pab_setup();
assert(~isempty(which('pivcore.pot.psgId')),     '+pivcore.pot.psgId tak di path');
assert(~isempty(which('pivcore.io.pab4PotData')), '+pivcore.io.pab4PotData tak di path');

% =====================================================================
% 1) psgId — ID stabil garis PSG
% =====================================================================
assert(strcmp(pivcore.pot.psgId.fromFrac(0.70), 'frac070'), 'fromFrac(0.70) != frac070');
assert(strcmp(pivcore.pot.psgId.fromFrac(0.5),  'frac050'), 'fromFrac(0.5) != frac050');
lnF = struct('p1',[0 645],'p2',[3000 645],'frac',0.70);
assert(strcmp(pivcore.pot.psgId.fromLine(lnF), 'frac070'), 'fromLine(frac) != frac070');
assert(pivcore.pot.psgId.isFrac('frac070') && ~pivcore.pot.psgId.isFrac('geom_0_1_2_3'), 'isFrac salah');

g1 = pivcore.pot.psgId.fromGeom([10 20],[300 25]);
g2 = pivcore.pot.psgId.fromGeom([10 20],[300 25]);
assert(strcmp(g1,g2), 'geom id tak deterministik');
% flip ujung -> id sama (urut kanonik)
gFlip = pivcore.pot.psgId.fromGeom([300 25],[10 20]);
assert(strcmp(g1,gFlip), 'flip ujung harus id sama');
% REGRESI: garis MIRING (x naik tapi y TURUN) — flip ujung HARUS tetap id sama.
% Dulu urut pakai `[x1 y1] <= [x2 y2]` (implicit all()) -> id beda saat dibalik.
gt1 = pivcore.pot.psgId.fromGeom([10 30],[300 25]);
gt2 = pivcore.pot.psgId.fromGeom([300 25],[10 30]);
assert(strcmp(gt1,gt2), 'garis miring: flip ujung harus id sama (urut leksikografis)');
% perturbasi < TOLPX -> id sama
gPert = pivcore.pot.psgId.fromGeom([10.3 20.2],[299.6 25.1]);
assert(strcmp(g1,gPert), 'perturbasi < toleransi harus id sama');
% garis beda -> id beda
gDiff = pivcore.pot.psgId.fromGeom([10 20],[300 99]);
assert(~strcmp(g1,gDiff), 'garis beda harus id beda');
% geomCoords round-trip
[pa,pb] = pivcore.pot.psgId.geomCoords(g1);
assert(~isempty(pa) && isequal(sort([pa;pb],1), sort([10 20;300 25],1)), 'geomCoords gagal');
% koordinat negatif
gNeg = pivcore.pot.psgId.fromGeom([-5 -8],[10 12]);
[na,nb] = pivcore.pot.psgId.geomCoords(gNeg);
assert(ismember(-5, [na nb]) && ismember(-8,[na nb]), 'geom id negatif gagal');
fprintf('[ok] psgId: frac/geom/flip/toleransi/round-trip\n');

% =====================================================================
% 2) pab4PotData — round-trip + atomic
% =====================================================================
tmp = tempname; mkdir(tmp);
clT = onCleanup(@() i_rmdir(tmp));
df = fullfile(tmp, 'TKS-5_cm-1.mat');   % path data (tak perlu ada)

doc = pivcore.io.pab4PotData.emptyDoc(df, 106);
doc.units = 'px/frame'; doc.signConvention = 'signed';
% Garis-1 (frac070) + 2 kurva (salah satunya ber-NaN) + 1 netslip + anotasi.
ln1 = pivcore.io.pab4PotData.lineStruct('frac070',[0 645],[3000 645],0.70,3);
ln1.curves = { pivcore.io.pab4PotData.curveStruct('HW-1',[100 645],[1 2 3 NaN 5]), ...
               pivcore.io.pab4PotData.curveStruct('HW-2',[200 645],[0 1 2 3 4]) };
ln1.netslip = { struct('hw',1,'partner','HW-2','start',1,'nuc',2,'fsr',3,'end',5, ...
                       'area',6.5,'dNet',1.0,'units','px/frame','values',[1 1 1 1 1]) };
ln1.annotations.lines  = { pivui.pab4Annot.serialize('line',[0 0; 10 10]) };
ln1.annotations.points = { pivui.pab4Annot.serialize('point',[5 5]) };
% Garis-2 (geom) tanpa kurva.
ln2 = pivcore.io.pab4PotData.lineStruct(g1,[10 20],[300 25],NaN,2);

doc = pivcore.io.pab4PotData.upsertLine(doc, ln1);
doc = pivcore.io.pab4PotData.upsertLine(doc, ln2);
pivcore.io.pab4PotData.write(df, doc);

assert(isfile(pivcore.io.pab4PotData.dataPath(df)), '_potdata.json tak tertulis');
assert(~isfile([pivcore.io.pab4PotData.dataPath(df) '.tmp']), 'sisa .tmp (atomic gagal)');

rd = pivcore.io.pab4PotData.read(df);
assert(numel(rd.psgLines) == 2, sprintf('jumlah garis != 2 (=%d)', numel(rd.psgLines)));
assert(strcmp(rd.units,'px/frame') && strcmp(rd.signConvention,'signed'), 'units/sign tak nyambung');
assert(rd.meta.frames == 106, 'meta.frames tak nyambung');
[lnA, idxA] = pivcore.io.pab4PotData.findLine(rd, 'frac070');
assert(idxA >= 1, 'garis frac070 tak ditemukan saat baca ulang');
assert(numel(lnA.curves) == 2, 'jumlah kurva tak nyambung');
% Nilai kurva (termasuk NaN) round-trip.
v1 = lnA.curves{1}.values;
assert(numel(v1)==5 && isnan(v1(4)) && v1(1)==1 && v1(5)==5, 'nilai kurva (NaN) tak round-trip');
assert(strcmp(lnA.curves{1}.label,'HW-1'), 'label kurva tak nyambung');
assert(numel(lnA.netslip)==1 && lnA.netslip{1}.area==6.5, 'netslip tak round-trip');
assert(numel(lnA.annotations.lines)==1 && numel(lnA.annotations.points)==1, 'anotasi tak round-trip');
% garis-2 ber-id geom nyambung
[lnB, idxB] = pivcore.io.pab4PotData.findLine(rd, g1);
assert(idxB >= 1 && isequal(pivcore.io.pab4PotData.dataPath(df), pivcore.io.pab4PotData.dataPath(df)), 'garis geom hilang');
assert(isequal(round(lnB.p1), [10 20]), 'p1 garis geom tak nyambung');
% sampleRate NaN -> JSON null -> NaN
assert(isnan(rd.sampleRate), 'sampleRate null tak round-trip ke NaN');
% upsert mengganti (bukan menduplikasi)
ln1b = lnA; ln1b.spacingPx = 9;
rd = pivcore.io.pab4PotData.upsertLine(rd, ln1b);
assert(numel(rd.psgLines)==2, 'upsert id sama harusnya GANTI bukan tambah');
fprintf('[ok] pab4PotData: 2 garis ber-id, kurva/NaN/netslip/anotasi round-trip, atomic, upsert\n');

% =====================================================================
% 3) pab4Notes — round-trip + cursor antrean Claude
% =====================================================================
pivcore.io.pab4Notes.appendEntry(df,'exp','','Kesan global eksperimen.');
pivcore.io.pab4Notes.appendEntry(df,'psg','frac070','Garis 70%: HW-1 tumbuh frame 5-40.');
ck = pivcore.io.pab4Notes.curveKey('HW-1','frac070');
pivcore.io.pab4Notes.appendEntry(df,'curve',ck,'Kurva HW-1 nukleasi ~f12.');
pivcore.io.pab4Notes.appendEntry(df,'frame',42,'Frame 42 ada artefak kilatan.');

assert(isfile(pivcore.io.pab4Notes.notesPath(df)), '_notes.md tak tertulis');
E = pivcore.io.pab4Notes.loadEntries(df);
assert(numel(E)==4, sprintf('jumlah entri != 4 (=%d)', numel(E)));
assert(strcmp(E(1).level,'exp') && strcmp(E(1).role,'USER'), 'entri-1 salah level/role');
assert(strcmp(E(2).level,'psg') && strcmp(E(2).key,'frac070'), 'entri-2 key psg salah');
assert(strcmp(E(3).level,'curve') && strcmp(E(3).key,ck), 'entri-3 key curve salah');
assert(strcmp(E(4).level,'frame') && strcmp(E(4).key,'42'), 'entri-4 key frame salah');
assert(contains(E(1).text,'Kesan global'), 'teks entri-1 hilang');
assert(pivcore.io.pab4Notes.pendingForClaude(df), 'harus pending untuk Claude setelah tulis USER');

% Simulasi Claude membalas.
pause(1.1);   % pastikan stempel waktu maju >= 1 detik (resolusi cursor)
pivcore.io.pab4Notes.appendEntry(df,'psg','frac070','Setuju; net-slip naik di akhir.', ...
    struct('role','CLAUDE'));
E2 = pivcore.io.pab4Notes.loadEntries(df);
assert(numel(E2)==5, 'entri Claude tak tertambah');
assert(strcmp(E2(5).role,'CLAUDE'), 'entri terakhir bukan CLAUDE');
assert(~pivcore.io.pab4Notes.pendingForClaude(df), 'setelah Claude baca, tak boleh pending');

% Jurnal seri (folder).
pivcore.io.pab4Notes.appendSeries(tmp, 'Tren dNet naik exp-1 -> exp-8.');
S = pivcore.io.pab4Notes.loadSeries(tmp);
assert(numel(S)>=1 && strcmp(S(1).level,'series'), 'jurnal seri gagal');
assert(isfile(pivcore.io.pab4Notes.journalPath(tmp)), '_PAB4_journal.md tak tertulis');
fprintf('[ok] pab4Notes: 4 level entri, cursor USER/CLAUDE, pending, jurnal seri\n');

% =====================================================================
% 4) netslip — GOLDEN sintetik (dihitung tangan)
% =====================================================================
% repVec: rata-rata per-frame
rA = pivcore.pot.netslip.repVec([1 2 3 4 5; 3 4 5 6 7], 5);   % mean -> [2 3 4 5 6]
assert(isequal(rA,[2 3 4 5 6]), 'repVec matriks salah');
% omitnan: kolom dgn satu NaN -> rata sisanya
rB = pivcore.pot.netslip.repVec({[1 NaN 3],[3 4 5]}, 3);      % [(1+3)/2 4 4] = [2 4 4]
assert(isequal(rB,[2 4 4]), 'repVec omitnan salah');
% kolom semua-NaN -> NaN
rC = pivcore.pot.netslip.repVec({[NaN NaN],[NaN NaN]}, 2);
assert(all(isnan(rC)), 'repVec semua-NaN harus NaN');
% netslipVec = A - B
ns = pivcore.pot.netslip.netslipVec([5 5 5 5 5],[1 2 3 4 5]); % [4 3 2 1 0]
assert(isequal(ns,[4 3 2 1 0]), 'netslipVec salah');
% area = trapz(1:5,[0 1 2 3 4]) = 8 ; dNet = ns(5)-ns(1) = 4
nsRamp = [0 1 2 3 4];
aGold = pivcore.pot.netslip.area(nsRamp,1,5);
assert(abs(aGold-8) < 1e-12, sprintf('area trapz GOLDEN != 8 (=%g)', aGold));
dGold = pivcore.pot.netslip.dNet(nsRamp,1,5);
assert(abs(dGold-4) < 1e-12, sprintf('dNet GOLDEN != 4 (=%g)', dGold));
% area dgn NaN di tengah tetap valid (trapz hanya titik finite)
aNan = pivcore.pot.netslip.area([0 NaN 2 3 4],1,5);
assert(isfinite(aNan), 'area dgn NaN di tengah harus tetap finite');
% <2 titik finite -> NaN
assert(isnan(pivcore.pot.netslip.area([NaN 5 NaN],1,3)), 'area <2 finite harus NaN');
% applySign absolute
assert(isequal(pivcore.pot.netslip.applySign([-1 -2 3],'absolute'),[1 2 3]), 'applySign absolute salah');
% compute rangkum
R = pivcore.pot.netslip.compute([5 5 5 5 5],[1 2 3 4 5], ...
    struct('startF',1,'nclF',2,'fsrF',3,'endF',5),'signed');
assert(isequal(R.values,[4 3 2 1 0]) && R.dNet==-4, 'compute rangkum salah');
fprintf('[ok] netslip: repVec/omitnan/area(trapz=8)/dNet(=4)/sign/compute GOLDEN\n');

% =====================================================================
% 5) snapPoints — snap + struct titik
% =====================================================================
yv = [1 2 NaN NaN 5 6];
assert(pivcore.pot.snapPoints.snapFrame(yv,1)==1, 'snap frame finite langsung salah');
assert(pivcore.pot.snapPoints.snapFrame(yv,3)==2 || pivcore.pot.snapPoints.snapFrame(yv,3)==5, ...
    'snap dari NaN tak ke frame finite terdekat'); % f3 NaN -> terdekat 2 (jarak1) atau 5 (jarak2) -> 2
assert(pivcore.pot.snapPoints.snapFrame(yv,3)==2, 'snap f3 harus ke f2 (terdekat)');
assert(pivcore.pot.snapPoints.snapFrame(yv,99)==6, 'snap di luar batas -> clip ke akhir');
p = pivcore.pot.snapPoints.emptyPts();
p = pivcore.pot.snapPoints.setPoint(p,1,'start',5);
p = pivcore.pot.snapPoints.setPoint(p,1,'end',40);
p = pivcore.pot.snapPoints.setPoint(p,2,'nuc',12);
assert(numel(p)==2, 'setPoint tak buat 2 baris HW');
row1 = pivcore.pot.snapPoints.getHW(p,1);
assert(row1.startF==5 && row1.endF==40, 'getHW nilai salah');
assert(pivcore.pot.snapPoints.hasAny(p), 'hasAny harus true');
fprintf('[ok] snapPoints: snap-to-curve + setPoint/getHW/hasAny\n');

% =====================================================================
% 6) hwLabel — labeling + grouping + pair + completeness
% =====================================================================
recs = struct('data',{[1 2 3 4 5],[1 2 3 4 5],[0 0 0 0 0]}, ...
              'assignLabel',{'','',''}, 'maWindow',{1,1,1});
recs = pivcore.pot.records.normalize(recs);
[recs.maWindow] = deal(1);   % matikan MA agar nilai deterministik
recs = pivcore.pot.hwLabel.assign(recs,1,'HW',1);
recs = pivcore.pot.hwLabel.assign(recs,2,'HW',2);
recs = pivcore.pot.hwLabel.assign(recs,3,'FFW',0);
assert(isequal(pivcore.pot.hwLabel.hwNumbers(recs),[1 2]), 'hwNumbers salah');
assert(isequal(pivcore.pot.hwLabel.rowsForHW(recs,1),1), 'rowsForHW(1) salah');
assert(isequal(pivcore.pot.hwLabel.ffwRows(recs),3), 'ffwRows salah');
% pair HW-2 -> partner FFW; ns = HW2 - FFW = [1 2 3 4 5]
[A,B,partner,okB] = pivcore.pot.hwLabel.pair(recs,2,5);
assert(okB && strcmp(partner,'FFW'), 'pair HW-2 partner harus FFW');
ns2 = pivcore.pot.netslip.netslipVec(A,B);
assert(isequal(ns2,[1 2 3 4 5]), sprintf('netslip HW2-FFW salah [%s]', num2str(ns2)));
% pair HW-1 -> partner HW-2 (ns=0)
[A1,B1,partner1] = pivcore.pot.hwLabel.pair(recs,1,5);
assert(strcmp(partner1,'HW-2') && isequal(pivcore.pot.netslip.netslipVec(A1,B1),[0 0 0 0 0]), ...
    'pair HW-1 partner/ns salah');
st = pivcore.pot.hwLabel.completeness(recs);
assert(st.nHW==2 && st.hasFFW && st.canNetslip, 'completeness salah');
% jalur belum-lengkap (1 HW, tanpa FFW) -> canNetslip false, tetap tak error
recs2 = pivcore.pot.records.normalize(struct('data',{[1 2 3]},'assignLabel',{''}));
recs2 = pivcore.pot.hwLabel.assign(recs2,1,'HW',1);
st2 = pivcore.pot.hwLabel.completeness(recs2);
assert(st2.nHW==1 && ~st2.canNetslip, 'completeness belum-lengkap salah');
fprintf('[ok] hwLabel: assign/group/pair(FFW & HW)/completeness (+ jalur belum-lengkap)\n');

fprintf('==== PAB4 ENGINES SEMUA LULUS ✓ ====\n');
end


function i_rmdir(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
