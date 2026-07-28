function rgb = normalizeToRGB(bg)
%NORMALIZETORGB  Normalisasi citra latar -> RGB double [0,1] (grayscale/RGB,
%   uint8/uint16/logical/double apa pun). Port verbatim dari step2 i_bgToRGB;
%   dipakai sbg overlay grayscale ber-alpha.
%
%   Catatan: processBGImage = KERNEL ini + CLAHE/brightness/contrast yang butuh
%   handle GUI. Yang ini murni (tanpa handle) sehingga aman dipanggil headless.
    rgb = [];
    if isempty(bg) || (~isnumeric(bg) && ~islogical(bg)), return; end
    d = double(bg);
    if isa(bg,'uint8'),   d = d / 255;
    elseif isa(bg,'uint16'), d = d / 65535;
    elseif islogical(bg), d = double(bg);
    else
        mx = max(d(:));
        if mx > 1.5
            if mx <= 255, d = d/255; elseif mx <= 65535, d = d/65535; else, d = d/mx; end
        end
    end
    d = max(0, min(1, d));
    if size(d,3) == 1
        rgb = repmat(d, [1 1 3]);
    elseif size(d,3) == 3
        rgb = d;
    else
        rgb = repmat(mean(d,3), [1 1 3]);
    end
end
