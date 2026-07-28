function test_smoke_grain4axpot()
%TEST_SMOKE_GRAIN4AXPOT  Produksi RAW + CLEAN untuk folder P-HF (headless, senyap).
    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

    expDir = fullfile(fullfile(grain_fixture_root(),'EXP_coll','EXP Q1','P-HF-4cm-F'));
    if ~isfolder(expDir)
        fprintf('[SKIP] folder uji absen: %s\n', expDir); return;
    end

    fig = GRAIN4AXPOT('expDir', expDir);   % builds GUI (invisible)
    h = guidata(fig);

    % Drive keempat tombol lewat callback yang sama (klik).
    for lbl = {'AX-POT RAW0','AX-POT RAW1','AX-POT CLEAN','AX-SLIP'}
        cb = i_findButton(fig, lbl{1});
        assert(~isempty(cb), sprintf('Tombol %s tak ditemukan.', lbl{1}));
        feval(get(cb,'Callback'), cb, []);
    end

    % Output kini ke CLCC/<namaFolder>/ dgn nama <kelompok EXP>_<jenis plot>.pdf.
    [~, sub] = fileparts(expDir);
    outDir = fullfile(fileparts(which('GRAIN4AXPOT')),'CLCC', sub);
    assert(isfile(fullfile(outDir,[sub '_RAW0.pdf'])),   'PDF RAW0 tak dibuat.');
    assert(isfile(fullfile(outDir,[sub '_RAW1.pdf'])),   'PDF RAW1 tak dibuat.');
    assert(isfile(fullfile(outDir,[sub '_CLEAN.pdf'])),  'PDF CLEAN tak dibuat.');
    assert(isfile(fullfile(outDir,[sub '_AXSLIP.pdf'])), 'PDF AXSLIP tak dibuat.');
    assert(isfile(fullfile(outDir,'PAB4AXPOT.mat')),     'MAT tak dibuat.');

    S = load(fullfile(outDir,'PAB4AXPOT.mat'));
    assert(isfield(S,'raw0') && isfield(S,'raw1') && isfield(S,'clean') && isfield(S,'axslip'), ...
        'MAT harus punya field raw0, raw1, clean & axslip.');
    assert(numel(S.clean.panels) == numel(S.clean.files), 'Jumlah panel != jumlah file.');

    if ishghandle(fig), close(fig); end
    fprintf('[OK] test_smoke_grain4axpot: RAW0+RAW1+CLEAN+AXSLIP PDF + PAB4AXPOT.mat (%d exp)\n', ...
        numel(S.clean.files));
end

function btn = i_findButton(fig, label)
    btn = [];
    cc = findall(fig,'Style','pushbutton');
    for c = cc(:).'
        if strcmp(get(c,'String'), label), btn = c; return; end
    end
end
