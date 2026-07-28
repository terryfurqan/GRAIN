function out = processBGImage(bg, h)
%PROCESSBGIMAGE  Pipeline pemrosesan citra latar -> RGB truecolor.
%   Port dari i_processBGImage (PIV_Viewer.m baris 1804-1885).
%
%   Tahapan: grayscale toggle -> normalisasi -> CLAHE opsional ->
%   brightness/contrast -> konversi akhir ke RGB.

    out = bg;

    % 1. Grayscale toggle
    isGray = (get(h.chkGrayBG,'Value') == 1);
    if isGray
        if size(out,3) == 3
            try
                out = rgb2gray(out);
            catch
                out = uint8(mean(double(out),3));
            end
        end
    end

    % Normalisasi ke double [0,1]
    outD = double(out);
    if isa(out,'uint8')
        outD = outD / 255;
    elseif isa(out,'uint16')
        outD = outD / 65535;
    elseif islogical(out)
        outD = double(out);
    else
        mx = max(outD(:));
        if mx > 1.5
            if mx <= 255, outD = outD/255;
            elseif mx <= 65535, outD = outD/65535;
            else, outD = outD / mx;
            end
        end
    end
    outD = max(0, min(1, outD));

    % 2. CLAHE
    if get(h.chkCLAHE,'Value') == 1
        clip = get(h.sldClip,'Value');
        try
            if size(outD,3) == 1
                outD = adapthisteq(outD, 'ClipLimit', clip, 'NumTiles',[8 8]);
            else
                tmp = outD;
                for c = 1:size(outD,3)
                    tmp(:,:,c) = adapthisteq(outD(:,:,c), ...
                        'ClipLimit', clip, 'NumTiles',[8 8]);
                end
                outD = tmp;
            end
        catch
            try
                if size(outD,3) == 1
                    outD = histeq(outD);
                end
            catch
            end
        end
    end

    % 3. Brightness & Contrast (sekitar 0.5)
    bVal = get(h.sldBright,'Value');
    cVal = get(h.sldContrast,'Value');
    if bVal ~= 0 || cVal ~= 1
        outD = (outD - 0.5) * cVal + 0.5 + bVal;
        outD = max(0, min(1, outD));
    end

    % 4. Konversi ke truecolor RGB
    if size(outD, 3) == 1
        out = repmat(outD, [1 1 3]);
    elseif size(outD, 3) == 3
        out = outD;
    else
        out = repmat(mean(outD,3), [1 1 3]);
    end
end
