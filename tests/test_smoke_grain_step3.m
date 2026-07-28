function test_smoke_grain_step3(rootDir)
%TEST_SMOKE_GRAINSA_STEP3  Uji headless GRAINSA3 (pratinjau output Step 2) — GUI nyata.
%
%   test_smoke_grain_step3                 % default: .../RAW_bat/PIV_2026-06-23
%   test_smoke_grain_step3('/path/folder') % folder berisi .mat PIV (PIV_<tgl>/)
%
%   GRAINSA3 (PAB_step_3) READ-ONLY: axMain (skalar+GS) + axPOT (POT on-the-fly).
%   Tes ini MEMBANGUN GUI sungguhan lalu MENJALANKAN callback-nya secara
%   terprogram (tanpa interaksi mouse) memakai data output Step 2 yang nyata:
%     1. setup path GRAIN_SA
%     2. PAB_step_3(folder) -> figure ke-build, tabel terisi
%     3. pilih eksperimen (i_loadExperiment lewat CellSelection)
%     4. tukar Vel mag <-> Shear, Auto CLim, render axMain
%     5. Muat semua bingkai + geser slider frame (i_onFrameSlider)
%     6. set garis PSG terprogram -> i_collectPOT (POT on-the-fly) -> axPOT
%     7. klik kurva + klik axPOT (pindah frame) + skala-V
%   Semua dijalankan via guidata + feval handler internal; bila ada bug skalar/
%   property, callback akan error -> tes GAGAL.
%
%   SELALU MATLAB R2025b.

fprintf('==== TEST SMOKE GRAINSA3 (PAB_step_3) — GUI nyata ====\n');

here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));  % +root (grain_setup, GRAIN*) sejak tests/ dipisah
roots = grain_setup();
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP: jendela tak rebut fokus
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>
assert(~isempty(which('pivcore.pot.step1Collect')), '+pivcore tidak di path.');

if nargin < 1 || isempty(rootDir)
    rootDir = fullfile(roots.data_root, 'RAW', 'PIV_2026-06-24');
end
assert(isfolder(rootDir), 'Folder tak ada: %s', rootDir);
fprintf('[ok] folder: %s\n', rootDir);

% --- 1) Build GUI (tanpa dialog: kirim rootDir langsung) ---
GRAIN3(rootDir);
figs = findall(0,'Type','figure','-and','-regexp','Name','GRAINSA3');
assert(~isempty(figs), 'figure GRAINSA3 tak terbuka');
fig = figs(1);
cleaner = onCleanup(@() i_closeFig(fig));
h = guidata(fig);
assert(~isempty(h.list), 'tabel eksperimen kosong (tak ada .mat PIV terdeteksi)');
fprintf('[ok] GUI build + %d berkas PIV di tabel\n', numel(h.list));

% --- 2) Pilih eksperimen pertama (simulasi CellSelectionCallback) ---
evt = struct('Indices',[1 1]);
i_invokeCellSel(fig, evt);
h = guidata(fig);
assert(~isempty(h.data), 'eksperimen tak termuat (h.data kosong)');
assert(isscalar(h.imgFrames) && isscalar(h.frame) && isscalar(h.nF), ...
    'imgFrames/frame/nF harus skalar');
fprintf('[ok] muat exp: %s (imgFrames=%d, nF=%d)\n', ...
    i_bn(h.realData), h.imgFrames, h.nF);

% --- 2b) AUTO PSG: garis + POT harus terbentuk OTOMATIS saat exp dimuat ---
assert(~isempty(h.line), 'garis PSG OTOMATIS tak terbentuk saat muat exp');
assert(isfield(h.line,'p1') && isfield(h.line,'p2'), 'struct garis PSG cacat');
assert(abs(h.line.p1(2) - h.line.p2(2)) < 1e-6, 'garis PSG otomatis harus horizontal');
assert(h.fullLoaded, 'auto-PSG harus memuat SEMUA bingkai');
assert(~isempty(h.recs), 'POT otomatis kosong setelah muat exp');
assert(~isempty(h.indenter) && any(isfinite(h.indenter)), 'indenter otomatis kosong');
% ROI interaktif (images.roi.Line, draggable) harus terbentuk — bukan garis statis.
assert(~isempty(h.roi) && isvalid(h.roi), 'ROI garis PSG interaktif tak terbentuk');
assert(isa(h.roi,'images.roi.Line'), 'h.roi harus images.roi.Line (draggable)');
assert(isequal(size(h.roi.Position),[2 2]), 'Position ROI harus 2x2');
fprintf('[ok] AUTO PSG: ROI draggable horizontal y=%.2f, %d titik POT otomatis\n', ...
    h.line.p1(2), numel(h.recs));

% --- 2c) CLim Vel mag atas = maks indenter dibulat KE ATAS kelipatan 0.5 ---
mxInd = max(h.indenter(isfinite(h.indenter)));
expHi = ceil(mxInd / 0.5) * 0.5;
assert(abs(h.climVel(2) - expHi) < 1e-9, ...
    sprintf('CLim atas %.3g != ceil(maks indenter %.3g, 0.5)=%.3g', ...
        h.climVel(2), mxInd, expHi));
assert(h.climVel(1) == 0, 'CLim bawah Vel mag harus 0');
assert(h.climVel(2) >= mxInd, 'CLim atas harus >= maks indenter (pembulatan KE ATAS)');
% Verifikasi aturan pembulatan dgn contoh user (3.3->3.5, 4.7->5.0).
assert(ceil(3.3/0.5)*0.5 == 3.5 && ceil(4.7/0.5)*0.5 == 5.0, 'aturan bulat 0.5 salah');
fprintf('[ok] CLim Vel mag dari indenter: maks=%.3g -> atas=%.2g (bulat 0.5)\n', ...
    mxInd, h.climVel(2));

% --- 3) axMain: shear <-> vel + Auto CLim (callback tombol) ---
set(h.btnDisp,'Value',1); i_fire(h.btnDisp);          % -> shear
set(h.btnDisp,'Value',0); i_fire(h.btnDisp);          % -> vel mag
i_fireByTip(fig,'batas atas = maks kurva indenter');  % Auto CLim (indenter)
fprintf('[ok] axMain: toggle skalar + Auto CLim tanpa error\n');

% --- 3b) Default: glyph ON (LW & sp = glyphDefaults) + CLAHE ON + auto-adjust ON ---
gD = pivcore.util.glyphDefaults();
h = guidata(fig);
assert(h.glyphOn, 'glyph harus ON by default');
assert(abs(h.glyphLW - gD.lineWidth) < 1e-9, 'glyph LW default harus = glyphDefaults (%.3g)', gD.lineWidth);
assert(h.glyphSp == gD.spacing, 'glyph spacing default harus = glyphDefaults (%d)', gD.spacing);
assert(h.claheOn, 'CLAHE harus ON by default');
assert(h.adjOn, 'auto kontras+brightness harus ON by default');
gl = findobj(h.axMain,'Tag','velGlyph');
assert(~isempty(gl), 'glyph (quiver) tak tergambar di axMain saat ON');
fprintf('[ok] default: glyph ON (LW=%.1f sp=%d) + CLAHE ON + auto-adjust ON, quiver tergambar\n', ...
    h.glyphLW, h.glyphSp);
% Toggle glyph OFF -> quiver hilang; lalu ON lagi.
set(h.chkGlyph,'Value',0); i_fire(h.chkGlyph); h = guidata(fig);
assert(~h.glyphOn && isempty(findobj(h.axMain,'Tag','velGlyph')), 'glyph OFF gagal');
set(h.chkGlyph,'Value',1); i_fire(h.chkGlyph); h = guidata(fig);
assert(h.glyphOn && ~isempty(findobj(h.axMain,'Tag','velGlyph')), 'glyph ON-lagi gagal');
% Toggle CLAHE & auto-adjust OFF lalu ON (lewat callback GS).
set(h.chkCLAHE,'Value',0); set(h.chkAdj,'Value',0); i_fire(h.chkGS); h = guidata(fig);
assert(~h.claheOn && ~h.adjOn, 'CLAHE/adjust OFF gagal');
set(h.chkCLAHE,'Value',1); set(h.chkAdj,'Value',1); i_fire(h.chkGS); h = guidata(fig);
assert(h.claheOn && h.adjOn, 'CLAHE/adjust ON-lagi gagal');
fprintf('[ok] toggle glyph/CLAHE/auto-adjust ON<->OFF tanpa error\n');

% --- 3c) Vel mag colormap = JET (bukan parula) ---
cm = colormap(h.axMain);
jt = jet(size(cm,1));
assert(max(abs(cm(:)-jt(:))) < 1e-6, 'colormap vel mag harus JET');
fprintf('[ok] colormap Vel mag = JET\n');

% --- 4) Muat semua bingkai + geser slider frame ---
i_fireByTip(fig,'Muat seluruh bingkai');              % "Muat semua frame"
h = guidata(fig);
assert(h.fullLoaded, 'fullLoaded harus true setelah Muat semua');
if h.nF >= 2
    set(h.sldFrame,'Value', min(3, h.nF));
    i_fire(h.sldFrame);                               % i_onFrameSlider
    h = guidata(fig);
    assert(isscalar(h.frame) && h.frame >= 1, 'frame non-skalar setelah slider');
    fprintf('[ok] slider frame -> f%d (semua %d bingkai dimuat)\n', h.frame, h.imgFrames);
else
    fprintf('[ok] hanya 1 bingkai (slider dilewati)\n');
end

% --- 5) GESER ROI (simulasi drag) -> POT re-sampel dari posisi ROI terkini ---
h = guidata(fig);
xExt = h.xExt; yExt = h.yExt;
assert(~isempty(xExt) && ~isempty(yExt), 'extent grid kosong');
ymid = mean(yExt);
% Geser ROI ke garis tengah (seperti user men-drag ujung-ujungnya).
newPos = [xExt(1)+0.1*diff(xExt) ymid; xExt(2)-0.1*diff(xExt) ymid];
assert(~isempty(h.roi) && isvalid(h.roi), 'ROI hilang sebelum di-geser');
h.roi.Position = newPos;
guidata(fig, h);
i_callCollect(fig);                                   % i_collectPOT (baca ROI)
h = guidata(fig);
% i_collectPOT harus memakai POSISI ROI terkini, bukan h.line lama.
assert(abs(h.line.p1(2) - ymid) < 1e-6, 'i_collectPOT tak baca posisi ROI terkini');
assert(~isempty(h.recs), 'POT kosong setelah garis di-set');
assert(~isempty(h.indenter) && any(isfinite(h.indenter)), 'indenter kosong');
% CLim Vel mag ikut RE-SAMPEL: atas = ceil(maks indenter baru, 0.5).
mx2 = max(h.indenter(isfinite(h.indenter)));
assert(abs(h.climVel(2) - ceil(mx2/0.5)*0.5) < 1e-9, ...
    'CLim atas tak ikut indenter baru setelah geser ROI');
fprintf('[ok] GESER ROI -> POT re-sampel: %d titik, indenter maks=%.3g -> CLim atas=%.2g\n', ...
    numel(h.recs), mx2, h.climVel(2));

% --- 6) Klik kurva + klik axPOT (pindah frame) + skala-V ---
crv = findobj(h.axPOT,'Tag','potCurve');
assert(~isempty(crv), 'tak ada handle kurva di axPOT');
i_callCurveClick(fig, crv(1));
set(h.sldVScale,'Value', 0.5); i_fire(h.sldVScale);   % i_onVScale
fprintf('[ok] klik kurva + skala-V tanpa error\n');

% --- 6b) MONTASE engine: even-frames + render grid & 2-kolom -> PNG ---
h = guidata(fig);
nF = max(1, h.imgFrames);
% even spacing: cek ujung-ujung & jumlah
fr = pivcore.montage.evenFrames(nF, min(8, nF));
assert(fr(1) == 1, 'evenFrames harus mulai dari bingkai 1');
assert(fr(end) == nF, 'evenFrames harus berakhir di bingkai terakhir');
fprintf('[ok] evenFrames(%d,%d) = [%s]\n', nF, numel(fr), num2str(fr));

tmpdir = tempname; mkdir(tmpdir);
cleanTmp = onCleanup(@() i_rmTmp(tmpdir));

% (a) grid kustom even-spacing, velocity, label huruf
cfgG = struct('mode','grid','scalar','velocity_magnitude', ...
    'frames',fr,'rows',2,'cols',ceil(numel(fr)/2), ...
    'climVel',h.climVel,'shearAbs',h.shearAbs, ...
    'gsOn',true,'gsAlpha',0.3,'label','letter','dpi',120, ...
    'outFile',fullfile(tmpdir,'mtg_grid.png'),'title','smoke grid');
outG = pivcore.montage.buildMontage(h.data, cfgG);
assert(isfile(outG), 'PNG montase grid tak tertulis');
dG = dir(outG); assert(dG.bytes > 1000, 'PNG grid mencurigakan kecil');
fprintf('[ok] montase GRID -> %s (%.0f KB)\n', 'mtg_grid.png', dG.bytes/1024);

% (b) 2-kolom vel|shear, selektif beberapa frame, label frame-saja
frSel = unique([1 round(nF/2) nF]);
cfg2 = struct('mode','twocol','frames',frSel,'rows',numel(frSel),'cols',2, ...
    'climVel',h.climVel,'shearAbs',h.shearAbs, ...
    'gsOn',false,'gsAlpha',0.3,'label','frame','dpi',120, ...
    'outFile',fullfile(tmpdir,'mtg_2col.png'),'title','smoke 2col');
out2 = pivcore.montage.buildMontage(h.data, cfg2);
assert(isfile(out2), 'PNG montase 2-kolom tak tertulis');
d2 = dir(out2); assert(d2.bytes > 1000, 'PNG 2-kolom mencurigakan kecil');
fprintf('[ok] montase 2-KOLOM -> %s (%.0f KB)\n', 'mtg_2col.png', d2.bytes/1024);

% pastikan tak ada figure montase tertinggal (semua di-close)
assert(isempty(findall(0,'Type','figure','-and','-regexp','Name','smoke')), ...
    'figure montase off-screen tak ter-close');
fprintf('[ok] figure montase off-screen bersih (ter-close)\n');

% --- 7) Hapus garis (reset) -> ROI ikut terhapus ---
i_fireByTip(fig,'Hapus garis PSG');
h = guidata(fig);
assert(isempty(h.recs) && isempty(h.line), 'garis/POT tak ter-reset');
assert(isempty(h.roi) || ~isvalid(h.roi), 'ROI tak terhapus saat reset garis');
fprintf('[ok] hapus garis -> axPOT kosong + ROI terhapus\n');

fprintf('==== GRAINSA3 SEMUA LULUS ✓ ====\n');
end


% ---------------------------------------------------------------------
% Helper tes: panggil handler internal via callback handle terpasang
% (i_* nested tak bisa dipanggil langsung; kita fire callback widget).
% ---------------------------------------------------------------------
function i_fire(hObj)
    cb = get(hObj,'Callback');
    if ~isempty(cb), feval(cb, hObj, struct()); end
end

function i_invokeCellSel(fig, evt)
    h = guidata(fig);
    cb = get(h.tbl,'CellSelectionCallback');
    feval(cb, h.tbl, evt);
end

function i_fireByTip(fig, tipSubstr)
%I_FIREBYTIP  Cari uicontrol pushbutton di figure yg TooltipString memuat
%   substring lalu picu callback-nya (cara stabil memilih tombol tanpa tag).
    btns = findall(fig,'Type','uicontrol');
    for i = 1:numel(btns)
        tip = get(btns(i),'TooltipString');
        if ischar(tip) && contains(tip, tipSubstr)
            i_fire(btns(i)); return;
        end
    end
    error('Tombol dgn tooltip "%s" tak ditemukan', tipSubstr);
end

function i_callCollect(fig)
%I_CALLCOLLECT  Picu sampling POT lewat callback "Tarik garis PSG" TAK bisa
%   (butuh klik). Sebagai gantinya panggil jalur yg sama via tombol Spacing
%   (i_onSpacing -> i_collectPOT bila ada garis). Set spacing -> auto.
    h = guidata(fig);
    set(h.edSpacing,'String','auto');
    cb = get(h.edSpacing,'Callback');
    feval(cb, h.edSpacing, struct());   % i_onSpacing -> i_collectPOT (garis sudah di-set)
end

function i_callCurveClick(fig, srcLine)
    cb = get(srcLine,'ButtonDownFcn');
    if ~isempty(cb), feval(cb, srcLine, struct()); end
end

function i_closeFig(fig)
    try, if ishghandle(fig), close(fig); end, catch, end
end

function b = i_bn(p)
    if isempty(p), b=''; else, [~,b]=fileparts(p); end
end

function i_rmTmp(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
