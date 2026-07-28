classdef grain4PotData
%GRAIN4POTDATA  Kanal KUANTITATIF GRAIN4 — sidecar `<base>_potdata.json` (mesin-
%   readable, untuk Claude) di folder yang sama dgn MAT PIV. INI kebenaran milik
%   GRAIN4 (lihat GRAIN4_PLAN §3b). MAT PIV biner TIDAK disentuh.
%
%   Struktur BERPUSAT PADA GARIS PSG: akar punya array `psgLines[]`; tiap garis
%   ber-`id` STABIL (pivcore.pot.psgId) dan MEMBAWA kurva + net-slip + anotasinya
%   sendiri. SATU eksperimen = BANYAK garis. Membuka ulang garis yang sama ->
%   id sama -> kurva & catatan nyambung.
%
%   Satuan & tanda WAJIB eksplisit (output ilmiah ke Claude tak boleh ambigu):
%     units          'px/frame' | 'px/s' | 'cm/s' | ...   (pivcore.pot.units)
%     sampleRate     s/frame (NaN -> JSON null bila tak diketahui)
%     signConvention 'signed' | 'absolute'                (cermin toggle drift)
%
%   Penulisan WAJIB ATOMIC: tulis `<path>.tmp` lalu movefile ke nama final
%   (mencegah berkas korup bila proses terinterupsi di tengah tulis).
%
%   API:
%     p   = pivcore.io.grain4PotData.dataPath(dataFile)
%     doc = pivcore.io.grain4PotData.emptyDoc(dataFile)
%     doc = pivcore.io.grain4PotData.read(dataFile)        % [] -> emptyDoc bila tak ada
%     pivcore.io.grain4PotData.write(dataFile, doc)        % ATOMIC
%     ln  = pivcore.io.grain4PotData.lineStruct(id,p1,p2,frac,spacingPx)
%     c   = pivcore.io.grain4PotData.curveStruct(label,origin,values)
%     doc = pivcore.io.grain4PotData.upsertLine(doc, ln)   % ganti bila id sama, selain itu tambah
%     [ln,idx] = pivcore.io.grain4PotData.findLine(doc, id)
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivcore/+io/grain4PotData.m

    methods (Static)

        % ================================================================
        function p = dataPath(dataFile)
        %DATAPATH  <dir>/<base>_potdata.json untuk MAT PIV dataFile.
            p = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_potdata.json', base));
        end


        % ================================================================
        function doc = emptyDoc(dataFile, frames)
        %EMPTYDOC  Kerangka dokumen kosong (default satuan px/frame, signed).
            if nargin < 2, frames = NaN; end
            [~, base, ext] = fileparts(char(dataFile));
            doc = struct();
            doc.formatName    = 'GRAIN4 POT Data';
            doc.formatVersion = 1;
            doc.source        = [base ext];
            doc.meta          = struct('frames', frames, 'basename', base);
            doc.units         = 'px/frame';
            doc.sampleRate    = NaN;          % -> JSON null
            doc.signConvention= 'signed';
            doc.indenter      = [];
            doc.viewSettings  = struct();     % setting tampilan tersimpan (clim/glyph/skala/tebal)
            doc.psgLines      = {};           % cell of line-structs (JSON array)
        end


        % ================================================================
        function doc = read(dataFile)
        %READ  Baca & NORMALISASI sidecar. Tak ada berkas -> emptyDoc. Berkas
        %   rusak -> emptyDoc + warning (tak melempar, agar GUI tetap jalan).
            p = pivcore.io.grain4PotData.dataPath(dataFile);
            if isempty(p) || ~isfile(p)
                doc = pivcore.io.grain4PotData.emptyDoc(dataFile); return;
            end
            try
                txt = fileread(p);
                raw = jsondecode(txt);
            catch ME
                warning('pivcore:grain4PotData:read', ...
                    'Gagal membaca/parse %s (%s); pakai dokumen kosong.', p, ME.message);
                doc = pivcore.io.grain4PotData.emptyDoc(dataFile); return;
            end
            doc = pivcore.io.grain4PotData.normalizeDoc(raw, dataFile);
        end


        % ================================================================
        function write(dataFile, doc)
        %WRITE  Tulis dokumen ke `<base>_potdata.json` secara ATOMIC.
            p = pivcore.io.grain4PotData.dataPath(dataFile);
            if isempty(p)
                error('pivcore:grain4PotData:noPath', ...
                    'Tak bisa menentukan path _potdata untuk: %s', dataFile);
            end
            doc = pivcore.io.grain4PotData.prepForEncode(doc);
            txt = jsonencode(doc, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0
                error('pivcore:grain4PotData:open', 'Tak bisa membuka %s utk tulis.', tmp);
            end
            cleaner = onCleanup(@() pivcore.io.grain4PotData.cleanupTmp(tmp));
            fwrite(fid, txt, 'char');
            fclose(fid);
            % movefile menimpa final secara atomik (rename pada FS yang sama).
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok
                error('pivcore:grain4PotData:move', ...
                    'Gagal memindah tmp->final (%s): %s', p, msg);
            end
        end


        % ================================================================
        function ln = lineStruct(id, p1, p2, frac, spacingPx)
        %LINESTRUCT  Skeleton satu garis PSG (kurva/netslip/anotasi kosong).
            if nargin < 4, frac = NaN; end
            if nargin < 5, spacingPx = NaN; end
            ln = struct();
            ln.id        = char(id);
            ln.p1        = pivcore.io.grain4PotData.row2(p1);
            ln.p2        = pivcore.io.grain4PotData.row2(p2);
            ln.frac      = pivcore.io.grain4PotData.scal(frac);
            ln.spacingPx = pivcore.io.grain4PotData.scal(spacingPx);
            ln.curves    = {};
            ln.netslip   = {};
            ln.annotations = struct('lines',{{}}, 'points',{{}}, 'measures',{{}});
        end


        % ================================================================
        function c = curveStruct(label, origin, values, cutFrame, excluded)
        %CURVESTRUCT  Skeleton satu kurva POT (label HW/F/..., origin, deret,
        %   cutFrame trim opsional -> NaN bila tak ter-trim; excluded = kurva
        %   dibuang dari analisis -> false bila tidak).
            if nargin < 4, cutFrame = NaN; end
            if nargin < 5, excluded = false; end
            c = struct('label', char(label), ...
                       'origin', pivcore.io.grain4PotData.row2(origin), ...
                       'values', pivcore.io.grain4PotData.rowv(values), ...
                       'cutFrame', pivcore.io.grain4PotData.scal(cutFrame), ...
                       'excluded', logical(excluded));
        end


        % ================================================================
        function cv = curvesFromRecs(recs, nF)
        %CURVESFROMRECS  Ubah array record POT (h.recs) -> cell curveStruct
        %   (label = assignLabel bila ada, selain itu .point; origin; deret
        %   tampil via records.curveXY). Dipakai 4A/4B saat menulis _potdata.json.
            cv = {};
            if isempty(recs), return; end
            for r = 1:numel(recs)
                lab = pivcore.pot.records.label(recs(r));
                if isempty(lab)
                    if isfield(recs(r),'point') && ~isempty(recs(r).point)
                        lab = recs(r).point;
                    else
                        lab = sprintf('P-%d', r);
                    end
                end
                org = [NaN NaN];
                if isfield(recs(r),'origin'), org = recs(r).origin; end
                [~, yv] = pivcore.pot.records.curveXY(recs(r), nF);
                cf = NaN;
                if isfield(recs(r),'cutManual') && isscalar(recs(r).cutManual) && recs(r).cutManual ...
                        && isfield(recs(r),'cutFrame') && isscalar(recs(r).cutFrame)
                    cf = recs(r).cutFrame;
                end
                ex = isfield(recs(r),'excluded') && isscalar(recs(r).excluded) && logical(recs(r).excluded);
                cv{end+1} = pivcore.io.grain4PotData.curveStruct(lab, org, yv, cf, ex); %#ok<AGROW>
            end
        end


        % ================================================================
        function [ln, idx] = findLine(doc, id)
        %FINDLINE  Cari garis ber-id. idx=0 & ln=[] bila tak ada.
            ln = []; idx = 0;
            if ~isstruct(doc) || ~isfield(doc,'psgLines'), return; end
            L = doc.psgLines;
            for k = 1:numel(L)
                lk = L{k};
                if isstruct(lk) && isfield(lk,'id') && strcmp(lk.id, id)
                    ln = lk; idx = k; return;
                end
            end
        end


        % ================================================================
        function doc = upsertLine(doc, ln)
        %UPSERTLINE  Sisipkan/ganti garis ber-id sama (id = kunci stabil).
            if ~isstruct(doc), doc = pivcore.io.grain4PotData.emptyDoc(''); end
            if ~isfield(doc,'psgLines') || ~iscell(doc.psgLines), doc.psgLines = {}; end
            [~, idx] = pivcore.io.grain4PotData.findLine(doc, ln.id);
            if idx > 0
                doc.psgLines{idx} = ln;
            else
                doc.psgLines{end+1} = ln;
            end
        end


        % ================================================================
        function doc = removeLine(doc, id)
        %REMOVELINE  Buang garis ber-id (no-op bila tak ada).
            [~, idx] = pivcore.io.grain4PotData.findLine(doc, id);
            if idx > 0, doc.psgLines(idx) = []; end
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function doc = normalizeDoc(raw, dataFile)
        %NORMALIZEDOC  Rapikan hasil jsondecode -> dokumen kanonik (psgLines =
        %   cell of struct; p1/p2 baris; lists = cell). Field hilang diisi default.
            d = pivcore.io.grain4PotData.emptyDoc(dataFile);
            if ~isstruct(raw), doc = d; return; end
            doc = d;
            for fn = {'formatName','formatVersion','source','units', ...
                      'signConvention','sampleRate','indenter','viewSettings'}
                k = fn{1};
                if isfield(raw, k), doc.(k) = raw.(k); end
            end
            if isfield(raw,'meta') && isstruct(raw.meta)
                if isfield(raw.meta,'frames'),   doc.meta.frames   = raw.meta.frames; end
                if isfield(raw.meta,'basename'), doc.meta.basename = raw.meta.basename; end
            end
            if isfield(doc,'indenter'), doc.indenter = pivcore.io.grain4PotData.rowv(doc.indenter); end
            % JSON null -> [] saat decode; sampleRate kanonik = skalar (NaN bila null).
            if ~isscalar(doc.sampleRate) || ~isnumeric(doc.sampleRate), doc.sampleRate = NaN; end
            % psgLines -> cell of normalized line struct.
            lines = {};
            if isfield(raw,'psgLines')
                src = pivcore.io.grain4PotData.tocell(raw.psgLines);
                for k = 1:numel(src)
                    lines{end+1} = pivcore.io.grain4PotData.normLine(src{k}); %#ok<AGROW>
                end
            end
            doc.psgLines = lines;
        end


        function ln = normLine(s)
        %NORMLINE  Satu garis dari decode -> struktur kanonik.
            ln = pivcore.io.grain4PotData.lineStruct('', [NaN NaN], [NaN NaN], NaN, NaN);
            if ~isstruct(s), return; end
            if isfield(s,'id'),        ln.id        = char(s.id); end
            if isfield(s,'p1'),        ln.p1        = pivcore.io.grain4PotData.row2(s.p1); end
            if isfield(s,'p2'),        ln.p2        = pivcore.io.grain4PotData.row2(s.p2); end
            if isfield(s,'frac'),      ln.frac      = pivcore.io.grain4PotData.scal(s.frac); end
            if isfield(s,'spacingPx'), ln.spacingPx = pivcore.io.grain4PotData.scal(s.spacingPx); end
            if isfield(s,'curves'),    ln.curves    = pivcore.io.grain4PotData.normCurves(s.curves); end
            if isfield(s,'netslip'),   ln.netslip   = pivcore.io.grain4PotData.tocell(s.netslip); end
            if isfield(s,'annotations') && isstruct(s.annotations)
                a = s.annotations;
                if isfield(a,'lines'),    ln.annotations.lines    = pivcore.io.grain4PotData.tocell(a.lines); end
                if isfield(a,'points'),   ln.annotations.points   = pivcore.io.grain4PotData.tocell(a.points); end
                if isfield(a,'measures'), ln.annotations.measures = pivcore.io.grain4PotData.tocell(a.measures); end
            end
        end


        function cv = normCurves(c)
            src = pivcore.io.grain4PotData.tocell(c);
            cv = {};
            for k = 1:numel(src)
                s = src{k};
                if ~isstruct(s), continue; end
                lab = ''; org = [NaN NaN]; val = []; cf = NaN; ex = false;
                if isfield(s,'label'),    lab = char(s.label); end
                if isfield(s,'origin'),   org = pivcore.io.grain4PotData.row2(s.origin); end
                if isfield(s,'values'),   val = pivcore.io.grain4PotData.rowv(s.values); end
                if isfield(s,'cutFrame'), cf  = pivcore.io.grain4PotData.scal(s.cutFrame); end
                if isfield(s,'excluded'), ex  = isscalar(s.excluded) && logical(s.excluded); end
                cv{end+1} = pivcore.io.grain4PotData.curveStruct(lab, org, val, cf, ex); %#ok<AGROW>
            end
        end


        function doc = prepForEncode(doc)
        %PREPFORENCODE  Pastikan field minimal ADA & lists = cell (cell kosong
        %   -> JSON []). Tak mengubah nilai numerik (NaN -> null oleh jsonencode).
            d = pivcore.io.grain4PotData.emptyDoc('');
            fn = fieldnames(d);
            for i = 1:numel(fn)
                if ~isfield(doc, fn{i}), doc.(fn{i}) = d.(fn{i}); end
            end
            if ~iscell(doc.psgLines)
                doc.psgLines = pivcore.io.grain4PotData.tocell(doc.psgLines);
            end
            % Pastikan tiap garis punya lists cell (agar JSON array, bukan objek).
            for k = 1:numel(doc.psgLines)
                ln = doc.psgLines{k};
                if ~isfield(ln,'curves')  || ~iscell(ln.curves),  ln.curves  = {}; end
                if ~isfield(ln,'netslip') || ~iscell(ln.netslip), ln.netslip = {}; end
                if ~isfield(ln,'annotations') || ~isstruct(ln.annotations)
                    ln.annotations = struct('lines',{{}},'points',{{}},'measures',{{}});
                end
                doc.psgLines{k} = ln;
            end
        end


        % --- helper tipe ---------------------------------------------
        function c = tocell(x)
        %TOCELL  Apa pun (struct-array / cell / kosong) -> cell baris.
            if isempty(x), c = {}; return; end
            if iscell(x), c = reshape(x, 1, []); return; end
            if isstruct(x)
                c = cell(1, numel(x));
                for k = 1:numel(x), c{k} = x(k); end
                return;
            end
            c = {x};
        end

        function v = row2(p)
        %ROW2  Paksa ke baris 1x2 (NaN bila tak lengkap).
            p = double(p(:)).';
            if numel(p) >= 2, v = p(1:2); else, v = [NaN NaN]; end
        end

        function v = rowv(x)
        %ROWV  Paksa ke vektor baris double ([] tetap []).
            if isempty(x), v = []; return; end
            v = double(x(:)).';
        end

        function v = scal(x)
        %SCAL  Skalar double (NaN bila tak skalar).
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end

        function cleanupTmp(tmp)
            try, if isfile(tmp), delete(tmp); end, catch, end
        end

    end
end
