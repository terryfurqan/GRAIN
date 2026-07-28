function test_pab1_qpiv_prune()
%TEST_PAB1_QPIV_PRUNE  Kunci anti-bengkak: frame yang di-drop QPIV (Step 0)
%   TIDAK ikut terkemas, dan exp yang BELUM di-QPIV ditandai (hasQpiv=false +
%   penanda "⚠" di kolom Frame) supaya user sadar frame mati akan membesarkan
%   MAT PREP. Menguji jalur NYATA i_qpivKeptImages via PAB1 headless.
%
%   Jalankan: pab_setup; test_pab1_qpiv_prune   (SELALU MATLAB R2025b)
    fprintf('\n=== TEST PAB1 QPIV prune / penanda belum-QPIV ===\n');
    pab_setup();
    assert(~isempty(which('PAB1')), 'PAB1 tak di-path');

    troot = fullfile(tempdir, sprintf('pab1_qprune_%d', feature('getpid')));
    if isfolder(troot), rmdir(troot,'s'); end
    mkdir(troot);
    cleaner = onCleanup(@() i_rmdir(troot)); %#ok<NASGU>

    % --- 2 exp x 10 frame PNG bertekstur ---
    nF = 10;
    expA = fullfile(troot,'exp_A'); mkdir(expA);   % akan di-QPIV
    expB = fullfile(troot,'exp_B'); mkdir(expB);   % TIDAK di-QPIV
    base = i_texture(200, 260);
    for k = 1:nF
        imwrite(base, fullfile(expA, sprintf('f_%03d.png', k)));
        imwrite(base, fullfile(expB, sprintf('f_%03d.png', k)));
    end

    % --- Progress QPIV PALSU utk exp_A: skip=1 (stride 2) + ignore pasangan 2 ---
    %     consecutive, stride=2: files(1:2:10) -> 5 gambar post-skip.
    %     ignore pasangan k=2 -> buang gambar ke-(k+1)=3 -> tersisa 4.
    pf = fullfile(troot, 'PAB0_progress.mat');
    PIVlab_automasi_progress('setfile', pf);
    restoreProg = onCleanup(@() PIVlab_automasi_progress('resetfile')); %#ok<NASGU>
    eA = PIVlab_automasi_progress('empty');
    eA.expdir = expA; eA.key = PIVlab_automasi_progress('key', expA);
    eA.sequencing = 'consecutive'; eA.skip = 1;
    eA.qpiv_done = true; eA.qpiv_nframes = 5;   % 5 pasangan post-skip
    eA.ignore_frames = 2;                       % buang pasangan ke-2
    PIVlab_automasi_progress('set', eA);

    expectedA = 4;   % 10 -stride2-> 5 -ignore1-> 4

    % --- Luncurkan PAB1 headless -> i_rescan memanggil i_qpivKeptImages ---
    set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible','on')); %#ok<NASGU>
    PAB1(troot);
    f = findall(0,'Type','figure','-regexp','Name','^PAB1');
    if numel(f) > 1, f = f(1); end
    assert(~isempty(f), 'figure PAB1 tak terbentuk');
    closeFig = onCleanup(@() i_closeFig(f)); %#ok<NASGU>
    h = guidata(f);

    iA = find(strcmp({h.exps.path}, expA), 1);
    iB = find(strcmp({h.exps.path}, expB), 1);
    assert(~isempty(iA) && ~isempty(iB), 'kedua exp harus terpindai');

    % exp_A: frame drop QPIV tersaring -> nImg = expectedA, hasQpiv true.
    assert(h.exps(iA).hasQpiv == true, 'exp_A mestinya hasQpiv=true');
    assert(h.exps(iA).nImg == expectedA, ...
        sprintf('exp_A frame tersaring=%d (harusnya %d)', h.exps(iA).nImg, expectedA));
    assert(numel(h.exps(iA).files) == expectedA, 'files exp_A tak ikut tersaring');
    assert(~isempty(h.exps(iA).qOut) && h.exps(iA).qOut == expectedA, ...
        'qOut exp_A harus = jumlah frame lolos');

    % exp_B: belum di-QPIV -> hasQpiv=false, semua frame penuh, ditandai "⚠".
    assert(h.exps(iB).hasQpiv == false, 'exp_B mestinya hasQpiv=false');
    assert(h.exps(iB).nImg == nF, 'exp_B (belum QPIV) harus penuh nF frame');
    D = get(h.tbl,'Data');
    frameCellB = D{iB,2};
    assert(ischar(frameCellB) && contains(frameCellB, '⚠'), ...
        'kolom Frame exp_B harus bertanda ⚠ (belum QPIV)');
    frameCellA = D{iA,2};
    assert(~(ischar(frameCellA) && contains(frameCellA,'⚠')), ...
        'exp_A (sudah QPIV) tak boleh bertanda ⚠');

    fprintf('  OK: exp_A 10->%d frame (drop QPIV tersaring), exp_B ditandai belum-QPIV.\n', ...
        expectedA);
    fprintf('=== LULUS ===\n');
end

% ---------------------------------------------------------------------
function img = i_texture(H, W)
    [xx,yy] = meshgrid(1:W, 1:H);
    img = uint8(128 + 60*sin(xx/7) .* cos(yy/9));
end

function i_closeFig(f)
    try, if all(ishghandle(f)), delete(f); end, catch, end
end

function i_rmdir(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
