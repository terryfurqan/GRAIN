classdef pab4Interp
%PAB4INTERP  Engine INTERPOLASI bidang sesar antar-keyframe (evolusi frame-by-frame).
%   Konsep: user menggambar polyline bidang sesar HANYA di beberapa KEYFRAME (mis.
%   PRP-FSR di awal & ACT-FSR menjelang X-FS), sistem MENGISI frame di antaranya
%   dengan interpolasi LINEAR vertex-per-vertex -> lokasi tiap vertex "di-track"
%   sepanjang siklus FSR. Tabel DESKRIPSI TETAP bersih (cuma keyframe); hasil track
%   disimpan di sidecar TERPISAH `<base>_faultinterp.json`.
%
%   PRASYARAT (dipaksa): tiap keyframe sesar SAMA jumlah vertex (korespondensi
%   per-indeks). Ini terjamin krn ACT-FSR di-SEED (copy) dari PRP-FSR via Ctrl+Q
%   lalu digeser — jadi jumlah titik konsisten. Jumlah beda -> DITOLAK + pesan.
%
%   Struktur dokumen:
%     doc.tracks = { entry, ... }
%       entry.psgId, entry.fNum ('F3'), entry.keyFrames [f0 f1 ...],
%       entry.samples = { sample, ... }  (1 per frame integer f0..fLast)
%         sample.frame, sample.vertices (Nx2 -> cell saat encode), sample.lenCm,
%         sample.angleDeg
%
%   MURNI/headless (pola pab4Desc). Vertices di-cell-kan saat encode (round-trip
%   stabil). Penempatan: PAB/pivcore_lib/+pivcore/+io/pab4Interp.m

    methods (Static)

        % ================================================================
        function p = dataPath(dataFile)
        %DATAPATH  <dir>/<base>_faultinterp.json untuk MAT PIV dataFile.
            p = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_faultinterp.json', base));
        end

        function doc = emptyDoc(dataFile)
        %EMPTYDOC  Kerangka dokumen kosong.
            if nargin < 1, dataFile = ''; end
            [~, base, ext] = fileparts(char(dataFile));
            doc = struct();
            doc.formatName    = 'PAB4 Fault Interpolation Track';
            doc.formatVersion = 1;
            doc.source        = [base ext];
            doc.tracks        = {};   % cell of track-entry (JSON array)
        end

        function doc = read(dataFile)
        %READ  Baca & NORMALISASI sidecar. Tak ada berkas -> emptyDoc. Rusak ->
        %   emptyDoc + warning (tak melempar agar GUI tetap jalan).
            p = pivcore.io.pab4Interp.dataPath(dataFile);
            if isempty(p) || ~isfile(p)
                doc = pivcore.io.pab4Interp.emptyDoc(dataFile); return;
            end
            try
                txt = fileread(p);
                raw = jsondecode(txt);
            catch ME
                warning('pivcore:pab4Interp:read', ...
                    'Gagal membaca/parse %s (%s); pakai dokumen kosong.', p, ME.message);
                doc = pivcore.io.pab4Interp.emptyDoc(dataFile); return;
            end
            doc = pivcore.io.pab4Interp.normalizeDoc(raw, dataFile);
        end

        function write(dataFile, doc)
        %WRITE  Tulis dokumen ke `<base>_faultinterp.json` secara ATOMIC.
            p = pivcore.io.pab4Interp.dataPath(dataFile);
            if isempty(p)
                error('pivcore:pab4Interp:noPath', ...
                    'Tak bisa menentukan path _faultinterp untuk: %s', dataFile);
            end
            doc = pivcore.io.pab4Interp.prepForEncode(doc);
            txt = jsonencode(doc, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0
                error('pivcore:pab4Interp:open', 'Tak bisa membuka %s utk tulis.', tmp);
            end
            cleaner = onCleanup(@() pivcore.io.pab4Interp.cleanupTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
            fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok
                error('pivcore:pab4Interp:move', ...
                    'Gagal memindah tmp->final (%s): %s', p, msg);
            end
        end

        % ================================================================
        %                       INTI MATEMATIKA
        % ================================================================
        function V = lerpVerts(V0, V1, t)
        %LERPVERTS  Interpolasi linear vertex-per-vertex: (1-t)*V0 + t*V1. V0/V1 =
        %   Nx2 dgn JUMLAH VERTEX SAMA. Beda jumlah -> error (korespondensi wajib).
            V0 = pivcore.io.pab4Desc.normVerts(V0);
            V1 = pivcore.io.pab4Desc.normVerts(V1);
            if size(V0,1) < 1 || size(V0,1) ~= size(V1,1)
                error('pivcore:pab4Interp:vertexMismatch', ...
                    'lerpVerts: jumlah vertex harus sama (%d vs %d).', size(V0,1), size(V1,1));
            end
            t = double(t); if ~isscalar(t) || ~isfinite(t), t = 0; end
            t = max(0, min(1, t));
            V = (1-t).*V0 + t.*V1;
        end

        function [ok, msg, N] = validateKeyframes(kf)
        %VALIDATEKEYFRAMES  Cek kelayakan keyframe interpolasi. kf = struct array /
        %   cell (masing-masing .frame skalar & .vertices Nx2). Syarat: >=2 keyframe
        %   ber-frame BEDA & finite; SEMUA vertices jumlahnya SAMA (>=2). Kembalikan
        %   ok/pesan/N (jumlah vertex seragam; NaN bila gagal).
            ok = false; msg = ''; N = NaN;
            kf = pivcore.io.pab4Interp.tocell(kf);
            frames = []; counts = [];
            for k = 1:numel(kf)
                e = kf{k};
                if ~isstruct(e) || ~isfield(e,'frame') || ~isfield(e,'vertices'), continue; end
                f = pivcore.io.pab4Interp.scal(e.frame);
                V = pivcore.io.pab4Desc.normVerts(e.vertices);
                if ~isfinite(f) || size(V,1) < 2, continue; end
                frames(end+1) = round(f);          %#ok<AGROW>
                counts(end+1) = size(V,1);          %#ok<AGROW>
            end
            if numel(frames) < 2
                msg = 'Butuh >=2 keyframe ber-bidang sesar (mis. PRP-FSR + ACT-FSR).'; return;
            end
            if numel(unique(frames)) ~= numel(frames)
                msg = 'Keyframe punya frame kembar — tiap keyframe harus frame berbeda.'; return;
            end
            if numel(unique(counts)) ~= 1
                msg = sprintf(['Jumlah vertex antar-keyframe BEDA (%s). Interpolasi butuh ' ...
                    'jumlah SAMA — gambar ACT-FSR via Ctrl+Q (ter-seed/copy dari PRP-FSR) ' ...
                    'lalu geser vertex-nya.'], mat2str(unique(counts)));
                return;
            end
            ok = true; N = counts(1);
        end

        function samples = buildSamples(kf, cmPerPx, refDeg)
        %BUILDSAMPLES  Rakit track per-frame integer dari keyframe. kf = cell/struct
        %   array (.frame,.vertices). Untuk tiap frame f di [min..max] frame keyframe:
        %   cari pasangan keyframe pengapit -> lerp -> sample{frame,vertices,lenCm,
        %   angleDeg}. Frame == keyframe -> pakai vertex keyframe apa adanya. Melempar
        %   bila keyframe tak lolos validateKeyframes.
            if nargin < 2, cmPerPx = NaN; end
            if nargin < 3, refDeg = NaN; end
            [ok, msg] = pivcore.io.pab4Interp.validateKeyframes(kf);
            if ~ok, error('pivcore:pab4Interp:badKeyframes', '%s', msg); end
            kf = pivcore.io.pab4Interp.tocell(kf);
            % Susun (frame, V) valid & urutkan menaik.
            fr = []; VV = {};
            for k = 1:numel(kf)
                e = kf{k};
                if ~isstruct(e) || ~isfield(e,'frame') || ~isfield(e,'vertices'), continue; end
                f = pivcore.io.pab4Interp.scal(e.frame);
                V = pivcore.io.pab4Desc.normVerts(e.vertices);
                if ~isfinite(f) || size(V,1) < 2, continue; end
                fr(end+1) = round(f); VV{end+1} = V; %#ok<AGROW>
            end
            [fr, ord] = sort(fr); VV = VV(ord);
            samples = {};
            for f = fr(1):fr(end)
                % cari segmen j: fr(j) <= f <= fr(j+1)
                j = find(fr <= f, 1, 'last');
                if isempty(j), continue; end
                if fr(j) == f
                    V = VV{j};
                else
                    j2 = j + 1; if j2 > numel(fr), V = VV{j}; else
                        t = (f - fr(j)) / (fr(j2) - fr(j));
                        V = pivcore.io.pab4Interp.lerpVerts(VV{j}, VV{j2}, t);
                    end
                end
                lenCm = pivcore.io.pab4Desc.lenCmOf(V, cmPerPx);
                ang   = pivcore.io.pab4Desc.angleDegRelOf(V, refDeg);
                samples{end+1} = pivcore.io.pab4Interp.sampleStruct(f, V, lenCm, ang); %#ok<AGROW>
            end
        end

        % ================================================================
        %                       AKSES TRACK SIDECAR
        % ================================================================
        function s = sampleStruct(frame, vertices, lenCm, angleDeg)
        %SAMPLESTRUCT  Satu sample track per-frame.
            if nargin < 1, frame = NaN; end
            if nargin < 2, vertices = zeros(0,2); end
            if nargin < 3, lenCm = NaN; end
            if nargin < 4, angleDeg = NaN; end
            s = struct();
            s.frame    = pivcore.io.pab4Interp.scal(frame);
            s.vertices = pivcore.io.pab4Desc.normVerts(vertices);
            s.lenCm    = pivcore.io.pab4Interp.scal(lenCm);
            s.angleDeg = pivcore.io.pab4Interp.scal(angleDeg);
        end

        function e = trackFor(doc, psgId, fNum)
        %TRACKFOR  Entry track utk (psgId, F#). [] bila tak ada.
            e = [];
            if ~isstruct(doc) || ~isfield(doc,'tracks'), return; end
            all = pivcore.io.pab4Interp.tocell(doc.tracks);
            key = pivcore.io.pab4Interp.tostr(psgId);
            tgt = pivcore.io.pab4Interp.normFtag(fNum);
            for k = 1:numel(all)
                en = all{k};
                if ~isstruct(en), continue; end
                pk = ''; if isfield(en,'psgId'), pk = pivcore.io.pab4Interp.tostr(en.psgId); end
                fk = ''; if isfield(en,'fNum'),  fk = pivcore.io.pab4Interp.normFtag(en.fNum); end
                if strcmp(pk, key) && strcmp(fk, tgt), e = pivcore.io.pab4Interp.normEntry(en); return; end
            end
        end

        function doc = setTrackFor(doc, psgId, fNum, samples, keyFrames)
        %SETTRACKFOR  Set/replace track (psgId, F#) dgn samples (cell of sample) +
        %   keyFrames (opsional, daftar frame keyframe). Entry (psgId,F#) lain utuh.
            if ~isstruct(doc), doc = pivcore.io.pab4Interp.emptyDoc(''); end
            if ~isfield(doc,'tracks'), doc.tracks = {}; end
            if nargin < 5, keyFrames = []; end
            key = pivcore.io.pab4Interp.tostr(psgId);
            tgt = pivcore.io.pab4Interp.normFtag(fNum);
            all = pivcore.io.pab4Interp.tocell(doc.tracks);
            keep = {};
            for k = 1:numel(all)
                en = all{k};
                pk = ''; fk = '';
                if isstruct(en) && isfield(en,'psgId'), pk = pivcore.io.pab4Interp.tostr(en.psgId); end
                if isstruct(en) && isfield(en,'fNum'),  fk = pivcore.io.pab4Interp.normFtag(en.fNum); end
                if ~(strcmp(pk,key) && strcmp(fk,tgt)), keep{end+1} = en; end %#ok<AGROW>
            end
            entry = struct();
            entry.psgId     = key;
            entry.fNum      = ['F' tgt];
            entry.keyFrames = reshape(double(keyFrames),1,[]);
            sc = pivcore.io.pab4Interp.tocell(samples);
            for k = 1:numel(sc), sc{k} = pivcore.io.pab4Interp.normSample(sc{k}); end
            entry.samples   = sc;
            keep{end+1} = entry;
            doc.tracks = keep;
        end

        function doc = clearTrackFor(doc, psgId, fNum)
        %CLEARTRACKFOR  Buang track (psgId, F#).
            if ~isstruct(doc) || ~isfield(doc,'tracks'), return; end
            key = pivcore.io.pab4Interp.tostr(psgId);
            tgt = pivcore.io.pab4Interp.normFtag(fNum);
            all = pivcore.io.pab4Interp.tocell(doc.tracks);
            keep = {};
            for k = 1:numel(all)
                en = all{k};
                pk = ''; fk = '';
                if isstruct(en) && isfield(en,'psgId'), pk = pivcore.io.pab4Interp.tostr(en.psgId); end
                if isstruct(en) && isfield(en,'fNum'),  fk = pivcore.io.pab4Interp.normFtag(en.fNum); end
                if ~(strcmp(pk,key) && strcmp(fk,tgt)), keep{end+1} = en; end %#ok<AGROW>
            end
            doc.tracks = keep;
        end

        function V = vertsAtFrame(e, frame)
        %VERTSATFRAME  Vertices sample track pada `frame` (dari entry ter-materialisasi).
        %   0x2 bila tak ada.
            V = zeros(0,2);
            if ~isstruct(e) || ~isfield(e,'samples'), return; end
            f = round(pivcore.io.pab4Interp.scal(frame));
            sc = pivcore.io.pab4Interp.tocell(e.samples);
            for k = 1:numel(sc)
                s = pivcore.io.pab4Interp.normSample(sc{k});
                if isfinite(s.frame) && round(s.frame) == f
                    V = pivcore.io.pab4Desc.normVerts(s.vertices); return;
                end
            end
        end

        % ================================================================
        %                    NORMALISASI / ENCODE
        % ================================================================
        function doc = normalizeDoc(raw, dataFile)
            doc = pivcore.io.pab4Interp.emptyDoc(dataFile);
            if ~isstruct(raw), return; end
            if isfield(raw,'formatVersion') && isscalar(raw.formatVersion)
                doc.formatVersion = double(raw.formatVersion);
            end
            if isfield(raw,'source') && ischar(raw.source), doc.source = raw.source; end
            if isfield(raw,'tracks')
                tc = pivcore.io.pab4Interp.tocell(raw.tracks);
                out = {};
                for k = 1:numel(tc), out{end+1} = pivcore.io.pab4Interp.normEntry(tc{k}); end %#ok<AGROW>
                doc.tracks = out;
            end
        end

        function e = normEntry(s)
            e = struct('psgId','', 'fNum','', 'keyFrames',[], 'samples',{{}});
            if ~isstruct(s), return; end
            if isfield(s,'psgId'), e.psgId = pivcore.io.pab4Interp.tostr(s.psgId); end
            if isfield(s,'fNum'),  e.fNum  = ['F' pivcore.io.pab4Interp.normFtag(s.fNum)]; end
            if isfield(s,'keyFrames'), e.keyFrames = reshape(double(s.keyFrames),1,[]); end
            if isfield(s,'samples')
                sc = pivcore.io.pab4Interp.tocell(s.samples);
                for k = 1:numel(sc), sc{k} = pivcore.io.pab4Interp.normSample(sc{k}); end
                e.samples = sc;
            end
        end

        function s = normSample(x)
            s = pivcore.io.pab4Interp.sampleStruct();
            if ~isstruct(x), return; end
            if isfield(x,'frame'),    s.frame    = pivcore.io.pab4Interp.scal(x.frame); end
            if isfield(x,'vertices'), s.vertices = pivcore.io.pab4Desc.normVerts(x.vertices); end
            if isfield(x,'lenCm'),    s.lenCm    = pivcore.io.pab4Interp.scal(x.lenCm); end
            if isfield(x,'angleDeg'), s.angleDeg = pivcore.io.pab4Interp.scal(x.angleDeg); end
        end

        function doc = prepForEncode(doc)
        %PREPFORENCODE  vertices Nx2 -> cell-of-[x y] tiap sample (round-trip stabil).
            if ~isstruct(doc), doc = pivcore.io.pab4Interp.emptyDoc(''); end
            if ~isfield(doc,'tracks'), doc.tracks = {}; end
            all = pivcore.io.pab4Interp.tocell(doc.tracks);
            out = cell(1, numel(all));
            for k = 1:numel(all)
                en = pivcore.io.pab4Interp.normEntry(all{k});
                sc = pivcore.io.pab4Interp.tocell(en.samples);
                so = cell(1, numel(sc));
                for j = 1:numel(sc)
                    s = pivcore.io.pab4Interp.normSample(sc{j});
                    s.vertices = pivcore.io.pab4Desc.vertsToCell(s.vertices);
                    so{j} = s;
                end
                en.samples = so;
                out{k} = en;
            end
            doc.tracks = out;
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

        function t = normFtag(fNum)
        %NORMFTAG  'F3'/'3'/3 -> '3'. '' / tak dikenal -> ''.
            t = '';
            s = strtrim(pivcore.io.pab4Interp.tostr(fNum));
            if isempty(s), return; end
            s = regexprep(s, '^[Ff]', '');
            m = regexp(s, '\d+', 'match', 'once');
            if ~isempty(m), t = m; else, t = s; end
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
