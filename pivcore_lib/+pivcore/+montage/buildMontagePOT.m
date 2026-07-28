function outFile = buildMontagePOT(data, cfg)
%BUILDMONTAGEPOT  Montase panel-panel skalar PIV + plot POT di bawahnya, dengan
%   GARIS VERTIKAL MERAH (satu per panel foto) + label angka di atas tiap garis.
%
%   outFile = pivcore.montage.buildMontagePOT(data, cfg)
%
%   READ-ONLY. Sama dengan pivcore.montage.buildMontage (grid skalar+GS+glyph,
%   CLim global, off-screen -> PNG) TAPI menambah satu axes POT lebar di bawah
%   grid. Plot POT = spaghetti kurva |V| + envelope MAX (garis hitam), persis
%   tampilan axPOT GRAINSA3. Untuk SETIAP bingkai yang ditampilkan di grid, sebuah
%   garis vertikal merah ditarik di axPOT dengan label angka di atasnya. Label
%   bisa: nomor frame, strain hasil interpolasi posisi (X0/X1/L_pos), atau
%   strain override manual.
%
%   cfg (struct) — superset cfg buildMontage grid, plus:
%     .frames    vektor indeks bingkai yang ditampilkan (urut baca)
%     .rows,.cols  dimensi grid panel foto
%     .scalar    'velocity_magnitude' | 'shear' (panel foto)
%     .climVel / .shearAbs / .gsOn / .gsAlpha / .claheOn / .adjOn / .glyphOn /
%       .glyphLW / .glyphSp  — sama seperti buildMontage
%     .label     'letter' | 'frame' | 'none'  (label SUDUT panel foto)
%     .dpi / .title / .outFile
%     --- khusus POT ---
%     .potRecs   array record POT (pivcore.pot.records, punya .data/.color/.mode)
%     .potNF     panjang deret POT (jumlah frame kurva)
%     .potIndenter  envelope MAX (1 x potNF) atau [] (dihitung ulang bila kosong)
%     .markMode  'frame' | 'strain' | 'override'  -> isi label garis vertikal
%     .geom      struct experiment_geometry (untuk markMode 'strain')
%     .overrides vektor nilai override (sejajar cfg.frames) untuk markMode 'override'
%
%   Mengembalikan path PNG yang ditulis (= cfg.outFile). Error bila gagal.

    if nargin < 2 || ~isstruct(cfg), error('buildMontagePOT: cfg wajib struct.'); end
    cfg = i_defaults(cfg);
    if isempty(cfg.outFile), error('buildMontagePOT: cfg.outFile wajib.'); end
    if isempty(cfg.potRecs), error('buildMontagePOT: cfg.potRecs kosong (tarik garis PSG dulu).'); end

    fig = i_renderGridPOT(data, cfg);
    cleaner = onCleanup(@() i_safeClose(fig));
    i_export(fig, cfg.outFile, cfg.dpi);
    outFile = cfg.outFile;
end


% =====================================================================
function cfg = i_defaults(cfg)
    if ~isfield(cfg,'scalar')   || isempty(cfg.scalar),   cfg.scalar = 'velocity_magnitude'; end
    if ~isfield(cfg,'frames')   || isempty(cfg.frames),   cfg.frames = 1; end
    if ~isfield(cfg,'rows')     || isempty(cfg.rows),     cfg.rows = 1; end
    if ~isfield(cfg,'cols')     || isempty(cfg.cols),     cfg.cols = numel(cfg.frames); end
    if ~isfield(cfg,'climVel')  || numel(cfg.climVel)~=2, cfg.climVel = [0 5]; end
    if ~isfield(cfg,'shearAbs') || isempty(cfg.shearAbs), cfg.shearAbs = 0.05; end
    if ~isfield(cfg,'gsOn')     || isempty(cfg.gsOn),     cfg.gsOn = true; end
    if ~isfield(cfg,'gsAlpha')  || isempty(cfg.gsAlpha),  cfg.gsAlpha = 0.30; end
    if ~isfield(cfg,'claheOn')  || isempty(cfg.claheOn),  cfg.claheOn = true; end
    if ~isfield(cfg,'adjOn')    || isempty(cfg.adjOn),    cfg.adjOn = true; end
    if ~isfield(cfg,'glyphOn')  || isempty(cfg.glyphOn),  cfg.glyphOn = true; end
    if ~isfield(cfg,'glyphLW')  || isempty(cfg.glyphLW),  cfg.glyphLW = 1.2; end
    if ~isfield(cfg,'glyphSp')  || isempty(cfg.glyphSp),  cfg.glyphSp = 3; end
    if ~isfield(cfg,'label')    || isempty(cfg.label),    cfg.label = 'letter'; end
    if ~isfield(cfg,'dpi')      || isempty(cfg.dpi),      cfg.dpi = 200; end
    if ~isfield(cfg,'title'),    cfg.title = ''; end
    if ~isfield(cfg,'outFile'),  cfg.outFile = ''; end
    if ~isfield(cfg,'potRecs'),  cfg.potRecs = []; end
    if ~isfield(cfg,'potNF') || isempty(cfg.potNF), cfg.potNF = i_recsNF(cfg.potRecs); end
    if ~isfield(cfg,'potIndenter'), cfg.potIndenter = []; end
    if ~isfield(cfg,'markMode') || isempty(cfg.markMode), cfg.markMode = 'frame'; end
    if ~isfield(cfg,'geom'),      cfg.geom = []; end
    if ~isfield(cfg,'overrides'), cfg.overrides = []; end
    cfg.frames = round(cfg.frames(:).');
    cfg.frames = cfg.frames(isfinite(cfg.frames) & cfg.frames >= 1);
end


% =====================================================================
% Grid panel foto (atas) + axPOT lebar (bawah)
% =====================================================================
function fig = i_renderGridPOT(data, cfg)
    nF   = pivcore.data.frameCount(data);
    fr   = cfg.frames; fr(fr > nF) = nF;
    nP   = numel(fr);
    rows = max(1, cfg.rows); cols = max(1, cfg.cols);
    if rows*cols < nP, cols = ceil(nP / rows); end

    isShear = strcmpi(cfg.scalar, 'shear');
    fig = i_newFig(cfg.title);

    ar     = i_panelAspect(data, fr);
    PANELW = 240;
    panelH = max(40, PANELW / max(ar, 0.2));
    potH   = round(0.9 * panelH * rows);   % tinggi blok POT ~ proporsi grid
    potH   = max(180, min(potH, 360));
    figW = PANELW*cols + 130;              % + ruang colorbar global kanan
    figH = panelH*rows + potH + 90;        % grid + POT + judul/label
    set(fig, 'Position', [50 50 round(figW) round(figH)]);

    % SATU tiledlayout: (rows untuk grid foto) + (nPotRows untuk plot POT yang
    % MEMBENTANG SEMUA kolom). Bobot baris diatur lewat RowHeight relatif via
    % jumlah baris POT proporsional dgn potH/panelH. Pendekatan span-tile ini
    % kokoh (tak ada nested-layout/placeholder yang rapuh).
    nPotRows = max(1, round(potH / max(panelH, 1)));
    tl = tiledlayout(fig, rows + nPotRows, cols, 'TileSpacing','tight','Padding','tight');
    if ~isempty(cfg.title), title(tl, cfg.title, 'Interpreter','none'); end

    % --- Panel foto: baris 1..rows (tile 1..rows*cols, urut baca) ---
    for i = 1:nP
        ax = nexttile(tl, i);
        pivcore.montage.renderScalarPanel(ax, data, fr(i), cfg.scalar, cfg);
        set(ax,'XTick',[],'YTick',[]);
        i_annotate(ax, i, fr(i), cfg.label, cfg, nF);
    end
    i_globalColorbar(tl, isShear, cfg);

    % --- Plot POT: tile berikut, span [nPotRows cols] (lebar penuh) ---
    axPOT = nexttile(tl, rows*cols + 1, [nPotRows cols]);
    i_drawPOT(axPOT, cfg, fr, nF);
end


% =====================================================================
% Plot POT (spaghetti + indenter) + garis vertikal per frame
% =====================================================================
function i_drawPOT(ax, cfg, fr, nF)
    recs = cfg.potRecs;
    potNF = max(1, round(cfg.potNF));
    set(ax,'Color','w','XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
           'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top');
    hold(ax,'on');

    ymin = inf; ymax = -inf;
    for r = 1:numel(recs)
        [xv, yv] = pivcore.pot.records.curveXY(recs(r), potNF);
        g = isfinite(xv) & isfinite(yv); if ~any(g), continue; end
        col = [0.4 0.4 0.4];
        if isfield(recs(r),'color') && numel(recs(r).color) == 3, col = recs(r).color; end
        plot(ax, xv(g), yv(g), '-', 'Color', col, 'LineWidth',1.0);
        ymin = min(ymin, min(yv(g))); ymax = max(ymax, max(yv(g)));
    end

    env = cfg.potIndenter;
    if isempty(env), env = i_indenterEnvelope(recs, potNF); end
    if ~isempty(env)
        xe = 1:numel(env); ge = isfinite(env);
        if any(ge)
            plot(ax, xe(ge), env(ge), '-', 'Color',[0 0 0], 'LineWidth',3);
            ymin = min(ymin, min(env(ge))); ymax = max(ymax, max(env(ge)));
        end
    end

    xlabel(ax,'Frame'); ylabel(ax,'|V| (px/frame)');
    grid(ax,'on');
    if potNF > 1, xlim(ax, [1 potNF]); end
    if isfinite(ymin) && isfinite(ymax) && ymax > ymin
        pad = 0.04*(ymax-ymin);
        ylim(ax, [ymin-pad ymax+pad]);
    end

    % --- Garis vertikal merah per bingkai yang ditampilkan + label angka ---
    % Label disejajarkan agar tak terpotong di tepi: bingkai paling kiri rata
    % kiri, paling kanan rata kanan, sisanya di tengah garis.
    yl = get(ax,'YLim');
    xl = get(ax,'XLim');
    for i = 1:numel(fr)
        k = max(1, min(fr(i), potNF));
        plot(ax, [k k], yl, '-', 'Color',[0.85 0 0], 'LineWidth',1.6);
        s = i_markLabel(cfg, i, fr(i), nF);
        if isempty(s), continue; end
        if k <= xl(1) + 0.02*(xl(2)-xl(1))
            ha = 'left';
        elseif k >= xl(2) - 0.02*(xl(2)-xl(1))
            ha = 'right';
        else
            ha = 'center';
        end
        text(ax, k, yl(2), s, 'Color',[0.85 0 0], ...
            'HorizontalAlignment',ha,'VerticalAlignment','bottom', ...
            'FontSize',9,'FontWeight','bold', ...
            'BackgroundColor',[1 1 1 0.7],'Margin',1, 'Clipping','off');
    end
    hold(ax,'off');
end


function s = i_markLabel(cfg, idx, frame, nF)
%I_MARKLABEL  Label angka di atas garis vertikal POT sesuai markMode:
%   'frame'    -> "f12"
%   'strain'   -> strain interpolasi posisi (X0/X1/L_pos), mis. "+1.83%"
%   'override' -> nilai override manual sejajar cfg.frames, mis. "+2.0%"
    switch lower(cfg.markMode)
        case 'strain'
            pct = i_frameStrainPct(cfg.geom, frame, nF);
            if isfinite(pct), s = sprintf('%+.2f%%', pct); else, s = sprintf('f%d', frame); end
        case 'override'
            v = NaN;
            if ~isempty(cfg.overrides) && idx <= numel(cfg.overrides), v = cfg.overrides(idx); end
            if isfinite(v), s = sprintf('%+.2f%%', v); else, s = sprintf('f%d', frame); end
        otherwise % 'frame'
            s = sprintf('f%d', frame);
    end
end


function pct = i_frameStrainPct(g, frame, nF)
%I_FRAMESTRAINPCT  Strain (%) bingkai via interpolasi linier antar-bingkai:
%   strain(k) = (k-1)/(nF-1) * strain_cumm_pct (bingkai 1 = 0%, nF = penuh).
    pct = NaN;
    if ~(isstruct(g) && isfield(g,'strain_cumm_pct') && ...
         isscalar(g.strain_cumm_pct) && isfinite(g.strain_cumm_pct)), return; end
    if isfield(g,'valid') && ~isempty(g.valid) && ~logical(g.valid), return; end
    nF = max(1, round(nF)); k = round(frame);
    if nF <= 1, pct = g.strain_cumm_pct; return; end
    k = max(1, min(k, nF));
    pct = (k-1)/(nF-1) * g.strain_cumm_pct;
end


function env = i_indenterEnvelope(recs, nF)
    env = [];
    if isempty(recs), return; end
    M = -inf(1, nF); any_ = false;
    for r = 1:numel(recs)
        [~, yv] = pivcore.pot.records.curveXY(recs(r), nF);
        if isempty(yv), continue; end
        m = numel(yv); seg = M(1:m); g = isfinite(yv);
        seg(g) = max(seg(g), yv(g)); M(1:m) = seg; any_ = true;
    end
    if ~any_, return; end
    M(~isfinite(M)) = NaN; env = M;
end


function nF = i_recsNF(recs)
    nF = 1;
    for r = 1:numel(recs)
        if isfield(recs(r),'data'), nF = max(nF, numel(recs(r).data)); end
    end
end


% =====================================================================
% Anotasi panel foto (sudut) — tunjukkan frame / strain / override
% =====================================================================
function i_annotate(ax, idx, frame, mode, cfg, nF)
    % Saat penanda POT = strain/override, label panel mengikuti (konsisten).
    base = '';
    switch lower(mode)
        case 'none', base = '';
        case 'frame', base = sprintf('f%d', frame);
        otherwise % 'letter'
            letters = 'a':'z';
            if idx <= numel(letters), lt = letters(idx); else, lt = '?'; end
            base = sprintf('%c  f%d', lt, frame);
    end
    extra = '';
    switch lower(cfg.markMode)
        case 'strain'
            pct = i_frameStrainPct(cfg.geom, frame, nF);
            if isfinite(pct), extra = sprintf('%+.2f%%', pct); end
        case 'override'
            v = NaN;
            if ~isempty(cfg.overrides) && idx <= numel(cfg.overrides), v = cfg.overrides(idx); end
            if isfinite(v), extra = sprintf('%+.2f%%', v); end
    end
    if isempty(base) && isempty(extra), return; end
    if isempty(base),      s = extra;
    elseif isempty(extra), s = base;
    else,                  s = sprintf('%s | %s', base, extra);
    end
    text(ax, 0.97, 0.93, s, 'Units','normalized', ...
        'HorizontalAlignment','right','VerticalAlignment','top', ...
        'FontWeight','bold','FontSize',9,'Color',[0 0 0], ...
        'BackgroundColor',[1 1 1 0.6]);
end


% =====================================================================
% Colorbar global / figure off-screen / export — sama buildMontage
% =====================================================================
function i_globalColorbar(tl, isShear, cfg)
    ax = nexttile(tl, 1);
    if isShear
        colormap(ax, pivcore.util.divergingMap(256));
        clim(ax, [-cfg.shearAbs cfg.shearAbs]);
        lab = 'shear strain (du/dy+dv/dx)';
    else
        colormap(ax, pivcore.util.velColormap(256));
        clim(ax, cfg.climVel);
        lab = 'Velocity magnitude';
    end
    cb = colorbar(ax); cb.Layout.Tile = 'east'; cb.Label.String = lab;
end


function fig = i_newFig(ttl)
    nm = 'GRAINSA3 Montage POT';
    if ~isempty(ttl), nm = ttl; end
    fig = figure('Name',nm,'NumberTitle','off','Color',[1 1 1], ...
        'Visible','off','Units','pixels','MenuBar','none','ToolBar','none');
    try, pivui.forceLightTheme(fig); catch, end
end


function i_export(fig, outFile, dpi)
    d = fileparts(outFile);
    if ~isempty(d) && ~isfolder(d), mkdir(d); end
    drawnow;
    if exist('exportgraphics','file') == 2
        exportgraphics(fig, outFile, 'Resolution', dpi, 'BackgroundColor','white');
    else
        print(fig, outFile, '-dpng', sprintf('-r%d', round(dpi)));
    end
end


function ar = i_panelAspect(data, frames)
    ar = 3;
    for k = frames(:).'
        x = pivcore.data.safeFrame(data.x, k);
        y = pivcore.data.safeFrame(data.y, k);
        if isempty(x) || isempty(y), continue; end
        w = max(x(:)) - min(x(:));
        hgt = max(y(:)) - min(y(:));
        if isfinite(w) && isfinite(hgt) && hgt > 0 && w > 0
            ar = w / hgt; return;
        end
    end
end


function i_safeClose(fig)
    try, if ishghandle(fig), close(fig); end, catch, end
end
