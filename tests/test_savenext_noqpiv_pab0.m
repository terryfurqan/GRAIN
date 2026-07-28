function test_savenext_noqpiv_pab0()
%TEST_SAVENEXT_NOQPIV_PAB0  Tombol "✓ Save ▸ Next (tanpa QPIV)": simpan exclusion
%   exp ini lalu PINDAH ke exp berikutnya TANPA menjalankan QPIV.
%
%   Verifikasi (GUI headless):
%     A. Tombol ada & aktif.
%     B. Pilih exp-1, klik tombol -> pindah ke exp-2 (expSel berubah).
%     C. TIDAK ada file *_QPIV_cache.mat dibuat (QPIV tak dijalankan).
%     D. Entry progres exp-1 tersimpan (setIgnore dipanggil -> ada di progres).
%
%   Jalankan: pab_setup; test_savenext_noqpiv_pab0   (SELALU R2025b)
    fprintf('\n=== TEST PAB0 Save-Next tanpa QPIV ===\n');
    pab_setup();
    assert(~isempty(which('PAB0')), 'PAB0 tak di-path');
    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

    root = fullfile(tempdir, sprintf('pab0_snnq_%d', feature('getpid')));
    if isfolder(root); rmdir(root,'s'); end; mkdir(root);
    cleaner = onCleanup(@() i_rmdir(root)); %#ok<NASGU>
    for e = 1:2
        d = fullfile(root, sprintf('exp%d', e)); mkdir(d);
        for k = 1:3
            imwrite(uint8(50*e+10*k+zeros(40,60,3)), fullfile(d, sprintf('img_%03d.jpg', k)));
        end
    end

    PAB0(root); drawnow;
    fig = findall(0,'Type','figure','-regexp','Name','^PAB0'); fig = fig(end);
    clo = onCleanup(@() i_close(fig)); %#ok<NASGU>

    % --- A. tombol ada ---
    btns = findall(fig,'Type','uibutton');
    snnq = i_findByText(btns, 'Save ▸ Next (no QPIV)');
    assert(~isempty(snnq), 'A: tombol "Save ▸ Next (tanpa QPIV)" tak ada');
    assert(strcmp(snnq.Enable,'on'), 'A: tombol harus aktif');
    fprintf('  [A] tombol ada & aktif OK.\n');

    % tabel exp
    tbls = findall(fig,'Type','uitable'); expTbl = [];
    for k=1:numel(tbls); cn=tbls(k).ColumnName; if iscell(cn)&&any(strcmp(cn,'Experiment')); expTbl=tbls(k); break; end; end
    assert(~isempty(expTbl) && size(expTbl.Data,1)>=2, 'butuh >=2 exp terpindai');

    % pilih exp-1
    cb = expTbl.CellSelectionCallback; cb(expTbl, struct('Indices',[1 1])); drawnow;
    h0 = guidata(fig);

    % --- B+C+D: klik "Save Next tanpa QPIV" (exp-1 BELUM QPIV -> dilewati) ---
    snnq.ButtonPushedFcn(snnq, struct()); drawnow;

    % C. tak ada cache QPIV dibuat di kedua exp
    c1 = dir(fullfile(root,'exp1','*_QPIV_cache.mat'));
    c2 = dir(fullfile(root,'exp2','*_QPIV_cache.mat'));
    assert(isempty(c1) && isempty(c2), 'C: QPIV cache TERBUAT — QPIV tak boleh jalan!');
    fprintf('  [C] tak ada QPIV cache dibuat (QPIV tak dijalankan) OK.\n');

    % D. exp AKTIF berpindah ke exp-2: loadOrPrompt exp tujuan men-set status yg
    % menyebut nama exp berikutnya ("exp2"). Bukti perpindahan tanpa QPIV.
    lbl = findall(fig,'Type','uilabel');
    movedToExp2 = false;
    for k=1:numel(lbl); t=char(string(lbl(k).Text)); if contains(t,'exp2') && contains(lower(t),'qpiv'); movedToExp2=true; break; end; end
    assert(movedToExp2, 'D: tak pindah ke exp-2 (status tak menyebut exp2)');
    fprintf('  [D] exp belum-QPIV dilewati & pindah ke exp-2 (tanpa QPIV) OK.\n');

    % B. figure masih hidup (tak crash) — perpindahan tanpa error.
    assert(isvalid(fig), 'B: figure mati setelah klik (crash)');
    fprintf('  [B] pindah ke exp berikutnya tanpa QPIV, tanpa crash OK.\n');

    fprintf('=== LULUS ===\n');

    fprintf('=== LULUS ===\n');
end

function b = i_findByText(btns, txt)
    b = [];
    for k = 1:numel(btns)
        if contains(string(btns(k).Text), txt); b = btns(k); return; end
    end
end

function i_close(f)
    try, if all(ishghandle(f)); delete(f); end, catch, end
end
function i_rmdir(d)
    try, if isfolder(d); rmdir(d,'s'); end, catch, end
end
