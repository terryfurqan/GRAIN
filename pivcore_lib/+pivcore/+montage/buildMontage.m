function outFile = buildMontage(data, cfg)
%BUILDMONTAGE  Render montase panel-panel PIV (vel/shear+GS) OFF-SCREEN ke PNG.
%
%   outFile = pivcore.montage.buildMontage(data, cfg)
%
%   READ-ONLY: data tak diubah, hanya dibaca per-bingkai. Montase digambar di
%   figure TAK-TERLIHAT ('Visible','off') lalu di-export sebagai PNG (exportgraphics
%   bila ada, fallback print -dpng). Spacing antar panel dibikin IRIT (rapat,
%   meniru figur publikasi) memakai tiledlayout('TileSpacing','compact').
%
%   CLim disuplai SAMA untuk semua panel (cfg.climVel / cfg.shearAbs) -> warna
%   konsisten antar tahap, satu colorbar global per kolom-jenis.
%
%   cfg (struct):
%     .mode      'grid'  -> grid rows x cols, satu jenis skalar (cfg.scalar)
%                'twocol'-> 2 kolom: kiri vel mag, kanan shear; cfg.rows baris,
%                           tiap baris satu frame (cfg.frames(i)).
%     .scalar    'velocity_magnitude' | 'shear'  (mode 'grid' saja)
%     .frames    vektor indeks bingkai yang dipasang (urut baca: baris->kolom)
%     .rows,.cols  dimensi grid (mode 'grid'). mode 'twocol': cols=2 paksa.
%     .climVel   [lo hi] CLim velocity (mm/s atau px/frame)
%     .shearAbs  X -> CLim shear simetris [-X X]
%     .gsOn      logical overlay grayscale
%     .gsAlpha   0..1 transparansi grayscale
%     .label     'letter' (a,b,c+frame) | 'frame' (f12) | 'none'
%     .outFile   path PNG tujuan (wajib)
%     .dpi       resolusi (default 200)
%     .title     judul figur (opsional)
%
%   Mengembalikan path PNG yang ditulis (= cfg.outFile). Error bila gagal.

    if nargin < 2 || ~isstruct(cfg), error('buildMontage: cfg wajib struct.'); end
    cfg = i_defaults(cfg);
    if isempty(cfg.outFile), error('buildMontage: cfg.outFile wajib.'); end

    switch lower(cfg.mode)
        case 'twocol'
            fig = i_renderTwoCol(data, cfg);
        otherwise
            fig = i_renderGrid(data, cfg);
    end
    cleaner = onCleanup(@() i_safeClose(fig));

    % --- Export off-screen ---
    i_export(fig, cfg.outFile, cfg.dpi);
    outFile = cfg.outFile;
end


% =====================================================================
function cfg = i_defaults(cfg)
    if ~isfield(cfg,'mode')     || isempty(cfg.mode),     cfg.mode = 'grid'; end
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
    cfg.frames = round(cfg.frames(:).');
    cfg.frames = cfg.frames(isfinite(cfg.frames) & cfg.frames >= 1);
end


% =====================================================================
% Mode grid: rows x cols panel, satu jenis skalar
% =====================================================================
function fig = i_renderGrid(data, cfg)
    nF   = pivcore.data.frameCount(data);
    fr   = cfg.frames; fr(fr > nF) = nF;
    nP   = numel(fr);
    rows = max(1, cfg.rows); cols = max(1, cfg.cols);
    if rows*cols < nP, cols = ceil(nP / rows); end

    isShear = strcmpi(cfg.scalar, 'shear');
    fig = i_newFig(cfg.title);
    % Tinggi tile = lebar/aspek panel -> panel WIDE-SHORT mengisi penuh tanpa
    % gap vertikal besar. Lebar panel tetap (PANELW px), tinggi mengikuti aspek.
    ar     = i_panelAspect(data, fr);
    PANELW = 240;                       % lebar tiap panel (px)
    panelH = max(40, PANELW / max(ar, 0.2));
    figW = PANELW*cols + 130;           % + ruang colorbar global kanan
    figH = panelH*rows  + 70;           % + ruang judul atas
    set(fig, 'Position', [50 50 round(figW) round(figH)]);

    tl = tiledlayout(fig, rows, cols, 'TileSpacing','tight','Padding','tight');
    if ~isempty(cfg.title), title(tl, cfg.title, 'Interpreter','none'); end

    for i = 1:nP
        ax = nexttile(tl, i);
        pivcore.montage.renderScalarPanel(ax, data, fr(i), cfg.scalar, cfg);
        set(ax,'XTick',[],'YTick',[]);   % panel rapat: tanpa tick (irit ruang)
        i_annotate(ax, i, fr(i), cfg.label);
    end
    % Satu colorbar global (kanan).
    i_globalColorbar(tl, isShear, cfg);
end


% =====================================================================
% Mode 2-kolom: kiri vel mag / kanan shear, cfg.rows baris (1 frame/baris)
% =====================================================================
function fig = i_renderTwoCol(data, cfg)
    nF = pivcore.data.frameCount(data);
    fr = cfg.frames; fr(fr > nF) = nF;
    rows = numel(fr);
    if rows < 1, error('buildMontage: tak ada frame untuk mode 2-kolom.'); end

    fig = i_newFig(cfg.title);
    % Tinggi tiap baris = lebar panel / aspek -> panel rapat tanpa gap vertikal.
    ar     = i_panelAspect(data, fr);
    PANELW = 240;
    panelH = max(40, PANELW / max(ar, 0.2));
    figW = PANELW*2 + 200;              % 2 panel + 2 colorbar (kiri vel, kanan shear)
    figH = panelH*rows + 60;
    set(fig, 'Position', [50 50 round(figW) round(figH)]);
    tl = tiledlayout(fig, rows, 2, 'TileSpacing','tight','Padding','tight');
    if ~isempty(cfg.title), title(tl, cfg.title, 'Interpreter','none'); end

    letters = 'a':'z';
    for r = 1:rows
        % Kolom kiri: velocity_magnitude
        axL = nexttile(tl, (r-1)*2 + 1);
        pivcore.montage.renderScalarPanel(axL, data, fr(r), 'velocity_magnitude', cfg);
        set(axL,'XTick',[],'YTick',[]);   % panel rapat: tanpa tick (irit ruang)
        % Kolom kanan: shear
        axR = nexttile(tl, (r-1)*2 + 2);
        pivcore.montage.renderScalarPanel(axR, data, fr(r), 'shear', cfg);
        set(axR,'XTick',[],'YTick',[]);   % panel rapat: tanpa tick (irit ruang)
        % Label per BARIS (huruf + frame) di panel kiri.
        if r <= numel(letters), lt = letters(r); else, lt = '?'; end
        i_annotateTwoCol(axL, lt, fr(r), cfg.label);
    end
    % Dua colorbar global: vel (kolom kiri) & shear (kolom kanan).
    i_twoColColorbars(tl, cfg);
end


% =====================================================================
% Anotasi panel
% =====================================================================
function i_annotate(ax, idx, frame, mode)
    switch lower(mode)
        case 'none', return;
        case 'frame', s = sprintf('f%d', frame);
        otherwise % 'letter'
            letters = 'a':'z';
            if idx <= numel(letters), lt = letters(idx); else, lt = '?'; end
            s = sprintf('%c  f%d', lt, frame);
    end
    text(ax, 0.97, 0.93, s, 'Units','normalized', ...
        'HorizontalAlignment','right','VerticalAlignment','top', ...
        'FontWeight','bold','FontSize',9,'Color',[0 0 0], ...
        'BackgroundColor',[1 1 1 0.6]);
end


function i_annotateTwoCol(ax, letter, frame, mode)
    switch lower(mode)
        case 'none', return;
        case 'frame', s = sprintf('f%d', frame);
        otherwise, s = sprintf('%c  f%d', letter, frame);
    end
    text(ax, 0.97, 0.93, s, 'Units','normalized', ...
        'HorizontalAlignment','right','VerticalAlignment','top', ...
        'FontWeight','bold','FontSize',9,'Color',[0 0 0], ...
        'BackgroundColor',[1 1 1 0.6]);
end


% =====================================================================
% Colorbar global
% =====================================================================
function i_globalColorbar(tl, isShear, cfg)
    ax = nexttile(tl, 1);   % gunakan tile pertama sbg jangkar colorbar
    if isShear
        colormap(ax, pivcore.util.divergingMap(256));
        clim(ax, [-cfg.shearAbs cfg.shearAbs]);
        lab = 'shear strain (du/dy+dv/dx)';
    else
        colormap(ax, pivcore.util.velColormap(256));   % JET
        clim(ax, cfg.climVel);
        lab = 'Velocity magnitude';
    end
    cb = colorbar(ax);
    cb.Layout.Tile = 'east';
    cb.Label.String = lab;
end


function i_twoColColorbars(tl, cfg)
    % Colorbar velocity: jangkar di panel kiri-atas (tile 1).
    axV = nexttile(tl, 1);
    colormap(axV, pivcore.util.velColormap(256));   % JET
    clim(axV, cfg.climVel);
    cbV = colorbar(axV); cbV.Layout.Tile = 'west';
    cbV.Label.String = 'Velocity magnitude';
    % Colorbar shear: jangkar di panel kanan-atas (tile 2).
    axS = nexttile(tl, 2);
    colormap(axS, pivcore.util.divergingMap(256));
    clim(axS, [-cfg.shearAbs cfg.shearAbs]);
    cbS = colorbar(axS); cbS.Layout.Tile = 'east';
    cbS.Label.String = 'Shear strain';
end


% =====================================================================
% Figure off-screen + export
% =====================================================================
function fig = i_newFig(ttl)
    nm = 'PABSA3 Montage';
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
%I_PANELASPECT  Rasio LEBAR/TINGGI panel dari extent grid PIV (bingkai pertama
%   yang valid). Dipakai untuk menyetel tinggi tile = lebar/ar -> panel WIDE-
%   SHORT tak menyisakan gap vertikal besar (daspect [1 1 1] mengisi penuh).
    ar = 3;   % fallback wajar utk sandbox PIV (lebar ~3x tinggi)
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
