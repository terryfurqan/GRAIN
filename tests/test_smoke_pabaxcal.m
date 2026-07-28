function test_smoke_pabaxcal(rootDir)
%TEST_SMOKE_PABAXCAL  Uji modul kalibrasi sumbu cm AX main (PABAXCAL) — engine +
%   applyCmAxes + WYSIWYG + GUI.
%
%   test_smoke_pabaxcal                 % default: .../RAW/PIV_2026-06-24
%   test_smoke_pabaxcal('/path/folder') % folder berisi .mat PIV (Step 2)
%
%   Memverifikasi:
%     A. Engine MURNI pivcore.io.pabAxCal — emptyDoc/write/read round-trip;
%        pxToCm<->cmToPx inverse; guard 2-titik-sama -> NaN & disabled.
%     B. applyCmAxes (headless axes offscreen) — XTick=cmToPx(tick),
%        XTickLabel, xlabel; segitiga Tag 'indenterTri' di posisi shortening;
%        disabled -> tak set tick cm.
%     C. WYSIWYG identik — drawScalarPanel(axCal enabled) ke axes GUI & figure
%        offscreen -> XTick/XTickLabel & posisi segitiga SAMA. (real data; SKIP
%        bila tak ada.)
%     D. GUI PABAXCAL — build, load exp, set 2 titik X/Y manual, Save -> sidecar
%        _axcal.json; buka ulang ter-restore. (real data; SKIP bila tak ada.)
%
%   SELALU MATLAB R2025b. SENYAP (DefaultFigureVisible off).

fprintf('==== TEST SMOKE PABAXCAL ====\n');

here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
roots = pab_setup();
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>
assert(~isempty(which('pivcore.io.pabAxCal')), 'pabAxCal tak di path.');
assert(~isempty(which('pivcore.export.frameCatalog')), '+pivcore.export tak di path.');

% =====================================================================
% A. ENGINE MURNI pabAxCal
% =====================================================================
fprintf('-- A. engine pabAxCal --\n');
tmpMat = fullfile(tempdir, sprintf('axcal_test_%s.mat', i_stamp()));
cleanMat = onCleanup(@() i_del(tmpMat));                 %#ok<NASGU>
cleanSide= onCleanup(@() i_del(pivcore.io.pabAxCal.dataPath(tmpMat))); %#ok<NASGU>

doc = pivcore.io.pabAxCal.emptyDoc(tmpMat);
assert(~doc.enabled, 'emptyDoc harus disabled');
assert(isequal(doc.x.tickCm, [0 5 10 15 20 25 30]), 'default xTick salah');
assert(isequal(doc.y.tickCm, [0 4 8]), 'default yTick salah');
assert(strcmp(doc.x.label,'Cummulative Shortening (cm)'), 'label X salah');

% Isi kalibrasi: X pixel 100->2900 == 0->30 cm; Y pixel 900->100 == 0->8 cm.
doc.enabled = true;
doc.x.p1Px = 100;  doc.x.p1Cm = 0;   doc.x.p2Px = 2900; doc.x.p2Cm = 30;
doc.y.p1Px = 900;  doc.y.p1Cm = 0;   doc.y.p2Px = 100;  doc.y.p2Cm = 8;

assert(pivcore.io.pabAxCal.isValid(doc,'x'), 'X harus valid');
assert(pivcore.io.pabAxCal.isValid(doc,'y'), 'Y harus valid');

% px<->cm inverse.
cm = pivcore.io.pabAxCal.pxToCm(doc,'x', 1500);
assert(abs(cm - 15) < 1e-9, 'pxToCm X salah: %.6f (harusnya 15)', cm);
px = pivcore.io.pabAxCal.cmToPx(doc,'x', 15);
assert(abs(px - 1500) < 1e-9, 'cmToPx X salah: %.6f (harusnya 1500)', px);
% round-trip acak.
for v = [0 3.7 10 22.5 30]
    p = pivcore.io.pabAxCal.cmToPx(doc,'x', v);
    c = pivcore.io.pabAxCal.pxToCm(doc,'x', p);
    assert(abs(c - v) < 1e-9, 'round-trip X gagal di %.3g', v);
end
cmY = pivcore.io.pabAxCal.pxToCm(doc,'y', 500);   % di tengah 900..100
assert(abs(cmY - 4) < 1e-9, 'pxToCm Y salah: %.6f (harusnya 4)', cmY);
fprintf('[ok] pxToCm/cmToPx inverse konsisten (X & Y)\n');

% Guard: 2 titik sama -> tak valid -> NaN.
bad = doc; bad.x.p2Px = bad.x.p1Px;
assert(~pivcore.io.pabAxCal.isValid(bad,'x'), 'guard 2-titik-sama gagal');
assert(isnan(pivcore.io.pabAxCal.pxToCm(bad,'x',123)), 'invalid harus NaN');
assert(isnan(pivcore.io.pabAxCal.cmToPx(bad,'x',5)), 'invalid harus NaN');
fprintf('[ok] guard 2-titik-sama -> NaN\n');

% write/read round-trip (atomic) + NaN<->null.
doc.indenter.show = true; doc.indenter.mode = 'shortening';
pivcore.io.pabAxCal.write(tmpMat, doc);
assert(isfile(pivcore.io.pabAxCal.dataPath(tmpMat)), '_axcal.json tak ditulis');
d2 = pivcore.io.pabAxCal.read(tmpMat);
assert(d2.enabled, 'enabled tak persist');
assert(abs(d2.x.p2Cm - 30) < 1e-9, 'p2Cm round-trip rusak');
assert(isequal(d2.x.tickCm, doc.x.tickCm), 'tickCm round-trip rusak');
assert(strcmp(d2.y.label, doc.y.label), 'label Y round-trip rusak');
assert(pivcore.io.pabAxCal.isValid(d2,'x') && pivcore.io.pabAxCal.isValid(d2,'y'), ...
    'validitas tak persist');
fprintf('[ok] write/read round-trip (atomic)\n');

% =====================================================================
% B. applyCmAxes (headless)
% =====================================================================
fprintf('-- B. applyCmAxes headless --\n');
f = figure('Visible','off'); cax = axes('Parent',f);
cleanFig = onCleanup(@() i_closeIf(f));                  %#ok<NASGU>
xExt = [0 3000]; yExt = [0 1000];
imagesc(cax, xExt, yExt, rand(20,60)); set(cax,'YDir','normal');
xlim(cax, xExt); ylim(cax, yExt);

% dxCm=20 cm (pemendekan total), frame 6/11 -> shortening = 5/10*20 = 10 cm.
R = struct('dxCm', 20);
nF = 11; k = 6;
pivcore.export.frameCatalog.applyCmAxes(cax, d2, R, k, nF, xExt, yExt);

xt = get(cax,'XTick');
expXt = pivcore.io.pabAxCal.cmToPx(d2,'x', d2.x.tickCm);
assert(numel(xt) == numel(expXt), 'jumlah XTick salah: %d vs %d', numel(xt), numel(expXt));
assert(max(abs(sort(xt(:)') - sort(expXt(:)'))) < 1e-6, 'XTick != cmToPx(tick)');
xl = get(get(cax,'XLabel'),'String');
assert(contains(xl,'Cummulative Shortening'), 'xlabel salah: %s', xl);
yl = get(get(cax,'YLabel'),'String');
assert(contains(yl,'Height'), 'ylabel salah: %s', yl);

tri = findobj(cax,'Tag','indenterTri');
assert(~isempty(tri), 'segitiga indenter tak digambar');
shortCm = (k-1)/(nF-1) * R.dxCm;           % = 10
xTriExp = pivcore.io.pabAxCal.cmToPx(d2,'x', shortCm);
assert(abs(get(tri(1),'XData') - xTriExp) < 1e-6, 'posisi segitiga salah');
fprintf('[ok] XTick=cmToPx(tick) + label + segitiga @ shortening=%.1f cm\n', shortCm);

% Disabled -> tak menyentuh tick (biarkan auto/pixel).
cla(cax); imagesc(cax, xExt, yExt, rand(20,60)); set(cax,'YDir','normal');
xlim(cax,xExt); ylim(cax,yExt);
dDis = d2; dDis.enabled = false;
tickBefore = get(cax,'XTick');
pivcore.export.frameCatalog.applyCmAxes(cax, dDis, R, k, nF, xExt, yExt);
assert(isequal(get(cax,'XTick'), tickBefore), 'disabled harus tak ubah tick');
assert(isempty(findobj(cax,'Tag','indenterTri')), 'disabled harus tak gambar segitiga');
fprintf('[ok] disabled -> tick/segitiga tak diubah\n');

% dxCm NaN -> segitiga di-skip (jujur), tick tetap.
cla(cax); imagesc(cax, xExt, yExt, rand(20,60)); set(cax,'YDir','normal');
xlim(cax,xExt); ylim(cax,yExt);
pivcore.export.frameCatalog.applyCmAxes(cax, d2, struct('dxCm',NaN), k, nF, xExt, yExt);
assert(~isempty(get(cax,'XTick')), 'tick cm harus tetap saat dxCm NaN');
assert(isempty(findobj(cax,'Tag','indenterTri')), 'segitiga harus skip saat dxCm NaN');
fprintf('[ok] dxCm NaN -> segitiga skip, tick cm tetap\n');

% =====================================================================
% C+D. WYSIWYG identik + GUI (real data; SKIP bila tak ada)
% =====================================================================
if nargin < 1 || isempty(rootDir)
    rootDir = fullfile(roots.data_root, 'RAW', 'PIV_2026-06-24');
end
if ~isfolder(rootDir)
    fprintf('[SKIP C+D] folder uji tak ada: %s\n', rootDir);
    fprintf('==== LULUS (A+B; C+D di-skip) ====\n'); return;
end
files = pivanalyzemat.core.scanPivMats(rootDir);
if isempty(files)
    fprintf('[SKIP C+D] tak ada .mat PIV di %s\n', rootDir);
    fprintf('==== LULUS (A+B; C+D di-skip) ====\n'); return;
end
df = files{1}; [~, base] = fileparts(df);
% snapshot sidecar existing supaya test tak merusak kalibrasi user.
sidePath = pivcore.io.pabAxCal.dataPath(df);
hadSide = isfile(sidePath); sideBak = '';
if hadSide, sideBak = [sidePath '.testbak']; copyfile(sidePath, sideBak); end
restoreSide = onCleanup(@() i_restoreSide(sidePath, sideBak, hadSide)); %#ok<NASGU>

fprintf('-- C. WYSIWYG identik (exp: %s) --\n', base);
data1 = pivcore.io.step1Session.loadFrame1(df);
Rr = pivcore.export.frameCatalog.resolveRender(df);
% Kalibrasi dari extent frame-1 (px tepi kiri->0, tepi kanan->30; bawah->0 atas->8).
xg = pivcore.data.safeFrame(data1.x,1); yg = pivcore.data.safeFrame(data1.y,1);
xe = [min(xg(:)) max(xg(:))]; ye = [min(yg(:)) max(yg(:))];
cal = pivcore.io.pabAxCal.emptyDoc(df); cal.enabled = true;
cal.x.p1Px = xe(1); cal.x.p1Cm = 0; cal.x.p2Px = xe(2); cal.x.p2Cm = 30;
cal.y.p1Px = ye(1); cal.y.p1Cm = 0; cal.y.p2Px = ye(2); cal.y.p2Cm = 8;

up = struct('scalars',{{'velmag','shear'}});
spec = pivcore.export.frameCatalog.specFromResolve(Rr, up);
cfg  = pivcore.export.frameCatalog.renderCfg(spec);
dec  = pivcore.export.frameCatalog.decOptsFromSpec(spec, struct());
dec.axCal = cal;
kk = min(3, max(1, Rr.nFrames));

fG = figure('Visible','off'); axG = axes('Parent',fG);
fE = figure('Visible','off'); axE = axes('Parent',fE);
cleanG = onCleanup(@() i_closeIf(fG)); cleanE = onCleanup(@() i_closeIf(fE)); %#ok<NASGU>
pivcore.export.frameCatalog.drawScalarPanel(axG, data1, kk, 'velmag', cfg, Rr, base, dec);
pivcore.export.frameCatalog.drawScalarPanel(axE, data1, kk, 'velmag', cfg, Rr, base, dec);
xtG = get(axG,'XTick'); xtE = get(axE,'XTick');
assert(isequal(size(xtG),size(xtE)) && max(abs(xtG-xtE))<1e-9, 'XTick preview != export');
triG = findobj(axG,'Tag','indenterTri'); triE = findobj(axE,'Tag','indenterTri');
if isfinite(Rr.dxCm)
    assert(~isempty(triG) && ~isempty(triE), 'segitiga hilang di salah satu render');
    assert(abs(get(triG(1),'XData')-get(triE(1),'XData'))<1e-9, 'posisi segitiga beda preview/export');
    fprintf('[ok] WYSIWYG: XTick & segitiga preview == export (dxCm=%.4g)\n', Rr.dxCm);
else
    fprintf('[ok] WYSIWYG: XTick preview == export (dxCm NaN -> tanpa segitiga)\n');
end

fprintf('-- D. GUI PABAXCAL --\n');
before = findall(0,'Type','figure');
PABAXCAL(rootDir);
after = findall(0,'Type','figure');
figA = [];
for ff = setdiff(after, before)'
    if contains(char(get(ff,'Name')),'PABAXCAL'), figA = ff; break; end
end
assert(~isempty(figA) && ishghandle(figA), 'figure PABAXCAL tak terbuat');
cleanA = onCleanup(@() i_closeIf(figA));                 %#ok<NASGU>
hA = guidata(figA);
% muat exp pertama.
i_fireSelect(figA, 1);
hA = guidata(figA);
assert(~isempty(hA.data), 'data exp tak termuat di GUI');
% set 2 titik X & Y manual + aktif, lalu Save.
set(hA.edX1Px,'String',num2str(xe(1))); set(hA.edX1Cm,'String','0');
set(hA.edX2Px,'String',num2str(xe(2))); set(hA.edX2Cm,'String','30');
set(hA.edY1Px,'String',num2str(ye(1))); set(hA.edY1Cm,'String','0');
set(hA.edY2Px,'String',num2str(ye(2))); set(hA.edY2Cm,'String','8');
set(hA.chkEnabled,'Value',1);
i_fireCb(hA_saveBtn(figA));   % klik Save
% verifikasi sidecar ditulis + valid.
saved = pivcore.io.pabAxCal.read(df);
assert(saved.enabled, 'GUI Save: enabled tak tersimpan');
assert(pivcore.io.pabAxCal.isValid(saved,'x'), 'GUI Save: X tak valid');
assert(pivcore.io.pabAxCal.isValid(saved,'y'), 'GUI Save: Y tak valid');
assert(abs(pivcore.io.pabAxCal.pxToCm(saved,'x', xe(2)) - 30) < 1e-6, 'GUI Save: skala X salah');
fprintf('[ok] GUI: load + set 2 titik + Save -> _axcal.json valid\n');

fprintf('==== LULUS (A+B+C+D) ====\n');
end


% ------------------------------------------------------------------
function i_fireSelect(fig, row)
    h = guidata(fig);
    e = struct('Indices',[row 1]);
    cb = get(h.tbl,'CellSelectionCallback');
    if ~isempty(cb), cb(h.tbl, e); end
end

function b = hA_saveBtn(fig)
%HA_SAVEBTN  Cari tombol "Simpan (_axcal.json)" di GUI.
    b = [];
    btns = findall(fig,'Style','pushbutton');
    for x = btns(:).'
        if contains(char(get(x,'String')),'Simpan (_axcal'), b = x; return; end
    end
end

function i_fireCb(hobj)
    if isempty(hobj) || ~ishghandle(hobj), return; end
    cb = get(hobj,'Callback');
    if ~isempty(cb), cb(hobj, struct()); end
end

function s = i_stamp()
    c = clock; s = sprintf('%02d%02d%02d_%02d%02d%02.0f', ...
        mod(c(1),100),c(2),c(3),c(4),c(5),c(6));
end

function i_del(p)
    try, if ischar(p) && isfile(p), delete(p); end, catch, end
end

function i_closeIf(f)
    try, if ~isempty(f) && ishghandle(f), delete(f); end, catch, end
end

function i_restoreSide(sidePath, sideBak, hadSide)
    try
        if hadSide && ~isempty(sideBak) && isfile(sideBak)
            movefile(sideBak, sidePath, 'f');
        elseif ~hadSide && isfile(sidePath)
            delete(sidePath);   % test membuatnya; bersihkan
        end
    catch
    end
end
