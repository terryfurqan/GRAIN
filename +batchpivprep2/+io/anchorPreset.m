classdef anchorPreset
%ANCHORPRESET  Pengelola anchor/"titik ikat" STABILISASI yang bisa di-reuse.
%
%   Anchor adalah polygon di area background yang DIAM, dipakai sebagai
%   referensi pengukuran jitter pada stabilisasi. Kelas ini menyimpan
%   anchor dalam sebuah STRUCT preset yang bisa disimpan ke berkas .mat
%   dan dimuat kembali untuk dipakai pada data baru (reuse lokasi ukur).
%
%   Pada BatchPIVPrep versi 2, anchor STABILISASI ini TERPISAH dari ROI
%   CROPPING (lihat batchpivprep2.io.cropPreset). Stabilisasi diambil dari
%   gambar yang BELUM di-crop, lalu cropping diterapkan setelahnya.
%
%   STRUKTUR PRESET (struct 'preset'):
%       .version     versi skema (=1)
%       .name        nama preset (string)
%       .anchorPts   Nx2 titik polygon, dalam koordinat piksel gambar
%                    referensi (resolusi penuh saat digambar)
%       .anchorROI   [x y w h] bounding box anchor (resolusi penuh)
%       .imgSize     [H W] ukuran gambar referensi saat anchor dibuat
%       .method      'surf' | 'phasecorr' (metode yang disarankan)
%       .thumb       thumbnail gambar referensi (untuk preview)
%       .thumbScale  skala thumb/asli (untuk memetakan anchorPts ke thumb)
%       .sourceImage path gambar referensi sumber (informasi)
%       .createdAt   timestamp pembuatan
%       .note        catatan bebas
%
%   Semua method statik; dipanggil sbg batchpivprep2.io.anchorPreset.<fn>.

    properties (Constant)
        MaxThumbDim = 800;   % dimensi maksimum sisi terpanjang thumbnail
        Version     = 1;
        % Jarak aman titik polygon dari tepi frame (default fitToImage),
        % supaya bulatan handle ROI tidak tersembunyi di luar gambar &
        % tetap bisa di-drag. Dibuat PROPORSIONAL terhadap ukuran gambar
        % karena handle berukuran tetap di satuan layar: pada gambar besar,
        % beberapa piksel saja tidak cukup memunculkan handle.
        FitMarginFrac = 0.012;  % fraksi sisi terpanjang gambar
        FitMarginMin  = 8;      % px, batas bawah
        FitMarginMax  = 10;     % px, batas atas (jangan terlalu masuk)
    end

    methods (Static)

        % -------------------------------------------------------------
        function preset = createFromImage(imgPath, method, gridN)
        %CREATEFROMIMAGE  Muat gambar, gambar polygon anchor interaktif,
        %   kembalikan struct preset. Mengembalikan [] bila dibatalkan.
            if nargin < 2 || isempty(method); method = 'surf'; end
            if nargin < 3 || isempty(gridN);  gridN  = 5;      end

            preset = [];
            if isempty(imgPath) || exist(imgPath, 'file') ~= 2
                return;
            end

            img = imread(imgPath);
            pts = batchpivprep2.io.anchorPreset.drawPolygon(img, gridN);
            if isempty(pts)
                return;   % dibatalkan / polygon kosong
            end

            [~, nm] = fileparts(imgPath);
            preset = batchpivprep2.io.anchorPreset.fromPoints( ...
                pts, size(img, [1 2]), method, img, ...
                sprintf('anchor-%s', nm), imgPath);
        end

        % -------------------------------------------------------------
        function pts = drawPolygon(img, gridN)
        %DRAWPOLYGON  Tampilkan gambar + grid, minta user menggambar
        %   polygon anchor. Kembalikan Nx2 titik (atau [] bila batal).
            if nargin < 2 || isempty(gridN); gridN = 5; end
            util = pivprep.util.utilities;

            [hIm, wIm, ~] = size(img);
            fig = figure( ...
                'Name', 'BatchPIVPrep2 - Gambar Anchor STABILISASI (area DIAM, kaya tekstur)', ...
                'NumberTitle', 'off', 'Color', 'k', ...
                'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
            cleaner = onCleanup(@() local_safeClose(fig)); %#ok<NASGU>

            imshow(img);
            ax = gca;
            util.drawGrid(ax, hIm, wIm, gridN, 'w', 2);
            title({ ...
                'Gambar POLYGON anchor di area background yang DIAM (kaya tekstur).', ...
                'Diambil dari gambar yang BELUM di-crop (stabilisasi dulu, crop kemudian).', ...
                'Klik titik-titik untuk membentuk polygon, double-click untuk konfirmasi.', ...
                'Tutup jendela tanpa konfirmasi untuk membatalkan.'}, ...
                'Color', 'y', 'FontSize', 12, 'FontWeight', 'bold');

            pts = [];
            try
                hPoly = util.safeDrawPolygon([], 'y', 'Anchor');
                wait(hPoly);
                if isvalid(hPoly) && size(hPoly.Position, 1) >= 3
                    pts = hPoly.Position;
                end
            catch
                pts = [];
            end
        end

        % -------------------------------------------------------------
        function preset = fromPoints(pts, imgSize, method, img, name, sourcePath)
        %FROMPOINTS  Bangun struct preset dari titik polygon + gambar ref.
            if nargin < 5 || isempty(name);       name = 'anchor';   end
            if nargin < 6;                         sourcePath = '';   end
            if nargin < 3 || isempty(method);      method = 'surf';   end

            maxThumb = batchpivprep2.io.anchorPreset.MaxThumbDim;
            verNum   = batchpivprep2.io.anchorPreset.Version;

            anchorROI = [ ...
                min(pts(:,1)), ...
                min(pts(:,2)), ...
                max(pts(:,1)) - min(pts(:,1)), ...
                max(pts(:,2)) - min(pts(:,2))];

            % Thumbnail untuk preview (sisi terpanjang <= MaxThumbDim)
            scale = min(1, maxThumb / max(imgSize));
            if scale < 1
                thumb = imresize(img, scale);
            else
                thumb = img;
                scale = 1;
            end

            preset = struct( ...
                'version',     verNum, ...
                'name',        char(name), ...
                'anchorPts',   pts, ...
                'anchorROI',   anchorROI, ...
                'imgSize',     double(imgSize), ...   % [H W]
                'method',      lower(method), ...
                'thumb',       thumb, ...
                'thumbScale',  scale, ...
                'sourceImage', char(sourcePath), ...
                'createdAt',   char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
                'note',        '');
        end

        % -------------------------------------------------------------
        function savePreset(preset, outPath)
        %SAVEPRESET  Simpan preset ke berkas .mat (variabel bernama 'preset').
            if isempty(preset)
                error('batchpivprep2:anchorPreset:empty', ...
                    'Tidak ada anchor untuk disimpan.');
            end
            save(outPath, 'preset');
        end

        % -------------------------------------------------------------
        function preset = loadPreset(inPath)
        %LOADPRESET  Muat preset dari berkas .mat. Validasi field minimum.
            S = load(inPath);
            if isfield(S, 'preset')
                preset = S.preset;
            elseif isfield(S, 'anchorPts') || isfield(S, 'anchorROI')
                preset = S;   % berkas lama tanpa pembungkus 'preset'
            else
                error('batchpivprep2:anchorPreset:badFile', ...
                    'Berkas tidak berisi preset anchor yang valid: %s', inPath);
            end
            preset = batchpivprep2.io.anchorPreset.normalize(preset, inPath);
        end

        % -------------------------------------------------------------
        function preset = normalize(preset, srcPath)
        %NORMALIZE  Lengkapi field yang hilang agar kompatibel.
            if nargin < 2; srcPath = ''; end
            if ~isfield(preset, 'anchorPts') || isempty(preset.anchorPts)
                error('batchpivprep2:anchorPreset:noPts', ...
                    'Preset tidak memiliki anchorPts (apakah ini preset CROP?).');
            end
            pts = preset.anchorPts;
            if ~isfield(preset, 'anchorROI') || isempty(preset.anchorROI)
                preset.anchorROI = [ ...
                    min(pts(:,1)), min(pts(:,2)), ...
                    max(pts(:,1)) - min(pts(:,1)), ...
                    max(pts(:,2)) - min(pts(:,2))];
            end
            if ~isfield(preset, 'imgSize') || isempty(preset.imgSize)
                % Tidak diketahui: asumsikan bounding-box terisi penuh.
                preset.imgSize = [ceil(max(pts(:,2))), ceil(max(pts(:,1)))];
            end
            if ~isfield(preset, 'method') || isempty(preset.method)
                preset.method = 'surf';
            end
            if ~isfield(preset, 'name') || isempty(preset.name)
                [~, nm] = fileparts(srcPath);
                if isempty(nm); nm = 'anchor'; end
                preset.name = nm;
            end
            if ~isfield(preset, 'thumb');      preset.thumb = [];      end
            if ~isfield(preset, 'thumbScale') || isempty(preset.thumbScale)
                preset.thumbScale = 1;
            end
            if ~isfield(preset, 'version'); preset.version = 1; end
        end

        % -------------------------------------------------------------
        function p2 = scaleTo(preset, newImgSize)
        %SCALETO  Skalakan koordinat anchor ke ukuran gambar baru.
        %   newImgSize = [H W]. Berguna saat data baru beda resolusi.
        %   Jika ukuran sama (toleransi 1 px), preset dikembalikan apa
        %   adanya. Penskalaan independen sumbu X dan Y.
            p2 = preset;
            old = preset.imgSize;            % [H W]
            new = double(newImgSize);        % [H W]
            if isempty(old) || numel(old) < 2
                return;
            end
            if all(abs(new - old) <= 1)
                return;   % praktis identik
            end
            sx = new(2) / old(2);            % skala lebar
            sy = new(1) / old(1);            % skala tinggi
            pts = preset.anchorPts;
            pts(:,1) = pts(:,1) * sx;
            pts(:,2) = pts(:,2) * sy;
            p2.anchorPts = pts;
            p2.anchorROI = [ ...
                preset.anchorROI(1) * sx, ...
                preset.anchorROI(2) * sy, ...
                preset.anchorROI(3) * sx, ...
                preset.anchorROI(4) * sy];
            p2.imgSize = new;
        end

        % -------------------------------------------------------------
        function [p2, info] = fitToImage(preset, newImgSize, margin)
        %FITTOIMAGE  Sesuaikan anchor agar MUAT di frame target dengan
        %   mempertahankan POSISI PIKSEL identik (untuk data yang berbeda
        %   FOV/cropping, bukan sekadar berbeda resolusi).
        %
        %   newImgSize = [H W]. margin (opsional) = jarak aman titik polygon
        %   dari tepi frame (px). Bila tak diberikan, dipakai margin default
        %   PROPORSIONAL ukuran gambar (lihat properti FitMargin*) agar bulatan
        %   handle ROI tetap bisa diraih saat diedit, termasuk pada gambar
        %   besar yang ditampilkan kecil.
        %
        %   Strategi (berurutan, hanya bila perlu):
        %     1. POSISI IDENTIK  — koordinat piksel anchor dipakai apa adanya.
        %     2. PERKECIL         — bila anchor lebih besar dari frame (minus
        %        margin), skala turun uniform (di sekitar pusatnya) sampai muat.
        %     3. GESER            — translasi minimal agar bounding-box masuk
        %        sepenuhnya, menjaga jarak >= margin dari tepi. Bentuk tetap.
        %
        %   OUTPUT:
        %       p2    preset dengan anchorPts/anchorROI/imgSize tersesuaikan.
        %       info  struct .status ('ok'|'shifted'|'shrunk'|'shifted+shrunk'),
        %             .shift [dx dy] (px), .scale (faktor perkecil; 1 = utuh),
        %             .margin (px jarak aman yang dipakai).
            p2   = preset;
            info = struct('status', 'ok', 'shift', [0 0], 'scale', 1, 'margin', 0);

            new = double(newImgSize);
            if numel(new) < 2 || isempty(preset.anchorPts)
                return;
            end
            H = new(1); W = new(2);

            % Margin default proporsional (clamp ke [Min, Max]). Akses
            % konstanta via nama kelas penuh = baca nilai, tanpa membuat instance.
            if nargin < 3 || isempty(margin)
                m      = round(batchpivprep2.io.anchorPreset.FitMarginFrac * max(H, W));
                margin = min(batchpivprep2.io.anchorPreset.FitMarginMax, ...
                             max(batchpivprep2.io.anchorPreset.FitMarginMin, m));
            end
            % Jangan biarkan margin menelan seluruh frame.
            margin = max(0, min(margin, floor((min(H, W) - 1) / 2)));
            info.margin = margin;

            pts = preset.anchorPts;

            % --- (2) Perkecil bila anchor lebih besar dari frame ---
            availW = max(1, W - 2*margin);
            availH = max(1, H - 2*margin);
            bw = max(pts(:,1)) - min(pts(:,1));
            bh = max(pts(:,2)) - min(pts(:,2));
            sc = 1;
            if bw > availW || bh > availH
                sc = min([availW / max(bw, eps), availH / max(bh, eps), 1]);
                cx = (max(pts(:,1)) + min(pts(:,1))) / 2;
                cy = (max(pts(:,2)) + min(pts(:,2))) / 2;
                pts(:,1) = (pts(:,1) - cx) * sc + cx;
                pts(:,2) = (pts(:,2) - cy) * sc + cy;
                info.scale = sc;
            end

            % --- (3) Geser minimal agar bounding-box masuk frame ---
            loX = 1 + margin; hiX = W - margin;
            loY = 1 + margin; hiY = H - margin;
            dx = 0; dy = 0;
            minx = min(pts(:,1)); maxx = max(pts(:,1));
            miny = min(pts(:,2)); maxy = max(pts(:,2));
            if     minx < loX; dx = loX - minx;
            elseif maxx > hiX; dx = hiX - maxx;
            end
            if     miny < loY; dy = loY - miny;
            elseif maxy > hiY; dy = hiY - maxy;
            end
            pts(:,1) = pts(:,1) + dx;
            pts(:,2) = pts(:,2) + dy;
            info.shift = [dx dy];

            % --- Status ringkas ---
            moved  = abs(dx) > 0.5 || abs(dy) > 0.5;
            shrunk = sc < 0.999;
            if      moved && shrunk; info.status = 'shifted+shrunk';
            elseif  shrunk;          info.status = 'shrunk';
            elseif  moved;           info.status = 'shifted';
            else;                    info.status = 'ok';
            end

            % --- Tulis kembali ke preset ---
            p2.anchorPts = pts;
            p2.anchorROI = [ ...
                min(pts(:,1)), min(pts(:,2)), ...
                max(pts(:,1)) - min(pts(:,1)), ...
                max(pts(:,2)) - min(pts(:,2))];
            p2.imgSize = [H W];
        end

        % -------------------------------------------------------------
        function displayInAxes(preset, ax)
        %DISPLAYINAXES  Tampilkan thumbnail + polygon anchor di axes.
        %   Inilah "container" untuk MENAMPILKAN hasil seleksi objek.
            cla(ax, 'reset');
            if isempty(preset)
                axis(ax, 'off');
                text(ax, 0.5, 0.5, '(belum ada anchor stabilisasi)', ...
                    'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                    'Color', [0.5 0.5 0.5], 'FontAngle', 'italic');
                return;
            end

            if ~isempty(preset.thumb)
                imshow(preset.thumb, 'Parent', ax);
                s = preset.thumbScale;
            else
                % Tanpa thumbnail: gambar di kanvas kosong seukuran imgSize.
                axis(ax, [1 max(preset.imgSize(2),2) 1 max(preset.imgSize(1),2)]);
                set(ax, 'YDir', 'reverse'); axis(ax, 'image');
                s = 1;
            end
            hold(ax, 'on');

            pts = preset.anchorPts * s;
            patch(ax, 'XData', pts(:,1), 'YData', pts(:,2), ...
                'FaceColor', 'y', 'FaceAlpha', 0.18, ...
                'EdgeColor', 'y', 'LineWidth', 1.6);
            plot(ax, [pts(:,1); pts(1,1)], [pts(:,2); pts(1,2)], ...
                'y-', 'LineWidth', 1.6);
            hold(ax, 'off');
            title(ax, sprintf('%s  (%dx%d px, %d titik)', ...
                preset.name, preset.imgSize(2), preset.imgSize(1), ...
                size(preset.anchorPts, 1)), ...
                'FontSize', 8, 'Interpreter', 'none');
        end

        % -------------------------------------------------------------
        function s = summaryText(preset)
        %SUMMARYTEXT  String multi-baris ringkasan preset (untuk GUI).
            if isempty(preset)
                s = 'Anchor stabilisasi aktif: (belum ada)';
                return;
            end
            roi = preset.anchorROI;
            s = sprintf([ ...
                'Anchor aktif : %s\n' ...
                'Ref. size    : %d x %d px (W x H)\n' ...
                'Titik polygon: %d   |   Metode: %s\n' ...
                'ROI [x y w h]: [%.0f %.0f %.0f %.0f]'], ...
                preset.name, preset.imgSize(2), preset.imgSize(1), ...
                size(preset.anchorPts, 1), upper(preset.method), ...
                roi(1), roi(2), roi(3), roi(4));
        end

    end
end


% =====================================================================
function local_safeClose(fig)
    try
        if ~isempty(fig) && ishandle(fig)
            close(fig);
        end
    catch
    end
end
