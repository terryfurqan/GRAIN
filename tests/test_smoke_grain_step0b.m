function test_smoke_grain_step0b()
%TEST_SMOKE_GRAINSA_STEP0B  Smoke test GRAINSA0b (exclusion frame) — TANPA GUI.
%
%   Memvalidasi inti yang dipakai PAB_step_0b:
%     1. pivprepFrameExclusion menggabungkan DUA detektor:
%        - MATI   : |V| puncak < ambang (mesin berhenti).
%        - INTERVAL: dt EXIF outlier dari median (counter-wrap shutter).
%        dengan alasan per-frame yang benar, dan masing-masing bisa dimatikan.
%     2. pivprepRawExifDt membaca dt EXIF langsung dari JPG (diuji pada data
%        nyata 5 cm-1 bila tersedia; dilewati bila tidak).
%     3. PAB_step_0b + engine QPIV ter-path.
%
%   Jalankan: grain_setup; test_smoke_grain_step0b
%   SELALU MATLAB R2025b.

    fprintf('\n=== SMOKE GRAINSA0b (PAB_step_0b) ===\n');
    grain_setup();
    assert(~isempty(which('pivprepFrameExclusion')), 'pivprepFrameExclusion tak di-path');
    assert(~isempty(which('pivprepRawExifDt')),      'pivprepRawExifDt tak di-path');
    assert(~isempty(which('PAB_step_0b')),           'PAB_step_0b tak di-path');
    assert(~isempty(which('PIVlab_automasi_qpiv')),  'engine QPIV tak di-path');
    assert(~isempty(which('batchpivprep2.io.collectFolders')), 'collectFolders tak di-path');

    % --- 1. Detektor gabungan: mati + interval -------------------------
    peak = [5 5 0.1 5 5 5 0.05 5 5 5];           % frame 3 & 7 = mati
    dt   = [12 12 12 40 12 12 12 12 12 12];       % frame 4 = interval outlier
    ex = pivprepFrameExclusion(peak, dt, struct());   % default (auto thresh, ±50%)
    fprintf('  [1] motionMin auto=%.3g, medianDt=%.3g, dtTol=%.3g\n', ex.motionMin, ex.medianDt, ex.dtTol);
    assert(isequal(find(ex.deadMask), [3 7]), 'detektor MATI salah');
    assert(isequal(find(ex.timeMask), 4),     'detektor INTERVAL salah');
    assert(isequal(find(ex.ignore),  [3 4 7]),'gabungan ignore salah');
    assert(strcmp(ex.reason{3},'mati') && strcmp(ex.reason{4},'interval') && strcmp(ex.reason{7},'mati'), ...
        'alasan per-frame salah');
    fprintf('  [1b] mati={3,7} interval={4} ignore={3,4,7} + alasan OK\n');

    % Matikan tiap detektor -> mask kosong sesuai.
     exM = pivprepFrameExclusion(peak, dt, struct('useTime',false));
    assert(~any(exM.timeMask), 'useTime=false harus matikan interval');
    exT = pivprepFrameExclusion(peak, dt, struct('useMotion',false));
    assert(~any(exT.deadMask), 'useMotion=false harus matikan mati');
    % dt NaN tak boleh auto-buang.
    exN = pivprepFrameExclusion([5 5 5], [NaN NaN NaN], struct());
    assert(~any(exN.timeMask), 'dt NaN tak boleh ditandai interval');
    fprintf('  [2] toggle detektor & guard dt-NaN OK\n');

    % --- 2. EXIF dt langsung dari JPG (data nyata, bila ada) -----------
    raw = fullfile(grain_fixture_root(),'5 cm-1');
    if isfolder(raw)
        d = dir(fullfile(raw,'*.JPG')); [~,o]=sort({d.name}); names={d(o).name};
        fn1 = names(1:end-1)'; fn2 = names(2:end)';
        info = pivprepRawExifDt(raw, fn1, fn2);
        fprintf('  [3] 5cm-1: %d frame, status=%s, median dt=%.3g s, valid=%d\n', ...
            info.nFrames, info.status, info.median_dt, info.n_valid);
        assert(info.n_valid > 0, 'dt EXIF 5cm-1 harusnya terbaca');
        assert(abs(info.median_dt - 12) < 3, 'median dt 5cm-1 diharapkan ~12 s');
    else
        fprintf('  [3] (folder 5 cm-1 tak ada — uji EXIF nyata dilewati)\n');
    end

    fprintf('=== SMOKE GRAINSA0b: LULUS ===\n\n');
end
