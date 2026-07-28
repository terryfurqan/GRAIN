function ref = buildReference(refImg, anchorROI, method)
%BUILDREFERENCE  Siapkan data referensi untuk stabilisasi.
%
%   ref = pivprep.stab.buildReference(refImg, anchorROI, method)
%
%   INPUT:
%       refImg      gambar referensi (biasanya frame pertama)
%       anchorROI   [x y w h] bounding box area anchor (background diam)
%       method      'surf' | 'phasecorr'    (default 'surf')
%
%   OUTPUT:
%       ref struct dengan field:
%           .method      metode yang dipakai
%           .anchorROI   bounding box anchor
%           .imgSize     [H W] gambar referensi
%
%       Khusus SURF:
%           .features    objek SURFFeatures
%           .points      titik valid
%           .nPoints     jumlah titik
%
%       Khusus phase correlation:
%           .patch        patch grayscale anchor
%           .patchOrigin  [x1 y1] origin patch di koordinat gambar

    if nargin < 3 || isempty(method)
        method = 'surf';
    end

    ref          = struct();
    ref.method   = lower(method);
    ref.imgSize  = size(refImg, [1 2]);
    ref.anchorROI = anchorROI;

    grayRef = pivprep.util.utilities.toGray(refImg);

    switch ref.method
        case 'surf'
            % Clamp ROI ke dalam batas gambar: detectSURFFeatures menolak
            % ROI yang melewati tepi (anchor di-reuse dari gambar lain bisa
            % keluar frame). Penyesuaian utama dilakukan di anchorPreset.
            roi = local_clampROI(anchorROI, size(grayRef));
            pts = detectSURFFeatures(grayRef, 'ROI', roi);
            [feat, vpts] = extractFeatures(grayRef, pts);
            ref.features = feat;
            ref.points   = vpts;
            ref.nPoints  = numel(vpts);
            if ref.nPoints == 0
                warning('pivprep:buildReference:noFeatures', ...
                    'Tidak ada fitur SURF terdeteksi pada anchor ROI.');
            end

        case 'phasecorr'
            x1 = max(1, round(anchorROI(1)));
            y1 = max(1, round(anchorROI(2)));
            x2 = min(size(grayRef, 2), round(anchorROI(1) + anchorROI(3)));
            y2 = min(size(grayRef, 1), round(anchorROI(2) + anchorROI(4)));
            ref.patch       = grayRef(y1:y2, x1:x2);
            ref.patchOrigin = [x1, y1];
            if any(size(ref.patch) < 32)
                warning('pivprep:buildReference:smallPatch', ...
                    'Patch anchor terlalu kecil; phase correlation mungkin kurang akurat.');
            end

        otherwise
            error('pivprep:buildReference:method', ...
                'Metode tidak dikenali: %s', method);
    end
end


% =====================================================================
function roi = local_clampROI(roi, sz)
%LOCAL_CLAMPROI  Pastikan ROI [x y w h] berada penuh di dalam gambar [H W].
%   Membulatkan ke piksel & menjamin lebar/tinggi >= 1 (ROI valid).
    H = sz(1); W = sz(2);
    x1 = max(1, round(roi(1)));
    y1 = max(1, round(roi(2)));
    x2 = min(W, round(roi(1) + roi(3)));
    y2 = min(H, round(roi(2) + roi(4)));
    w  = max(1, x2 - x1);
    h  = max(1, y2 - y1);
    if x1 + w > W; x1 = max(1, W - w); end
    if y1 + h > H; y1 = max(1, H - h); end
    roi = [x1, y1, w, h];
end
