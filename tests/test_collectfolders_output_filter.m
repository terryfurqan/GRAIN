function test_collectfolders_output_filter()
%TEST_COLLECTFOLDERS_OUTPUT_FILTER  Kunci: scan rekursif TIDAK menyeret folder
%   EKSPOR bergambar (PAB_export/PABLINK_export/velmag/shear/_preview) sbg
%   "eksperimen", TAPI folder input sah (termasuk yg kebetulan bernama PIV_*)
%   TETAP terpindai. Melindungi dari pembengkakan/perlambatan daftar exp GRAIN1.
%
%   HEADLESS. Jalankan: grain_setup; test_collectfolders_output_filter
    grain_setup();

    root = fullfile(tempdir, sprintf('cf_filter_%d', feature('getpid')));
    if isfolder(root); rmdir(root, 's'); end
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>

    % 1x1 px JPEG dummy (isi tak penting; collectFolders hanya cek listImages).
    dummy = uint8(zeros(4,4,3));
    writeJpg = @(dir_, nm) imwrite(dummy, fullfile(dir_, nm));
    mk = @(varargin) i_mkdirp(fullfile(root, varargin{:}));

    % --- Folder input SAH: eksperimen asli ---
    e1 = mk('5 cm-1');          writeJpg(e1, 'f001.jpg'); writeJpg(e1, 'f002.jpg');
    % Eksperimen sah yang kebetulan berawalan "PIV_" (domain user) HARUS lolos.
    pivExp = mk('PIV_uji_lab');  writeJpg(pivExp, 'a001.jpg');

    % --- Folder EKSPOR bergambar: HARUS diabaikan ---
    velmag = mk('PAB_export', 'P-CON', 'velmag'); writeJpg(velmag, 'x_velmag_f001.jpg');
    shear  = mk('PAB_export', 'P-CON', 'shear');  writeJpg(shear,  'x_shear_f001.jpg');
    prev   = mk('PAB_export', '_preview');        writeJpg(prev,   'PREVIEW_1.jpg');
    panel  = mk('PABLINK_export', 'pair', 'panel'); writeJpg(panel, 'p_f001.jpg');
    % Keluaran lama RAW/GS/EXIF (regresi filter lama) juga harus tetap diabaikan.
    rawOut = mk('RAW_olahan');    writeJpg(rawOut, 'r001.jpg');

    found = batchpivprep2.io.collectFolders(root, true);
    names = arrayfun(@(f) i_leaf(f.path), found, 'UniformOutput', false);

    % Yang WAJIB ada:
    assert(any(strcmp(names, '5 cm-1')),      'Eksperimen asli "5 cm-1" hilang dari scan.');
    assert(any(strcmp(names, 'PIV_uji_lab')), 'Eksperimen input "PIV_*" salah dipangkas.');

    % Yang WAJIB TIDAK ada (folder ekspor bergambar & keluaran olahan):
    banned = {'velmag','shear','_preview','panel','RAW_olahan'};
    for k = 1:numel(banned)
        assert(~any(strcmp(names, banned{k})), ...
            'Folder ekspor "%s" salah terpindai sbg eksperimen.', banned{k});
    end
    % Folder induk ekspor sendiri (PAB_export/PABLINK_export) tak berisi gambar
    % langsung, jadi memang tak muncul; pastikan begitu.
    assert(~any(strcmp(names, 'PAB_export')),     'PAB_export induk salah terpindai.');
    assert(~any(strcmp(names, 'PABLINK_export')), 'PABLINK_export induk salah terpindai.');

    fprintf('OK test_collectfolders_output_filter: %d exp sah (%s); ekspor terpangkas.\n', ...
        numel(found), strjoin(names, ', '));
end

function p = i_mkdirp(p)
    if ~isfolder(p); mkdir(p); end
end

function nm = i_leaf(p)
    [~, nm] = fileparts(p);
end
