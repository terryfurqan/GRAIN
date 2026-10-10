function out = setup_20_horizontal_lines(pivMatFile, refFrame)
% SETUP_20_HORIZONTAL_LINES  Membuat 20 garis horizontal (L01 dari Atas s/d L20 di Bawah)
% pada TKS-5_cm-1, memvisualisasikan posisi ke-20 garis di atas citra eksperimen,
% serta men-scan matriks |V| dan Cleaned Shear Strain (\gamma_{xy}) untuk ke-20 garis.

    if nargin < 1 || isempty(pivMatFile)
        pivMatFile = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm/TKS_5 Compare/TKS-5_cm-1-OVL-S0-111-3p16px.mat';
    end
    if nargin < 2 || isempty(refFrame)
        refFrame = 35;
    end

    here = fileparts(mfilename('fullpath'));
    cd(here);
    grain_setup();

    [mDir, ~, ~] = fileparts(pivMatFile);
    expName = 'TKS-5_cm-1';
    outDir = fullfile(mDir, sprintf('%s_PSG_Kymograph_POT', expName));
    if ~isfolder(outDir), mkdir(outDir); end

    fprintf('Memuat dataset %s...\n', pivMatFile);
    S = load(pivMatFile);
    data = pivcore.data.buildDataset(S);
    nF = data.nFrames;
    x1 = pivcore.data.safeFrame(data.x, 1);
    y1 = pivcore.data.safeFrame(data.y, 1);
    xExt = [min(x1(:)), max(x1(:))]; % [9 .. 2993]
    yExt = [min(y1(:)), max(y1(:))]; % [9 .. 913]

    % Siapkan citra referensi Frame 35 (CLAHE grayscale + Cleaned Shear Strain)
    bg = pivcore.data.bgAt(data, refFrame);
    rgb = pivcore.util.grayCLAHE(bg, true, true);
    [U, V] = pivcore.data.pickAnyVel(data, refFrame);
    yF = (yExt(2) + yExt(1)) - y1;

    Zraw = pivcore.data.computeShearRate(data, refFrame, 'mode', 'engineering');
    Zcln = imgaussfilt(medfilt2(Zraw, [3 3], 'symmetric'), 1.8);
    Zdb  = Zcln;
    Zdb(abs(Zdb) < 0.0035) = 0;

    % =====================================================================
    % DEFINISI 20 GARIS HORIZONTAL DARI ATAS KE BAWAH (L01 = Atas -> L20 = Bawah)
    % =====================================================================
    nLines = 20;
    % Kita buat 20 garis horizontal merata dari atas ke bawah pada rentang Y penuh
    % dengan margin 2.5% di tepi paling atas & bawah (posPct = linspace(2.5, 97.5, 20)%)
    posPct_full = linspace(2.5, 97.5, nLines); % 2.5% (Atas) s/d 97.5% (Bawah)
    % Dalam koordinat axMain (YDir = normal, yExt(2)=913 di Atas, yExt(1)=9 di Bawah):
    yLines_ax = yExt(2) - (posPct_full / 100) * (yExt(2) - yExt(1));
    % Dalam koordinat baris gambar/grid PIV (yv: 9 di Atas s/d 913 di Bawah):
    yMid = (yExt(1) + yExt(2)) / 2;
    yLines_row = 2 * yMid - yLines_ax;

    % =====================================================================
    % VISUALISASI 20 GARIS HORIZONTAL PADA CITRA EKSPERIMEN
    % Panel Atas : Citra Grayscale CLAHE + 20 Garis Horizontal (L01 - L20)
    % Panel Bawah: Overlay Cleaned Shear Strain (\gamma_{xy}) + 20 Garis Horizontal + Titik Sesar
    % =====================================================================
    fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2500 1650]);
    try, theme(fig, 'light'); catch, end
    try, fig.Theme = 'light'; catch, end

    % --- PANEL 1: Citra Pasir Grayscale CLAHE + 20 Garis Horizontal ---
    ax1 = axes('Parent', fig, 'Position', [0.05 0.53 0.89 0.42]);
    hold(ax1, 'on');
    image(ax1, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgb);

    cmapLines = turbo(nLines);
    for i = 1:nLines
        yi = yLines_ax(i);
        col = cmapLines(i, :);
        % Garis kontras (hitam tipis di bawah, warna terang putus-putus di atas)
        plot(ax1, xExt, [yi yi], '-', 'Color', [0 0 0 0.65], 'LineWidth', 2.4);
        plot(ax1, xExt, [yi yi], '--', 'Color', col, 'LineWidth', 1.8);

        % Label Kiri: L01 .. L20 + pos%
        lblLeft = sprintf('L%02d (%4.1f%%)', i, posPct_full(i));
        text(ax1, xExt(1) + 15, yi, lblLeft, ...
            'Color', 'w', 'BackgroundColor', [0 0 0 0.78], ...
            'FontSize', 8.5, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');

        % Label Kanan: Y_ax dan Y_row
        lblRight = sprintf('L%02d | Y=%.0f px', i, yi);
        text(ax1, xExt(2) - 15, yi, lblRight, ...
            'Color', [1 0.95 0.2], 'BackgroundColor', [0 0 0 0.78], ...
            'FontSize', 8.5, 'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');
    end

    set(ax1, 'YDir', 'normal');
    axis(ax1, 'image'); xlim(ax1, xExt); ylim(ax1, yExt);
    ylabel(ax1, 'Posisi Y (px) [Atas = 913, Bawah = 9]', 'FontWeight', 'bold', 'FontSize', 11);
    title(ax1, sprintf('TKS-5\\_cm-1 (Frame %d/%d) — Tata Letak 20 Garis Horizontal (L01 Atas \\rightarrow L20 Bawah) di Atas Citra Grayscale', ...
        refFrame, nF), 'FontSize', 13.5, 'FontWeight', 'bold', 'Color', 'k');
    i_styleAx(ax1);

    % --- PANEL 2: Overlay Cleaned Shear Strain + Vektor + 20 Garis Horizontal ---
    ax2 = axes('Parent', fig, 'Position', [0.05 0.05 0.89 0.42]);
    hold(ax2, 'on');
    imagesc(ax2, xExt, [yExt(2) yExt(1)], Zdb);
    colormap(ax2, jet(256));
    clim(ax2, [-0.02, 0.02]);
    image(ax2, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgb, 'AlphaData', 0.32);
    pivcore.util.drawGlyphs(ax2, x1, yF, U, -V, 12, 1.0, [1 1 1]);

    xv = x1(1, :);
    yv = y1(:, 1);
    interiorMask = (xv >= 400) & (xv <= 2600);

    xFaultPerLine = nan(nLines, 1);
    shrPeakPerLine = nan(nLines, 1);

    for i = 1:nLines
        yi = yLines_ax(i);
        rIdx = yLines_row(i);
        [~, ri] = min(abs(yv - rIdx));
        rowSlice = Zcln(ri, :);
        rowSliceMasked = rowSlice;
        rowSliceMasked(~interiorMask) = -Inf;
        [pkVal, cMax] = max(rowSliceMasked);

        plot(ax2, xExt, [yi yi], '-', 'Color', [0 0 0 0.55], 'LineWidth', 1.8);
        plot(ax2, xExt, [yi yi], '--', 'Color', [1 1 1 0.85], 'LineWidth', 1.2);

        % Tandai titik perpotongan garis dengan zona sesar utama bila melewati ambang deadband
        if pkVal >= 0.0035
            xFaultPerLine(i) = xv(cMax);
            shrPeakPerLine(i) = pkVal;
            plot(ax2, xv(cMax), yi, 'o', 'MarkerSize', 8, ...
                'MarkerFaceColor', [1 0.95 0], 'MarkerEdgeColor', 'k', 'LineWidth', 1.4);
        end

        lblLeft = sprintf('L%02d (Y=%.0f)', i, yi);
        text(ax2, xExt(1) + 15, yi, lblLeft, ...
            'Color', 'w', 'BackgroundColor', [0 0 0 0.75], ...
            'FontSize', 8.5, 'FontWeight', 'bold', 'VerticalAlignment', 'middle');

        if isfinite(xFaultPerLine(i))
            lblRight = sprintf('L%02d | X_{sesar}≈%.0f px (\\gamma_{xy}=%+.3f)', i, xFaultPerLine(i), shrPeakPerLine(i));
            txtCol = [0.4 1.0 0.4];
        else
            lblRight = sprintf('L%02d | (di luar zona sesar)', i);
            txtCol = [0.85 0.85 0.85];
        end
        text(ax2, xExt(2) - 15, yi, lblRight, ...
            'Color', txtCol, 'BackgroundColor', [0 0 0 0.78], ...
            'FontSize', 8.5, 'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');
    end

    set(ax2, 'YDir', 'normal');
    axis(ax2, 'image'); xlim(ax2, xExt); ylim(ax2, yExt);
    xlabel(ax2, 'Posisi X sepanjang Sandbox (px)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(ax2, 'Posisi Y (px) [Atas = 913, Bawah = 9]', 'FontWeight', 'bold', 'FontSize', 11);
    title(ax2, sprintf('TKS-5\\_cm-1 (Frame %d/%d) — 20 Garis Horizontal (L01 - L20) + Overlay Cleaned Shear Strain \\gamma_{xy} & Titik Perpotongan Sesar (Lingkaran Kuning)', ...
        refFrame, nF), 'FontSize', 13.5, 'FontWeight', 'bold', 'Color', 'k');
    cb = colorbar(ax2, 'eastoutside');
    cb.Label.String = 'Cleaned \gamma_{xy} [\pm0.02]';
    cb.Color = 'k';
    i_styleAx(ax2);

    outImg = fullfile(outDir, sprintf('%s_20_Garis_Horizontal_L01_L20.jpg', expName));
    exportgraphics(fig, outImg, 'Resolution', 150, 'BackgroundColor', 'white');
    close(fig);

    % Simpan tabel koordinat 20 garis
    T_lines = table((1:nLines)', arrayfun(@(k) sprintf('L%02d', k), (1:nLines)', 'UniformOutput', false), ...
        posPct_full(:), round(yLines_ax(:), 1), round(yLines_row(:), 1), ...
        round(xFaultPerLine(:), 1), round(shrPeakPerLine(:), 4), ...
        'VariableNames', {'Line_Index', 'Line_ID', 'Pos_Pct_From_Top', 'Y_AxMain_px', 'Y_GridRow_px', 'X_Fault_Frame35_px', 'Peak_Shear_Frame35'});
    outCsv = fullfile(outDir, sprintf('%s_20_Garis_Horizontal_Koordinat.csv', expName));
    writetable(T_lines, outCsv);
    disp(T_lines);

    out = struct('outImg', outImg, 'outCsv', outCsv, 'T_lines', T_lines);
    fprintf('\n✅ Visualisasi 20 Garis Horizontal tersimpan di:\n   %s\n', outImg);
end

function i_styleAx(ax)
    ax.Color = [1 1 1];
    ax.XColor = [0.1 0.1 0.1];
    ax.YColor = [0.1 0.1 0.1];
    ax.Title.Color = [0.05 0.05 0.05];
    ax.XLabel.Color = [0.1 0.1 0.1];
    ax.YLabel.Color = [0.1 0.1 0.1];
    box(ax, 'on');
end
