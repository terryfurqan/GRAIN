function roots = pab_setup()
%PAB_SETUP  Bootstrap path tunggal untuk single-app PAB_SA.
%
%   roots = pab_setup()
%
%   PAB_SA = PIVlab Automasi Batch - Single App. Folder mandiri & bersih yang
%   menyatukan engine modular (paket +pivprep, +batchpivprep2, +pivanalyze)
%   dengan helper di lib/ dan satu GUI. Jalankan sekali per sesi:
%
%       cd('.../Automasi PIV LAB/PAB_SA'); pab_setup;
%
%   GLOBAL: project ini SELALU memakai MATLAB R2025b (lihat GLOBAL_CONTEXT.md).
%
%   Paket MATLAB (+folder) ada di ROOT PAB_SA -> di-addpath lewat root, dan
%   namespace bare (pivprep.*, batchpivprep2.*, pivanalyze.*) tetap valid.
%   PIVlab inti (eksternal, tak diubah) ikut ditambahkan bila ditemukan.

proj = fileparts(mfilename('fullpath'));     % .../PAB_SA
lib  = fullfile(proj, 'lib');
pivc = fullfile(proj, 'pivcore_lib');         % +pivcore + +pivui (utk QPIV GUI penuh)
cmpt = fullfile(proj, '_compat');             % forwarder nama lama (PAB_step_*, pab_sa_setup)
tst  = fullfile(proj, 'tests');               % test_smoke_* + run_* (lihat FILE_GOVERNANCE.md)

addpath(proj);                                % paket + pab_setup + entry point PAB*
if isfolder(lib);  addpath(lib);  end         % helper PIVlab_automasi*, pivprepSingle
if isfolder(pivc); addpath(pivc); end         % pivcore.*/pivui.* (POT/PSG di QPIV GUI)
if isfolder(cmpt); addpath(cmpt); end         % nama lama tetap jalan sampai Fase 7
if isfolder(tst);  addpath(tst);  end         % smoke test & runner dapat dipanggil by-name

% --- PIVlab inti (eksternal) ---
pivlab = i_findPIVlab();
if ~isempty(pivlab); addpath(pivlab); end

% --- versi MATLAB (peringatan, bukan error) ---
v = version('-release');
if ~strcmp(v, '2025b')
	warning('PAB_SA:matlabVersion', ...
		'Project ini distandarkan ke R2025b; Anda di R%s.', v);
end

% --- Konfirmasi ---
fprintf('[PAB_SA] path siap. (MATLAB R%s)\n', v);
fprintf('  root   : %s\n', proj);
fprintf('  lib    : %s\n', i_ok(lib));
if isempty(pivlab)
	fprintf('  PIVlab : (!) TIDAK ditemukan -- set manual via addpath.\n');
else
	fprintf('  PIVlab : %s\n', pivlab);
end
fprintf('Buka GUI: PAB0 (Step 0 QPIV) -> PAB1 (Step 1 ROI jitter) -> PAB1_old (produksi .mat)\n');
fprintf('  Lain  : PABEXPORT (katalog gambar AX main velmag+shear per-bingkai)\n');
fprintf('        : MATPIVEDIT (QC MAT PIV 3-kolom: Geometri X0/X1/L_pos · Hapus Frame error · Masking kotak)\n');
fprintf('        : PABLINK (ikat strain penampang↔peta via FSR) -> PABSYNC (penampil tersinkron)\n');
fprintf('        : PABEDIT (editor tampilan WYSIWYG -> produksi 1 gambar spesifik AXPOT/Net-slip/AX main + masking)\n');
fprintf('        : PABAXCAL (kalibrasi sumbu cm AX main: X=Cummulative Shortening, Y=Height + segitiga indenter -> _axcal.json; dipakai PAB4 Commit)\n');

roots = struct( ...
	'project',   proj, ...
	'lib',       lib, ...
	'pivlab',    pivlab, ...
	'data_root', fileparts(proj));   % .../Automasi PIV LAB (induk: RAW, dll)
end

%% --------------------------------------------------------------------
function s = i_ok(p)
if isfolder(p); s = p; else; s = sprintf('(!) hilang: %s', p); end
end

function root = i_findPIVlab()
%I_FINDPIVLAB  Cari folder PIVlab inti (penanda PIVlab_GUI.m).
%   Urutan: (1) sudah di path (mis. terpasang sbg MATLAB Add-On),
%           (2) environment variable PIVLAB_ROOT,
%           (3) folder sebelah/di dalam project: ../PIVlab, ./PIVlab.
%   Kosong bila tak ketemu — pemanggil memberi peringatan, bukan error.
root = '';
w = which('PIVlab_GUI.m');
if ~isempty(w); root = fileparts(w); return; end

here = fileparts(mfilename('fullpath'));
cands = {getenv('PIVLAB_ROOT'), ...
	fullfile(fileparts(here), 'PIVlab'), ...
	fullfile(here, 'PIVlab')};
for i = 1:numel(cands)
	c = cands{i};
	if isempty(c); continue; end
	if exist(fullfile(c, 'PIVlab_GUI.m'), 'file'); root = c; return; end
end
end
