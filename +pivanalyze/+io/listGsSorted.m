function files = listGsSorted(gsdir, patternStr)
%LISTGSSORTED  Daftar berkas GS terurut (multi-pola, dedup) di satu folder.
%
%   files = pivanalyze.io.listGsSorted(gsdir, patternStr)
%
%   patternStr : pola dipisah ';' atau ',' (mis. '*.jpg;*.png'). Default
%   '*.jpg;*.jpeg;*.tif;*.tiff;*.png;*.bmp'. Kembalian = cell kolom path
%   penuh, terurut menurut nama.
%
%   Salinan persis subfungsi list_gs_sorted dari PIVlab_automasi_batch_V4.

    files = {};
    if isempty(gsdir) || ~isfolder(gsdir); return; end
    if nargin < 2 || isempty(patternStr)
        patternStr = '*.jpg;*.jpeg;*.tif;*.tiff;*.png;*.bmp';
    end
    patternStr = strrep(patternStr, ',', ';');
    parts = strsplit(patternStr, ';');
    seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    names = {};
    for i = 1:numel(parts)
        pp = strtrim(parts{i});
        if isempty(pp); continue; end
        d = dir(fullfile(gsdir, pp));
        for j = 1:numel(d)
            if ~d(j).isdir && ~isKey(seen, d(j).name)
                seen(d(j).name) = true;
                names{end+1} = d(j).name; %#ok<AGROW>
            end
        end
    end
    names = sort(names);
    files = cellfun(@(nm) fullfile(gsdir, nm), names, 'UniformOutput', false);
    files = files(:);
end
