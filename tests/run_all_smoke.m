function results = run_all_smoke(pattern)
%RUN_ALL_SMOKE  Jalankan SEMUA smoke test dalam SATU sesi MATLAB.
%   Tujuan: hindari bayar startup MATLAB berulang (jauh lebih cepat daripada
%   `matlab -batch` per test). Buka MATLAB sekali, panggil ini, selesai.
%
%   Pakai:
%     run_all_smoke                 % semua test_smoke_* + test_pab*_ (default)
%     run_all_smoke 'pab4'          % hanya file test yang namanya memuat 'pab4'
%     r = run_all_smoke;            % ambil ringkasan sbg struct array
%
%   Tiap test = fungsi yang LEMPAR error saat gagal. Runner menangkap error
%   per-test (satu gagal TIDAK menghentikan sisanya) lalu cetak ringkasan
%   PASS/FAIL/SKIP di akhir. SELALU MATLAB R2025b.
%
%   Lihat memori [[read-context-first]] & CLAUDE.md.

    here = fileparts(mfilename('fullpath'));
    addpath(here);                                      % tests/
    addpath(fileparts(here));                           % PAB/ (PAB*, pab_setup)
    addpath(fullfile(fileparts(here), 'pivcore_lib'));  % engine
    try, pab_setup; catch, end

    if nargin < 1, pattern = ''; end

    % SENYAP: test tak boleh rebut fokus / munculkan figure di layar.
    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

    % ---------- Kumpulkan daftar test ----------
    d = dir(fullfile(here, 'test_*.m'));
    names = sort({d.name});
    keep = false(1, numel(names));
    for i = 1:numel(names)
        n = names{i};
        isSmoke = startsWith(n, 'test_smoke_');
        isPab   = startsWith(n, 'test_pab');   % test_pab4_*, test_pab5_*, dst.
        keep(i) = isSmoke || isPab;
    end
    names = names(keep);
    if ~isempty(pattern)
        names = names(contains(lower(names), lower(pattern)));
    end
    if isempty(names)
        fprintf(2, 'Tidak ada test cocok pola "%s".\n', pattern);
        results = struct('name',{},'status',{},'secs',{},'err',{});
        return;
    end

    fprintf('\n========== RUN_ALL_SMOKE: %d test (1 sesi) ==========\n', numel(names));

    results = struct('name',{},'status',{},'secs',{},'err',{});
    for i = 1:numel(names)
        fn = names{i}(1:end-2);                          % buang '.m'
        fprintf('\n----- [%d/%d] %s -----\n', i, numel(names), fn);
        t0 = tic;
        status = 'PASS'; errMsg = '';
        try
            feval(fn);                                   % test tanpa argumen wajib
        catch ME
            % Konvensi lokal: pesan bertanda [SKIP] = lewati, bukan gagal.
            if contains(ME.message, '[SKIP]') || strcmp(ME.identifier, 'PAB:skip')
                status = 'SKIP';
            else
                status = 'FAIL';
            end
            errMsg = ME.message;
            fprintf(2, '  >> %s: %s\n', status, ME.message);
        end
        secs = toc(t0);
        results(end+1) = struct('name',fn,'status',status,'secs',secs,'err',errMsg); %#ok<AGROW>
        fprintf('  [%s] %.1fs\n', status, secs);
    end

    % ---------- Ringkasan ----------
    st = {results.status};
    nPass = sum(strcmp(st,'PASS'));
    nFail = sum(strcmp(st,'FAIL'));
    nSkip = sum(strcmp(st,'SKIP'));
    total = sum([results.secs]);

    fprintf('\n========== RINGKASAN ==========\n');
    for i = 1:numel(results)
        r = results(i);
        fprintf('  %-6s %6.1fs  %s\n', r.status, r.secs, r.name);
    end
    fprintf('  ------------------------------\n');
    fprintf('  PASS=%d  FAIL=%d  SKIP=%d   total %.1fs\n', nPass, nFail, nSkip, total);

    if nFail > 0
        fprintf(2, '\n%d test GAGAL:\n', nFail);
        for i = 1:numel(results)
            if strcmp(results(i).status,'FAIL')
                fprintf(2, '  - %s: %s\n', results(i).name, results(i).err);
            end
        end
    else
        fprintf('\nSemua test yang jalan LULUS (di luar SKIP).\n');
    end
end
