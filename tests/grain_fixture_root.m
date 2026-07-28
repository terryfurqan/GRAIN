function r = grain_fixture_root()
%GRAIN_FIXTURE_ROOT  Root folder of the LOCAL test fixtures.
%
%   Several smoke tests need real experiment data (packed .mat files, PIV
%   output, `_faults.json` sidecars). That data is large and is NOT part of
%   this repository, so its location is configurable:
%
%       setenv('GRAIN_FIXTURES', '/path/to/your/data')
%
%   Expected layout underneath that root (only what a given test needs):
%       EXP_coll/...            packed experiments
%       RAW/PIV_<date>/...      PIV output folders
%
%   When the variable is unset the function points at <repo>/fixtures, which
%   normally does not exist — the tests then SKIP instead of failing, so a
%   fresh clone still runs green.
r = getenv('GRAIN_FIXTURES');
if isempty(r)
    r = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'fixtures');
end
end
