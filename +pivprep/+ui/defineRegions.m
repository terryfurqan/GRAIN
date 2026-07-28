function regions = defineRegions(imgOverlay, mode, useStab, cfg)
%DEFINEREGIONS  Pemilihan ROI interaktif: framing dan anchor.
%
%   regions = pivprep.ui.defineRegions(imgOverlay, mode, useStab, cfg)
%
%   INPUT:
%       imgOverlay  gambar overlay frame pertama + terakhir (50/50)
%       mode        'square' atau 'crop'
%       useStab     logical, true jika anchor stabilisasi perlu didefinisikan
%       cfg         struct opsi:
%           .gridN          jumlah sel grid (default 5)
%           .gridColor      warna grid (default 'w')
%           .gridLineWidth  ketebalan garis grid (default 2)
%           .initMargin     margin awal kotak (default 0.10)
%
%   OUTPUT:
%       regions struct:
%           .framePts   Nx2 titik untuk framing
%           .anchorPts  Mx2 titik anchor (kosong jika useStab false)
%           .anchorROI  [x y w h] bounding box anchor (kosong jika useStab false)

    util = pivprep.util.utilities;

    if nargin < 4 || isempty(cfg)
        cfg = struct();
    end
    if ~isfield(cfg, 'gridN');         cfg.gridN         = 5;    end
    if ~isfield(cfg, 'gridColor');     cfg.gridColor     = 'w';  end
    if ~isfield(cfg, 'gridLineWidth'); cfg.gridLineWidth = 2;    end
    if ~isfield(cfg, 'initMargin');    cfg.initMargin    = 0.10; end

    [hIm, wIm, ~] = size(imgOverlay);

    % --- Langkah A: Framing region ---
    figA = figure( ...
        'Name', 'PIVPrep - Step A: Framing Region', ...
        'NumberTitle', 'off', 'Color', 'k', ...
        'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
    imshow(imgOverlay);
    axA = gca;
    util.drawGrid(axA, hIm, wIm, cfg.gridN, cfg.gridColor, cfg.gridLineWidth);

    m = cfg.initMargin;
    if strcmpi(mode, 'square')
        defPts = [wIm*m,     hIm*m;      ...
                  wIm*(1-m), hIm*m;      ...
                  wIm*(1-m), hIm*(1-m);  ...
                  wIm*m,     hIm*(1-m)];
        title({ ...
            'STEP A - SQUARE MODE (4-point projective, rectangular output)', ...
            'Sesuaikan 4 sudut polygon cyan ke area yang akan direktifikasi.', ...
            'Lebar rata-rata sisi atas dan bawah menjadi lebar output;', ...
            'tinggi rata-rata sisi kiri dan kanan menjadi tinggi output.', ...
            'Klik-tarik titik sudut. Double-click pada polygon untuk konfirmasi.'}, ...
            'Color', 'y', 'FontSize', 11, 'FontWeight', 'bold');
        hPoly = util.safeDrawPolygon(defPts, 'c', 'Rectify Area');
        wait(hPoly);
        regions.framePts = hPoly.Position;
    else
        % Crop default: kotak resizable (bukan polygon edit titik).
        % Pengguna cukup menarik sisi/sudut untuk resize sumbu X dan Y.
        defRect = [wIm*m, hIm*m, wIm*(1-2*m), hIm*(1-2*m)];
        title({ ...
            'STEP A - CROP MODE (rectangular crop)', ...
            'Tarik sisi atau sudut kotak cyan untuk resize sumbu X dan Y.', ...
            'Tarik bagian dalam kotak untuk menggeser posisi.', ...
            'Aspect ratio kotak dipertahankan pada output.', ...
            'Double-click pada kotak untuk konfirmasi.'}, ...
            'Color', 'y', 'FontSize', 11, 'FontWeight', 'bold');
        hRect = util.safeDrawRectangle(defRect, 'c', 'Crop Area');
        wait(hRect);
        % Konversi [x y w h] menjadi 4 titik sudut agar kompatibel dengan
        % pivprep.geom.computeFraming (mode 'crop' memakai bounding box).
        regions.framePts = util.rectToCorners(hRect.Position);
    end

    close(figA);

    % --- Langkah B: Anchor stabilisasi ---
    if useStab
        figB = figure( ...
            'Name', 'PIVPrep - Step B: Stabilization Anchor', ...
            'NumberTitle', 'off', 'Color', 'k', ...
            'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
        imshow(imgOverlay);
        axB = gca;
        util.drawGrid(axB, hIm, wIm, cfg.gridN, cfg.gridColor, cfg.gridLineWidth);

        title({ ...
            'STEP B - STABILIZATION ANCHOR', ...
            'Gambar polygon di area background yang DIAM (kaya tekstur, hindari area bergerak).', ...
            'Klik titik-titik untuk membentuk polygon. Double-click untuk konfirmasi.'}, ...
            'Color', 'y', 'FontSize', 11, 'FontWeight', 'bold');

        hPolyB = util.safeDrawPolygon([], 'y', 'Anchor');
        wait(hPolyB);
        anchorPts = hPolyB.Position;
        close(figB);

        regions.anchorPts = anchorPts;
        regions.anchorROI = [ ...
            min(anchorPts(:,1)), ...
            min(anchorPts(:,2)), ...
            max(anchorPts(:,1)) - min(anchorPts(:,1)), ...
            max(anchorPts(:,2)) - min(anchorPts(:,2))];
    else
        regions.anchorPts = [];
        regions.anchorROI = [];
    end
end
