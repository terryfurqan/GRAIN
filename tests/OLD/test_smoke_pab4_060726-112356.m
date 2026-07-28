function test_smoke_pab4(rootDir)
%TEST_SMOKE_PAB4  Uji headless PAB4 TERPADU (Komentar + Label HW + Net-slip)
%   atas .mat PIV nyata. Membangun 1 GUI, lalu menjalankan callback antar-TAB
%   tanpa reload — membuktikan 1 ruang kerja, 1 garis PSG, 1 truth.
%
%   test_smoke_pab4                 % default: .../RAW/PIV_2026-06-24
%   test_smoke_pab4('/path/folder') % folder berisi .mat PIV
%
%   Jejak sidecar (_comments.json / _potdata.json / PAB4_claude/) dibersihkan.

fprintf('==== TEST SMOKE PAB4 — terpadu ====\n');
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));
roots = pab_setup();
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP: jendela tak rebut fokus
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>
if nargin < 1 || isempty(rootDir)
    rootDir = fullfile(roots.data_root, 'RAW', 'PIV_2026-06-24');
end
assert(isfolder(rootDir), 'Folder tak ada: %s', rootDir);
fprintf('[ok] folder: %s\n', rootDir);

PAB4(rootDir);
fig = findall(0,'Type','figure','-regexp','Name','PAB4');
assert(~isempty(fig),'figure PAB4 tak terbuka'); fig = fig(1);
cln = onCleanup(@() i_close(fig));
h = guidata(fig);
assert(isfield(h,'tabKom') && isfield(h,'tabLbl') && isfield(h,'tabNet'), '3 tab tak terbentuk');
assert(~isempty(h.list), 'tabel eksperimen kosong');
fprintf('[ok] GUI 3-tab + %d berkas PIV\n', numel(h.list));

df1 = h.list(1).file;
potP = pivcore.io.pab4PotData.dataPath(df1);
comP = pivcore.io.pab4Comments.dataPath(df1);
claudeRoot = pivcore.io.pab4Comments.claudeRoot(df1);
i_rm(potP); i_rm(comP); i_rmDir(claudeRoot);
clean2 = onCleanup(@() i_cleanup({potP, comP}, claudeRoot));

% --- muat exp1 (sekali): garis 75% MULAI tak-terkunci & belum disampel ---
hasAuto = isfile(pivcore.io.step1Session.autopotPath(df1));   % _autopot -> auto-sampel
pivui.pab4Shell.loadExperiment(fig, 1);
h = guidata(fig);
if ~hasAuto
    assert(isempty(h.recs), 'exp baru harusnya BELUM disampel (garis tak-terkunci)');
    assert(~h.psgLocked, 'garis baru harus mulai tak-terkunci');
    assert(strcmp(h.activePsgId,'frac075'), 'garis auto harus frac075 (=%s)', h.activePsgId);
    pivui.pab4Shell.setPsgLock(fig, true);   % KUNCI -> baru POT disampel
    h = guidata(fig);
end
assert(~isempty(h.recs), 'POT tak termuat setelah kunci');
nrec = numel(h.recs);
fprintf('[ok] muat exp1: garis 75%% (unlocked->kunci) -> %d kurva tersampel\n', nrec);

% --- TAB LABEL: assign HW-1, HW-2, FFW ke 3 kurva (ruang kerja SAMA) ---
rA = 1; rB = 2; rC = 3;
i_assign(fig, h.tabLbl, rA, 'HW', 1);
i_assign(fig, h.tabLbl, rB, 'HW', 2);
i_assign(fig, h.tabLbl, rC, 'FFW', NaN);
h = guidata(fig);
nums = pivcore.pot.hwLabel.hwNumbers(h.recs);
assert(isequal(sort(nums(:)'),[1 2]), 'HW-1/HW-2 tak terbentuk (=%s)', mat2str(nums));
assert(strcmp(pivcore.pot.records.label(h.recs(rC)),'FFW'), 'FFW tak ter-assign');
assert(size(get(h.tblAssign,'Data'),1)==3, 'tabel kurva berlabel != 3');
fprintf('[ok] assign HW-1/HW-2/FFW (tab Label) + tabel berlabel 3 baris\n');

% --- TAB NET-SLIP: titik Start/END HW-1 + tabel ---
i_click(h.tabNet,'Next ▶'); i_click(h.tabNet,'Next ▶');   % siklus -> HW-1 aktif (Next/Prev)
h = guidata(fig); if h.activeHW~=1, i_click(h.tabNet,'◀ Prev'); h=guidata(fig); end
pivui.pab4Shell.gotoFrame(fig, max(2,round(h.nF*0.3)));
i_click(h.tabNet,'Start');
pivui.pab4Shell.gotoFrame(fig, max(3,round(h.nF*0.8)));
i_click(h.tabNet,'END');
h = guidata(fig);
D = get(h.tblNet,'Data');
assert(size(D,1)==2, 'tabel net-slip bukan 2 HW (=%d)', size(D,1));
st = pivcore.pot.hwLabel.completeness(h.recs);
fprintf('[ok] net-slip: %d HW, FFW=%d, canNetslip=%d; tabel %d baris\n', ...
    st.nHW, st.hasFFW, st.canNetslip, size(D,1));

% --- TAB KOMENTAR: kurva ter-IDENTIFIKASI (label) -> komentar tertaut ---
pivui.pab4Shell.onCurveClick(fig, i_src(h, rA));   % pilih HW-1
h = guidata(fig);
assert(strcmp(h.selCurveLabel,'HW-1'), 'selCurveLabel bukan HW-1 (=%s)', h.selCurveLabel);
set(h.edComment,'String','HW-1 mulai nukleasi.');
i_click(h.tabKom,'➕ Komentar');
h = guidata(fig);
assert(numel(h.cdoc.comments)==1, 'komentar tak tercatat');
assert(strcmp(h.cdoc.comments{1}.curve,'HW-1'), 'komentar tak tertaut HW-1 (=%s)', h.cdoc.comments{1}.curve);
fprintf('[ok] komentar tertaut frame %d + kurva %s (identifikasi via label)\n', ...
    h.cdoc.comments{1}.frame, h.cdoc.comments{1}.curve);

% --- LINK KURVA HW (berupa file) ke komentar terpilih (tab ③) ---
h.selCommentId = h.cdoc.comments{1}.id; guidata(fig, h);
i_click(h.tabKom,'🔗 Link kurva HW');
h = guidata(fig);
c1 = h.cdoc.comments{1};
assert(strcmp(c1.curve,'HW-1'), 'link: curve bukan HW-1 (=%s)', c1.curve);
assert(~isempty(c1.images.axpot), 'link: gambar kurva HW tak terlampir');
adir0 = pivcore.io.pab4Comments.assetDir(df1);
assert(isfile(fullfile(adir0, c1.images.axpot)), 'link: file gambar HW tak ada: %s', c1.images.axpot);
fprintf('[ok] link kurva HW: komentar c001 -> %s + gambar %s\n', c1.curve, c1.images.axpot);

% --- SIMPAN: 1 truth (_potdata: garis+label+netslip; _comments) ---
i_click(h.tabKom,'💾 Save');
assert(isfile(potP) && isfile(comP), 'truth tak tertulis');
rd = pivcore.io.pab4PotData.read(df1);
[ln,~] = pivcore.io.pab4PotData.findLine(rd, h.activePsgId);
assert(~isempty(ln) && numel(ln.curves)==nrec, '_potdata kurva tak lengkap');
nLab = 0; for k=1:numel(ln.curves), if ~isempty(pivcore.pot.labels.parseLabel(ln.curves{k}.label)), nLab=nLab+1; end; end
assert(nLab==3, 'label tak tersimpan di _potdata (=%d)', nLab);
assert(numel(ln.netslip)==2, 'netslip entri bukan 2');
cd = pivcore.io.pab4Comments.read(df1);
assert(numel(cd.comments)==1, '_comments tak tersimpan');
fprintf('[ok] 1 truth tersimpan: _potdata(%d kurva,%d label,%d netslip) + _comments(%d)\n', ...
    numel(ln.curves), nLab, numel(ln.netslip), numel(cd.comments));

% --- EXPORT CLAUDE + balasan inline ---
i_click(h.tabKom,'📤 Export untuk Claude (folder + report)');
assert(isfile(fullfile(claudeRoot,'READ_ME_CLAUDE.md')), 'READ_ME_CLAUDE.md tak dibuat');
% curves.json: DATA NUMERIK kurva HW teridentifikasi (HW-1/HW-2/FFW = 3)
curvP = pivcore.io.pab4Curves.dataPath(df1);
assert(isfile(curvP), 'curves.json tak ditulis saat export');
cv = jsondecode(fileread(curvP));
Cc = cv.curves; if ~iscell(Cc), Cc = num2cell(Cc); end
labs = cellfun(@(c) char(c.label), Cc, 'UniformOutput', false);
assert(numel(Cc)==3, 'curves.json bukan 3 kurva teridentifikasi (=%d)', numel(Cc));
assert(any(strcmp(labs,'HW-1')) && any(strcmp(labs,'HW-2')), 'label HW tak lengkap di curves.json');
hw1 = Cc{find(strcmp(labs,'HW-1'),1)};
assert(numel(hw1.values)==h.nF, 'values HW-1 bukan nF (%d vs %d)', numel(hw1.values), h.nF);
fprintf('[ok] curves.json: 3 kurva teridentifikasi + |V| per-frame (HW-1 %d titik) + %d netslip\n', ...
    numel(hw1.values), numel(cv.netslip));
cc = pivcore.io.pab4Comments.commentStruct(5,h.activePsgId,'HW-1','interpretasi sesar','CLAUDE');
[cd,~] = pivcore.io.pab4Comments.add(cd, cc); pivcore.io.pab4Comments.write(df1, cd);
i_click(h.tabKom,'↻ Balasan');
h = guidata(fig);
R = get(h.tblComments,'Data');
assert(any(cellfun(@(s) contains(char(s),'[CLAUDE]:'), R(:,4))), 'balasan [CLAUDE] tak inline');
fprintf('[ok] export Claude + balasan inline [CLAUDE]: (total %d komentar)\n', size(R,1));

% --- TAB ④ PRODUKSI GAMBAR: produksi velmag+shear+axpot utk komentar c001 ---
h = guidata(fig);
set(h.tg,'SelectedTab',h.tabShot);
h.shotTarget = 'c001';
nums = h.shotHWnums; if ~isempty(nums), set(h.lstShotHW,'Value',1:numel(nums)); end
set(h.edShotFrame,'String', num2str(h.frame));
guidata(fig, h);
i_click(h.tabShot,'📸 Produksi gambar untuk komentar ini');
h = guidata(fig);
[cc1,~] = pivcore.io.pab4Comments.find(h.cdoc, 'c001');
assert(isstruct(cc1) && isfield(cc1,'assets'), 'komentar c001 tak punya assets');
nass = numel(cc1.assets);
cdir = pivcore.io.pab4Shots.commentDir(df1, 'c001');
nfile = 0;
for a = 1:nass
    as = cc1.assets{a};
    assert(~isempty(as.fingerprint), 'asset %d fingerprint kosong', a);
    if isfile(fullfile(cdir, as.file)), nfile = nfile + 1; end
end
assert(nass >= 3, 'asset tercatat < 3 (=%d)', nass);
assert(nfile >= 3, 'PNG terproduksi < 3 (=%d dari %d)', nfile, nass);
manP = fullfile(pivcore.io.pab4Comments.assetDir(df1), 'manifest.json');
assert(isfile(manP), 'manifest CLim tak ditulis');
fprintf('[ok] tab ④: %d gambar ber-spec diproduksi (%d PNG ada) + manifest CLim\n', nass, nfile);

% --- BASI: ubah data (unassign HW-2) -> daftar asset tab ④ menandai ⚠BASI ---
h = guidata(fig); h.recs = pivcore.pot.hwLabel.unassign(h.recs, rB); guidata(fig, h);
idxC = find(strcmp(h.shotComIds,'c001'), 1);
if ~isempty(idxC), set(h.lstShotCom,'Value',idxC); end
cbPick = get(h.lstShotCom,'Callback'); feval(cbPick, h.lstShotCom, struct());
h = guidata(fig);
assetStr = get(h.lstShotAssets,'String');
assert(any(cellfun(@(s) contains(char(s),'BASI'), assetStr)), ...
    'perubahan data tak ditandai BASI di tab ④');
fprintf('[ok] tab ④: data diubah (unassign HW-2) -> asset ditandai ⚠BASI\n');
% pulihkan label HW-2 supaya bagian reload di bawah tetap konsisten
h = guidata(fig); h.recs = pivcore.pot.hwLabel.assign(h.recs, rB, 'HW', 2); guidata(fig, h);

% --- EXPORT bundel per-komentar (comments/<id>/comment.json) ---
i_click(h.tabShot,'📤 Bundel komentar');
assert(isfile(fullfile(cdir,'comment.json')), 'comments/c001/comment.json tak ditulis');
fprintf('[ok] tab ④: export bundel per-komentar (comment.json per folder)\n');

% --- PAKET CERITA HW: hw_story.json + gambar per-HW (HW = titik ikat) ---
i_click(h.tabShot,'📖 Paket cerita HW');
storyP = pivcore.io.pab4Curves.storyPath(df1);
assert(isfile(storyP), 'hw_story.json tak ditulis');
sd = jsondecode(fileread(storyP));
HWs = sd.hangingWalls; if ~iscell(HWs), HWs = num2cell(HWs); end
assert(numel(HWs)==2, 'hw_story bukan 2 HW (=%d)', numel(HWs));
hwLabs = cellfun(@(x) char(x.label), HWs, 'UniformOutput', false);
assert(any(strcmp(hwLabs,'HW-1')) && any(strcmp(hwLabs,'HW-2')), 'HW-1/HW-2 tak lengkap di hw_story');
hw1 = HWs{find(strcmp(hwLabs,'HW-1'),1)};
adir = pivcore.io.pab4Comments.assetDir(df1);
assert(~isempty(hw1.image) && isfile(fullfile(adir, hw1.image)), 'gambar HW-1 tak ada: %s', hw1.image);
assert(numel(hw1.curve.values)==h.nF, 'values HW-1 bukan nF di hw_story');
assert(~isempty(hw1.comments), 'komentar HW-1 tak tertaut di hw_story');
fprintf('[ok] paket cerita HW: %d HW, HW-1 punya gambar + %d komentar tertaut\n', ...
    numel(HWs), numel(hw1.comments));

% --- TAB ⑤ KOMPOSER CERITA: gambar axPOT bebas dgn layer di-toggle ---
h = guidata(fig);
set(h.tg,'SelectedTab',h.tabStory);
set(h.chkStoryFrame,'Value',1);                 % nyalakan garis vertikal frame
set(h.edStoryFrame,'String', num2str(max(1,round(h.nF/2))));
set(h.chkStoryRaw,'Value',0);                   % sembunyikan kurva mentah (layer off)
set(h.edStoryName,'String','cerita uji 1');     % nama tak-aman -> di-sanitasi
guidata(fig, h);
i_click(h.tabStory,'📸 Produksi gambar cerita (axPOT)');
sdir = pivcore.io.pab4Shots.storyDir(df1);
assert(isfolder(sdir), 'folder story/ tak dibuat');
assert(isfile(fullfile(sdir,'cerita_uji_1.png')), 'gambar cerita PNG tak ditulis (nama tersanitasi)');
assert(isfile(fullfile(sdir,'cerita_uji_1.json')), 'sidecar spec cerita tak ditulis');
sj = jsondecode(fileread(fullfile(sdir,'cerita_uji_1.json')));
assert(sj.spec.hwLabel==1 && sj.spec.pointsAllHW==1, 'spec cerita: layer HW#/titik tak tercatat');
assert(isfinite(sj.spec.frameLine), 'spec cerita: frameLine tak tercatat');
h = guidata(fig);
ls5 = get(h.lstStory,'String');
assert(any(cellfun(@(s) contains(char(s),'cerita_uji_1.png'), ls5)), 'gambar cerita tak muncul di daftar');
fprintf('[ok] tab ⑤: gambar cerita "cerita_uji_1.png" + sidecar (layer HW#/titik/frame tercatat)\n');
% BASI: ubah data lalu produksi gambar lain -> memicu refresh -> gambar lama ⚠BASI
h = guidata(fig); h.recs = pivcore.pot.hwLabel.unassign(h.recs, rB); guidata(fig, h);
set(h.edStoryName,'String','cerita uji 2'); guidata(fig, h);
i_click(h.tabStory,'📸 Produksi gambar cerita (axPOT)');   % memicu i_refreshStoryTab
h = guidata(fig); ls5b = get(h.lstStory,'String');
assert(any(cellfun(@(s) contains(char(s),'BASI'), ls5b)), 'cerita lama tak ditandai BASI saat data berubah');
h = guidata(fig); h.recs = pivcore.pot.hwLabel.assign(h.recs, rB, 'HW', 2); guidata(fig, h);
% hapus SEMUA gambar cerita
h = guidata(fig); set(h.lstStory,'Value',1:numel(h.storyFiles)); guidata(fig, h);
i_click(h.tabStory,'🗑 Hapus gambar terpilih');
assert(~isfile(fullfile(sdir,'cerita_uji_1.png')), 'gambar cerita tak terhapus');
assert(~isfile(fullfile(sdir,'cerita_uji_2.png')), 'gambar cerita kedua tak terhapus');
fprintf('[ok] tab ⑤: deteksi ⚠BASI + hapus gambar cerita\n');

% --- 1 TRUTH lintas-tab: reload exp -> seed pulihkan label dari _potdata ---
pivui.pab4Shell.loadExperiment(fig, 1);   % muat ulang exp1
h = guidata(fig);
nums2 = pivcore.pot.hwLabel.hwNumbers(h.recs);
assert(isequal(sort(nums2(:)'),[1 2]), 'label tak ter-seed dari _potdata saat reload (=%s)', mat2str(nums2));
assert(contains(h.seedMsg,'_potdata'), 'seed bukan dari _potdata (=%s)', h.seedMsg);
fprintf('[ok] reload: label ter-seed dari _potdata (1 truth) — %s\n', h.seedMsg);

fprintf('==== PAB4 SEMUA LULUS ✓ ====\n');
end


% ---------------------------------------------------------------------
function i_assign(fig, tab, r, ty, num)
    h = guidata(fig);
    h.selRows = r; guidata(fig, h);
    tl = {'HW','F','F0','FFW'}; v = find(strcmp(tl,ty),1);
    set(h.popType,'Value',v); cb=get(h.popType,'Callback'); cb(h.popType,[]);
    if isfinite(num), set(h.edNum,'String',num2str(num)); end
    i_click(tab,'✔ Assign');
end

function i_click(parent, str)
    b = findobj(parent,'Style','pushbutton','String',str);
    assert(~isempty(b), 'tombol "%s" tak ada', str);
    cb = get(b(1),'Callback'); if ~isempty(cb), feval(cb, b(1), struct()); end
end

function s = i_src(h, r)
    s = line('Parent',h.axPOT,'XData',[1 2],'YData',[1 2],'UserData',r,'Visible','off');
end

function i_close(fig), try, if ishghandle(fig), delete(fig); end, catch, end, end
function i_rm(f), try, if ~isempty(f)&&isfile(f), delete(f); end, catch, end, end
function i_rmDir(d), try, if ~isempty(d)&&isfolder(d), rmdir(d,'s'); end, catch, end, end
function i_cleanup(files, d), for k=1:numel(files), i_rm(files{k}); end, i_rmDir(d); end
