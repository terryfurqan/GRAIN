function test_grain4_actfsr_prp_leak(rootDir)
%TEST_GRAIN4_ACTFSR_PRP_LEAK  Regresi bentuk bidang sesar antar-DX. Skenario:
%     (1) Baris PRP-FSR di frame A digambar bidang (vertices).
%     (2) POI baris itu DIGANTI jadi ACT-FSR (Ctrl+4 pada frame A).
%         -> bidang PRP-FSR TAK boleh ikut jadi milik ACT-FSR (dibuang -> KOSONG).
%     (3) Tambah ACT-FSR baru di frame B (> A) -> TAK mewarisi bentuk PRP.
%     (4) PENSIUN warisan copy-from-previous-POI (2026-07-17): ACT-FSR baru MULAI
%         KOSONG (tak copy ACT-FSR bawah). INTERPOLASI = metode utama pengisi bentuk.
%     (A/B) COPY INTERPOLASI Ctrl+Q: interp OFF -> tak seed; interp ON -> seed lerp.
%     (ZOOM+KUNCI) Ctrl+Q saat zoom+lock: mode zoom OFF + view tetap + ROI terbuka.
%   SELALU MATLAB R2025b. SENYAP (Visible off). [SKIP] bila fixture absen.

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(fileparts(here)));
    addpath(fullfile(fileparts(here), 'pivcore_lib'));
    try, grain_setup; catch, end
    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

    if nargin < 1 || isempty(rootDir)
        cand = {fullfile(grain_fixture_root(),'EXP_coll','EXP Q1','P-CON-4cm-F'), ...
                fullfile(grain_fixture_root(),'EXP_coll','P-CON-4cm-F')};
        rootDir = '';
        for i = 1:numel(cand)
            if isfolder(cand{i}) && ~isempty(i_findMat(cand{i})), rootDir = cand{i}; break; end
        end
    end
    if isempty(rootDir) || ~isfolder(rootDir)
        fprintf('[SKIP] test_grain4_actfsr_prp_leak: fixture tak ada.\n'); return;
    end
    df = i_findMat(rootDir);
    if isempty(df), fprintf('[SKIP] tak ada .mat ber-_faults.json.\n'); return; end
    sidecarGuard = i_guardSidecars(df); %#ok<NASGU>   % lindungi data user (restore auto)

    fig = GRAIN4(rootDir);
    cuf = onCleanup(@() i_close(fig)); %#ok<NASGU>
    idx = i_expIndexOf(fig, df); assert(idx>=1, 'exp fixture ada');
    descPath = strrep(df,'.mat','_desc.json');
    if isfile(descPath), delete(descPath); end
    pivui.grain4Shell.loadExperiment(fig, idx);
    h = guidata(fig);

    % --- Pilih sesar aktif (F# terisi otomatis untuk baris baru) ---
    F = pivui.grain5Model.faultsForPsg(h.fdoc, h.activePsgId);
    assert(~isempty(F), 'perlu >=1 sesar di garis PSG aktif');
    fA = F{1}; h.activeFaultId = fA.id; guidata(fig, h);
    uN = pivui.grain5Model.faultUiNum(fA); fTag = sprintf('F%d', round(uN));
    psg = h.activePsgId;
    Vprp = [500 300; 560 300+60*tand(30)];   % bidang PRP-FSR "asing"

    kcb = get(fig,'WindowKeyPressFcn');
    gotoFr = @(k) pivui.grain4Shell.gotoFrame(fig, k);
    frA = min(30, max(2, round(h.nF/3)));     % frame PRP-FSR (dikonversi)
    frB = min(frA+15, h.nF);                    % frame ACT-FSR baru (> A)

    % (1) PRP-FSR di frame A + bidang tergambar (set langsung ke _desc).
    gotoFr(frA); h = guidata(fig);
    kcb(fig, FakeKeyData('3','#',{'control','shift'}));   % Ctrl+Shift+3 = PRP-FSR
    h = guidata(fig);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    kA = i_findRow(rows, fTag, frA);
    assert(kA>0, 'setup: baris PRP-FSR@%d dibuat', frA);
    assert(strcmp(rows{kA}.poi,'PRP-FSR'), 'setup: POI=PRP-FSR (dapat %s)', rows{kA}.poi);
    rows{kA}.vertices = Vprp;
    rows{kA}.lenCm = pivcore.io.grain4Desc.lenCmOf(Vprp, 0.01);
    rows{kA}.angleDeg = pivcore.io.grain4Desc.angleDegOf(Vprp);
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, psg, rows);
    guidata(fig, h);

    % (2) Ctrl+4 pada frame A -> ganti POI ke ACT-FSR. Bidang PRP HARUS dibuang.
    gotoFr(frA); h = guidata(fig);
    kcb(fig, FakeKeyData('4','4',{'control'}));   % Ctrl+4 = ACT-FSR
    h = guidata(fig);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    kA = i_findRow(rows, fTag, frA);
    assert(kA>0, '(2): baris frame %d masih ada', frA);
    assert(strcmp(rows{kA}.poi,'ACT-FSR'), '(2): POI jadi ACT-FSR (dapat %s)', rows{kA}.poi);
    nvA = size(pivcore.io.grain4Desc.normVerts(rows{kA}.vertices),1);
    assert(nvA < 2, ['BUG: ACT-FSR(A) MASIH mewarisi bidang PRP-FSR ' ...
        '(%d vertex; harusnya 0 karena tak ada ACT-FSR di bawah).'], nvA);
    fprintf('[OK] (2) konversi PRP-FSR->ACT-FSR TIDAK membawa bidang PRP (%d vertex)\n', nvA);

    % (3) Tambah ACT-FSR baru di frame B -> TAK boleh warisi bentuk PRP.
    gotoFr(frB); h = guidata(fig);
    kcb(fig, FakeKeyData('4','4',{'control'}));
    h = guidata(fig);
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    kB = i_findRow(rows, fTag, frB);
    assert(kB>0, '(3): baris ACT-FSR@%d dibuat', frB);
    nvB = size(pivcore.io.grain4Desc.normVerts(rows{kB}.vertices),1);
    Vb = pivcore.io.grain4Desc.normVerts(rows{kB}.vertices);
    leaked = size(Vb,1)==size(Vprp,1) && isequal(round(Vb),round(Vprp));
    assert(~leaked, 'BUG: ACT-FSR(B) mewarisi bidang PRP-FSR (leak lewat ACT-FSR A).');
    fprintf('[OK] (3) ACT-FSR baru TAK mewarisi bentuk PRP (%d vertex, no-leak)\n', nvB);

    % --- (4) PENSIUN warisan copy-from-previous-POI (2026-07-17). Dulu ACT-FSR baru
    %   MEWARISI bidang ACT-FSR terdekat di bawah TANPA menghormati garis biru
    %   interpolasi -> Ctrl+Q memunculkan bentuk previous, bukan interpolasi. Kini
    %   INTERPOLASI = metode utama: baris ACT-FSR baru MULAI KOSONG. Beri ACT-FSR(A)
    %   bidang sendiri, tambah ACT-FSR(C)>B -> C HARUS tetap KOSONG (tak warisi A). ---
    Vact = [400 200; 500 260];
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
    kA = i_findRow(rows, fTag, frA);
    rows{kA}.vertices = Vact;
    rows{kA}.lenCm = pivcore.io.grain4Desc.lenCmOf(Vact, 0.01);
    rows{kA}.angleDeg = pivcore.io.grain4Desc.angleDegOf(Vact);
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, psg, rows);
    guidata(fig, h);
    frC = min(frB+10, h.nF);
    if frC > frB
        gotoFr(frC); h = guidata(fig);
        kcb(fig, FakeKeyData('4','4',{'control'}));
        h = guidata(fig);
        rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
        kC = i_findRow(rows, fTag, frC);
        Vc = pivcore.io.grain4Desc.normVerts(rows{kC}.vertices);
        assert(size(Vc,1) < 2, ...
            'BUG: warisan ACT->ACT belum dipensiunkan (ACT-FSR(C) masih copy bidang A: %d vertex).', size(Vc,1));
        fprintf('[OK] (4) warisan copy-from-previous-POI DIPENSIUNKAN (ACT-FSR baru mulai kosong)\n');
    end

    % ================= COPY INTERPOLASI Ctrl+Q (gaya After Effects) =================
    %   Model baru 2026-07-16: Ctrl+Q pada DX KOSONG meng-COPY bentuk INTERPOLASI
    %   (unsupervised) di frame itu — HANYA saat interpolasi AKTIF. Setup: 2 supervised
    %   keyframe (PRP-FSR@P + ACT-FSR@R) + 1 DX kosong di TENGAH (ACT-FSR@Q, P<Q<R).
    %   Interpolasi ON -> Ctrl+Q@Q harus seed dari bentuk lerp (bukan salah satu
    %   keyframe apa adanya, bukan kosong).
    h = guidata(fig);
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, psg, {}); guidata(fig, h);
    h.interpOn = false; guidata(fig, h);
    frP = min(20, max(2, round(h.nF/4)));
    frR = min(frP+40, h.nF);
    frQ = round((frP+frR)/2);
    if frR > frQ && frQ > frP
        % Dua keyframe supervised: PRP-FSR@P (bidang V0) & ACT-FSR@R (bidang V1),
        % JUMLAH VERTEX SAMA (syarat interpolasi). Bentuk lerp @Q = 0.5*(V0+V1).
        gotoFr(frP); kcb(fig, FakeKeyData('3','#',{'control','shift'}));   % PRP-FSR@P
        gotoFr(frR); kcb(fig, FakeKeyData('4','4',{'control'}));           % ACT-FSR@R
        gotoFr(frQ); kcb(fig, FakeKeyData('4','4',{'control'}));           % ACT-FSR@Q (kosong)
        h = guidata(fig);
        rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
        kP = i_findRow(rows, fTag, frP); kR = i_findRow(rows, fTag, frR); kQ = i_findRow(rows, fTag, frQ);
        assert(kP>0 && kR>0 && kQ>0, 'seed setup: PRP@%d, ACT@%d, ACT@%d ada', frP, frR, frQ);
        V0 = [420 260; 495 320];
        V1 = [440 280; 520 360];
        Vmid = 0.5*(V0+V1);   % harapan lerp @Q (t=0.5 krn Q di tengah)
        rows{kP}.vertices = V0; rows{kP}.lenCm = pivcore.io.grain4Desc.lenCmOf(V0,0.01); rows{kP}.angleDeg = pivcore.io.grain4Desc.angleDegOf(V0);
        rows{kR}.vertices = V1; rows{kR}.lenCm = pivcore.io.grain4Desc.lenCmOf(V1,0.01); rows{kR}.angleDeg = pivcore.io.grain4Desc.angleDegOf(V1);
        rows{kQ}.vertices = zeros(0,2);   % DX tengah KOSONG (unsupervised)
        h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, psg, rows);
        guidata(fig, h);

        % (A) Interpolasi OFF -> Ctrl+Q@Q buka ROI KOSONG (tak ada seed) atau batal.
        %     Kontrak: seededFromInterp=false -> ROI tak ter-seed dari keyframe.
        h = guidata(fig); h.interpOn = false; guidata(fig, h);
        vis = []; if isfield(h,'descVisIdx'), vis = h.descVisIdx; end
        selR = kQ; if ~isempty(vis), vv = find(vis==kQ,1); if ~isempty(vv), selR = vv; end, end
        h.descSelRow = selR; guidata(fig, h);
        kcb(fig, FakeKeyData('q','q',{'control'})); h = guidata(fig);
        seeded = isfield(h,'roiFaultPoly') && ~isempty(h.roiFaultPoly) && isvalid(h.roiFaultPoly) ...
            && size(pivcore.io.grain4Desc.normVerts(h.roiFaultPoly.Position),1) >= 2;
        assert(~seeded, 'BUG: interpolasi OFF tapi Ctrl+Q masih meng-seed ROI dari keyframe.');
        fprintf('[OK] (A) interpolasi OFF -> Ctrl+Q pada DX kosong TIDAK seed (gambar manual)\n');
        % tutup/batalkan ROI bila terbuka
        try, if isfield(h,'faultPolyOn') && h.faultPolyOn, kcb(fig, FakeKeyData('q','q',{'control'})); end, catch, end

        % (B) Interpolasi ON -> Ctrl+Q@Q meng-COPY bentuk lerp (0.5*(V0+V1)).
        h = guidata(fig); h.interpOn = true; guidata(fig, h);
        h.descSelRow = selR; guidata(fig, h);
        kcb(fig, FakeKeyData('q','q',{'control'})); h = guidata(fig);
        assert(isfield(h,'roiFaultPoly') && ~isempty(h.roiFaultPoly) && isvalid(h.roiFaultPoly), ...
            'copy-interp: Ctrl+Q membuka ROI bidang sesar');
        Vroi = pivcore.io.grain4Desc.normVerts(h.roiFaultPoly.Position);
        assert(size(Vroi,1)==size(Vmid,1) && max(abs(Vroi(:)-Vmid(:)))<1e-6, ...
            'BUG: Ctrl+Q@Q TAK meng-copy bentuk INTERPOLASI (harusnya lerp 0.5, dapat %d vertex).', size(Vroi,1));
        fprintf('[OK] (B) interpolasi ON -> Ctrl+Q pada DX tengah COPY bentuk lerp (%d vertex)\n', size(Vroi,1));
        % tutup ROI tanpa menyimpan
        try, kcb(fig, FakeKeyData('q','q',{'control'})); catch, end
    end

    % ================= ZOOM + KUNCI -> Ctrl+Q input vertex =================
    %   Bug user 2026-07-16: setelah zoom-in + kunci pandang, Ctrl+Q gagal input
    %   vertex krn kursor tetap mode zoom. FIX: i_suspendAxZoomForRoi mematikan MODE
    %   zoom (kursor crosshair) TAPI mempertahankan view zoom-in yg dikunci. Uji:
    %   ROI terbuka + axMainZoomOn=false + limit view TAK berubah.
    h = guidata(fig);
    if isfield(h,'axMain') && ishghandle(h.axMain) && isfield(h,'descSelRow')
        % Beri 1 baris ACT-FSR ber-bidang supaya Ctrl+Q punya seed (buka ROI headless).
        h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, psg, {}); guidata(fig,h);
        frZ = min(25, max(2, round(h.nF/3)));
        gotoFr(frZ); h = guidata(fig);
        kcb(fig, FakeKeyData('4','4',{'control'}));           % ACT-FSR@frZ
        h = guidata(fig);
        rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, psg);
        kZ = i_findRow(rows, fTag, frZ);
        if kZ>0
            rows{kZ}.vertices = [430 250; 500 315];
            h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, psg, rows);
            % Simulasi zoom-in + kunci: set limit sempit + state lock ON.
            zx = [200 900]; zy = [150 700];
            set(h.axMain,'XLim',zx,'YLim',zy);
            h.axMainZoomOn = true; h.axMainViewLock = true; h.axMainViewLim = [zx zy];
            % pilih baris DX ACT-FSR@frZ
            vis = []; if isfield(h,'descVisIdx'), vis = h.descVisIdx; end
            selR = kZ; if ~isempty(vis), vv=find(vis==kZ,1); if ~isempty(vv), selR=vv; end, end
            h.descSelRow = selR; guidata(fig,h);
            % Ctrl+Q -> buka ROI. Harus: zoom mode OFF + view limit tetap + ROI ada.
            kcb(fig, FakeKeyData('q','q',{'control'})); h = guidata(fig);
            assert(~(isfield(h,'axMainZoomOn') && h.axMainZoomOn), ...
                'BUG: Ctrl+Q tak mematikan mode zoom (kursor tetap zoom).');
            assert(isfield(h,'roiFaultPoly') && ~isempty(h.roiFaultPoly) && isvalid(h.roiFaultPoly), ...
                'BUG: Ctrl+Q saat zoom+kunci tak membuka ROI input vertex.');
            xln = get(h.axMain,'XLim'); yln = get(h.axMain,'YLim');
            assert(max(abs([xln yln]-[zx zy]))<1e-6, ...
                'BUG: view zoom-in TAK dipertahankan saat Ctrl+Q (X[%.0f %.0f] Y[%.0f %.0f]).', xln, yln);
            fprintf('[OK] ZOOM+KUNCI -> Ctrl+Q: mode zoom OFF, view zoom-in tetap, ROI terbuka\n');
            try, kcb(fig, FakeKeyData('q','q',{'control'})); catch, end   % tutup ROI
        end
    end

    if isfile(descPath), delete(descPath); end
    fprintf('==== ACT-FSR/PRP-FSR leak + copy-interpolasi Ctrl+Q + zoom-lock: SEMUA LULUS ✓ ====\n');
end

function k = i_findRow(rows, fTag, fr)
    k = 0;
    for i = 1:numel(rows)
        v = rows{i}.frame;
        if strcmp(strtrim(rows{i}.fNum), fTag) && isscalar(v) && isfinite(v) && round(v)==round(fr)
            k = i; return;
        end
    end
end

function df = i_findMat(dirPath)
    df = '';
    d = dir(fullfile(dirPath, '**', '*.mat'));
    for i = 1:numel(d)
        p = fullfile(d(i).folder, d(i).name);
        if isfile(strrep(p,'.mat','_faults.json')), df = p; return; end
    end
end

function idx = i_expIndexOf(fig, df)
    idx = -1; h = guidata(fig);
    if ~isfield(h,'list'), return; end
    for i=1:numel(h.list)
        if strcmp(h.list(i).file, df), idx = i; return; end
    end
end

function i_close(fig), try, if ishghandle(fig), delete(fig); end, catch, end, end
