function run_rename_verify(names)
%RUN_RENAME_VERIFY  Gerbang verifikasi untuk fase RENAME (non-destruktif).
%   run_rename_verify()        -> hanya cek PARSE CLEAN semua .m root + paket.
%   run_rename_verify(names)   -> + cek tiap nama di cellstr `names` resolve
%                                 sebagai file fungsi (exist==2).
%   Dipakai sebelum & sesudah tiap fase. Tidak meluncurkan GUI apa pun.
if nargin < 1, names = {}; end
here = fileparts(mfilename('fullpath')); addpath(here); addpath(fileparts(here));  % +root (grain_setup, GRAIN*) sejak tests/ dipisah
proj = fileparts(here);   % .../GRAIN (root) -- tests/ kini subfolder; scan tetap di root

rootM = dir(fullfile(proj,'*.m'));
files = {};
for k = 1:numel(rootM)
    files{end+1} = fullfile(rootM(k).folder, rootM(k).name); %#ok<AGROW>
end
add = [ dir(fullfile(proj,'pivcore_lib','+pivcore','+util','*.m')); ...
        dir(fullfile(proj,'pivcore_lib','+pivcore','+data','*.m')); ...
        dir(fullfile(proj,'pivcore_lib','+pivui','*.m')) ];
for k = 1:numel(add), files{end+1} = fullfile(add(k).folder, add(k).name); end %#ok<AGROW>

bad = 0;
for i = 1:numel(files)
    c = checkcode(files{i}, '-string');
    if contains(lower(c), 'error')
        fprintf('ERR %s:\n%s\n', files{i}, c); bad = bad + 1;
    end
end
if bad == 0
    fprintf('PARSE: ALL %d FILES CLEAN\n', numel(files));
else
    error('PARSE: %d file dengan ERROR', bad);
end

missing = 0;
for i = 1:numel(names)
    if exist(names{i}, 'file') ~= 2
        fprintf('MISSING FUNC: %s\n', names{i}); missing = missing + 1;
    end
end
if ~isempty(names)
    if missing == 0
        fprintf('NAMES: ALL %d RESOLVE\n', numel(names));
    else
        error('NAMES: %d nama tak resolve', missing);
    end
end
end
