function embedGS(matFile, pack, gsdir, provenance)
%EMBEDGS  Sematkan blob latar GS (format vector_gs_v1) ke .mat hasil PIV.
%
%   pivanalyze.io.embedGS(matFile, pack, gsdir)
%   pivanalyze.io.embedGS(matFile, pack, gsdir, provenance)
%
%   pack : keluaran PIVlab_automasi_packgs (field format/blobs/index/quality).
%   Menambahkan variabel ke matFile dengan save '-append'.
%
%   Salinan subfungsi embed_gs_into_mat dari PIVlab_automasi_batch_V4 (tag
%   provenance dapat diubah; default 'pivanalyze_core').

    if nargin < 4 || isempty(provenance); provenance = 'pivanalyze_core'; end
    bg_images_format  = pack.format;       %#ok<NASGU>
    bg_images_blobs   = pack.blobs;        %#ok<NASGU>
    bg_images_index   = pack.index;        %#ok<NASGU>
    bg_images_quality = pack.quality;      %#ok<NASGU>
    pivterry_pack     = 'vector_gs_v1';    %#ok<NASGU>
    gs_source_dir     = gsdir;             %#ok<NASGU>
    gs_embedded_by    = provenance;        %#ok<NASGU>
    save(matFile, 'bg_images_format', 'bg_images_blobs', 'bg_images_index', ...
        'bg_images_quality', 'pivterry_pack', 'gs_source_dir', 'gs_embedded_by', '-append');
end
