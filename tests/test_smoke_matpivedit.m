function test_smoke_matpivedit()
%TEST_SMOKE_MATPIVEDIT  Uji MAT PIV Editor (QC · Geometri · Hapus Frame · Masking).
%
%   test_smoke_matpivedit
%
%   MATPIVEDIT kini GUI 3-kolom yang menumpang pivui.pab4Shell (axMain 2D +
%   axPOT + PSG + slider) dengan panel kanan 3 tab. Uji:
%     A. readPivBgPair latar GS tersemat (frame awal+akhir).
%     B. Engine matpivEdit: backup .bak berlapis; writeGeom (recompute strain +
%        blob PIV/GS UTUH); dropFrames (buang FISIK frame + prune GS dedup +
%        backup); maskFromBoxes + writeMask/readMask sidecar (_mask.json).
%     C. GUI MATPIVEDIT — build shell, scan tabel, muat exp (axMain render),
%        tab ① isi field geometri + Simpan; tab ② tandai frame + buang → sisa
%        frame benar; tab ③ tambah kotak (data) + Simpan sidecar → readMask OK.
%
%   SELALU MATLAB R2025b. SENYAP (DefaultFigureVisible off). Bersih (TMP dihapus).

fprintf('==== TEST SMOKE MAT PIV EDITOR ====\n');

here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
pab_setup();
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

assert(~isempty(which('pivanalyzemat.core.readPivBgPair')), 'readPivBgPair tak di path.');
assert(~isempty(which('pivanalyzemat.core.pivGeomIO')),    'pivGeomIO tak di path.');
assert(~isempty(which('pivanalyzemat.core.matpivEdit')),   'matpivEdit tak di path.');
assert(~isempty(which('PIVlab_automasi_dropframes')),      'dropframes tak di path.');
assert(~isempty(which('MATPIVEDIT')),                      'MATPIVEDIT tak di path.');
assert(~isempty(which('pivui.pab4Shell')),                 'pab4Shell tak di path.');

% --- folder TMP + MAT PIV sintetis -----------------------------------
tmpRoot = fullfile(tempdir, sprintf('matpivedit_test_%d', feature('getpid')));
if isfolder(tmpRoot), rmdir(tmpRoot,'s'); end
mkdir(tmpRoot);
cleanTmp = onCleanup(@() i_rmTmp(tmpRoot));

df = fullfile(tmpRoot, 'exp_5cm.mat');
i_makeSyntheticPiv(df, 5, [12.0 8.0 20.0]);   % 5 frame; X0=12 X1=8 Lpos=20 (strain 50%)
fprintf('[ok] MAT PIV sintetis (5 frame): %s\n', df);

% =====================================================================
% A. HELPER baca latar GS tersemat
% =====================================================================
fprintf('-- A. readPivBgPair --\n');
[imgF, imgL, nF, fmt] = pivanalyzemat.core.readPivBgPair(df);
assert(nF == 5, 'nFrames salah: %d', nF);
assert(strcmp(fmt,'jpeg_dedup_v1'), 'fmt salah: %s', fmt);
assert(~isempty(imgF) && ~isempty(imgL), 'foto awal/akhir kosong');
assert(abs(mean(imgF(:)) - mean(imgL(:))) > 1, 'foto awal==akhir (tak terbedakan)');
fprintf('[ok] foto awal/akhir beda mean=%.1f\n', abs(mean(imgF(:))-mean(imgL(:))));

% =====================================================================
% B. ENGINE matpivEdit — geom, drop-frame, masking sidecar
% =====================================================================
fprintf('-- B1. writeGeom + blob utuh + backup --\n');
g0 = pivanalyzemat.core.matpivEdit.readGeom(df);
assert(g0.X0_cm==12 && g0.X1_cm==8 && g0.Lpos_cm==20, 'geom awal salah');
assert(abs(g0.strain_cumm_pct - 50) < 1e-6, 'strain awal salah: %.4g', g0.strain_cumm_pct);

S0 = load(df, 'bg_images_blobs', 'velocity_magnitude');
[g1, bak] = pivanalyzemat.core.matpivEdit.writeGeom(df, 10, 8, 20, true);
assert(abs(g1.strain_cumm_pct - 20) < 1e-6, 'strain baru salah: %.4g', g1.strain_cumm_pct);
assert(isfile(bak), 'backup .bak tak dibuat oleh writeGeom');
g1r = pivanalyzemat.core.matpivEdit.readGeom(df);
assert(g1r.X0_cm==10 && abs(g1r.strain_cumm_pct-20)<1e-6, 'geom tak tersimpan');
S1 = load(df, 'bg_images_blobs', 'velocity_magnitude');
assert(isequal(S0.bg_images_blobs, S1.bg_images_blobs), 'blob GS berubah!');
assert(isequal(S0.velocity_magnitude, S1.velocity_magnitude), 'blob PIV berubah!');
% backup berlapis -> .bak2
[bak2, made2] = pivanalyzemat.core.matpivEdit.backup(df);
assert(made2 && endsWith(bak2,'.bak2'), 'backup berlapis .bak2 gagal: %s', bak2);
fprintf('[ok] geom 50%%->20%% tersimpan, blob utuh, backup .bak/.bak2\n');

fprintf('-- B2. dropFrames (buang FISIK frame + prune GS) --\n');
% buang frame 2 & 4 dari 5 -> sisa 3 (frame 1,3,5).
info = pivanalyzemat.core.matpivEdit.dropFrames(df, [2 4], true);
assert(info.nDrop == 2 && info.nKept == 3, 'drop count salah: kept=%d drop=%d', info.nKept, info.nDrop);
assert(isfile(info.bak), 'backup drop tak dibuat');
Sd = load(df, 'velocity_magnitude', 'bg_images_index', 'x');
assert(numel(Sd.velocity_magnitude) == 3, 'cell PIV tak terpangkas: %d', numel(Sd.velocity_magnitude));
assert(numel(Sd.x) == 3, 'cell x tak terpangkas: %d', numel(Sd.x));
assert(numel(Sd.bg_images_index) == 3, 'bg_images_index tak terpangkas: %d', numel(Sd.bg_images_index));
[~,~,nFd] = pivanalyzemat.core.readPivBgPair(df);
assert(nFd == 3, 'nFrames pasca-drop salah: %d', nFd);
fprintf('[ok] drop 2 frame -> sisa %d; GS index & cell terpangkas\n', info.nKept);

fprintf('-- B3. masking sidecar (maskRect + maskSidecar) --\n');
boxes = struct('rect_first',[5 5 10 8], 'rect_last',[7 6 10 8], ...
    'frame_first',1, 'frame_last',NaN, 'keyframes',[]);
m = pivanalyzemat.core.matpivEdit.maskFromBoxes(boxes, 255, 3);
assert(pivanalyzemat.core.maskRect.isActive(m), 'maskFromBoxes tak aktif');
ok = pivanalyzemat.core.matpivEdit.writeMask(df, m);
assert(ok, 'writeMask gagal');
assert(pivanalyzemat.core.maskSidecar.has(df), 'sidecar _mask.json tak ada');
mr = pivanalyzemat.core.matpivEdit.readMask(df);
assert(pivanalyzemat.core.maskRect.isActive(mr) && numel(mr.boxes)==1, 'readMask salah');
assert(isequal(round(mr.boxes(1).rect_first), [5 5 10 8]), 'rect_first tak konsisten');
% interp bbox di frame tengah harus di antara first & last (x geser 5->7).
bb = pivanalyzemat.core.matpivEdit.maskBoxAtFrame(mr.boxes(1), 2, 3, 100, 100, mr.n_ref);
assert(~isempty(bb) && bb(1) >= 5 && bb(1) <= 7, 'interp mask x di luar rentang: %d', bb(1));
% hapus sidecar via writeMask([]) -> nonaktif
pivanalyzemat.core.matpivEdit.writeMask(df, []);
assert(~pivanalyzemat.core.maskSidecar.has(df), 'sidecar tak terhapus saat mask kosong');
fprintf('[ok] mask sidecar tulis/baca/interp/hapus OK\n');

% reset df ke kondisi bersih utk uji GUI (5 frame, strain 50%).
i_cleanBaks(df);
i_makeSyntheticPiv(df, 5, [12.0 8.0 20.0]);

% =====================================================================
% C. GUI MATPIVEDIT (pab4Shell + 3 tab)
% =====================================================================
fprintf('-- C. GUI MATPIVEDIT --\n');
MATPIVEDIT(tmpRoot);
figs = findall(0,'Type','figure');
fig = [];
for ii = 1:numel(figs)
    if startsWith(get(figs(ii),'Name'), 'MAT PIV Editor —'); fig = figs(ii); break; end
end
assert(~isempty(fig), 'jendela editor tak terbuka');
fig = fig(1);
closeFig = onCleanup(@() i_closeFig(fig));
h = guidata(fig);
assert(numel(h.list) == 1, 'tabel exp salah jumlah: %d', numel(h.list));
assert(strcmp(h.list(1).name,'exp_5cm'), 'nama exp salah');
% shell auto-load exp pertama -> data termuat + field geometri terisi.
assert(~isempty(h.data), 'data axMain tak termuat oleh shell');
assert(h.me.nF == 5, 'nF salah di state: %d', h.me.nF);
assert(str2double(get(h.me_edGeom(1),'String'))==12, 'field X0 tak terisi');

% --- Tab ① Geometri: edit X0 -> 10 + Simpan ---
set(h.me_edGeom(1), 'String', '10');
i_fireCb(h.me_edGeom(1));
i_fireCb(h.me_btnSaveGeom);
gAfter = pivanalyzemat.core.matpivEdit.readGeom(df);
assert(gAfter.X0_cm==10, 'X0 tak tersimpan via GUI');
assert(abs(gAfter.strain_cumm_pct-20)<1e-6, 'strain GUI salah: %.4g', gAfter.strain_cumm_pct);
assert(isfile([df '.bak']), 'backup geom GUI tak dibuat');
fprintf('[ok] Tab①: edit X0->10 + Simpan; strain=%.4g%%\n', gAfter.strain_cumm_pct);

% --- Tab ②: tandai frame 3 lalu buang → sisa 4 frame ---
h = guidata(fig);
h.frame = 3; guidata(fig, h);           % simulasi slider di frame 3
i_fireBtn(findall(fig,'Style','pushbutton','String','⚑ Tandai frame ini (dari slider)'));
h = guidata(fig);
assert(isequal(h.me.dropSet, 3), 'frame 3 tak ditandai: %s', mat2str(h.me.dropSet));
% panggil langsung engine (dialog questdlg tak bisa headless) — verifikasi state.
info2 = pivanalyzemat.core.matpivEdit.dropFrames(df, h.me.dropSet, true);
assert(info2.nKept == 4, 'sisa frame salah: %d', info2.nKept);
fprintf('[ok] Tab②: tandai frame 3; dropFrames -> sisa %d\n', info2.nKept);
% muat ulang exp aktif via jalur GUI (jumlah frame berubah 5->4).
h = guidata(fig); h.me.dropSet = []; guidata(fig, h);
% reload manual seperti i_reloadActive (probe + loadExperiment)
[meta, okp] = pivanalyzemat.core.probePivMat(df);
assert(okp && meta.nFrames == 4, 'probe pasca-drop salah: %d', meta.nFrames);

% --- Tab ③: tambah kotak (DATA) + Simpan sidecar ---
h = guidata(fig);
h.me.boxes = {struct('first',[4 4 12 9], 'last',[4 4 12 9])};
h.me.activeBox = 1; h.me.maskDirty = true;
guidata(fig, h);
i_fireCb(h.me_btnSaveMask);
assert(pivanalyzemat.core.maskSidecar.has(df), 'sidecar mask GUI tak tertulis');
mg = pivanalyzemat.core.matpivEdit.readMask(df);
assert(pivanalyzemat.core.maskRect.isActive(mg) && numel(mg.boxes)==1, 'mask GUI salah');
assert(isequal(round(mg.boxes(1).rect_first), [4 4 12 9]), 'rect GUI tak konsisten');
fprintf('[ok] Tab③: tambah kotak + Simpan sidecar; readMask OK\n');

fprintf('==== SEMUA UJI MAT PIV EDITOR LULUS ====\n');
end

% =====================================================================
%  Builder MAT PIV sintetis (skema kompat probePivMat + readPivBgPair +
%  pivGeomIO + pivcore.data.buildDataset): cell PIV x/y/u/v/velmag 2D +
%  bg_images_* dedup + geom.
% =====================================================================
function i_makeSyntheticPiv(matFile, nFrames, geomXYZ)
    [X, Y] = meshgrid(1:10, 1:8);   % grid 8x10
    x = cell(nFrames,1); y = cell(nFrames,1);
    u_original = cell(nFrames,1); v_original = cell(nFrames,1); %#ok<NASGU>
    u_filtered = cell(nFrames,1); v_filtered = cell(nFrames,1); %#ok<NASGU>
    velocity_magnitude = cell(nFrames,1);
    for k = 1:nFrames
        x{k} = X; y{k} = Y;
        uu = 0.1*k*ones(8,10); vv = 0.05*k*ones(8,10);
        u_original{k} = uu; v_original{k} = vv;      %#ok<NASGU>
        u_filtered{k} = uu; v_filtered{k} = vv;      %#ok<NASGU>
        velocity_magnitude{k} = hypot(uu, vv) + 0.01*rand(8,10);
    end

    % --- latar GS tersemat: skema jpeg_dedup_v1 (blob JPEG per-bingkai) ---
    blobs = cell(nFrames,1);
    for k = 1:nFrames
        img = uint8(20 + 40*k + zeros(40, 60));   % mean naik per-bingkai
        img(5:10, 5:10) = uint8(200);
        tmp = [tempname '.jpg'];
        imwrite(img, tmp, 'jpg', 'Quality', 92);
        fid = fopen(tmp,'rb'); blobs{k} = fread(fid, Inf, '*uint8'); fclose(fid);
        delete(tmp);
    end
    bg_images_format  = 'jpeg_dedup_v1';            %#ok<NASGU>
    bg_images_blobs   = blobs;                       %#ok<NASGU>
    bg_images_index   = uint32((1:nFrames)');        %#ok<NASGU>
    bg_images_quality = 92;                           %#ok<NASGU>
    pivterry_pack     = 'vector_gs_v1';              %#ok<NASGU>

    % --- geometri + bookkeeping (dipakai dropframes) ---
    experiment_geometry = pivanalyze.geom.computeGeometry( ...
        geomXYZ(1), geomXYZ(2), geomXYZ(3), 'synthetic_test'); %#ok<NASGU>
    pivterry_geom_pack  = 'geom_strain_v1';          %#ok<NASGU>
    automasi_settings   = struct('num_pairs', nFrames); %#ok<NASGU>
    calxy = 1; units = {'px'}; %#ok<NASGU>

    save(matFile, 'velocity_magnitude', 'x', 'y', ...
        'u_original','v_original','u_filtered','v_filtered', ...
        'bg_images_format', 'bg_images_blobs', 'bg_images_index', ...
        'bg_images_quality', 'pivterry_pack', 'automasi_settings', 'calxy', 'units', ...
        'experiment_geometry', 'pivterry_geom_pack', '-v7.3');
end

% =====================================================================
%  Util test
% =====================================================================
function i_cleanBaks(df)
    for e = {'.bak','.bak2','.bak3','.bak4'}
        p = [df e{1}]; if isfile(p), delete(p); end
    end
    sp = pivanalyzemat.core.maskSidecar.path(df);
    if isfile(sp), delete(sp); end
end

function i_fireBtn(btn)
    i_fireCb(btn);
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
    try
        if isgraphics(fig)
            set(fig,'CloseRequestFcn',''); delete(fig);
        end
    catch %#ok<CTCH>
    end
end

function i_rmTmp(p)
    try, if isfolder(p), rmdir(p,'s'); end; catch, end %#ok<CTCH>
end
