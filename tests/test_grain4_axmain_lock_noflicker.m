function test_grain4_axmain_lock_noflicker(rootDir)
%TEST_GRAIN4_AXMAIN_LOCK_NOFLICKER  Anti-FLICKER kunci pandang axMain (GRAIN4).
%   Bug user (2026-07-18): zoom axMain -> klik 🔒 (kunci pandang) BERFUNGSI, tapi
%   saat GANTI FRAME zoom "flickering" balik ke ekstent penuh sesaat lalu ke view
%   terkunci -> menyulitkan observasi detail shear strain. Akar: renderMain shell
%   set XLim/YLim EKSTENT PENUH + colorbar memicu paint SEBELUM hook afterRenderMain
%   sempat mengembalikan view beku. FIX: listener 'MarkedClean' pada axMain yang
%   meng-reassert view beku SEBELUM paint -> tak ada frame penuh yang muncul.
%
%   Cakupan:
%     A  Kunci pandang ON -> listener MarkedClean terpasang (h.axMainLockLsnr valid).
%     B  Ganti frame (gotoFrame) saat terkunci -> XLim/YLim axMain TETAP = view beku
%        (tanpa ini XLim balik ke ekstent penuh, sumber flicker).
%     C  Selama render (MarkedClean dipicu), reassert menjaga limit == view beku
%        pada SETIAP frame yang di-scrub (2..4).
%     D  Lepas kunci (toggle OFF) -> listener DIBUANG (h.axMainLockLsnr kosong) +
%        view mengikuti ekstent penuh lagi.
%     E  Zoom OFF total juga membuang listener (tak ada listener menggantung).
%
%   SENYAP: DefaultFigureVisible off. Fixture = exp ber-_potdata.json (garis PSG).
%   Data user DILINDUNGI (backup+restore sidecar). SELALU MATLAB R2025b.

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(fileparts(here)));                 % GRAIN/ (GRAIN4.m)
    addpath(fullfile(fileparts(here), 'pivcore_lib'));  % engine
    try, grain_setup; catch, end

    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

    % ---------- Fixture ----------
    if nargin < 1 || isempty(rootDir)
        cand = {fullfile(grain_fixture_root(),'EXP_coll','EXP Q1','P-CON-4cm-F'), ...
                fullfile(grain_fixture_root(),'EXP_coll','P-CON-4cm-F')};
        rootDir = '';
        for i = 1:numel(cand)
            if isfolder(cand{i}) && ~isempty(i_findMatWithLine(cand{i})), rootDir = cand{i}; break; end
        end
        if isempty(rootDir), rootDir = i_searchFixture(fullfile(grain_fixture_root(),'EXP_coll')); end
    end
    if isempty(rootDir) || ~isfolder(rootDir)
        fprintf('[SKIP] test_grain4_axmain_lock_noflicker: fixture tak ada.\n'); return;
    end
    df = i_findMatWithLine(rootDir);
    if isempty(df)
        fprintf('[SKIP] test_grain4_axmain_lock_noflicker: tak ada .mat ber-garis PSG di %s\n', rootDir); return;
    end
    [~, baseName] = fileparts(df);
    fprintf('Fixture: %s\n', baseName);
    sidecarGuard = i_guardSidecars(df); %#ok<NASGU>

    % ---------- Build + load ----------
    fig = GRAIN4(rootDir);
    cleanFig = onCleanup(@() i_safeClose(fig)); %#ok<NASGU>
    idx = i_expIndexOf(fig, df);
    assert(idx >= 1, 'exp fixture ada di daftar shell');
    pivui.grain4Shell.loadExperiment(fig, idx);
    h = guidata(fig);
    assert(strcmp(h.df, df), 'exp fixture termuat');
    nF = max(pivcore.util.scalarOr(h.nF,1), 4);

    % Pastikan data penuh (scrub frame >1). Mulai di frame 1.
    pivui.grain4Shell.gotoFrame(fig, 1);

    % ================= A. Kunci ON -> listener PostSet terpasang =================
    fprintf('==== A. Kunci pandang ON -> listener PostSet XLim/YLim terpasang ====\n');
    % Set view zoom-in buatan (setengah ekstent, di kuadran kiri-atas) lalu kunci.
    h = guidata(fig);
    xe = h.xExt; ye = h.yExt;
    zx = [xe(1), xe(1) + 0.5*diff(xe)];
    zy = [ye(1), ye(1) + 0.5*diff(ye)];
    set(h.axMain, 'XLim', zx, 'YLim', zy);
    i_fireViewLock(fig);   % toggle kunci ON (i_onAxMainViewLock) -> lock mode STRETCH
    h = guidata(fig);
    assert(isfield(h,'axMainViewLock') && h.axMainViewLock, 'A: kunci pandang aktif');
    assert(numel(h.axMainViewLim)==4, 'A: axMainViewLim tersimpan');
    assert(isfield(h,'axMainLockLsnr') && ~isempty(h.axMainLockLsnr) ...
        && all(isvalid(h.axMainLockLsnr)), 'A: listener PostSet XLim/YLim terpasang (2)');
    Lbeku = h.axMainViewLim;
    % Kunci = bekukan view APA ADANYA -> == zoom yg dipasang (tanpa snap/stretch).
    assert(norm(Lbeku - [zx zy]) < 1e-6, 'A: view beku = zoom-in yg dipasang');
    fprintf('[OK] A: kunci ON (1:1), 2 listener PostSet, view beku X[%.0f %.0f] Y[%.0f %.0f]\n', Lbeku);

    % ================= B. Ganti frame -> ISI (XLim/YLim) TETAP zoom =================
    fprintf('==== B. Ganti frame terkunci -> ISI axMain TETAP zoom (tak kedip) ====\n');
    posLock = h.axMainPos;   % Position box (bingkai) harus tetap juga
    for k = 2:min(nF,4)
        pivui.grain4Shell.gotoFrame(fig, k);   % renderMain reset ke penuh -> PostSet timpa
        h = guidata(fig);
        cx = get(h.axMain,'XLim'); cy = get(h.axMain,'YLim');
        assert(norm([cx cy] - Lbeku) < 1e-6, ...
            'B: frame %d XLim/YLim TETAP view beku (ISI tak zoom-out) — dapat X[%.1f %.1f] Y[%.1f %.1f]', ...
            k, cx, cy);
        % TETAP 1:1: daspect manual dari renderMain TAK diubah kunci pandang.
        assert(strcmp(get(h.axMain,'DataAspectRatioMode'),'manual'), 'B: frame %d tetap 1:1 (DARmode=manual)', k);
        pnow = get(h.axMain,'Position');
        assert(norm(pnow - posLock) < 1e-4, 'B: frame %d Position bingkai TETAP', k);
    end
    pivui.grain4Shell.gotoFrame(fig, 1);
    h = guidata(fig);
    cx = get(h.axMain,'XLim'); cy = get(h.axMain,'YLim');
    assert(norm([cx cy] - Lbeku) < 1e-6, 'B: kembali ke frame 1 -> view beku tetap');
    fprintf('[OK] B: scrub frame 2..%d + balik -> ISI TETAP zoom (1:1, bingkai tetap)\n', min(nF,4));

    % ================= C. PostSet MENIMPA upaya set-ke-PENUH SEGERA =================
    fprintf('==== C. PostSet menimpa reset-ke-penuh (anti-flicker isi) ====\n');
    % Simulasikan renderMain: paksa set XLim/YLim ke EKSTENT PENUH. PostSet harus
    % SINKRON menimpanya kembali ke beku (sebelum paint) -> baca langsung = beku.
    set(h.axMain,'XLim',h.xExt,'YLim',h.yExt);
    h = guidata(fig);
    cx = get(h.axMain,'XLim'); cy = get(h.axMain,'YLim');
    assert(norm([cx cy] - Lbeku) < 1e-6, ...
        'C: set XLim/YLim=penuh SEGERA ditimpa PostSet ke beku (dapat X[%.1f %.1f] Y[%.1f %.1f])', cx, cy);
    fprintf('[OK] C: set-ke-penuh langsung ditimpa PostSet ke view beku (tanpa drawnow)\n');

    % ================= F. PostSet TETAP aktif saat ALAT ROI aktif =================
    % Bug user: flicker ISI zoom-out saat Ctrl+Q (bidang sesar) / Ctrl+W (taper) aktif.
    % Sebab lama: PostSet di-SKIP saat alat ROI ON -> render/overlay saat alat ON reset
    % XLim ke penuh & tak ditimpa. Fix: guard ROI DIBUANG (PostSet cuma menimpa XLim/
    % YLim, tak menyentuh vertex ROI). Uji: set flag alat ROI ON lalu paksa XLim=penuh
    % -> harus TETAP ditimpa ke beku.
    fprintf('==== F. Alat ROI aktif (taper/faultPoly/refHoriz) -> PostSet TETAP menimpa ====\n');
    for tool = {'taperOn','faultPolyOn','refHorizOn'}
        tf = tool{1};
        h = guidata(fig); h.(tf) = true; guidata(fig, h);   % simulasikan alat ROI ON
        set(h.axMain,'XLim',h.xExt,'YLim',h.yExt);          % render/overlay reset ke penuh
        h = guidata(fig);
        cx = get(h.axMain,'XLim'); cy = get(h.axMain,'YLim');
        assert(norm([cx cy] - Lbeku) < 1e-6, ...
            'F: %s ON -> XLim=penuh HARUS ditimpa ke beku (dapat X[%.1f %.1f])', tf, cx);
        h = guidata(fig); h.(tf) = false; guidata(fig, h);   % matikan lagi
    end
    fprintf('[OK] F: PostSet menimpa reset-ke-penuh walau alat ROI aktif (Ctrl+Q/Ctrl+W/ref)\n');

    % ================= D. Lepas kunci -> listener DIBUANG =================
    fprintf('==== D. Lepas kunci -> listener dibuang + ikut ekstent penuh ====\n');
    i_fireViewLock(fig);   % toggle kunci OFF
    h = guidata(fig);
    assert(~h.axMainViewLock, 'D: kunci pandang lepas');
    assert(isempty(h.axMainLockLsnr), 'D: listener PostSet dibuang');
    fprintf('[OK] D: kunci OFF -> listener dibuang (h.axMainLockLsnr kosong)\n');

    % ================= E. Zoom OFF total juga bersih =================
    fprintf('==== E. Zoom OFF total -> tak ada listener menggantung ====\n');
    % Kunci lagi -> listener terpasang -> lalu Zoom OFF (yg juga melepas kunci).
    set(h.axMain,'XLim',zx,'YLim',zy);
    i_fireViewLock(fig);
    h = guidata(fig);
    assert(~isempty(h.axMainLockLsnr) && all(isvalid(h.axMainLockLsnr)), 'E: listener terpasang (pra Zoom OFF)');
    % Nyalakan flag zoom lalu panggil toggle zoom -> jadi OFF (buang kunci+listener).
    h.axMainZoomOn = true; guidata(fig, h);
    i_fireZoom(fig);
    h = guidata(fig);
    assert(~h.axMainZoomOn, 'E: zoom OFF');
    assert(~h.axMainViewLock, 'E: kunci ikut lepas saat zoom OFF');
    assert(isempty(h.axMainLockLsnr), 'E: listener dibuang saat zoom OFF');
    fprintf('[OK] E: zoom OFF total -> kunci + listener bersih\n');

    fprintf('\n==== GRAIN4 AXMAIN LOCK ANTI-FLICKER SEMUA LULUS ✓ ====\n');
end

% ===================== helpers =====================
function df = i_findMatWithLine(dirPath)
    df = '';
    L = dir(fullfile(dirPath, '*.mat'));
    for i = 1:numel(L)
        cand = fullfile(L(i).folder, L(i).name);
        try
            doc = pivcore.io.grain4PotData.read(cand);
            if isstruct(doc) && isfield(doc,'psgLines') && ~isempty(doc.psgLines)
                pl = doc.psgLines{1};
                if isstruct(pl) && isfield(pl,'p1') && all(isfinite([pl.p1(:);pl.p2(:)])')
                    df = cand; return;
                end
            end
        catch
        end
    end
end

function root = i_searchFixture(base)
    root = '';
    if ~isfolder(base), return; end
    S = dir(fullfile(base, '**', '*.mat'));
    seen = {};
    for i = 1:numel(S)
        d = S(i).folder;
        if any(strcmp(seen, d)), continue; end
        seen{end+1} = d; %#ok<AGROW>
        if ~isempty(i_findMatWithLine(d)), root = d; return; end
    end
end

function idx = i_expIndexOf(fig, df)
    idx = -1; h = guidata(fig);
    if ~isfield(h,'list'), return; end
    for i = 1:numel(h.list)
        if strcmp(h.list(i).file, df), idx = i; return; end
    end
end

function hb = i_findButtonExact(fig, str)
    hb = [];
    a = findall(fig, 'Type','uicontrol');
    for i = 1:numel(a)
        try
            if any(strcmp(get(a(i),'Style'),{'pushbutton','togglebutton'})) ...
                    && strcmp(char(get(a(i),'String')), str), hb = a(i); return; end
        catch
        end
    end
end
function hb = i_findButtonContains(fig, sub)
    hb = [];
    a = findall(fig, 'Type','uicontrol');
    for i = 1:numel(a)
        try
            if any(strcmp(get(a(i),'Style'),{'pushbutton','togglebutton'})) ...
                    && contains(char(get(a(i),'String')), sub), hb = a(i); return; end
        catch
        end
    end
end

function i_fireViewLock(fig)
%I_FIREVIEWLOCK  Picu toggle KUNCI PANDANG (tombol 🔒 -> i_onAxMainViewLock).
    hb = i_findButtonContains(fig, '🔒');
    if isempty(hb), hb = i_findButtonExact(fig, 'btnAxViewLock'); end
    assert(~isempty(hb), 'tombol kunci pandang (🔒) tak ditemukan');
    cb = get(hb,'Callback'); assert(~isempty(cb),'kunci: callback kosong'); cb(hb, []);
end

function i_fireZoom(fig)
%I_FIREZOOM  Picu toggle ZOOM (tombol 🔍 -> i_onAxMainZoom).
    hb = i_findButtonContains(fig, '🔍');
    assert(~isempty(hb), 'tombol zoom (🔍) tak ditemukan');
    cb = get(hb,'Callback'); assert(~isempty(cb),'zoom: callback kosong'); cb(hb, []);
end

function i_safeClose(fig)
    try, if ishghandle(fig), delete(fig); end, catch, end
end
