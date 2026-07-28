classdef utilities
%UTILITIES  Kumpulan helper statis untuk PIVPrep.
%
%   Dipanggil sebagai:
%       pivprep.util.utilities.toGray(img)
%       pivprep.util.utilities.clampROI(roi, W, H)
%
%   Semua method tidak menyimpan state; aman dipanggil bebas urutan.

    methods (Static)

        function g = toGray(img)
            %TOGRAY  Konversi ke grayscale; biarkan jika sudah grayscale.
            if size(img, 3) == 3
                g = rgb2gray(img);
            else
                g = img;
            end
        end

        function roi = clampROI(roi, imgW, imgH)
            %CLAMPROI  Pastikan ROI [x y w h] tidak keluar batas gambar.
            roi(1) = max(1, roi(1));
            roi(2) = max(1, roi(2));
            roi(3) = min(roi(3), imgW - roi(1));
            roi(4) = min(roi(4), imgH - roi(2));
        end

        function sortedNames = naturalSort(names)
            %NATURALSORT  Urutkan nama file berdasarkan angka di dalam nama.
            %   Jika nama tidak mengandung angka, item tetap tertahan di awal.
            if isempty(names); sortedNames = names; return; end
            nums = cellfun(@(f) str2double(regexp(f, '\d+', 'match', 'once')), names);
            nums(isnan(nums)) = 0;
            [~, idx] = sort(nums);
            sortedNames = names(idx);
        end

        function printHeader(step, label)
            %PRINTHEADER  Tulis header langkah ke konsol.
            fprintf('\n[%s] %s\n', step, upper(label));
            fprintf('  %s\n', repmat('-', 1, 60));
        end

        function ensureDir(p)
            %ENSUREDIR  Buat direktori jika belum ada.
            if ~isempty(p) && ~exist(p, 'dir')
                mkdir(p);
            end
        end

        function safeCloseWb(wb)
            %SAFECLOSEWB  Tutup waitbar tanpa error meskipun sudah ditutup user.
            try
                if ~isempty(wb) && ishandle(wb)
                    close(wb);
                end
            catch
            end
        end

        function drawGrid(ax, hIm, wIm, N, color, lw)
            %DRAWGRID  Gambar grid NxN di atas axes (non-destructive).
            if nargin < 4 || isempty(N);     N     = 5;    end
            if nargin < 5 || isempty(color); color = 'w';  end
            if nargin < 6 || isempty(lw);    lw    = 1.5;  end

            xStep = wIm / N;
            yStep = hIm / N;
            for i = 1:N-1
                line(ax, [i*xStep, i*xStep], [1, hIm], ...
                    'Color', color, 'LineWidth', lw, 'HitTest', 'off');
                line(ax, [1, wIm], [i*yStep, i*yStep], ...
                    'Color', color, 'LineWidth', lw, 'HitTest', 'off');
            end
        end

        function h = safeDrawPolygon(pts, color, label)
            %SAFEDRAWPOLYGON  Buat polygon ROI dengan fallback impoly.
            if exist('drawpolygon', 'file')
                if isempty(pts)
                    h = drawpolygon('Color', color, 'LineWidth', 2, 'Label', label);
                else
                    h = drawpolygon('Position', pts, 'Color', color, ...
                                    'LineWidth', 2, 'Label', label);
                end
            else
                if isempty(pts)
                    h = impoly;
                else
                    h = impoly(gca, pts);
                end
                if exist('setColor', 'file')
                    setColor(h, color);
                end
            end
        end

        function h = safeDrawRectangle(rect, color, label)
            %SAFEDRAWRECTANGLE  Buat rectangle ROI dengan fallback imrect.
            %   rect berupa [x y w h]. Pengguna cukup menarik sisi/sudut
            %   untuk me-resize sumbu X dan Y (bukan edit titik polygon).
            if exist('drawrectangle', 'file')
                if isempty(rect)
                    h = drawrectangle('Color', color, 'LineWidth', 2, 'Label', label);
                else
                    h = drawrectangle('Position', rect, 'Color', color, ...
                                      'LineWidth', 2, 'Label', label);
                end
            else
                if isempty(rect)
                    h = imrect;
                else
                    h = imrect(gca, rect);
                end
                if exist('setColor', 'file')
                    setColor(h, color);
                end
            end
        end

        function pts = rectToCorners(rect)
            %RECTTOCORNERS  Ubah [x y w h] menjadi 4 titik sudut (Nx2).
            %   Urutan: kiri-atas, kanan-atas, kanan-bawah, kiri-bawah.
            x = rect(1); y = rect(2); w = rect(3); hgt = rect(4);
            pts = [x,     y;       ...
                   x + w, y;       ...
                   x + w, y + hgt; ...
                   x,     y + hgt];
        end

        function out = flattenStruct(s, prefix)
            %FLATTENSTRUCT  Ratakan struct (rekursif) menjadi struct datar.
            %   Sub-struct skalar diratakan dgn awalan 'parent_child'.
            if nargin < 2; prefix = ''; end
            out = struct();
            if ~isstruct(s) || ~isscalar(s)
                return;
            end
            fn = fieldnames(s);
            for k = 1:numel(fn)
                key = fn{k};
                if isempty(prefix)
                    name = key;
                else
                    name = [prefix '_' key];
                end
                v = s.(key);
                if isstruct(v) && isscalar(v)
                    sub = pivprep.util.utilities.flattenStruct(v, name);
                    sfn = fieldnames(sub);
                    for j = 1:numel(sfn)
                        out.(sfn{j}) = sub.(sfn{j});
                    end
                else
                    out.(name) = v;
                end
            end
        end

        function str = valueToStr(v)
            %VALUETOSTR  Konversi sembarang nilai menjadi string scalar.
            if isstring(v) && isscalar(v)
                str = v;
            elseif ischar(v)
                str = string(v);
            elseif isnumeric(v) || islogical(v)
                if isscalar(v)
                    str = string(num2str(v));
                else
                    str = string(mat2str(reshape(v, 1, [])));
                end
            elseif iscell(v)
                parts = strings(1, numel(v));
                for c = 1:numel(v)
                    parts(c) = pivprep.util.utilities.valueToStr(v{c});
                end
                str = strjoin(parts, "; ");
            else
                try
                    str = string(class(v));
                catch
                    str = "<?>";
                end
            end
        end

        function str = secsToHMS(secs)
            %SECSTOHMS  Format detik ke HH:MM:SS.
            secs = max(0, secs);
            hh = floor(secs / 3600);
            mm = floor(mod(secs, 3600) / 60);
            ss = mod(secs, 60);
            str = sprintf('%02d:%02d:%02.0f', hh, mm, ss);
        end

        function t = tformTranslation(tform)
            %TFORMTRANSLATION  Ekstrak [dx dy] dari sembarang objek tform.
            %   Mendukung affine2d, affinetform2d, rigidtform2d, simtform2d.
            if isempty(tform)
                t = [0, 0]; return;
            end
            if isprop(tform, 'Translation')
                tr = tform.Translation;
                t  = [tr(1), tr(2)];
            elseif isprop(tform, 'A')
                A = tform.A;
                t = [A(1, end), A(2, end)];
            elseif isprop(tform, 'T')
                T = tform.T;
                t = [T(3, 1), T(3, 2)];
            else
                t = [0, 0];
            end
        end

        function t = identityTform()
            %IDENTITYTFORM  Transform identitas, kompatibel lintas versi MATLAB.
            try
                t = affinetform2d(eye(3));
            catch
                t = affine2d(eye(3));
            end
        end

    end
end
