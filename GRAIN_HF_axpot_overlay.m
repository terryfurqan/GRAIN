function outPdf = GRAIN_HF_axpot_overlay(varargin)
%GRAIN_HF_AXPOT_OVERLAY  Satu PDF berisi 4 axPOT overlay data-MENTAH (P-HF F-1..4).
%
%   Membuat SATU gambar berisi EMPAT axPOT (spaghetti kurva mentah + garis
%   hitam max-indenter) dari keempat eksperimen P-HF-4cm-F, DISUSUN dari atas
%   ke bawah: F-1, F-2, F-3, F-4. TANPA POI / garis vertikal (murni overlay).
%   X-limit maksimum DISAMAKAN untuk keempat panel (rentang frame terpanjang).
%
%   Tampilan meniru axPOT GRAIN4 (pivui.grain4Shell.renderPOT): latar putih, grid
%   abu tipis, kurva warna per-record, envelope indenter hitam tebal.
%   Logika sampling IDENTIK GRAIN4: garis PSG dari <base>_autopot.mat bila ada
%   (pivcore.io.step1Session.loadLine), else garis horizontal 75% dari ATAS;
%   sampling pivcore.pot.step1Collect.collectAlongLine; kurva via
%   pivcore.pot.records.curveXY; indenter = max envelope per-frame.
%
%   Output: GRAIN/CLCC/HF_axpot_overlay.pdf  (folder dibuat bila belum ada).
%
%   Contoh:
%       GRAIN_HF_axpot_overlay
%       GRAIN_HF_axpot_overlay('expDir', '/path/ke/P-HF-4cm-F')
%
%   Jalankan `grain_setup` lebih dulu agar paket pivcore/pivui di path.

    p = inputParser;
    p.addParameter('expDir', '', @(s) ischar(s) || isstring(s));
    p.addParameter('psgFrac', 0.75, @(x) isscalar(x) && x>=0 && x<=1);
    p.parse(varargin{:});
    opt = p.Results;

    % --- Lokasi keempat eksperimen HF (F-1..4), urut menaik ---------------
    expDir = char(opt.expDir);
    if isempty(expDir)
        % Default: sibling repo EXP_coll (path stabil di mesin lab).
        cand = fullfile(fileparts(fileparts(mfilename('fullpath'))), '..', ...
            'EXP_coll', 'EXP Q1', 'P-HF-4cm-F');
        if ~isfolder(cand)
            cand = fullfile(getenv('HOME'), 'MACTERR_shared', 'EXP_coll', ...
                'EXP Q1', 'P-HF-4cm-F');
        end
        expDir = cand;
    end
    assert(isfolder(expDir), 'Folder eksperimen tak ditemukan: %s', expDir);

    files = i_findHFFiles(expDir);   % 1x4 cellstr, indeks = nomor F (1..4)

    % --- Kumpulkan data tiap eksperimen (headless, reuse engine GRAIN4) ------
    n = numel(files);
    panels = cell(1, n);
    xMax = 1;
    for i = 1:n
        fprintf('[%d/%d] %s\n', i, n, files{i});
        panels{i} = i_collectPanel(files{i}, opt.psgFrac);
        xMax = max(xMax, panels{i}.nF);
    end

    % --- Susun figur: n panel dari atas ke bawah, X-limit sama ------------
    fig = figure('Color','w', 'Units','pixels', ...
        'Position',[100 100 1000 220*n + 60], 'Visible','off');
    try, pivui.forceLightTheme(fig); catch, end

    for i = 1:n
        ax = subplot(n, 1, i, 'Parent', fig);
        i_renderPanel(ax, panels{i}, xMax);
        if i < n, xlabel(ax, ''); end   % label X hanya di panel paling bawah
    end

    % --- Ekspor PDF ke GRAIN/CLCC -------------------------------------------
    outDir = fullfile(fileparts(mfilename('fullpath')), 'CLCC');
    if ~isfolder(outDir), mkdir(outDir); end
    outPdf = fullfile(outDir, 'HF_axpot_overlay.pdf');

    set(fig, 'PaperPositionMode','auto');
    try
        exportgraphics(fig, outPdf, 'ContentType','vector', 'BackgroundColor','white');
    catch
        % Fallback R-lama: print vektor.
        print(fig, outPdf, '-dpdf', '-bestfit');
    end
    if isvalid(fig), close(fig); end
    fprintf('PDF tersimpan: %s\n', outPdf);
end

% =====================================================================
function files = i_findHFFiles(expDir)
%I_FINDHFFILES  Kembalikan 1xN cellstr .mat P-HF-4cm-F-<n> (abaikan _axpot/BAK),
%   diurut MENAIK menurut nomor F (1,2,3,4).
    d = dir(fullfile(expDir, 'P-HF-4cm-F-*-*.mat'));
    d = d(~[d.isdir]);
    keep = {}; nums = [];
    for k = 1:numel(d)
        nm = d(k).name;
        if ~isempty(regexpi(nm, '_axpot\.mat$', 'once')), continue; end
        tok = regexpi(nm, 'P-HF-4cm-F-(\d+)-', 'tokens', 'once');
        if isempty(tok), continue; end
        keep{end+1} = fullfile(d(k).folder, nm); %#ok<AGROW>
        nums(end+1) = str2double(tok{1});        %#ok<AGROW>
    end
    assert(~isempty(keep), 'Tak ada .mat P-HF-4cm-F ditemukan di %s', expDir);
    [~, ord] = sort(nums);
    files = keep(ord);
end

% =====================================================================
function P = i_collectPanel(matFile, psgFrac)
%I_COLLECTPANEL  Muat semua frame, sampel POT sepanjang garis PSG, siapkan
%   struct panel: recs, nF, indenter envelope, judul. Reuse engine GRAIN4.
    data = pivcore.io.step1Session.loadAllFrames(matFile);

    % Garis PSG: pakai yang tersimpan (paling setia dgn GRAIN4) bila ada; else
    % horizontal 75% dari ATAS (identik pivui.grain4Shell.autoPSG).
    L = [];
    try, L = pivcore.io.step1Session.loadLine(matFile); catch, L = []; end
    x = pivcore.data.safeFrame(data.x, 1);
    y = pivcore.data.safeFrame(data.y, 1);
    xE = [min(x(:)) max(x(:))]; yE = [min(y(:)) max(y(:))];
    if isempty(L) || ~isstruct(L) || ~isfield(L,'p1')
        yL = yE(2) - psgFrac*(yE(2)-yE(1));   % frac diukur dari ATAS (YDir normal)
        p1 = [xE(1) yL]; p2 = [xE(2) yL];
    else
        p1 = L.p1(:).'; p2 = L.p2(:).';
    end

    % Spacing node (identik jalur GRAIN4 tanpa buffer band).
    dd = pivcore.data.nodeSpacing(data);
    if isfinite(dd) && dd > 0, sp = round(dd); else, sp = 10; end

    recs = pivcore.pot.step1Collect.collectAlongLine(data, p1, p2, sp, 'velocity_magnitude');
    recs = pivcore.pot.records.normalize(recs);
    recs = pivcore.pot.records.applyColors(recs);

    nF = 0;
    for r = 1:numel(recs), nF = max(nF, numel(recs(r).data)); end
    nF = max(1, nF);

    P.recs = recs;
    P.nF   = nF;
    P.env  = i_indenterEnv(recs, nF);
    [~, base] = fileparts(matFile);
    P.title = base;
end

% =====================================================================
function env = i_indenterEnv(recs, nF)
%I_INDENTERENV  Max envelope per-frame (identik pivui.grain4Shell.indenterEnvelope,
%   tanpa flag excluded krn overlay mentah).
    M = -inf(1, nF); any_ = false;
    for r = 1:numel(recs)
        [~, yv] = pivcore.pot.records.curveXY(recs(r), nF);
        if isempty(yv), continue; end
        m = numel(yv); seg = M(1:m); g = isfinite(yv);
        seg(g) = max(seg(g), yv(g)); M(1:m) = seg; any_ = true;
    end
    if ~any_, env = []; return; end
    M(~isfinite(M)) = NaN; env = M;
end

% =====================================================================
function i_renderPanel(ax, P, xMax)
%I_RENDERPANEL  Gambar satu axPOT overlay mentah (tanpa POI/garis vertikal),
%   meniru pivui.grain4Shell.renderPOT.
    cla(ax);
    set(ax, 'Color','w', 'XColor',[0.15 0.15 0.15], 'YColor',[0.15 0.15 0.15], ...
        'GridColor',[0.85 0.85 0.85], 'GridAlpha',1, 'Box','on', 'Layer','top');
    hold(ax, 'on');

    nShown = 0; ymax = -inf;
    for r = 1:numel(P.recs)
        [xv, yv] = pivcore.pot.records.curveXY(P.recs(r), P.nF);
        g = isfinite(xv) & isfinite(yv); if ~any(g), continue; end
        nShown = nShown + 1;
        col = P.recs(r).color; if numel(col) ~= 3, col = [0.4 0.4 0.4]; end
        plot(ax, xv(g), yv(g), '-', 'Color',col, 'LineWidth',0.6);
        ymax = max(ymax, max(yv(g)));
    end
    if ~isempty(P.env)
        xe = 1:numel(P.env); ge = isfinite(P.env);
        if any(ge)
            plot(ax, xe(ge), P.env(ge), '-', 'Color',[0 0 0], 'LineWidth',3);
            ymax = max(ymax, max(P.env(ge)));
        end
    end
    hold(ax, 'off');
    grid(ax, 'on');
    xlabel(ax, 'Frame'); ylabel(ax, '|V| (px/frame)');
    title(ax, sprintf('%s  —  %d kurva (garis hitam = max indenter)', ...
        P.title, nShown), 'Color',[0 0 0], 'Interpreter','none');

    xlim(ax, [1 xMax]);                        % X-limit SAMA semua panel
    if isfinite(ymax) && ymax > 0, ylim(ax, [0 ymax*1.05]); end
end
