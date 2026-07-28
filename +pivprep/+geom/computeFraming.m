function frame = computeFraming(pts, mode, refSize)
%COMPUTEFRAMING  Hitung transform framing dari titik-titik user.
%
%   frame = pivprep.geom.computeFraming(pts, mode, refSize)
%
%   INPUT:
%       pts     Nx2 titik (4 untuk 'square'; 4 untuk 'crop' juga)
%       mode    'square' atau 'crop'
%       refSize [H W] gambar referensi (untuk pembatasan crop)
%
%   OUTPUT:
%       frame struct:
%           .mode         sama dengan input
%           .tform        projective2d (mode 'square') atau [] (mode 'crop')
%           .refView      imref2d untuk output
%           .outSize      [H W] gambar keluaran (RECTANGULAR, aspect ratio
%                         dipertahankan dari pilihan user)
%           .cropRect     [x y w h] (mode 'crop' saja)
%           .aspectRatio  W / H output (untuk info)
%
%   CATATAN PENTING:
%   Mode 'square' BUKAN berarti hasil keluarannya berbentuk persegi
%   dengan sisi sama panjang. Yang dimaksud 'square' di sini adalah
%   sudut-sudut keluarannya 90 derajat (rectangular). Aspect ratio
%   dari polygon yang digambar user dipertahankan: lebar rata-rata
%   (sisi atas dan bawah) menjadi lebar output, tinggi rata-rata
%   (sisi kiri dan kanan) menjadi tinggi output.
%
%   Mode 'crop' juga menghasilkan rectangle, mengambil bounding box
%   dari titik-titik user dan mempertahankan aspect ratio bounding box
%   tersebut.

    frame = struct('mode', mode);

    switch lower(mode)

        case 'square'
            if size(pts, 1) ~= 4
                error('pivprep:computeFraming:points', ...
                    'Mode square memerlukan tepat 4 titik sudut.');
            end

            % Dimensi target: rata-rata sisi horizontal (top + bottom)
            % menjadi lebar, rata-rata sisi vertikal (left + right)
            % menjadi tinggi. Aspect ratio dijaga sesuai polygon user.
            avgW = round((norm(pts(1,:) - pts(2,:)) + ...
                          norm(pts(4,:) - pts(3,:))) / 2);
            avgH = round((norm(pts(1,:) - pts(4,:)) + ...
                          norm(pts(2,:) - pts(3,:))) / 2);

            % Pengaman batas bawah dimensi
            avgW = max(avgW, 4);
            avgH = max(avgH, 4);

            % Target rectangle (BUKAN square dengan sisi sama)
            targetPts = [1    1;       ...
                         avgW 1;       ...
                         avgW avgH;    ...
                         1    avgH];

            frame.tform       = fitgeotrans(pts, targetPts, 'projective');
            frame.refView     = imref2d([avgH, avgW]);
            frame.outSize     = [avgH, avgW];
            frame.cropRect    = [];
            frame.aspectRatio = avgW / avgH;

        case 'crop'
            if size(pts, 1) < 2
                error('pivprep:computeFraming:points', ...
                    'Mode crop memerlukan minimal 2 titik.');
            end

            % Bounding box rectangle (BUKAN dipaksa persegi)
            xMin = min(pts(:, 1));
            xMax = max(pts(:, 1));
            yMin = min(pts(:, 2));
            yMax = max(pts(:, 2));

            w = round(xMax - xMin);
            h = round(yMax - yMin);
            x1 = round(xMin);
            y1 = round(yMin);

            % Clamp koordinat ke dalam image
            if x1 < 1; x1 = 1; end
            if y1 < 1; y1 = 1; end
            if x1 + w - 1 > refSize(2)
                w = refSize(2) - x1 + 1;
            end
            if y1 + h - 1 > refSize(1)
                h = refSize(1) - y1 + 1;
            end

            % Pengaman batas bawah dimensi
            w = max(w, 4);
            h = max(h, 4);

            frame.cropRect    = [x1, y1, w - 1, h - 1];
            frame.tform       = [];
            frame.refView     = imref2d([h, w]);
            frame.outSize     = [h, w];
            frame.aspectRatio = w / h;

        otherwise
            error('pivprep:computeFraming:mode', ...
                'Mode tidak dikenali: %s', mode);
    end
end
