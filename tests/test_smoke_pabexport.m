function test_smoke_pabexport(rootDir)
%TEST_SMOKE_PABEXPORT  Uji PAB Exporter (katalog gambar AX main) — engine + GUI.
%
%   test_smoke_pabexport                 % default: .../RAW/PIV_2026-06-24
%   test_smoke_pabexport('/path/folder') % folder berisi .mat PIV (Step 2)
%
%   Memverifikasi:
%     A. Engine MURNI pivcore.io.pabExportCatalog — naming, spec/fingerprint,
%        manifest round-trip, deteksi BASI, indeks global, purge.
%     B. Engine HEADLESS pivcore.export.frameCatalog — resolveRender (garis PSG
%        + CLim) & renderExperiment (JPEG semua bingkai 1 exp ke folder TMP).
%     C. GUI PABEXPORT — build, rescan tabel, centang, render via callback,
%        status katalog, deteksi BASI, purge & regenerate.
%
%   Render KE FOLDER TMP (bukan PAB_export/ asli) supaya tak mengotori repo.
%   SELALU MATLAB R2025b. SENYAP (DefaultFigureVisible off).

fprintf('==== TEST SMOKE PAB EXPORTER ====\n');

here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
roots = pab_setup();
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>
assert(~isempty(which('pivcore.export.frameCatalog')), '+pivcore.export tak di path.');
assert(~isempty(which('pivcore.io.pabExportCatalog')), 'pabExportCatalog tak di path.');

if nargin < 1 || isempty(rootDir)
    rootDir = fullfile(roots.data_root, 'RAW', 'PIV_2026-06-24');
end
if ~isfolder(rootDir)
    fprintf('[SKIP] folder uji tak ada: %s\n', rootDir);
    fprintf('       beri arg folder berisi .mat PIV (output Step 2).\n');
    return;
end
files = pivanalyzemat.core.scanPivMats(rootDir);
if isempty(files)
    fprintf('[SKIP] tak ada .mat PIV di %s\n', rootDir); return;
end
df = files{1};
[~, base] = fileparts(df);
fprintf('[ok] folder: %s (%d .mat); exp uji: %s\n', rootDir, numel(files), base);

% Folder katalog TMP (dibersihkan di akhir).
tmpRoot = fullfile(tempdir, sprintf('pabexport_test_%s', i_stamp()));
if isfolder(tmpRoot), rmdir(tmpRoot,'s'); end
mkdir(tmpRoot);
cleanTmp = onCleanup(@() i_rmTmp(tmpRoot));

% =====================================================================
% A. ENGINE KATALOG (murni)
% =====================================================================
fprintf('-- A. engine katalog --\n');
cat = @pivcore.io.pabExportCatalog;

% Naming deterministik.
fn1 = pivcore.io.pabExportCatalog.frameFile(df, 'velmag', 1);
fn2 = pivcore.io.pabExportCatalog.frameFile(df, 'shear', 12);
assert(contains(fn1,'_velmag_f001.jpg'), 'nama velmag salah: %s', fn1);
assert(contains(fn2,'_shear_f012.jpg'), 'nama shear salah: %s', fn2);
assert(strcmp(pivcore.io.pabExportCatalog.scalarKey('velocity_magnitude'),'velmag'));
assert(strcmp(pivcore.io.pabExportCatalog.scalarKey('shear strain'),'shear'));
fprintf('[ok] penamaan: %s | %s\n', fn1, fn2);

% Spec + fingerprint deterministik & sensitif.
spec1 = pivcore.io.pabExportCatalog.specStruct(struct('climVel',[0 5],'psgP1',[1 100],'psgP2',[200 100]));
spec1b = pivcore.io.pabExportCatalog.specStruct(struct('climVel',[0 5],'psgP1',[1 100],'psgP2',[200 100]));
assert(strcmp(spec1.fingerprint, spec1b.fingerprint), 'fingerprint tak deterministik');
spec2 = pivcore.io.pabExportCatalog.specStruct(struct('climVel',[0 6],'psgP1',[1 100],'psgP2',[200 100]));
assert(~strcmp(spec1.fingerprint, spec2.fingerprint), 'fingerprint tak peka CLim');
% urutan skalar invarian:
sA = pivcore.io.pabExportCatalog.specStruct(struct('scalars',{{'velmag','shear'}}));
sB = pivcore.io.pabExportCatalog.specStruct(struct('scalars',{{'shear','velmag'}}));
assert(strcmp(sA.fingerprint, sB.fingerprint), 'fingerprint harus invarian urutan skalar');
fprintf('[ok] fingerprint: deterministik + peka CLim + invarian urutan skalar\n');

% Manifest round-trip + indeks + purge.
m = pivcore.io.pabExportCatalog.emptyManifest(df, 10);
m.producedAt = '2026-06-27 00:00'; m.dpi = 200; m.spec = spec1;
m.scalars.velmag = struct('dir','velmag','count',10,'files',{{'a.jpg'}});
pivcore.io.pabExportCatalog.write(tmpRoot, df, m);
mp = pivcore.io.pabExportCatalog.manifestPath(tmpRoot, df);
assert(isfile(mp), 'manifest.json tak ditulis');
m2 = pivcore.io.pabExportCatalog.read(tmpRoot, df);
assert(strcmp(m2.spec.fingerprint, spec1.fingerprint), 'manifest round-trip fingerprint rusak');
assert(pivcore.io.pabExportCatalog.scalCount(m2.scalars.velmag) == 10, 'count rusak');
% BASI: spec live beda -> stale.
assert(pivcore.io.pabExportCatalog.isStale(m2, spec2), 'BASI tak terdeteksi saat spec beda');
assert(~pivcore.io.pabExportCatalog.isStale(m2, spec1), 'salah-positif BASI saat spec sama');
pivcore.io.pabExportCatalog.rebuildIndex(tmpRoot);
assert(isfile(pivcore.io.pabExportCatalog.catalogPath(tmpRoot)), '_catalog.json tak ditulis');
pivcore.io.pabExportCatalog.purgeExp(tmpRoot, df);
assert(~isfolder(pivcore.io.pabExportCatalog.expDir(tmpRoot, df)), 'purge tak menghapus folder');
fprintf('[ok] manifest round-trip + BASI + indeks + purge\n');

% =====================================================================
% B. ENGINE RENDER (headless)
% =====================================================================
fprintf('-- B. engine render headless --\n');
R = pivcore.export.frameCatalog.resolveRender(df);
assert(~isempty(R.line) && isfield(R.line,'p1') && isfield(R.line,'p2'), 'garis PSG tak teresolve');
assert(ismember(R.psgSource, {'potdata','autopot','auto'}), 'psgSource tak valid: %s', R.psgSource);
assert(R.nFrames >= 1, 'nFrames tak valid');
assert(numel(R.climVel)==2 && R.climVel(2) > R.climVel(1), 'climVel tak valid');
fprintf('[ok] resolveRender: psg=%s, nF=%d, climVel=[%.2f %.2f], indMax=%.3f\n', ...
    R.psgSource, R.nFrames, R.climVel(1), R.climVel(2), R.indenterMax);

% Render exp PERTAMA penuh (semua bingkai) ke TMP — velmag saja agar cepat.
nSeen = [0 0];
prog = @(k,n,sc) assignin('base','dummy',0); %#ok<NASGU>
opts = struct('dpi',96, 'jpegQuality',85, ...
    'userPrefs',struct('scalars',{{'velmag'}}), ...
    'producedAt','2026-06-27 00:00', 'purge',true, 'resolve',R);
manR = pivcore.export.frameCatalog.renderExperiment(tmpRoot, df, opts);
vdir = pivcore.io.pabExportCatalog.scalarDir(tmpRoot, df, 'velmag');
jpgs = dir(fullfile(vdir,'*.jpg'));
assert(numel(jpgs) == R.nFrames, 'jumlah JPEG (%d) != nFrames (%d)', numel(jpgs), R.nFrames);
% berkas bingkai-1 ada & berukuran > 0.
f1 = fullfile(vdir, pivcore.io.pabExportCatalog.frameFile(df,'velmag',1));
assert(isfile(f1), 'JPEG bingkai-1 tak ada'); d1 = dir(f1); assert(d1.bytes > 0, 'JPEG kosong');
assert(pivcore.io.pabExportCatalog.scalCount(manR.scalars.velmag) == R.nFrames, 'manifest count salah');
% shear TIDAK dirender (userPrefs cuma velmag).
assert(~isfield(manR.scalars,'shear'), 'shear seharusnya tak dirender');
fprintf('[ok] render %d JPEG velmag (bingkai-1 %d byte) + manifest\n', numel(jpgs), d1.bytes);

% =====================================================================
% C. GUI PABEXPORT — WYSIWYG (kanvas + slider + export di akhir)
% =====================================================================
fprintf('-- C. GUI PABEXPORT (WYSIWYG) --\n');
% Reset pref global supaya tes deterministik (tak terpengaruh default tersimpan).
prefSnap = i_snapPref();
cleanPref = onCleanup(@() i_restorePref(prefSnap));
if ispref('PABEXPORT','global'), rmpref('PABEXPORT','global'); end

% Buka dgn pabRoot=TMP (jangan sentuh PAB_export/ asli + progress sesi nyata).
PABEXPORT(rootDir, tmpRoot);
figs = findall(0,'Type','figure','-and','-regexp','Name','PAB Exporter');
assert(~isempty(figs), 'figure PAB Exporter tak terbuka');
fig = figs(end);
cleanFig = onCleanup(@() i_closeFig(fig));
h = guidata(fig);
% Setel render cepat lewat KONTROL (sumber kebenaran i_onPrefs): dpi 96,
% velmag saja. Picu i_onPrefs supaya h.g ikut + status katalog dihitung di TMP.
set(h.edDPI,'String','96'); set(h.edJQ,'String','85');
set(h.chkShear,'Value',0); set(h.chkVel,'Value',1);
i_fireCb(h.chkVel);   % -> i_onPrefs
h = guidata(fig);
assert(h.g.dpi == 96 && ~h.g.doShear, 'global tak terupdate dari kontrol');
assert(~isempty(h.list), 'tabel eksperimen GUI kosong');
fprintf('[ok] GUI build + %d exp di tabel\n', numel(h.list));

% --- WYSIWYG: klik baris-1 -> i_loadExperiment -> kanvas terisi ---
i_fireCellSel(h.tbl, [1 1]);
h = guidata(fig);
assert(~isempty(h.data), 'exp tak termuat ke kanvas (h.data kosong)');
assert(~isempty(h.resolve), 'resolve exp kosong');
assert(h.activeRow == 1, 'activeRow harus 1 setelah klik baris-1');
% Kanvas (axes) harus punya konten (image dari renderScalarPanel).
kids = get(h.ax, 'Children');
assert(~isempty(kids), 'kanvas KOSONG setelah load (WYSIWYG gagal)');
fprintf('[ok] WYSIWYG: klik baris-1 -> kanvas terisi (%d objek grafik), PSG=%s\n', ...
    numel(kids), h.resolve.psgSource);

% --- spinner ukuran kanvas ▲/▼ (klik langsung ubah + re-render) ---
w0 = h.g.widthCm; h0 = h.g.heightCm;
i_fireCb(h.btnWup); i_fireCb(h.btnHdn);
h = guidata(fig);
assert(h.g.widthCm == w0+1, 'spinner lebar ▲ gagal (%g != %g)', h.g.widthCm, w0+1);
assert(h.g.heightCm == h0-1, 'spinner tinggi ▼ gagal (%g != %g)', h.g.heightCm, h0-1);
assert(~isempty(get(h.ax,'Children')), 'kanvas kosong setelah spinner');
fprintf('[ok] spinner kanvas: lebar %g→%g, tinggi %g→%g (re-render OK)\n', ...
    w0, h.g.widthCm, h0, h.g.heightCm);

% --- toggle skalar velmag<->shear + geser slider (frame) ---
set(h.btnScalar,'Value',1); i_fireCb(h.btnScalar);
h = guidata(fig); assert(strcmp(h.scalar,'shear'), 'toggle skalar gagal');
midF = max(1, round(h.nF/2));
set(h.sldFrame,'Value',midF); i_fireCb(h.sldFrame);
h = guidata(fig); assert(h.frame == midF, 'slider frame tak update (%d != %d)', h.frame, midF);
assert(h.fullLoaded, 'geser slider>1 harus memuat semua bingkai');
% balik ke velmag utk ekspor cepat.
set(h.btnScalar,'Value',0); i_fireCb(h.btnScalar);
fprintf('[ok] toggle skalar + slider frame (f%d, full-loaded)\n', midF);

% --- EXPORT exp aktif (tombol di akhir) ---
i_fireCb(h.btnExport);
h = guidata(fig);
assert(~h.busy, 'GUI masih busy setelah export');
assert(contains(h.list(1).status,'OK'), 'status exp-1 bukan OK: %s', h.list(1).status);
assert(h.list(1).count(1) == h.resolve.nFrames, 'hitung velmag GUI salah');
% berkas JPEG benar-benar ditulis ke TMP.
gv = pivcore.io.pabExportCatalog.scalarDir(tmpRoot, h.list(1).file, 'velmag');
assert(numel(dir(fullfile(gv,'*.jpg'))) == h.resolve.nFrames, 'JPEG GUI tak lengkap');
fprintf('[ok] EXPORT exp aktif: status="%s", velmag=%d JPEG\n', h.list(1).status, h.list(1).count(1));

% --- ubah preferensi (tambah shear) -> exp-1 jadi BASI ---
set(h.chkShear,'Value',1); i_fireCb(h.chkShear);
h = guidata(fig);
assert(contains(h.list(1).status,'BASI'), 'status tak jadi BASI: %s', h.list(1).status);
fprintf('[ok] deteksi ⚠BASI saat preferensi render berubah\n');

% =====================================================================
% E. KONTROL BARU: glyph, tickmark, cm/s, caption strain, save cfg/progress
% =====================================================================
fprintf('-- E. kontrol baru --\n');
% Glyph tebal/spacing -> h.g + re-render.
set(h.edGlyphLW,'String','2.2'); set(h.edGlyphSp,'String','5'); i_fireCb(h.edGlyphLW);
h = guidata(fig);
assert(abs(h.g.glyphLW-2.2)<1e-9 && h.g.glyphSp==5, 'glyph tebal/spacing tak terbaca');
% Tickmark OFF -> XTick kanvas kosong.
set(h.chkTick,'Value',0); i_fireCb(h.chkTick);
h = guidata(fig);
assert(~h.g.tickPx, 'tickPx tak OFF');
assert(isempty(get(h.ax,'XTick')), 'tickmark masih ada setelah OFF');
set(h.chkTick,'Value',1); i_fireCb(h.chkTick);
% Warna glyph shear (set langsung via state karena uisetcolor di-skip saat quiet).
h = guidata(fig); h.g.glyphColorShear = [1 0 0]; guidata(fig,h);
i_fireCb(h.chkGS); i_fireCb(h.chkGS);   % picu i_onPrefs -> i_apply (re-render)
% cm/s: isi cm/px + dt -> auto multiplier; aktifkan unit cms.
set(h.edCmPx,'String','0.05'); set(h.edDt,'String','0.5'); set(h.edMult,'String','');
set(h.chkCms,'Value',1); i_fireCb(h.chkCms);
h = guidata(fig);
assert(strcmp(h.g.velUnit,'cms'), 'velUnit tak cms');
assert(abs(h.g.velMult - 0.1) < 1e-9, 'auto multiplier salah (%.4g != 0.1)', h.g.velMult);
fprintf('[ok] glyph LW/Sp, tickmark toggle, glyph shear, cm/s auto-mult=%.4g\n', h.g.velMult);
% Caption strain: posisi + ada teks di kanvas (Tag strainCaption).
set(h.chkStrain,'Value',1); set(h.edStrainX,'String','0.10'); set(h.edStrainY,'String','0.08');
i_fireCb(h.chkStrain);
h = guidata(fig);
assert(abs(h.g.strainPosX-0.10)<1e-9 && abs(h.g.strainPosY-0.08)<1e-9, 'posisi caption salah');
assert(~isempty(findall(h.ax,'Tag','strainCaption')), 'caption strain tak digambar');
fprintf('[ok] caption strain digambar di posisi (%.2f,%.2f)\n', h.g.strainPosX, h.g.strainPosY);
% Spinner caption ±0.01.
xb = h.g.strainPosX;
i_fireCb(h.btnSXup); h = guidata(fig);
assert(abs(h.g.strainPosX - (xb+0.01)) < 1e-9, 'spinner caption x ▲ gagal');
% Warna caption teks (set state, uisetcolor di-skip saat quiet).
h.g.strainColor = [1 0 0]; h.g.strainBg = [0 0 0]; guidata(fig,h);
i_fireCb(h.chkStrain); i_fireCb(h.chkStrain);
fprintf('[ok] spinner caption x +0.01 + warna teks/latar\n');
% Opsi multiplier (sumber): geometri X0/X1+dt -> velMultGeom (bila tersedia).
R = h.resolve;
assert(isfield(R,'velMultGeom') && isfield(R,'dxCm'), 'resolve tak punya velMultGeom/dxCm');
if isfinite(R.velMultGeom)
    set(h.popMultSrc,'Value',3); i_fireCb(h.popMultSrc);   % i_onMultSource -> autoMult
    h = guidata(fig);
    assert(strcmp(h.g.multSource,'geom'), 'multSource tak geom');
    assert(abs(h.g.velMult - R.velMultGeom) < 1e-6, 'velMult opsi-3 != velMultGeom');
    fprintf('[ok] opsi-3 geometri: velMult=%.5g (dx=%.3gcm)\n', h.g.velMult, R.dxCm);
else
    fprintf('[ok] opsi-3 geometri: velMultGeom NaN (dt/EXIF tak ada) — jalur jujur\n');
end
% kembali ke manual cm/s biar export bawah konsisten.
set(h.popMultSrc,'Value',1); i_fireCb(h.popMultSrc);
set(h.edCmPx,'String','0.05'); set(h.edDt,'String','0.5'); set(h.edMult,'String','0.1');
set(h.chkCms,'Value',1); i_fireCb(h.chkCms);
% Test 1 frame -> _preview (tak isi katalog).
i_fireCb(h.btnTest1);
pdir = pivcore.io.pabExportCatalog.previewDir(h.pabRoot);
assert(isfolder(pdir) && ~isempty(dir(fullfile(pdir,'*.jpg'))), 'test frame tak ditulis ke _preview');
% _preview TIDAK mengubah manifest exp aktif (tetap katalog terpisah).
fprintf('[ok] Test 1 frame -> _preview (%d JPG)\n', numel(dir(fullfile(pdir,'*.jpg'))));
% Ekspor frame ini -> _frame/ (2 berkas NYATA: velmag + shear), tak isi katalog.
i_fireCb(h.btnFrame2);
fdir = pivcore.io.pabExportCatalog.frameDir(h.pabRoot, h.realData);
hh = guidata(fig);
vFn = pivcore.io.pabExportCatalog.frameFile(hh.realData,'velmag',hh.frame,'jpg');
sFn = pivcore.io.pabExportCatalog.frameFile(hh.realData,'shear', hh.frame,'jpg');
assert(isfile(fullfile(fdir,vFn)), 'ekspor frame ini: velmag tak ditulis');
assert(isfile(fullfile(fdir,sFn)), 'ekspor frame ini: shear tak ditulis');
fprintf('[ok] Ekspor frame ini -> _frame/ (velmag + shear, f%d)\n', hh.frame);
% Save setelan per-exp -> sidecar _exportcfg.json.
i_fireCb(h.btnSave);
cfgPath = pivcore.io.pabExportCatalog.cfgPath(h.realData);
assert(isfile(cfgPath), 'sidecar _exportcfg.json tak ditulis');
cfgR = pivcore.io.pabExportCatalog.readCfg(h.realData);
assert(isfield(cfgR,'global') && strcmp(cfgR.global.velUnit,'cms'), 'sidecar tak simpan velUnit');
fprintf('[ok] Save setelan exp -> %s\n', i_baseN(cfgPath));
% Save Progress -> _export_progress.json (centang exp-1).
h = guidata(fig); h.list(1).sel = true; guidata(fig,h);
i_fireCb(h.btnSaveProg);
ppath = pivcore.io.pabExportCatalog.progressPath(h.pabRoot);
assert(isfile(ppath), '_export_progress.json tak ditulis');
prog = pivcore.io.pabExportCatalog.readProgress(h.pabRoot);
assert(isfield(prog,'selected') && ~isempty(prog.selected), 'progress tak simpan centang');
fprintf('[ok] Save Progress -> %d exp tercentang\n', numel(prog.selected));
% Bersihkan sidecar uji (jangan kotori RAW asli).
try, if isfile(cfgPath), delete(cfgPath); end, catch, end

% =====================================================================
% D. SETELAN GLOBAL ke FILE (lintas-sesi via setpref) — non-destruktif
% =====================================================================
fprintf('-- D. setelan global -> file --\n');
% Set DPI khas lalu "Jadikan default".
set(h.edDPI,'String','222'); i_fireCb(h.edDPI);   % i_onPrefs -> readControlsToGlobal
i_fireByString(fig, '⭐ Jadikan default');
assert(ispref('PABEXPORT','global'), 'pref global tak tersimpan');
pg = getpref('PABEXPORT','global');
assert(pg.dpi == 222, 'DPI default tersimpan salah: %d', pg.dpi);
fprintf('[ok] setpref global: dpi=%d tersimpan ke file\n', pg.dpi);
% Tutup & buka ulang -> default (pref global) ter-load. Hapus progress sesi dulu
% (progress LEBIH spesifik dari pref global & akan menimpanya — sengaja; di sini
% kita uji jalur pref global murni).
delete(fig);
try, delete(ppath); catch, end
PABEXPORT(rootDir, tmpRoot);   % tmpRoot progress sudah dihapus -> pref global murni
figs2 = findall(0,'Type','figure','-and','-regexp','Name','PAB Exporter');
fig2 = figs2(end); cleanFig2 = onCleanup(@() i_closeFig(fig2));
h2 = guidata(fig2);
assert(h2.g.dpi == 222, 'default dpi tak ter-load saat buka ulang: %d', h2.g.dpi);
fprintf('[ok] buka ulang -> default dpi=%d ter-restore dari file\n', h2.g.dpi);

fprintf('==== SEMUA LULUS ====\n');
end

% =====================================================================
% Helper picu kontrol GUI nyata
% =====================================================================
function i_fireCb(c)
    if ishghandle(c) && isprop(c,'Callback') && ~isempty(get(c,'Callback'))
        cb = get(c,'Callback'); cb(c, struct());
    end
end

function i_fireCellSel(tbl, idx)
%I_FIRECELLSEL  Picu CellSelectionCallback tabel dgn event ber-Indices.
    if ishghandle(tbl) && isprop(tbl,'CellSelectionCallback') ...
            && ~isempty(get(tbl,'CellSelectionCallback'))
        cb = get(tbl,'CellSelectionCallback');
        cb(tbl, struct('Indices', idx));
    end
end

function i_fireByString(fig, str)
%I_FIREBYSTRING  Cari pushbutton ber-String tertentu di figure & picu callback.
    btns = findall(fig, 'Type','uicontrol', 'Style','pushbutton');
    for i = 1:numel(btns)
        if strcmp(get(btns(i),'String'), str), i_fireCb(btns(i)); return; end
    end
    error('tombol "%s" tak ditemukan', str);
end

function s = i_baseN(p), [~,b,e] = fileparts(p); s = [b e]; end

function pf = i_snapPref()
    pf = [];
    if ispref('PABEXPORT','global'), pf = getpref('PABEXPORT','global'); end
end

function i_restorePref(pf)
    try
        if isempty(pf)
            if ispref('PABEXPORT','global'), rmpref('PABEXPORT','global'); end
        else
            setpref('PABEXPORT','global', pf);
        end
    catch
    end
end

function s = i_stamp()
    s = sprintf('%05d', mod(round(cputime*1000), 100000));
end

function i_rmTmp(p)
    if isfolder(p), try, rmdir(p,'s'); catch, end, end
end

function i_closeFig(fig)
    try
        h = guidata(fig);
        if isstruct(h) && isfield(h,'busy'), h.busy = false; guidata(fig,h); end
        if ishghandle(fig), delete(fig); end
    catch
    end
end
