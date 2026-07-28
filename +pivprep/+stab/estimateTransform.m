function out = estimateTransform(movImg, ref, params)
%ESTIMATETRANSFORM  Estimasi transform stabilisasi untuk satu frame.
%
%   out = pivprep.stab.estimateTransform(movImg, ref, params)
%
%   INPUT:
%       movImg  gambar yang akan distabilkan
%       ref     struct hasil pivprep.stab.buildReference
%       params  struct opsi:
%           .roiPad         padding ROI (px),                 default 50
%           .jitterTol      ambang jitter (px) yang diterima, default 20
%           .maxRatio       MaxRatio matchFeatures SURF,      default 0.6
%           .minMatchPts    jumlah match minimum,             default 4
%           .lastGoodTform  tform terakhir yang diterima
%                           (untuk fallback dan basis jitter)
%
%   OUTPUT:
%       out struct:
%           .tform      tform yang akan dipakai (baru atau fallback)
%           .nMatch     jumlah match (SURF) atau 0 (phasecorr)
%           .jitter     jitter terestimasi (px, magnitude / non-negatif)
%           .dx         pergeseran horizontal SIGNED (px) relatif ke
%                       last-good. Positif = bergeser ke kanan.
%                       0 jika estimasi gagal sebelum sempat dihitung.
%           .dy         pergeseran vertikal SIGNED (px) relatif ke
%                       last-good. Positif = bergeser ke bawah.
%                       0 jika estimasi gagal sebelum sempat dihitung.
%           .status     'OK' | 'REJECT (alasan)' | dst.
%           .accepted   logical, true jika estimasi diterima

    util = pivprep.util.utilities;

    if nargin < 3 || isempty(params); params = struct(); end
    p = struct( ...
        'roiPad',         50, ...
        'jitterTol',      20, ...
        'maxRatio',       0.6, ...
        'minMatchPts',    4,   ...
        'lastGoodTform',  util.identityTform());
    fn = fieldnames(p);
    for k = 1:numel(fn)
        if isfield(params, fn{k}) && ~isempty(params.(fn{k}))
            p.(fn{k}) = params.(fn{k});
        end
    end

    out = struct( ...
        'tform',    p.lastGoodTform, ...
        'nMatch',   0, ...
        'jitter',   0, ...
        'dx',       0, ...
        'dy',       0, ...
        'status',   'Pos. Terakhir', ...
        'accepted', false);

    grayMov = util.toGray(movImg);
    [mH, mW] = size(grayMov);

    roi = util.clampROI( ...
        ref.anchorROI + [-p.roiPad, -p.roiPad, 2*p.roiPad, 2*p.roiPad], ...
        mW, mH);

    if roi(3) <= 1 || roi(4) <= 1
        out.status = 'REJECT (ROI invalid)';
        return;
    end

    prevTrans = util.tformTranslation(p.lastGoodTform);

    switch ref.method

        case 'surf'
            ptsMov = detectSURFFeatures(grayMov, 'ROI', roi);
            [featMov, vMov] = extractFeatures(grayMov, ptsMov);
            pairs = matchFeatures(ref.features, featMov, ...
                'Unique', true, 'MaxRatio', p.maxRatio);
            out.nMatch = size(pairs, 1);

            if out.nMatch < p.minMatchPts
                out.status = sprintf('REJECT (match=%d)', out.nMatch);
                return;
            end

            mRef = ref.points(pairs(:, 1));
            mMov = vMov(pairs(:, 2));
            try
                estT     = estimateGeometricTransform2D(mMov, mRef, 'rigid');
                newTrans = util.tformTranslation(estT);
                out.dx     = newTrans(1) - prevTrans(1);
                out.dy     = newTrans(2) - prevTrans(2);
                out.jitter = hypot(out.dx, out.dy);
                if out.jitter <= p.jitterTol
                    out.tform    = estT;
                    out.status   = 'OK';
                    out.accepted = true;
                else
                    out.status = sprintf('REJECT (jitter=%.1fpx)', out.jitter);
                end
            catch ME
                out.status = sprintf('REJECT (%s)', ME.message);
            end

        case 'phasecorr'
            x1 = max(1, round(ref.patchOrigin(1)));
            y1 = max(1, round(ref.patchOrigin(2)));
            x2 = min(mW, x1 + size(ref.patch, 2) - 1);
            y2 = min(mH, y1 + size(ref.patch, 1) - 1);
            patch = grayMov(y1:y2, x1:x2);

            if any(size(patch) ~= size(ref.patch))
                patch = imresize(patch, size(ref.patch));
            end

            try
                estT     = imregcorr(patch, ref.patch, 'translation');
                newTrans = util.tformTranslation(estT);
                out.dx     = newTrans(1) - prevTrans(1);
                out.dy     = newTrans(2) - prevTrans(2);
                out.jitter = hypot(out.dx, out.dy);
                if out.jitter <= p.jitterTol
                    out.tform    = estT;
                    out.status   = 'OK';
                    out.accepted = true;
                else
                    out.status = sprintf('REJECT (jitter=%.1fpx)', out.jitter);
                end
            catch ME
                out.status = sprintf('REJECT (%s)', ME.message);
            end

        otherwise
            out.status = sprintf('REJECT (metode %s)', ref.method);
    end
end
