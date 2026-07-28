function test_pab6_hbmerge()
%TEST_PAB6_HBMERGE  Unit test engine murni PAB6: pivcore.pot.hbMerge (merge
%   kandidat HB, overlap=MAX, tanpa ekor) + pivcore.io.pab6Hb (sidecar _hb.json
%   round-trip). Headless, tak butuh GUI/figure.

fprintf('==== TEST PAB6 HB ENGINE ====\n');
here = fileparts(mfilename('fullpath'));
addpath(fileparts(here));
pab_setup();

% --- hbMerge.merge: overlap = MAX (envelope atas) ---
c1 = struct('values',[3 3 3 3 3],'x0',1,'x1',3);
c2 = struct('values',[9 8 7 6 5],'x0',2,'x1',4);
[hb, sx] = pivcore.pot.hbMerge.merge({c1,c2}, 5);
assert(isequaln(hb,[3 8 7 6 NaN]), 'overlap harus MAX (bukan mean)');
assert(sx==1, 'startX = X0 kurva pertama');
fprintf('[ok] merge overlap=MAX + startX\n');

% --- Tanpa ekor sebelum X0 kurva pertama ---
c3 = struct('values',[5 5 5 5 5],'x0',3,'x1',5);
c4 = struct('values',[1 1 1 1 1],'x0',1,'x1',5);
[hb2, sx2] = pivcore.pot.hbMerge.merge({c3,c4}, 5);
assert(isequaln(hb2(1:2),[NaN NaN]), 'tak boleh ada ekor sebelum X0 kurva-1');
assert(isequaln(hb2(3:5),[5 5 5]), 'MAX zona salah');
assert(sx2==3, 'startX salah');
fprintf('[ok] tanpa ekor (startX>1)\n');

% --- NaN x0/x1 -> pakai tepi 1/nF ; struct array & cell keduanya ---
ca(1) = struct('values',[2 4 6 8],'x0',NaN,'x1',NaN);
[hb3,~] = pivcore.pot.hbMerge.merge(ca, 4);
assert(isequaln(hb3,[2 4 6 8]), 'NaN x0/x1 -> rentang penuh salah');
% clipToRange
y = pivcore.pot.hbMerge.clipToRange([2 4 6 8], 2, 3, 4);
assert(isequaln(y,[NaN 4 6 NaN]), 'clipToRange salah');
% kosong
[hb4,sx4] = pivcore.pot.hbMerge.merge({}, 10);
assert(all(isnan(hb4)) && isnan(sx4), 'input kosong salah');
fprintf('[ok] NaN-tepi + clipToRange + kosong\n');

% --- pab6Hb round-trip sidecar _hb.json ---
tmpf = fullfile(tempdir, 'pab6hb_unit.mat');
p = pivcore.io.pab6Hb.dataPath(tmpf);
if isfile(p), delete(p); end
doc = pivcore.io.pab6Hb.emptyDoc(tmpf, 300);
assert(strcmp(doc.formatName,'PAB6 HB Data'), 'formatName salah');
blk = pivcore.io.pab6Hb.hbBlockStruct('geom_1_2_3_4');
blk.candidates{end+1} = pivcore.io.pab6Hb.candStruct(120.5, 10, 120);
blk.candidates{end+1} = pivcore.io.pab6Hb.candStruct(340.2, 60, 200);
doc = pivcore.io.pab6Hb.upsertBlock(doc, blk);
pivcore.io.pab6Hb.write(tmpf, doc);
assert(isfile(p), '_hb.json tak tertulis');
doc2 = pivcore.io.pab6Hb.read(tmpf);
[b2, idx] = pivcore.io.pab6Hb.findBlock(doc2, 'geom_1_2_3_4');
assert(idx==1 && numel(b2.candidates)==2, 'blok/kandidat tak round-trip');
assert(abs(b2.candidates{1}.posPx-120.5)<1e-9, 'posPx tak round-trip');
assert(b2.candidates{1}.x0==10 && b2.candidates{1}.x1==120, 'x0/x1 tak round-trip');
% remove
doc2 = pivcore.io.pab6Hb.removeBlock(doc2, 'geom_1_2_3_4');
assert(isempty(doc2.psgHb), 'removeBlock salah');
delete(p);
fprintf('[ok] pab6Hb round-trip + upsert/remove\n');

% --- read file tak ada -> emptyDoc (tak melempar) ---
docE = pivcore.io.pab6Hb.read('/nonexistent/xyz.mat');
assert(strcmp(docE.formatName,'PAB6 HB Data') && isempty(docE.psgHb), 'read no-file bukan emptyDoc');
fprintf('[ok] read no-file -> emptyDoc\n');

fprintf('==== PAB6 HB ENGINE SEMUA LULUS ✓ ====\n');
end
