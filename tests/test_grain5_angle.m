function test_grain5_angle()
%TEST_GRAIN5_ANGLE  Unit test engine sudut sesar (MURNI, tanpa GUI/data nyata):
%   pivcore.pot.faultAngle (fromPoints/relativeToDetachment/enforceLeftDip/
%   emptyDetachment/isValidDetachment) + round-trip detachment & angleDeg pada
%   sidecar pivcore.io.grain5Faults (write->read). SELALU MATLAB R2025b.
%
%   test_grain5_angle

fprintf('==== TEST GRAIN5 ANGLE ====\n');

here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
grain_setup();
assert(~isempty(which('pivcore.pot.faultAngle')), '+pivcore.pot.faultAngle tak di path');
assert(~isempty(which('pivcore.io.grain5Faults')),  '+pivcore.io.grain5Faults tak di path');

FA = @pivcore.pot.faultAngle.fromPoints;
tol = 1e-9;

% =====================================================================
% 1) fromPoints — sudut dikenal (dinormalkan ke (-90,90])
% =====================================================================
assert(abs(FA([0 0],[1 0]) - 0)   < tol, 'horizontal -> 0°');
assert(abs(FA([0 0],[1 1]) - 45)  < tol, 'naik 45° -> 45°');
assert(abs(FA([0 0],[0 1]) - 90)  < tol, 'vertikal -> 90°');
assert(abs(FA([0 0],[1 -1]) + 45) < tol, 'turun 45° -> -45°');
% garis tak berarah: 170° ekuivalen -10°; dan flip titik -> sudut sama
assert(abs(FA([0 0],[-1 0]) - 0)  < tol, 'kiri (180°) dinormalkan -> 0°');
assert(abs(FA([0 0],[1 1]) - FA([1 1],[0 0])) < tol, 'flip titik -> sudut sama (garis)');
% titik berimpit / invalid -> NaN
assert(isnan(FA([2 2],[2 2])),  'titik berimpit -> NaN');
assert(isnan(FA([NaN 0],[1 1])),'titik NaN -> NaN');
fprintf('[ok] fromPoints: 0/45/90/-45 + normalisasi + flip + NaN-guard\n');

% =====================================================================
% 2) relativeToDetachment — selisih sudut sesar vs bidang ref
% =====================================================================
% sesar 45°, detachment 0° -> relatif 45°
d1 = pivcore.pot.faultAngle.relativeToDetachment([0 0],[1 1],[0 0],[1 0]);
assert(abs(d1 - 45) < tol, 'sesar45 vs det0 -> 45°');
% sesar 45°, detachment 30° -> relatif 15°
d2 = pivcore.pot.faultAngle.relativeToDetachment([0 0],[1 1],[0 0],[cosd(30) sind(30)]);
assert(abs(d2 - 15) < 1e-6, 'sesar45 vs det30 -> 15°');
% detachment invalid (berimpit) -> jatuh ke absolut (45°)
d3 = pivcore.pot.faultAngle.relativeToDetachment([0 0],[1 1],[5 5],[5 5]);
assert(abs(d3 - 45) < tol, 'det invalid -> absolut 45°');
% tanpa argumen detachment -> absolut
d4 = pivcore.pot.faultAngle.relativeToDetachment([0 0],[0 1]);
assert(abs(d4 - 90) < tol, 'tanpa det -> absolut 90°');
% sesar invalid -> NaN
assert(isnan(pivcore.pot.faultAngle.relativeToDetachment([0 0],[0 0],[0 0],[1 0])), 'sesar invalid -> NaN');
fprintf('[ok] relativeToDetachment: 45/15 + fallback absolut + NaN\n');

% =====================================================================
% 3) enforceLeftDip — q1=kiri, q2=kanan
% =====================================================================
[q1,q2] = pivcore.pot.faultAngle.enforceLeftDip([10 5],[2 8]);
assert(isequal(q1,[2 8]) && isequal(q2,[10 5]), 'enforceLeftDip: q1 harus x terkecil');
[r1,r2] = pivcore.pot.faultAngle.enforceLeftDip([1 1],[5 5]);
assert(isequal(r1,[1 1]) && isequal(r2,[5 5]), 'enforceLeftDip: sudah urut -> tak berubah');
% x sama -> urut per-y (bawah/kecil dulu)
[s1,s2] = pivcore.pot.faultAngle.enforceLeftDip([3 9],[3 2]);
assert(isequal(s1,[3 2]) && isequal(s2,[3 9]), 'enforceLeftDip: x sama -> y kecil dulu');
fprintf('[ok] enforceLeftDip: swap/no-swap/tie-break\n');

% =====================================================================
% 4) emptyDetachment / isValidDetachment
% =====================================================================
de = pivcore.pot.faultAngle.emptyDetachment();
assert(isstruct(de) && all(isnan(de.p1)) && all(isnan(de.p2)), 'emptyDetachment struct NaN');
assert(~pivcore.pot.faultAngle.isValidDetachment(de), 'empty -> invalid');
dv = struct('p1',[0 0],'p2',[10 3]);
assert(pivcore.pot.faultAngle.isValidDetachment(dv), 'det 2-titik beda -> valid');
assert(~pivcore.pot.faultAngle.isValidDetachment(struct('p1',[1 1],'p2',[1 1])), 'det berimpit -> invalid');
fprintf('[ok] emptyDetachment + isValidDetachment\n');

% =====================================================================
% 5) round-trip sidecar: detachment + angleDeg (write -> read)
% =====================================================================
tmpDir = tempname; mkdir(tmpDir);
cleaner = onCleanup(@() rmdir(tmpDir, 's')); %#ok<NASGU>
df = fullfile(tmpDir, 'DUMMY_exp_4p20px.mat');   % tak perlu ada (hanya utk path)

doc = pivcore.io.grain5Faults.emptyDoc(df, 26);
% default emptyDoc harus punya detachment kosong
assert(isfield(doc,'detachment'), 'emptyDoc tanpa field detachment');
assert(all(isnan(doc.detachment.p1)), 'emptyDoc detachment tak kosong');
% set detachment + satu fault ber-angleDeg
doc.detachment = struct('p1',[12.5 640.0], 'p2',[2988.0 655.5]);
f = pivcore.io.grain5Faults.faultStruct('F1', 40, 240, 5, 12, 3, 26);
assert(isfield(f,'angleDeg') && isnan(f.angleDeg), 'faultStruct tanpa angleDeg NaN default');
f.angleDeg = 33.7;
doc = pivcore.io.grain5Faults.upsertFault(doc, f);

pivcore.io.grain5Faults.write(df, doc);
p = pivcore.io.grain5Faults.dataPath(df);
assert(isfile(p), '_faults.json tak tertulis');

doc2 = pivcore.io.grain5Faults.read(df);
% detachment round-trip
assert(isfield(doc2,'detachment'), 'read tanpa detachment');
assert(max(abs(doc2.detachment.p1 - [12.5 640.0])) < 1e-6, 'detachment.p1 tak round-trip');
assert(max(abs(doc2.detachment.p2 - [2988.0 655.5])) < 1e-6, 'detachment.p2 tak round-trip');
assert(pivcore.pot.faultAngle.isValidDetachment(doc2.detachment), 'detachment round-trip harus valid');
% angleDeg round-trip
[f2,idx] = pivcore.io.grain5Faults.findFault(doc2, 'F1');
assert(idx==1 && isfield(f2,'angleDeg'), 'fault F1 tanpa angleDeg pasca-read');
assert(abs(f2.angleDeg - 33.7) < 1e-6, 'angleDeg tak round-trip');
fprintf('[ok] round-trip: detachment + angleDeg (write->read)\n');

% =====================================================================
% 6) backward-compat: sidecar LAMA (tanpa detachment/angleDeg) tetap terbaca
% =====================================================================
old = struct('formatName','GRAIN5 Fault Data','formatVersion',1, ...
    'source','DUMMY.mat','units','px/frame','signConvention','signed', ...
    'faults', {{struct('id','F1','parentId','','hwPosPx',40,'fwPosPx',240, ...
        'nuc',5,'fsr',12,'startF',3,'endF',26,'area',100,'dNet',5,'values',[])}});
oldP = pivcore.io.grain5Faults.dataPath(fullfile(tmpDir,'OLD_exp.mat'));
fid = fopen(oldP,'w'); fwrite(fid, jsonencode(old), 'char'); fclose(fid);
docOld = pivcore.io.grain5Faults.read(fullfile(tmpDir,'OLD_exp.mat'));
assert(isfield(docOld,'detachment') && all(isnan(docOld.detachment.p1)), ...
    'sidecar lama: detachment harus default kosong');
[fo,~] = pivcore.io.grain5Faults.findFault(docOld,'F1');
assert(isfield(fo,'angleDeg') && isnan(fo.angleDeg), 'sidecar lama: angleDeg harus NaN default');
assert(fo.hwPosPx==40 && fo.endF==26, 'sidecar lama: field lama harus utuh');
fprintf('[ok] backward-compat sidecar lama (tanpa detachment/angleDeg)\n');

fprintf('==== GRAIN5 ANGLE SEMUA LULUS ✓ ====\n');
end
