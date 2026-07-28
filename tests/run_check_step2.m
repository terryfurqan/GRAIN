function run_check_step2()
%RUN_CHECK_STEP2  Cek ringan refaktor step_2: parse OK + pivui.forceLightTheme &
%   pivanalyze.geom.strainText ter-resolve + strainText hasil benar (incl Unicode badL0).
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here));  % +root (pab_setup, PAB*) sejak tests/ dipisah
pab_setup;

% 1) parse: pastikan PAB2 tak punya error sintaks (tanpa eksekusi GUI)
chk = checkcode('PAB2.m','-string');
isErr = contains(lower(chk),'error');
assert(~isErr, 'PAB2.m checkcode melaporkan ERROR:\n%s', chk);
fprintf('[ok] PAB2.m parse bersih (checkcode tanpa error)\n');

% 2) resolusi paket
assert(~isempty(which('pivui.forceLightTheme')), 'pivui.forceLightTheme tak di path');
assert(~isempty(which('pivanalyze.geom.strainText')), 'pivanalyze.geom.strainText tak di path');
fprintf('[ok] pivui.forceLightTheme + pivanalyze.geom.strainText ter-resolve\n');

% 3) strainText perilaku (termasuk badL0 Unicode ≤)
[t1,c1] = pivanalyze.geom.strainText(10, 8, 100);   % L0=90, dL=2 -> lengthening
assert(strcmp(c1,'lengthening') && t1(1)=='+', 'strain lengthening salah: %s/%s', t1, c1);
[t2,c2] = pivanalyze.geom.strainText(100, 100, 50); % L0=-50 -> badL0
assert(strcmp(c2,'badL0') && strcmp(t2,'L0≤0!'), 'badL0 salah: "%s"/%s', t2, c2);
[t3,c3] = pivanalyze.geom.strainText([], 1, 1);      % tak lengkap -> ''
assert(isempty(t3) && isempty(c3), 'kasus kosong salah');
fprintf('[ok] strainText: lengthening=%s, badL0="%s", kosong OK\n', t1, t2);

% 4) pastikan TIDAK ada subfungsi strainText lokal lagi di step_2
src = fileread('PAB2.m');
assert(isempty(regexp(src,'function\s+\[txt, cat\]\s*=\s*strainText','once')), ...
    'masih ada strainText lokal di PAB2.m');
fprintf('[ok] strainText lokal sudah dihapus dari PAB2.m\n');

fprintf('\n========== CHECK STEP 2 (refaktor) LULUS ==========\n');
end
