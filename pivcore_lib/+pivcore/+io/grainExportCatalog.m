classdef grainExportCatalog
%GRAINEXPORTCATALOG  Tata-kelola KATALOG gambar AX main (GRAIN Exporter).
%
%   Engine MURNI/HEADLESS (tak ada figure / pivui). Mengelola struktur folder
%   katalog, manifest JSON per-eksperimen, penamaan berkas deterministik, dan
%   deteksi-BASI (fingerprint setelan render). GRAIN Exporter = SATU-SATUNYA
%   penulis folder katalog; manusia hanya MENG-KOPI keluar (jangan edit manual).
%
%   STRUKTUR FOLDER (di root GRAIN/, default):
%       PAB_export/
%         _catalog.json                 % indeks GLOBAL semua eksperimen
%         <exp>/
%           manifest.json               % manifest 1 eksperimen (setelan + frame)
%           velmag/
%             <exp>_velmag_f001.jpg ...  % 1 JPEG per-bingkai
%           shear/
%             <exp>_shear_f001.jpg  ...
%
%   IMMUTABLE bagi user: kalau setelan plot/warna berubah & user tak suka ->
%   HAPUS folder <exp> lalu REGENERATE dari nol (folder dibersihkan total).
%   `fingerprint(spec)` membandingkan setelan render: bila berubah dari yang
%   tercatat di manifest -> katalog ditandai BASI (perlu regenerate).
%
%   Skema MANIFEST (manifest.json):
%     formatName/formatVersion, exp(base), source(dataFile relatif), nFrames,
%     producedAt (tanggal, di-stamp PEMANGGIL — engine tak panggil clock),
%     dpi, jpegQuality, spec (setelan render: scalar list, clim, psg, glyph,
%     gs, fingerprint), scalars{velmag/shear -> {dir, files[], count}}.
%
%   Lihat [[grain-step4-ecosystem]] (PAB4_claude bundle) — pola manifest serupa,
%   tapi katalog ini SKALA-BESAR (semua frame x semua exp) & untuk montase paper.

    methods (Static)

        % =============================================================
        % LOKASI & PENAMAAN
        % =============================================================
        function r = rootDir(grainRoot)
        %ROOTDIR  Folder induk katalog: <grainRoot>/PAB_export.
            if nargin < 1 || isempty(grainRoot), grainRoot = pwd; end
            r = fullfile(char(grainRoot), 'PAB_export');
        end

        function b = expName(dataFile)
        %EXPNAME  Nama eksperimen = basename .mat, di-sanitasi untuk folder.
            [~, base] = fileparts(char(dataFile));
            b = pivcore.io.grainExportCatalog.safeName(base);
        end

        function d = expDir(grainRoot, dataFile)
        %EXPDIR  Folder 1 eksperimen: PAB_export/<exp>/.
            d = fullfile(pivcore.io.grainExportCatalog.rootDir(grainRoot), ...
                pivcore.io.grainExportCatalog.expName(dataFile));
        end

        function d = scalarDir(grainRoot, dataFile, scalar)
        %SCALARDIR  Folder per-skalar: PAB_export/<exp>/velmag|shear/.
            d = fullfile(pivcore.io.grainExportCatalog.expDir(grainRoot, dataFile), ...
                pivcore.io.grainExportCatalog.scalarKey(scalar));
        end

        function d = frameDir(grainRoot, dataFile)
        %FRAMEDIR  Folder ekspor 1 bingkai (velmag+shear): PAB_export/<exp>/_frame/.
        %   Terpisah dari katalog resmi (tak menyentuh manifest/purge).
            d = fullfile(pivcore.io.grainExportCatalog.expDir(grainRoot, dataFile), ...
                '_frame');
        end

        function k = scalarKey(scalar)
        %SCALARKEY  Normalisasi nama skalar -> 'velmag' | 'shear'.
            s = lower(char(scalar));
            if contains(s,'shear'), k = 'shear'; else, k = 'velmag'; end
        end

        function nm = frameFile(dataFile, scalar, k, ext)
        %FRAMEFILE  Nama berkas 1 bingkai: <exp>_<scalar>_f###.<ext>.
        %   k di-zero-pad 3 digit (atau lebih bila >999 bingkai).
            if nargin < 4 || isempty(ext), ext = 'jpg'; end
            exp = pivcore.io.grainExportCatalog.expName(dataFile);
            sk  = pivcore.io.grainExportCatalog.scalarKey(scalar);
            w = max(3, numel(num2str(k)));
            nm = sprintf('%s_%s_f%0*d.%s', exp, sk, w, k, ext);
        end

        function p = manifestPath(grainRoot, dataFile)
        %MANIFESTPATH  Path manifest.json eksperimen.
            p = fullfile(pivcore.io.grainExportCatalog.expDir(grainRoot, dataFile), ...
                'manifest.json');
        end

        function p = catalogPath(grainRoot)
        %CATALOGPATH  Path indeks global _catalog.json.
            p = fullfile(pivcore.io.grainExportCatalog.rootDir(grainRoot), ...
                '_catalog.json');
        end

        % =============================================================
        % SPEC RENDER & FINGERPRINT (deteksi BASI)
        % =============================================================
        function spec = specStruct(p)
        %SPECSTRUCT  Bangun spec setelan render (apa yang menentukan rupa gambar).
        %   p = struct opsional dgn field; field hilang -> default. Field:
        %     scalars   cellstr {'velmag','shear'} (mana yg dirender)
        %     climVel   [lo hi] CLim |V|         shearAbs  CLim |shear|
        %     psgId     id garis PSG (string)    psgP1/psgP2 [x y] ujung garis
        %     psgSource 'potdata'|'autopot'|'auto'  asal garis PSG
        %     gsOn/claheOn/adjOn/gsAlpha           overlay grayscale
        %     glyphOn/glyphLW/glyphSp/glyphColor   overlay panah
        %   psgP1/P2 & clim IKUT fingerprint (mengubah rupa); psgSource TIDAK.
            if nargin < 1 || ~isstruct(p), p = struct(); end
            g = @(f,d) pivcore.io.grainExportCatalog.getf(p, f, d);
            spec = struct();
            spec.scalars   = pivcore.io.grainExportCatalog.normScalars( ...
                g('scalars', {{'velmag','shear'}}));
            spec.climVel   = pivcore.io.grainExportCatalog.row2(g('climVel', [0 5]));
            spec.shearAbs  = pivcore.io.grainExportCatalog.scal(g('shearAbs', 0.05));
            spec.psgId     = char(g('psgId', ''));
            spec.psgP1     = pivcore.io.grainExportCatalog.row2(g('psgP1', [NaN NaN]));
            spec.psgP2     = pivcore.io.grainExportCatalog.row2(g('psgP2', [NaN NaN]));
            spec.psgSource = char(g('psgSource', 'auto'));
            spec.gsOn      = logical(g('gsOn', true));
            spec.claheOn   = logical(g('claheOn', true));
            spec.adjOn     = logical(g('adjOn', true));
            spec.gsAlpha   = pivcore.io.grainExportCatalog.scal(g('gsAlpha', 0.5));
            spec.glyphOn   = logical(g('glyphOn', true));
            spec.glyphLW   = pivcore.io.grainExportCatalog.scal(g('glyphLW', 1));
            spec.glyphSp   = pivcore.io.grainExportCatalog.scal(g('glyphSp', 3));
            spec.glyphColor= pivcore.io.grainExportCatalog.row3(g('glyphColor', [0 0 0]));
            % Warna glyph KHUSUS shear (default = sama dgn velmag bila NaN).
            spec.glyphColorShear = pivcore.io.grainExportCatalog.row3(g('glyphColorShear', [NaN NaN NaN]));
            % Tickmark posisi pixel (XTick/YTick) on/off.
            spec.tickPx    = logical(g('tickPx', true));
            % Satuan vel mag: 'pxframe' (asli) | 'cms' (cm/s = |V|*velMult).
            spec.velUnit   = char(g('velUnit', 'pxframe'));
            spec.velMult   = pivcore.io.grainExportCatalog.scal(g('velMult', 1));
            % Caption strain kiri-bawah: show + posisi + warna teks + warna latar.
            spec.strainShow= logical(g('strainShow', true));
            spec.strainPos = pivcore.io.grainExportCatalog.row2(g('strainPos', [0.02 0.04]));
            spec.strainColor = pivcore.io.grainExportCatalog.row3(g('strainColor', [0 0 0]));
            spec.strainBg  = pivcore.io.grainExportCatalog.row3(g('strainBg', [1 1 1]));
            spec.fingerprint = pivcore.io.grainExportCatalog.fingerprint(spec);
        end

        function fp = fingerprint(spec)
        %FINGERPRINT  Hash 8-hex (FNV-1a 32-bit) dari setelan PENENTU RUPA gambar.
        %   Deterministik; mengabaikan psgSource (asal garis tak mengubah piksel
        %   bila p1/p2 sama). Dipakai untuk deteksi BASI: spec live vs manifest.
            parts = {};
            sc = sort(pivcore.io.grainExportCatalog.normScalars(spec.scalars));   % urutan-invarian
            parts{end+1} = strjoin(sc, ',');
            parts{end+1} = pivcore.io.grainExportCatalog.numStr(spec.climVel);
            parts{end+1} = pivcore.io.grainExportCatalog.numStr(spec.shearAbs);
            parts{end+1} = pivcore.io.grainExportCatalog.numStr(spec.psgP1);
            parts{end+1} = pivcore.io.grainExportCatalog.numStr(spec.psgP2);
            parts{end+1} = sprintf('gs%d.%d.%d.%s', spec.gsOn, spec.claheOn, ...
                spec.adjOn, pivcore.io.grainExportCatalog.numStr(spec.gsAlpha));
            parts{end+1} = sprintf('gl%d.%s.%s.%s', spec.glyphOn, ...
                pivcore.io.grainExportCatalog.numStr(spec.glyphLW), ...
                pivcore.io.grainExportCatalog.numStr(spec.glyphSp), ...
                pivcore.io.grainExportCatalog.numStr(spec.glyphColor));
            % --- field BARU: hanya masuk hash bila NON-default (kompat manifest lama) ---
            gf = @(s,f,d) pivcore.io.grainExportCatalog.getf(s,f,d);
            gcs = gf(spec,'glyphColorShear',[NaN NaN NaN]);
            if any(isfinite(gcs))
                parts{end+1} = ['gcs' pivcore.io.grainExportCatalog.numStr(gcs)];
            end
            if ~gf(spec,'tickPx',true)             % default true -> hanya bila OFF
                parts{end+1} = 'tickoff';
            end
            vu = char(gf(spec,'velUnit','pxframe'));
            if ~strcmp(vu,'pxframe')               % default pxframe
                parts{end+1} = ['vu' vu pivcore.io.grainExportCatalog.numStr(gf(spec,'velMult',1))];
            end
            if ~gf(spec,'strainShow',true)         % default tampil
                parts{end+1} = 'strainoff';
            end
            sp = pivcore.io.grainExportCatalog.row2(gf(spec,'strainPos',[0.02 0.04]));
            if ~isequal(sp, [0.02 0.04])           % default pos
                parts{end+1} = ['sp' pivcore.io.grainExportCatalog.numStr(sp)];
            end
            scol = pivcore.io.grainExportCatalog.row3(gf(spec,'strainColor',[0 0 0]));
            if ~isequal(scol, [0 0 0])
                parts{end+1} = ['scol' pivcore.io.grainExportCatalog.numStr(scol)];
            end
            sbg = pivcore.io.grainExportCatalog.row3(gf(spec,'strainBg',[1 1 1]));
            if ~isequal(sbg, [1 1 1])
                parts{end+1} = ['sbg' pivcore.io.grainExportCatalog.numStr(sbg)];
            end
            fp = pivcore.io.grainExportCatalog.hashString(strjoin(parts, '|'));
        end

        function tf = isStale(manifest, liveSpec)
        %ISSTALE  true bila katalog BASI: fingerprint manifest != fingerprint
        %   spec live (setelan render berubah) ATAU manifest tak punya spec.
            tf = true;
            if ~isstruct(manifest) || ~isfield(manifest,'spec'), return; end
            ms = manifest.spec;
            if ~isstruct(ms) || ~isfield(ms,'fingerprint'), return; end
            tf = ~strcmp(char(ms.fingerprint), char(liveSpec.fingerprint));
        end

        % =============================================================
        % MANIFEST I/O
        % =============================================================
        function m = emptyManifest(dataFile, nFrames)
        %EMPTYMANIFEST  Kerangka manifest 1 eksperimen.
            if nargin < 2, nFrames = NaN; end
            m = struct();
            m.formatName    = 'GRAIN Export Catalog';
            m.formatVersion = 1;
            m.exp           = pivcore.io.grainExportCatalog.expName(dataFile);
            m.source        = char(dataFile);
            m.nFrames       = pivcore.io.grainExportCatalog.scal(nFrames);
            m.producedAt    = '';                 % di-stamp pemanggil (tanggal)
            m.dpi           = 300;
            m.jpegQuality   = 95;
            m.spec          = struct();
            m.scalars       = struct();           % velmag/shear -> {dir,files,count}
        end

        function m = read(grainRoot, dataFile)
        %READ  Baca manifest eksperimen. Tak ada -> emptyManifest.
            p = pivcore.io.grainExportCatalog.manifestPath(grainRoot, dataFile);
            if isempty(p) || ~isfile(p)
                m = pivcore.io.grainExportCatalog.emptyManifest(dataFile); return;
            end
            try
                m = jsondecode(fileread(p));
            catch ME
                warning('pivcore:grainExportCatalog:read', ...
                    'Gagal parse %s (%s); pakai manifest kosong.', p, ME.message);
                m = pivcore.io.grainExportCatalog.emptyManifest(dataFile);
            end
        end

        function write(grainRoot, dataFile, manifest)
        %WRITE  Tulis manifest.json ATOMIC (tmp->movefile). Buat folder bila perlu.
            d = pivcore.io.grainExportCatalog.expDir(grainRoot, dataFile);
            if ~isfolder(d), mkdir(d); end
            p = pivcore.io.grainExportCatalog.manifestPath(grainRoot, dataFile);
            pivcore.io.grainExportCatalog.writeJsonAtomic(p, manifest);
        end

        % =============================================================
        % INDEKS GLOBAL _catalog.json
        % =============================================================
        function rebuildIndex(grainRoot)
        %REBUILDINDEX  Pindai PAB_export/*/manifest.json -> _catalog.json (indeks
        %   global: daftar exp + jumlah gambar + fingerprint + producedAt). Dipanggil
        %   setelah render/hapus agar histori "apa yg sudah diekspor" mutakhir.
            r = pivcore.io.grainExportCatalog.rootDir(grainRoot);
            idx = struct();
            idx.formatName    = 'GRAIN Export Index';
            idx.formatVersion = 1;
            idx.root          = r;
            idx.experiments   = {};
            if isfolder(r)
                sub = dir(r);
                ents = {};
                for i = 1:numel(sub)
                    if ~sub(i).isdir, continue; end
                    nm = sub(i).name;
                    if strcmp(nm,'.')||strcmp(nm,'..'), continue; end
                    mp = fullfile(r, nm, 'manifest.json');
                    if ~isfile(mp), continue; end
                    try, m = jsondecode(fileread(mp)); catch, continue; end
                    e = struct();
                    e.exp        = nm;
                    e.nFrames    = pivcore.io.grainExportCatalog.getf(m,'nFrames',NaN);
                    e.producedAt = pivcore.io.grainExportCatalog.getf(m,'producedAt','');
                    e.dpi        = pivcore.io.grainExportCatalog.getf(m,'dpi',NaN);
                    cnt = struct('velmag',0,'shear',0);
                    if isfield(m,'scalars') && isstruct(m.scalars)
                        if isfield(m.scalars,'velmag'), cnt.velmag = pivcore.io.grainExportCatalog.scalCount(m.scalars.velmag); end
                        if isfield(m.scalars,'shear'),  cnt.shear  = pivcore.io.grainExportCatalog.scalCount(m.scalars.shear); end
                    end
                    e.velmagCount = cnt.velmag;
                    e.shearCount  = cnt.shear;
                    fp = '';
                    if isfield(m,'spec') && isstruct(m.spec) && isfield(m.spec,'fingerprint')
                        fp = char(m.spec.fingerprint);
                    end
                    e.fingerprint = fp;
                    ents{end+1} = e; %#ok<AGROW>
                end
                idx.experiments = ents;
            else
                mkdir(r);
            end
            pivcore.io.grainExportCatalog.writeJsonAtomic( ...
                pivcore.io.grainExportCatalog.catalogPath(grainRoot), idx);
        end

        % =============================================================
        % HAPUS (regenerate dari nol)
        % =============================================================
        function purgeExp(grainRoot, dataFile)
        %PURGEEXP  HAPUS TOTAL folder eksperimen (semua JPEG + manifest). Dipakai
        %   sebelum regenerate supaya tak ada berkas yatim dari setelan lama.
            d = pivcore.io.grainExportCatalog.expDir(grainRoot, dataFile);
            if isfolder(d)
                st = rmdir(d, 's');
                if ~st
                    warning('pivcore:grainExportCatalog:purge', ...
                        'Gagal menghapus folder katalog: %s', d);
                end
            end
        end

        % =============================================================
        % SIDECAR per-exp <base>_exportcfg.json + PROGRESS sesi
        % =============================================================
        function p = cfgPath(dataFile)
        %CFGPATH  Path sidecar setelan render per-exp = <dir>/<base>_exportcfg.json
        %   (di SAMPING .mat sumber, bukan di folder katalog).
            [d, base] = fileparts(char(dataFile));
            p = fullfile(d, [base '_exportcfg.json']);
        end

        function cfg = readCfg(dataFile)
        %READCFG  Baca sidecar setelan render exp. Tak ada -> struct kosong.
            p = pivcore.io.grainExportCatalog.cfgPath(dataFile);
            cfg = struct();
            if isfile(p)
                try, cfg = jsondecode(fileread(p)); catch, cfg = struct(); end
            end
        end

        function writeCfg(dataFile, cfg)
        %WRITECFG  Tulis sidecar setelan render exp (ATOMIC).
            p = pivcore.io.grainExportCatalog.cfgPath(dataFile);
            if ~isstruct(cfg), cfg = struct(); end
            cfg.formatName = 'GRAIN Export Cfg'; cfg.formatVersion = 1;
            cfg.source = char(dataFile);
            pivcore.io.grainExportCatalog.writeJsonAtomic(p, cfg);
        end

        function p = progressPath(grainRoot)
        %PROGRESSPATH  Path progress sesi = PAB_export/_export_progress.json.
            p = fullfile(pivcore.io.grainExportCatalog.rootDir(grainRoot), ...
                '_export_progress.json');
        end

        function d = previewDir(grainRoot)
        %PREVIEWDIR  Folder TES = PAB_export/_preview/ (1 frame uji, BUKAN katalog
        %   resmi -> tak masuk manifest/indeks).
            d = fullfile(pivcore.io.grainExportCatalog.rootDir(grainRoot), '_preview');
        end

        function prog = readProgress(grainRoot)
        %READPROGRESS  Baca progress sesi. Tak ada -> struct kosong default.
            p = pivcore.io.grainExportCatalog.progressPath(grainRoot);
            prog = struct('formatName','GRAIN Export Progress','formatVersion',1, ...
                'root','', 'savedAt','', 'global',struct(), 'selected',{{}});
            if isfile(p)
                try, prog = jsondecode(fileread(p)); catch, end
            end
        end

        function writeProgress(grainRoot, prog)
        %WRITEPROGRESS  Tulis progress sesi (ATOMIC). Buat folder bila perlu.
            r = pivcore.io.grainExportCatalog.rootDir(grainRoot);
            if ~isfolder(r), mkdir(r); end
            if ~isstruct(prog), prog = struct(); end
            prog.formatName = 'GRAIN Export Progress'; prog.formatVersion = 1;
            pivcore.io.grainExportCatalog.writeJsonAtomic( ...
                pivcore.io.grainExportCatalog.progressPath(grainRoot), prog);
        end

        % =============================================================
        % UTIL (murni)
        % =============================================================
        function fp = hashString(s)
        %HASHSTRING  FNV-1a 32-bit -> 8 hex char (deterministik, lintas-sesi).
            s = uint8(char(s));
            h = uint32(2166136261);
            P = uint32(16777619);
            for i = 1:numel(s)
                h = bitxor(h, uint32(s(i)));
                h = uint32(mod(double(h) * double(P), 4294967296));
            end
            fp = lower(dec2hex(h, 8));
        end

        function s = numStr(v)
        %NUMSTR  Serialisasi numerik stabil (6 sig, NaN->'nan') untuk fingerprint.
            v = double(v(:).');
            parts = cell(1, numel(v));
            for i = 1:numel(v)
                if isnan(v(i)), parts{i} = 'nan';
                else, parts{i} = sprintf('%.6g', v(i)); end
            end
            s = strjoin(parts, ',');
        end

        function nm = safeName(s)
        %SAFENAME  Sanitasi -> aman jadi nama folder/berkas.
            nm = regexprep(char(s), '[^\w\-\.]+', '_');
            nm = regexprep(nm, '_+', '_');
            nm = regexprep(nm, '^_+|_+$', '');
            if isempty(nm), nm = 'exp'; end
        end

        function sc = normScalars(x)
        %NORMSCALARS  Ratakan input skalar -> cellstr DATAR baris {'velmag',...}.
        %   Tahan terhadap nested cell ({{...}}), char tunggal, atau cellstr.
            while iscell(x) && isscalar(x) && iscell(x{1}), x = x{1}; end  % buang nested {{..}}
            if ischar(x) || isstring(x)
                sc = {char(x)};
            elseif iscell(x)
                sc = cellfun(@char, x(:).', 'UniformOutput', false);
            else
                sc = {'velmag','shear'};
            end
            if isempty(sc), sc = {'velmag','shear'}; end
        end

        function v = getf(s, f, d)
            if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
        end

        function v = scal(x)
            if isempty(x), v = NaN; else, v = double(x(1)); end
        end

        function v = row2(p)
            p = double(p(:).'); if numel(p) < 2, p = [p nan(1, 2-numel(p))]; end
            v = p(1:2);
        end

        function v = row3(p)
            p = double(p(:).'); if numel(p) < 3, p = [p nan(1, 3-numel(p))]; end
            v = p(1:3);
        end

        function n = scalCount(s)
        %SCALCOUNT  Ambil 'count' dari sub-struct skalar manifest (robust).
            n = 0;
            if isstruct(s)
                if isfield(s,'count') && ~isempty(s.count), n = double(s.count(1));
                elseif isfield(s,'files'), n = numel(s.files); end
            end
        end

        function writeJsonAtomic(p, obj)
        %WRITEJSONATOMIC  jsonencode pretty -> tmp -> movefile (atomic).
            txt = jsonencode(obj, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0, error('pivcore:grainExportCatalog:open','Tak bisa tulis %s', tmp); end
            c = onCleanup(@() pivcore.io.grainExportCatalog.cleanupTmp(tmp));
            fwrite(fid, txt, 'char'); fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok, error('pivcore:grainExportCatalog:move','Gagal pindah %s: %s', p, msg); end
        end

        function cleanupTmp(tmp)
            if isfile(tmp), try, delete(tmp); catch, end, end
        end

    end
end
