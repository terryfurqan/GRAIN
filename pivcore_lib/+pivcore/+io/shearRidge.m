classdef shearRidge
%SHEARRIDGE  Engine sidecar `<base>_shearridge.json` untuk digitasi punggungan
%   (ridge) shear strain rate hasil auto-tracing (modul SHEARSTRAINDetector).
%
%   Konsep: tiap ridge = 1 polyline (Nx2 koordinat piksel gambar) yang di-digitasi
%   pada SATU frame (Tahap 1: per-frame). Disimpan TERPISAH dari _desc.json GRAIN4
%   (bersih & mandiri). Beberapa ridge boleh ada per garis PSG per frame.
%
%   Struktur dokumen:
%     doc.ridges = { entry, ... }
%       entry.id        : id unik string (mis. 'R1', 'R2', ...)
%       entry.psgId     : garis PSG aktif saat digitasi
%       entry.frame     : frame tempat ridge di-digitasi
%       entry.vertices  : Nx2 [x y] piksel (di-cell-kan saat encode)
%       entry.polarity  : +1 (merah) / -1 (biru) dari sel seed
%       entry.seedVal   : |shear| di seed
%       entry.meanAbs   : rata-rata |shear| sepanjang ridge
%       entry.lenCm     : panjang (cm) bila cmPerPx diberikan; else NaN
%       entry.widthPx   : lebar garis (dari lebar puncak) — placeholder Tahap 1
%       entry.note      : catatan bebas
%
%   MURNI / headless (pola pivcore.io.grain4Interp). Vertices di-cell-kan saat encode.
%   Penempatan: GRAIN/pivcore_lib/+pivcore/+io/shearRidge.m

    methods (Static)

        % ================================================================
        function p = dataPath(dataFile)
        %DATAPATH  <dir>/<base>_shearridge.json untuk MAT PIV dataFile.
            p = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_shearridge.json', base));
        end

        function doc = emptyDoc(dataFile)
        %EMPTYDOC  Kerangka dokumen kosong.
            if nargin < 1, dataFile = ''; end
            [~, base, ext] = fileparts(char(dataFile));
            doc = struct();
            doc.formatName    = 'SHEARSTRAINDetector Shear Ridge';
            doc.formatVersion = 1;
            doc.source        = [base ext];
            doc.ridges        = {};   % cell of ridge-entry (JSON array)
        end

        function doc = read(dataFile)
        %READ  Baca & NORMALISASI sidecar. Tak ada berkas -> emptyDoc. Rusak ->
        %   emptyDoc + warning (tak melempar agar GUI tetap jalan).
            p = pivcore.io.shearRidge.dataPath(dataFile);
            if isempty(p) || ~isfile(p)
                doc = pivcore.io.shearRidge.emptyDoc(dataFile); return;
            end
            try
                txt = fileread(p);
                raw = jsondecode(txt);
            catch ME
                warning('pivcore:shearRidge:read', ...
                    'Gagal membaca/parse %s (%s); pakai dokumen kosong.', p, ME.message);
                doc = pivcore.io.shearRidge.emptyDoc(dataFile); return;
            end
            doc = pivcore.io.shearRidge.normalizeDoc(raw, dataFile);
        end

        function write(dataFile, doc)
        %WRITE  Tulis dokumen ke `<base>_shearridge.json` secara ATOMIC.
            p = pivcore.io.shearRidge.dataPath(dataFile);
            if isempty(p)
                error('pivcore:shearRidge:noPath', ...
                    'Tak bisa menentukan path _shearridge untuk: %s', dataFile);
            end
            doc = pivcore.io.shearRidge.prepForEncode(doc);
            txt = jsonencode(doc, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0
                error('pivcore:shearRidge:open', 'Tak bisa membuka %s utk tulis.', tmp);
            end
            cleaner = onCleanup(@() pivcore.io.shearRidge.cleanupTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
            fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok
                error('pivcore:shearRidge:move', ...
                    'Gagal memindah tmp->final (%s): %s', p, msg);
            end
        end

        % ================================================================
        %                    ENTRY / AKSES
        % ================================================================
        function e = ridgeStruct(varargin)
        %RIDGESTRUCT  Buat entry ridge. Argumen name/value.
            e = struct('id','', 'psgId','', 'frame',NaN, 'vertices',zeros(0,2), ...
                       'polarity',0, 'seedVal',NaN, 'meanAbs',NaN, 'lenCm',NaN, ...
                       'widthPx',NaN, 'note','');
            for i = 1:2:numel(varargin)-1
                k = varargin{i}; v = varargin{i+1};
                if ~ischar(k) || ~isfield(e,k), continue; end
                switch k
                    case {'id','psgId','note'}, e.(k) = pivcore.io.shearRidge.tostr(v);
                    case 'vertices', e.(k) = pivcore.io.grain4Desc.normVerts(v);
                    otherwise, e.(k) = pivcore.io.shearRidge.scal(v);
                end
            end
        end

        function ids = idsForFrame(doc, psgId, frame)
        %IDSFORFRAME  Daftar id ridge pada (psgId, frame). {} bila kosong.
            ids = {};
            all = pivcore.io.shearRidge.entries(doc);
            key = pivcore.io.shearRidge.tostr(psgId);
            f = round(pivcore.io.shearRidge.scal(frame));
            for k = 1:numel(all)
                en = all{k};
                pk = ''; if isfield(en,'psgId'), pk = pivcore.io.shearRidge.tostr(en.psgId); end
                ef = round(pivcore.io.shearRidge.scal(en.frame));
                if strcmp(pk,key) && ef == f, ids{end+1} = en.id; end %#ok<AGROW>
            end
        end

        function out = ridgesForFrame(doc, psgId, frame)
        %RIDGESFORFRAME  Cell entry ridge pada (psgId, frame).
            out = {};
            all = pivcore.io.shearRidge.entries(doc);
            key = pivcore.io.shearRidge.tostr(psgId);
            f = round(pivcore.io.shearRidge.scal(frame));
            for k = 1:numel(all)
                en = all{k};
                pk = ''; if isfield(en,'psgId'), pk = pivcore.io.shearRidge.tostr(en.psgId); end
                ef = round(pivcore.io.shearRidge.scal(en.frame));
                if strcmp(pk,key) && ef == f, out{end+1} = en; end %#ok<AGROW>
            end
        end

        function e = ridgeById(doc, id)
        %RIDGEBYID  Entry dgn id tsb. [] bila tak ada.
            e = [];
            all = pivcore.io.shearRidge.entries(doc);
            key = pivcore.io.shearRidge.tostr(id);
            for k = 1:numel(all)
                if strcmp(pivcore.io.shearRidge.tostr(all{k}.id), key), e = all{k}; return; end
            end
        end

        function id = nextId(doc)
        %NEXTID  'R<n>' unik berikut.
            all = pivcore.io.shearRidge.entries(doc);
            mx = 0;
            for k = 1:numel(all)
                s = pivcore.io.shearRidge.tostr(all{k}.id);
                m = regexp(s, '^R(\d+)$', 'tokens', 'once');
                if ~isempty(m), mx = max(mx, str2double(m{1})); end
            end
            id = sprintf('R%d', mx+1);
        end

        function doc = upsert(doc, entry)
        %UPSERT  Tambah/ganti ridge berdasar id. id kosong -> assign nextId.
            if ~isstruct(doc), doc = pivcore.io.shearRidge.emptyDoc(''); end
            if ~isfield(doc,'ridges'), doc.ridges = {}; end
            entry = pivcore.io.shearRidge.normEntry(entry);
            if isempty(entry.id), entry.id = pivcore.io.shearRidge.nextId(doc); end
            all = pivcore.io.shearRidge.entries(doc);
            keep = {}; replaced = false;
            for k = 1:numel(all)
                if strcmp(all{k}.id, entry.id)
                    keep{end+1} = entry; replaced = true; %#ok<AGROW>
                else
                    keep{end+1} = all{k}; %#ok<AGROW>
                end
            end
            if ~replaced, keep{end+1} = entry; end
            doc.ridges = keep;
        end

        function doc = removeById(doc, id)
        %REMOVEBYID  Buang ridge dgn id.
            if ~isstruct(doc) || ~isfield(doc,'ridges'), return; end
            key = pivcore.io.shearRidge.tostr(id);
            all = pivcore.io.shearRidge.entries(doc);
            keep = {};
            for k = 1:numel(all)
                if ~strcmp(pivcore.io.shearRidge.tostr(all{k}.id), key), keep{end+1} = all{k}; end %#ok<AGROW>
            end
            doc.ridges = keep;
        end

        function all = entries(doc)
        %ENTRIES  Cell entry ter-normalisasi.
            all = {};
            if ~isstruct(doc) || ~isfield(doc,'ridges'), return; end
            c = pivcore.io.shearRidge.tocell(doc.ridges);
            all = cell(1, numel(c));
            for k = 1:numel(c), all{k} = pivcore.io.shearRidge.normEntry(c{k}); end
        end

        % ================================================================
        %                    NORMALISASI / ENCODE
        % ================================================================
        function doc = normalizeDoc(raw, dataFile)
            doc = pivcore.io.shearRidge.emptyDoc(dataFile);
            if ~isstruct(raw), return; end
            if isfield(raw,'formatVersion') && isscalar(raw.formatVersion)
                doc.formatVersion = double(raw.formatVersion);
            end
            if isfield(raw,'source') && ischar(raw.source), doc.source = raw.source; end
            if isfield(raw,'ridges')
                tc = pivcore.io.shearRidge.tocell(raw.ridges);
                out = {};
                for k = 1:numel(tc), out{end+1} = pivcore.io.shearRidge.normEntry(tc{k}); end %#ok<AGROW>
                doc.ridges = out;
            end
        end

        function e = normEntry(s)
            e = pivcore.io.shearRidge.ridgeStruct();
            if ~isstruct(s), return; end
            if isfield(s,'id'),       e.id       = pivcore.io.shearRidge.tostr(s.id); end
            if isfield(s,'psgId'),    e.psgId    = pivcore.io.shearRidge.tostr(s.psgId); end
            if isfield(s,'frame'),    e.frame    = pivcore.io.shearRidge.scal(s.frame); end
            if isfield(s,'vertices'), e.vertices = pivcore.io.grain4Desc.normVerts(s.vertices); end
            if isfield(s,'polarity'), e.polarity = pivcore.io.shearRidge.scal(s.polarity); end
            if isfield(s,'seedVal'),  e.seedVal  = pivcore.io.shearRidge.scal(s.seedVal); end
            if isfield(s,'meanAbs'),  e.meanAbs  = pivcore.io.shearRidge.scal(s.meanAbs); end
            if isfield(s,'lenCm'),    e.lenCm    = pivcore.io.shearRidge.scal(s.lenCm); end
            if isfield(s,'widthPx'),  e.widthPx  = pivcore.io.shearRidge.scal(s.widthPx); end
            if isfield(s,'note'),     e.note     = pivcore.io.shearRidge.tostr(s.note); end
        end

        function doc = prepForEncode(doc)
        %PREPFORENCODE  vertices Nx2 -> cell-of-[x y] tiap entry (round-trip stabil).
            if ~isstruct(doc), doc = pivcore.io.shearRidge.emptyDoc(''); end
            if ~isfield(doc,'ridges'), doc.ridges = {}; end
            all = pivcore.io.shearRidge.entries(doc);
            out = cell(1, numel(all));
            for k = 1:numel(all)
                en = all{k};
                en.vertices = pivcore.io.grain4Desc.vertsToCell(en.vertices);
                out{k} = en;
            end
            doc.ridges = out;
        end

        % --- helper tipe ---------------------------------------------
        function c = tocell(x)
            if isempty(x), c = {}; return; end
            if iscell(x), c = reshape(x, 1, []); return; end
            if isstruct(x)
                c = cell(1, numel(x));
                for k = 1:numel(x), c{k} = x(k); end
                return;
            end
            c = {x};
        end

        function v = scal(x)
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end

        function s = tostr(x)
            if isempty(x), s = ''; return; end
            if ischar(x)
                if size(x,1) > 1, x = strjoin(cellstr(x), newline); end
                s = reshape(char(x), 1, []); return;
            end
            if isstring(x)
                s = char(strjoin(x(:).', newline)); s = reshape(s, 1, []); return;
            end
            if isnumeric(x) && isscalar(x)
                if isfinite(x), s = num2str(x); else, s = ''; end
                return;
            end
            try, s = reshape(char(string(x)), 1, []); catch, s = ''; end
        end

        function cleanupTmp(tmp)
            try, if isfile(tmp), delete(tmp); end, catch, end
        end

    end
end
