function u = utilities()
%UTILITIES  Kumpulan helper kecil untuk +pivanalyze (struct of function handles).
%
%   u = pivanalyze.util.utilities;
%   u.scalar(x)             -> double skalar (NaN bila kosong/non-numerik)
%   u.subfolderCI(p, name)  -> path subfolder (case-insensitive), '' bila tak ada
%   u.dirof(p)              -> fileparts(p) aman ('' bila kosong)
%   u.ensureField(s, n, d)  -> pastikan field n ada (isi default d bila kosong)
%   u.getIgnore(key, map, readStore) -> vektor indeks frame yang diabaikan
%
%   Semua fungsi ini SALINAN PERSIS subfungsi PIVlab_automasi_batch_V4 agar
%   perilaku numerik identik (lihat uji regresi test_regresi_v5.m).

    u = struct( ...
        'scalar',      @i_scalar, ...
        'subfolderCI', @i_subfolder_ci, ...
        'dirof',       @i_dirof, ...
        'ensureField', @ensure_field, ...
        'getIgnore',   @i_get_ignore);
end

function v = i_scalar(x)
    if isempty(x) || ~isnumeric(x); v = NaN; else; v = double(x(1)); end
end

function p = i_subfolder_ci(parent, name)
    p = '';
    if isempty(parent) || ~isfolder(parent); return; end
    exact = fullfile(parent, name);
    if isfolder(exact); p = exact; return; end
    items = dir(parent);
    for k = 1:numel(items)
        if items(k).isdir && strcmpi(items(k).name, name) ...
                && ~strcmp(items(k).name, '.') && ~strcmp(items(k).name, '..')
            p = fullfile(parent, items(k).name); return;
        end
    end
end

function d = i_dirof(p)
    if isempty(p); d = ''; else; d = fileparts(p); end
end

function folders = ensure_field(folders, name, defaultVal)
    if ~isfield(folders, name)
        [folders.(name)] = deal(defaultVal);
    else
        for i = 1:numel(folders)
            if isempty(folders(i).(name)); folders(i).(name) = defaultVal; end
        end
    end
end

function vec = i_get_ignore(key, map, readStore, fallbackKey)
%I_GET_IGNORE  Ambil vektor frame yang diabaikan: IgnoreMap dulu, lalu store.
%   fallbackKey (opsional): key folder RAW asli (pab_src) untuk jembatan QPIV
%   Step 0 -> Step 2. IgnoreMap (sesi GUI Step 2) TETAP dikunci 'key' (.mat);
%   hanya store progres yang mencoba fallback bila key .mat tak ketemu.
    if nargin < 4; fallbackKey = ''; end
    vec = [];
    if ~isempty(map) && isa(map, 'containers.Map') && isKey(map, key)
        vec = map(key);
    elseif readStore
        e = PIVlab_automasi_progress('get', key, fallbackKey);
        if ~isempty(e) && isfield(e, 'ignore_frames'); vec = e.ignore_frames; end
    end
    vec = double(vec(:))';
end
