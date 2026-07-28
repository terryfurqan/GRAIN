function test_pab4_shots()
%TEST_PAB4_SHOTS  Uji MURNI (headless, tanpa render) engine produksi gambar
%   pivcore.io.pab4Shots + integrasi assets pivcore.io.pab4Comments.

fprintf('==== TEST pab4Shots (engine murni) ====\n');
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
pab_setup();

% --- specStruct: normalisasi + caption ---
p = struct('panel','axpot','frame',47,'frameTotal',106,'strainPct',12.34, ...
    'exp','TKS-5_cm-1','psgId','frac075','curvesVisible',{{'HW-2','HW-1'}}, ...
    'rawVisible',false,'pointsVisible',true,'indenterVisible',true, ...
    'climVel',[0 3.5],'shearAbs',0.05);
spec = pivcore.io.pab4Shots.specStruct(p);
assert(strcmp(spec.panel,'axpot'), 'panel salah');
assert(spec.frame==47 && spec.frameTotal==106, 'frame salah');
assert(iscell(spec.curvesVisible) && numel(spec.curvesVisible)==2, 'curvesVisible salah');
assert(~isempty(spec.caption) && contains(spec.caption,'TKS-5_cm-1'), 'caption kosong/salah');
assert(contains(spec.caption,'frame 47/106'), 'caption tak ada frame');
fprintf('[ok] specStruct + caption: "%s"\n', spec.caption);

% --- fingerprint: DETERMINISTIK + peka data ---
fp1 = pivcore.io.pab4Shots.fingerprint(spec);
assert(ischar(fp1) && numel(fp1)==8, 'fingerprint bukan 8-hex (=%s)', fp1);
% urutan curvesVisible TAK boleh mengubah fingerprint (di-sort)
p2 = p; p2.curvesVisible = {'HW-1','HW-2'};
fp2 = pivcore.io.pab4Shots.fingerprint(pivcore.io.pab4Shots.specStruct(p2));
assert(strcmp(fp1,fp2), 'fingerprint berubah saat urutan kurva ditukar (harus sama)');
% dataHash beda -> fingerprint beda (deteksi BASI)
p3 = p; p3.dataHash = 'abc123';
fp3 = pivcore.io.pab4Shots.fingerprint(pivcore.io.pab4Shots.specStruct(p3));
assert(~strcmp(fp1,fp3), 'fingerprint tak peka perubahan dataHash');
fprintf('[ok] fingerprint deterministik (%s), urutan-invarian, peka dataHash\n', fp1);

% --- isStale: spec sama -> tidak basi; dataHash beda -> basi ---
as = pivcore.io.pab4Shots.assetStruct(spec, 'axpot_HW1-HW2_f047.png', '2026-06-26 10:00:00');
assert(~pivcore.io.pab4Shots.isStale(as, spec), 'asset baru tak boleh basi');
assert(pivcore.io.pab4Shots.isStale(as, pivcore.io.pab4Shots.specStruct(p3)), 'perubahan data tak terdeteksi basi');
assert(~isempty(as.fingerprint) && strcmp(as.kind,'axpot'), 'assetStruct salah');
fprintf('[ok] isStale: padan->bukan basi, data berubah->BASI\n');

% --- assetName konsisten ---
nmV = pivcore.io.pab4Shots.assetName(pivcore.io.pab4Shots.specStruct( ...
    struct('panel','velmag','frame',47)));
assert(strcmp(nmV,'velmag_f047.png'), 'assetName velmag salah (=%s)', nmV);
nmA = pivcore.io.pab4Shots.assetName(spec);
assert(startsWith(nmA,'axpot_HW') && endsWith(nmA,'_f047.png'), 'assetName axpot salah (=%s)', nmA);
fprintf('[ok] assetName: %s / %s\n', nmV, nmA);

% --- sumbu-X strain%: nama _pct + fingerprint beda + caption ---
pS = p; pS.xUnit = 'strain'; pS.strainTotal = 22.5;
specS = pivcore.io.pab4Shots.specStruct(pS);
nmS = pivcore.io.pab4Shots.assetName(specS);
assert(contains(nmS,'_pct') && endsWith(nmS,'.png'), 'assetName strain tak ber-_pct (=%s)', nmS);
assert(~strcmp(pivcore.io.pab4Shots.fingerprint(spec), pivcore.io.pab4Shots.fingerprint(specS)), ...
    'fingerprint tak peka xUnit/strainTotal');
assert(contains(specS.caption,'x=strain%'), 'caption tak tandai strain');
fprintf('[ok] sumbu-X strain: %s + fingerprint peka + caption\n', nmS);

% --- commentDir + integrasi assets pab4Comments (round-trip) ---
tmp = tempname; mkdir(tmp);
clean = onCleanup(@() i_rmdir(tmp));
df = fullfile(tmp, 'TKS-5_cm-1.mat');
cdir = pivcore.io.pab4Shots.commentDir(df, 'c001');
assert(contains(cdir, fullfile('PAB4_claude','TKS-5_cm-1','comments','c001')), 'commentDir salah: %s', cdir);

doc = pivcore.io.pab4Comments.emptyDoc(df);
c = pivcore.io.pab4Comments.commentStruct(47,'frac075','HW-1','uji', 'USER');
[doc, id] = pivcore.io.pab4Comments.add(doc, c);
doc = pivcore.io.pab4Comments.setAssets(doc, id, {as});
pivcore.io.pab4Comments.write(df, doc);
rd = pivcore.io.pab4Comments.read(df);
assert(numel(rd.comments)==1, 'komentar tak tersimpan');
assert(isfield(rd.comments{1},'assets') && numel(rd.comments{1}.assets)==1, 'assets tak round-trip');
ra = rd.comments{1}.assets{1};
assert(strcmp(char(ra.fingerprint), fp1), 'fingerprint tak round-trip (%s vs %s)', char(ra.fingerprint), fp1);
fprintf('[ok] assets round-trip via _comments.json (fingerprint utuh)\n');

% --- manifest ---
pivcore.io.pab4Shots.writeManifest(df, pivcore.io.pab4Shots.manifestStruct(df,[0 3.5],0.05,106));
manP = fullfile(pivcore.io.pab4Comments.assetDir(df),'manifest.json');
assert(isfile(manP), 'manifest tak ditulis');
mm = jsondecode(fileread(manP));
assert(isfield(mm,'lockedClim') && mm.lockedClim.velmag(2)==3.5, 'manifest CLim salah');
fprintf('[ok] manifest CLim terkunci ditulis\n');

fprintf('==== pab4Shots SEMUA LULUS ✓ ====\n');
end

function i_rmdir(d), try, if isfolder(d), rmdir(d,'s'); end, catch, end, end
