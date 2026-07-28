function test_smoke_grain6(rootDir)
%TEST_SMOKE_GRAIN6  Uji headless GRAIN6_temp (tampak peta / kurva HB). Cakupan:
%   dropdown PSG + tabel kandidat HB; tambah 3 kandidat kurva + Set X0/X1;
%   merge overlap = MAX (envelope, unit hbMerge); overlay hbLineTop hijau di
%   axPOT; round-trip _hb.json; per-PSG (kandidat HB unik per garis PSG); fitur
%   sesar F# DIPERTAHANKAN (assign HW + POI). Sidecar dibersihkan sendiri.
%
%   test_smoke_grain6                 % default: .../EXP_coll/M-CON-4cm-F/MATPIV
%   test_smoke_grain6('/path/folder')

fprintf('==== TEST SMOKE GRAIN6 (tampak peta / HB) ====\n');
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
grain_setup();
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>
if nargin < 1 || isempty(rootDir)
    rootDir = fullfile(grain_fixture_root(),'EXP_coll','M-CON-4cm-F','MATPIV');
end
if ~isfolder(rootDir)
    fprintf('[SKIP] folder uji tak ada: %s\n', rootDir);
    return;
end
fprintf('[ok] folder: %s\n', rootDir);

% --- UNIT hbMerge (murni; overlap=MAX + startX + tanpa ekor) SEBELUM GUI ---
c1 = struct('values',[3 3 3 3 3],'x0',1,'x1',3);
c2 = struct('values',[9 8 7 6 5],'x0',2,'x1',4);
[hbU, sxU] = pivcore.pot.hbMerge.merge({c1,c2}, 5);
assert(isequaln(hbU,[3 8 7 6 NaN]), 'hbMerge overlap bukan MAX / ekor salah');
assert(sxU==1, 'hbMerge startX salah');
% startX>1 -> tanpa ekor sebelum X0 kurva pertama
c3 = struct('values',[5 5 5 5 5],'x0',3,'x1',5);
[hbU2,~] = pivcore.pot.hbMerge.merge({c3, struct('values',[1 1 1 1 1],'x0',1,'x1',5)}, 5);
assert(isequaln(hbU2(1:2),[NaN NaN]), 'hbMerge ekor tak ter-NaN sebelum X0 kurva-1');
fprintf('[ok] unit hbMerge: overlap=MAX, startX, tanpa ekor\n');

% Bersihkan _hb dulu (uji ini yang punya); catat _potdata pre-exist.
d = dir(fullfile(rootDir,'*_hb.json')); for i=1:numel(d), delete(fullfile(rootDir,d(i).name)); end

fig = GRAIN6_temp(rootDir, 'tab','anlz');
assert(ishghandle(fig), 'figure GRAIN6 tak terbuka');
cln = onCleanup(@() i_close(fig)); %#ok<NASGU>
h = guidata(fig);
assert(~isempty(h.recs), 'recs kosong');
fprintf('[ok] build + exp1 (%d kurva, nF=%d)\n', numel(h.recs), h.nF);

df1 = h.df;
potP = pivcore.io.grain4PotData.dataPath(df1);
prePot = isfile(potP);
hbP = pivcore.io.grain6Hb.dataPath(df1);

% --- Kontrol HB baru + dropdown PSG ---
assert(isfield(h,'tblHb') && ishghandle(h.tblHb), 'tblHb (tabel kandidat HB) tak ada');
cn = get(h.tblHb,'ColumnName');
assert(isequal(cn(:).', {'#','posPx','X0','X1'}), 'ColumnName tblHb salah');
assert(strcmp(get(h.lstLines,'Style'),'popupmenu'), 'daftar garis PSG harus DROPDOWN (popupmenu)');
assert(isfield(h,'chkHbOverlay') && ishghandle(h.chkHbOverlay), 'checkbox overlay HB tak ada');
% Fitur sesar DIPERTAHANKAN.
assert(isfield(h,'tblFault') && ishghandle(h.tblFault), 'tblFault (F#) HARUS tetap ada di GRAIN6');
fprintf('[ok] tblHb 4 kolom + dropdown PSG + tblFault (F# dipertahankan)\n');

% --- Pastikan ada garis PSG aktif (exp punya 1 garis dari _potdata) ---
assert(~isempty(h.activePsgId), 'butuh garis PSG aktif utk uji HB');
psg1 = h.activePsgId;

% --- Tambah 3 kandidat HB (kurva OVERLAP) + Set X0/X1 ---
i_selCurve(fig, 5);  i_fire(fig,'➕ Kandidat');
i_setFrame(fig,10);  i_fire(fig,'Set X0'); i_setFrame(fig,120); i_fire(fig,'Set X1');
i_selCurve(fig, 8);  i_fire(fig,'➕ Kandidat');
i_setFrame(fig,60);  i_fire(fig,'Set X0'); i_setFrame(fig,200); i_fire(fig,'Set X1');
i_selCurve(fig, 12); i_fire(fig,'➕ Kandidat');
i_setFrame(fig,150); i_fire(fig,'Set X0'); i_setFrame(fig,280); i_fire(fig,'Set X1');
h = guidata(fig);
blk = pivcore.io.grain6Hb.findBlock(h.hbdoc, psg1);
assert(~isempty(blk), 'blok HB garis PSG aktif tak dibuat');
assert(numel(blk.candidates)==3, sprintf('kandidat HB harus 3, dapat %d', numel(blk.candidates)));
for k=1:3
    ck = blk.candidates{k};
    assert(isfinite(ck.x0) && isfinite(ck.x1), sprintf('kandidat %d X0/X1 tak finite', k));
end
fprintf('[ok] 3 kandidat HB + X0/X1 terisi (snap ke kurva)\n');

% --- Overlay garis HB (hbLineTop hijau) tergambar ---
i_fire(fig,'💾 Save'); % memicu render juga; overlay dari decoratePOT
pivui.grain4Shell.renderPOT(fig);
h = guidata(fig);
hbLine = findall(h.axPOT,'Tag','hbLineTop');
assert(~isempty(hbLine), 'overlay garis HB (hbLineTop) tak tergambar');
assert(isequal(get(hbLine(1),'Color'), [0 0.60 0]), 'garis HB bukan hijau [0 0.60 0]');
fprintf('[ok] overlay garis HB hijau (hbLineTop) di axPOT\n');

% --- Round-trip _hb.json ---
assert(isfile(hbP), '_hb.json tak tertulis');
doc2 = pivcore.io.grain6Hb.read(df1);
[b2, idx] = pivcore.io.grain6Hb.findBlock(doc2, psg1);
assert(idx>=1, 'blok HB tak round-trip');
assert(numel(b2.candidates)==3, 'jumlah kandidat tak round-trip');
% posPx & x0/x1 bertahan
c1r = b2.candidates{1};
assert(isfinite(c1r.posPx) && isfinite(c1r.x0) && isfinite(c1r.x1), 'kandidat-1 field hilang saat round-trip');
% cache merged terisi
assert(~isempty(b2.merged) && any(isfinite(b2.merged)), 'cache merged HB kosong saat simpan');
fprintf('[ok] round-trip _hb.json (3 kandidat; merged cache OK)\n');

% --- Per-PSG: buat garis PSG KEDUA -> tabel HB kosong (kandidat tak bocor) ---
h = guidata(fig);
if isstruct(h.line) && isfield(h.line,'p1')
    % Geser garis sedikit -> psgId baru; simpan sbg garis kedua.
    ln2 = h.line; ln2.p1 = ln2.p1 + [0 15]; ln2.p2 = ln2.p2 + [0 15];
    h.line = ln2; guidata(fig,h);
    pivui.grain4Shell.callHook(fig,'onLineChanged');
    i_fire(fig,'Simpan garis');
    h = guidata(fig);
    psg2 = h.activePsgId;
    if ~strcmp(psg2, psg1)
        % onLineChanged (dipicu di atas) sudah refresh tabel HB utk PSG-2.
        h = guidata(fig);
        d2 = get(h.tblHb,'Data');
        assert(isempty(d2) || size(d2,1)==0, 'kandidat HB BOCOR ke garis PSG lain');
        fprintf('[ok] per-PSG: garis PSG-2 (%s) tabel HB KOSONG (tak bocor)\n', psg2);
        % Aktifkan balik PSG-1 -> kandidat pulih (i_activateLineById refresh HB).
        i_activatePsgById(fig, psg1);
        h = guidata(fig);
        d1 = get(h.tblHb,'Data');
        assert(~isempty(d1) && size(d1,1)==3, sprintf('kandidat PSG-1 tak pulih (dapat %d baris)', size(d1,1)));
        fprintf('[ok] per-PSG: balik ke PSG-1 -> 3 kandidat PULIH\n');
    else
        fprintf('[SKIP] geser garis tak menghasilkan psgId berbeda; lewati uji per-PSG\n');
    end
else
    fprintf('[SKIP] tak ada h.line utk uji per-PSG\n');
end

% --- Fitur sesar F# masih jalan (model slot: ketik F# di sel -> assign HW + POI) ---
h = guidata(fig); i_activatePsgById(fig, psg1); % kembali ke garis dgn kurva
i_editCell(fig,1,2,'1');                     % baris 1, kolom F#=1 -> buat sesar nomor 1
h = guidata(fig); fid = h.activeFaultId;
assert(~isempty(fid), 'ketik F#=1 tak membuat sesar aktif');
i_selCurve(fig,5); i_fire(fig,'⬆ Jadikan HW');
i_setFrame(fig,5); i_fire(fig,'START');
h = guidata(fig);
[fF1,ix] = pivcore.io.grain5Faults.findFault(h.fdoc, fid);
assert(ix>=1 && isfinite(fF1.startF), 'fitur sesar F# (slot) rusak (assign/POI gagal)');
assert(pivui.grain5Model.faultUiNum(fF1)==1, 'nomor tampil sesar (uiNum) bukan 1');
fprintf('[ok] fitur sesar F# model SLOT: ketik F#=1 -> assign HW + START=%g (uiNum=1)\n', fF1.startF);

% --- +F tambah baris slot; kolom F# editable, SF read-only ---
h = guidata(fig); n0 = numel(h.faultSlots);
i_fire(fig,'+F');
h = guidata(fig); assert(numel(h.faultSlots)==n0+1, '+F tak menambah 1 baris slot');
ce = get(h.tblFault,'ColumnEditable');
assert(ce(2) && ~ce(3), 'kolom F# harus editable, SF read-only');
fprintf('[ok] +F tambah slot (%d->%d); F# editable, SF read-only\n', n0, n0+1);

delete(fig);
% cleanup
if ~prePot && isfile(potP), delete(potP); end
d = dir(fullfile(rootDir,'*_hb.json')); for i=1:numel(d), delete(fullfile(rootDir,d(i).name)); end
% _faults.json yang mungkin ditulis test ini (F1) — bersihkan hanya bila baru.
fprintf('==== GRAIN6 SEMUA LULUS ✓ ====\n');
end

% ---------------------------------------------------------------------
function i_fire(fig, str)
    b = findall(fig,'Type','uicontrol');
    for i=1:numel(b)
        s = get(b(i),'String');
        if ischar(s) && strcmp(s,str)
            cb = get(b(i),'Callback'); if ~isempty(cb), cb(b(i),[]); end, return;
        end
    end
    error('tombol tak ketemu: %s', str);
end
function i_selCurve(fig, r)
    h = guidata(fig); h.selRows = r; guidata(fig,h);
    try, set(fig,'CurrentObject',h.axPOT); catch, end
    pivui.grain4Shell.callHook(fig,'onCurveClick', r);
end
function i_setFrame(fig, k), h = guidata(fig); h.frame = k; guidata(fig,h); end
function i_editCell(fig, r, c, str)
    % Simulasikan user mengetik `str` di sel (r,c) tabel sesar -> picu CellEditCallback.
    h = guidata(fig); tb = h.tblFault;
    cb = get(tb,'CellEditCallback');
    evt = struct('Indices',[r c], 'NewData',str, 'PreviousData','', 'EditData',str, 'Error',[]);
    if ~isempty(cb), cb(tb, evt); end
end
function i_activatePsgById(fig, id)
    % Set dropdown ke garis id (bila ada) lalu aktifkan via handler internal.
    h = guidata(fig);
    S = get(h.lstLines,'String');
    hit = 0;
    for i=1:numel(S)
        if contains(S{i}, id), hit = i; break; end
    end
    if hit>0, set(h.lstLines,'Value',hit); end
    % Panggil handler aktifkan (cari tombol 'Aktifkan').
    b = findall(fig,'Type','uicontrol');
    for i=1:numel(b)
        if strcmp(get(b(i),'String'),'Aktifkan')
            cb=get(b(i),'Callback'); if ~isempty(cb), cb(b(i),[]); end, break;
        end
    end
end
function i_close(fig), try, if ishghandle(fig), delete(fig); end, catch, end, end
