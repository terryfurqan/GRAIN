function renderScalarPanel(ax, data, k, scalar, cfg)
%RENDERSCALARPANEL  Lukis SATU panel skalar PIV (vel/shear + GS + glyph) ke ax.
%
%   pivcore.montage.renderScalarPanel(ax, data, k, scalar, cfg)
%
%   SUMBER TUNGGAL pola "lukis panel" yang DULU terduplikasi di TIGA tempat:
%     (1) buildMontage.m  -> i_drawPanel (mode grid & 2-kolom)
%     (2) PAB_step_3.m    -> i_renderMain (inti skalar/GS/glyph axMain)
%     (3) PAB_step_3a.m   -> i_renderMain (inti yang sama)
%   Ketiganya kini MEMANGGIL fungsi ini supaya lukisan IDENTIK byte-for-byte
%   (flip-V citra, glyph yF/-V, colormap JET vel / diverging shear, CLim).
%
%   CAKUPAN (CORE SAJA): hanya melukis skalar (imagesc), overlay GS (grayCLAHE
%   + AlphaData), dan glyph vektor — lalu menata sumbu (YDir normal, xlim/ylim,
%   daspect [1 1 1], box, Layer top). TIDAK menyetel XTick/YTick, TIDAK
%   menggambar colorbar/judul/teks: hal-hal itu BEDA per-pemanggil dan menjadi
%   tanggung jawab pemanggil SETELAH fungsi ini (montase: set XTick/YTick=[];
%   GRAINSA3/3a: colorbar+label, judul, teks "kosong", penguncian interaksi).
%
%   Argumen:
%     ax      : target axes (digambari, sumbu ditata; cla() oleh pemanggil)
%     data    : struct dataset PIVLAB terstandar (pivcore.data.buildDataset)
%     k       : indeks bingkai (fallback ke 1 bila x/y bingkai-k kosong)
%     scalar  : 'shear' -> shear strain; selain itu -> velocity_magnitude
%     cfg     : struct opsi lukis. Field yang dipakai (struct h dari GRAINSA3/3a
%               maupun cfg montase sudah memuat semuanya):
%        .gsOn     logical overlay GS         .glyphOn  logical overlay glyph
%        .gsAlpha  transparansi GS (def 0.30) .glyphLW  lebar garis glyph
%        .claheOn  logical CLAHE pada GS      .glyphSp  spasi sampling glyph
%        .adjOn    logical auto kontras GS    .shearAbs CLim shear |X| (def 0.05)
%                                             .climVel  [lo hi] CLim vel (def [0 1])
%
%   READ-ONLY: data tak diubah, hanya dibaca per-bingkai. Tak mengembalikan apa-apa.

    x = pivcore.data.safeFrame(data.x, k);
    y = pivcore.data.safeFrame(data.y, k);
    if isempty(x) || isempty(y)
        x = pivcore.data.safeFrame(data.x, 1);
        y = pivcore.data.safeFrame(data.y, 1); k = 1;
    end
    if isempty(x) || isempty(y)
        axis(ax,'off'); return;
    end
    xExt = [min(x(:)) max(x(:))];
    yExt = [min(y(:)) max(y(:))];

    hold(ax,'on');
    if strcmpi(scalar, 'shear')
        Z = pivcore.data.computeShearRate(data, k, 'mode','engineering');
        cmap = pivcore.util.divergingMap(256);
        X = cfg.shearAbs; if ~(isfinite(X) && X > 0), X = 0.05; end
        clo = -X; chi = X;
    else
        Z = pivcore.data.resolveScalar(data, 'velocity_magnitude', k);
        cmap = pivcore.util.velColormap(256);   % JET (default), bukan parula/turbo
        clo = cfg.climVel(1); chi = cfg.climVel(2);
        if ~(isfinite(clo) && isfinite(chi) && chi > clo), clo = 0; chi = 1; end
    end
    if ~isempty(Z)
        him = imagesc(ax, xExt, [yExt(2) yExt(1)], Z);
        % Gambar dasar TAK boleh menelan klik: kalau HitTest on, ia menutupi
        % tengah axMain & memblokir seleksi/seret ROI garis PSG (hanya tepi
        % kiri yg lolos). Samakan dgn overlay GS di bawah.
        set(him, 'HitTest','off', 'PickableParts','none');
        colormap(ax, cmap); clim(ax, [clo chi]);
    end
    if cfg.gsOn
        bg = pivcore.data.bgAt(data, k);
        if ~isempty(bg)
            % GS dipaksa abu-abu (+CLAHE +auto kontras/brightness).
            % Cache OPSIONAL (cfg.gsCache=containers.Map, dibuat sekali per sesi
            % ekspor): grayCLAHE deterministik utk (k, claheOn, adjOn). Pemanggil
            % live tak set field -> jalur lama identik. k = EFEKTIF (line 39).
            if isfield(cfg,'gsCache') && isa(cfg.gsCache,'containers.Map')
                gk = sprintf('%d|%d|%d', k, logical(cfg.claheOn), logical(cfg.adjOn));
                if isKey(cfg.gsCache, gk)
                    rgb = cfg.gsCache(gk);
                else
                    rgb = pivcore.util.grayCLAHE(bg, cfg.claheOn, cfg.adjOn);
                    cfg.gsCache(gk) = rgb;
                end
            else
                rgb = pivcore.util.grayCLAHE(bg, cfg.claheOn, cfg.adjOn);
            end
            a = cfg.gsAlpha; if ~(isfinite(a) && a >= 0 && a <= 1), a = 0.30; end
            image(ax, 'XData', xExt, 'YData', [yExt(2) yExt(1)], ...
                'CData', rgb, 'AlphaData', a, ...
                'HitTest','off','PickableParts','none');
        end
    end
    % Overlay glyph vektor (ikut flip-V citra: posisi y & tanda V dibalik).
    if cfg.glyphOn
        [U, V] = pivcore.data.pickAnyVel(data, k);
        if ~isempty(U) && ~isempty(V)
            yF = (yExt(2) + yExt(1)) - y;
            gcol = [0 0 0];
            if isfield(cfg,'glyphColor') && numel(cfg.glyphColor)==3, gcol = cfg.glyphColor; end
            pivcore.util.drawGlyphs(ax, x, yF, U, -V, cfg.glyphSp, cfg.glyphLW, gcol);
        end
    end
    hold(ax,'off');
    set(ax,'YDir','normal');
    xlim(ax, xExt); ylim(ax, yExt);
    daspect(ax, [1 1 1]); box(ax,'on'); set(ax,'Layer','top');
end
