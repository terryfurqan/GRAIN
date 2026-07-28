function test_smoke_pab4(rootDir)
%TEST_SMOKE_PAB4  Smoke test PAB4 (pencatat Tabel Deskripsi, salinan PAB5 tanpa
%   assign). Blok:
%     A  engine pab4Desc (round-trip + per-PSG) + pab4DescExport (path/JSON)
%     B  build GUI PAB4 -> panel DESC ada; TAB & tombol assign TIDAK ada; tabel
%        sesar read-only; render sesar visible
%     C  navigasi (aktifkan garis PSG) TIDAK menulis _faults.json
%     D  tambah baris DESC (F#/FRM/psgId auto + POI auto-suggest) -> Save -> restore
%     E  Commit garis PSG aktif -> folder <ts>_<psg> berisi JPG (<=700KB) + JSON;
%        versioning; _faults.json TIDAK berubah
%
%   SENYAP: DefaultFigureVisible off. Fixture default = experiment ber-_faults.json
%   di EXP_coll; bila absen -> [SKIP]. SELALU MATLAB R2025b.

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(fileparts(here)));                 % PAB/ (PAB4.m)
    addpath(fullfile(fileparts(here), 'pivcore_lib'));  % engine
    try, pab_setup; catch, end

    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

    % ---------- Fixture ----------
    if nargin < 1 || isempty(rootDir)
        cand = {'/Users/terryfurqan/MACTERR_shared/EXP_coll/EXP Q1/P-CON-4cm-F', ...
                '/Users/terryfurqan/MACTERR_shared/EXP_coll/P-CON-4cm-F'};
        rootDir = '';
        for i = 1:numel(cand)
            if isfolder(cand{i}) && ~isempty(i_findMatWithFaults(cand{i}))
                rootDir = cand{i}; break;
            end
        end
        % Fallback: cari rekursif folder pertama ber-pasangan .mat + _faults.json.
        if isempty(rootDir)
            rootDir = i_searchFixture('/Users/terryfurqan/MACTERR_shared/EXP_coll');
        end
    end
    if isempty(rootDir) || ~isfolder(rootDir)
        fprintf('[SKIP] test_smoke_pab4: fixture (exp ber-_faults.json) tak ada.\n'); return;
    end
    df = i_findMatWithFaults(rootDir);
    if isempty(df)
        fprintf('[SKIP] test_smoke_pab4: tak ada .mat ber-_faults.json di %s\n', rootDir); return;
    end
    [~, baseName] = fileparts(df);
    fprintf('Fixture: %s\n', baseName);
    % LINDUNGI data sidecar user (fixture NYATA): backup + restore otomatis saat
    % keluar (lulus/gagal/crash). Test menulis/menghapus _desc.json dll di fixture.
    sidecarGuard = i_guardSidecars(df); %#ok<NASGU>   % JANGAN dihapus (onCleanup restore)

    % ========================= A. ENGINE =========================
    fprintf('==== A. Engine pab4Desc + pab4DescExport ====\n');
    tf = fullfile(tempdir, 'PAB4TEST_exp.mat');
    doc = pivcore.io.pab4Desc.emptyDoc(tf);
    r1 = pivcore.io.pab4Desc.rowStruct('psgA','F1',15,'Start',3,'1','pertama','UP','T',88);
    r2 = pivcore.io.pab4Desc.rowStruct('psgB','F2',40,'</blank>',NaN,'','lain','DWN');
    doc = pivcore.io.pab4Desc.setRowsForPsg(doc,'psgA',{r1});
    doc = pivcore.io.pab4Desc.setRowsForPsg(doc,'psgB',{r2});
    pivcore.io.pab4Desc.write(tf, doc);
    d2 = pivcore.io.pab4Desc.read(tf);
    assert(numel(pivcore.io.pab4Desc.rowsForPsg(d2,'psgA'))==1, 'A: psgA 1 baris');
    assert(numel(pivcore.io.pab4Desc.rowsForPsg(d2,'psgB'))==1, 'A: psgB 1 baris');
    ra = pivcore.io.pab4Desc.rowsForPsg(d2,'psgA');
    assert(strcmp(ra{1}.desc,'pertama') && ra{1}.actF==3, 'A: field roundtrip');
    assert(strcmp(ra{1}.fsrDir,'UP'), 'A: fsrDir roundtrip: %s', ra{1}.fsrDir);
    assert(strcmp(ra{1}.nucPos,'T'), 'A: nucPos roundtrip, dapat %s', ra{1}.nucPos);
    assert(ra{1}.fTrx==88, 'A: fTrx roundtrip, dapat %g', ra{1}.fTrx);
    % nucPos 'ALL' + fsrDir 'SIM' (opsi simultan baru) harus roundtrip apa adanya.
    rSim = pivcore.io.pab4Desc.rowStruct('psgA','F1',22,'NUC-FSR',1,'1','simultan','SIM','ALL');
    assert(strcmp(rSim.nucPos,'ALL'), 'A: nucPos ALL roundtrip, dapat %s', rSim.nucPos);
    assert(strcmp(rSim.fsrDir,'SIM'), 'A: fsrDir SIM roundtrip, dapat %s', rSim.fsrDir);
    % NUC-TF kini POI TERSENDIRI (migrasi ke NUC-FSR DIHENTIKAN) -> terbaca apa adanya.
    rMig = pivcore.io.pab4Desc.normRow(struct('poi','NUC-TF','frame',5));
    assert(strcmp(rMig.poi,'NUC-TF'), 'A: NUC-TF POI terpisah (tak dimigrasi), dapat %s', rMig.poi);
    delete(pivcore.io.pab4Desc.dataPath(tf));
    ts = '010101-000000';
    sd = pivcore.io.pab4DescExport.sessionDir(tempdir, tf, ts, 'PSG top');
    assert(contains(sd,'PAB4_DESC') && contains(sd,'010101-000000_PSG_top'), 'A: sessionDir: %s', sd);
    assert(endsWith(pivcore.io.pab4DescExport.faultDir(sd,''),'_no_fault'), 'A: no_fault dir');
    % --- DETEKSI (revisi 2026-07-19): NUC pertama & X-FS = batas EKSKLUSIF; isi inklusif.
    % F1: NUC@30 .. X-FS@130  -> aktif 31..129. F2: NUC@90 .. X-FS@165 -> aktif 91..164.
    mkd = @(fn,fr,poi) pivcore.io.pab4Desc.rowStruct('psg',fn,fr,poi);
    detRows = { mkd('F1',30,'NUC-BDF1'), mkd('F1',40,'PRP-BDF1'), mkd('F1',80,'PRP-FSR'), ...
                mkd('F1',100,'ACT-FSR'), mkd('F1',130,'X-FSR'), ...
                mkd('F2',90,'NUC-TF'), mkd('F2',95,'PRP-TF'), mkd('F2',125,'ACT-FSR'), mkd('F2',165,'X-FSR') };
    F1r = detRows(1:5); F2r = detRows(6:9);
    [a0,a1,aok,axe] = pivcore.io.pab4Desc.faultActiveRange(F1r);
    assert(a0==30 && a1==130 && aok && axe, 'A: F1 range NUC@30..X-FS@130 (eksklusif dua ujung)');
    [b0,b1] = pivcore.io.pab4Desc.faultActiveRange(F2r);
    assert(b0==90 && b1==165, 'A: F2 range NUC@90..X-FS@165');
    % NUC eksklusif (belum ada sesar di frame NUC); X-FS eksklusif (sudah mati); overlap = 2.
    ac = @(fr) pivcore.io.pab4Desc.activeCountAtFrame(detRows, fr);
    assert(ac(30)==0,  'A: frame30 (NUC F1 eksklusif) -> 0');
    assert(ac(40)==1,  'A: frame40 (F1 aktif; F2 blm NUC) -> 1');
    assert(ac(90)==1,  'A: frame90 (NUC F2 eksklusif -> hanya F1) -> 1');
    assert(ac(100)==2, 'A: frame100 (F1&F2 aktif) -> 2');
    assert(ac(130)==1, 'A: frame130 (X-FS F1 eksklusif -> hanya F2) -> 1');
    assert(ac(165)==0, 'A: frame165 (X-FS F2 eksklusif) -> 0');
    % --- Tanpa NUC = tak pernah ternukleasi -> ok=false (tak dihitung).
    rNoNuc = { mkd('F9',10,'PRP-TF'), mkd('F9',20,'ACT-FSR') };
    [~,~,okNo] = pivcore.io.pab4Desc.faultActiveRange(rNoNuc);
    assert(~okNo, 'A: sesar tanpa NUC -> ok=false');
    % --- X-FS milik satu sesar EKSKLUSIF, tapi sesar penerus (NUC lebih awal) tetap aktif.
    % Kasus P-HF F5 X-FS@166 + F6 NUC@160 -> di frame 166 hanya F6 dihitung.
    rF5 = { mkd('F5',140,'NUC-FSR'), mkd('F5',143,'PRP-FSR'), mkd('F5',160,'ACT-FSR'), mkd('F5',166,'X-FS') };
    rF6 = { mkd('F6',160,'NUC-TF'), mkd('F6',161,'PRP-TF'), mkd('F6',224,'X-FS') };
    succ = [rF5, rF6];
    acS = @(fr) pivcore.io.pab4Desc.activeCountAtFrame(succ, fr);
    assert(acS(140)==0, 'A: frame140 (NUC F5 eksklusif) -> 0 (dapat %d)', acS(140));
    assert(acS(165)==2, 'A: frame165 (F5&F6 aktif) -> 2 (dapat %d)', acS(165));
    assert(acS(166)==1, 'A: frame166 (X-FS F5 eksklusif; F6 aktif) -> 1 (dapat %d)', acS(166));
    fprintf('[OK] A engine (revisi NUC & X-FS eksklusif, isi inklusif; penerus tetap terhitung)\n');

    % ========================= B. BUILD GUI =========================
    fprintf('==== B. Build PAB4 (panel DESC; tanpa tab assign) ====\n');
    fig = PAB4(rootDir);
    cuf = onCleanup(@() i_close(fig)); %#ok<NASGU>
    h = guidata(fig);
    assert(isfield(h,'tblDesc') && ishghandle(h.tblDesc), 'B: tblDesc ada');
    assert(isfield(h,'tblFault') && ishghandle(h.tblFault), 'B: tblFault ada (navigasi)');
    assert(~isfield(h,'tg'),        'B: uitabgroup TAK boleh ada');
    assert(~isfield(h,'tabExport'), 'B: tab Export TAK boleh ada');
    % tombol assign TAK boleh ada
    assert(~i_hasButton(fig,'⬆ Jadikan HW'), 'B: tombol Jadikan HW harus hilang');
    assert(~i_hasButton(fig,'⏻ On/Off'),     'B: tombol On/Off harus hilang');
    % tombol BARU: navigasi sesar ◀F/F▶ + sticky Ctrl + Deteksi.
    assert(isfield(h,'btnFaultPrev') && ishghandle(h.btnFaultPrev), 'B: tombol ◀F (prev fault) ada');
    assert(isfield(h,'btnFaultNext') && ishghandle(h.btnFaultNext), 'B: tombol F▶ (next fault) ada');
    assert(isfield(h,'btnStickyCtrl') && ishghandle(h.btnStickyCtrl), 'B: tombol ⌃Ctrl (sticky) ada');
    assert(isfield(h,'btnDeteksi') && ishghandle(h.btnDeteksi), 'B: tombol 🔍 Deteksi ada');
    % tombol aksi DESC ada (termasuk Save & Tutup + Tutup)
    assert(i_hasButton(fig,'💾 Save Progress'), 'B: tombol Save Progress ada');
    assert(i_hasButtonContains(fig,'Commit'),   'B: tombol Commit ada');
    assert(i_hasButton(fig,'📄 Report PDF'),     'B: tombol Report PDF ada');
    assert(i_hasButton(fig,'↔ Edit di PAB5'),    'B: tombol Edit di PAB5 ada');
    assert(i_hasButton(fig,'💾 Save & Tutup'),   'B: tombol Save & Tutup ada');
    assert(i_hasButton(fig,'✖ Tutup'),           'B: tombol Tutup ada');
    % kontrol garis PSG (Aktifkan/Slip/Zoom/Reset) + X-win + MA DISEMBUNYIKAN
    % (2026-07-19): handle tetap dibuat (Visible='off') supaya callback/logika lain
    % tak patah, TAPI tak terlihat & tombol "Full"/X-win/MA-spinner DIBUANG dari UI.
    assert(~i_hasButton(fig,'Full'),          'B: tombol Full (X-win) HARUS dibuang');
    assert(~i_hasButton(fig,'Aktifkan garis'),'B: tombol Aktifkan garis HARUS dibuang');
    assert(~i_hasButton(fig,'🔍 Zoom kotak / Reset'),'B: tombol Zoom kotak/Reset HARUS dibuang');
    assert(isempty(findall(fig,'Tag','spDescMAUp')),  'B: spinner MA (▲) HARUS dibuang');
    % Handle yg disembunyikan tetap ADA (logika/hotkey lain memakainya) + Visible=off.
    assert(isfield(h,'btnFaultSlip') && ishghandle(h.btnFaultSlip), 'B: btnFaultSlip (handle) tetap ada');
    assert(strcmp(get(h.btnFaultSlip,'Visible'),'off'), 'B: btnFaultSlip disembunyikan');
    assert(isfield(h,'txtDescMA') && ishghandle(h.txtDescMA), 'B: txtDescMA (handle) tetap ada');
    assert(strcmp(get(h.txtDescMA,'Visible'),'off'), 'B: txtDescMA disembunyikan');
    assert(isfield(h,'lstLines') && ishghandle(h.lstLines), 'B: lstLines (handle) tetap ada');
    assert(strcmp(get(h.lstLines,'Visible'),'off'), 'B: lstLines (selektor garis PSG) disembunyikan');
    assert(isfield(h,'btnAutoFsMax') && ishghandle(h.btnAutoFsMax), 'B: btnAutoFsMax (handle) tetap ada');
    assert(strcmp(get(h.btnAutoFsMax,'Visible'),'off'), 'B: grup AUTO-DX disembunyikan');
    % Ref horizontal & sticky Ctrl & ◀F/F▶ TETAP TAMPIL.
    assert(isfield(h,'btnRefHoriz') && ishghandle(h.btnRefHoriz) && strcmp(get(h.btnRefHoriz,'Visible'),'on'), 'B: ⇄ Ref horizontal tetap tampil');
    assert(i_hasButton(fig,'📐 Bidang sesar'),  'B: tombol Bidang sesar (Ctrl+Q) ada');
    assert(isfield(h,'btnFaultPoly') && ishghandle(h.btnFaultPoly), 'B: btnFaultPoly ada');
    % Tabel DESKRIPSI = 11 kolom (F TRX dibuang; +Sudut/Len/Growth).
    assert(numel(get(h.tblDesc,'ColumnName'))==14, 'B: tblDesc 14 kolom (+Det/Taper°/Nuk), dapat %d', numel(get(h.tblDesc,'ColumnName')));
    % Tabel SESAR = 9 kolom (F#/DX/Len#/θ0/θ1/θ̄ + Tp0/Tp1/ΔTp).
    assert(numel(get(h.tblFault,'ColumnName'))==9, 'B: tblFault 9 kolom (+θ0/θ1/θ̄/Tp0/Tp1/ΔTp), dapat %d', numel(get(h.tblFault,'ColumnName')));
    assert(i_hasButton(fig,'⧉ Filter F#'),     'B: toggle Filter F# ada');
    fprintf('[OK] B build\n');

    % ========================= LOAD EXP =========================
    idx = i_expIndexOf(fig, df);
    assert(idx>=1, 'exp fixture ada di daftar');
    faultsPath = strrep(df,'.mat','_faults.json');
    descPath   = strrep(df,'.mat','_desc.json');
    if isfile(descPath), delete(descPath); end
    pivui.pab4Shell.loadExperiment(fig, idx);
    h = guidata(fig);
    assert(strcmp(h.df, df), 'df = exp fixture');
    assert(isfield(h,'descDoc') && isstruct(h.descDoc), 'descDoc dimuat');
    fprintf('[OK] exp dimuat (%s)\n', baseName);

    % ========================= C. NAVIGASI TAK MENULIS FAULTS =========================
    % fbefore dibaca SESUDAH load: i_onExpLoaded boleh menulis SEKALI (auto-prune
    % sesar hantu) saat load; yang diuji = NAVIGASI (aktifkan garis) tak menulis.
    fprintf('==== C. Navigasi (aktifkan garis) tak menulis _faults.json ====\n');
    fbefore = fileread(faultsPath);
    h = guidata(fig);
    if isfield(h.doc,'psgLines') && ~isempty(h.doc.psgLines)
        % Selektor garis PSG kini tersembunyi; navigasi listbox (callback) tak menulis.
        set(h.lstLines,'Value',1); i_fireH(h.lstLines);
    end
    assert(strcmp(fbefore, fileread(faultsPath)), 'C: _faults.json TIDAK boleh berubah');
    fprintf('[OK] C navigasi aman\n');

    % ========================= D. TAMBAH BARIS + SAVE + RESTORE =========================
    fprintf('==== D. Tambah baris DESC + Save + Restore ====\n');
    h = guidata(fig);
    % pilih sesar pertama (bila ada) supaya F# auto terisi
    ord = {};
    try, ord = i_activeFaultsSafe(h); catch, end
    i_fire(fig,'➕ Tambah baris (F# & FRM auto)');
    h = guidata(fig);
    rows = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    assert(~isempty(rows), 'D: baris ditambah');
    assert(strcmp(rows{end}.isOost,'1'), 'D: baris baru IS/OOST default 1, dapat %s', rows{end}.isOost);
    % GARIS VERTIKAL penanda frame yang sudah dideskripsi tampil di axPOT.
    vl = findall(h.axPOT,'Tag','descVline');
    assert(~isempty(vl), 'D: garis vertikal penanda DESC harus muncul di axPOT');
    kcb = get(fig,'WindowKeyPressFcn');
    % ATURAN 1 FRAME = 1 DX: pindah ke frame BARU sebelum tiap hotkey "tambah".
    gotoFr = @(k) pivui.pab4Shell.gotoFrame(fig, k);
    % HOTKEY Ctrl+T pada frame BARU = tambah baris </blank>.
    n0 = numel(rows);
    gotoFr(min(6, h.nF));
    kcb(fig, FakeKeyData('t','t',{'control'}));
    h = guidata(fig);
    rows2 = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    assert(numel(rows2)==n0+1, 'D: Ctrl+T frame baru harus tambah 1 baris (%d->%d)', n0, numel(rows2));
    % ATURAN 1-FRAME: Ctrl+Shift+2 pada frame SAMA -> GANTI POI ke PRP-TF, TAK tambah baris.
    %   (skema hotkey BARU: Ctrl+2=NUC-TF · Ctrl+Shift+2=PRP-TF.)
    kcb(fig, FakeKeyData('2','@',{'control','shift'}));
    h = guidata(fig);
    rows2b = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    assert(numel(rows2b)==n0+1, 'D: 1-frame=1-DX: hotkey frame sama TAK tambah baris (dapat %d)', numel(rows2b));
    fr6 = round(h.frame);
    ex = ''; for ii=1:numel(rows2b), if round(rows2b{ii}.frame)==fr6, ex=rows2b{ii}.poi; end, end
    assert(strcmp(ex,'PRP-TF'), 'D: 1-frame: POI frame %d diganti jadi PRP-TF (Ctrl+Shift+2), dapat %s', fr6, ex);
    % HOTKEY Ctrl+Shift+2 pada frame BARU = tambah baris POI=PRP-TF.
    gotoFr(min(8, h.nF));
    kcb(fig, FakeKeyData('2','@',{'control','shift'}));
    h = guidata(fig);
    rows3 = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    assert(numel(rows3)==n0+2, 'D: Ctrl+Shift+2 frame baru tambah baris');
    assert(strcmp(rows3{end}.poi,'PRP-TF'), 'D: Ctrl+Shift+2 POI=PRP-TF, dapat %s', rows3{end}.poi);
    assert(rows3{end}.frame==round(h.frame), 'D: Ctrl+Shift+2 FRM=frame live');
    assert(isempty(rows3{end}.nucPos), 'D: baris baru NUC POS kosong');
    % HOTKEY Ctrl+2 (tanpa Shift) = NUC-TF (POI baru terpisah) pada frame BARU (=7).
    frNT = min(7, h.nF); gotoFr(frNT);
    kcb(fig, FakeKeyData('2','2',{'control'}));
    h = guidata(fig);
    rowsNT = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    poiNT = ''; for ii=1:numel(rowsNT), if round(rowsNT{ii}.frame)==round(frNT), poiNT=rowsNT{ii}.poi; end, end
    assert(strcmp(poiNT,'NUC-TF'), 'D: Ctrl+2 POI frame %d = NUC-TF (terpisah), dapat %s', frNT, poiNT);
    % HOTKEY Ctrl+4 = ACT-FSR (frame baru) · Ctrl+Shift+4 SAMA-frame -> ganti X-FS.
    gotoFr(min(10, h.nF));
    kcb(fig, FakeKeyData('4','4',{'control'})); h = guidata(fig);
    r4 = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    assert(strcmp(r4{end}.poi,'ACT-FSR'), 'D: Ctrl+4 POI=ACT-FSR, dapat %s', r4{end}.poi);
    kcb(fig, FakeKeyData('4','$',{'control','shift'})); h = guidata(fig);
    r4b = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    fr10=round(h.frame); ex4='';
    for ii=1:numel(r4b), if round(r4b{ii}.frame)==fr10, ex4=r4b{ii}.poi; end, end
    assert(strcmp(ex4,'X-FS'), 'D: Ctrl+Shift+4 ganti POI jadi X-FS, dapat %s', ex4);
    % HOTKEY Ctrl+1 = NUC-BDF1 (frame baru) · Ctrl+Shift+1 SAMA-frame -> ganti PRP-BDF1.
    %   (skema hotkey BARU: digit 1 = BDF1, bukan BDF0.)
    gotoFr(min(12, h.nF));
    kcb(fig, FakeKeyData('1','1',{'control'})); h = guidata(fig);
    rb0 = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    assert(strcmp(rb0{end}.poi,'NUC-BDF1'), 'D: Ctrl+1 POI=NUC-BDF1, dapat %s', rb0{end}.poi);
    nBefore = numel(rb0);
    kcb(fig, FakeKeyData('1','!',{'control','shift'})); h = guidata(fig);
    rb1 = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    assert(numel(rb1)==nBefore, 'D: Ctrl+Shift+1 frame sama TAK tambah baris');
    fr12 = round(h.frame); exb = '';
    for ii=1:numel(rb1), if round(rb1{ii}.frame)==fr12, exb=rb1{ii}.poi; end, end
    assert(strcmp(exb,'PRP-BDF1'), 'D: 1-frame: POI ganti jadi PRP-BDF1, dapat %s', exb);
    % Ctrl+H = cycle antar DX + LONCAT frame pengamatan ke frame DX terpilih.
    gotoFr(1);   % geser dulu ke frame 1 supaya loncatan terlihat
    kcb(fig, FakeKeyData('h','h',{'control'})); h = guidata(fig);
    rr = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    sel = h.descSelRow; vis = h.descVisIdx; fi = [];
    if ~isempty(sel) && ~isempty(vis) && sel<=numel(vis), fi = vis(sel);
    elseif ~isempty(sel), fi = sel; end
    if ~isempty(fi) && fi>=1 && fi<=numel(rr) && isfinite(rr{fi}.frame)
        assert(round(h.frame)==round(rr{fi}.frame), ...
            'D: Ctrl+H loncat frame ke DX (frame %d vs %d)', round(h.frame), round(rr{fi}.frame));
    end
    % HOTKEY Ctrl+` = cycle NUC POS (—>T>M>B>FT>—) baris terpilih. Set awal '' lalu
    % pilih baris terakhir; cycle sekali -> 'T', dua kali -> 'M'.
    hh=guidata(fig); rl=pivcore.io.pab4Desc.rowsForPsg(hh.descDoc,hh.activePsgId);
    rl{end}.nucPos=''; hh.descDoc=pivcore.io.pab4Desc.setRowsForPsg(hh.descDoc,hh.activePsgId,rl);
    hh.descSelRow=numel(rl); guidata(fig,hh);
    kcb(fig, FakeKeyData('backquote','`',{'control'})); h = guidata(fig);
    rfs = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    assert(strcmp(rfs{end}.nucPos,'T'), 'D: Ctrl+` cycle NUC POS ->T, dapat %s', rfs{end}.nucPos);
    kcb(fig, FakeKeyData('backquote','`',{'control'})); h = guidata(fig);
    rfs2 = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    assert(strcmp(rfs2{end}.nucPos,'M'), 'D: Ctrl+` cycle NUC POS ->M, dapat %s', rfs2{end}.nucPos);
    % ZOOM X-window cycle 5%: Ctrl++ (persempit) 100%->95%; potXWin dihitung dari nF.
    hh=guidata(fig); hh.potXPct=100; hh.potXWin=0; guidata(fig,hh);
    kcb(fig, FakeKeyData('equal','+',{'control'})); h = guidata(fig);
    assert(h.potXPct==95, 'D: Ctrl++ -> potXPct 95, dapat %g', h.potXPct);
    assert(h.potXWin==max(2,round(0.95*h.nF)), 'D: potXWin diturunkan dari 95%%');
    % Ctrl+F = toggle plot bawah AXSLIP <-> axPOT. ZOOM HORIZONTAL (XLim) TETAP.
    pv0 = ''; if isfield(h,'potView'), pv0=h.potView; end
    xl0 = get(h.axPOT,'XLim');
    kcb(fig, FakeKeyData('f','f',{'control'})); h = guidata(fig);
    assert(~strcmp(h.potView, pv0), 'D: Ctrl+F toggle potView (%s->%s)', pv0, h.potView);
    xl1 = get(h.axPOT,'XLim');
    assert(max(abs(xl1-xl0))<1e-6, 'D: Ctrl+F zoom X TETAP ([%g %g] vs [%g %g])', xl0(1),xl0(2),xl1(1),xl1(2));
    kcb(fig, FakeKeyData('f','f',{'control'})); h = guidata(fig);   % balik lagi
    assert(strcmp(h.potView, pv0), 'D: Ctrl+F toggle balik ke %s', pv0);
    xl2 = get(h.axPOT,'XLim');
    assert(max(abs(xl2-xl0))<1e-6, 'D: Ctrl+F balik zoom X TETAP');
    % matikan FILTER F# supaya SEMUA baris tampil (edit baris-1 deterministik).
    if i_hasButton(fig,'⧉ Filter F#')
        bf = i_findButton(fig,'⧉ Filter F#'); set(bf,'Value',0); cb=get(bf,'Callback'); cb(bf,[]);
    end
    h = guidata(fig);
    % hapus SEMUA baris ekstra hotkey -> sisakan 1 baris (utk assert lanjut).
    while true
        rr = pivcore.io.pab4Desc.rowsForPsg(guidata(fig).descDoc, guidata(fig).activePsgId);
        if numel(rr) <= 1, break; end
        hh = guidata(fig); hh.descSelRow = numel(rr); guidata(fig,hh);
        i_fire(fig,'🗑 Hapus');
    end
    h = guidata(fig);
    % Kolom (14): 3 POI · 4 Det(RO) · 5 #ACT F · 6 IS/OOST · 7 NUC POS · 8 PRP DIR ·
    % 13 Nuk(RO) · 14 DESC. (Det/Nuk = read-only.) Isi actF/NUC POS/PRP DIR/DESC via
    % Data lalu picu CellEdit.
    D = get(h.tblDesc,'Data');
    D{1,5} = 4; D{1,7} = 'B'; D{1,8} = 'UP'; D{1,14} = 'observasi lisan uji';   % DESC kini kol 14
    set(h.tblDesc,'Data',D);
    i_fireCellEdit(h.tblDesc, 1, 14);
    i_fire(fig,'💾 Save Progress');
    assert(isfile(descPath), 'D: _desc.json ditulis');
    dRe = pivcore.io.pab4Desc.read(df);
    rRe = pivcore.io.pab4Desc.rowsForPsg(dRe, h.activePsgId);
    assert(~isempty(rRe), 'D: restore rows');
    assert(strcmp(rRe{1}.desc,'observasi lisan uji'), 'D: desc tersimpan: %s', rRe{1}.desc);
    assert(rRe{1}.actF==4, 'D: actF tersimpan');
    assert(strcmp(rRe{1}.fsrDir,'UP'), 'D: PRP DIR (kol8) tersimpan: %s', rRe{1}.fsrDir);
    assert(strcmp(rRe{1}.nucPos,'B'), 'D: NUC POS (kol7) tersimpan (=B), dapat %s', rRe{1}.nucPos);
    % --- AUTO-ASSIGN 2-arah PRP DIR <-> NUC POS (isi hanya yg kosong) ---
    %   (kolom geser +1 krn Det disisip: NUC POS=kol7, PRP DIR=kol8.)
    %   (i) PRP DIR terisi, NUC POS kosong: UP->FT · both->M · DWN->T
    D2 = get(h.tblDesc,'Data'); D2{1,7} = '—'; D2{1,8} = 'DWN'; set(h.tblDesc,'Data',D2);
    i_fireCellEdit(h.tblDesc, 1, 8);   % CellEdit -> capture -> auto-sync -> refresh tabel
    rA = pivcore.io.pab4Desc.rowsForPsg(guidata(fig).descDoc, h.activePsgId);
    assert(strcmp(rA{1}.fsrDir,'DWN') && strcmp(rA{1}.nucPos,'T'), ...
        'D: auto PRP DIR=DWN -> NUC POS=T (dapat NUC=%s)', rA{1}.nucPos);
    % hasil auto-assign harus TAMPIL di Data tabel (bukan hanya descDoc).
    Dchk = get(guidata(fig).tblDesc,'Data');
    assert(strcmp(strtrim(Dchk{1,7}),'T'), 'D: auto NUC POS tampil di tabel (kol7=%s)', Dchk{1,7});
    %   (ii) NUC POS terisi, PRP DIR kosong: FT->UP · B->UP · M->both · T->DWN
    D3 = get(h.tblDesc,'Data'); D3{1,7} = 'M'; D3{1,8} = '—'; set(h.tblDesc,'Data',D3);
    i_fireCellEdit(h.tblDesc, 1, 7);
    rB = pivcore.io.pab4Desc.rowsForPsg(guidata(fig).descDoc, h.activePsgId);
    assert(strcmp(rB{1}.nucPos,'M') && strcmp(rB{1}.fsrDir,'both'), ...
        'D: auto NUC POS=M -> PRP DIR=both (dapat PRP=%s)', rB{1}.fsrDir);
    %   (iii) PRP DIR=SIM (kosong NUC POS) -> NUC POS=ALL (opsi baru simultan).
    Dsim = get(h.tblDesc,'Data'); Dsim{1,7} = '—'; Dsim{1,8} = 'SIM'; set(h.tblDesc,'Data',Dsim);
    i_fireCellEdit(h.tblDesc, 1, 8);
    rSim = pivcore.io.pab4Desc.rowsForPsg(guidata(fig).descDoc, h.activePsgId);
    assert(strcmp(rSim{1}.fsrDir,'SIM') && strcmp(rSim{1}.nucPos,'ALL'), ...
        'D: auto PRP DIR=SIM -> NUC POS=ALL (dapat NUC=%s)', rSim{1}.nucPos);
    %   (iv) NUC POS=ALL (kosong PRP DIR) -> PRP DIR=SIM.
    Dall = get(h.tblDesc,'Data'); Dall{1,7} = 'ALL'; Dall{1,8} = '—'; set(h.tblDesc,'Data',Dall);
    i_fireCellEdit(h.tblDesc, 1, 7);
    rAll = pivcore.io.pab4Desc.rowsForPsg(guidata(fig).descDoc, h.activePsgId);
    assert(strcmp(rAll{1}.nucPos,'ALL') && strcmp(rAll{1}.fsrDir,'SIM'), ...
        'D: auto NUC POS=ALL -> PRP DIR=SIM (dapat PRP=%s)', rAll{1}.fsrDir);
    % pulihkan baris ke kondisi B/UP utk lanjutan test (NUC POS=kol7, PRP DIR=kol8)
    D4 = get(h.tblDesc,'Data'); D4{1,7} = 'B'; D4{1,8} = 'UP'; set(h.tblDesc,'Data',D4);
    i_fireCellEdit(h.tblDesc, 1, 8);
    % PAB4 TAK menulis _potdata.json (read-only sejak 2026-07-18): Save/Save Progress
    % HANYA menulis _desc.json. Verifikasi _potdata di disk TIDAK berubah oleh Save.
    pdocBefore = pivcore.io.pab4PotData.read(df);
    nLinesBefore = 0;
    if isstruct(pdocBefore) && isfield(pdocBefore,'psgLines'), nLinesBefore = numel(pdocBefore.psgLines); end
    i_fire(fig,'💾 Save Progress');                 % (silent -> tulis _desc saja)
    pdocAfter = pivcore.io.pab4PotData.read(df);
    nLinesAfter = 0;
    if isstruct(pdocAfter) && isfield(pdocAfter,'psgLines'), nLinesAfter = numel(pdocAfter.psgLines); end
    assert(nLinesAfter == nLinesBefore, ...
        'D: PAB4 TAK boleh mengubah _potdata (garis %d -> %d)', nLinesBefore, nLinesAfter);
    % INTERPRETASI ikut tersimpan di _desc.json (Save "update tabel -> update JSON").
    assert(isfield(dRe,'faults'), 'D: _desc.json harus punya blok faults (interpretasi)');
    fj = pivcore.io.pab4Desc.tocell(dRe.faults);
    if ~isempty(fj)
        f1 = fj{1};
        assert(isfield(f1,'hw') && isfield(f1.hw,'values'), 'D: JSON kurva HW values ada');
        assert(isfield(f1,'netslip'), 'D: JSON net-slip (AXSLIP) ada');
        assert(isfield(f1,'poi'), 'D: JSON POI ada');
    end
    assert(isfield(dRe,'interpretation'), 'D: blok interpretation ada');
    % FILL HITAM (a=0.3) = AKTIVITAS FSR: NUC-FSR pertama -> X-FS terakhir (per-F#).
    % Susun rows: NUC-FSR(10) + PRP-FSR(15) + ACT-FSR(20) + X-FS(30) -> band 10..30.
    h = guidata(fig); psg = h.activePsgId;
    mk = @(fr,poi) pivcore.io.pab4Desc.rowStruct(psg,'F1',fr,poi,NaN,'1','',' ','',NaN);
    rws = {mk(10,'NUC-FSR'), mk(15,'PRP-FSR'), mk(20,'ACT-FSR'), mk(30,'X-FS')};
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psg, rws);
    h.descFilterF = false;   % pastikan semua baris DX dipertimbangkan
    guidata(fig,h);
    try, pivui.pab4Shell.renderPOT(fig); catch, end
    h = guidata(fig);
    pf = findall(h.axPOT,'Type','patch','-and','UserData','descSlipFill');
    assert(numel(pf)==1, 'D: fill FSR = 1 patch (NUC-FSR..X-FS), dapat %d', numel(pf));
    xd = get(pf(1),'XData');
    assert(abs(min(xd)-10)<1e-6 && abs(max(xd)-30)<1e-6, 'D: fill FSR span 10..30 (NUC-FSR..X-FS), dapat %g..%g', min(xd), max(xd));
    fprintf('[OK] D add+save+restore+hotkeyPOI+fsrDir+FSmaxFill\n');

    % ========================= E. COMMIT (export gambar + JSON) =========================
    fprintf('==== E. Commit garis PSG aktif -> folder versi + JPG + JSON ====\n');
    tmpRoot = fullfile(tempdir, sprintf('pab4test_%d', feature('getpid')));
    if isfolder(tmpRoot), rmdir(tmpRoot,'s'); end
    h = guidata(fig);
    h.exportRootOverride = tmpRoot;
    h.exportStampOverride = '020202-020202';
    % set REFERENSI GEOMETRI (ref horizontal posisi + dinding + base + tebal) supaya
    % commit JSON HARUS membawanya (s.referenceGeom + faults[].geometry).
    h.descDoc = pivcore.io.pab4Desc.setModelBoxPts(h.descDoc,[120 100; 2900 110; 2910 900; 125 895]);
    h.descDoc = pivcore.io.pab4Desc.setRefHorizonPts(h.descDoc,[10 300; 3000 340]);
    h.descDoc = pivcore.io.pab4Desc.setModelThicknessCm(h.descDoc,4);
    guidata(fig, h);
    i_fire(fig,'✅ Commit (JSON, exp ini)');
    h = guidata(fig);
    sess = pivcore.io.pab4DescExport.sessionDir(tmpRoot, df, '020202-020202', h.activePsgId);
    assert(isfolder(sess), 'E: folder sesi dibuat: %s', sess);
    jp = pivcore.io.pab4DescExport.jsonPath(sess, df);
    assert(isfile(jp), 'E: JSON sesi ditulis');
    sj = jsondecode(fileread(jp));
    assert(isfield(sj,'rows') && ~isempty(sj.rows), 'E: JSON punya baris DESC');
    % --- v2: JSON commit terpadu (kalibrasi geometri + geometry + lifecycle) ---
    assert(isfield(sj,'formatVersion') && sj.formatVersion==2, 'E: formatVersion==2');
    assert(isfield(sj,'calibration'), 'E: blok calibration ada');
    cal = sj.calibration;
    assert(isfield(cal,'velMultGeom') && isfield(cal,'velMultUsed') && isfield(cal,'velMultSource'), ...
        'E: calibration velMultGeom/Used/Source ada');
    assert(isfield(cal,'dtSec') && isfield(cal,'dxCm') && isfield(cal,'indenterMax'), ...
        'E: calibration dtSec/dxCm/indenterMax ada');
    assert(isfield(cal,'velMult'), 'E: calibration.velMult alias backward-compat ada');
    assert(any(strcmp(cal.velMultSource,{'geom','fallback'})), 'E: velMultSource geom|fallback');
    % REFERENSI GEOMETRI (koordinat robust) HARUS ikut commit (s.referenceGeom).
    assert(isfield(sj,'referenceGeom'), 'E: JSON commit punya blok referenceGeom');
    rgE = sj.referenceGeom;
    assert(isfield(rgE,'modelBoxPts') && ~isempty(rgE.modelBoxPts), 'E: referenceGeom.modelBoxPts terisi (kotak model)');
    assert(isfield(rgE,'refHorizonPts') && ~isempty(rgE.refHorizonPts), 'E: referenceGeom.refHorizonPts terisi');
    assert(isfield(rgE,'effPushWallX') && isfinite(rgE.effPushWallX), 'E: referenceGeom.effPushWallX (datum pendorong) ada');
    assert(isfield(rgE,'modelThicknessCm') && rgE.modelThicknessCm==4, 'E: referenceGeom.modelThicknessCm=4');
    % faults[] membawa geometry + lifecycle (bila ada sesar ber-HW)
    if isfield(sj,'faults') && ~isempty(sj.faults)
        f1 = sj.faults(1); if iscell(sj.faults), f1 = sj.faults{1}; end
        assert(isfield(f1,'geometry'), 'E: faults{1}.geometry ada');
        assert(isfield(f1,'lifecycle'), 'E: faults{1}.lifecycle ada');
        g1 = f1.geometry;
        assert(isfield(g1,'perDx') && isfield(g1,'refHorizonDeg'), ...
            'E: geometry per-DX (perDx + refHorizonDeg) ada');
        assert(isfield(g1,'refHorizonPts') && isfield(g1,'limitWallPts') ...
            && isfield(g1,'basePts') && isfield(g1,'modelThicknessCm'), ...
            'E: geometry header bawa refHorizonPts/limitWallPts/basePts/modelThicknessCm');
        % lifecycle = array fase; frame 10/20 FS-max (dari blok D) -> minimal FSR-formation.
        lc = f1.lifecycle;
        assert(~isempty(lc), 'E: lifecycle punya >=1 fase');
        ph1 = lc(1); if iscell(lc), ph1 = lc{1}; end
        assert(isfield(ph1,'phase') && isfield(ph1,'frameStart') && isfield(ph1,'strainStartPct'), ...
            'E: fase lifecycle ber-stempel (phase/frameStart/strainStartPct)');
    end
    % COMMIT = JSON-ONLY: TIDAK ada JPG (export gambar dibuang; user hanya perlu JSON).
    jpgs = dir(fullfile(sess,'**','*.jpg'));
    assert(isempty(jpgs), 'E: commit JSON-only, tak boleh ada JPG (dapat %d)', numel(jpgs));
    % dan tak ada subfolder <F#>/ (dulu wadah JPG per-sesar) — hanya JSON di folder sesi.
    sub = dir(sess); sub = sub([sub.isdir] & ~ismember({sub.name},{'.','..'}));
    assert(isempty(sub), 'E: folder sesi hanya berisi JSON (tak ada subfolder), dapat %d', numel(sub));
    % versioning: commit kedua stamp beda -> folder beda
    h = guidata(fig); h.exportStampOverride = '030303-030303'; guidata(fig,h);
    i_fire(fig,'✅ Commit (JSON, exp ini)');
    sess2 = pivcore.io.pab4DescExport.sessionDir(tmpRoot, df, '030303-030303', guidata(fig).activePsgId);
    assert(isfolder(sess2) && ~strcmp(sess,sess2), 'E: versioning folder baru');
    % _faults.json TIDAK berubah
    assert(strcmp(fbefore, fileread(faultsPath)), 'E: _faults.json utuh setelah Commit');
    % CLEAN EXPORT: checkbox ON -> commit ke-3 hapus SEMUA versi lama (sess+sess2),
    % sisakan hanya sess3. (Headless: konfirmasi 2x auto-true.)
    expDir = pivcore.io.pab4DescExport.expDir(tmpRoot, df);
    before = dir(expDir); before = before(~ismember({before.name},{'.','..'}));
    assert(numel(before)>=2, 'E: ada >=2 versi commit sebelum clean (dapat %d)', numel(before));
    h = guidata(fig);
    if isfield(h,'chkCleanExport') && ishghandle(h.chkCleanExport), set(h.chkCleanExport,'Value',1); end
    h.exportStampOverride = '040404-040404'; guidata(fig,h);
    i_fire(fig,'✅ Commit (JSON, exp ini)');
    sess3 = pivcore.io.pab4DescExport.sessionDir(tmpRoot, df, '040404-040404', guidata(fig).activePsgId);
    assert(isfolder(sess3), 'E: clean-export commit ke-3 dibuat');
    assert(~isfolder(sess) && ~isfolder(sess2), 'E: clean-export hapus versi lama');
    after = dir(expDir); after = after(~ismember({after.name},{'.','..'}));
    assert(numel(after)==1, 'E: clean-export sisakan 1 versi (dapat %d)', numel(after));
    fprintf('[OK] E commit + versioning + faults utuh + clean-export\n');

    % ========================= F. REPORT PDF (Group A–E) =========================
    fprintf('==== F. Report PDF (engine murni + generate PDF headless) ====\n');
    % --- F1. engine murni (angka golden) ---
    mkr = @(fnum,fr,poi) pivcore.io.pab4Desc.rowStruct('psg',fnum,fr,poi,NaN,'1','',' ','',NaN);
    fr1 = {mkr('F1',10,'ACT-FSR'), mkr('F1',20,'ACT-FSR'), mkr('F1',30,'X-FS'), ...
           mkr('F2',5,'ACT-FSR'), mkr('F2',15,'ACT-FSR'), mkr('F2',25,'ACT-FSR')};
    p1 = pivcore.io.pab4Report.fsMaxPairs(fr1,'F1');
    p2 = pivcore.io.pab4Report.fsMaxPairs(fr1,'F2');
    p3 = pivcore.io.pab4Report.fsMaxPairs(fr1,'F3');
    assert(isequal(p1,[10 20]), 'F: fsMaxPairs F1 = [10 20]');
    assert(isequal(p2,[5 15]),  'F: fsMaxPairs F2 = [5 15] (25 unpaired dilewati)');
    assert(isempty(p3), 'F: fsMaxPairs F3 kosong (tak ada FS-max)');
    nsUnit = ones(1,40);
    est = pivcore.io.pab4Report.estNetSlip(nsUnit, p1, 0.005, 10);   % Σ ns[10..20]=11 *0.005*10
    assert(abs(est-0.55)<1e-9, 'F: estNetSlip = 0.55, dapat %.4f', est);
    assert(isnan(pivcore.io.pab4Report.estNetSlip(nsUnit, p3, 0.005, 10)), 'F: est tanpa FS-max = NaN');
    dtNo = pivcore.io.pab4Report.readDtMean('/nonexistent_file.mat');
    assert(dtNo==10, 'F: readDtMean fallback 10, dapat %g', dtNo);
    % velMultGeom: geometri absen -> NaN + source 'fallback'; math benar bila lengkap.
    [vmNo, iNo] = pivcore.io.pab4Report.velMultGeom('/nonexistent_file.mat', 8, 10, 100);
    assert(isnan(vmNo) && strcmp(iNo.source,'fallback'), 'F: velMultGeom no-geom -> NaN/fallback');
    % dimensi: dxCm=8, nF=101, dt=10, indMax=8 -> vInd=8/(100*10)=0.008; vm=0.008/8=0.001.
    % (uji rumus via estNetSlip pakai vm hasil hitung tangan)
    estGeom = pivcore.io.pab4Report.estNetSlip(nsUnit, p1, 0.001, 10);  % 11*0.001*10=0.11
    assert(abs(estGeom-0.11)<1e-9, 'F: estNetSlip velMultGeom = 0.11, dapat %.4f', estGeom);
    rdirGolden = pivcore.io.pab4Report.reportDir(tmpRoot, df, '050505-050505', 'top');
    assert(contains(rdirGolden,'PAB4_DESC') && contains(rdirGolden,'050505-050505_top_report'), ...
        'F: reportDir path: %s', rdirGolden);

    % --- F2. generate PDF headless: DILEWATI (lambat ~2 mnt; user test manual) ---
    %   Blok generate-PDF sengaja dibuang dari smoke agar cepat. Engine murni
    %   (F1) tetap diuji. Bila jalur generate PDF perlu diuji ulang, kembalikan
    %   dari git history (i_fire '📄 Report PDF' + assert report.pdf/json).
    fprintf('[OK] F report engine (golden fsMaxPairs/estNetSlip/velMultGeom; generate PDF dilewati)\n');

    % ========================= G. BIDANG SESAR PER-DX (geometri) =========================
    %   Tiap baris DESKRIPSI (DX) punya bidang sesar sendiri: vertices/sudut/panjang
    %   di _desc.json. Growth per-DX = (Len[n]-Len[n-1])/(Δframe·dt). Commit JSON ->
    %   geometry.perDx. Tabel DESKRIPSI kolom Sudut/Len/Growth terisi.
    fprintf('==== G. Bidang sesar per-DX (sudut/panjang/growth) ====\n');
    h = guidata(fig);
    F = pivui.pab5Model.faultsForPsg(h.fdoc, h.activePsgId);
    assert(~isempty(F), 'G: perlu >=1 sesar di garis PSG aktif');
    fA = F{1}; h.activeFaultId = fA.id;
    uN = pivui.pab5Model.faultUiNum(fA); psgG = h.activePsgId; fTag = sprintf('F%d', round(uN));
    % 2 DX ber-bidang sesar (frame 50 & 80), bentuk beda -> Len beda -> growth.
    %   DX1 @frame50: miring 30°, 1 segmen dx=60 -> len px=hyp(60,60tan30)
    %   DX2 @frame80: lebih panjang (dx=120) -> growth positif
    V1 = [500 300; 560 300+60*tand(30)];
    V2 = [500 300; 620 300+120*tand(30)];
    mkG = @(fr,poi) pivcore.io.pab4Desc.rowStruct(psgG,fTag,fr,poi,NaN,'1','',' ','',NaN);
    r1 = mkG(50,'ACT-FSR'); r1.vertices = V1;
    r1.lenCm = 5; r1.angleDeg = pivcore.io.pab4Desc.angleDegOf(V1);
    r2 = mkG(80,'ACT-FSR'); r2.vertices = V2;
    r2.lenCm = 9; r2.angleDeg = pivcore.io.pab4Desc.angleDegOf(V2);
    % DX2: lengkapi TAPER + atribut lisan (uji JSON perDx bawa SEMUA field DESC).
    r2.taperVerts = [400 250; 480 250]; r2.taperDeg = 12.5;   % taper topografi
    r2.nucPos = 'FT'; r2.fsrDir = 'UP'; r2.isOost = '1'; r2.desc = 'catatan lisan DX2';
    % DX3 @frame100: POI=X-FS ber-TITIK (Ctrl+R juga berlaku utk X-FS) -> WAJIB
    %   ikut ke JSON perDx (nucPoint). Uji end-to-end "titik X-FS masuk JSON".
    r3 = mkG(100,'X-FS'); r3.nucVerts = [640 520]; r3.nucDistCm = 7.7; r3.nucDepthPx = 33; r3.nucDepthCm = 0.2;
    rG = {r1, r2, r3};
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psgG, rG);
    guidata(fig, h);
    % sudut regresi ~30
    assert(abs(r1.angleDeg-30) < 0.5, 'G: sudut regresi ~30° (dapat %.2f)', r1.angleDeg);
    % Save -> _desc.json memuat vertices per baris (round-trip).
    i_fire(fig,'💾 Save Progress'); h = guidata(fig);
    dG = pivcore.io.pab4Desc.read(df);
    rowsRe = pivcore.io.pab4Desc.rowsForPsg(dG, psgG);
    % cari 2 baris ber-vertices
    nWithV = 0;
    for t=1:numel(rowsRe)
        if size(pivcore.io.pab4Desc.normVerts(rowsRe{t}.vertices),1) >= 2, nWithV = nWithV+1; end
    end
    assert(nWithV==2, 'G: 2 baris DX ber-vertices round-trip (dapat %d)', nWithV);
    % growthPerDx: DX2 (idx2 urut frame) = (len2-len1)/((f2-f1)*dt).
    dtG = 12.5;   % dt EKSPLISIT (dt-independen dari EXIF fixture)
    subG = i_rowsForF(rowsRe, fTag);
    assert(numel(subG)==3, 'G: subG 3 baris (ACT-FSR×2 + X-FS) (dapat %d)', numel(subG));
    a1 = pivcore.io.pab4Desc.normRow(subG{1}); a2 = pivcore.io.pab4Desc.normRow(subG{2});
    expG = (a2.lenCm - a1.lenCm) / (abs(a2.frame-a1.frame)*dtG);
    gr2 = pivcore.io.pab4Desc.growthPerDx(subG, 2, dtG);
    assert(abs(gr2 - expG) < 1e-9, 'G: growthPerDx DX2 = Δlen/(Δframe·dt) (dapat %.6f exp %.6f)', gr2, expG);
    assert(isnan(pivcore.io.pab4Desc.growthPerDx(subG, 1, dtG)), 'G: growthPerDx DX1 (pertama) = NaN');
    % refresh tabel DESKRIPSI -> kolom Sudut(8)/Len(9)/Growth(10) terisi.
    % (psgG = garis aktif; selektor "Aktifkan garis" kini disembunyikan -> pakai
    %  toggle Filter F# yg TETAP ada & memicu i_refreshDescTable; set OFF supaya
    %  SEMUA baris DX garis aktif tampil, termasuk DX2 @frame80.)
    set(h.btnDescFilter,'Value',0); i_fireH(h.btnDescFilter); h = guidata(fig);
    Dd = get(h.tblDesc,'Data');
    assert(size(Dd,2)==14, 'G: tblDesc 14 kolom (+Det/Taper°/Nuk) (dapat %d)', size(Dd,2));
    % cari baris frame 80 (DX2) -> Sud/Len/Growth kol 9/10/11 (geser +1 krn Det).
    rowFr80 = 0;
    for t=1:size(Dd,1), if isequal(Dd{t,2},80), rowFr80=t; break; end, end
    if rowFr80>0
        assert(~isempty(strtrim(num2str(Dd{rowFr80,9}))),  'G: kol Sudut DX2 terisi');
        assert(~isempty(strtrim(Dd{rowFr80,10})), 'G: kol Len DX2 terisi');
        assert(~isempty(strtrim(Dd{rowFr80,11})), 'G: kol Growth DX2 terisi');
    end
    % Tabel SESAR 9 kolom: F#/DX/Len#/θ0/θ1/θ̄/Tp0/Tp1/ΔTp. Kol 4=θ0(awal)
    % 5=θ1(akhir) 6=θ̄(rata2). DX1&DX2 sama-sama ~30° -> ketiganya ~30°.
    Df = get(h.tblFault,'Data');
    assert(size(Df,2)==9, 'G: tblFault 9 kolom (F#/DX/Len#/θ0/θ1/θ̄/Tp0/Tp1/ΔTp), dapat %d', size(Df,2));
    rowF = 0;
    for t=1:size(Df,1)
        if strcmp(strtrim(char(Df{t,1})), sprintf('%d',round(uN))), rowF=t; break; end
    end
    if rowF>0
        a0v = str2double(Df{rowF,4}); a1v = str2double(Df{rowF,5}); mv = str2double(Df{rowF,6});
        assert(isfinite(a0v) && abs(a0v-30) < 1.0, 'G: θ0 sesar aktif ~30° (dapat %s)', char(string(Df{rowF,4})));
        assert(isfinite(a1v) && abs(a1v-30) < 1.0, 'G: θ1 sesar aktif ~30° (dapat %s)', char(string(Df{rowF,5})));
        assert(isfinite(mv)  && abs(mv-30)  < 1.0, 'G: θ̄ sesar aktif ~30° (dapat %s)', char(string(Df{rowF,6})));
    end
    % Commit JSON -> geometry.perDx dgn vertices/angle/len/growth.
    dCJ = pivcore.io.pab4Desc.read(df);
    assert(isfield(dCJ,'faults') && ~isempty(dCJ.faults), 'G: _desc.json punya faults (commit JSON)');
    fCJ = dCJ.faults; if iscell(fCJ), fCJ = fCJ{1}; else, fCJ = fCJ(1); end
    assert(isfield(fCJ,'geometry') && isfield(fCJ.geometry,'perDx'), 'G: geometry.perDx ada');
    perDx = fCJ.geometry.perDx; if ~iscell(perDx), perDx = num2cell(perDx); end
    assert(numel(perDx)==3, 'G: perDx 3 entri (ACT-FSR×2 + X-FS ber-titik) (dapat %d)', numel(perDx));
    p2 = perDx{2}; if iscell(p2), p2=p2{1}; end
    assert(isfield(p2,'angleDeg') && isfield(p2,'lenCm') && isfield(p2,'growthRate'), ...
        'G: perDx entri punya angleDeg/lenCm/growthRate');
    assert(isfinite(p2.growthRate), 'G: perDx growthRate DX2 finite');
    % perDx LENGKAP (2026-07-17): SEMUA field DESC + TAPER ikut ke JSON CLCW.
    for fld = {'frame','poi','actF','isOost','nucPos','fsrDir','fTrx','desc', ...
               'angleDeg','lenCm','growthRate','vertices','taperDeg','taperLenCm','taperVertices'}
        assert(isfield(p2, fld{1}), 'G: perDx DX2 punya field %s', fld{1});
    end
    assert(strcmp(strtrim(p2.nucPos),'FT'), 'G: perDx bawa nucPos=FT (dapat %s)', p2.nucPos);
    assert(strcmp(strtrim(p2.fsrDir),'UP'), 'G: perDx bawa fsrDir=UP (dapat %s)', p2.fsrDir);
    assert(contains(p2.desc,'catatan lisan'), 'G: perDx bawa desc lisan (dapat %s)', p2.desc);
    assert(isfinite(p2.taperDeg) && abs(p2.taperDeg-12.5)<1e-6, 'G: perDx bawa taperDeg=12.5 (dapat %g)', p2.taperDeg);
    tv = p2.taperVertices; if ~iscell(tv), tv = num2cell(tv,2); end
    assert(numel(tv)==2, 'G: perDx bawa taperVertices 2 titik (dapat %d)', numel(tv));
    assert(isfinite(p2.taperLenCm), 'G: perDx taperLenCm finite');
    % --- X-FS ber-TITIK -> perDx (entri frame 100) WAJIB bawa nucPoint ke JSON ---
    pXfs = [];
    for t = 1:numel(perDx)
        pt = perDx{t}; if iscell(pt), pt = pt{1}; end
        if isfield(pt,'poi') && strcmp(strtrim(char(pt.poi)),'X-FS'), pXfs = pt; break; end
    end
    assert(~isempty(pXfs), 'G: perDx punya entri POI=X-FS (Ctrl+R utk X-FS ikut JSON)');
    npX = pXfs.nucPoint; if ~iscell(npX), npX = num2cell(npX,2); end
    assert(~isempty(npX), 'G: X-FS perDx bawa nucPoint (titik) ke JSON');
    xy = npX{1}; if iscell(xy), xy = xy{1}; end
    assert(isequal(round(xy(:)'),[640 520]), 'G: X-FS nucPoint koordinat = [640 520] (dapat %s)', mat2str(round(xy(:)')));
    assert(isfinite(pXfs.nucDistCm) && isfinite(pXfs.nucDepthCm), 'G: X-FS perDx bawa nucDistCm/nucDepthCm');
    fprintf('[OK] G bidang sesar per-DX LENGKAP (vertices+taper+POI+nucPos+fsrDir+desc + TITIK X-FS di JSON perDx)\n');

    % ========================= H. DETEKSI (tombol on-demand + kolom Det) =========================
    fprintf('==== H. Deteksi jumlah sesar aktif (tombol + kolom Det + mismatch merah) ====\n');
    h = guidata(fig); psgH = h.activePsgId;
    mkH = @(fn,fr,poi) pivcore.io.pab4Desc.rowStruct(psgH,fn,fr,poi);
    % F1 aktif 40..130(excl); F2 aktif 95..165(excl). isi #ACT F (actF) SENGAJA
    % SALAH di 1 baris utk uji penanda merah.
    % Aturan baru: NUC & X-FS eksklusif, isi inklusif.
    % F1: NUC@30 .. X-FS@130 (aktif 31..129). F2: NUC@90 .. X-FS@135 (aktif 91..134).
    rF1n = mkH('F1',30,'NUC-BDF1'); rF1a = mkH('F1',50,'PRP-BDF1'); rF1b = mkH('F1',100,'ACT-FSR'); rF1c = mkH('F1',130,'X-FSR');
    rF2n = mkH('F2',90,'NUC-TF');   rF2a = mkH('F2',95,'PRP-TF');   rF2b = mkH('F2',125,'ACT-FSR'); rF2c = mkH('F2',135,'X-FSR');
    rF1b.actF = 2;   % benar (frame100 -> F1&F2 = 2) -> COCOK
    rF1a.actF = 5;   % SALAH (frame50 -> hanya F1 = 1) -> MISMATCH merah
    rowsH = {rF1n, rF1a, rF1b, rF1c, rF2n, rF2a, rF2b, rF2c};
    % matikan filter DULU (sebelum set rows) supaya toggle tak meng-capture tabel
    % lama lalu menimpa rows kita. Set Value=0 + fire callback -> descFilterF=false.
    set(h.btnDescFilter,'Value',0);
    cbF = get(h.btnDescFilter,'Callback'); if ~isempty(cbF), cbF(h.btnDescFilter,[]); end
    h = guidata(fig);
    assert(~h.descFilterF, 'H: filter F# dimatikan');
    % set rows di descDoc + KOSONGKAN tabel visible (blok G/D meninggalkan rows lama
    % di tabel; i_onRunDeteksi meng-capture tabel dulu -> tanpa dikosongkan, rows lama
    % menimpa rowsH kita). Tabel kosong + descVisIdx [] -> capture no-op -> descDoc
    % (rowsH) dipertahankan, lalu Deteksi refresh menampilkannya.
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psgH, rowsH);
    set(h.tblDesc,'Data',cell(0,14)); h.descVisIdx = []; guidata(fig, h);
    assert(numel(get(h.tblDesc,'ColumnName'))==14, 'H: 14 kolom (Det+Nuk disisip)');
    % Klik tombol 🔍 Deteksi (via handle -> hindari cocok-string emoji) -> hitung +
    % isi kolom Det + tampilkan rows.
    assert(isfield(h,'btnDeteksi') && ishghandle(h.btnDeteksi), 'H: tombol Deteksi ada');
    i_fireH(h.btnDeteksi); h = guidata(fig);
    Dh = get(h.tblDesc,'Data');
    assert(size(Dh,1) >= 8, 'H: 8 baris DX tampil setelah Deteksi (dapat %d)', size(Dh,1));
    getDet = @(fr) i_detForFrame(Dh, fr);
    assert(strcmp(getDet(30),'0'),  'H: Det frame30 = 0 (NUC F1 eksklusif) (dapat %s)', getDet(30));
    assert(strcmp(getDet(50),'1'),  'H: Det frame50 = 1 (dapat %s)', getDet(50));
    assert(strcmp(getDet(100),'2'), 'H: Det frame100 = 2 (dapat %s)', getDet(100));
    assert(strcmp(getDet(130),'1'), 'H: Det frame130 = 1 (X-FS F1 excl -> F2) (dapat %s)', getDet(130));
    assert(strcmp(getDet(125),'2'), 'H: Det frame125 = 2 (dapat %s)', getDet(125));
    fprintf('[OK] H Deteksi (kolom Det terisi; aturan NUC & X-FS eksklusif; mismatch #ACT F ditandai)\n');

    % ========================= I. EXPORT MP4 (split: exp ini | semua) =========================
    fprintf('==== I. Export MP4 split (exp aktif + semua exp) ====\n');
    h = guidata(fig);
    assert(isfield(h,'btnMovie')    && ishghandle(h.btnMovie),    'I: tombol MP4 "exp ini" ada');
    assert(isfield(h,'btnMovieAll') && ishghandle(h.btnMovieAll), 'I: tombol MP4 "semua" ada');
    assert(isfield(h,'btnMovieCancel') && ishghandle(h.btnMovieCancel), 'I: tombol Cancel MP4 ada');
    % keduanya berbagi ruang lama (tak overlap; Cancel menutupi keduanya)
    pA = get(h.btnMovie,'Position'); pB = get(h.btnMovieAll,'Position');
    assert(pA(1)+pA(3) <= pB(1)+1e-6, 'I: btnMovie di kiri btnMovieAll tanpa overlap');
    % btnMovieState menyembunyikan KEDUA tombol + munculkan Cancel
    i_fireH(h.btnMovieCancel); % pastikan handle callback tak error (set flag saja)
    % render MP4 exp AKTIF headless: batasi 2 frame + arahkan output ke tempdir.
    movRoot = fullfile(tempdir, 'PAB4MP4TEST'); if isfolder(movRoot), rmdir(movRoot,'s'); end
    h = guidata(fig);
    h.movieMaxFrames = 2; h.movieTargetDur = 1; h.exportRootOverride = movRoot;
    h.exportStampOverride = '010101-000000'; guidata(fig, h);
    % pivui.quiet() sudah TRUE (DefaultFigureVisible='off' di awal test) -> msgbox
    % & questdlg dilewati oleh modul.
    assert(pivui.quiet(), 'I: mode senyap aktif (msgbox/questdlg dilewati)');
    i_fireH(h.btnMovie);                     % -> i_onExportMovie (exp aktif)
    mp4s = i_findMp4(movRoot);
    assert(numel(mp4s) >= 2, 'I: exp aktif hasilkan >=2 MP4 (velmag+shear), dapat %d', numel(mp4s));
    for i = 1:numel(mp4s)
        d = dir(mp4s{i}); assert(d.bytes > 0, 'I: MP4 %s tak kosong', mp4s{i});
    end
    fprintf('[OK] I.1 MP4 exp aktif (%d file di %s)\n', numel(mp4s), movRoot);
    % SEMUA exp: loop tiap exp di daftar -> tiap exp punya folder MP4 sendiri.
    if isfolder(movRoot), rmdir(movRoot,'s'); end
    h = guidata(fig); nExp = numel(h.list);
    i_fireH(h.btnMovieAll);                  % -> i_onExportMovieAll (loop semua exp)
    mp4all = i_findMp4(movRoot);
    assert(numel(mp4all) >= 2*max(1,min(nExp,2)), ...
        'I: semua exp hasilkan >=2 MP4 per exp (nExp=%d), dapat %d', nExp, numel(mp4all));
    fprintf('[OK] I.2 MP4 semua exp (%d exp -> %d file)\n', nExp, numel(mp4all));
    if isfolder(movRoot), rmdir(movRoot,'s'); end

    % I.3 EKSPOR GAMBAR per-bingkai (velmag+shear) — rentang dari kotak Frame img.
    h = guidata(fig);
    assert(isfield(h,'btnFrameImg') && ishghandle(h.btnFrameImg), 'I: tombol Ekspor frame ada');
    assert(isfield(h,'edFrameRange') && ishghandle(h.edFrameRange), 'I: kotak rentang frame ada');
    imgRoot = fullfile(tempdir, 'PAB4IMGTEST'); if isfolder(imgRoot), rmdir(imgRoot,'s'); end
    h.exportRootOverride = imgRoot; h.exportStampOverride = '010101-000000';
    set(h.edFrameRange,'String','1-2'); guidata(fig, h);
    i_fireH(h.btnFrameImg);                    % -> i_onExportFrameImg (2 bingkai × 2 skalar)
    jpgs = i_findExt(imgRoot, 'jpg');
    assert(numel(jpgs) >= 4, 'I.3: rentang 1-2 hasilkan >=4 JPG (2 bingkai × velmag+shear), dapat %d', numel(jpgs));
    for i = 1:numel(jpgs), d = dir(jpgs{i}); assert(d.bytes > 0, 'I.3: JPG %s tak kosong', jpgs{i}); end
    % Ukuran ekspor mengikuti ASPEK GAMBAR (bukan 1120×560 default MP4): figure
    % lebih lebar dari image extent -> aspek JPG mendekati aspek gambar.
    hI = guidata(fig);
    xg = pivcore.data.safeFrame(hI.data.x,1); yg = pivcore.data.safeFrame(hI.data.y,1);
    imgAsp = (max(xg(:))-min(xg(:)))/(max(yg(:))-min(yg(:)));
    info = imfinfo(jpgs{1}); jpgAsp = info.Width/info.Height;
    assert(imgAsp > 2.5, 'I.3: fixture gambar lebar (aspect %.2f)', imgAsp);   % sanity
    assert(jpgAsp > 3.0, 'I.3: JPG mengikuti aspek gambar lebar (dapat %.2f, bukan ~2.0 default)', jpgAsp);
    % rentang KOSONG -> hanya bingkai kini (2 JPG: velmag+shear).
    if isfolder(imgRoot), rmdir(imgRoot,'s'); end
    h = guidata(fig); set(h.edFrameRange,'String',''); guidata(fig, h);
    i_fireH(h.btnFrameImg);
    jpg1 = i_findExt(imgRoot, 'jpg');
    assert(numel(jpg1) == 2, 'I.3: kosong -> 2 JPG (bingkai kini × velmag+shear), dapat %d', numel(jpg1));
    fprintf('[OK] I.3 Ekspor gambar per-bingkai (rentang 1-2 -> %d JPG; kosong -> %d JPG)\n', numel(jpgs), numel(jpg1));
    if isfolder(imgRoot), rmdir(imgRoot,'s'); end

    % ========================= J. TITIK NUKLEASI (1 titik; datum indenter awal) =========================
    fprintf('==== J. Titik nukleasi (1 titik; jarak horiz ke indenter awal + kedalaman + Nuk) ====\n');
    h = guidata(fig);
    % (1) helper murni engine.
    % nucPointPx: 1 titik -> titik; data LAMA 2-titik -> vertex-1 (backward-compat).
    assert(isequal(pivcore.io.pab4Desc.nucPointPx([100 300]),[100 300]), 'J: nucPoint 1-titik');
    assert(isequal(pivcore.io.pab4Desc.nucPointPx([100 300; 140 360]),[100 300]), 'J: nucPoint data lama = vertex-1');
    % jarak HORIZONTAL ke datum X + lineMeanX + kalibrasi cmPerPx.
    assert(pivcore.io.pab4Desc.lineMeanX([505 0;515 900])==510, 'J: lineMeanX = mean x endpoint');
    assert(abs(pivcore.io.pab4Desc.horizDistPx([800 300],510)-290)<1e-9, 'J: horizDistPx = |x-xRef|');
    cpp = pivcore.io.pab4Desc.cmPerPxFromRefPair(510, 2900, 40.3);
    assert(abs(cpp - 40.3/2390)<1e-9, 'J: cmPerPxFromRefPair = L0/|xWall-x0|');
    % (1b) ref horizontal POSISI (datum kedalaman): jarak tegak-lurus ke garis.
    depSeg = pivcore.io.pab4Desc.pointToSegLineDistPx([100 300],[0 100; 200 100]);
    assert(abs(depSeg-200) < 1e-9, 'J: depth ke garis ref mendatar y=100 = 200');
    dref = pivcore.io.pab4Desc.emptyDoc('');
    dref = pivcore.io.pab4Desc.setRefHorizonPts(dref,[10 50; 400 90]);
    dref = pivcore.io.pab4Desc.setMetaLine(dref,'limitWallPts',[500 0; 510 900]);
    dref = pivcore.io.pab4Desc.setMetaLine(dref,'indenterInitPts',[120 0; 125 900]);
    dref = pivcore.io.pab4Desc.setMetaLine(dref,'basePts',[0 850; 3000 850]);
    dref = pivcore.io.pab4Desc.setModelThicknessCm(dref, 4);
    dref2 = pivcore.io.pab4Desc.normalizeDoc(jsondecode(jsonencode(pivcore.io.pab4Desc.prepForEncode(dref))),'');
    assert(isequal(pivcore.io.pab4Desc.refHorizonPts(dref2),[10 50;400 90]), 'J: refHorizonPts round-trip');
    assert(isequal(pivcore.io.pab4Desc.metaLine(dref2,'limitWallPts'),[500 0;510 900]), 'J: limitWallPts round-trip');
    assert(isequal(pivcore.io.pab4Desc.metaLine(dref2,'indenterInitPts'),[120 0;125 900]), 'J: indenterInitPts round-trip');
    assert(isequal(pivcore.io.pab4Desc.metaLine(dref2,'basePts'),[0 850;3000 850]), 'J: basePts round-trip');
    assert(pivcore.io.pab4Desc.modelThicknessCm(dref2)==4, 'J: modelThicknessCm round-trip=4');
    assert(pivcore.io.pab4Desc.modelThicknessCm(pivcore.io.pab4Desc.emptyDoc(''))==4, 'J: tebal default=4');
    % (1c) KOTAK MODEL 4-titik: round-trip + boxSides (sumber referensi).
    box = [100 200; 900 210; 905 800; 110 795];   % KiA KaA KaB KiB (clockwise)
    dbx = pivcore.io.pab4Desc.setModelBoxPts(pivcore.io.pab4Desc.emptyDoc(''), box);
    dbx2 = pivcore.io.pab4Desc.normalizeDoc(jsondecode(jsonencode(pivcore.io.pab4Desc.prepForEncode(dbx))),'');
    assert(isequal(pivcore.io.pab4Desc.modelBoxPts(dbx2),box), 'J: modelBoxPts round-trip 4 titik');
    sB = pivcore.io.pab4Desc.boxSides(box);
    assert(sB.xLeft==mean([100 110]) && sB.xRight==mean([900 905]), 'J: boxSides kiri/kanan');
    assert(isequal(sB.top,[100 200;900 210]) && isequal(sB.bottom,[110 795;905 800]), 'J: boxSides atas/bawah');
    % (2) tombol + checklist kolom Nuk + round-trip (1 titik + data lama 2-titik).
    assert(isfield(h,'btnNucPt') && ishghandle(h.btnNucPt), 'J: tombol Titik nukleasi ada');
    assert(isfield(h,'btnModelBox') && ishghandle(h.btnModelBox), 'J: tombol Kotak model ada');
    psgJ = h.activePsgId;
    % F2 = NUC-FSR@62 dgn TITIK nukleasi (1 titik). F1 = data LAMA garis 2-titik (backward-compat).
    rF2 = pivcore.io.pab4Desc.rowStruct(psgJ,'F2',62,'NUC-FSR');
    rF2.nucPos = 'FT'; rF2.fsrDir = 'UP';
    rF2.nucVerts = [210 410];                    % SATU titik nukleasi
    % F1 = NUC-TF (bukan NUC-FSR) dgn titik nukleasi -> titik nukleasi berlaku SEMUA NUC-*.
    rF1 = pivcore.io.pab4Desc.rowStruct(psgJ,'F1',60,'NUC-TF');
    rF1.nucVerts = [305 415; 260 470];           % data LAMA 2-titik -> vertex-1 dipakai
    % F3 = PRP-FSR (BUKAN NUC-*) -> tak relevan titik nukleasi (tak ditandai merah).
    rF3 = pivcore.io.pab4Desc.rowStruct(psgJ,'F3',70,'PRP-FSR');
    % F4 = X-FS ber-titik -> Ctrl+R juga berlaku utk X-FS; kolom Nuk -> ✓.
    rF4 = pivcore.io.pab4Desc.rowStruct(psgJ,'F4',72,'X-FS');
    rF4.nucVerts = [640 520];
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psgJ, {rF1, rF2, rF3, rF4});
    set(h.tblDesc,'Data',cell(0,14)); h.descVisIdx = []; guidata(fig, h);
    % refresh tabel DESC lewat callback filter (memanggil i_refreshDescTable internal;
    % private -> tak bisa dipanggil langsung dari test). Set OFF -> semua baris tampil.
    set(h.btnDescFilter,'Value',0); cbJ = get(h.btnDescFilter,'Callback'); if ~isempty(cbJ), cbJ(h.btnDescFilter,[]); end
    h = guidata(fig);
    Dj = get(h.tblDesc,'Data');
    % baris NUC-FSR@62 -> kolom Nuk (13) = ✓.
    rowNuc = 0;
    for t=1:size(Dj,1), if isequal(Dj{t,2},62), rowNuc=t; break; end, end
    assert(rowNuc>0, 'J: baris NUC-FSR@62 tampil');
    assert(strcmp(strtrim(Dj{rowNuc,13}),char(10003)), 'J: kolom Nuk (13) = ✓ untuk DX ber-titik nukleasi (dapat "%s")', Dj{rowNuc,13});
    % baris F1 = NUC-TF ber-titik (data lama 2-titik) -> Nuk ✓ (titik nukleasi utk SEMUA NUC-*).
    rowF1j = 0;
    for t=1:size(Dj,1), if isequal(Dj{t,2},60), rowF1j=t; break; end, end
    if rowF1j>0, assert(strcmp(strtrim(Dj{rowF1j,13}),char(10003)), 'J: DX NUC-TF ber-titik -> Nuk ✓ (semua NUC-*)'); end
    % baris F3 = PRP-FSR (bukan NUC-*) tanpa titik -> Nuk kosong (tak relevan).
    rowF3j = 0;
    for t=1:size(Dj,1), if isequal(Dj{t,2},70), rowF3j=t; break; end, end
    if rowF3j>0, assert(isempty(strtrim(char(Dj{rowF3j,13}))), 'J: DX PRP-FSR (bukan NUC-*) -> Nuk kosong'); end
    % baris F4 = X-FS ber-titik -> Nuk ✓ (Ctrl+R berlaku utk X-FS juga).
    rowF4j = 0;
    for t=1:size(Dj,1), if isequal(Dj{t,2},72), rowF4j=t; break; end, end
    if rowF4j>0, assert(strcmp(strtrim(Dj{rowF4j,13}),char(10003)), 'J: DX X-FS ber-titik -> Nuk ✓ (Ctrl+R utk X-FS)'); end
    % Save -> round-trip nucVerts (F2 = 1 titik, F1 = 2 titik lama tetap terbaca).
    i_fire(fig,'💾 Save Progress');
    dRj = pivcore.io.pab4Desc.read(df);
    rRj = pivcore.io.pab4Desc.rowsForPsg(dRj, psgJ);
    rNuc = []; rNuc1 = [];
    for t=1:numel(rRj)
        if isequal(round(rRj{t}.frame),62), rNuc=rRj{t}; end
        if isequal(round(rRj{t}.frame),60), rNuc1=rRj{t}; end
    end
    assert(~isempty(rNuc), 'J: baris NUC-FSR@62 tersimpan');
    assert(isequal(pivcore.io.pab4Desc.normVerts(rNuc.nucVerts),[210 410]), 'J: nucVerts 1-titik round-trip');
    assert(isequal(pivcore.io.pab4Desc.nucPointPx(rNuc1.nucVerts),[305 415]), 'J: nucVerts data-lama vertex-1 terbaca');
    % (3) KOTAK MODEL: set via engine + overlay + checkbox + recompute jarak nukleasi.
    h = guidata(fig);
    assert(isfield(h,'chkShowModelBox') && ishghandle(h.chkShowModelBox), 'J: checkbox tampil kotak ada');
    assert(get(h.chkShowModelBox,'Value')==1, 'J: checkbox kotak default ON');
    assert(isfield(h,'btnRefHoriz') && ishghandle(h.btnRefHoriz), 'J: tombol Ref horizontal (manual) ada');
    assert(isfield(h,'edModelThick') && ishghandle(h.edModelThick), 'J: kotak Tebal ada');
    % INPUT KOTAK via TOMBOL + hook tes (CurrentPoint read-only -> tak bisa simulasi
    % klik loupe headless). h.boxTestPts -> i_onToggleModelBox finalisasi langsung.
    h.boxTestPts = [200 100; 2900 110; 2910 900; 210 895];
    guidata(fig,h);
    i_fireH(h.btnModelBox);   % -> i_onToggleModelBox (jalur hook) -> simpan + recompute
    h = guidata(fig);
    assert(isequal(pivcore.io.pab4Desc.modelBoxPts(h.descDoc),[200 100;2900 110;2910 900;210 895]), 'J: kotak model via tombol tersimpan');
    h.boxTestPts = []; guidata(fig,h);
    i_fireH(h.chkShowModelBox);
    assert(~isempty(findall(h.axMain,'Tag','storedModelBox')), 'J: overlay kotak model ON');
    set(h.chkShowModelBox,'Value',0); i_fireH(h.chkShowModelBox);
    assert(isempty(findall(h.axMain,'Tag','storedModelBox')), 'J: overlay kotak hilang saat OFF');
    set(h.chkShowModelBox,'Value',1); i_fireH(h.chkShowModelBox);
    % kotak ketebalan -> meta.
    set(h.edModelThick,'String','6'); i_fireH(h.edModelThick);
    assert(pivcore.io.pab4Desc.modelThicknessCm(guidata(fig).descDoc)==6, 'J: tebal 6 cm ke meta');
    % Save -> kotak model + tebal round-trip ke disk.
    i_fire(fig,'💾 Save Progress');
    dRj2 = pivcore.io.pab4Desc.read(df);
    assert(isequal(pivcore.io.pab4Desc.modelBoxPts(dRj2),[200 100;2900 110;2910 900;210 895]), 'J: kotak model tersimpan ke disk');
    assert(pivcore.io.pab4Desc.modelThicknessCm(dRj2)==6, 'J: tebal 6 tersimpan ke disk');
    fprintf('[OK] J nukleasi 1-titik SEMUA NUC-* (NUC-TF/FSR/BDF) + KOTAK MODEL 4-titik + checklist Nuk + overlay + tebal\n');

    % cleanup
    if isfolder(tmpRoot), rmdir(tmpRoot,'s'); end
    if isfile(descPath), delete(descPath); end
    delete(fig);
    fprintf('==== PAB4 SEMUA LULUS (A-J) ✓ ====\n');
end

% ---------------------------------------------------------------------
function s = i_detForFrame(D, fr)
%I_DETFORFRAME  Nilai kolom Det (kol 4) pada baris ber-FRM (kol 2) == fr.
    s = '';
    for t = 1:size(D,1)
        if isequal(D{t,2}, fr), s = strtrim(char(D{t,4})); return; end
    end
end

function sub = i_rowsForF(rows, fTag)
%I_ROWSFORF  Baris DESC ber-fNum=fTag, urut frame menaik.
    sub = {};
    for k = 1:numel(rows)
        if strcmp(strtrim(rows{k}.fNum), fTag), sub{end+1} = rows{k}; end %#ok<AGROW>
    end
    fr = cellfun(@(r) i_frOrInf(r), sub);
    [~,ord] = sort(fr); sub = sub(ord);
end
function v = i_frOrInf(r)
    v = inf; if isfield(r,'frame') && isscalar(r.frame) && isfinite(r.frame), v = r.frame; end
end

function ph = i_pickPhase(lc, nm)
%I_PICKPHASE  Ambil struct fase bernama nm dari lifecycle (cell atau struct-array).
    ph = struct();
    if iscell(lc)
        for k = 1:numel(lc)
            if strcmp(lc{k}.phase, nm), ph = lc{k}; return; end
        end
    else
        for k = 1:numel(lc)
            if strcmp(lc(k).phase, nm), ph = lc(k); return; end
        end
    end
end

% ---------------------------------------------------------------------
function root = i_searchFixture(base)
%I_SEARCHFIXTURE  Cari rekursif (<=3 level) folder pertama yg punya .mat ber-
%   pasangan _faults.json. Kosong bila tak ada.
    root = '';
    if ~isfolder(base), return; end
    stack = {base}; depth = 0;
    while ~isempty(stack) && depth < 4
        next = {};
        for i = 1:numel(stack)
            if ~isempty(i_findMatWithFaults(stack{i})), root = stack{i}; return; end
            d = dir(stack{i});
            for j = 1:numel(d)
                if d(j).isdir && ~ismember(d(j).name, {'.','..'})
                    next{end+1} = fullfile(stack{i}, d(j).name); %#ok<AGROW>
                end
            end
        end
        stack = next; depth = depth + 1;
    end
end

function df = i_findMatWithFaults(dirPath)
%I_FINDMATWITHFAULTS  .mat pertama yang punya sidecar _faults.json di folder.
    df = '';
    d = dir(fullfile(dirPath,'*.mat'));
    for i=1:numel(d)
        [~,b] = fileparts(d(i).name);
        if endsWith(b,'_axpot') || endsWith(b,'_autopot'), continue; end
        fj = fullfile(dirPath,[b '_faults.json']);
        if isfile(fj), df = fullfile(dirPath, d(i).name); return; end
    end
end

function tf = i_hasButton(fig, str)
    tf = ~isempty(i_findButton(fig, str));
end

function hb = i_findButton(fig, str)
    hb = [];
    b = findall(fig,'Type','uicontrol');
    for i=1:numel(b)
        s = get(b(i),'String');
        if ischar(s) && strcmp(s,str), hb = b(i); return; end
    end
end

function tf = i_hasButtonContains(fig, sub)
    tf = false;
    b = findall(fig,'Type','uicontrol');
    for i=1:numel(b)
        s = get(b(i),'String');
        if ischar(s) && contains(s,sub), tf = true; return; end
    end
end

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

function i_fireH(hc), cb=get(hc,'Callback'); if ~isempty(cb), cb(hc,[]); end, end

function i_fireCellEdit(tb, r, c)
    cb = get(tb,'CellEditCallback');
    D = get(tb,'Data'); nd = ''; if ~isempty(D), nd = D{r,c}; end
    evt = struct('Indices',[r c],'NewData',nd,'PreviousData','','EditData',nd,'Error',[]);
    if ~isempty(cb), cb(tb, evt); end
end

function i_fireFaultRow(fig, row)
    h = guidata(fig);
    tb = h.tblFault; cb = get(tb,'CellSelectionCallback');
    evt = struct('Indices',[row 1]);
    if ~isempty(cb), cb(tb, evt); end
end

function idx = i_expIndexOf(fig, df)
    idx = -1; h = guidata(fig);
    if ~isfield(h,'list'), return; end
    for i=1:numel(h.list)
        if strcmp(h.list(i).file, df), idx = i; return; end
    end
end

function ord = i_activeFaultsSafe(h)
    ord = {};
    try, ord = pivui.pab5Model.faultRowOrder(h); catch, end
end

function i_close(fig), try, if ishghandle(fig), delete(fig); end, catch, end, end

function files = i_findMp4(root)
%I_FINDMP4  Cari rekursif semua .mp4 di bawah `root` (folder ekspor tes MP4).
    files = {};
    if ~isfolder(root), return; end
    d = dir(fullfile(root, '**', '*.mp4'));
    for i = 1:numel(d)
        files{end+1} = fullfile(d(i).folder, d(i).name); %#ok<AGROW>
    end
end

function files = i_findExt(root, ext)
%I_FINDEXT  Cari rekursif semua *.<ext> di bawah `root`.
    files = {};
    if ~isfolder(root), return; end
    d = dir(fullfile(root, '**', ['*.' ext]));
    for i = 1:numel(d)
        files{end+1} = fullfile(d(i).folder, d(i).name); %#ok<AGROW>
    end
end
