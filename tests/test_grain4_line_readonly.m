function test_grain4_line_readonly(rootDir)
%TEST_GRAIN4_LINE_READONLY  GRAIN4 = PEMBACA garis PSG (read-only). Buktikan bahwa
%   TAK ADA jalur di GRAIN4 yang menulis/menggeser/menghitung-ulang garis PSG:
%     A  Setelah load, garis PSG aktif = id + koordinat TERSIMPAN (_potdata.json).
%     B  Menggeser h.line secara programatik lalu render (afterRenderMain) ->
%        i_freezePsgLine RE-ASSERT garis ke nilai tersimpan; h.activePsgId TETAP.
%        (Ini insiden P-CON-F1: dulu render/geser -> psgId baru -> baris DESC yatim.)
%     C  ROI garis PSG dibuat NON-INTERAKTIF (InteractionsAllowed='none').
%     D  Save TIDAK mengubah id/geometri garis di _potdata.json (hanya kurva/POI).
%     E  Tombol tulis-garis DIBUANG dari GUI: 'Simpan garis' / 'Hapus garis' /
%        '★ Jadikan L1' / '⊞ Generate' tak ada. 'Aktifkan garis' TETAP ada.
%
%   SENYAP: DefaultFigureVisible off. Fixture = experiment ber-_potdata.json (garis
%   PSG) di EXP_coll; absen -> [SKIP]. SELALU MATLAB R2025b. Data user DILINDUNGI
%   (backup+restore sidecar via i_guardSidecars).

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(fileparts(here)));                 % GRAIN/ (GRAIN4.m)
    addpath(fullfile(fileparts(here), 'pivcore_lib'));  % engine
    try, grain_setup; catch, end

    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

    % ---------- Fixture: exp ber-_potdata.json (punya psgLines) ----------
    if nargin < 1 || isempty(rootDir)
        cand = {'/Users/terryfurqan/MACTERR_shared/EXP_coll/EXP Q1/P-CON-4cm-F', ...
                '/Users/terryfurqan/MACTERR_shared/EXP_coll/P-CON-4cm-F'};
        rootDir = '';
        for i = 1:numel(cand)
            if isfolder(cand{i}) && ~isempty(i_findMatWithLine(cand{i})), rootDir = cand{i}; break; end
        end
        if isempty(rootDir), rootDir = i_searchFixture('/Users/terryfurqan/MACTERR_shared/EXP_coll'); end
    end
    if isempty(rootDir) || ~isfolder(rootDir)
        fprintf('[SKIP] test_grain4_line_readonly: fixture (exp ber-_potdata.json) tak ada.\n'); return;
    end
    df = i_findMatWithLine(rootDir);
    if isempty(df)
        fprintf('[SKIP] test_grain4_line_readonly: tak ada .mat ber-garis PSG di %s\n', rootDir); return;
    end
    [~, baseName] = fileparts(df);
    fprintf('Fixture: %s\n', baseName);
    sidecarGuard = i_guardSidecars(df); %#ok<NASGU>   % JANGAN dihapus (onCleanup restore)

    % ---------- Build + load ----------
    fig = GRAIN4(rootDir);
    cleanFig = onCleanup(@() i_safeClose(fig)); %#ok<NASGU>
    idx = i_expIndexOf(fig, df);
    assert(idx >= 1, 'exp fixture ada di daftar shell');
    pivui.grain4Shell.loadExperiment(fig, idx);
    h = guidata(fig);
    assert(strcmp(h.df, df), 'exp fixture termuat');

    % ================= A. Garis aktif = TERSIMPAN =================
    fprintf('==== A. Garis aktif = id + koordinat TERSIMPAN ====\n');
    id0 = h.activePsgId;
    assert(~isempty(id0), 'A: ada garis PSG aktif setelah load');
    [ln0, idx0] = pivcore.io.grain4PotData.findLine(h.doc, id0);
    assert(idx0 >= 1, 'A: garis aktif ada di doc tersimpan');
    p1_0 = ln0.p1(:).'; p2_0 = ln0.p2(:).';
    assert(isequal(round(h.line.p1(:).'), round(p1_0)) || norm(h.line.p1(:).'-p1_0) < 1, ...
        'A: h.line.p1 = koordinat tersimpan');
    fprintf('[OK] A: garis aktif "%s" p1=[%.0f %.0f] p2=[%.0f %.0f]\n', id0, p1_0, p2_0);

    % ================= B. Geser h.line + render -> psgId TETAP =================
    fprintf('==== B. Geser h.line + render -> psgId BEKU (tak yatim) ====\n');
    h = guidata(fig);
    % Geser jauh MELEWATI grid TOLPX=50 (200 px) — dulu ini melahirkan id baru.
    h.line.p1 = h.line.p1 + 200; h.line.p2 = h.line.p2 + 200;
    guidata(fig, h);
    pivui.grain4Shell.renderMain(fig);         % memicu afterRenderMain -> i_freezePsgLine
    h = guidata(fig);
    assert(strcmp(h.activePsgId, id0), ...
        'B: activePsgId TETAP "%s" (dapat "%s") setelah geser+render', id0, h.activePsgId);
    assert(norm(h.line.p1(:).' - p1_0) < 1, 'B: h.line di-RE-ASSERT ke koordinat tersimpan');
    % Simulasikan hook onLineChanged (dulu men-derive id baru) -> id harus TETAP.
    i0 = h.activePsgId; %#ok<NASGU>
    feval(@()[]);                            % no-op agar jelas urutan
    if isfield(h,'hooks') && isfield(h.hooks,'onLineChanged') && ~isempty(h.hooks.onLineChanged)
        h.line.p1 = h.line.p1 + 137; guidata(fig, h);   % geser lagi
        h.hooks.onLineChanged(fig);
        h = guidata(fig);
        assert(strcmp(h.activePsgId, id0), 'B: onLineChanged TAK mengubah activePsgId');
    end
    fprintf('[OK] B: psgId beku "%s" walau h.line digeser 200+137 px\n', id0);

    % ================= C. ROI non-interaktif =================
    fprintf('==== C. ROI garis PSG NON-INTERAKTIF ====\n');
    h = guidata(fig);
    if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi)
        ia = '';
        try, ia = char(h.roi.InteractionsAllowed); catch, end
        assert(strcmp(ia,'none'), 'C: ROI.InteractionsAllowed=none (dapat "%s")', ia);
        fprintf('[OK] C: ROI garis PSG dibekukan (InteractionsAllowed=none)\n');
    else
        fprintf('[OK] C: tak ada ROI garis PSG (garis statik) — tak ada yg bisa digeser\n');
    end

    % ================= D. Save (ke disk) tak mengubah geometri/id garis =========
    fprintf('==== D. Save: id+geometri garis TERSIMPAN tak berubah ====\n');
    h = guidata(fig);
    nLinesBefore = numel(h.doc.psgLines);
    % Cemari h.line sebelum Save (dulu i_captureActiveLine baca ROI -> derive id
    % baru -> garis TERTIMPA). Save fixture dilindungi i_guardSidecars (restore).
    h.line.p1 = h.line.p1 - 321; h.line.p2 = h.line.p2 - 321; guidata(fig, h);
    i_fire(fig, '💾 Save Progress');
    docDisk = pivcore.io.grain4PotData.read(df);   % baca _potdata.json dari disk
    [lnS, idxS] = pivcore.io.grain4PotData.findLine(docDisk, id0);
    assert(idxS >= 1, 'D: garis id0 masih ada di _potdata.json setelah Save');
    assert(norm(lnS.p1(:).' - p1_0) < 1 && norm(lnS.p2(:).' - p2_0) < 1, ...
        'D: koordinat garis di _potdata.json TAK berubah oleh Save');
    assert(numel(docDisk.psgLines) == nLinesBefore, ...
        'D: jumlah garis PSG di disk tak bertambah saat Save (%d vs %d)', ...
        numel(docDisk.psgLines), nLinesBefore);
    fprintf('[OK] D: Save tak menyentuh id/koordinat garis (tak ada garis baru)\n');

    % ================= E. Tombol tulis-garis DIBUANG =================
    fprintf('==== E. GUI tak punya tombol tulis-garis ====\n');
    assert(~i_hasButton(fig, 'Simpan garis'), 'E: tombol "Simpan garis" harus DIBUANG');
    assert(~i_hasButton(fig, 'Hapus garis'),  'E: tombol "Hapus garis" harus DIBUANG');
    assert(~i_hasButtonContains(fig, 'Jadikan L1'), 'E: tombol "★ Jadikan L1" harus DIBUANG');
    assert(~i_hasButtonContains(fig, 'Generate'),   'E: tombol "⊞ Generate" harus DIBUANG');
    % 2026-07-19: selektor garis PSG (listbox + "Aktifkan garis") DISEMBUNYIKAN atas
    % permintaan user (GRAIN4 = pembaca; garis dipilih otomatis saat load). Handle
    % lstLines tetap ada (Visible='off') utk logika lain; tombol "Aktifkan garis" DIBUANG.
    assert(~i_hasButtonContains(fig, 'Aktifkan'),   'E: tombol "Aktifkan garis" kini DIBUANG/disembunyikan');
    h = guidata(fig);
    assert(isfield(h,'lstLines') && ishghandle(h.lstLines) && strcmp(get(h.lstLines,'Visible'),'off'), ...
        'E: listbox garis PSG (handle) tetap ada tapi Visible=off');
    fprintf('[OK] E: tombol tulis-garis dibuang; selektor garis PSG disembunyikan\n');

    fprintf('\n==== GRAIN4 LINE READ-ONLY SEMUA LULUS ✓ ====\n');
end

% ===================== helpers =====================
function df = i_findMatWithLine(dirPath)
%I_FINDMATWITHLINE  .mat pertama di dirPath yang punya _potdata.json ber-psgLines.
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

function tf = i_hasButton(fig, str)
    tf = ~isempty(i_findButtonExact(fig, str));
end
function tf = i_hasButtonContains(fig, sub)
    all = findall(fig, 'Type','uicontrol');
    tf = false;
    for i = 1:numel(all)
        try
            if any(strcmp(get(all(i),'Style'),{'pushbutton','togglebutton'})) ...
                    && contains(char(get(all(i),'String')), sub), tf = true; return; end
        catch
        end
    end
end
function hb = i_findButtonExact(fig, str)
    hb = [];
    all = findall(fig, 'Type','uicontrol');
    for i = 1:numel(all)
        try
            if any(strcmp(get(all(i),'Style'),{'pushbutton','togglebutton'})) ...
                    && strcmp(char(get(all(i),'String')), str), hb = all(i); return; end
        catch
        end
    end
end

function i_fire(fig, str)
    hb = i_findButtonExact(fig, str);
    assert(~isempty(hb), 'tombol "%s" tak ditemukan', str);
    cb = get(hb, 'Callback');
    if ~isempty(cb), cb(hb, []); end
end

function i_safeClose(fig)
    try, if ishghandle(fig), delete(fig); end, catch, end
end
