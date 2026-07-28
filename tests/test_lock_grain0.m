function test_lock_grain0()
% Verifikasi fungsional KUNCI config GRAIN0: saat ceklis kunci aktif, mengubah
% UI lalu memicu i_restoreCfg (via pindah exp) TIDAK mengembalikan nilai.
% Karena i_restoreCfg nested, kita uji via skenario GUI: aktifkan kunci IW,
% set IW pass-1 ke 128, lalu pilih exp lain -> IW harus TETAP 128.
grain_setup;
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>  % pulihkan sesi

% Buat 2 exp sintetis (folder berisi >=2 JPG) di tempdir.
root = fullfile(tempdir, sprintf('grain0_lock_root'));
if isfolder(root); rmdir(root,'s'); end
for e = 1:2
    d = fullfile(root, sprintf('exp%d', e)); mkdir(d);
    for k = 1:3
        img = uint8(50*e + 10*k + zeros(40,60,3));
        imwrite(img, fullfile(d, sprintf('img_%03d.jpg', k)));
    end
end

GRAIN0(root); drawnow;
fig = findall(0,'Type','figure','-regexp','Name','^GRAIN0'); fig=fig(end);
clo = onCleanup(@() close(fig));

% Cari widget: tabel exp, field IW pertama, ceklis "🔒 IW".
tbls = findall(fig,'Type','uitable'); expTbl=[];
for k=1:numel(tbls); cn=tbls(k).ColumnName; if iscell(cn)&&any(strcmp(cn,'Experiment')); expTbl=tbls(k); break; end; end
assert(~isempty(expTbl) && size(expTbl.Data,1)>=2, 'butuh >=2 exp');

cbs = findall(fig,'Type','uicheckbox'); lockIWcb=[];
for k=1:numel(cbs); if contains(string(cbs(k).Text),'IW'); lockIWcb=cbs(k); break; end; end
assert(~isempty(lockIWcb),'ceklis kunci IW tak ketemu');

% Field IW = NumericEditField dgn nilai 64/32/25/16 di panel cfg.
nfs = findall(fig,'Type','uinumericeditfield'); iw1=[];
for k=1:numel(nfs); if nfs(k).Value==64; iw1=nfs(k); break; end; end
assert(~isempty(iw1),'field IW pass-1 (=64) tak ketemu');

% Pilih exp 1.
cb=expTbl.CellSelectionCallback; cb(expTbl,struct('Indices',[1 1])); drawnow;

% AKTIFKAN kunci IW + ubah IW pass-1 -> 128.
lockIWcb.Value=true; lockIWcb.ValueChangedFcn(lockIWcb,struct()); drawnow;
iw1.Value=128; iw1.ValueChangedFcn(iw1,struct()); drawnow;
assert(iw1.Value==128,'IW gagal di-set 128');

% Pindah ke exp 2 -> i_restoreCfg dipanggil; karena terkunci, harus TETAP 128.
cb(expTbl,struct('Indices',[2 1])); drawnow;
fprintf('  Setelah pindah exp (kunci IW ON): IW pass-1 = %g\n', iw1.Value);
assert(iw1.Value==128, sprintf('KUNCI GAGAL: IW kembali ke %g (harus 128)', iw1.Value));
fprintf('  PASS: kunci IW mempertahankan 128 lintas-exp\n');

% Matikan kunci -> pindah balik ke exp1: IW boleh berubah (default/tersimpan).
lockIWcb.Value=false; lockIWcb.ValueChangedFcn(lockIWcb,struct()); drawnow;
cb(expTbl,struct('Indices',[1 1])); drawnow;
fprintf('  Kunci OFF, pindah exp1: IW pass-1 = %g (boleh != 128)\n', iw1.Value);

fprintf('=== TEST_LOCK_GRAIN0: LULUS ===\n');
rmdir(root,'s');
end
