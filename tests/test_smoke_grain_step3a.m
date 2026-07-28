function test_smoke_grain_step3a(rootDir)
%TEST_SMOKE_GRAINSA_STEP3A  Uji headless GRAINSA3a (assign kurva POT atas .mat Step 2).
%
%   test_smoke_grain_step3a                 % default: .../RAW_bat/PIV_2026-06-23
%   test_smoke_grain_step3a('/path/folder') % folder berisi .mat PIV (PIV_<tgl>/)
%
%   GRAINSA3a (PAB_step_3a): input = .mat output Step 2, POT on-the-fly (auto-PSG),
%   lalu ASSIGN kurva -> HW-#/F/F0/FFW (pola PIVTerry StandAlone step2). Progres
%   assignment + garis PSG disimpan ke <base>_autopot.mat (kompat suite).
%
%   Tes membangun GUI sungguhan & menjalankan callback secara terprogram:
%     1. setup path GRAIN_SA + build GUI + tabel terisi
%     2. pilih exp -> auto-PSG -> POT terbentuk + records punya origin
%     3. pilih kurva (klik) -> set Type+# -> Assign -> label tertempel + auto-save
%     4. _autopot.mat tertulis + loadAssignments balik konsisten
%     5. RAW<->ASG view toggle + Unassign
%     6. Trim ke indenter + Pulih
%     7. reload exp -> assignment & garis PSG ter-restore (round-trip)
%   Sidecar _autopot dibersihkan di akhir (tes tak meninggalkan jejak).
%
%   SELALU MATLAB R2025b.

fprintf('==== TEST SMOKE GRAINSA3a (PAB_step_3a) — assign GUI nyata ====\n');

here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));  % +root (grain_setup, GRAIN*) sejak tests/ dipisah
roots = grain_setup();
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP: jendela tak rebut fokus
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>
assert(~isempty(which('pivcore.pot.step1Collect')), '+pivcore tidak di path.');
assert(~isempty(which('pivcore.pot.labels')), '+pivcore.pot.labels tidak di path.');

if nargin < 1 || isempty(rootDir)
    rootDir = fullfile(roots.data_root, 'RAW', 'PIV_2026-06-24');
end
assert(isfolder(rootDir), 'Folder tak ada: %s', rootDir);
fprintf('[ok] folder: %s\n', rootDir);

% --- 1) Build GUI ---
GRAIN3a(rootDir);
figs = findall(0,'Type','figure','-and','-regexp','Name','GRAINSA3a');
assert(~isempty(figs), 'figure GRAINSA3a tak terbuka');
fig = figs(1);
cleaner = onCleanup(@() i_closeFig(fig));
h = guidata(fig);
assert(~isempty(h.list), 'tabel eksperimen kosong (tak ada .mat PIV)');
fprintf('[ok] GUI build + %d berkas PIV\n', numel(h.list));

% Bersihkan sidecar _autopot exp pertama LEBIH DULU (round-trip dari nol).
df = h.list(1).file;
ap = pivcore.io.step1Session.autopotPath(df);
cleanAp = onCleanup(@() i_rmIfFile(ap));
i_rmIfFile(ap);

% --- 2) Pilih exp -> auto-PSG -> POT ---
i_invokeCellSel(fig, struct('Indices',[1 1]));
h = guidata(fig);
assert(~isempty(h.data), 'exp tak termuat');
assert(~isempty(h.line) && ~isempty(h.recs), 'auto-PSG/POT tak terbentuk');
assert(~isempty(h.indenter) && any(isfinite(h.indenter)), 'indenter kosong');
% records on-the-fly harus punya field origin (utk penanda HW di axMain).
assert(isfield(h.recs,'origin'), 'records POT tak punya field origin');
assert(isfield(h.recs,'assignLabel'), 'records tak punya assignLabel');
nrec = numel(h.recs);
assert(nrec >= 3, 'jumlah titik POT terlalu sedikit utk uji assign');
fprintf('[ok] muat exp %s: %d titik POT (auto-PSG)\n', i_bn(df), nrec);

% --- 3) Pilih kurva pertama via klik -> Assign HW-1 ---
% NB: axPOT di-render ulang tiap Assign -> handle kurva BASI. Selalu cari
% ulang lewat i_clickRec (findobj fresh) sebelum klik.
assert(~isempty(findobj(h.axPOT,'Tag','potCurve')), 'tak ada handle kurva di axPOT');
i_clickRec(fig, 1);
h = guidata(fig);
assert(isequal(h.selRows, 1), 'klik kurva tak memilih record 1');

set(h.popType,'Value',1);            % HW
set(h.edNum,'String','1');
i_fire(h.popType);                   % preview
i_fireGreenCheck(fig);               % Assign (tombol ceklis hijau)
h = guidata(fig);
assert(strcmp(h.recs(1).assignLabel,'HW-1'), ...
    sprintf('record 1 tak ber-label HW-1 (=%s)', h.recs(1).assignLabel));
assert(~isempty(h.assign) && isstruct(h.assign), 'agregat assign kosong setelah Assign');
fprintf('[ok] Assign record 1 -> HW-1 (auto # maju ke %s)\n', get(h.edNum,'String'));

% --- 3b) Auto-maju nomor: setelah Assign HW-1, edNum -> 2 ---
assert(strcmp(strtrim(get(h.edNum,'String')),'2'), 'nomor tak auto-maju ke 2');

% --- 4) _autopot.mat tertulis + loadAssignments konsisten ---
assert(isfile(ap), 'auto-save tak menulis _autopot.mat');
saved = pivcore.io.step1Session.loadAssignments(df);
assert(~isempty(saved) && isstruct(saved), 'loadAssignments kosong');
lbls = {saved.label};
assert(any(strcmp(lbls,'HW-1')), 'HW-1 tak tersimpan di _autopot');
% garis PSG juga tersimpan (utk round-trip sampling identik).
Lsv = pivcore.io.step1Session.loadLine(df);
assert(~isempty(Lsv) && isfield(Lsv,'p1'), 'garis PSG tak tersimpan');
fprintf('[ok] _autopot.mat: %d label + garis PSG tersimpan\n', numel(saved));

% --- 5) Assign record 2 -> F-1, lalu RAW<->ASG view + Unassign ---
if i_clickRec(fig, 2)
    h = guidata(fig);
    set(h.popType,'Value',2);        % F
    set(h.edNum,'String','1'); i_fire(h.popType);
    i_fireGreenCheck(fig);
    h = guidata(fig);
    assert(strcmp(h.recs(2).assignLabel,'F-1'), 'record 2 tak ber-label F-1');
    fprintf('[ok] Assign record 2 -> F-1\n');
end

% ASG view: hanya kurva ter-assign tampil.
set(h.btnView,'Value',1); i_fire(h.btnView);
h = guidata(fig);
assert(strcmp(h.viewMode,'assigned'), 'view tak pindah ke assigned');
crvAsg = findobj(h.axPOT,'Tag','potCurve');
labeled = 0; for r=1:numel(h.recs), if ~isempty(pivcore.pot.records.label(h.recs(r))), labeled=labeled+1; end, end
assert(numel(crvAsg) == labeled, 'jumlah kurva ASG view tak cocok jumlah ter-assign');
set(h.btnView,'Value',0); i_fire(h.btnView);
fprintf('[ok] RAW<->ASG view toggle (%d kurva ter-assign)\n', labeled);

% Unassign record 1.
i_clickRec(fig, 1);
i_fireRedX(fig);                     % Unassign (tombol X merah)
h = guidata(fig);
assert(isempty(h.recs(1).assignLabel), 'record 1 tak ter-unassign');
fprintf('[ok] Unassign record 1\n');

% --- 6) Trim ke indenter record 1 + Pulih ---
i_clickRec(fig, 1);
i_fireByTip(fig,'di titik kurva menyentuh max indenter');   % Trim
h = guidata(fig);
assert(h.recs(1).cutManual == true, 'record 1 tak ditandai trim (cutManual)');
fprintf('[ok] Trim ke indenter record 1 (cutFrame=%g)\n', h.recs(1).cutFrame);
i_fireByTip(fig,'batalkan trim');                            % Pulih (terpilih)
h = guidata(fig);
assert(h.recs(1).cutManual == false, 'Pulih tak membatalkan trim');
fprintf('[ok] Pulih record 1 (trim dibatalkan)\n');

% --- 7) Round-trip: reload exp -> assignment & garis ter-restore ---
i_invokeCellSel(fig, struct('Indices',[1 1]));
h = guidata(fig);
% F-1 (record 2) harus pulih dari _autopot (HW-1 sudah di-unassign di step 5).
got = ''; for r=1:numel(h.recs), L=pivcore.pot.records.label(h.recs(r)); if strcmp(L,'F-1'), got='F-1'; break; end, end
assert(strcmp(got,'F-1'), 'assignment F-1 tak ter-restore saat reload');
% garis tersimpan dipulihkan (horizontal y sama).
assert(~isempty(h.line), 'garis PSG tak ter-restore saat reload');
fprintf('[ok] round-trip reload: F-1 + garis PSG ter-restore\n');

fprintf('==== GRAINSA3a SEMUA LULUS ✓ ====\n');
end


% ---------------------------------------------------------------------
% Helper tes
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
    btns = findall(fig,'Type','uicontrol');
    for i = 1:numel(btns)
        tip = get(btns(i),'TooltipString');
        if ischar(tip) && contains(tip, tipSubstr)
            i_fire(btns(i)); return;
        end
    end
    error('Tombol dgn tooltip "%s" tak ditemukan', tipSubstr);
end

function i_fireGreenCheck(fig)
%I_FIREGREENCHECK  Picu tombol Assign (ForegroundColor hijau, String ceklis).
    i_fireByTip(fig, 'Assign kurva terpilih');
end

function i_fireRedX(fig)
    i_fireByTip(fig, 'Unassign kurva terpilih');
end

function ok = i_clickRec(fig, rec)
%I_CLICKREC  Cari handle kurva axPOT (FRESH, axPOT di-render ulang tiap aksi)
%   yg UserData == rec lalu picu klik-nya. ok=false bila kurva tak ditemukan.
    ok = false;
    h = guidata(fig);
    crv = findobj(h.axPOT,'Tag','potCurve');
    for i = 1:numel(crv)
        if ~ishghandle(crv(i)), continue; end
        if isequal(get(crv(i),'UserData'), rec)
            cb = get(crv(i),'ButtonDownFcn');
            if ~isempty(cb), feval(cb, crv(i), struct()); ok = true; end
            return;
        end
    end
end

function i_closeFig(fig)
    try, if ishghandle(fig), close(fig); end, catch, end
end

function b = i_bn(p)
    if isempty(p), b=''; else, [~,b]=fileparts(p); end
end

function i_rmIfFile(f)
    try, if ~isempty(f) && isfile(f), delete(f); end, catch, end
end
