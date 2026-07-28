function test_unpack_mask_inmemory()
%TEST_UNPACK_MASK_INMEMORY  Decode blob TANPA file temporer saat masking aktif.
%
%   unpackMat.i_writeMaskedImage kini decode blob dari MEMORI (Java ImageIO/
%   raster) alih-alih tulis+baca+delete berkas sementara per frame. Uji bahwa
%   hasilnya BENAR untuk kedua cabang decode:
%     A. GRAYSCALE (raster 1-band) -> kotak putih tertempel di posisi interpolasi.
%     B. RGB (getRGB 3-band)       -> kotak putih di KETIGA kanal.
%     C. Non-destruktif: blob asli di .mat TAK berubah (byte-identik sebelum/
%        sesudah unpack ber-masking).
%
%   Kita panggil unpackMat penuh (jalur produksi GRAIN2). Bila decode in-memory
%   salah, kotak tak muncul / warna kanal salah -> assert gagal.
%
%   Jalankan: grain_setup; test_unpack_mask_inmemory   (SELALU R2025b)
    fprintf('\n=== TEST unpack masking in-memory decode ===\n');
    here = fileparts(mfilename('fullpath'));
    addpath(here); addpath(fileparts(here));
    grain_setup();

    troot = fullfile(tempdir, sprintf('unpmask_%d', feature('getpid')));
    if isfolder(troot), rmdir(troot,'s'); end; mkdir(troot);
    cleaner = onCleanup(@() i_rmdir(troot)); %#ok<NASGU>

    nF = 4; H = 40; W = 70;
    % Kotak statis (rect_first==rect_last) -> posisi pasti di semua frame.
    box = struct('rect_first',[20 10 15 12], 'rect_last',[20 10 15 12], ...
        'frame_first',1, 'frame_last',nF);
    mask = struct('enabled',true,'fill',255,'boxes',box);

    % ===== A. GRAYSCALE =====
    dfG = fullfile(troot, 'expGray.mat');
    blobsBefore = i_makePrep(dfG, nF, H, W, false);   % grayscale
    assert(pivanalyzemat.core.maskSidecar.write(dfG, mask), 'tulis sidecar gray gagal');
    eG = i_entry(dfG, 'expGray');
    outG = pivanalyzemat.core.unpackMat(eG, 'Force', true, 'RootTmp', fullfile(troot,'tg'));
    rawG = i_readFrame(outG.path, 1);
    % region kotak [x=20..34, y=10..21] harus putih (>=250 karena JPEG Q95).
    assert(min(min(rawG(12:20, 22:32))) >= 245, 'A: gray region kotak tak putih');
    % luar kotak (pojok) tak putih.
    assert(rawG(2,2) < 245, 'A: gray luar kotak ikut putih (bocor)');
    fprintf('  [A] grayscale: kotak tertempel via decode in-memory OK.\n');

    % ===== B. RGB =====
    dfC = fullfile(troot, 'expRGB.mat');
    i_makePrep(dfC, nF, H, W, true);                  % RGB
    assert(pivanalyzemat.core.maskSidecar.write(dfC, mask), 'tulis sidecar rgb gagal');
    eC = i_entry(dfC, 'expRGB');
    outC = pivanalyzemat.core.unpackMat(eC, 'Force', true, 'RootTmp', fullfile(troot,'tc'));
    rawC = i_readFrame(outC.path, 1);
    assert(size(rawC,3) == 3, 'B: RGB frame bukan 3 kanal (%d)', size(rawC,3));
    for c = 1:3
        ch = rawC(:,:,c);
        assert(min(min(ch(12:20, 22:32))) >= 245, 'B: RGB kanal %d region tak putih', c);
    end
    % luar kotak: minimal satu kanal jelas < putih (warna asli terjaga).
    assert(rawC(2,2,1) < 245 || rawC(2,2,2) < 245 || rawC(2,2,3) < 245, ...
        'B: RGB luar kotak semua putih (bocor)');
    fprintf('  [B] RGB: kotak di 3 kanal via getRGB in-memory OK.\n');

    % ===== C. Non-destruktif blob =====
    S = load(dfG, 'prep');
    blobsAfter = S.prep.raw.blobs;
    assert(numel(blobsAfter) == numel(blobsBefore), 'C: jumlah blob berubah');
    same = true;
    for k = 1:numel(blobsBefore)
        if ~isequal(blobsBefore{k}, blobsAfter{k}); same = false; break; end
    end
    assert(same, 'C: blob RAW di .mat BERUBAH (masking harus non-destruktif)');
    fprintf('  [C] non-destruktif: blob RAW di .mat byte-identik OK.\n');

    fprintf('=== LULUS ===\n');
end

% ---------------------------------------------------------------------
function blobs = i_makePrep(matFile, nF, H, W, rgb)
%I_MAKEPREP  MAT PREP sintetis (grayscale/RGB) -> kembalikan cell blob RAW.
    names = cell(nF,1); blobs = cell(nF,1); idx = uint32(1:nF);
    for k = 1:nF
        if rgb
            img = uint8(zeros(H,W,3));
            img(:,:,1) = uint8(30+10*k); img(:,:,2) = uint8(60); img(:,:,3) = uint8(90);
        else
            img = uint8(40 + 8*k + zeros(H,W));
        end
        names{k} = sprintf('frame%03d-RAW.jpg', k);
        tmp = [tempname '.jpg']; imwrite(img, tmp, 'jpg', 'Quality', 95);
        fid = fopen(tmp,'rb'); b = fread(fid,Inf,'*uint8'); fclose(fid); delete(tmp);
        blobs{k} = b(:);
    end
    prep = struct();
    prep.format = 'pivprep_single_v1'; prep.created = '2026-01-01 00:00:00';
    prep.source_base = fileparts(matFile); prep.pab_src = ''; prep.nFrames = nF;
    prep.sequencing = struct('mode','consecutive','step',1);
    prep.raw = struct('format','jpeg_dedup_v1','blobs',{blobs},'index',idx,'names',{names},'ext','.jpg');
    prep.gs  = struct('format','jpeg_dedup_v1','blobs',{{}},'index',uint32([]),'names',{{}},'ext','.jpg','quality',92);
    prep.gs_embedded = false; prep.gs_scale = 0.5; prep.gs_quality = 92;
    prep.exif = []; prep.jitter = [];
    save(matFile, 'prep', '-v7');
end

function e = i_entry(matFile, name)
    e = struct('matfile',matFile, 'name',name, 'seqmode','consecutive', 'seqstep',1);
end

function img = i_readFrame(rawDir, k)
    d = dir(fullfile(rawDir,'*.jpg')); nm = sort({d.name});
    img = imread(fullfile(rawDir, nm{k}));
end

function i_rmdir(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
