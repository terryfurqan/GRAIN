classdef grainAxCal
%GRAINAXCAL  Model KALIBRASI SUMBU cm untuk AX main — sidecar `<base>_axcal.json`
%   di folder yang sama dgn MAT PIV. Menyimpan pemetaan PIXEL -> cm untuk sumbu
%   spasial gambar AX main (velmag/shear), supaya ekspor tampil:
%     X = "Cummulative Shortening (cm)" (tick 0,5,10,...,30)
%     Y = "Height (cm)"                 (tick 0,4,8)
%   + segitiga merah posisi indenter di sumbu-X bawah (bergeser ikut frame).
%
%   KONSEP: kalibrasi LINEAR 2-TITIK per sumbu (robust walau PIVlab calxy=1 /
%   belum terkalibrasi). Untuk tiap sumbu, user tetapkan 2 pasang (pixel, cm);
%   pemetaan cm = p1Cm + (px-p1Px)/(p2Px-p1Px)*(p2Cm-p1Cm) dan inversnya.
%
%   Segitiga indenter: mode 'shortening' -> posisi cm bingkai-k =
%     (k-1)/(nF-1) * dxCm  (dxCm = |X0_cm-X1_cm| dari experiment_geometry, dibaca
%   terpisah oleh pemanggil via frameCatalog.readGeom). mode 'fixed' -> posisi
%   tetap `fixedCm` (tak ikut frame; disediakan utk masa depan).
%
%   NON-DESTRUKTIF: MAT PIV biner & sidecar lain (_potdata/_faults) TIDAK
%   disentuh. `_axcal.json` OPSIONAL — bila absen/`enabled=false`, renderer
%   memakai tick PIXEL lama (tanpa regresi).
%
%   Penulisan WAJIB ATOMIC (tmp -> movefile). NaN <-> JSON null.
%
%   API:
%     p    = pivcore.io.grainAxCal.dataPath(dataFile)
%     doc  = pivcore.io.grainAxCal.emptyDoc(dataFile)
%     doc  = pivcore.io.grainAxCal.read(dataFile)          % [] -> emptyDoc
%     pivcore.io.grainAxCal.write(dataFile, doc)           % ATOMIC
%     ok   = pivcore.io.grainAxCal.isValid(doc, axis)      % axis = 'x'|'y'
%     cm   = pivcore.io.grainAxCal.pxToCm(doc, axis, px)
%     px   = pivcore.io.grainAxCal.cmToPx(doc, axis, cm)
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivcore/+io/grainAxCal.m

    methods (Static)

        % ================================================================
        function p = dataPath(dataFile)
        %DATAPATH  <dir>/<base>_axcal.json untuk MAT PIV dataFile.
            p = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_axcal.json', base));
        end


        % ================================================================
        function doc = emptyDoc(dataFile)
        %EMPTYDOC  Kerangka dokumen kosong (disabled; kalibrasi belum di-set).
            [~, base, ext] = fileparts(char(dataFile));
            doc = struct();
            doc.formatName    = 'GRAIN AxCal';
            doc.formatVersion = 1;
            doc.source        = [base ext];
            doc.meta          = struct('basename', base);
            doc.enabled       = false;               % false -> renderer pakai tick pixel lama
            doc.x = pivcore.io.grainAxCal.axisStruct( ...
                [0 5 10 15 20 25 30], 'Cummulative Shortening (cm)');
            doc.y = pivcore.io.grainAxCal.axisStruct( ...
                [0 4 8], 'Height (cm)');
            doc.indenter = struct( ...
                'show',    true, ...
                'mode',    'shortening', ...   % 'shortening' (ikut frame via dxCm) | 'fixed'
                'fixedCm', NaN, ...            % dipakai bila mode='fixed'
                'color',   [1 0 0]);
        end


        % ================================================================
        function a = axisStruct(tickCm, label)
        %AXISSTRUCT  Kerangka satu sumbu: 2-titik kalibrasi + tick + label.
            if nargin < 1, tickCm = []; end
            if nargin < 2, label  = ''; end
            a = struct();
            a.p1Px = NaN;  a.p1Cm = NaN;     % titik-1: pixel <-> cm
            a.p2Px = NaN;  a.p2Cm = NaN;     % titik-2: pixel <-> cm
            a.tickCm     = pivcore.io.grainAxCal.rowv(tickCm);
            a.label      = char(label);
            a.autoLimit  = true;             % true -> limit sumbu diset agar rentang tick terlihat
        end


        % ================================================================
        function doc = read(dataFile)
        %READ  Baca & NORMALISASI sidecar. Tak ada berkas -> emptyDoc. Rusak ->
        %   emptyDoc + warning (tak melempar agar GUI tetap jalan).
            p = pivcore.io.grainAxCal.dataPath(dataFile);
            if isempty(p) || ~isfile(p)
                doc = pivcore.io.grainAxCal.emptyDoc(dataFile); return;
            end
            try
                txt = fileread(p);
                raw = jsondecode(txt);
            catch ME
                warning('pivcore:grainAxCal:read', ...
                    'Gagal membaca/parse %s (%s); pakai dokumen kosong.', p, ME.message);
                doc = pivcore.io.grainAxCal.emptyDoc(dataFile); return;
            end
            doc = pivcore.io.grainAxCal.normalizeDoc(raw, dataFile);
        end


        % ================================================================
        function write(dataFile, doc)
        %WRITE  Tulis dokumen ke `<base>_axcal.json` secara ATOMIC.
            p = pivcore.io.grainAxCal.dataPath(dataFile);
            if isempty(p)
                error('pivcore:grainAxCal:noPath', ...
                    'Tak bisa menentukan path _axcal untuk: %s', dataFile);
            end
            doc = pivcore.io.grainAxCal.prepForEncode(doc);
            txt = jsonencode(doc, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0
                error('pivcore:grainAxCal:open', 'Tak bisa membuka %s utk tulis.', tmp);
            end
            cleaner = onCleanup(@() pivcore.io.grainAxCal.cleanupTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
            fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok
                error('pivcore:grainAxCal:move', ...
                    'Gagal memindah tmp->final (%s): %s', p, msg);
            end
        end


        % ================================================================
        function ok = isValid(doc, axis)
        %ISVALID  true bila sumbu `axis` ('x'|'y') punya 2 titik kalibrasi valid
        %   (semua finite & pixel berbeda -> pemetaan tak singular).
            ok = false;
            a = pivcore.io.grainAxCal.axisOf(doc, axis);
            if isempty(a), return; end
            v = [a.p1Px a.p1Cm a.p2Px a.p2Cm];
            if any(~isfinite(v)), return; end
            if abs(a.p2Px - a.p1Px) < eps, return; end
            ok = true;
        end


        % ================================================================
        function cm = pxToCm(doc, axis, px)
        %PXTOCM  Pixel -> cm (linear 2-titik). NaN bila kalibrasi tak valid.
            cm = NaN(size(px));
            if ~pivcore.io.grainAxCal.isValid(doc, axis), return; end
            a = pivcore.io.grainAxCal.axisOf(doc, axis);
            cm = a.p1Cm + (double(px) - a.p1Px) ./ (a.p2Px - a.p1Px) .* (a.p2Cm - a.p1Cm);
        end


        % ================================================================
        function px = cmToPx(doc, axis, cm)
        %CMTOPX  cm -> pixel (invers dari pxToCm). NaN bila kalibrasi tak valid.
            px = NaN(size(cm));
            if ~pivcore.io.grainAxCal.isValid(doc, axis), return; end
            a = pivcore.io.grainAxCal.axisOf(doc, axis);
            if abs(a.p2Cm - a.p1Cm) < eps, return; end   % cm degenerate -> tak bisa invers
            px = a.p1Px + (double(cm) - a.p1Cm) ./ (a.p2Cm - a.p1Cm) .* (a.p2Px - a.p1Px);
        end


        % ================================================================
        function a = axisOf(doc, axis)
        %AXISOF  Ambil struct sumbu 'x'/'y' dari doc (kosong bila tak ada).
            a = [];
            if ~isstruct(doc), return; end
            switch lower(char(axis))
                case 'x', if isfield(doc,'x'), a = doc.x; end
                case 'y', if isfield(doc,'y'), a = doc.y; end
            end
        end


        % ---------- normalisasi / encode -----------------------------
        function doc = normalizeDoc(raw, dataFile)
            d = pivcore.io.grainAxCal.emptyDoc(dataFile);
            if ~isstruct(raw), doc = d; return; end
            doc = d;
            for fn = {'formatName','formatVersion','source'}
                k = fn{1};
                if isfield(raw, k), doc.(k) = raw.(k); end
            end
            if isfield(raw,'meta') && isstruct(raw.meta) && isfield(raw.meta,'basename')
                doc.meta.basename = raw.meta.basename;
            end
            if isfield(raw,'enabled'), doc.enabled = logical(raw.enabled); end
            if isfield(raw,'x'), doc.x = pivcore.io.grainAxCal.normAxis(raw.x, d.x); end
            if isfield(raw,'y'), doc.y = pivcore.io.grainAxCal.normAxis(raw.y, d.y); end
            if isfield(raw,'indenter')
                doc.indenter = pivcore.io.grainAxCal.normIndenter(raw.indenter, d.indenter);
            end
        end


        function a = normAxis(s, def)
            a = def;
            if ~isstruct(s), return; end
            for fn = {'p1Px','p1Cm','p2Px','p2Cm'}
                k = fn{1};
                if isfield(s,k), a.(k) = pivcore.io.grainAxCal.scal(s.(k)); end
            end
            if isfield(s,'tickCm'),    a.tickCm    = pivcore.io.grainAxCal.rowv(s.tickCm); end
            if isfield(s,'label'),     a.label     = char(s.label); end
            if isfield(s,'autoLimit'), a.autoLimit = logical(s.autoLimit); end
        end


        function o = normIndenter(s, def)
            o = def;
            if ~isstruct(s), return; end
            if isfield(s,'show'),    o.show    = logical(s.show); end
            if isfield(s,'mode'),    o.mode    = char(s.mode); end
            if isfield(s,'fixedCm'), o.fixedCm = pivcore.io.grainAxCal.scal(s.fixedCm); end
            if isfield(s,'color') && isnumeric(s.color) && numel(s.color)==3
                o.color = double(s.color(:)).';
            end
        end


        function doc = prepForEncode(doc)
            d = pivcore.io.grainAxCal.emptyDoc('');
            fn = fieldnames(d);
            for i = 1:numel(fn)
                if ~isfield(doc, fn{i}), doc.(fn{i}) = d.(fn{i}); end
            end
        end


        % --- helper tipe (NaN<->JSON null) ---------------------------
        function v = rowv(x)
            if isempty(x), v = []; return; end
            v = double(x(:)).';
        end

        function v = scal(x)
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end

        function cleanupTmp(tmp)
            try, if isfile(tmp), delete(tmp); end, catch, end
        end

    end
end
