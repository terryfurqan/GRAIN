function test_pab1_qpiv_prune_naturalsort()
%TEST_PAB1_QPIV_PRUNE_NATURALSORT  Regresi bug urutan file: frame yang di-flag
%   PAB0 (QPIV) HARUS benar-benar hilang di PAB1 meski nama file TAK ber-padding
%   (urutan leksikografik PAB0 != naturalSort PAB1). Menguji jalur by-NAMA
%   (qpiv_kept_names / ignore_names) + fallback indeks lama.
%
%   Bug: ignore_frames = indeks POSISIONAL pada urutan PAB0 (sort leksikografik).
%   Nama unpadded 'f_1..f_12' -> sort: f_1,f_10,f_11,f_12,f_2,... ; naturalSort:
%   f_1,f_2,...,f_12. Indeks meleset -> file salah dibuang, frame mati lolos.
%   Fix: buang by NAMA (kebal urutan).
%
%   Jalankan: pab_setup; test_pab1_qpiv_prune_naturalsort   (SELALU R2025b)
    fprintf('\n=== TEST PAB1 QPIV prune (naturalsort / by-name) ===\n');
    pab_setup();
    assert(~isempty(which('PAB1')), 'PAB1 tak di-path');

    troot = fullfile(tempdir, sprintf('pab1_qns_%d', feature('getpid')));
    if isfolder(troot), rmdir(troot,'s'); end
    mkdir(troot);
    cleaner = onCleanup(@() i_rmdir(troot)); %#ok<NASGU>

    nImg = 12;                      % f_1.jpg .. f_12.jpg (UNPADDED)
    base = i_texture(200, 260);

    % exp_KEPT : jalur-1 (qpiv_kept_names) — daftar LOLOS eksplisit
    % exp_IGN  : jalur-2 (ignore_names)    — daftar DIBUANG eksplisit
    % exp_OLD  : jalur-3 (fallback indeks) — entry pra-patch (tanpa nama)
    expKept = fullfile(troot,'exp_KEPT'); mkdir(expKept);
    expIgn  = fullfile(troot,'exp_IGN');  mkdir(expIgn);
    expOld  = fullfile(troot,'exp_OLD');  mkdir(expOld);
    names = cell(1,nImg);
    for k = 1:nImg
        names{k} = sprintf('f_%d.jpg', k);   % UNPADDED
        imwrite(base, fullfile(expKept, names{k}));
        imwrite(base, fullfile(expIgn,  names{k}));
        imwrite(base, fullfile(expOld,  names{k}));
    end

    pf = fullfile(troot, 'PAB0_progress.mat');
    PIVlab_automasi_progress('setfile', pf);
    restoreProg = onCleanup(@() PIVlab_automasi_progress('resetfile')); %#ok<NASGU>

    % Frame yang HARUS hilang (di ruang urutan BENAR): f_3.jpg & f_7.jpg.
    dropNames = {'f_3.jpg','f_7.jpg'};
    keptNames = setdiff(names, dropNames, 'stable');   % 10 nama, urutan benar
    assert(numel(keptNames) == nImg - numel(dropNames), 'setdiff kept salah');

    % --- exp_KEPT: jalur-1 whitelist by nama ---
    eK = PIVlab_automasi_progress('empty');
    eK.expdir = expKept; eK.key = PIVlab_automasi_progress('key', expKept);
    eK.sequencing = 'consecutive'; eK.skip = 0;
    eK.qpiv_done = true; eK.qpiv_nframes = nImg - 1;
    eK.ignore_frames = [2 6];              % (diabaikan krn ada kept_names)
    eK.qpiv_kept_names = keptNames;
    PIVlab_automasi_progress('set', eK);

    % --- exp_IGN: jalur-2 buang by nama ---
    eI = PIVlab_automasi_progress('empty');
    eI.expdir = expIgn; eI.key = PIVlab_automasi_progress('key', expIgn);
    eI.sequencing = 'consecutive'; eI.skip = 0;
    eI.qpiv_done = true; eI.qpiv_nframes = nImg - 1;
    eI.ignore_names = dropNames;
    PIVlab_automasi_progress('set', eI);

    % --- exp_OLD: jalur-3 fallback indeks (entry lama tanpa nama) ---
    eO = PIVlab_automasi_progress('empty');
    eO.expdir = expOld; eO.key = PIVlab_automasi_progress('key', expOld);
    eO.sequencing = 'consecutive'; eO.skip = 0;
    eO.qpiv_done = true; eO.qpiv_nframes = nImg - 1;
    eO.ignore_frames = 2;   % consecutive: buang gambar ke-3 (SATU frame)
    PIVlab_automasi_progress('set', eO);

    % --- Luncurkan PAB1 headless ---
    set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible','on')); %#ok<NASGU>
    PAB1(troot);
    f = findall(0,'Type','figure','-regexp','Name','^PAB1');
    if numel(f) > 1, f = f(1); end
    assert(~isempty(f), 'figure PAB1 tak terbentuk');
    closeFig = onCleanup(@() i_closeFig(f)); %#ok<NASGU>
    h = guidata(f);

    iK = find(strcmp({h.exps.path}, expKept), 1);
    iI = find(strcmp({h.exps.path}, expIgn),  1);
    iO = find(strcmp({h.exps.path}, expOld),  1);
    assert(~isempty(iK)&&~isempty(iI)&&~isempty(iO), 'ketiga exp harus terpindai');

    % === Jalur 1: whitelist ===
    keptK = i_base(h.exps(iK).files);
    assert(numel(keptK) == numel(keptNames), ...
        sprintf('exp_KEPT: %d frame (harus %d)', numel(keptK), numel(keptNames)));
    assert(~any(strcmpi(keptK,'f_3.jpg')) && ~any(strcmpi(keptK,'f_7.jpg')), ...
        'exp_KEPT: frame ber-flag (f_3/f_7) MASIH ada — BUG belum terperbaiki!');
    assert(isequal(keptK(:)', lower(keptNames(:)')), ...
        'exp_KEPT: urutan tak mengikuti daftar QPIV');

    % === Jalur 2: ignore by nama ===
    keptI = i_base(h.exps(iI).files);
    assert(numel(keptI) == nImg - numel(dropNames), ...
        sprintf('exp_IGN: %d frame (harus %d)', numel(keptI), nImg-numel(dropNames)));
    assert(~any(strcmpi(keptI,'f_3.jpg')) && ~any(strcmpi(keptI,'f_7.jpg')), ...
        'exp_IGN: frame ber-flag MASIH ada — BUG!');

    % === Jalur 3: fallback indeks (entry lama) TETAP jalan (buang 1) ===
    assert(h.exps(iO).hasQpiv == true, 'exp_OLD hasQpiv harus true');
    assert(h.exps(iO).nImg == nImg - 1, ...
        sprintf('exp_OLD fallback indeks: %d frame (harus %d)', h.exps(iO).nImg, nImg-1));

    fprintf('  OK: by-name whitelist & ignore membuang f_3/f_7 tepat; fallback indeks utuh.\n');
    fprintf('=== LULUS ===\n');
end

% ---------------------------------------------------------------------
function img = i_texture(H, W)
    [xx,yy] = meshgrid(1:W, 1:H);
    img = uint8(128 + 60*sin(xx/7) .* cos(yy/9));
end

function b = i_base(files)
    b = cell(1,numel(files));
    for i = 1:numel(files)
        [~,nm,ext] = fileparts(char(files{i})); b{i} = lower([nm ext]);
    end
end

function i_closeFig(f)
    try, if all(ishghandle(f)), delete(f); end, catch, end
end

function i_rmdir(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
