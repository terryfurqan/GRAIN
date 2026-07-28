classdef pab4Shots
%PAB4SHOTS  Sistem PRODUKSI GAMBAR PAB4 (tab ④ Produksi Gambar).
%   "shotSpec" = SATU-SATUNYA sumber kebenaran tiap gambar: spec yang sama
%   menggerakkan render PNG DAN dicatat ke JSON -> gambar & tag SELALU padan
%   (tak ada desain "baca ulang UI saat ekspor"). Tiap gambar membawa:
%     - spec        : apa yang DITAMPILKAN (panel, frame, garis, kurva, titik)
%     - fingerprint : hash DETERMINISTIK dari data penentu (deteksi BASI bila
%                     data berubah: re-label / trim / geser garis / buang kurva)
%     - producedAt  : tanggal produksi (seperti "commit date" git sederhana)
%     - caption     : teks tertanam di gambar (gambar self-describing lepas JSON)
%
%   FOLDER (per-komentar; satu komentar = satu folder berisi beberapa PNG):
%     PAB4_claude/<base>/comments/<commentId>/{ comment.json, *.png }
%     PAB4_claude/<base>/manifest.json   (CLim terkunci per-eksperimen + indeks)
%
%   Kontrak CLim: CLim Vel mag & batas Shear DIKUNCI per-eksperimen (di manifest)
%   -> semua PNG eksperimen sama skalanya (komparabilitas ilmiah lampiran paper).
%
%   API utama:
%     spec = pivcore.io.pab4Shots.specStruct(p)        % normalisasi + caption
%     fp   = pivcore.io.pab4Shots.fingerprint(spec)    % hash deterministik
%     nm   = pivcore.io.pab4Shots.assetName(spec)      % nama PNG konsisten
%     d    = pivcore.io.pab4Shots.commentDir(dataFile, commentId)
%     a    = pivcore.io.pab4Shots.assetStruct(spec, file, producedAt)
%     pivcore.io.pab4Shots.writeManifest(dataFile, manifest)
%     stale = pivcore.io.pab4Shots.isStale(asset, liveSpec)   % fp beda -> basi
%
%   Penempatan: PAB/pivcore_lib/+pivcore/+io/pab4Shots.m

    methods (Static)

        % ================================================================
        function spec = specStruct(p)
        %SPECSTRUCT  Normalisasi parameter -> shotSpec kanonik (+caption).
        %   p: struct dgn field (opsional, default aman):
        %     panel('axpot'|'velmag'|'shear'), frame, frameTotal, strainPct,
        %     exp, psgId, preset, curvesVisible{cellstr}, rawVisible(logical),
        %     pointsVisible(logical), indenterVisible(logical), climVel[1x2],
        %     shearAbs(scalar).
            if nargin < 1 || ~isstruct(p), p = struct(); end
            S = pivcore.io.pab4Shots;
            spec = struct();
            spec.panel          = S.gp(p,'panel','axpot');
            spec.frame          = S.gn(p,'frame',1);
            spec.frameTotal     = S.gn(p,'frameTotal',NaN);
            spec.strainPct      = S.gn(p,'strainPct',NaN);
            spec.exp            = S.gp(p,'exp','');
            spec.psgId          = S.gp(p,'psgId','');
            spec.preset         = S.gp(p,'preset','custom');
            spec.curvesVisible  = S.gc(p,'curvesVisible');
            spec.rawVisible     = S.gb(p,'rawVisible',false);
            spec.pointsVisible  = S.gb(p,'pointsVisible',true);
            spec.indenterVisible= S.gb(p,'indenterVisible',true);
            spec.climVel        = S.gv(p,'climVel',[0 5]);
            spec.shearAbs       = S.gn(p,'shearAbs',1);
            spec.xUnit          = lower(S.gp(p,'xUnit','frame'));   % 'frame' | 'strain' (axPOT)
            spec.strainTotal    = S.gn(p,'strainTotal',NaN);        % strain kumulatif % di frame terakhir
            % --- Layer KOMPOSER CERITA (tab ⑤; default OFF -> kompat tab ④) ---
            spec.hwLabel        = S.gb(p,'hwLabel',false);      % label HW# di puncak tiap kurva HW
            spec.pointsAllHW    = S.gb(p,'pointsAllHW',false);  % titik POI utk SEMUA HW (bukan hanya curvesVisible)
            spec.frameLine      = S.gn(p,'frameLine',NaN);      % frame garis vertikal penunjuk; NaN=off
            spec.dataHash       = S.gp(p,'dataHash','');   % hash keadaan data saat produksi
            spec.caption        = S.captionText(spec);
        end


        % ================================================================
        function s = captionText(spec)
        %CAPTIONTEXT  Teks tertanam di gambar: exp · frame · strain · garis ·
        %   isi (panel). Dibuat self-describing supaya PNG bermakna lepas JSON.
            ex = spec.exp; if isempty(ex), ex = '?'; end
            fr = '';
            if isfinite(spec.frame)
                if isfinite(spec.frameTotal) && spec.frameTotal >= 1
                    fr = sprintf('frame %d/%d', round(spec.frame), round(spec.frameTotal));
                else
                    fr = sprintf('frame %d', round(spec.frame));
                end
            end
            st = ''; if isfinite(spec.strainPct), st = sprintf('strain %.1f%%', spec.strainPct); end
            pg = ''; if ~isempty(spec.psgId), pg = sprintf('psg %s', spec.psgId); end
            switch lower(spec.panel)
                case 'velmag', what = '|V| (vel mag)';
                case 'shear',  what = 'shear strain';
                otherwise
                    if isempty(spec.curvesVisible)
                        what = 'axPOT';
                    else
                        what = ['axPOT [' strjoin(spec.curvesVisible, ', ') ']'];
                    end
                    if spec.rawVisible, what = [what ' +mentah']; end
                    if isfield(spec,'xUnit') && strcmpi(spec.xUnit,'strain')
                        what = [what ' · x=strain%'];
                    end
            end
            parts = {ex, fr, st, pg, what};
            parts = parts(~cellfun(@isempty, parts));
            s = strjoin(parts, ' · ');
        end


        % ================================================================
        function fp = fingerprint(spec)
        %FINGERPRINT  Hash DETERMINISTIK (FNV-1a 32-bit) dari field PENENTU-DATA
        %   spec. TANPA producedAt/caption (itu bukan penentu kebenaran data).
        %   Beda fingerprint -> gambar BASI (data sudah berubah sejak diproduksi).
            d = struct();
            d.panel           = lower(char(spec.panel));
            d.frame           = pivcore.io.pab4Shots.num(spec.frame);
            d.exp             = char(spec.exp);
            d.psgId           = char(spec.psgId);
            d.curvesVisible   = sort(pivcore.io.pab4Shots.cleanCell(spec.curvesVisible));
            d.rawVisible      = logical(spec.rawVisible);
            d.pointsVisible   = logical(spec.pointsVisible);
            d.indenterVisible = logical(spec.indenterVisible);
            d.climVel         = pivcore.io.pab4Shots.numv(spec.climVel);
            d.shearAbs        = pivcore.io.pab4Shots.num(spec.shearAbs);
            d.strainPct       = round(1000*pivcore.io.pab4Shots.num(spec.strainPct))/1000;
            if isfield(spec,'xUnit'), d.xUnit = lower(char(spec.xUnit)); else, d.xUnit = 'frame'; end
            if isfield(spec,'strainTotal'), st = spec.strainTotal; else, st = NaN; end
            d.strainTotal     = round(1000*pivcore.io.pab4Shots.num(st))/1000;
            % Layer komposer (tab ⑤): hanya MASUK hash bila AKTIF -> spec default
            % (tab ④) menghasilkan struct & fingerprint IDENTIK seperti sebelumnya.
            if isfield(spec,'hwLabel')     && logical(spec.hwLabel),     d.hwLabel = true; end
            if isfield(spec,'pointsAllHW') && logical(spec.pointsAllHW), d.pointsAllHW = true; end
            if isfield(spec,'frameLine')
                fl = pivcore.io.pab4Shots.num(spec.frameLine);
                if isfinite(fl), d.frameLine = round(fl); end
            end
            if isfield(spec,'dataHash'), d.dataHash = char(spec.dataHash); else, d.dataHash = ''; end
            txt = jsonencode(d);
            fp  = pivcore.io.pab4Shots.fnv1a(txt);
        end


        % ================================================================
        function s = hashString(str)
        %HASHSTRING  Hash deterministik publik (FNV-1a 32-bit) -> 8 hex. Dipakai
        %   pemanggil membentuk dataHash dari keadaan data (label/trim/titik/garis).
            s = pivcore.io.pab4Shots.fnv1a(char(str));
        end


        % ================================================================
        function nm = assetName(spec)
        %ASSETNAME  Nama PNG konsisten & nyambung ke sistem pencatatan:
        %   <panel>_f<frame>[_<isi>].png. Aman utk nama berkas.
            fr = ''; if isfinite(spec.frame), fr = sprintf('_f%03d', round(spec.frame)); end
            switch lower(spec.panel)
                case 'velmag', nm = sprintf('velmag%s.png', fr);
                case 'shear',  nm = sprintf('shear%s.png', fr);
                otherwise
                    tag = 'axpot';
                    cv = pivcore.io.pab4Shots.cleanCell(spec.curvesVisible);
                    if ~isempty(cv)
                        safe = regexprep(strjoin(cv,'-'), '[^A-Za-z0-9\-]', '');
                        tag = ['axpot_' safe];
                    elseif spec.rawVisible
                        tag = 'axpot_mentah';
                    end
                    if spec.rawVisible && ~isempty(cv), tag = [tag '_mentah']; end
                    if isfield(spec,'xUnit') && strcmpi(spec.xUnit,'strain'), tag = [tag '_pct']; end
                    nm = sprintf('%s%s.png', tag, fr);
            end
        end


        % ================================================================
        function d = commentDir(dataFile, commentId)
        %COMMENTDIR  Folder per-komentar: PAB4_claude/<base>/comments/<id>/
            d = '';
            base = pivcore.io.pab4Comments.assetDir(dataFile);
            if isempty(base), return; end
            d = fullfile(base, 'comments', char(commentId));
        end


        % ================================================================
        function d = storyDir(dataFile)
        %STORYDIR  Folder gambar CERITA (tab ⑤; lepas komentar):
        %   PAB4_claude/<base>/story/   -> { *.png, *.json } pasangan se-basename.
            d = '';
            base = pivcore.io.pab4Comments.assetDir(dataFile);
            if isempty(base), return; end
            d = fullfile(base, 'story');
        end


        % ================================================================
        function writeStoryAsset(dataFile, baseName, asset)
        %WRITESTORYASSET  Tulis sidecar story/<baseName>.json (ATOMIC). Pasangan
        %   se-basename dengan PNG -> daftar gambar cerita + deteksi BASI.
            d = pivcore.io.pab4Shots.storyDir(dataFile);
            if isempty(d), return; end
            if ~isfolder(d), mkdir(d); end
            txt = jsonencode(asset, 'PrettyPrint', true);
            pivcore.io.pab4Shots.atomicWrite(fullfile(d, [char(baseName) '.json']), txt);
        end


        % ================================================================
        function a = assetStruct(spec, file, producedAt)
        %ASSETSTRUCT  Satu rekaman gambar terproduksi (untuk comment.assets).
            if nargin < 3 || isempty(producedAt), producedAt = ''; end
            a = struct();
            a.kind        = lower(char(spec.panel));
            a.file        = char(file);
            a.spec        = spec;
            a.fingerprint = pivcore.io.pab4Shots.fingerprint(spec);
            a.producedAt  = char(producedAt);
        end


        % ================================================================
        function tf = isStale(asset, liveSpec)
        %ISSTALE  Gambar BASI bila fingerprint tersimpan != fingerprint dari
        %   spec data terkini (liveSpec dgn isi tampilan SAMA).
            tf = false;
            if ~isstruct(asset) || ~isfield(asset,'fingerprint'), return; end
            tf = ~strcmp(char(asset.fingerprint), pivcore.io.pab4Shots.fingerprint(liveSpec));
        end


        % ================================================================
        function m = manifestStruct(dataFile, climVel, shearAbs, frameTotal)
        %MANIFESTSTRUCT  Skeleton manifest per-eksperimen (CLim terkunci).
            [~, base, ext] = fileparts(char(dataFile));
            m = struct();
            m.formatName    = 'PAB4 Shots Manifest';
            m.formatVersion = 1;
            m.source        = [base ext];
            m.lockedClim    = struct('velmag', pivcore.io.pab4Shots.numv(climVel), ...
                                     'shearAbs', pivcore.io.pab4Shots.num(shearAbs));
            m.frameTotal    = pivcore.io.pab4Shots.num(frameTotal);
            m.comments      = {};   % diisi exportClaude (id + daftar asset)
        end


        function writeManifest(dataFile, manifest)
        %WRITEMANIFEST  Tulis PAB4_claude/<base>/manifest.json (ATOMIC).
            dir0 = pivcore.io.pab4Comments.assetDir(dataFile);
            if isempty(dir0), return; end
            if ~isfolder(dir0), mkdir(dir0); end
            txt = jsonencode(manifest, 'PrettyPrint', true);
            pivcore.io.pab4Shots.atomicWrite(fullfile(dir0,'manifest.json'), txt);
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function v = gp(p, f, dflt)   % get char/string field
            v = dflt; if isstruct(p) && isfield(p,f) && ~isempty(p.(f)), v = char(p.(f)); end
        end
        function v = gn(p, f, dflt)   % get numeric scalar field
            v = dflt;
            if isstruct(p) && isfield(p,f) && isscalar(p.(f)) && isnumeric(p.(f)), v = double(p.(f)); end
        end
        function v = gb(p, f, dflt)   % get logical field
            v = logical(dflt);
            if isstruct(p) && isfield(p,f) && isscalar(p.(f)), v = logical(p.(f)); end
        end
        function v = gv(p, f, dflt)   % get [1x2] numeric vector
            v = dflt;
            if isstruct(p) && isfield(p,f) && numel(p.(f))==2 && isnumeric(p.(f)), v = double(p.(f)(:).'); end
        end
        function c = gc(p, f)         % get cellstr field
            c = {};
            if isstruct(p) && isfield(p,f), c = pivcore.io.pab4Shots.cleanCell(p.(f)); end
        end

        function c = cleanCell(x)
            c = {};
            if isempty(x), return; end
            if ischar(x), c = {x}; return; end
            if iscell(x)
                for k = 1:numel(x)
                    s = x{k}; if ~isempty(s) && (ischar(s)||isstring(s)), c{end+1} = char(s); end %#ok<AGROW>
                end
            elseif isstring(x)
                for k = 1:numel(x), if strlength(x(k))>0, c{end+1} = char(x(k)); end, end %#ok<AGROW>
            end
        end

        function v = num(x)
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end
        function v = numv(x)
            if isnumeric(x) && ~isempty(x), v = double(x(:).'); else, v = []; end
        end

        function s = fnv1a(str)
        %FNV1A  Hash FNV-1a 32-bit deterministik (offline, tanpa Java) -> 8 hex.
            b = double(unicode2native(char(str), 'UTF-8'));
            h = uint64(2166136261); prime = uint64(16777619); mask = uint64(4294967295);
            for i = 1:numel(b)
                h = bitxor(h, uint64(b(i)));
                h = bitand(h * prime, mask);
            end
            s = sprintf('%08x', h);
        end

        function atomicWrite(p, txt)
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0, error('pivcore:pab4Shots:open','Tak bisa tulis %s', tmp); end
            cleaner = onCleanup(@() pivcore.io.pab4Shots.rmTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
            fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok, error('pivcore:pab4Shots:move','Gagal tulis %s: %s', p, msg); end
        end
        function rmTmp(tmp)
            try, if isfile(tmp), delete(tmp); end, catch, end
        end

    end
end
