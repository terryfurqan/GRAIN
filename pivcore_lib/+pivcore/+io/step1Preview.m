classdef step1Preview
%STEP1PREVIEW  Cache PRATINJAU bingkai-1 (citra acuan) seri Step-1, di level
%   folder kerja (root). Logika murni, TANPA GUI.
%
%   MASALAH yang dipecahkan: memuat bingkai-1 dari berkas PIVLAB v7.3 (ratusan
%   MB) tiap kali pindah eksperimen membuat browsing terasa berat. Modul ini
%   menyimpan citra acuan bingkai-1 (citra LATAR — dasar penarikan garis PSG)
%   yang sudah DI-DOWNSCALE (default 50%) ke SATU berkas cache di root, agar
%   pindah-tampilan antar-eksperimen INSTAN (cukup baca cache, tak menyentuh
%   berkas besar). Garis PSG bisa ditarik/digeser & disimpan murni dari cache
%   (extent grid + node spacing ikut tersimpan); berkas besar hanya dibuka saat
%   ganti tampilan ke velocity/shear atau saat collect/sampling.
%
%   Berkas cache:  <root>/_pivterry_step1_preview.mat   (var `step1Preview`)
%   Berawalan `_pivterry_` -> otomatis dilewati indexScanner.isProgressName,
%   jadi tak pernah disalah-anggap sebagai eksperimen. TERPISAH dari berkas
%   index progres (_pivterry_index_step1.mat) yang harus tetap kecil & instan.
%
%   STRUKTUR satu entri (struct array):
%     base        char    base name eksperimen
%     img         uint8   citra acuan RGB (HxWx3) ter-downscale
%     xExt        1x2     [min max] extent grid sumbu-x (koordinat data)
%     yExt        1x2     [min max] extent grid sumbu-y (koordinat data)
%     nodeSpacing double  jarak node grid (px) -> dasar dropdown spacing
%     gridSize    1x2     [baris kolom] grid vektor bingkai-1
%     hasBG       logical TRUE bila img dari citra latar; FALSE = fallback |V|
%     scale       double  faktor downscale (mis. 0.5)
%     savedAt     char    timestamp pembuatan
%
%   API:
%     f     = pivcore.io.step1Preview.previewFile(root)
%     tf    = pivcore.io.step1Preview.exists(root)
%     e     = pivcore.io.step1Preview.buildEntry(dataFile [, scale])
%     cache = pivcore.io.step1Preview.loadCache(root)
%     e     = pivcore.io.step1Preview.getEntry(root, base)        % [] bila tak ada
%     pivcore.io.step1Preview.saveEntry(root, base, entry)        % RMW
%     cache = pivcore.io.step1Preview.buildAll(root, list [, progressFcn])
%
%   Penempatan berkas: PIVTerry/core/+pivcore/+io/step1Preview.m

    methods (Static)

        % ================================================================
        function f = previewFile(root)
        %PREVIEWFILE  Path berkas cache pratinjau di dalam folder kerja.
            f = '';
            if isempty(root) || ~ischar(root), return; end
            f = fullfile(root, '_pivterry_step1_preview.mat');
        end


        % ================================================================
        function tf = exists(root)
        %EXISTS  TRUE bila berkas cache pratinjau untuk folder ini sudah ada.
            f = pivcore.io.step1Preview.previewFile(root);
            tf = ~isempty(f) && isfile(f);
        end


        % ================================================================
        function e = buildEntry(dataFile, scale)
        %BUILDENTRY  Bangun satu entri pratinjau dari BERKAS data: muat bingkai-1
        %   (partial-load v7.3 lewat step1Session.loadFrame1) lalu delegasi ke
        %   entryFromData. Lempar bila berkas tak terbaca.
            if nargin < 2, scale = 0.5; end
            if isempty(dataFile) || ~ischar(dataFile)
                e = pivcore.io.step1Preview.blankEntry(); return;
            end
            [~, base] = fileparts(dataFile);
            data1 = pivcore.io.step1Session.loadFrame1(dataFile);   % lempar bila gagal
            e = pivcore.io.step1Preview.entryFromData(data1, base, scale);
        end


        % ================================================================
        function e = entryFromData(data1, base, scale)
        %ENTRYFROMDATA  Bangun entri pratinjau dari struct `data` bingkai-1 yang
        %   SUDAH dimuat (tanpa baca-ulang berkas besar): ambil extent grid +
        %   node spacing + citra acuan (latar -> fallback |V|), normalisasi ke
        %   RGB uint8, downscale `scale`. Dipakai caching oportunistik di GUI
        %   saat data sudah di memori. blankEntry (img kosong) bila grid invalid.
            if nargin < 3 || isempty(scale) || ~isfinite(scale) || scale <= 0
                scale = 0.5;
            end
            e = pivcore.io.step1Preview.blankEntry();
            e.scale = scale;
            e.base  = char(base);
            if isempty(data1) || ~isstruct(data1), return; end

            x = pivcore.data.safeFrame(data1.x, 1);
            y = pivcore.data.safeFrame(data1.y, 1);
            if isempty(x) || isempty(y), return; end
            e.xExt     = [min(x(:)) max(x(:))];
            e.yExt     = [min(y(:)) max(y(:))];
            e.gridSize = [size(x,1) size(x,2)];

            d = pivcore.data.nodeSpacing(data1);
            if isfinite(d) && d > 0, e.nodeSpacing = round(d); end

            % Citra acuan: latar bingkai-1 bila ada, jika tidak fallback |V|.
            bg = [];
            if isfield(data1,'bg_images') && ~isempty(data1.bg_images)
                bg = data1.bg_images{1};
            end
            if ~isempty(bg) && (isnumeric(bg) || islogical(bg))
                img = pivcore.io.step1Preview.toRGB(bg);
                e.hasBG = true;
            else
                [Z, ~] = pivcore.data.resolveScalar(data1, 'velocity_magnitude', 1);
                img = pivcore.io.step1Preview.scalarToRGB(Z);
                e.hasBG = false;
            end
            e.img     = pivcore.io.step1Preview.resizeImg(img, scale);
            e.savedAt = char(datetime('now'));
            e = orderfields(e, pivcore.io.step1Preview.blankEntry());
        end


        % ================================================================
        function cache = loadCache(root)
        %LOADCACHE  Muat semua entri pratinjau dari folder kerja. Struct array
        %   kosong (1x0) bila tak ada / rusak / skema tak cocok.
            cache = pivcore.io.step1Preview.emptyArray();
            f = pivcore.io.step1Preview.previewFile(root);
            if isempty(f) || ~isfile(f), return; end
            try
                S = load(f, 'step1Preview');
            catch
                return;
            end
            if ~isfield(S,'step1Preview') || ~isstruct(S.step1Preview) ...
                    || ~isfield(S.step1Preview,'entries')
                return;
            end
            ent = S.step1Preview.entries;
            if ~isstruct(ent), return; end
            req = {'base','img','xExt','yExt','nodeSpacing','hasBG'};
            if ~isempty(ent) && ~all(isfield(ent, req)), return; end
            cache = ent;
        end


        % ================================================================
        function e = getEntry(root, base)
        %GETENTRY  Ambil satu entri pratinjau berdasarkan base name. [] bila
        %   tak ada di cache.
            e = [];
            if isempty(base), return; end
            cache = pivcore.io.step1Preview.loadCache(root);
            if isempty(cache), return; end
            j = find(strcmpi({cache.base}, base), 1);
            if ~isempty(j), e = cache(j); end
        end


        % ================================================================
        function saveEntry(root, base, entry)
        %SAVEENTRY  Sisip/ganti satu entri pratinjau di cache (read-modify-
        %   write). Dipakai caching oportunistik saat eksperimen di-load penuh.
            if isempty(entry) || ~isstruct(entry), return; end
            entry.base = char(base);
            cache = pivcore.io.step1Preview.loadCache(root);
            cache = pivcore.io.step1Preview.updateEntry(cache, entry);
            pivcore.io.step1Preview.saveCache(root, cache);
        end


        % ================================================================
        function cache = buildAll(root, list, progressFcn)
        %BUILDALL  Bangun pratinjau untuk SEMUA eksperimen di `list` (struct
        %   array berfield dataFile, mis. dari step1Index) lalu simpan SEKALI.
        %   Eksperimen yang gagal dibangun dilewati (non-fatal). progressFcn(i,n)
        %   opsional dipanggil tiap eksperimen.
            if nargin < 3, progressFcn = []; end
            cache = pivcore.io.step1Preview.emptyArray();
            if isempty(list), return; end
            n = numel(list);
            for i = 1:n
                df = '';
                if isfield(list(i),'dataFile'), df = list(i).dataFile; end
                try
                    e = pivcore.io.step1Preview.buildEntry(df, 0.5);
                    if ~isempty(e.base)
                        cache = pivcore.io.step1Preview.updateEntry(cache, e);
                    end
                catch
                    % berkas korup / tak terbaca -> lewati
                end
                if ~isempty(progressFcn), try, progressFcn(i, n); catch, end, end %#ok<NOSEM,CTCH>
            end
            try
                pivcore.io.step1Preview.saveCache(root, cache);
            catch
                % folder read-only: lanjut tanpa menyimpan (non-fatal)
            end
        end


        % ================================================================
        function saveCache(root, cache)
        %SAVECACHE  Tulis seluruh cache ke <root>/_pivterry_step1_preview.mat.
            f = pivcore.io.step1Preview.previewFile(root);
            if isempty(f) || ~isfolder(root)
                error('pivcore:step1Preview:badRoot', ...
                    'Folder kerja tidak valid: %s', root);
            end
            S = struct('step1Preview', ...
                pivcore.io.step1Preview.toStruct(cache, root)); %#ok<NASGU>
            save(f, '-struct', 'S', '-v7');     % -v7 kompres citra uint8
        end


        % ================================================================
        function cache = updateEntry(cache, e)
        %UPDATEENTRY  Sisip/ganti entri `e` dicocokkan berdasarkan base.
            if isempty(e) || ~isstruct(e) || ~isfield(e,'base'), return; end
            e = orderfields(e, pivcore.io.step1Preview.blankEntry());
            if isempty(cache), cache = e; return; end
            j = find(strcmpi({cache.base}, e.base), 1);
            if isempty(j)
                cache(end+1) = e;
            else
                cache(j) = e;
            end
        end


        % ================================================================
        function S = toStruct(cache, root)
        %TOSTRUCT  Bangun struct cache self-describing untuk disimpan.
            S = struct();
            S.formatName    = 'PIVTerry Step1 Preview';
            S.formatVersion = 1;
            S.rootDir       = char(root);
            S.savedAt       = char(datetime('now'));
            S.scale         = 0.5;
            S.entries       = cache;
        end


        % ================================================================
        function e = blankEntry()
        %BLANKENTRY  Satu entri (1x1) berformat standar, nilai default.
            e = struct('base','', 'img',uint8([]), ...
                       'xExt',[NaN NaN], 'yExt',[NaN NaN], ...
                       'nodeSpacing',NaN, 'gridSize',[0 0], ...
                       'hasBG',false, 'scale',0.5, 'savedAt','');
        end


        % ================================================================
        function e = emptyArray()
        %EMPTYARRAY  Struct array 1x0 berformat sama (untuk akumulasi).
            e = pivcore.io.step1Preview.blankEntry();
            e(1) = [];
        end


        % ================================================================
        function rgb = toRGB(img)
        %TORGB  Normalisasi citra (grayscale/RGB, uint8/double/logical) ke RGB
        %   uint8 HxWx3 agar tampil benar TANPA bergantung colormap axes.
        %   Grayscale uint8 dipertahankan apa adanya (hanya direplikasi 3 kanal);
        %   tipe lain dipetakan ke [0 255] via rentang min-maks.
            if islogical(img), img = uint8(img) * 255; end
            if ~isa(img, 'uint8')
                v = double(img);
                mn = min(v(:)); mx = max(v(:));
                if isfinite(mn) && isfinite(mx) && mx > mn
                    img = uint8(255 * (v - mn) / (mx - mn));
                else
                    img = uint8(zeros(size(v)));
                end
            end
            if ndims(img) == 3 && size(img,3) == 3
                rgb = img;
            elseif ndims(img) == 3 && size(img,3) >= 1
                rgb = repmat(img(:,:,1), 1, 1, 3);   % ambil kanal pertama
            else
                rgb = repmat(img, 1, 1, 3);          % grayscale -> 3 kanal
            end
        end


        % ================================================================
        function rgb = scalarToRGB(Z)
        %SCALARTORGB  Petakan bidang skalar (mis. |V|) ke RGB uint8 via turbo,
        %   CLim robust [0, ~p98] (sama semangat dgn render axMain). Dipakai
        %   sbg fallback bila eksperimen tak punya citra latar.
            if isempty(Z) || ~isnumeric(Z)
                rgb = uint8(zeros(2, 2, 3)); return;
            end
            if ~any(isfinite(Z(:)))
                rgb = uint8(zeros(size(Z,1), size(Z,2), 3)); return;
            end
            c = pivcore.util.robustCLim(Z); lo = c(1); hi = c(2);
            Zc = max(lo, min(hi, Z));
            Zc(~isfinite(Z)) = lo;
            idx  = round(1 + 255 * (Zc - lo) / (hi - lo));   % 1..256
            idx  = max(1, min(256, idx));
            cmap = pivcore.util.turboFallback(256);
            rgb  = uint8(255 * ind2rgb(idx, cmap));
        end


        % ================================================================
        function out = resizeImg(img, scale)
        %RESIZEIMG  Downscale citra dgn imresize (IPT); fallback subsample bila
        %   imresize tak tersedia. scale>=1 / kosong -> apa adanya.
            out = img;
            if isempty(img) || scale >= 1, return; end
            try
                out = imresize(img, scale);
            catch
                r = max(1, round(1 / scale));
                out = img(1:r:end, 1:r:end, :);
            end
            out = uint8(out);
        end

    end
end
