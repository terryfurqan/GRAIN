function test_pab4_desc_orphan_guard()
%TEST_PAB4_DESC_ORPHAN_GUARD  Regresi rantai kegagalan P-CON-F1 (2026-07-17):
%   garis PSG bergeser -> id psg berubah -> baris DESC jadi YATIM -> tabel
%   tampil kosong -> Save menimpa `rows: []` -> DATA HILANG.
%
%   Mengunci 3 pertahanan (murni ENGINE, pakai tempdir; TAK menyentuh data user):
%     A  psgId.fromGeom STABIL (parsial): TOLPX=50 = pembulatan ke KELIPATAN 50
%        (grid). Geseran dalam SATU sel grid TAK mengubah id; garis PSG berbeda
%        (ratusan px) tetap dibedakan; flip p1<->p2 -> id sama. CATATAN: karena ini
%        grid (bukan toleransi relatif), geseran yang MELEWATI batas sel TETAP
%        mengubah id — jadi TOLPX cuma MENGURANGI frekuensi yatim, bukan penjamin.
%        Penyelamat DATA sesungguhnya = guard write (B) + adopsi yatim (C).
%     B  pab4Desc.write GUARD anti-PENYUSUTAN: #baris BARU < #baris DISK -> TOLAK
%        tulis + .SAFEBAK + data lama utuh (menutup celah lama: dulu hanya anti-
%        kosong, penyusutan SEBAGIAN mis. 3->1 LOLOS -> data hilang 2026-07-18).
%        allowShrink=TRUE (dari Save berkonfirmasi) boleh menyusut; menambah/sama
%        & file-baru tetap boleh.
%     C  pab4Desc.adoptOrphanRows: 1 garis nyata -> baris yatim di-remap ke garis
%        aktif; >1 garis nyata (ambigu) -> TAK mengadopsi; id yatim yang KEBETULAN
%        sudah cocok garis nyata -> tak disentuh.
%
%   SELALU MATLAB R2025b. SENYAP. Bersih-bersih tempdir saat keluar.

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(fileparts(here)));
    addpath(fullfile(fileparts(here), 'pivcore_lib'));
    try, pab_setup; catch, end
    D  = @pivcore.io.pab4Desc;
    ID = @pivcore.pot.psgId;

    tmp = tempname; mkdir(tmp);
    cln = onCleanup(@() i_rmdir(tmp)); %#ok<NASGU>
    df  = fullfile(tmp, 'EXP_dummy.mat');   % base fiktif (file .mat tak perlu ada)

    % ================= A. psgId.fromGeom STABIL =================
    fprintf('==== A. psgId.fromGeom stabil (TOLPX=%d) ====\n', pivcore.pot.psgId.TOLPX);
    assert(pivcore.pot.psgId.TOLPX >= 25, ...
        'A: TOLPX harus >= 25 px (dapat %d) supaya geseran wajar tak memutus id', ...
        pivcore.pot.psgId.TOLPX);
    tol = pivcore.pot.psgId.TOLPX;

    % Ujung di PUSAT sel grid (kelipatan TOLPX) -> geseran dalam sel tak ubah id.
    p1 = [tol 17*tol]; p2 = [138*tol 17*tol];   % mis. [50 850] & [6900 850]
    baseId = pivcore.pot.psgId.fromGeom(p1, p2);
    % Geseran < TOLPX/2 di kedua ujung, tetap DALAM sel -> id SAMA.
    shift = floor(tol/2) - 1;
    idShift = pivcore.pot.psgId.fromGeom(p1+shift, p2-shift);
    assert(strcmp(baseId, idShift), ...
        'A: geseran %d px dalam sel grid TAK boleh mengubah id (%s vs %s)', shift, baseId, idShift);
    % Garis PSG BERBEDA (ratusan px terpisah) tetap dibedakan.
    idFar = pivcore.pot.psgId.fromGeom([tol 30*tol], [138*tol 30*tol]);
    assert(~strcmp(baseId, idFar), 'A: garis terpisah ratusan px harus id BEDA');
    % Flip p1<->p2 -> id sama (urut kanonik).
    idFlip = pivcore.pot.psgId.fromGeom(p2, p1);
    assert(strcmp(baseId, idFlip), 'A: flip ujung harus id sama (%s vs %s)', baseId, idFlip);
    % JUJUR: geseran yang MELEWATI batas sel TETAP mengubah id (limitasi grid).
    % Ini bukan bug test — memang sifat TOLPX; penyelamat data = guard (B)+adopsi (C).
    idAcross = pivcore.pot.psgId.fromGeom(p1+tol, p2+tol);
    assert(~strcmp(baseId, idAcross), 'A: geser 1 sel penuh -> id beda (sifat grid, terdokumentasi)');
    fprintf('[OK] A: id stabil dalam sel (geser %d px); beda utk garis jauh & lintas-sel; flip invarian\n', shift);

    % ================= B. write GUARD anti-timpa-kosong =================
    fprintf('==== B. pab4Desc.write guard anti-PENYUSUTAN ====\n');
    p = pivcore.io.pab4Desc.dataPath(df);
    bak = [p '.SAFEBAK'];
    if isfile(bak), delete(bak); end

    % Tulis dokumen BERISI 3 baris (psgId = baseId).
    doc = pivcore.io.pab4Desc.emptyDoc(df);
    doc = pivcore.io.pab4Desc.setRowsForPsg(doc, baseId, { ...
        pivcore.io.pab4Desc.rowStruct(baseId,'F1',100,'PRP-FSR',1,'',  'baris satu'), ...
        pivcore.io.pab4Desc.rowStruct(baseId,'F1',110,'ACT-FSR',1,'',  'baris dua'), ...
        pivcore.io.pab4Desc.rowStruct(baseId,'F1',115,'X-FS',1,'',      'baris tiga')});
    pivcore.io.pab4Desc.write(df, doc);
    assert(isfile(p), 'B: file _desc.json harus tertulis');
    assert(pivcore.io.pab4Desc.rowCount(pivcore.io.pab4Desc.read(df))==3, 'B: harus 3 baris tersimpan');
    bytesBefore = i_bytes(p);

    warnState = warning('off','pivcore:pab4Desc:shrinkOverwrite');
    cwarn = onCleanup(@() warning(warnState)); %#ok<NASGU>

    % (B1) MENYUSUT ke 0 (kosong) TANPA izin -> DITOLAK + SAFEBAK; data 3 baris utuh.
    pivcore.io.pab4Desc.write(df, pivcore.io.pab4Desc.emptyDoc(df));
    assert(pivcore.io.pab4Desc.rowCount(pivcore.io.pab4Desc.read(df))==3, ...
        'B1: timpa-kosong HARUS ditolak; 3 baris tetap ada');
    assert(i_bytes(p)==bytesBefore, 'B1: byte file tak berubah saat guard');
    assert(isfile(bak), 'B1: guard membuat .SAFEBAK');

    % (B2) MENYUSUT sebagian 3->1 TANPA izin -> DITOLAK (celah lama: dulu LOLOS!).
    doc1 = pivcore.io.pab4Desc.setRowsForPsg(pivcore.io.pab4Desc.emptyDoc(df), baseId, ...
        { pivcore.io.pab4Desc.rowStruct(baseId,'F1',120,'NUC-FSR',1,'','sisa satu') });
    pivcore.io.pab4Desc.write(df, doc1);   % allowShrink default FALSE
    assert(pivcore.io.pab4Desc.rowCount(pivcore.io.pab4Desc.read(df))==3, ...
        'B2: penyusutan 3->1 TANPA izin HARUS ditolak; 3 baris tetap ada');
    fprintf('[OK] B: penyusutan (->0 dan 3->1) TANPA izin DITOLAK + .SAFEBAK; data utuh\n');

    % (B3) MENYUSUT 3->1 DENGAN izin (allowShrink=TRUE, mis. user konfirmasi) -> BOLEH.
    pivcore.io.pab4Desc.write(df, doc1, true);
    assert(pivcore.io.pab4Desc.rowCount(pivcore.io.pab4Desc.read(df))==1, ...
        'B3: penyusutan DENGAN izin (allowShrink) harus BOLEH');
    % (B4) MENAMBAH/SAMA tetap boleh (tulis 2 baris di atas 1).
    doc2 = pivcore.io.pab4Desc.setRowsForPsg(pivcore.io.pab4Desc.emptyDoc(df), baseId, { ...
        pivcore.io.pab4Desc.rowStruct(baseId,'F1',121,'PRP-FSR',1,'','a'), ...
        pivcore.io.pab4Desc.rowStruct(baseId,'F1',122,'ACT-FSR',1,'','b')});
    pivcore.io.pab4Desc.write(df, doc2);
    assert(pivcore.io.pab4Desc.rowCount(pivcore.io.pab4Desc.read(df))==2, ...
        'B4: menambah baris (1->2) harus BOLEH tanpa izin');
    % (B5) kosong -> file BELUM ada tetap boleh (tak ada yg disusutkan).
    df2 = fullfile(tmp, 'EXP_fresh.mat');
    pivcore.io.pab4Desc.write(df2, pivcore.io.pab4Desc.emptyDoc(df2));
    assert(isfile(pivcore.io.pab4Desc.dataPath(df2)), 'B5: kosong->file baru tetap boleh');
    fprintf('[OK] B: allowShrink=TRUE boleh menyusut; menambah/sama & file-baru tetap boleh\n');

    % ================= C. adoptOrphanRows =================
    fprintf('==== C. adoptOrphanRows (adopsi baris yatim) ====\n');
    orphanId = 'geom_99_11111_88_22222';   % id lama yang TAK ada di garis nyata
    docO = pivcore.io.pab4Desc.setRowsForPsg(pivcore.io.pab4Desc.emptyDoc(df), orphanId, { ...
        pivcore.io.pab4Desc.rowStruct(orphanId,'F1',100,'PRP-FSR',1,'','yatim satu'), ...
        pivcore.io.pab4Desc.rowStruct(orphanId,'F1',110,'ACT-FSR',1,'','yatim dua')});
    % Sebelum adopsi: garis aktif baseId tak punya baris (semua yatim).
    assert(numel(pivcore.io.pab4Desc.rowsForPsg(docO, baseId))==0, 'C: pra-adopsi baseId kosong');

    % (i) 1 garis nyata == garis aktif -> yatim di-remap ke baseId.
    [docA, nA] = pivcore.io.pab4Desc.adoptOrphanRows(docO, {baseId}, baseId);
    assert(nA==2, 'C(i): 2 baris yatim harus diadopsi (dapat %d)', nA);
    assert(numel(pivcore.io.pab4Desc.rowsForPsg(docA, baseId))==2, ...
        'C(i): setelah adopsi, baseId punya 2 baris');
    fprintf('[OK] C(i): 1 garis nyata -> %d baris yatim di-remap ke garis aktif\n', nA);

    % (ii) >1 garis nyata (ambigu) -> TAK mengadopsi.
    [docB, nB] = pivcore.io.pab4Desc.adoptOrphanRows(docO, {baseId, idFar}, baseId);
    assert(nB==0, 'C(ii): >1 garis nyata harus TAK mengadopsi (dapat %d)', nB);
    assert(numel(pivcore.io.pab4Desc.rowsForPsg(docB, baseId))==0, ...
        'C(ii): ambigu -> baseId tetap kosong');
    fprintf('[OK] C(ii): >1 garis nyata (ambigu) -> tak mengadopsi\n');

    % (iii) baris yang SUDAH cocok garis nyata -> tak disentuh (nAdopted=0).
    docOk = pivcore.io.pab4Desc.setRowsForPsg(pivcore.io.pab4Desc.emptyDoc(df), baseId, ...
        { pivcore.io.pab4Desc.rowStruct(baseId,'F1',100,'PRP-FSR',1,'','sudah cocok') });
    [~, nC] = pivcore.io.pab4Desc.adoptOrphanRows(docOk, {baseId}, baseId);
    assert(nC==0, 'C(iii): baris sudah cocok garis nyata -> tak diadopsi (dapat %d)', nC);
    fprintf('[OK] C(iii): baris cocok garis nyata -> tak disentuh\n');

    fprintf('\n==== SEMUA LULUS: test_pab4_desc_orphan_guard ====\n');
end

% ---------------------------------------------------------------------
function b = i_bytes(p)
    di = dir(p); if isempty(di), b = -1; else, b = di(1).bytes; end
end

function i_rmdir(d)
    try, if isfolder(d), rmdir(d,'s'); end, catch, end
end
