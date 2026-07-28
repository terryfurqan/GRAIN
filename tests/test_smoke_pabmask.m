function test_smoke_pabmask()
%TEST_SMOKE_PABMASK  Uji masking persegi non-destruktif — engine + decode + GUI.
%
%   test_smoke_pabmask
%
%   Membangun MAT PREP SINTETIS (skema pivprep_single_v1) di folder TMP (tak
%   butuh data nyata), lalu uji:
%     A. Engine murni pivanalyzemat.core.maskRect: normalize, interpRect (frame
%        awal/tengah/akhir), applyMask (piksel jadi putih di region benar).
%     B. Round-trip resep: tulis prep.masking ke .mat -> readMatFrame(applyMask)
%        & unpackMat menghasilkan frame ber-kotak-putih di posisi interpolasi;
%        applyMask=false (editor) memberi frame BERSIH; blob asli TAK berubah.
%     C. GUI PABMASK — build, scan tabel MAT PREP, pilih baris (muat frame),
%        set kotak via state+commit, Simpan (resep ke SIDECAR '<nama>_mask.json',
%        MAT PREP nol-tulis, TANPA backup .bak), round-trip reload memuat resep.
%
%   SELALU MATLAB R2025b. SENYAP (DefaultFigureVisible off). Bersih (TMP dihapus).

fprintf('==== TEST SMOKE PAB MASKING ====\n');

here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
pab_setup();
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

assert(~isempty(which('pivanalyzemat.core.maskRect')),     'maskRect tak di path.');
assert(~isempty(which('pivanalyzemat.core.readMatFrame')),  'readMatFrame tak di path.');
assert(~isempty(which('pivanalyzemat.core.unpackMat')),     'unpackMat tak di path.');
assert(~isempty(which('PABMASK')),                          'PABMASK tak di path.');

% --- folder TMP + MAT PREP sintetis ----------------------------------
tmpRoot = fullfile(tempdir, sprintf('pabmask_test_%d', feature('getpid')));
if isfolder(tmpRoot), rmdir(tmpRoot,'s'); end
mkdir(tmpRoot);
cleanTmp = onCleanup(@() i_rmTmp(tmpRoot)); %#ok<NASGU>

nF = 5; W = 60; H = 40;
df = fullfile(tmpRoot, 'exp_mask.mat');
i_makeSyntheticPrep(df, nF, H, W);
fprintf('[ok] MAT PREP sintetis: %s (%dx%d, %d frame)\n', df, H, W, nF);

% =====================================================================
% A. ENGINE maskRect (murni)
% =====================================================================
fprintf('-- A. engine maskRect --\n');

% kotak awal [x y w h] -> bbox; kotak akhir lebih lebar
rf = [10 10 8 8];      % awal: x1=10..x2=18, y1=10..y2=18
rl = [10 10 28 8];     % akhir: lebar 28 -> x2=38
box = struct('rect_first',rf,'rect_last',rl,'frame_first',1,'frame_last',nF);

% interpRect frame 1 = awal, frame nF = akhir, tengah = interpolasi.
bb1 = pivanalyzemat.core.maskRect.interpRect(box, 1, nF, W, H);
bbN = pivanalyzemat.core.maskRect.interpRect(box, nF, nF, W, H);
bbM = pivanalyzemat.core.maskRect.interpRect(box, 3, nF, W, H);     % t=0.5 -> lebar (8+28)/2=18 -> x2=28
assert(isequal(bb1, [10 10 18 18]), 'interp frame1 salah: %s', mat2str(bb1));
assert(isequal(bbN, [10 10 38 18]), 'interp frameN salah: %s', mat2str(bbN));
assert(bbM(3) == 28, 'interp tengah x2 salah: %d (harap 28)', bbM(3));
fprintf('[ok] interpRect: f1=%s fmid x2=%d fN=%s\n', mat2str(bb1), bbM(3), mat2str(bbN));

% clamp di luar acuan (frame > nF) tetap menempel ke akhir
bbOver = pivanalyzemat.core.maskRect.interpRect(box, nF+5, nF, W, H);
assert(isequal(bbOver, bbN), 'clamp di luar acuan gagal');

% applyMask: region jadi putih, luar region tak berubah.
img = uint8(50 * ones(H, W));
masking = struct('enabled',true,'fill',255,'boxes',box);
out1 = pivanalyzemat.core.maskRect.applyMask(img, masking, 1, nF);
assert(all(all(out1(10:18, 10:18) == 255)), 'region awal tak putih');
assert(out1(1,1) == 50, 'luar region berubah');
% frame akhir region lebih lebar -> kolom 30 (di akhir) putih, (di awal) tidak.
outN = pivanalyzemat.core.maskRect.applyMask(img, masking, nF, nF);
assert(outN(12, 30) == 255, 'region akhir tak melebar');
assert(out1(12, 30) == 50,  'region awal seharusnya belum capai kolom 30');
% nonaktif -> no-op
outOff = pivanalyzemat.core.maskRect.applyMask(img, struct('enabled',false,'boxes',box), 1, nF);
assert(isequal(outOff, img), 'masking nonaktif tak no-op');
% RGB aman
outRGB = pivanalyzemat.core.maskRect.applyMask(repmat(img,[1 1 3]), masking, 1, nF);
assert(all(all(all(outRGB(10:18,10:18,:) == 255))), 'RGB region tak putih');
fprintf('[ok] applyMask: putih di region, no-op saat off, RGB OK\n');

% --- KEYFRAME tengah: interpolasi PATAH-PATAH (piecewise) ---
% Tanpa keyframe, frame 3 -> lebar interpolasi lurus (w=18, x2=28; dicek di atas).
% Tambah keyframe di frame 3 dgn kotak TETAP kecil (w=8) -> frame 3 harus pakai
% kotak keyframe (x2=18), BUKAN 28. Endpoint (f1/fN) tetap.
kfBox = box;
kfBox.keyframes = struct('frame_index',3, 'rect',[10 10 8 8]);
bbK1 = pivanalyzemat.core.maskRect.interpRect(kfBox, 1,  nF, W, H);
bbK3 = pivanalyzemat.core.maskRect.interpRect(kfBox, 3,  nF, W, H);
bbK4 = pivanalyzemat.core.maskRect.interpRect(kfBox, 4,  nF, W, H);   % antara kf(3) & akhir(5)
bbK5 = pivanalyzemat.core.maskRect.interpRect(kfBox, nF, nF, W, H);
assert(isequal(bbK1, bb1), 'keyframe: endpoint AWAL berubah: %s', mat2str(bbK1));
assert(isequal(bbK5, bbN), 'keyframe: endpoint AKHIR berubah: %s', mat2str(bbK5));
assert(bbK3(3) == 18, 'keyframe f3 x2 salah: %d (harap 18, bukan 28 lurus)', bbK3(3));
assert(bbK4(3) == 28, 'keyframe f4 x2 salah: %d (harap 28 = tengah kf3->akhir)', bbK4(3));
fprintf('[ok] keyframe: interpolasi patah (f3 x2=%d≠28, f4 x2=%d), endpoint utuh\n', bbK3(3), bbK4(3));

% backward-compat: box TANPA keyframes -> interpRect byte-identik dua-ujung.
box0 = box; if isfield(box0,'keyframes'), box0 = rmfield(box0,'keyframes'); end
assert(isequal(pivanalyzemat.core.maskRect.interpRect(box0,3,nF,W,H), bbM), ...
    'tanpa-keyframe tak identik dua-ujung');

% normalizeBox: keyframe invalid (frame<1 / rect w,h<=0) dibuang; terurut.
badbox = kfBox;
badbox.keyframes = struct('frame_index',{4, 0, 2}, ...
                          'rect',{[1 1 5 5], [1 1 5 5], [1 1 -1 5]});
nb = pivanalyzemat.core.maskRect.normalizeBox(badbox);
assert(numel(nb.keyframes) == 1 && nb.keyframes(1).frame_index == 4, ...
    'normalizeBox tak buang keyframe invalid / tak terurut');
fprintf('[ok] normalizeBox: keyframe invalid dibuang, terurut\n');

% Round-trip SIDECAR mempertahankan keyframes (jsonencode/decode + i_coerceBoxes).
kfMasking = struct('enabled',true,'fill',255,'n_ref',nF,'boxes',kfBox);
okKf = pivanalyzemat.core.maskSidecar.write(df, kfMasking);
assert(okKf, 'tulis sidecar keyframe gagal');
r2 = pivanalyzemat.core.maskSidecar.read(df);
assert(~isempty(r2) && ~isempty(r2.boxes) && numel(r2.boxes(1).keyframes) == 1, ...
    'keyframe hilang round-trip sidecar');
assert(round(r2.boxes(1).keyframes(1).frame_index) == 3, 'frame_index keyframe sidecar salah');
assert(isequal(round(r2.boxes(1).keyframes(1).rect), [10 10 8 8]), 'rect keyframe sidecar salah');
pivanalyzemat.core.maskSidecar.remove(df);      % bersih untuk bagian B
fprintf('[ok] round-trip sidecar mempertahankan keyframes\n');

% =====================================================================
% B. ROUND-TRIP resep di MAT PREP (readMatFrame + unpackMat)
% =====================================================================
fprintf('-- B. round-trip resep masking (SIDECAR) --\n');
% baseline NON-DESTRUKTIF: frame BERSIH terdekode SEBELUM tulis masking. "blob
% asli utuh" diuji lewat citra terdekode yang IDENTIK.
cleanBefore = pivanalyzemat.core.readMatFrame(df, 'first', false);
assert(~isempty(cleanBefore), 'frame bersih baseline kosong');

% NOL-TULIS: rekam ukuran+mtime .mat sebelum tulis resep -> harus TAK berubah.
dBefore = dir(df);

% tulis resep ke SIDECAR '<nama>_mask.json' (bukan menyentuh .mat).
mnorm = pivanalyzemat.core.maskRect.normalize(masking);
ok = pivanalyzemat.core.prepBlobStore.writeMasking(df, mnorm);
assert(ok, 'writeMasking (sidecar) gagal');
assert(pivanalyzemat.core.maskSidecar.has(df), 'sidecar _mask.json tak dibuat');

% MAT PREP TAK ditulis ulang (byte & mtime sama).
dAfter = dir(df);
assert(dBefore.bytes == dAfter.bytes, 'ukuran .mat berubah (harusnya nol-tulis!)');
assert(abs(dBefore.datenum - dAfter.datenum) < 1e-9, 'mtime .mat berubah (harusnya nol-tulis!)');

% readMatFrame BERSIH (applyMask=false) -> tak ada putih di region.
imgClean = pivanalyzemat.core.readMatFrame(df, 'first', false);
assert(~isempty(imgClean), 'frame bersih kosong');
% (frame sintetis tak 255 di region) -> region BUKAN semua putih
assert(~all(all(imgClean(10:18,10:18) == 255)), 'frame bersih malah ter-masking');
% NON-DESTRUKTIF: frame bersih SETELAH tulis masking == baseline (blob utuh).
assert(isequal(imgClean, cleanBefore), 'blob asli berubah (destruktif!)');

% readMatFrame ter-MASKING (default) -> region putih.
imgMaskF = pivanalyzemat.core.readMatFrame(df, 'first');     % applyMask default true
imgMaskL = pivanalyzemat.core.readMatFrame(df, 'last');
% JPEG lossy -> pakai ambang, bukan ==255 ketat.
assert(mean(mean(imgMaskF(11:17,11:17))) > 240, 'frame awal region tak putih (mask)');
assert(mean(mean(imgMaskL(11:17,30:36))) > 240, 'frame akhir region lebar tak putih');
fprintf('[ok] readMatFrame: bersih vs ter-masking; MAT PREP nol-tulis (sidecar)\n');

% readMatFramePair (dipakai PRATINJAU PAB2) HARUS menempel masking juga supaya
% pratinjau WYSIWYG dgn output PIV (PAB2 kompatibel PABMASK).
[pA, pB] = pivanalyzemat.core.readMatFramePair(df);          % applyMask default true
assert(mean(mean(pA(11:17,11:17))) > 240, 'pair AWAL region tak putih (mask)');
assert(mean(mean(pB(11:17,30:36))) > 240, 'pair AKHIR region lebar tak putih (mask)');
[cA, cB] = pivanalyzemat.core.readMatFramePair(df, false);   % bersih (editor)
assert(~all(all(cA(10:18,10:18) == 255)), 'pair applyMask=false malah ter-masking');
assert(~isequal(pB, cB), 'pair mask vs bersih identik (masking tak nempel)');
fprintf('[ok] readMatFramePair: mask nempel (pratinjau PAB2 WYSIWYG) + bersih saat off\n');

% unpackMat -> RAW di disk ter-masking; GS regen ikut bersih.
exps = pivanalyzemat.core.scanMats(tmpRoot);
assert(~isempty(exps), 'scanMats tak menemukan MAT PREP');
entry = pivanalyzemat.core.unpackMat(exps(1), 'Force', true);
rawF = i_firstImg(entry.path);
assert(~isempty(rawF), 'RAW unpack kosong');
rawImg = imread(rawF);
assert(mean(mean(rawImg(11:17,11:17))) > 240, 'RAW unpack region tak putih');
% GS folder ada & juga ter-masking (regen dari RAW ter-masking)
if ~isempty(entry.gsdir) && isfolder(entry.gsdir)
    gsF = i_firstImg(entry.gsdir);
    if ~isempty(gsF)
        gsImg = imread(gsF);
        % GS diperkecil; region awal proporsional -> cek mean tinggi di pojok kiri-atas region.
        assert(mean(gsImg(:)) >= mean(rawImg(:)) - 60, 'GS jauh beda (sanity)');
        fprintf('[ok] unpackMat: RAW ter-masking + GS regen ada\n');
    end
else
    fprintf('[ok] unpackMat: RAW ter-masking (GS dilewati)\n');
end
try, pivanalyzemat.core.cleanupTmp(); catch, end %#ok<CTCH>

% regresi: tanpa masking -> unpack passthrough (RAW disk == blob asli byte).
i_makeSyntheticPrep(df, nF, H, W);             % reset MAT PREP tanpa masking
pivanalyzemat.core.maskSidecar.remove(df);     % pastikan TAK ada resep sidecar
pivanalyzemat.core.prepRawCache('', 'clear');  % buang cache lama (fixture ganti)
exps2 = pivanalyzemat.core.scanMats(tmpRoot);
entry2 = pivanalyzemat.core.unpackMat(exps2(1), 'Force', true);
rawF2 = i_firstImg(entry2.path);
b = i_readBytes(rawF2);
% Byte blob frame pertama (urutan leksikografis) langsung dari prep.raw.
S2 = load(df, 'prep'); nm = sort(S2.prep.raw.names(:));
[~, want] = ismember(nm{1}, S2.prep.raw.names(:));
b0 = S2.prep.raw.blobs{S2.prep.raw.index(want)};
assert(isequal(uint8(b(:)), uint8(b0(:))), ...
    'passthrough byte berubah saat masking OFF');
fprintf('[ok] regresi: masking OFF -> RAW byte-identik blob (passthrough)\n');
try, pivanalyzemat.core.cleanupTmp(); catch, end %#ok<CTCH>

% =====================================================================
% C. GUI PABMASK  (figure+uicontrol klasik -> headless -batch)
% =====================================================================
fprintf('-- C. GUI PABMASK --\n');
i_makeSyntheticPrep(df, nF, H, W);             % bersih, tanpa masking
pivanalyzemat.core.maskSidecar.remove(df);     % buang sidecar dari bagian B
pivanalyzemat.core.prepRawCache('', 'clear');
PABMASK(tmpRoot);
% Title bar kini memuat keterangan versi (pivui.titleWithVersion) -> cocokkan
% PREFIX, bukan Name persis.
figs = findall(0,'Type','figure');
fig = [];
for ii = 1:numel(figs)
    if startsWith(get(figs(ii),'Name'), 'PAB Masking —'); fig = figs(ii); break; end
end
assert(~isempty(fig), 'jendela PABMASK tak terbuka');
fig = fig(1);
closeFig = onCleanup(@() i_closeFig(fig)); %#ok<NASGU>
h = guidata(fig);
assert(numel(h.list) == 1, 'tabel exp salah jumlah: %d', numel(h.list));
assert(strcmp(h.list(1).name,'exp_mask'), 'nama exp salah: %s', h.list(1).name);

% pilih baris -> muat frame awal/akhir BERSIH
i_fireCellSel(h.tbl, 1);
h = guidata(fig);
assert(h.activeRow == 1, 'baris aktif tak ter-set');
assert(~isempty(h.imgFirst) && ~isempty(h.imgLast), 'frame tak termuat');
assert(isequal(h.imSz, [H W]), 'ukuran frame salah: %s', mat2str(h.imSz));

% set kotak AWAL & AKHIR lewat state (drawrectangle interaktif tak ada headless)
h.editTarget = 'first'; h.list(1).rectFirst = rf; h.list(1).enabled = true;
h.editTarget = 'last';  h.list(1).rectLast  = rl;
set(h.chkEnable,'Value',1);
guidata(fig, h);
i_fireCb(h.chkEnable);                          % toggle enable -> mark dirty + refresh
h = guidata(fig);
assert(h.list(1).enabled, 'enable tak ter-set');
assert(h.list(1).dirty, 'tak ditandai dirty');

% pratinjau interpolasi (slider) tak boleh error
set(h.sld,'Value',3); i_fireCb(h.sld);
h = guidata(fig);
assert(h.previewFrame == 3, 'preview frame tak update');

% "🖼 Tampilkan frame ini" pada frame 3 -> muat frame nyata on-demand ke kanvas.
set(h.sld,'Value',3);
i_fireBtnByStr(fig, '🖼 Tampilkan frame ini');
h = guidata(fig);
assert(strcmp(h.viewMode,'preview'), 'mode preview tak aktif');
assert(h.prevLoaded == 3, 'frame pratinjau tak termuat (prevLoaded=%d)', h.prevLoaded);
assert(~isempty(h.imgPrev), 'imgPrev kosong');
% ukuran frame pratinjau = ukuran frame awal (resolusi penuh -> kotak pas)
assert(isequal([size(h.imgPrev,1) size(h.imgPrev,2)], h.imSz), ...
    'ukuran frame pratinjau != imSz (kotak takkan pas)');
assert(~isempty(h.ovl) && isgraphics(h.ovl), 'overlay kotak interpolasi tak tergambar');

% --- KEYFRAME tengah via GUI (mode preview frame 3, tanpa ROI -> nudge interp) ---
h = guidata(fig);
assert(h.previewFrame == 3 && strcmp(h.viewMode,'preview'), 'prasyarat preview f3');
i_fireBtnByStr(fig, '＋ Set KF');               % tak ada ROI -> ambil kotak interpolasi f3
h = guidata(fig);
assert(numel(h.list(1).keyframes) == 1, 'keyframe tengah tak ter-set');
assert(h.list(1).keyframes(1).frame_index == 3, 'keyframe frame_index salah: %d', ...
    h.list(1).keyframes(1).frame_index);
assert(h.list(1).dirty, 'set keyframe tak menandai dirty');
kfD = get(h.kfTbl,'Data');
assert(size(kfD,1) == 3, 'tabel keyframe bukan 3 node (AWAL/tengah/AKHIR): %d', size(kfD,1));
fprintf('[ok] GUI: set keyframe tengah frame 3; tabel 3 node\n');
% Navigasi Prev/Next keyframe: f3 -> Next -> f5 (AKHIR) -> Prev -> f3
i_fireBtnByStr(fig, 'KF ▶'); h = guidata(fig);
assert(h.previewFrame == 5, 'Next KF tak ke frame 5: %d', h.previewFrame);
i_fireBtnByStr(fig, '◀ KF'); h = guidata(fig);
assert(h.previewFrame == 3, 'Prev KF tak ke frame 3: %d', h.previewFrame);
fprintf('[ok] GUI: loncat Prev/Next keyframe (tanpa scan frame-by-frame)\n');

% kembali ke awal/akhir untuk edit
i_fireBtnByStr(fig, '↩ Kembali awal/akhir');
h = guidata(fig);
assert(~strcmp(h.viewMode,'preview'), 'tak kembali dari mode preview');
fprintf('[ok] Tampilkan frame %d on-demand: mode preview, ukuran penuh, kotak overlay\n', 3);

% Simpan aktif -> tulis resep ke SIDECAR '<nama>_mask.json', MAT PREP nol-tulis.
dPre = dir(df);
i_fireCb(h.btnSave);
h = guidata(fig);
assert(~h.list(1).dirty, 'masih dirty setelah simpan');
% NON-DESTRUKTIF: TAK ada backup .bak; MAT PREP TAK ditulis ulang.
assert(~isfile([df '.bak']), 'backup .bak dibuat (harusnya TIDAK)');
dPost = dir(df);
assert(dPre.bytes == dPost.bytes && abs(dPre.datenum - dPost.datenum) < 1e-9, ...
    'MAT PREP berubah saat simpan (harusnya nol-tulis!)');
% Resep tersimpan di SIDECAR (bukan di .mat).
assert(pivanalyzemat.core.maskSidecar.has(df), 'sidecar _mask.json tak dibuat');
mg = pivanalyzemat.core.maskSidecar.read(df);
assert(~isempty(mg) && mg.enabled && ~isempty(mg.boxes), 'masking tersimpan tak aktif');
assert(isequal(round(mg.boxes(1).rect_first), rf), 'rect_first tersimpan salah: %s', ...
    mat2str(mg.boxes(1).rect_first));
assert(numel(mg.boxes(1).keyframes) == 1 && round(mg.boxes(1).keyframes(1).frame_index) == 3, ...
    'keyframe tak ikut tersimpan ke sidecar');
fprintf('[ok] GUI: muat->set kotak+keyframe->simpan; SIDECAR ditulis; MAT PREP nol-tulis; TANPA .bak\n');

% round-trip: pindai ulang -> baris memuat resep (Masking=ON)
i_fireCb(findall(fig,'Style','pushbutton','String','🔄 Pindai ulang'));
h = guidata(fig);
assert(h.list(1).enabled, 'round-trip: resep tak termuat (enabled false)');
assert(~isempty(h.list(1).rectFirst), 'round-trip: rectFirst hilang');
assert(numel(h.list(1).keyframes) == 1, 'round-trip: keyframe hilang saat reload');
D = get(h.tbl,'Data');
assert(strcmp(D{1,3},'ON'), 'kolom Masking tak ON pasca-reload: %s', D{1,3});
fprintf('[ok] round-trip reload memuat resep + keyframe (Masking ON)\n');

% Save/Load Progress per-root: simpan -> ubah state -> muat -> pulih.
i_fireBtnByStr(fig, '💾 Simpan Progress');
assert(isfile(fullfile(tmpRoot,'PABMASK_progress.mat')), 'PABMASK_progress.mat tak dibuat');
% rusak state di memori (seolah sesi baru), lalu muat progress.
h = guidata(fig);
h.list(1).enabled = false; h.list(1).rectFirst = []; h.list(1).rectLast = [];
h.list(1).keyframes = struct('frame_index',{},'rect',{});
guidata(fig, h);
i_fireBtnByStr(fig, '📂 Muat Progress');
h = guidata(fig);
assert(h.list(1).enabled, 'load progress: enabled tak pulih');
assert(isequal(round(h.list(1).rectFirst), rf), 'load progress: rectFirst tak pulih: %s', ...
    mat2str(h.list(1).rectFirst));
assert(numel(h.list(1).keyframes) == 1, 'load progress: keyframe tak pulih');
fprintf('[ok] Save/Load Progress per-root: resep + keyframe pulih dari PABMASK_progress.mat\n');

% Hapus masking -> nonaktif
i_fireCellSel(h.tbl, 1); h = guidata(fig);
i_fireCb(h.btnClear); h = guidata(fig);
assert(~h.list(1).enabled, 'hapus masking gagal');
fprintf('[ok] hapus masking menonaktifkan\n');

fprintf('==== SEMUA UJI PAB MASKING LULUS ====\n');
end

% =====================================================================
%  Builder MAT PREP sintetis (skema pivprep_single_v1)
% =====================================================================
function i_makeSyntheticPrep(matFile, nFrames, H, W)
    names = cell(nFrames,1); blobs = cell(nFrames,1); idx = uint32(1:nFrames);
    for k = 1:nFrames
        img = uint8(40 + 8*k + zeros(H, W));       % mean naik per-bingkai
        img(20:25, 5:9) = uint8(120);              % motif gelap di luar region mask
        names{k} = sprintf('frame%03d-RAW.jpg', k);
        tmp = [tempname '.jpg'];
        imwrite(img, tmp, 'jpg', 'Quality', 95);
        blobs{k} = i_readBytes(tmp); delete(tmp);
    end
    prep = struct();
    prep.format      = 'pivprep_single_v1';
    prep.created     = '2026-01-01 00:00:00';
    prep.source_base = fileparts(matFile);
    prep.pab_src     = '';
    prep.nFrames     = nFrames;
    prep.sequencing  = struct('mode','consecutive','step',1);
    prep.raw = struct('format','jpeg_dedup_v1','blobs',{blobs}, ...
        'index',idx,'names',{names},'ext','.jpg');
    prep.gs  = struct('format','jpeg_dedup_v1','blobs',{{}}, ...
        'index',uint32([]),'names',{{}},'ext','.jpg','quality',92);
    prep.gs_embedded = false;
    prep.gs_scale    = 0.5;
    prep.gs_quality  = 92;
    prep.exif        = [];
    prep.jitter      = [];
    save(matFile, 'prep', '-v7');
end

% =====================================================================
%  Util
% =====================================================================
function f = i_firstImg(dirPath)
    f = '';
    if isempty(dirPath) || ~isfolder(dirPath), return; end
    pats = {'*.jpg','*.jpeg','*.png','*.tif'};
    nm = {};
    for i = 1:numel(pats)
        dd = dir(fullfile(dirPath, pats{i}));
        for j = 1:numel(dd), if ~dd(j).isdir, nm{end+1} = dd(j).name; end; end %#ok<AGROW>
    end
    if isempty(nm), return; end
    nm = sort(nm);
    f = fullfile(dirPath, nm{1});
end

function b = i_readBytes(p)
    fid = fopen(p,'rb'); b = fread(fid, Inf, '*uint8'); fclose(fid);
end

function i_fireCellSel(tbl, row)
    ev = struct('Indices', [row 1]);
    cb = get(tbl, 'CellSelectionCallback');
    if iscell(cb), cb{1}(tbl, ev); else, cb(tbl, ev); end
end

function i_fireBtnByStr(fig, str)
    b = findall(fig, 'Style','pushbutton', 'String', str);
    assert(~isempty(b), 'tombol "%s" tak ditemukan', str);
    i_fireCb(b(1));
end

function i_fireCb(obj)
    assert(~isempty(obj), 'kontrol tak ditemukan');
    obj = obj(1);
    cb = get(obj, 'Callback');
    if ~isempty(cb)
        if iscell(cb), cb{1}(obj, struct()); else, cb(obj, struct()); end
    end
end

function i_closeFig(fig)
    try, if isgraphics(fig), delete(fig); end; catch, end %#ok<CTCH>
end

function i_rmTmp(p)
    try, if isfolder(p), rmdir(p,'s'); end; catch, end %#ok<CTCH>
end
