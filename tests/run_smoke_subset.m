function run_smoke_subset(which)
%RUN_SMOKE_SUBSET  Driver smoke test subset untuk verifikasi refaktor modularitas.
%   which: 'chrome' = step3,3a ; 'all' = + step2 ; default 'chrome'.
%   (Step 1a/1b DIPENSIUNKAN — modul PAB1a/PAB1b lama, lihat commit fec8593.)
if nargin < 1, which = 'chrome'; end
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));  % +root (pab_setup, PAB*) sejak tests/ dipisah
pab_setup;
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP: subset tak rebut fokus
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>  % pulihkan sesi di akhir
DR  = fileparts(fileparts(here));      % .../Automasi PIV LAB (here=tests/, induk=PAB, induknya=DR)
RAW = fullfile(DR, 'RAW');
PIV = fullfile(RAW, 'PIV_2026-06-24');

fprintf('\n===== step3  =====\n'); test_smoke_pab_step3(PIV);
fprintf('\n===== step3a =====\n'); test_smoke_pab_step3a(PIV);
fprintf('\n========== SMOKE SUBSET (chrome) SEMUA LULUS ==========\n');
end
