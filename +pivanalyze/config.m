function cfg = config(varargin)
%CONFIG  Struct konfigurasi default untuk engine analisis +pivanalyze.
%
%   cfg = pivanalyze.config()                 -> semua default
%   cfg = pivanalyze.config('Name', Value...) -> override sebagian field
%
%   Default DISAMAKAN PERSIS dengan inputParser PIVlab_automasi_batch_V4 agar
%   perilaku engine modular identik dengan V4. GUI dan wrapper batch_V5 cukup
%   memanggil config() lalu menimpa field yang relevan.
%
%   FIELD UTAMA
%     NumWorkers      jumlah worker paralel (default 8)
%     Sequencing      'consecutive' | 'pairs' (default 'consecutive')
%     Suffix          filter ekstensi RAW ('' = auto)
%     Recursive       pindai rekursif (default true)
%     MinImages       minimum gambar per eksperimen (default 2)
%     Confirm         minta konfirmasi Command Window (default true)
%     Folders         daftar eksperimen siap-pakai ([] = pindai)
%     OutputFolder    folder output bersama ('' = di folder eksperimen)
%     PIVlabRoot      root instalasi PIVlab ('' = auto)
%     GSQuality       kualitas JPEG GS (default 92)
%     DropFirstGS     buang GS pertama saat consecutive (default true)
%     GSPattern       pola berkas GS
%     ReencodeJpeg    paksa re-encode JPEG (default false)
%     EmbedExifTime   sematkan waktu EXIF (default true)
%     EmbedExifTable  sematkan tabel EXIF penuh (default true)
%     ExifName        nama subfolder EXIF (default 'EXIF')
%     IntAreas        [1x4] IW pass 1..4 (default [64 32 25 16])
%     NumPasses       jumlah pass 1..4 (default 3)
%     Skip            lewati N frame (default 0)
%     IgnoreMap       containers.Map override frame diabaikan ([] = none)
%     ReadProgress    baca daftar abaikan dari berkas progres (default true)
%     ProgressFcn     callback @(frac,msg) ([] = none)
%     LogFcn          callback @(str) ([] = tulis ke Command Window)
%     CheckAbort      callback @()->logical ([] = tak pernah batal)
%     Provenance      tag 'embedded_by' pada .mat (default 'pivanalyze_core')

    cfg = struct( ...
        'NumWorkers',     8, ...
        'Sequencing',     'consecutive', ...
        'Suffix',         '', ...
        'Recursive',      true, ...
        'MinImages',      2, ...
        'Confirm',        true, ...
        'Folders',        [], ...
        'OutputFolder',   '', ...
        'PIVlabRoot',     '', ...
        'GSQuality',      92, ...
        'DropFirstGS',    true, ...
        'GSPattern',      '*.jpg;*.jpeg;*.tif;*.tiff;*.png;*.bmp', ...
        'ReencodeJpeg',   false, ...
        'EmbedExifTime',  true, ...
        'EmbedExifTable', true, ...
        'ExifName',       'EXIF', ...
        'IntAreas',       [64 32 25 16], ...
        'NumPasses',      3, ...
        'Skip',           0, ...
        'IgnoreMap',      [], ...
        'ReadProgress',   true, ...
        'QpivParamsOverride', true, ...
        'ProgressFcn',    [], ...
        'LogFcn',         [], ...
        'CheckAbort',     [], ...
        'Provenance',     'pivanalyze_core');

    % --- override Name-Value ---
    if isempty(varargin); return; end
    if numel(varargin) == 1 && isstruct(varargin{1})
        in = varargin{1};
        fn = fieldnames(in);
        for i = 1:numel(fn)
            cfg.(fn{i}) = in.(fn{i});
        end
        return;
    end
    if mod(numel(varargin), 2) ~= 0
        error('pivanalyze:config:badArgs', 'Argumen harus pasangan Name,Value.');
    end
    for i = 1:2:numel(varargin)
        name = varargin{i};
        if ~ischar(name) && ~isstring(name)
            error('pivanalyze:config:badName', 'Nama field harus string.');
        end
        name = char(name);
        if ~isfield(cfg, name)
            error('pivanalyze:config:unknown', 'Field tak dikenal: %s', name);
        end
        cfg.(name) = varargin{i+1};
    end
end
