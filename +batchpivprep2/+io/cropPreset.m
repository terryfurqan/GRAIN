classdef cropPreset
%CROPPRESET  Pengelola ROI CROPPING yang bisa di-reuse (BatchPIVPrep v2).
%
%   Ini adalah TAMBAHAN versi 2 dibanding versi 1: setelah stabilisasi,
%   tiap frame di-CROP memakai ROI ini. ROI cropping bersifat REUSABLE
%   lintas folder/eksperimen, persis seperti anchor stabilisasi
%   (batchpivprep2.io.anchorPreset) -- TETAPI ROI cropping TIDAK SAMA
%   dengan ROI stabilisasi; keduanya disimpan & ditugaskan terpisah.
%
%   TIGA MODE CROPPING:
%     'none'   (Mode 0) TANPA crop: keluaran = frame penuh hasil stabilisasi
%              (tidak ada framing). Preset tak butuh ROI yang digambar.
%     'crop'   (Mode 1) Crop persegi-panjang apa adanya sesuai ROI kotak.
%              Backend: stabilisasi -> crop bounding-box.
%     'square' (Mode 2) Crop poligon 4-titik dgn NORMALISASI GEOMETRIS:
%              objek persegi (sudut 90 derajat) yang difoto miring/terdistorsi
%              "dipaksa" menjadi kotak ber-sudut 90 derajat (rectify projektif),
%              aspect ratio mengikuti polygon. Backend: stabilisasi -> squaring
%              (warp projektif) -> crop pada area persegi hasil squaring.
%
%   Kedua mode memakai pivprep.geom.computeFraming (modul +pivprep yang
%   dipakai ulang) sehingga matematika framing identik dengan PIVPrep.
%
%   STRUKTUR PRESET (struct):
%       .version     versi skema (=1)
%       .name        nama preset (string)
%       .cropMode    'crop' | 'square'
%       .framePts    4x2 titik sudut ROI, koordinat piksel gambar referensi.
%                    Urutan: kiri-atas, kanan-atas, kanan-bawah, kiri-bawah.
%                    Mode 'crop' -> 4 sudut kotak axis-aligned.
%                    Mode 'square' -> 4 sudut polygon (boleh terdistorsi).
%       .frameROI    [x y w h] bounding box framePts (informasi)
%       .imgSize     [H W] ukuran gambar referensi saat ROI dibuat
%       .thumb       thumbnail gambar referensi (untuk preview)
%       .thumbScale  skala thumb/asli
%       .sourceImage path gambar referensi sumber (informasi)
%       .createdAt   timestamp pembuatan
%       .note        catatan bebas
%
%   Semua method statik; dipanggil sbg batchpivprep2.io.cropPreset.<fn>.

    properties (Constant)
        MaxThumbDim = 800;
        Version     = 1;
        Color       = [0.10 0.85 0.95];   % cyan utk membedakan dari anchor (kuning)
    end

    methods (Static)

        % -------------------------------------------------------------
        function preset = createFromImage(imgPath, cropMode, gridN)
        %CREATEFROMIMAGE  Muat gambar, gambar ROI cropping interaktif,
        %   kembalikan struct preset. Mengembalikan [] bila dibatalkan.
            if nargin < 2 || isempty(cropMode); cropMode = 'crop'; end
            if nargin < 3 || isempty(gridN);    gridN    = 5;      end

            preset = [];
            if isempty(imgPath) || exist(imgPath, 'file') ~= 2
                return;
            end

            img = imread(imgPath);
            pts = batchpivprep2.io.cropPreset.drawROI(img, cropMode, gridN);
            if isempty(pts)
                return;   % dibatalkan / titik tidak valid
            end

            [~, nm] = fileparts(imgPath);
            preset = batchpivprep2.io.cropPreset.fromPoints( ...
                pts, size(img, [1 2]), cropMode, img, ...
                sprintf('crop-%s', nm), imgPath);
        end

        % -------------------------------------------------------------
        function preset = makeNone(name)
        %MAKENONE  Buat preset "tanpa crop" (Mode 0): keluaran = frame penuh.
        %   Tidak butuh gambar/ROI. framePts placeholder (unit box) hanya agar
        %   field skema lengkap; processFolder MELEWATI framing bila mode 'none'.
            if nargin < 1 || isempty(name); name = 'no-crop'; end
            pts = [1 1; 2 1; 2 2; 1 2];   % placeholder; tidak dipakai utk framing
            preset = struct( ...
                'version',     batchpivprep2.io.cropPreset.Version, ...
                'name',        char(name), ...
                'cropMode',    'none', ...
                'framePts',    pts, ...
                'frameROI',    [1 1 1 1], ...
                'imgSize',     [0 0], ...      % 0 = "ikuti frame sumber"
                'thumb',       [], ...
                'thumbScale',  1, ...
                'sourceImage', '', ...
                'createdAt',   char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
                'note',        'Tanpa crop (full frame).');
        end

        % -------------------------------------------------------------
        function pts = drawROI(img, cropMode, gridN)
        %DRAWROI  Tampilkan gambar + grid, minta user menggambar ROI
        %   cropping sesuai mode. Kembalikan 4x2 titik sudut (atau []).
        %     Mode 'crop'   -> rectangle resizable -> 4 sudut.
        %     Mode 'square' -> polygon 4 titik (klik 4 sudut berurutan).
            if nargin < 2 || isempty(cropMode); cropMode = 'crop'; end
            if nargin < 3 || isempty(gridN);    gridN    = 5;      end
            util = pivprep.util.utilities;
            cropMode = batchpivprep2.io.cropPreset.validMode(cropMode);

            [hIm, wIm, ~] = size(img);
            fig = figure( ...
                'Name', 'BatchPIVPrep2 - Gambar ROI CROPPING (gambar belum di-crop)', ...
                'NumberTitle', 'off', 'Color', 'k', ...
                'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
            cleaner = onCleanup(@() local_safeClose(fig)); %#ok<NASGU>

            imshow(img);
            ax = gca;
            util.drawGrid(ax, hIm, wIm, gridN, 'w', 2);
            col = batchpivprep2.io.cropPreset.Color;

            pts = [];
            if strcmpi(cropMode, 'square')
                title({ ...
                    'ROI CROPPING - MODE 2: POLYGON SQUARING (normalisasi geometris)', ...
                    'Klik 4 SUDUT objek persegi BERURUTAN: kiri-atas -> kanan-atas ->', ...
                    'kanan-bawah -> kiri-bawah, lalu double-click untuk konfirmasi.', ...
                    'Gambar akan dipaksa menjadi kotak ber-sudut 90 derajat (rectify).'}, ...
                    'Color', 'y', 'FontSize', 11, 'FontWeight', 'bold');
                try
                    % Posisi KOSONG ([]) -> mode MENGGAMBAR interaktif. ROI
                    % ber-'Position' default + wait() tidak bisa di-ambil di
                    % R2026a (bug "ga bisa ambil ROI").
                    hPoly = util.safeDrawPolygon([], col, 'Crop (squaring)');
                    wait(hPoly);
                    if isvalid(hPoly)
                        pts = batchpivprep2.io.cropPreset.coerceQuad(hPoly.Position);
                    end
                catch
                    pts = [];
                end
            else
                title({ ...
                    'ROI CROPPING - MODE 1: RECTANGLE CROP (apa adanya)', ...
                    'Klik-seret untuk menggambar kotak crop; tarik sisi/sudut', ...
                    'untuk resize, tarik bagian dalam untuk menggeser.', ...
                    'Double-click pada kotak untuk konfirmasi.'}, ...
                    'Color', 'y', 'FontSize', 11, 'FontWeight', 'bold');
                try
                    hRect = util.safeDrawRectangle([], col, 'Crop (rectangle)');
                    wait(hRect);
                    if isvalid(hRect)
                        pts = util.rectToCorners(hRect.Position);
                    end
                catch
                    pts = [];
                end
            end
        end

        % -------------------------------------------------------------
        function pts = coerceQuad(pts)
        %COERCEQUAD  Reduksi & urutkan polygon squaring menjadi TEPAT 4 sudut
        %   dalam urutan KANONIK kiri-atas, kanan-atas, kanan-bawah, kiri-bawah
        %   (TL, TR, BR, BL) -- urutan yang diasumsikan pivprep.geom.computeFraming.
        %
        %   <4 titik  -> [] (dibatalkan).
        %   >=4 titik -> 4 sudut EKSTREM dipilih & diurutkan via orderCorners.
        %   Ini robust terhadap (a) urutan klik yang tidak persis dan (b) vertex
        %   sisipan di tengah sisi (drawpolygon mengizinkan tambah titik saat
        %   diedit): titik non-sudut tidak pernah ekstrem sehingga otomatis
        %   terabaikan. Dengan begitu rectify projektif tidak pernah "diam-diam
        %   salah" hanya karena indeks titik teracak.
            if isempty(pts) || size(pts, 1) < 4
                warning('batchpivprep2:cropPreset:quad', ...
                    'Mode squaring memerlukan 4 sudut; titik kurang -> dibatalkan.');
                pts = [];
                return;
            end
            if size(pts, 1) > 4
                warning('batchpivprep2:cropPreset:quad', ...
                    ['Polygon %d titik; memilih 4 sudut EKSTREM (TL,TR,BR,BL) ' ...
                     'untuk squaring.'], size(pts, 1));
            end
            pts = batchpivprep2.io.cropPreset.orderCorners(pts);
        end

        % -------------------------------------------------------------
        function q = orderCorners(pts)
        %ORDERCORNERS  Pilih & urutkan 4 sudut menjadi TL, TR, BR, BL.
        %   Memakai jumlah dan selisih koordinat:
        %       TL = argmin(x+y),  BR = argmax(x+y),
        %       TR = argmin(y-x),  BL = argmax(y-x).
        %   Titik non-sudut (mis. sisipan di tengah sisi) tidak pernah ekstrem
        %   sehingga terabaikan. Untuk ROI yang DIGAMBAR BENAR (TL,TR,BR,BL),
        %   hasilnya identik dengan input (no-op). Cocok untuk distorsi
        %   perspektif sedang dengan objek yang relatif tegak; pada rotasi
        %   ekstrem (>~45 derajat) label sudut bisa ambigu.
            x = pts(:,1); y = pts(:,2);
            s = x + y;          % TL terkecil, BR terbesar
            d = y - x;          % TR terkecil, BL terbesar
            [~, iTL] = min(s);
            [~, iBR] = max(s);
            [~, iTR] = min(d);
            [~, iBL] = max(d);
            q = [pts(iTL,:); pts(iTR,:); pts(iBR,:); pts(iBL,:)];
        end

        % -------------------------------------------------------------
        function preset = fromPoints(pts, imgSize, cropMode, img, name, sourcePath)
        %FROMPOINTS  Bangun struct preset crop dari titik sudut + gambar ref.
            if nargin < 5 || isempty(name);      name = 'crop';     end
            if nargin < 6;                        sourcePath = '';   end
            if nargin < 3 || isempty(cropMode);   cropMode = 'crop'; end
            cropMode = batchpivprep2.io.cropPreset.validMode(cropMode);

            maxThumb = batchpivprep2.io.cropPreset.MaxThumbDim;
            verNum   = batchpivprep2.io.cropPreset.Version;

            frameROI = [ ...
                min(pts(:,1)), ...
                min(pts(:,2)), ...
                max(pts(:,1)) - min(pts(:,1)), ...
                max(pts(:,2)) - min(pts(:,2))];

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
                'cropMode',    cropMode, ...
                'framePts',    pts, ...
                'frameROI',    frameROI, ...
                'imgSize',     double(imgSize), ...   % [H W]
                'thumb',       thumb, ...
                'thumbScale',  scale, ...
                'sourceImage', char(sourcePath), ...
                'createdAt',   char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
                'note',        '');
        end

        % -------------------------------------------------------------
        function savePreset(preset, outPath)
        %SAVEPRESET  Simpan preset crop ke .mat (variabel bernama 'cropROI').
            if isempty(preset)
                error('batchpivprep2:cropPreset:empty', ...
                    'Tidak ada ROI cropping untuk disimpan.');
            end
            cropROI = preset; %#ok<NASGU>
            save(outPath, 'cropROI');
        end

        % -------------------------------------------------------------
        function preset = loadPreset(inPath)
        %LOADPRESET  Muat preset crop dari .mat. Validasi field minimum.
            S = load(inPath);
            if isfield(S, 'cropROI')
                preset = S.cropROI;
            elseif isfield(S, 'framePts') || isfield(S, 'frameROI')
                preset = S;                 % struct telanjang
            elseif isfield(S, 'preset') && isfield(S.preset, 'framePts')
                preset = S.preset;          % terbungkus 'preset'
            else
                error('batchpivprep2:cropPreset:badFile', ...
                    ['Berkas tidak berisi preset CROP yang valid (apakah ini ' ...
                     'preset ANCHOR?): %s'], inPath);
            end
            preset = batchpivprep2.io.cropPreset.normalize(preset, inPath);
        end

        % -------------------------------------------------------------
        function preset = normalize(preset, srcPath)
        %NORMALIZE  Lengkapi field yang hilang agar kompatibel.
            if nargin < 2; srcPath = ''; end
            if ~isfield(preset, 'cropMode') || isempty(preset.cropMode)
                preset.cropMode = 'crop';
            end
            preset.cropMode = batchpivprep2.io.cropPreset.validMode(preset.cropMode);
            % Mode 'none' tidak butuh ROI yang digambar: lengkapi placeholder.
            if strcmpi(preset.cropMode, 'none')
                if ~isfield(preset, 'framePts') || isempty(preset.framePts)
                    preset.framePts = [1 1; 2 1; 2 2; 1 2];
                end
                if ~isfield(preset, 'frameROI') || isempty(preset.frameROI)
                    preset.frameROI = [1 1 1 1];
                end
                if ~isfield(preset, 'imgSize') || isempty(preset.imgSize)
                    preset.imgSize = [0 0];
                end
                if ~isfield(preset, 'name') || isempty(preset.name)
                    preset.name = 'no-crop';
                end
                if ~isfield(preset, 'thumb');      preset.thumb = [];      end
                if ~isfield(preset, 'thumbScale') || isempty(preset.thumbScale)
                    preset.thumbScale = 1;
                end
                if ~isfield(preset, 'version'); preset.version = 1; end
                return;
            end
            if ~isfield(preset, 'framePts') || isempty(preset.framePts)
                error('batchpivprep2:cropPreset:noPts', ...
                    'Preset tidak memiliki framePts.');
            end
            pts = preset.framePts;
            if strcmpi(preset.cropMode, 'square')
                preset.framePts = batchpivprep2.io.cropPreset.coerceQuad(pts);
                pts = preset.framePts;
            end
            if ~isfield(preset, 'frameROI') || isempty(preset.frameROI)
                preset.frameROI = [ ...
                    min(pts(:,1)), min(pts(:,2)), ...
                    max(pts(:,1)) - min(pts(:,1)), ...
                    max(pts(:,2)) - min(pts(:,2))];
            end
            if ~isfield(preset, 'imgSize') || isempty(preset.imgSize)
                preset.imgSize = [ceil(max(pts(:,2))), ceil(max(pts(:,1)))];
            end
            if ~isfield(preset, 'name') || isempty(preset.name)
                [~, nm] = fileparts(srcPath);
                if isempty(nm); nm = 'crop'; end
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
        %SCALETO  Skalakan koordinat ROI cropping ke ukuran gambar baru.
        %   newImgSize = [H W]. Penskalaan independen sumbu X & Y.
            p2 = preset;
            old = preset.imgSize;
            new = double(newImgSize);
            if isempty(old) || numel(old) < 2
                return;
            end
            if all(abs(new - old) <= 1)
                return;
            end
            sx = new(2) / old(2);
            sy = new(1) / old(1);
            pts = preset.framePts;
            pts(:,1) = pts(:,1) * sx;
            pts(:,2) = pts(:,2) * sy;
            p2.framePts = pts;
            p2.frameROI = [ ...
                preset.frameROI(1) * sx, ...
                preset.frameROI(2) * sy, ...
                preset.frameROI(3) * sx, ...
                preset.frameROI(4) * sy];
            p2.imgSize = new;
        end

        % -------------------------------------------------------------
        function [p2, info] = fitToImage(preset, newImgSize, margin)
        %FITTOIMAGE  Sesuaikan ROI cropping agar MUAT di frame target dengan
        %   mempertahankan POSISI PIKSEL identik (untuk data berbeda FOV/ukuran).
        %
        %   newImgSize = [H W]. margin (opsional, px) = jarak aman titik dari
        %   tepi. DEFAULT 0 (crop persis apa adanya); margin > 0 hanya berefek
        %   bila ROI berada dalam <margin px dari tepi atau di luar frame.
        %
        %   Strategi (berurutan, hanya bila perlu): posisi identik -> perkecil
        %   bila lebih besar dari frame -> geser minimal agar masuk. Bentuk
        %   (aspect ratio polygon) dipertahankan.
            p2   = preset;
            info = struct('status', 'ok', 'shift', [0 0], 'scale', 1, 'margin', 0);

            new = double(newImgSize);
            % Mode 'none': tanpa crop -> keluaran = frame penuh, tak ada
            % penyesuaian ROI. Catat ukuran frame target untuk dokumentasi.
            if isfield(preset, 'cropMode') && strcmpi(preset.cropMode, 'none')
                if numel(new) >= 2; p2.imgSize = new; end
                return;
            end
            if numel(new) < 2 || isempty(preset.framePts)
                return;
            end
            H = new(1); W = new(2);

            if nargin < 3 || isempty(margin)
                margin = 0;     % crop default: persis apa adanya
            end
            margin = max(0, min(margin, floor((min(H, W) - 1) / 2)));
            info.margin = margin;

            pts = preset.framePts;

            % --- Perkecil bila ROI lebih besar dari frame ---
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

            % --- Geser minimal agar bounding-box masuk frame ---
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

            moved  = abs(dx) > 0.5 || abs(dy) > 0.5;
            shrunk = sc < 0.999;
            if      moved && shrunk; info.status = 'shifted+shrunk';
            elseif  shrunk;          info.status = 'shrunk';
            elseif  moved;           info.status = 'shifted';
            else;                    info.status = 'ok';
            end

            p2.framePts = pts;
            p2.frameROI = [ ...
                min(pts(:,1)), min(pts(:,2)), ...
                max(pts(:,1)) - min(pts(:,1)), ...
                max(pts(:,2)) - min(pts(:,2))];
            p2.imgSize = [H W];
        end

        % -------------------------------------------------------------
        function displayInAxes(preset, ax)
        %DISPLAYINAXES  Tampilkan thumbnail + ROI cropping di axes (cyan).
            cla(ax, 'reset');
            if isempty(preset)
                axis(ax, 'off');
                text(ax, 0.5, 0.5, '(belum ada ROI cropping)', ...
                    'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                    'Color', [0.5 0.5 0.5], 'FontAngle', 'italic');
                return;
            end
            if isfield(preset, 'cropMode') && strcmpi(preset.cropMode, 'none')
                axis(ax, 'off');
                text(ax, 0.5, 0.5, {'MODE 0 - TANPA CROP', '(keluaran = frame penuh)'}, ...
                    'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                    'Color', [0.20 0.45 0.55], 'FontWeight', 'bold');
                return;
            end

            if ~isempty(preset.thumb)
                imshow(preset.thumb, 'Parent', ax);
                s = preset.thumbScale;
            else
                axis(ax, [1 max(preset.imgSize(2),2) 1 max(preset.imgSize(1),2)]);
                set(ax, 'YDir', 'reverse'); axis(ax, 'image');
                s = 1;
            end
            hold(ax, 'on');

            col = batchpivprep2.io.cropPreset.Color;
            pts = preset.framePts * s;
            patch(ax, 'XData', pts(:,1), 'YData', pts(:,2), ...
                'FaceColor', col, 'FaceAlpha', 0.15, ...
                'EdgeColor', col, 'LineWidth', 1.6);
            plot(ax, [pts(:,1); pts(1,1)], [pts(:,2); pts(1,2)], ...
                '-', 'Color', col, 'LineWidth', 1.6);
            plot(ax, pts(:,1), pts(:,2), 'o', 'MarkerSize', 5, ...
                'MarkerFaceColor', col, 'MarkerEdgeColor', 'k');
            hold(ax, 'off');
            title(ax, sprintf('%s  [%s]  (%dx%d px)', preset.name, ...
                upper(preset.cropMode), preset.imgSize(2), preset.imgSize(1)), ...
                'FontSize', 8, 'Interpreter', 'none');
        end

        % -------------------------------------------------------------
        function s = summaryText(preset)
        %SUMMARYTEXT  String multi-baris ringkasan preset crop (untuk GUI).
            if isempty(preset)
                s = 'ROI cropping aktif: (belum ada)';
                return;
            end
            if isfield(preset, 'cropMode') && strcmpi(preset.cropMode, 'none')
                s = sprintf([ ...
                    'Crop ROI aktif : %s\n' ...
                    'Mode           : %s\n' ...
                    'Keluaran       : frame penuh hasil stabilisasi (tanpa crop)'], ...
                    preset.name, batchpivprep2.io.cropPreset.modeLabel('none'));
                return;
            end
            roi = preset.frameROI;
            s = sprintf([ ...
                'Crop ROI aktif : %s\n' ...
                'Mode           : %s\n' ...
                'Ref. size      : %d x %d px (W x H)\n' ...
                'Bounding [x y w h]: [%.0f %.0f %.0f %.0f]'], ...
                preset.name, ...
                batchpivprep2.io.cropPreset.modeLabel(preset.cropMode), ...
                preset.imgSize(2), preset.imgSize(1), ...
                roi(1), roi(2), roi(3), roi(4));
        end

        % -------------------------------------------------------------
        function lbl = modeLabel(cropMode)
        %MODELABEL  Label deskriptif mode crop (untuk GUI).
            switch lower(char(cropMode))
                case 'none'
                    lbl = 'Mode 0 - Tanpa crop (frame penuh)';
                case 'square'
                    lbl = 'Mode 2 - Polygon squaring (normalisasi 4-titik)';
                otherwise
                    lbl = 'Mode 1 - Rectangle crop (apa adanya)';
            end
        end

        % -------------------------------------------------------------
        function m = validMode(cropMode)
        %VALIDMODE  Normalkan string mode ke 'none' | 'crop' | 'square'.
            switch lower(char(cropMode))
                case {'none', 'nocrop', 'no-crop'}
                    m = 'none';
                case 'square'
                    m = 'square';
                otherwise
                    m = 'crop';
            end
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
