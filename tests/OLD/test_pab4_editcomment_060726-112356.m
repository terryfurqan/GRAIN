function test_pab4_editcomment()
%PROBE_EDITCOMMENT  Tombol Edit komentar tab③: muat->ubah->Simpan edit (update,
%   bukan tambah) + Batal.
here = fileparts(mfilename('fullpath')); addpath(here); addpath(fileparts(here));
roots = pab_setup();
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP: jendela tak rebut fokus
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>
rootDir = fullfile(roots.data_root, 'RAW', 'PIV_2026-06-24');
PAB4(rootDir);
fig = findall(0,'Type','figure','-regexp','Name','PAB4'); fig = fig(1);
cln = onCleanup(@() delete(fig));
h = guidata(fig); df1 = h.list(1).file;
potP = pivcore.io.pab4PotData.dataPath(df1); comP = pivcore.io.pab4Comments.dataPath(df1);
i_rm(potP); i_rm(comP);
cl2 = onCleanup(@() i_rm2({potP,comP}));

pivui.pab4Shell.loadExperiment(fig, 1); h = guidata(fig);
if isempty(h.recs), pivui.pab4Shell.setPsgLock(fig, true); h = guidata(fig); end

% tambah komentar
set(h.edComment,'String','komentar awal observasi');
i_click(h.tabKom,'➕ Komentar');
h = guidata(fig);
assert(numel(h.cdoc.comments)==1, 'komentar awal tak tersimpan');
id = h.cdoc.comments{1}.id;

% --- ENTER EDIT ---
h.selCommentId = id; guidata(fig,h);
feval(get(h.btnEditComment,'Callback'), h.btnEditComment, []);
h = guidata(fig);
assert(strcmp(h.editingCommentId,id), 'mode edit tak aktif');
assert(strcmp(get(h.btnAddComment,'String'),'💾 Simpan edit'), 'tombol add tak jadi Simpan edit');
assert(strcmp(get(h.btnEditComment,'String'),'✖ Batal edit'), 'tombol edit tak jadi Batal');
box = i_flat(get(h.edComment,'String'));
assert(contains(box,'komentar awal'), 'teks komentar tak dimuat ke kotak: %s', box);
fprintf('[ok] enter edit: teks dimuat, tombol jadi Simpan/Batal\n');

% --- SIMPAN EDIT (update) ---
set(h.edComment,'String','komentar awal observasi DIREVISI');
feval(get(h.btnAddComment,'Callback'), h.btnAddComment, []);
h = guidata(fig);
assert(numel(h.cdoc.comments)==1, 'update malah menambah komentar (=%d)', numel(h.cdoc.comments));
assert(strcmp(h.cdoc.comments{1}.id, id), 'id komentar berubah saat edit');
assert(contains(h.cdoc.comments{1}.text,'DIREVISI'), 'teks tak terupdate');
assert(isempty(h.editingCommentId), 'mode edit tak keluar setelah simpan');
assert(strcmp(get(h.btnAddComment,'String'),'➕ Komentar'), 'tombol tak balik ke ➕ Komentar');
cd = pivcore.io.pab4Comments.read(df1);
assert(contains(cd.comments{1}.text,'DIREVISI'), 'update tak terpersist ke disk');
fprintf('[ok] simpan edit: id sama, teks terupdate (1 komentar), terpersist\n');

% --- BATAL EDIT ---
h.selCommentId = id; guidata(fig,h);
feval(get(h.btnEditComment,'Callback'), h.btnEditComment, []);   % enter
set(h.edComment,'String','perubahan yang dibatalkan');
feval(get(h.btnEditComment,'Callback'), h.btnEditComment, []);   % batal
h = guidata(fig);
assert(isempty(h.editingCommentId), 'batal tak keluar mode edit');
assert(contains(h.cdoc.comments{1}.text,'DIREVISI'), 'batal malah mengubah teks');
assert(isempty(strtrim(i_flat(get(h.edComment,'String')))), 'kotak tak dikosongkan saat batal');
fprintf('[ok] batal edit: mode keluar, teks tak berubah, kotak bersih\n');

fprintf('==== editcomment LULUS ✓ ====\n');
end

function s = i_flat(raw)
    if iscell(raw), s = strjoin(cellfun(@char,raw(:).','UniformOutput',false),' ');
    elseif ischar(raw) && size(raw,1)>1, s = strjoin(cellstr(raw).',' ');
    else, s = char(raw); end
end
function i_click(parent, str)
    b = findobj(parent,'Style','pushbutton','String',str);
    assert(~isempty(b), 'tombol "%s" tak ada', str);
    cb = get(b(1),'Callback'); if ~isempty(cb), feval(cb, b(1), struct()); end
end
function i_rm(f), try, if ~isempty(f)&&isfile(f), delete(f); end, catch, end, end
function i_rm2(fs), for k=1:numel(fs), i_rm(fs{k}); end, end
