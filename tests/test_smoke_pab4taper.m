function test_smoke_pab4taper(rootDir)
%TEST_SMOKE_PAB4TAPER  Smoke test FITUR TAPER ANGLE (kemiringan topografi) PAB4.
%   Blok:
%     A  engine pab4Desc: taperVerts/taperDeg round-trip + bertahan reset lifecycle
%     B  build GUI -> tabel DESC 12 kolom (+Taper°) + tabel sesar 7 kolom
%        (+Tp0/Tp1/ΔTp) + tombol 📐 Taper/🔗 Grab ada; interpolasi taper ALWAYS-ON
%        (btnTaperInterp DIBUANG; taperInterpOn default true)
%     C  set 2 DX ber-taper (F# aktif) -> Save round-trip + kolom tabel DESC
%        Taper° terisi + tabel sesar Tp0/Tp1/ΔTp benar (awal/akhir/change)
%     D  alat 'w' via callback (ROI offscreen) -> commit simpan ke DX; auto-copy
%        acuan DIBUANG (gaya AE) -> HANYA DX yg di-commit ber-taper
%     D2 hotkey Ctrl+W (input taper); interpolasi always-on (tanpa Ctrl+Shift+W)
%     D3 Ctrl+W di DX-KOSONG saat interpolasi aktif -> COPY dari garis interpolasi
%        (bukan previous DX) + commit AUTO-RECOMPUTE sample taper (gaya After Effects)
%     E  interpolasi taper ALWAYS-ON: buildSamples (engine) + overlay 'taperInterp'
%        tampil OTOMATIS di frame antar-keyframe (tanpa toggle)
%     F  Ctrl+G GRAB keyframe taper (kontinuitas): F# aktif kosong -> ambil dari F#
%        LAIN (overlap); edit -> commit ke DX F# aktif; sumber utuh
%     F2 Ctrl+G PRIORITAS F# SENDIRI: F# aktif punya keyframe -> grab dari sesar sama
%        (skenario sesar terakhir, POI pertama ambil dari frame akhir), bukan tetangga
%     G  BAYANGAN REFERENSI taper F# tetangga (taperInterpRef): F# tetangga ber-interp
%        penuh -> bayangan ABU tampil di frame antara (lerp benar), hilang di luar rentang
%
%   SENYAP: DefaultFigureVisible off. Fixture default = exp ber-_faults.json di
%   EXP_coll; absen -> [SKIP]. SELALU MATLAB R2025b.

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
            if isfolder(cand{i}) && ~isempty(i_findMatWithFaults(cand{i})), rootDir = cand{i}; break; end
        end
    end
    if isempty(rootDir) || ~isfolder(rootDir)
        fprintf('[SKIP] test_smoke_pab4taper: fixture tak ada.\n'); return;
    end
    df = i_findMatWithFaults(rootDir);
    if isempty(df), fprintf('[SKIP] test_smoke_pab4taper: tak ada .mat ber-_faults.json.\n'); return; end
    sidecarGuard = i_guardSidecars(df); %#ok<NASGU>   % lindungi data user (restore auto)
    [~, baseName] = fileparts(df);
    fprintf('Fixture: %s\n', baseName);

    % ========================= A. ENGINE =========================
    fprintf('==== A. Engine taper round-trip ====\n');
    tf = fullfile(tempdir, 'PAB4TAPER_exp.mat');
    doc = pivcore.io.pab4Desc.emptyDoc(tf);
    r = pivcore.io.pab4Desc.rowStruct('P1','F1',10,'PRP-FSR');
    r.taperVerts = [0 0; 100 20]; r.taperDeg = 11.31;
    doc = pivcore.io.pab4Desc.setRowsForPsg(doc,'P1',{r});
    pivcore.io.pab4Desc.write(tf, doc);
    d2 = pivcore.io.pab4Desc.read(tf);
    rr = pivcore.io.pab4Desc.rowsForPsg(d2,'P1'); rr = rr{1};
    assert(abs(rr.taperDeg-11.31) < 1e-6, 'A: taperDeg roundtrip (%.4f)', rr.taperDeg);
    assert(isequal(size(rr.taperVerts),[2 2]), 'A: taperVerts roundtrip');
    % taper BERTAHAN walau POI NUC-FSR mereset vertices bidang sesar.
    r2 = pivcore.io.pab4Desc.normRow(struct('poi','NUC-FSR','vertices',[0 0;5 5], ...
        'taperVerts',[0 0;10 3],'taperDeg',7));
    assert(size(r2.vertices,1)==0 && size(r2.taperVerts,1)==2 && r2.taperDeg==7, ...
        'A: taper survive reset lifecycle');
    delete(pivcore.io.pab4Desc.dataPath(tf));
    fprintf('[OK] A engine\n');

    % ========================= B. BUILD =========================
    fprintf('==== B. Build GUI (kolom + tombol taper) ====\n');
    fig = PAB4(rootDir);
    cuf = onCleanup(@() i_close(fig)); %#ok<NASGU>
    h = guidata(fig);
    assert(numel(get(h.tblDesc,'ColumnName'))==14, 'B: tblDesc 14 kolom (+Det/Taper°/Nuk), dapat %d', numel(get(h.tblDesc,'ColumnName')));
    assert(numel(get(h.tblFault,'ColumnName'))==9, 'B: tblFault 9 kolom (+θ0/θ1/θ̄/Tp0/Tp1/ΔTp), dapat %d', numel(get(h.tblFault,'ColumnName')));
    assert(isfield(h,'btnTaper') && ishghandle(h.btnTaper), 'B: btnTaper ada');
    assert(isfield(h,'btnTaperGrab') && ishghandle(h.btnTaperGrab), 'B: btnTaperGrab ada');
    assert(~isfield(h,'btnTaperInterp'), 'B: btnTaperInterp DIBUANG (interpolasi always-on)');
    assert(isfield(h,'taperInterpOn') && h.taperInterpOn, 'B: taperInterpOn default true (always-on)');
    fprintf('[OK] B build\n');

    % ========================= LOAD EXP =========================
    idx = i_expIndexOf(fig, df);
    assert(idx>=1, 'exp fixture ada di daftar');
    descPath = strrep(df,'.mat','_desc.json');
    tintPath = strrep(df,'.mat','_taperinterp.json');
    fintPath = strrep(df,'.mat','_faultinterp.json');
    if isfile(descPath), delete(descPath); end
    if isfile(tintPath), delete(tintPath); end   % sidecar taper kerja (jangan bocor antar-run)
    if isfile(fintPath), delete(fintPath); end
    % bersihkan juga saat test SELESAI supaya run smoke lain tak terganggu.
    cleanSide = onCleanup(@() i_delIf({descPath, tintPath, fintPath})); %#ok<NASGU>
    pivui.pab4Shell.loadExperiment(fig, idx);
    h = guidata(fig);
    psg = h.activePsgId;
    assert(~isempty(psg), 'garis PSG aktif ada');
    % pastikan ada 1 sesar aktif (uiNum).
    slots = h.faultSlots; uN = [];
    [f0, i0] = pivui.pab5Model.activeFault(h);
    if i0 >= 1, uN = pivui.pab5Model.faultUiNum(f0); end
    if isempty(uN)
        % aktifkan sesar pertama yg ada record.
        for k=1:numel(slots)
            [ff, ii] = pivcore.io.pab5Faults.findFault(h.fdoc, slots{k});
            if ii>=1, i_setActiveFaultById(fig, ff.id); h=guidata(fig); uN = pivui.pab5Model.faultUiNum(ff); break; end
        end
    end
    assert(~isempty(uN), 'ada sesar aktif (uiNum)'); uN = round(uN);
    fTag = sprintf('F%d', uN);
    fprintf('[OK] exp dimuat (F# aktif = %s)\n', fTag);

    % ========================= C. 2 DX ber-taper -> tabel =========================
    fprintf('==== C. 2 DX ber-taper: round-trip + kolom tabel ====\n');
    % DX awal (frame 20, taper 10°) & akhir (frame 80, taper 25°).
    rA = pivcore.io.pab4Desc.rowStruct(psg,fTag,20,'PRP-FSR');
    rA.taperVerts = i_lineDeg(10); rA.taperDeg = pivcore.io.pab4Desc.angleDegRelOf(rA.taperVerts, NaN);
    rB = pivcore.io.pab4Desc.rowStruct(psg,fTag,80,'ACT-FSR');
    rB.taperVerts = i_lineDeg(25); rB.taperDeg = pivcore.io.pab4Desc.angleDegRelOf(rB.taperVerts, NaN);
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psg, {rA, rB});
    guidata(fig, h);
    tp0e = rA.taperDeg; tp1e = rB.taperDeg;
    i_fire(fig,'💾 Save Progress'); h = guidata(fig);
    dC = pivcore.io.pab4Desc.read(df);
    rowsRe = pivcore.io.pab4Desc.rowsForPsg(dC, psg);
    nWith = 0;
    for t=1:numel(rowsRe), if size(pivcore.io.pab4Desc.normVerts(rowsRe{t}.taperVerts),1)>=2, nWith=nWith+1; end, end
    assert(nWith==2, 'C: 2 DX ber-taper round-trip (dapat %d)', nWith);
    % Aktifkan garis -> refresh tabel.
    i_activateActiveLine(fig); h = guidata(fig);
    Dd = get(h.tblDesc,'Data');
    % kolom 12 = Taper° (geser +1 krn Det disisip). cari baris frame 20 & 80.
    tprCol = {};
    for t=1:size(Dd,1)
        if isequal(Dd{t,2},20), tprCol{end+1} = strtrim(Dd{t,12}); end %#ok<AGROW>
        if isequal(Dd{t,2},80), tprCol{end+1} = strtrim(Dd{t,12}); end %#ok<AGROW>
    end
    assert(numel(tprCol)==2 && ~isempty(tprCol{1}) && ~isempty(tprCol{2}), 'C: kolom Taper° terisi 2 baris');
    % tabel sesar 9 kolom: Tp0/Tp1/ΔTp (kol 7/8/9) untuk F# aktif.
    Df = get(h.tblFault,'Data');
    rowF = 0;
    for t=1:size(Df,1), if strcmp(strtrim(char(Df{t,1})), sprintf('%d',uN)), rowF=t; break; end, end
    assert(rowF>0, 'C: baris F# aktif di tabel sesar');
    tp0 = str2double(Df{rowF,7}); tp1 = str2double(Df{rowF,8}); tpD = str2double(Df{rowF,9});
    assert(abs(tp0-tp0e)<0.15, 'C: Tp0 ~ %.2f (dapat %.2f)', tp0e, tp0);
    assert(abs(tp1-tp1e)<0.15, 'C: Tp1 ~ %.2f (dapat %.2f)', tp1e, tp1);
    assert(abs(tpD-(tp1e-tp0e))<0.2, 'C: ΔTp = Tp1-Tp0 (dapat %.2f)', tpD);
    fprintf('[OK] C tabel taper (Tp0=%.1f Tp1=%.1f ΔTp=%.1f)\n', tp0, tp1, tpD);

    % ================ D. alat 'w' commit + auto-copy DIBUANG (gaya AE) ================
    fprintf('==== D. alat w commit; auto-copy acuan DIBUANG ====\n');
    % Sejajar pensiun warisan bidang sesar (2026-07-17): commit taper ke SATU DX TIDAK
    % LAGI menyebar ke DX F# lain. Tiap keyframe taper diisi manual; interpolasi
    % mengisi frame antara. Reset: 3 DX F# (frame 20/50/80). Frame 20 (keyframe) diberi
    % taperVerts SEED supaya alat 'w' bisa buat ROI di HEADLESS (drawpolyline interaktif
    % di-skip saat quiet). Commit -> HANYA frame 20 ber-taper; 50 & 80 TETAP KOSONG.
    r20 = pivcore.io.pab4Desc.rowStruct(psg,fTag,20,'PRP-FSR');
    r20.taperVerts = i_lineDeg(15); r20.taperDeg = 15;   % seed
    r50 = pivcore.io.pab4Desc.rowStruct(psg,fTag,50,'ACT-FSR');
    r80 = pivcore.io.pab4Desc.rowStruct(psg,fTag,80,'ACT-FSR');
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psg, {r20,r50,r80});
    guidata(fig,h);
    i_activateActiveLine(fig); h = guidata(fig);
    % pilih baris DX frame 20 (keyframe).
    idx20 = i_descRowIdx(h, psg, fTag, 20);
    assert(idx20>0, 'D: baris DX frame 20 ada');
    i_selectDescFull(fig, idx20);
    % buka alat taper (ON) -> ROI dibuat dari seed taperVerts -> commit (w lagi).
    h = guidata(fig);
    cb = get(h.btnTaper,'Callback'); cb(h.btnTaper,[]);   % ON
    h = guidata(fig);
    assert(isfield(h,'taperOn') && h.taperOn, 'D: alat taper ON (ROI dari seed)');
    assert(~isempty(h.roiTaper) && isvalid(h.roiTaper), 'D: roiTaper valid');
    % ubah garis (offscreen) lalu commit.
    try, h.roiTaper.Position = i_lineDeg(18); catch, end
    guidata(fig,h);
    cb = get(h.btnTaper,'Callback'); cb(h.btnTaper,[]);   % OFF = commit
    h = guidata(fig);
    rowsD = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, psg);
    nT = 0;
    for t=1:numel(rowsD)
        if ~strcmp(strtrim(rowsD{t}.fNum),fTag), continue; end
        if size(pivcore.io.pab4Desc.normVerts(rowsD{t}.taperVerts),1)>=2
            nT = nT+1;
        end
    end
    assert(nT==1, 'D: commit HANYA frame 20 ber-taper; DX lain TETAP KOSONG (dapat %d)', nT);
    fprintf('[OK] D commit tanpa auto-copy (1 DX ber-taper)\n');

    % Untuk blok D2/E (butuh >=2 DX ber-taper utk interpolasi) isi frame 50 MANUAL.
    rows50 = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, psg);
    i50 = i_descRowIdx(h, psg, fTag, 50);
    rows50{i50}.taperVerts = i_lineDeg(25); rows50{i50}.taperDeg = 25;
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psg, rows50);
    guidata(fig,h);

    % ===================== D2. HOTKEY Ctrl+W (input taper) =====================
    %   Ctrl+W = toggle alat TAPER (input). Interpolasi taper ALWAYS-ON (tak ada
    %   hotkey/tombol interpolasi terpisah lagi). DX frame 20 masih punya taperVerts.
    kcb = get(fig,'WindowKeyPressFcn');
    idx20b = i_descRowIdx(h, psg, fTag, 20);
    i_selectDescFull(fig, idx20b); h = guidata(fig);
    % pastikan alat OFF dulu
    if isfield(h,'taperOn') && h.taperOn, cbx=get(h.btnTaper,'Callback'); cbx(h.btnTaper,[]); h=guidata(fig); end
    kcb(fig, FakeKeyData('w','w',{'control'})); h = guidata(fig);   % Ctrl+W -> ON
    assert(isfield(h,'taperOn') && h.taperOn, 'D2: Ctrl+W membuka alat taper');
    kcb(fig, FakeKeyData('w','w',{'control'})); h = guidata(fig);   % Ctrl+W -> OFF/commit
    assert(~(isfield(h,'taperOn') && h.taperOn), 'D2: Ctrl+W lagi menutup/commit alat taper');
    % interpolasi taper ALWAYS-ON (default true, tanpa toggle).
    assert(isfield(h,'taperInterpOn') && h.taperInterpOn, 'D2: interpolasi taper always-on (default true)');
    fprintf('[OK] D2 hotkey Ctrl+W (input); interpolasi always-on\n');

    % ============ D3. Ctrl+W AUTO-SEED dari INTERPOLASI + AUTO-RECOMPUTE (gaya AE) ============
    %   Keyframe taper frame 20 (15°) & 80 (35°), frame 50 KOSONG. Interpolasi always-on
    %   -> di DX-KOSONG frame 50 (di antara), Ctrl+W harus AUTO-SEED garis INTERPOLASI
    %   (lerp ~25°, bukan previous DX). Commit -> jadi keyframe & sample di-recompute.
    rows3 = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, psg);
    for t=1:numel(rows3)
        if ~strcmp(strtrim(rows3{t}.fNum),fTag), continue; end
        switch rows3{t}.frame
            case 20, rows3{t}.taperVerts = i_lineDeg(15); rows3{t}.taperDeg = 15;
            case 80, rows3{t}.taperVerts = i_lineDeg(35); rows3{t}.taperDeg = 35;
            case 50, rows3{t}.taperVerts = zeros(0,2);    rows3{t}.taperDeg = NaN;
        end
    end
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psg, rows3);
    guidata(fig,h);
    assert(isfield(h,'taperInterpOn') && h.taperInterpOn, 'D3: interpolasi taper always-on');
    % pilih DX-kosong frame 50, buka alat taper -> ROI harus AUTO-seeded dari interpolasi.
    idx50 = i_descRowIdx(h, psg, fTag, 50);
    i_selectDescFull(fig, idx50); h = guidata(fig);
    cb = get(h.btnTaper,'Callback'); cb(h.btnTaper,[]);   % ON
    h = guidata(fig);
    assert(isfield(h,'taperOn') && h.taperOn, 'D3: alat taper ON @frame50');
    assert(~isempty(h.roiTaper) && isvalid(h.roiTaper), 'D3: roiTaper AUTO-seeded dari interpolasi');
    % frame50 di antara 20(15°) & 80(35°): t=0.5 -> ~25°.
    angSeed = pivcore.io.pab4Desc.angleDegRelOf(h.roiTaper.Position, 0);
    assert(abs(abs(angSeed)-25)<2.0, 'D3: AUTO-seed dari INTERPOLASI ~25° (dapat %.2f)', angSeed);
    % edit jadi 28° lalu commit -> keyframe baru + auto-recompute (event-driven).
    try, h.roiTaper.Position = i_lineDeg(28); catch, end
    guidata(fig,h);
    cb = get(h.btnTaper,'Callback'); cb(h.btnTaper,[]);   % OFF = commit
    h = guidata(fig);
    rowsC = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, psg);
    i50c = i_descRowIdx(h, psg, fTag, 50);
    assert(abs(rowsC{i50c}.taperDeg-28)<1.0, 'D3: frame 50 jadi keyframe 28° (dapat %.2f)', rowsC{i50c}.taperDeg);
    key = sprintf('%s|F%d', h.activePsgId, str2double(fTag(2:end)));
    assert(isKey(h.taperSamples,key), 'D3: taperSamples ter-recompute utk F# (event-driven)');
    fprintf('[OK] D3 Ctrl+W AUTO-seed interpolasi + auto-recompute taper\n');

    % ========================= E. interpolasi keyframe =========================
    fprintf('==== E. interpolasi keyframe taper ====\n');
    % 2 keyframe taper beda sudut (frame 20=10°, 80=30°) -> buildSamples engine.
    k1 = struct('frame',20,'vertices',i_lineDeg(10));
    k2 = struct('frame',80,'vertices',i_lineDeg(30));
    [okKf,~,N] = pivcore.io.pab4Interp.validateKeyframes({k1,k2});
    assert(okKf && N==2, 'E: validateKeyframes ok');
    samp = pivcore.io.pab4Interp.buildSamples({k1,k2}, NaN, NaN);
    assert(numel(samp)==(80-20+1), 'E: sample tiap frame 20..80 (dapat %d)', numel(samp));
    % midpoint frame 50 -> sudut ~20° (interpolasi vertex linear).
    mid = [];
    for t=1:numel(samp), if round(samp{t}.frame)==50, mid=samp{t}; break; end, end
    assert(~isempty(mid), 'E: sample frame 50 ada');
    angMid = pivcore.io.pab4Desc.angleDegRelOf(pivcore.io.pab4Desc.normVerts(mid.vertices), NaN);
    assert(abs(angMid-20)<1.0, 'E: taper interp frame 50 ~20° (dapat %.2f)', angMid);
    % GUI: set 2 DX keyframe taper -> interpolasi ALWAYS-ON -> overlay muncul OTOMATIS
    % saat scrub (tanpa toggle). Rebuild cache (event-driven; dipanggil saat exp/PSG
    % load; di sini paksa via i_activateActiveLine tak cukup -> panggil rebuild explicit
    % dgn commit path: set keyframe lalu gotoFrame; cache dibangun saat exp-loaded, tapi
    % kita ubah descDoc langsung -> picu rebuild lewat i_onExpLoaded tak jalan. Gunakan
    % commit satu keyframe utk memicu i_rebuildTaperTrack, atau langsung set frame.
    rk1 = pivcore.io.pab4Desc.rowStruct(psg,fTag,20,'PRP-FSR'); rk1.taperVerts=i_lineDeg(10); rk1.taperDeg=10;
    rk2 = pivcore.io.pab4Desc.rowStruct(psg,fTag,80,'ACT-FSR'); rk2.taperVerts=i_lineDeg(30); rk2.taperDeg=30;
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psg, {rk1,rk2});
    guidata(fig,h);
    i_activateActiveLine(fig); h = guidata(fig);
    % descDoc diubah LANGSUNG (bukan via commit) -> cache belum ter-recompute; commit DX
    % frame 20 (re-lock keyframe yg sama) utk memicu i_rebuildTaperTrack event-driven.
    idx20e = i_descRowIdx(h, psg, fTag, 20);
    i_selectDescFull(fig, idx20e); h = guidata(fig);
    cbT = get(h.btnTaper,'Callback'); cbT(h.btnTaper,[]); h = guidata(fig);   % ON (seed dari kf sendiri)
    cbT(h.btnTaper,[]); h = guidata(fig);                                     % OFF = commit -> recompute
    assert(isfield(h,'taperInterpOn') && h.taperInterpOn, 'E: interpolasi taper always-on');
    key_e = sprintf('%s|F%d', h.activePsgId, str2double(fTag(2:end)));
    assert(isKey(h.taperSamples,key_e), 'E: cache taperSamples terisi (event-driven commit)');
    pivui.pab4Shell.gotoFrame(fig, 50); h = guidata(fig);
    ov2 = findall(h.axMain,'Tag','taperInterp');
    assert(~isempty(ov2), 'E: overlay taperInterp tampil OTOMATIS di frame 50 (antar-keyframe)');
    % frame keyframe (20) -> overlay interp F# aktif DILEWATI (garis manual sudah ada).
    pivui.pab4Shell.gotoFrame(fig, 20); h = guidata(fig);
    ov3 = findall(h.axMain,'Tag','taperInterp');
    assert(isempty(ov3), 'E: overlay interp DILEWATI di frame keyframe 20');
    fprintf('[OK] E interpolasi taper always-on (overlay otomatis)\n');

    % ============ F. Ctrl+G GRAB dari OVERLAP lintas-F# (kontinuitas) ============
    fprintf('==== F. Ctrl+G grab taper dari overlap F# lain ====\n');
    % Skenario: F# AKTIF (fTag) hidup ~250, sesar TETANGGA (fNbr) punya taper @300
    % (di zona overlap). Ctrl+G di baris DX fTag@250 harus SEED dari fNbr@300 (frame
    % terdekat lintas-F#) lalu commit ke DX fTag@250. Sesar tetangga cukup sbg baris
    % DX ber-taper di descDoc (grab baca descDoc, bukan fault model).
    uNbr = uN + 1; fNbr = sprintf('F%d', uNbr);
    rAct = pivcore.io.pab4Desc.rowStruct(psg,fTag,250,'PRP-FSR');   % F# aktif, KOSONG
    rNbr = pivcore.io.pab4Desc.rowStruct(psg,fNbr,300,'ACT-FSR');
    rNbr.taperVerts = i_lineDeg(40); rNbr.taperDeg = 40;            % taper tetangga 40°
    rFar = pivcore.io.pab4Desc.rowStruct(psg,fNbr,500,'ACT-FSR');
    rFar.taperVerts = i_lineDeg(10); rFar.taperDeg = 10;            % tetangga jauh (frame 500)
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psg, {rAct,rNbr,rFar});
    guidata(fig,h);
    i_activateActiveLine(fig); h = guidata(fig);
    % GUI: pilih DX fTag@250, Ctrl+G -> ROI seeded dari fNbr@300 (frame terdekat lintas-
    % F#: |300-250|=50 < |500-250|=250), edit, Ctrl+G commit. (Helper grab = subfungsi
    % PAB4 internal; diuji lewat jalur GUI, bukan panggilan langsung.)
    idxAct = i_descRowIdx(h, psg, fTag, 250);
    i_selectDescFull(fig, idxAct); h = guidata(fig);
    kcbF = get(fig,'WindowKeyPressFcn');
    kcbF(fig, FakeKeyData('g','g',{'control'})); h = guidata(fig);   % Ctrl+G -> ON (grab)
    assert(isfield(h,'taperOn') && h.taperOn, 'F: Ctrl+G buka alat taper (grab)');
    assert(~isempty(h.roiTaper) && isvalid(h.roiTaper), 'F: roiTaper seeded dari grab');
    angSeed = pivcore.io.pab4Desc.angleDegRelOf(h.roiTaper.Position, 0);
    assert(abs(abs(angSeed)-40)<1.0, 'F: ROI seed = 40° dari tetangga (dapat %.2f)', angSeed);
    % edit jadi 33° lalu commit ke DX fTag@250.
    try, h.roiTaper.Position = i_lineDeg(33); catch, end
    guidata(fig,h);
    kcbF(fig, FakeKeyData('g','g',{'control'})); h = guidata(fig);   % Ctrl+G -> commit
    assert(~(isfield(h,'taperOn') && h.taperOn), 'F: Ctrl+G lagi commit alat taper');
    rowsF = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, psg);
    iAct = i_descRowIdx(h, psg, fTag, 250);
    assert(abs(rowsF{iAct}.taperDeg-33)<1.0, 'F: DX %s@250 jadi keyframe 33° (dapat %.2f)', fTag, rowsF{iAct}.taperDeg);
    % tetangga fNbr@300 TAK berubah (grab tak menimpa sumber).
    iNbr = i_descRowIdx(h, psg, fNbr, 300);
    assert(abs(rowsF{iNbr}.taperDeg-40)<1e-6, 'F: sumber %s@300 tetap 40° (tak tertimpa)', fNbr);
    fprintf('[OK] F Ctrl+G grab lintas-F# (seed 40°->commit 33° ke DX aktif; sumber utuh)\n');

    % ===== F2. Ctrl+G PRIORITAS F# SENDIRI dulu (skenario sesar terakhir, POI pertama) =====
    fprintf('==== F2. Ctrl+G prioritas F# sendiri (grab dari keyframe sesar sama) ====\n');
    % Skenario user P-CON-F-1: sesar terakhir, sudah gambar taper di frame AKHIR (F#
    % aktif@300=22°). Loncat ke POI PERTAMA sesar itu (fTag@250, KOSONG). Ctrl+G harus
    % ambil dari F# SENDIRI @300 (22°), BUKAN tetangga fNbr@300 (55°). Meski jaraknya
    % sama (|300-250|), tahap-1 (F# sendiri) menang atas tahap-2 (lintas-F#).
    rSelf250 = pivcore.io.pab4Desc.rowStruct(psg,fTag,250,'PRP-FSR');    % F# aktif, KOSONG (POI pertama)
    rSelf300 = pivcore.io.pab4Desc.rowStruct(psg,fTag,300,'ACT-FSR');
    rSelf300.taperVerts = i_lineDeg(22); rSelf300.taperDeg = 22;         % keyframe F# SENDIRI 22°
    rNbr300  = pivcore.io.pab4Desc.rowStruct(psg,fNbr,300,'ACT-FSR');
    rNbr300.taperVerts = i_lineDeg(55); rNbr300.taperDeg = 55;           % tetangga 55° (jarak sama)
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psg, {rSelf250,rSelf300,rNbr300});
    guidata(fig,h);
    i_activateActiveLine(fig); h = guidata(fig);
    idxSelf = i_descRowIdx(h, psg, fTag, 250);
    i_selectDescFull(fig, idxSelf); h = guidata(fig);
    kcbF2 = get(fig,'WindowKeyPressFcn');
    kcbF2(fig, FakeKeyData('g','g',{'control'})); h = guidata(fig);      % Ctrl+G -> ON
    assert(isfield(h,'taperOn') && h.taperOn, 'F2: Ctrl+G buka alat taper');
    assert(~isempty(h.roiTaper) && isvalid(h.roiTaper), 'F2: roiTaper seeded');
    angS2 = pivcore.io.pab4Desc.angleDegRelOf(h.roiTaper.Position, 0);
    assert(abs(abs(angS2)-22)<1.0, 'F2: seed dari F# SENDIRI @300=22° (bukan tetangga 55°) (dapat %.2f)', angS2);
    % batal (Ctrl+G lagi commit ROI apa adanya; tak masalah utk assert utama).
    kcbF2(fig, FakeKeyData('g','g',{'control'})); h = guidata(fig);
    fprintf('[OK] F2 Ctrl+G prioritas F# sendiri (seed 22° dari keyframe sesar sama)\n');

    % ===== G. BAYANGAN REFERENSI taper F# tetangga (kontinuitas overlap; kasus F11) =====
    fprintf('==== G. Bayangan referensi taper F# tetangga (taperInterpRef) ====\n');
    % Skenario user F11/F12: F# aktif (fTag) sedang dikerjakan, tetangga (fNbr) SUDAH
    % punya interpolasi taper penuh (2 keyframe: 288=20° & 348=40°). Scrub ke frame
    % ANTARA (mis. 318) -> bayangan ABU 'taperInterpRef' dari fNbr HARUS tampil (referensi
    % kontinuitas) supaya user lihat bentuk taper tetangga di tiap frame. fTag aktif
    % cukup 1 keyframe (tak interpolasi) -> tak ada garis hijau, tapi bayangan tetangga ada.
    % F# aktif fTag: 2 keyframe (300=12°,360=18°) supaya bisa di-commit (picu rebuild-all).
    rActG1 = pivcore.io.pab4Desc.rowStruct(psg,fTag,300,'PRP-FSR');
    rActG1.taperVerts = i_lineDeg(12); rActG1.taperDeg = 12;
    rActG2 = pivcore.io.pab4Desc.rowStruct(psg,fTag,360,'ACT-FSR');
    rActG2.taperVerts = i_lineDeg(18); rActG2.taperDeg = 18;
    rNbrA = pivcore.io.pab4Desc.rowStruct(psg,fNbr,288,'ACT-FSR');
    rNbrA.taperVerts = i_lineDeg(20); rNbrA.taperDeg = 20;               % tetangga kf1
    rNbrB = pivcore.io.pab4Desc.rowStruct(psg,fNbr,348,'ACT-FSR');
    rNbrB.taperVerts = i_lineDeg(40); rNbrB.taperDeg = 40;               % tetangga kf2
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psg, {rActG1,rActG2,rNbrA,rNbrB});
    guidata(fig,h);
    i_activateActiveLine(fig); h = guidata(fig);
    % Picu rebuild cache SEMUA F# lewat jalur GUI: commit taper fTag@300 (re-lock keyframe
    % sama). i_taperCommit -> i_rebuildAllTaperTracks -> cache tetangga fNbr ikut terisi.
    idxG = i_descRowIdx(h, psg, fTag, 300);
    i_selectDescFull(fig, idxG); h = guidata(fig);
    cbG = get(h.btnTaper,'Callback'); cbG(h.btnTaper,[]); h = guidata(fig);   % ON (seed kf sendiri)
    cbG(h.btnTaper,[]); h = guidata(fig);                                     % OFF = commit -> rebuild-all
    keyNbr = sprintf('%s|F%d', h.activePsgId, uNbr);
    assert(isKey(h.taperSamples,keyNbr), 'G: cache interp tetangga %s terisi (rebuild-all saat commit)', fNbr);
    % scrub ke frame ANTARA 318 (di antara 288 & 348) -> bayangan referensi tetangga tampil.
    pivui.pab4Shell.gotoFrame(fig, 318); h = guidata(fig);
    ref1 = findall(h.axMain,'Tag','taperInterpRef','Type','line');
    assert(~isempty(ref1), 'G: bayangan referensi taper tetangga TAMPIL di frame antara 318');
    % bentuk bayangan = lerp 288(20°)..348(40°) @318 (t=0.5) -> ~30°.
    Vref = [get(ref1(1),'XData').' get(ref1(1),'YData').'];
    angRef = pivcore.io.pab4Desc.angleDegRelOf(Vref, 0);
    assert(abs(abs(angRef)-30)<2.0, 'G: bayangan tetangga = interpolasi ~30° @318 (dapat %.2f)', angRef);
    % scrub ke LUAR rentang tetangga (frame 400 > 348) -> bayangan hilang (no extrapolasi).
    if h.nF >= 400
        pivui.pab4Shell.gotoFrame(fig, 400); h = guidata(fig);
        assert(isempty(findall(h.axMain,'Tag','taperInterpRef','Type','line')), ...
            'G: bayangan tetangga hilang di LUAR rentang keyframe-nya');
    end
    fprintf('[OK] G bayangan referensi taper tetangga (tampil dlm rentang, lerp benar)\n');

    % ===== H. AUTO-FILL kolom T° + status warna (super/auto/empty) + sidecar kerja =====
    fprintf('==== H. Auto-fill T° + warna sel + sidecar _taperinterp ====\n');
    % F# aktif fTag: keyframe supervised @300 (12°) & @360 (18°) -> interpolasi F# sendiri.
    % Baris DX kosong @330 (di antara) -> auto-fill dari interpolasi F# sendiri (~15°, HIJAU).
    % Baris DX kosong @500 (di LUAR rentang) -> tetap kosong (MERAH). Keyframe @300 -> BIRU.
    rS1 = pivcore.io.pab4Desc.rowStruct(psg,fTag,300,'PRP-FSR'); rS1.taperVerts=i_lineDeg(12); rS1.taperDeg=12;
    rS2 = pivcore.io.pab4Desc.rowStruct(psg,fTag,360,'ACT-FSR'); rS2.taperVerts=i_lineDeg(18); rS2.taperDeg=18;
    rMid = pivcore.io.pab4Desc.rowStruct(psg,fTag,330,'ACT-FSR');   % KOSONG (dlm rentang)
    rOut = pivcore.io.pab4Desc.rowStruct(psg,fTag,500,'ACT-FSR');   % KOSONG (luar rentang)
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psg, {rS1,rMid,rS2,rOut});
    guidata(fig,h);
    i_activateActiveLine(fig); h = guidata(fig);
    % picu rebuild lewat commit keyframe @300 (re-lock) -> cache + sidecar terisi.
    idxH = i_descRowIdx(h, psg, fTag, 300);
    i_selectDescFull(fig, idxH); h = guidata(fig);
    cbH = get(h.btnTaper,'Callback'); cbH(h.btnTaper,[]); h = guidata(fig);   % ON
    cbH(h.btnTaper,[]); h = guidata(fig);                                     % commit -> rebuild + refresh tabel
    % re-aktivasi garis utk refresh tabel DESC -> descTaperStat terisi (tanpa filter).
    i_activateActiveLine(fig); h = guidata(fig);
    stat = h.descTaperStat; vis = h.descVisIdx;
    % petakan frame -> status (via vis idx ke rows).
    rowsH = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, psg);
    statByFrame = containers.Map('KeyType','double','ValueType','char');
    for jj=1:numel(vis)
        fr = rowsH{vis(jj)}.frame;
        if isscalar(fr) && isfinite(fr), statByFrame(round(fr)) = stat{jj}; end
    end
    assert(isKey(statByFrame,300) && strcmp(statByFrame(300),'super'), 'H: @300 keyframe -> super (biru)');
    assert(isKey(statByFrame,330) && strcmp(statByFrame(330),'auto'),  'H: @330 dlm rentang -> auto (hijau)');
    assert(isKey(statByFrame,500) && strcmp(statByFrame(500),'empty'), 'H: @500 luar rentang -> empty (merah)');
    % nilai auto @330 (di antara 12° & 18°): lerp t=0.5 -> ~15°. Kolom T° tampilan terisi.
    D = get(h.tblDesc,'Data');
    row330 = find(cellfun(@(x) isequal(x,330), D(:,2)), 1);
    assert(~isempty(row330), 'H: baris 330 ada di tabel');
    tval = str2double(D{row330,12});
    assert(abs(abs(tval)-15)<2.0, 'H: auto-fill T° @330 ~15° (dapat %s)', D{row330,12});
    % baris 500 (luar rentang) kolom T° KOSONG.
    row500 = find(cellfun(@(x) isequal(x,500), D(:,2)), 1);
    assert(~isempty(row500), 'H: baris 500 ada');
    assert(i_cellEmptyT(D{row500,12}), 'H: @500 kolom T° kosong (empty)');
    % sidecar kerja: track F# tercatat di h.taperInterpDoc.
    e = pivcore.io.pab4TaperInterp.trackFor(h.taperInterpDoc, psg, fTag);
    assert(~isempty(e), 'H: track taper F# tercatat di sidecar doc');
    fprintf('[OK] H auto-fill T° (super/auto/empty) + nilai lerp + sidecar kerja\n');

    % ===== I. HAPUS keyframe -> interpolasi TAK persisten (cache+overlay bersih) =====
    fprintf('==== I. Hapus keyframe -> interpolasi hilang (no persisten) ====\n');
    % Lanjut kondisi H: F# aktif punya keyframe @300 & @360 -> cache interp ada.
    keyI = sprintf('%s|F%d', h.activePsgId, str2double(fTag(2:end)));
    assert(isKey(h.taperSamples, keyI), 'I: prasyarat cache interp F# ada');
    % scrub ke frame antara 330 -> overlay hijau F# aktif tampil.
    pivui.pab4Shell.gotoFrame(fig, 330); h = guidata(fig);
    assert(~isempty(findall(h.axMain,'Tag','taperInterp')), 'I: overlay interp tampil sebelum hapus');
    % HAPUS keyframe @360 via tombol 🗑 Taper (clear taper baris) -> keyframe turun jadi 1.
    idxDel = i_descRowIdx(h, psg, fTag, 360);
    i_selectDescFull(fig, idxDel); h = guidata(fig);
    % tombol clear taper = '🗑' (i_onClearTaper). Panggil via callback tombolnya.
    i_onClearTaperProxy(fig);
    h = guidata(fig);
    % cache F# HARUS terhapus (interpolasi tak boleh jalan dgn 1 keyframe).
    assert(~isKey(h.taperSamples, keyI), 'I: cache interp DIHAPUS setelah keyframe <2');
    % overlay hijau HARUS hilang saat scrub.
    pivui.pab4Shell.gotoFrame(fig, 330); h = guidata(fig);
    assert(isempty(findall(h.axMain,'Tag','taperInterp')), 'I: overlay interp HILANG (no persisten)');
    % sidecar doc: track F# juga dibersihkan.
    eI = pivcore.io.pab4TaperInterp.trackFor(h.taperInterpDoc, psg, fTag);
    assert(isempty(eI), 'I: track sidecar F# dibersihkan');
    fprintf('[OK] I hapus keyframe -> interpolasi hilang (cache+overlay+sidecar bersih)\n');

    % ===== J. Data EVOLUSI taper (sumber plot Report A hal.2) tersedia =====
    fprintf('==== J. Evolusi taper: angleDeg per-frame utk plot Report A ====\n');
    % Buat F# aktif 2 keyframe (@280=15°, @340=35°) -> cache samples tiap frame 280..340
    % harus punya angleDeg (dasar plot X=frame Y=sudut). Titik keyframe = 280 & 340.
    rJ1 = pivcore.io.pab4Desc.rowStruct(psg,fTag,280,'PRP-FSR'); rJ1.taperVerts=i_lineDeg(15); rJ1.taperDeg=15;
    rJ2 = pivcore.io.pab4Desc.rowStruct(psg,fTag,340,'ACT-FSR'); rJ2.taperVerts=i_lineDeg(35); rJ2.taperDeg=35;
    h.descDoc = pivcore.io.pab4Desc.setRowsForPsg(h.descDoc, psg, {rJ1,rJ2});
    guidata(fig,h);
    i_activateActiveLine(fig); h = guidata(fig);
    idxJ = i_descRowIdx(h, psg, fTag, 280);
    i_selectDescFull(fig, idxJ); h = guidata(fig);
    cbJ = get(h.btnTaper,'Callback'); cbJ(h.btnTaper,[]); h=guidata(fig); cbJ(h.btnTaper,[]); h=guidata(fig);  % commit -> rebuild
    keyJ = sprintf('%s|F%d', h.activePsgId, str2double(fTag(2:end)));
    assert(isKey(h.taperSamples,keyJ), 'J: cache samples F# ada');
    SJ = h.taperSamples(keyJ);
    sampJ = pivcore.io.pab4Interp.tocell(SJ.samples);
    assert(numel(sampJ) == (340-280+1), 'J: samples tiap frame 280..340 (dapat %d)', numel(sampJ));
    % tiap sample punya angleDeg finite (sumber plot); ujung 15° & 35°.
    a0=NaN; a1=NaN; allFinite=true;
    for t=1:numel(sampJ)
        s=sampJ{t};
        if ~(isfield(s,'angleDeg') && isfinite(s.angleDeg)), allFinite=false; end
        if round(s.frame)==280, a0=s.angleDeg; end
        if round(s.frame)==340, a1=s.angleDeg; end
    end
    assert(allFinite, 'J: SEMUA sample punya angleDeg finite (plot valid)');
    assert(abs(abs(a0)-15)<1.5 && abs(abs(a1)-35)<1.5, 'J: ujung 15°/35° (dapat %.1f/%.1f)', a0, a1);
    assert(isfield(SJ,'keyFrames') && numel(SJ.keyFrames)==2, 'J: 2 keyframe (● supervised di plot)');
    fprintf('[OK] J evolusi taper: angleDeg per-frame + keyframe tersedia utk plot Report A\n');

    fprintf('==== PAB4 TAPER SEMUA LULUS ✓ ====\n');
end

function i_onClearTaperProxy(fig)
% panggil handler clear taper (subfungsi PAB4) via findall tombol '🗑'.
    b = findall(fig,'Style','pushbutton');
    for k=b(:)'
        if strcmp(strtrim(char(get(k,'String'))),'🗑')
            cb = get(k,'Callback'); if ~isempty(cb), cb(k,[]); end, return;
        end
    end
    error('tombol 🗑 taper tak ketemu');
end

function tf = i_cellEmptyT(x)
    tf = false;
    if isempty(x), tf = true; return; end
    s = strtrim(char(x));
    tf = isempty(s) || strcmp(s,'—') || strcmp(s,'·');
end

% ---------------- helper lokal ----------------
function V = i_lineDeg(deg)
%I_LINEDEG  Garis 2-titik dari (0,0) ke (100, 100*tand(deg)) -> sudut = deg.
    V = [0 0; 100 100*tand(deg)];
end

function df = i_findMatWithFaults(root)
    df = '';
    dd = dir(fullfile(root,'**','*.mat'));
    for i=1:numel(dd)
        p = fullfile(dd(i).folder, dd(i).name);
        if isfile(strrep(p,'.mat','_faults.json')), df = p; return; end
    end
end

function idx = i_expIndexOf(fig, df)
    h = guidata(fig); idx = -1;
    if ~isfield(h,'list'), return; end
    for i=1:numel(h.list)
        if strcmp(h.list(i).file, df), idx=i; return; end
    end
end

function i_fire(fig, label)
    h = guidata(fig);
    b = findall(fig,'Style','pushbutton','-or','Style','togglebutton');
    for k=b(:)'
        if strcmp(strtrim(char(get(k,'String'))), label)
            cb = get(k,'Callback'); if ~isempty(cb), cb(k,[]); end, return;
        end
    end
    error('tombol tak ketemu: %s', label);
end

function idx = i_descRowIdx(h, psg, fTag, frame)
    idx = 0;
    rows = pivcore.io.pab4Desc.rowsForPsg(h.descDoc, psg);
    for t=1:numel(rows)
        if strcmp(strtrim(rows{t}.fNum),fTag) && isscalar(rows{t}.frame) && rows{t}.frame==frame
            idx = t; return;
        end
    end
end

function i_selectDescFull(fig, fullIdx)
% set descVisIdx + descSelRow supaya i_descSelFullIdx -> fullIdx (tanpa filter).
    h = guidata(fig);
    h.descFilterF = false;
    guidata(fig,h);
    i_activateActiveLine(fig); h = guidata(fig);   % refresh tabel tanpa filter
    vis = h.descVisIdx;
    row = find(vis==fullIdx, 1);
    if isempty(row), row = fullIdx; end
    h.descSelRow = row; guidata(fig,h);
end

function i_setActiveFaultById(fig, id)
    h = guidata(fig); h.activeFaultId = id; guidata(fig,h);
    try, i_activateActiveLine(fig); catch, end
end

function i_activateActiveLine(fig)
%I_ACTIVATEACTIVELINE  Picu i_refreshDescTable via KLIK baris tabel sesar pertama
%   yg ber-record (memanggil CellSelectionCallback -> i_setActiveFault -> refresh).
%   Robust headless (listbox garis PSG string ber-prefix » & suffix stat, tak cocok
%   utk find). Kembali ke baris F# terpilih semula bila diberikan.
    h = guidata(fig);
    Df = get(h.tblFault,'Data');
    for t = 1:size(Df,1)
        if ~isempty(strtrim(char(Df{t,1})))
            try, h.tblFault.Selection = t; catch, end
            cbf = get(h.tblFault,'CellSelectionCallback');
            if ~isempty(cbf), ev.Indices=[t 1]; try, cbf(h.tblFault,ev); catch, end, end
            break;
        end
    end
end

function i_close(fig)
    try, if ishghandle(fig), delete(fig); end, catch, end
end

function i_delIf(paths)
    for k = 1:numel(paths)
        try, if isfile(paths{k}), delete(paths{k}); end, catch, end
    end
end
