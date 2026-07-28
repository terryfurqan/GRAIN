function exifdir = resolveExifDir(entry, exifName)
%RESOLVEEXIFDIR  Temukan subfolder EXIF untuk satu eksperimen.
%
%   exifdir = pivanalyze.io.resolveExifDir(entry, exifName)
%
%   entry : struct eksperimen (field .expdir, .path, opsional .exifdir).
%   Urutan coba: entry.exifdir -> <exifName> -> EXIF<suffix RAW> -> EXIF*.
%   '' bila tak ada.
%
%   Salinan subfungsi resolve_exif_dir dari PIVlab_automasi_batch_V4.

    u = pivanalyze.util.utilities;
    exifdir = '';
    if isfield(entry, 'exifdir') && ~isempty(entry.exifdir) && isfolder(entry.exifdir)
        exifdir = entry.exifdir; return;
    end
    expdir = entry.expdir;
    cand = u.subfolderCI(expdir, exifName);
    if ~isempty(cand); exifdir = cand; return; end
    [~, rawLeaf] = fileparts(regexprep(entry.path, '[\\/]+$', ''));
    tok = regexpi(rawLeaf, '^RAW([_\-].*)?$', 'tokens', 'once');
    if ~isempty(tok) && ~isempty(tok{1})
        cand = u.subfolderCI(expdir, ['EXIF' tok{1}]);
        if ~isempty(cand); exifdir = cand; return; end
    end
    items = dir(expdir);
    for k = 1:numel(items)
        if items(k).isdir && ~isempty(regexpi(items(k).name, '^EXIF([_\-].*)?$', 'once'))
            exifdir = fullfile(expdir, items(k).name); return;
        end
    end
end
