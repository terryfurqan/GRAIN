function summary = writeJitter(jitterRows, exifDir, meta, curvePath)
%WRITEJITTER  Tulis CONTAINER jitter untuk satu folder ke dalam EXIF dir.
%
%   summary = batchpivprep2.io.writeJitter(jitterRows, exifDir, meta, curvePath)
%
%   Jitter TIDAK ditampilkan sebagai grafik real-time; ia disimpan agar
%   karakter jitter (besar, arah, drift kumulatif, kestabilan) dapat
%   dipelajari, plus opsional disimpan sebagai kurva (PNG). Identik dengan
%   container jitter BatchPIVPrep versi 1.
%
%   INPUT:
%       jitterRows  struct array, satu elemen per frame, field:
%           .frame    indeks frame (1..N)
%           .file     nama berkas
%           .nMatch   jumlah match fitur (SURF) / 0 (phasecorr)
%           .dx       pergeseran horizontal SIGNED (px)
%           .dy       pergeseran vertikal SIGNED (px)
%           .jitter   magnitude jitter = hypot(dx,dy) (px)
%           .accepted logical, koreksi diterima atau tidak
%           .status   string status
%       exifDir     folder EXIF_<suffix> tujuan penyimpanan.
%       meta        struct opsional: .folder, .method, .jitterTol,
%                   .anchorName, .anchor, .cropName, .cropMode -> ikut disimpan.
%       curvePath   path .png opsional untuk menyimpan KURVA jitter.
%
%   KELUARAN BERKAS (di dalam exifDir):
%       JITTER.mat          struct 'jitter': .perFrame (table),
%                           .summary (struct), .anchor, .meta
%       JITTER.csv          tabel per-frame (mudah dibuka di Excel)
%       JITTER_summary.txt  ringkasan karakter jitter (teks)
%   plus (bila curvePath diberikan):
%       <curvePath>         kurva jitter instan + drift kumulatif (PNG)
%
%   OUTPUT:
%       summary   struct statistik ringkas (lihat local_summarize).

    if nargin < 3 || isempty(meta); meta = struct(); end
    if nargin < 4; curvePath = ''; end
    util = pivprep.util.utilities;
    util.ensureDir(exifDir);

    n = numel(jitterRows);

    % --- Vektorisasi + drift kumulatif (running sum dx, dy) ---
    frame    = zeros(n, 1);
    nMatch   = zeros(n, 1);
    dx       = zeros(n, 1);
    dy       = zeros(n, 1);
    jit      = zeros(n, 1);
    accepted = false(n, 1);
    fileNames = strings(n, 1);
    statusStr = strings(n, 1);

    for i = 1:n
        r = jitterRows(i);
        frame(i)     = r.frame;
        nMatch(i)    = r.nMatch;
        dx(i)        = r.dx;
        dy(i)        = r.dy;
        jit(i)       = r.jitter;
        accepted(i)  = logical(r.accepted);
        fileNames(i) = string(r.file);
        statusStr(i) = string(r.status);
    end

    cumDx = cumsum(dx);
    cumDy = cumsum(dy);
    cumMag = hypot(cumDx, cumDy);

    perFrame = table(frame, fileNames, nMatch, dx, dy, jit, ...
        cumDx, cumDy, cumMag, accepted, statusStr, ...
        'VariableNames', {'Frame', 'File', 'nMatch', 'dx_px', 'dy_px', ...
            'jitter_px', 'cumDx_px', 'cumDy_px', 'cumMag_px', ...
            'Accepted', 'Status'});

    summary = local_summarize(dx, dy, jit, cumDx, cumDy, cumMag, accepted, meta);

    % --- Simpan .mat ---
    jitter = struct();
    jitter.perFrame = perFrame;
    jitter.summary  = summary;
    if isfield(meta, 'anchor'); jitter.anchor = meta.anchor; end
    if isfield(meta, 'crop');   jitter.crop   = meta.crop;   end
    jitter.meta = meta;
    save(fullfile(exifDir, 'JITTER.mat'), 'jitter');

    % --- Simpan .csv ---
    try
        writetable(perFrame, fullfile(exifDir, 'JITTER.csv'));
    catch ME
        warning('batchpivprep2:writeJitter:csv', ...
            'Gagal menulis JITTER.csv: %s', ME.message);
    end

    % --- Simpan ringkasan teks ---
    local_writeSummaryTxt(fullfile(exifDir, 'JITTER_summary.txt'), summary, meta, n);

    % --- Simpan KURVA jitter (PNG) bila diminta ---
    if ~isempty(curvePath)
        try
            local_saveCurve(curvePath, frame, dx, dy, jit, cumDx, cumDy, meta);
        catch ME
            warning('batchpivprep2:writeJitter:curve', ...
                'Gagal menyimpan kurva jitter: %s', ME.message);
        end
    end
end


% =====================================================================
function local_saveCurve(curvePath, frame, dx, dy, jit, cumDx, cumDy, meta)
%LOCAL_SAVECURVE  Render kurva jitter ke berkas PNG (tanpa menampilkan).
%   Dua panel: (1) jitter instan dx/dy/|jitter|, (2) drift kumulatif.
    if isempty(frame)
        return;
    end
    if isfield(meta, 'folder') && ~isempty(meta.folder)
        [~, fn] = fileparts(meta.folder);
    else
        fn = '';
    end

    fig = figure('Visible', 'off', 'Color', 'w', ...
        'Units', 'pixels', 'Position', [100 100 1000 640]);
    try                                  % kurva jitter selalu tema TERANG
        theme(fig, 'light');
    catch
    end
    cleaner = onCleanup(@() local_safeClose(fig)); %#ok<NASGU>

    % Panel 1: instan (signed dx, dy + magnitude)
    ax1 = subplot(2, 1, 1, 'Parent', fig);
    hold(ax1, 'on'); grid(ax1, 'on'); box(ax1, 'on');
    plot(ax1, frame, dx, '-', 'Color', [0.10 0.45 0.80], 'LineWidth', 1.2, ...
        'DisplayName', 'dx (signed, px)');
    plot(ax1, frame, dy, '-', 'Color', [0.85 0.35 0.25], 'LineWidth', 1.2, ...
        'DisplayName', 'dy (signed, px)');
    plot(ax1, frame, jit, ':', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.0, ...
        'DisplayName', '|jitter| (px)');
    yline(ax1, 0, 'k-', 'LineWidth', 0.4, 'HandleVisibility', 'off');
    title(ax1, sprintf('Jitter instan per frame  -  %s', fn), ...
        'Interpreter', 'none', 'FontWeight', 'bold');
    ylabel(ax1, 'pixels');
    legend(ax1, 'Location', 'best', 'FontSize', 8);

    % Panel 2: drift kumulatif (running sum)
    ax2 = subplot(2, 1, 2, 'Parent', fig);
    hold(ax2, 'on'); grid(ax2, 'on'); box(ax2, 'on');
    plot(ax2, frame, cumDx, '-', 'Color', [0.10 0.45 0.80], 'LineWidth', 1.5, ...
        'DisplayName', 'cumulative dx');
    plot(ax2, frame, cumDy, '-', 'Color', [0.85 0.35 0.25], 'LineWidth', 1.5, ...
        'DisplayName', 'cumulative dy');
    yline(ax2, 0, 'k-', 'LineWidth', 0.4, 'HandleVisibility', 'off');
    title(ax2, 'Drift kumulatif (running sum, signed)', 'FontWeight', 'bold');
    xlabel(ax2, 'Frame index'); ylabel(ax2, 'pixels');
    legend(ax2, 'Location', 'best', 'FontSize', 8);

    % Simpan (exportgraphics bila ada, jika tidak gunakan print)
    try
        exportgraphics(fig, curvePath, 'Resolution', 150);
    catch
        print(fig, curvePath, '-dpng', '-r150');
    end
end


function local_safeClose(fig)
    try
        if ~isempty(fig) && ishandle(fig); close(fig); end
    catch
    end
end


% =====================================================================
function s = local_summarize(dx, dy, jit, cumDx, cumDy, cumMag, accepted, meta)
%LOCAL_SUMMARIZE  Statistik karakter jitter.
    s = struct();
    s.nFrames     = numel(jit);
    s.nAccepted   = sum(accepted);
    s.nRejected   = sum(~accepted);

    s.jitterMean  = mean(jit);
    s.jitterStd   = std(jit);
    s.jitterMax   = max([jit; 0]);
    s.jitterRMS   = sqrt(mean(jit.^2));
    s.jitterP95   = local_prctile(jit, 95);

    s.dxMean = mean(dx);   s.dxStd = std(dx);
    s.dyMean = mean(dy);   s.dyStd = std(dy);
    s.dxMaxAbs = max([abs(dx); 0]);
    s.dyMaxAbs = max([abs(dy); 0]);

    % Drift kumulatif (akhir + ekstrem)
    if isempty(cumDx)
        s.driftEndX = 0; s.driftEndY = 0; s.driftMaxMag = 0;
    else
        s.driftEndX   = cumDx(end);
        s.driftEndY   = cumDy(end);
        s.driftMaxMag = max(cumMag);
    end

    if isfield(meta, 'method');    s.method    = meta.method;    else, s.method    = ''; end
    if isfield(meta, 'jitterTol'); s.jitterTol = meta.jitterTol; else, s.jitterTol = NaN; end
end


% =====================================================================
function p = local_prctile(x, pct)
%LOCAL_PRCTILE  Persentil tanpa Statistics Toolbox (interpolasi linear).
    x = sort(x(:));
    n = numel(x);
    if n == 0, p = 0; return; end
    if n == 1, p = x(1); return; end
    rank = (pct/100) * (n - 1) + 1;
    lo = floor(rank); hi = ceil(rank);
    if lo == hi
        p = x(lo);
    else
        p = x(lo) + (rank - lo) * (x(hi) - x(lo));
    end
end


% =====================================================================
function local_writeSummaryTxt(txtPath, s, meta, n)
%LOCAL_WRITESUMMARYTXT  Tulis ringkasan karakter jitter ke .txt.
    fid = fopen(txtPath, 'w');
    if fid < 0
        warning('batchpivprep2:writeJitter:txt', ...
            'Gagal membuka %s untuk ditulis.', txtPath);
        return;
    end
    c = onCleanup(@() fclose(fid)); %#ok<NASGU>

    if isfield(meta, 'folder');     folderStr = meta.folder;     else, folderStr = '(?)'; end
    if isfield(meta, 'anchorName'); anchorStr = meta.anchorName; else, anchorStr = '(?)'; end
    if isfield(meta, 'cropName');   cropStr   = meta.cropName;   else, cropStr   = '(?)'; end
    if isfield(meta, 'cropMode');   cropModeStr = meta.cropMode; else, cropModeStr = '(?)'; end

    fprintf(fid, 'BatchPIVPrep2 - Ringkasan Karakter Jitter\n');
    fprintf(fid, '========================================\n');
    fprintf(fid, 'Folder        : %s\n', folderStr);
    fprintf(fid, 'Anchor stab.  : %s\n', anchorStr);
    fprintf(fid, 'Crop ROI      : %s  [mode: %s]\n', cropStr, cropModeStr);
    fprintf(fid, 'Metode        : %s\n', s.method);
    fprintf(fid, 'Jitter tol    : %.3g px\n', s.jitterTol);
    fprintf(fid, 'Dibuat        : %s\n\n', ...
        char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));

    fprintf(fid, 'Jumlah frame  : %d  (diterima: %d, ditolak: %d)\n\n', ...
        n, s.nAccepted, s.nRejected);

    fprintf(fid, '--- Magnitude jitter per frame (px) ---\n');
    fprintf(fid, '  mean   : %.3f\n', s.jitterMean);
    fprintf(fid, '  std    : %.3f\n', s.jitterStd);
    fprintf(fid, '  RMS    : %.3f\n', s.jitterRMS);
    fprintf(fid, '  p95    : %.3f\n', s.jitterP95);
    fprintf(fid, '  max    : %.3f\n\n', s.jitterMax);

    fprintf(fid, '--- Komponen pergeseran (signed, px) ---\n');
    fprintf(fid, '  dx: mean %+.3f, std %.3f, |max| %.3f\n', ...
        s.dxMean, s.dxStd, s.dxMaxAbs);
    fprintf(fid, '  dy: mean %+.3f, std %.3f, |max| %.3f\n\n', ...
        s.dyMean, s.dyStd, s.dyMaxAbs);

    fprintf(fid, '--- Drift kumulatif (running sum, px) ---\n');
    fprintf(fid, '  akhir  : dx %+.3f, dy %+.3f\n', s.driftEndX, s.driftEndY);
    fprintf(fid, '  |drift| maksimum sepanjang sekuens: %.3f\n', s.driftMaxMag);

    fprintf(fid, '\nDetail per-frame ada di JITTER.csv / JITTER.mat.\n');
end
