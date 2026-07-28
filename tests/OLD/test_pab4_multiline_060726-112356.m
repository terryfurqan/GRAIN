function test_pab4_multiline()
%PROBE_MULTILINE  Reproduksi bug: komentar MULTI-BARIS (char matrix / cell) bikin
%   Save & ➕ Komentar error ("First argument must be text"). Harus LULUS sekarang.
here = fileparts(mfilename('fullpath')); addpath(here); addpath(fileparts(here));

% 1) unit: i_editText harus ratakan char-matrix & cell -> char row
% (akses lewat PAB4 sulit; uji perilaku end-to-end di bawah)

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

% --- KASUS 1: char MATRIX 2-D (yang dulu bikin error) -> ➕ Komentar ---
set(h.edComment,'String', char({'baris satu observasi', 'baris dua lanjutan'}));
i_click(h.tabKom,'➕ Komentar');
h = guidata(fig);
assert(numel(h.cdoc.comments) >= 1, 'KASUS1: komentar multi-baris (char matrix) TAK tersimpan');
t1 = h.cdoc.comments{end}.text;
assert(contains(t1,'baris satu') && contains(t1,'baris dua'), 'KASUS1: isi multi-baris hilang: %s', t1);
fprintf('[ok] KASUS1 char-matrix 2-baris -> komentar tersimpan, 2 baris utuh\n');

% --- KASUS 2: cellstr multi-baris -> Save langsung (tanpa ➕) ---
set(h.edComment,'String', {'paragraf A', 'paragraf B', 'paragraf C'});
i_click(h.tabKom,'💾 Save');
assert(isfile(comP), 'KASUS2: _comments.json tak tertulis (Save mati)');
cd = pivcore.io.pab4Comments.read(df1);
assert(numel(cd.comments) >= 2, 'KASUS2: Save tak menyimpan komentar pending (=%d)', numel(cd.comments));
t2 = cd.comments{end}.text;
assert(contains(t2,'paragraf A') && contains(t2,'paragraf C'), 'KASUS2: isi hilang: %s', t2);
fprintf('[ok] KASUS2 cellstr 3-baris -> Save commit pending + tertulis ke disk\n');

% --- KASUS 3: sisip tag saat teks multi-baris (dulu endsWith error) ---
set(h.edComment,'String', char({'kalimat satu', 'kalimat dua ^'}));
b = findobj(h.tabKom,'Style','pushbutton','String','@frame');
cb = get(b(1),'Callback'); cb(b(1),[]);
txt = i_flat(get(h.edComment,'String'));
assert(contains(txt,'@frame:'), 'KASUS3: sisip tag multi-baris gagal');
fprintf('[ok] KASUS3 sisip tag pada teks multi-baris OK\n');

fprintf('==== multiline LULUS ✓ ====\n');
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
