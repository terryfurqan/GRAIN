function out = pivprepJitterGrid(files, refImg, rawDir, opts)
%PIVPREPJITTERGRID  Pindai GRID kandidat area -> peta jitter pemilih anchor.
%
%   out = pivprepJitterGrid(files, refImg, rawDir, opts)
%
%   = ENGINE inti PABSA0a (PAB_step_0a). Bila PABSA0 menguji SATU ROI yang
%   ditebak pengguna, fungsi ini MEMINDAI seluruh frame dengan GRID rapat
%   area kecil dan mengukur "seberapa jauh tiap area menyimpang dari posisi
%   frame-1" sepanjang urutan. Area yang paling DIAM (simpangan terendah)
%   yang TERUKUR ANDAL adalah kandidat terbaik untuk lokasi anchor
%   stabilisasi Step 1; area yang terus bergerak adalah jitter eksternal
%   ATAU justru zona observasi (pasir/dinding pendorong) — engine tidak
%   membedakan keduanya, ia hanya MEMERINGKAT kediaman.
%
%   ENGINE = SAMA dengan PABSA0/Step 1 (tanpa duplikasi algoritma): tiap sel
%   memakai pivprep.stab.buildReference + estimateTransform dengan
%       roiPad        = 0      -> pengukuran terkurung di sel itu
%       lastGoodTform = I      -> dx/dy ABSOLUT relatif frame-1
%       jitterTol     = 1e9    -> semua frame terukur (tak ada gating produksi)
%   sehingga dx/dy tiap frame = simpangan absolut area itu dari frame-1.
%
%   Loop FRAME-luar / SEL-dalam: tiap frame dibaca SEKALI dari disk lalu
%   diadu ke referensi semua sel (hemat I/O).
%
%   INPUT:
%       files   cellstr nama file frame (natural-sort), relatif terhadap rawDir
%       refImg  frame-1 (sudah dibaca; RGB/gray)
%       rawDir  folder berisi files
%       opts    struct opsi (semua punya default):
%           .rows, .cols      dimensi grid (default 6, 8)
%           .method           'phasecorr' | 'surf'   (default 'phasecorr')
%           .marginFrac       inset dari tepi, fraksi sisi terpendek (default 0.02)
%           .maxFrames        0 = semua (default 0)
%           .frameStep        ambil tiap-N frame (default 1)
%           .surfMinPts       min fitur SURF utk "terukur" (default 8)
%           .failFracTol      maks fraksi frame gagal utk "terukur" (default 0.25)
%           .flatStdTol       min std patch (phasecorr) utk "terukur" (default 3)
%           .minCellPx        min sisi sel (px) utk "terukur" (default 24)
%           .rankMetric       'rms'|'max'|'mean'|'drift' utk pilih .best (default 'rms')
%           .progressFcn      @(frac,msg)->keepGoing(logical). Kembalikan false
%                             untuk membatalkan. (opsional)
%
%   OUTPUT struct out:
%       .rows,.cols,.nCells,.method,.imgSize
%       .cellBox    nCells x 4  [x y w h] (urut baris-major: c = (r-1)*cols + col)
%       .frames     1 x nUse indeks frame yang dipakai (selalu memuat frame-1)
%       .nUse,.nAll
%       .DX,.DY,.JIT,.OK   nCells x nUse deret per-sel (JIT=hypot(DX,DY))
%       .rmsOffset,.maxOffset,.meanOffset,.driftMag   nCells x 1 ringkasan
%       .failFrac   nCells x 1
%       .texture    nCells x 1 (nPoints SURF, atau std patch phasecorr)
%       .measurable nCells x 1 logical (lolos gerbang keterukuran)
%       .reason     nCells x 1 cellstr alasan bila TAK terukur ('' bila ok)
%       .best       indeks sel rekomendasi (argmin rankMetric di antara
%                   yang measurable), [] bila tak ada
%       .rankMetric metrik yang dipakai memilih .best
%       .cancelled  logical
%
%   Lihat juga PAB_step_0a, pivprep.stab.buildReference, pivprep.stab.estimateTransform.

    if nargin < 4 || isempty(opts); opts = struct(); end
    o = i_defaults(opts);

    util    = pivprep.util.utilities;
    imgSize = size(refImg, [1 2]);          % [H W]
    H = imgSize(1); W = imgSize(2);

    % --- Geometri grid: tile frame dengan inset dari tepi ---------------
    margin = max(0, round(o.marginFrac * min(H, W)));
    gx = round(linspace(1 + margin, W - margin, o.cols + 1));
    gy = round(linspace(1 + margin, H - margin, o.rows + 1));
    nCells  = o.rows * o.cols;
    cellBox = zeros(nCells, 4);
    for r = 1:o.rows
        for c = 1:o.cols
            ci = (r - 1) * o.cols + c;
            x1 = gx(c);   x2 = gx(c + 1);
            y1 = gy(r);   y2 = gy(r + 1);
            cellBox(ci, :) = [x1, y1, max(1, x2 - x1), max(1, y2 - y1)];
        end
    end

    % --- Frame yang dipakai (selalu memuat frame-1 sbg referensi) -------
    nAll = numel(files);
    step = max(1, round(o.frameStep));
    idx  = 1:step:nAll;
    if o.maxFrames > 0; idx = idx(1:min(numel(idx), o.maxFrames)); end
    if isempty(idx) || idx(1) ~= 1; idx = unique([1, idx]); end
    frames = idx;
    nUse   = numel(frames);

    % --- Referensi tiap sel (frame-1). Bungkam warning detektor ---------
    wState = warning('off', 'pivprep:buildReference:noFeatures');
    wState2 = warning('off', 'pivprep:buildReference:smallPatch');
    cleanW = onCleanup(@() i_restoreWarn(wState, wState2));

    refs    = cell(nCells, 1);
    texture = zeros(nCells, 1);     % nPoints (surf) | std patch (phasecorr)
    refOK   = false(nCells, 1);
    for ci = 1:nCells
        try
            ref = pivprep.stab.buildReference(refImg, cellBox(ci, :), o.method);
            refs{ci} = ref;
            if strcmp(o.method, 'surf')
                texture(ci) = i_getf(ref, 'nPoints', 0);
                refOK(ci)   = texture(ci) > 0;
            else
                if isfield(ref, 'patch') && ~isempty(ref.patch)
                    texture(ci) = std(double(ref.patch(:)));
                    refOK(ci)   = true;
                end
            end
        catch
            refs{ci} = [];
        end
    end

    % --- Loop FRAME-luar / SEL-dalam -----------------------------------
    Iform = util.identityTform();
    prm   = struct('roiPad', 0, 'jitterTol', 1e9, 'lastGoodTform', Iform);

    DX = nan(nCells, nUse); DY = nan(nCells, nUse);
    OK = false(nCells, nUse);
    cancelled = false;

    for ki = 1:nUse
        k = frames(ki);
        if k == 1
            DX(:, ki) = 0; DY(:, ki) = 0; OK(:, ki) = true;   % frame-1 = referensi
        else
            try
                img = imread(fullfile(rawDir, files{k}));
            catch
                DX(:, ki) = NaN; DY(:, ki) = NaN; OK(:, ki) = false;
                img = [];
            end
            if ~isempty(img)
                for ci = 1:nCells
                    if isempty(refs{ci}); continue; end     % tetap NaN/false
                    try
                        t = pivprep.stab.estimateTransform(img, refs{ci}, prm);
                        DX(ci, ki) = t.dx;
                        DY(ci, ki) = t.dy;
                        OK(ci, ki) = ~startsWith(t.status, 'REJECT');
                    catch
                        DX(ci, ki) = NaN; DY(ci, ki) = NaN; OK(ci, ki) = false;
                    end
                end
            end
        end

        if ~isempty(o.progressFcn)
            keep = o.progressFcn(ki / nUse, ...
                sprintf('Memindai frame %d/%d (%d sel)…', ki, nUse, nCells));
            if islogical(keep) && ~keep
                cancelled = true;
                % Potong kolom yang belum terisi agar ringkasan jujur.
                frames = frames(1:ki); nUse = ki;
                DX = DX(:, 1:ki); DY = DY(:, 1:ki); OK = OK(:, 1:ki);
                break;
            end
        end
    end

    JIT = hypot(DX, DY);            % simpangan absolut tiap frame vs frame-1

    % --- Ringkasan per-sel (kecualikan frame-1 referensi) --------------
    isRef = (frames == 1);
    rmsOffset  = nan(nCells, 1); maxOffset = nan(nCells, 1);
    meanOffset = nan(nCells, 1); driftMag  = nan(nCells, 1);
    failFrac   = nan(nCells, 1);
    minSide    = min(cellBox(:, 3), cellBox(:, 4));

    for ci = 1:nCells
        jit = JIT(ci, ~isRef);
        ok  = OK(ci, ~isRef);
        valid = isfinite(jit);
        nMeas = sum(~isRef);
        if any(valid)
            jv = jit(valid);
            rmsOffset(ci)  = sqrt(mean(jv .^ 2));
            maxOffset(ci)  = max(jv);
            meanOffset(ci) = mean(jv);
        end
        failFrac(ci) = sum(~ok) / max(1, nMeas);
        dxc = DX(ci, :); dyc = DY(ci, :);
        dxc(~isfinite(dxc)) = 0; dyc(~isfinite(dyc)) = 0;
        cdx = cumsum(dxc); cdy = cumsum(dyc);
        driftMag(ci) = hypot(cdx(end), cdy(end));
    end

    % --- Gerbang keterukuran (per-sel) ---------------------------------
    measurable = false(nCells, 1);
    reason     = repmat({''}, nCells, 1);
    for ci = 1:nCells
        why = '';
        if isempty(refs{ci}) || ~refOK(ci)
            why = 'ref gagal';
        elseif minSide(ci) < o.minCellPx
            why = sprintf('sel kecil (%.0fpx)', minSide(ci));
        elseif strcmp(o.method, 'surf') && texture(ci) < o.surfMinPts
            why = sprintf('fitur tipis (%d<%d)', round(texture(ci)), o.surfMinPts);
        elseif strcmp(o.method, 'phasecorr') && texture(ci) < o.flatStdTol
            why = sprintf('terlalu polos (std %.1f)', texture(ci));
        elseif ~isfinite(rmsOffset(ci))
            why = 'tak terukur';
        elseif failFrac(ci) > o.failFracTol
            why = sprintf('gagal %.0f%%', 100 * failFrac(ci));
        end
        measurable(ci) = isempty(why);
        reason{ci}     = why;
    end

    % --- Rekomendasi: argmin metrik peringkat di antara yang measurable --
    metric = i_metricVec(o.rankMetric, rmsOffset, maxOffset, meanOffset, driftMag);
    best = [];
    cand = find(measurable & isfinite(metric));
    if ~isempty(cand)
        [~, mi] = min(metric(cand));
        best = cand(mi);
    end

    out = struct();
    out.rows = o.rows; out.cols = o.cols; out.nCells = nCells;
    out.method = o.method; out.imgSize = imgSize;
    out.cellBox = cellBox;
    out.frames = frames; out.nUse = nUse; out.nAll = nAll;
    out.DX = DX; out.DY = DY; out.JIT = JIT; out.OK = OK;
    out.rmsOffset = rmsOffset; out.maxOffset = maxOffset;
    out.meanOffset = meanOffset; out.driftMag = driftMag;
    out.failFrac = failFrac; out.texture = texture;
    out.measurable = measurable; out.reason = reason(:);
    out.best = best; out.rankMetric = o.rankMetric;
    out.cancelled = cancelled;
end


% =====================================================================
% Helper
% =====================================================================
function o = i_defaults(opts)
    d = struct( ...
        'rows', 6, 'cols', 8, 'method', 'phasecorr', ...
        'marginFrac', 0.02, 'maxFrames', 0, 'frameStep', 1, ...
        'surfMinPts', 8, 'failFracTol', 0.25, 'flatStdTol', 3, ...
        'minCellPx', 24, 'rankMetric', 'rms', 'progressFcn', []);
    fn = fieldnames(d);
    o = d;
    for k = 1:numel(fn)
        if isfield(opts, fn{k}) && ~isempty(opts.(fn{k}))
            o.(fn{k}) = opts.(fn{k});
        end
    end
    o.method = lower(char(o.method));
    if ~ismember(o.method, {'phasecorr', 'surf'}); o.method = 'phasecorr'; end
    o.rows = max(1, round(o.rows));
    o.cols = max(1, round(o.cols));
end

function v = i_metricVec(name, rms, mx, mean_, drift)
    switch lower(char(name))
        case 'max',   v = mx;
        case 'mean',  v = mean_;
        case 'drift', v = drift;
        otherwise,    v = rms;
    end
end

function v = i_getf(s, f, def)
    if isfield(s, f) && ~isempty(s.(f)); v = s.(f); else; v = def; end
end

function i_restoreWarn(w1, w2)
    try, warning(w1); catch, end
    try, warning(w2); catch, end
end
