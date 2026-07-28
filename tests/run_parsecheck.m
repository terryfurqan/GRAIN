function run_parsecheck()
%RUN_PARSECHECK  checkcode semua file step + paket bersama baru; gagal bila ada ERROR.
here = fileparts(mfilename('fullpath')); addpath(here); addpath(fileparts(here));  % +root (pab_setup, PAB*) sejak tests/ dipisah
files = {'PAB0.m','PAB1.m','PAB2.m','PAB3.m','PAB3a.m'};
proj = fileparts(here);   % .../PAB (root); tests/ kini subfolder
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
    fprintf('ALL %d FILES PARSE CLEAN\n', numel(files));
else
    error('%d file dengan ERROR parse', bad);
end
end
