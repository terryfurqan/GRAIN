function names = rawSortedNames(rawdir, suffix)
%RAWSORTEDNAMES  Daftar nama berkas RAW terurut (untuk pemetaan waktu EXIF).
%
%   names = pivanalyze.io.rawSortedNames(rawdir, suffix)
%
%   suffix : filter ekstensi (mis. '*.jpg'); '' -> '*.*'. Kembalian = cell
%   kolom nama berkas (tanpa path), terurut.
%
%   Salinan subfungsi raw_sorted_names dari PIVlab_automasi_batch_V4.

    names = {};
    if isempty(rawdir) || ~isfolder(rawdir); return; end
    if isempty(suffix); suffix = '*.*'; end
    d = dir(fullfile(rawdir, suffix));
    d = d(~[d.isdir]);
    names = sort({d.name});
    names = names(:);
end
