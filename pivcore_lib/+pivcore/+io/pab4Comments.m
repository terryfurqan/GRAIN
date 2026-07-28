classdef pab4Comments
%PAB4COMMENTS  Kanal KOMENTAR PAB4A — sidecar `<base>_comments.json` (mesin-
%   readable) + bundel folder `PAB4_claude/` untuk Claude membuat laporan.
%
%   Tiap KOMENTAR menautkan: nomor frame, garis PSG (psgId), KURVA aktif/terpilih
%   (label/point), teks, peran (USER/CLAUDE), dan 3 GAMBAR terlampir
%   (vel mag / shear strain / axPOT). Balasan Claude = komentar peran CLAUDE
%   (di GUI ditandai prefiks "[CLAUDE]: "), BUKAN kolom terpisah.
%
%   SKEMA (akar):
%     formatName='PAB4 Comments'; formatVersion=1; source=<base.ext>;
%     comments[] : { id, time, role, frame, psgId, curve, text,
%                    images:{velmag,shear,axpot} }
%
%   Penulisan ATOMIC (tmp->movefile). NaN/'' aman. Kebenaran per-eksperimen di
%   `<base>_comments.json` (di samping .mat, untuk reload GUI). "Export untuk
%   Claude" menyalin json + gambar ke `PAB4_claude/<base>/` + README pengarah.
%
%   API:
%     p   = pivcore.io.pab4Comments.dataPath(dataFile)
%     d   = pivcore.io.pab4Comments.assetDir(dataFile)     % PAB4_claude/<base>/
%     doc = pivcore.io.pab4Comments.emptyDoc(dataFile)
%     doc = pivcore.io.pab4Comments.read(dataFile)
%     pivcore.io.pab4Comments.write(dataFile, doc)         % ATOMIC
%     c          = pivcore.io.pab4Comments.commentStruct(frame,psgId,curve,text,role)
%     [doc, id]  = pivcore.io.pab4Comments.add(doc, c)     % beri id+time, append
%     doc = pivcore.io.pab4Comments.setImages(doc, id, images)
%     doc = pivcore.io.pab4Comments.remove(doc, id)
%     R   = pivcore.io.pab4Comments.tableRows(doc)         % {no,frame,kurva,teks}
%     [folder, n] = pivcore.io.pab4Comments.exportClaude(dataFile, doc)
%
%   Penempatan berkas: PAB/pivcore_lib/+pivcore/+io/pab4Comments.m

    methods (Static)

        % ================================================================
        function p = dataPath(dataFile)
            p = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_comments.json', base));
        end


        function d = assetDir(dataFile)
        %ASSETDIR  Folder bundel Claude untuk eksperimen ini: <dir>/PAB4_claude/<base>/
            d = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [dd, base] = fileparts(dataFile);
            if isempty(dd), dd = pwd; end
            d = fullfile(dd, 'PAB4_claude', base);
        end


        function d = claudeRoot(dataFile)
        %CLAUDEROOT  Folder bundel induk: <dir>/PAB4_claude/
            d = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            dd = fileparts(dataFile); if isempty(dd), dd = pwd; end
            d = fullfile(dd, 'PAB4_claude');
        end


        % ================================================================
        function doc = emptyDoc(dataFile)
            [~, base, ext] = fileparts(char(dataFile));
            doc = struct();
            doc.formatName    = 'PAB4 Comments';
            doc.formatVersion = 1;
            doc.source        = [base ext];
            doc.comments      = {};
        end


        % ================================================================
        function doc = read(dataFile)
            p = pivcore.io.pab4Comments.dataPath(dataFile);
            if isempty(p) || ~isfile(p)
                doc = pivcore.io.pab4Comments.emptyDoc(dataFile); return;
            end
            try
                raw = jsondecode(fileread(p));
            catch ME
                warning('pivcore:pab4Comments:read', ...
                    'Gagal baca/parse %s (%s); pakai kosong.', p, ME.message);
                doc = pivcore.io.pab4Comments.emptyDoc(dataFile); return;
            end
            doc = pivcore.io.pab4Comments.normalizeDoc(raw, dataFile);
        end


        % ================================================================
        function write(dataFile, doc)
            p = pivcore.io.pab4Comments.dataPath(dataFile);
            if isempty(p)
                error('pivcore:pab4Comments:noPath','Tak bisa tentukan path comments: %s', dataFile);
            end
            doc = pivcore.io.pab4Comments.prepForEncode(doc);
            txt = jsonencode(doc, 'PrettyPrint', true);
            pivcore.io.pab4Comments.atomicWrite(p, txt);
        end


        % ================================================================
        function c = commentStruct(frame, psgId, curve, text, role, refs)
        %COMMENTSTRUCT  Skeleton satu komentar (tanpa id/time; diisi oleh add).
        %   refs (opsional) = struct referensi terstruktur mesin-readable
        %   (exp/psg/curve/frame/strainPct/posPx/...) untuk ekspor ke Claude.
            if nargin < 5 || isempty(role), role = 'USER'; end
            if nargin < 6 || ~isstruct(refs), refs = struct(); end
            c = struct();
            c.id     = '';
            c.time   = '';
            c.role   = upper(char(role));
            c.frame  = pivcore.io.pab4Comments.scal(frame);
            c.psgId  = char(psgId);
            c.curve  = char(curve);
            c.text   = pivcore.io.pab4Comments.cleanText(text);
            c.images = struct('velmag','', 'shear','', 'axpot','');
            c.refs   = refs;
            c.assets = {};   % gambar ber-spec (tab ④ Produksi Gambar); lihat pab4Shots
        end


        % ================================================================
        function [doc, id] = add(doc, c)
        %ADD  Beri id stabil ('c<seq>') + timestamp, lalu append ke doc.comments.
            if ~isstruct(doc) || ~isfield(doc,'comments') || ~iscell(doc.comments)
                doc = pivcore.io.pab4Comments.emptyDoc('');
            end
            seq = pivcore.io.pab4Comments.nextSeq(doc);
            id  = sprintf('c%03d', seq);
            c.id = id;
            if ~isfield(c,'time') || isempty(c.time)
                c.time = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<DATST,TNOW1>
            end
            c = pivcore.io.pab4Comments.normComment(c);
            doc.comments{end+1} = c;
        end


        % ================================================================
        function doc = setImages(doc, id, images)
        %SETIMAGES  Lampirkan nama berkas gambar (relatif) ke komentar id.
            idx = pivcore.io.pab4Comments.findIdx(doc, id);
            if idx < 1, return; end
            c = doc.comments{idx};
            for fn = {'velmag','shear','axpot'}
                k = fn{1};
                if isfield(images, k) && ~isempty(images.(k))
                    c.images.(k) = char(images.(k));
                end
            end
            doc.comments{idx} = c;
        end


        % ================================================================
        function doc = setAssets(doc, id, assets)
        %SETASSETS  Pasang daftar asset ber-spec (cell of struct) ke komentar id.
        %   assets dibuat via pivcore.io.pab4Shots.assetStruct (kind/file/spec/
        %   fingerprint/producedAt). Menimpa daftar lama komentar tsb.
            idx = pivcore.io.pab4Comments.findIdx(doc, id);
            if idx < 1, return; end
            c = doc.comments{idx};
            if ~iscell(assets), assets = pivcore.io.pab4Comments.tocell(assets); end
            c.assets = assets;
            doc.comments{idx} = c;
        end


        function doc = remove(doc, id)
            idx = pivcore.io.pab4Comments.findIdx(doc, id);
            if idx >= 1, doc.comments(idx) = []; end
        end


        function [c, idx] = find(doc, id)
            idx = pivcore.io.pab4Comments.findIdx(doc, id);
            if idx >= 1, c = doc.comments{idx}; else, c = []; end
        end


        % ================================================================
        function R = tableRows(doc)
        %TABLEROWS  -> cell {no, frame, kurva, teks}. Teks peran CLAUDE diberi
        %   prefiks "[CLAUDE]: " (balasan inline, bukan kolom terpisah).
            R = cell(0,4);
            if ~isstruct(doc) || ~isfield(doc,'comments'), return; end
            C = doc.comments; n = numel(C); R = cell(n,4);
            for k = 1:n
                c = C{k};
                fr = ''; if isfield(c,'frame') && isscalar(c.frame) && isfinite(c.frame)
                    fr = sprintf('%d', round(c.frame)); end
                cu = ''; if isfield(c,'curve'), cu = char(c.curve); end
                tx = ''; if isfield(c,'text'),  tx = char(c.text); end
                if isfield(c,'role') && strcmpi(c.role,'CLAUDE'), tx = ['[CLAUDE]: ' tx]; end
                hasImg = isfield(c,'images') && pivcore.io.pab4Comments.anyImage(c.images);
                if hasImg, tx = ['📎 ' tx]; end
                tx = regexprep(tx, '\s+', ' ');
                R{k,1} = k; R{k,2} = fr; R{k,3} = cu; R{k,4} = tx;
            end
        end


        % ================================================================
        function [folder, n] = exportClaude(dataFile, doc)
        %EXPORTCLAUDE  Bundel komentar + gambar eksperimen ini ke
        %   PAB4_claude/<base>/ (comments.json + gambar) + tulis ulang
        %   PAB4_claude/READ_ME_CLAUDE.md (pengarah pembuatan laporan).
            folder = pivcore.io.pab4Comments.assetDir(dataFile);
            n = 0;
            if isempty(folder), return; end
            if ~isfolder(folder), mkdir(folder); end
            % 1) salin/tulis comments.json kanonik ke bundel
            txt = jsonencode(pivcore.io.pab4Comments.prepForEncode(doc), 'PrettyPrint', true);
            pivcore.io.pab4Comments.atomicWrite(fullfile(folder,'comments.json'), txt);
            % 2) salin gambar terlampir (bila ada di assetDir; Export-3 menulis ke sana)
            if isfield(doc,'comments')
                for k = 1:numel(doc.comments)
                    im = doc.comments{k}.images;
                    for fn = {'velmag','shear','axpot'}
                        f = im.(fn{1});
                        if ~isempty(f) && isfile(fullfile(folder,f)), n = n + 1; end
                    end
                end
            end
            % 2b) layout PER-KOMENTAR: comments/<id>/comment.json + PNG ber-spec.
            %     PNG sudah ditulis tab ④ langsung ke folder ini; di sini kita
            %     tulis comment.json per folder (komentar + assets + render-spec).
            if isfield(doc,'comments')
                for k = 1:numel(doc.comments)
                    c = doc.comments{k};
                    if ~isfield(c,'assets') || isempty(c.assets), continue; end
                    cdir = pivcore.io.pab4Shots.commentDir(dataFile, c.id);
                    if isempty(cdir), continue; end
                    if ~isfolder(cdir), mkdir(cdir); end
                    ctxt = jsonencode(c, 'PrettyPrint', true);
                    pivcore.io.pab4Comments.atomicWrite(fullfile(cdir,'comment.json'), ctxt);
                    for a = 1:numel(c.assets)
                        as = c.assets{a};
                        if isstruct(as) && isfield(as,'file') && ~isempty(as.file) ...
                                && isfile(fullfile(cdir, as.file)), n = n + 1; end
                    end
                end
            end
            % 3) (re)tulis pengarah Claude tingkat folder
            pivcore.io.pab4Comments.writeClaudeReadme(dataFile);
            % 4) GUARD KONSISTENSI: registry (assets[]) <-> file fisik + fingerprint.
            %    Tutup masalah desync §2 secara OTOMATIS tiap ekspor; tulis ringkasan
            %    _HANDSHAKE.md (status untuk CLCW + peneliti).
            pivcore.io.pab4Comments.verifyBundle(dataFile, doc);
        end


        function rep = verifyBundle(dataFile, doc)
        %VERIFYBUNDLE  Cek konsistensi bundel PAB4_claude/<base>/: tiap asset
        %   terdaftar punya FILE, tiap PNG punya ENTRY, fingerprint asset PADAN
        %   dengan fingerprint dari spec-nya. Murni/headless, deterministik —
        %   tak melibatkan CLCW. Mengembalikan struct laporan + menulis
        %   _HANDSHAKE.md ke bundel. (dataFile, doc) — doc opsional (dibaca bila kosong).
            if nargin < 2 || ~isstruct(doc), doc = pivcore.io.pab4Comments.read(dataFile); end
            folder = pivcore.io.pab4Comments.assetDir(dataFile);
            rep = struct('ok',true, 'nComments',0, 'nAssets',0, ...
                'missingFiles',{{}}, 'orphanFiles',{{}}, 'fpMismatch',{{}});
            if isempty(folder) || ~isfolder(folder), rep.ok = false; return; end
            comments = {};
            if isstruct(doc) && isfield(doc,'comments'), comments = doc.comments; end
            rep.nComments = numel(comments);
            for k = 1:numel(comments)
                c = comments{k};
                if ~isstruct(c) || ~isfield(c,'id'), continue; end
                cid  = char(c.id);
                cdir = pivcore.io.pab4Shots.commentDir(dataFile, cid);
                assets = {};
                if isfield(c,'assets') && ~isempty(c.assets)
                    assets = pivcore.io.pab4Comments.tocell(c.assets);
                end
                % (a) tiap asset terdaftar -> file ADA + fingerprint PADAN spec
                declared = {};
                for a = 1:numel(assets)
                    as = assets{a};
                    if ~isstruct(as) || ~isfield(as,'file') || isempty(as.file), continue; end
                    rep.nAssets = rep.nAssets + 1;
                    f = char(as.file); declared{end+1} = f; %#ok<AGROW>
                    if isempty(cdir) || ~isfile(fullfile(cdir, f))
                        rep.missingFiles{end+1} = sprintf('%s/%s', cid, f); %#ok<AGROW>
                        rep.ok = false;
                    end
                    if isfield(as,'fingerprint') && isfield(as,'spec') && isstruct(as.spec)
                        want = pivcore.io.pab4Shots.fingerprint(as.spec);
                        if ~strcmp(char(as.fingerprint), want)
                            rep.fpMismatch{end+1} = sprintf('%s/%s (asset=%s spec=%s)', ...
                                cid, f, char(as.fingerprint), want); %#ok<AGROW>
                            rep.ok = false;
                        end
                    end
                end
                % (b) tiap PNG di folder komentar -> TERDAFTAR (cegah yatim)
                if ~isempty(cdir) && isfolder(cdir)
                    dd = dir(fullfile(cdir, '*.png'));
                    for j = 1:numel(dd)
                        if ~ismember(dd(j).name, declared)
                            rep.orphanFiles{end+1} = sprintf('%s/%s', cid, dd(j).name); %#ok<AGROW>
                            rep.ok = false;
                        end
                    end
                end
            end
            pivcore.io.pab4Comments.writeHandshake(folder, rep);
        end


        function writeHandshake(folder, rep)
        %WRITEHANDSHAKE  Ringkasan status konsistensi bundel -> <folder>/_HANDSHAKE.md.
        %   Dibaca CLCW (Cowork) untuk tahu bundel SIAP/ tidak sebelum melapor.
            if isempty(folder) || ~isfolder(folder), return; end
            L = {};
            if rep.ok, st = '✅ SINKRON — registry↔file konsisten, fingerprint padan.';
            else,      st = '⚠️ DESYNC — JANGAN dipakai melapor sampai diperbaiki (re-export).'; end
            L{end+1} = '# PAB4 — Status Jabat-Tangan Bundel (CLCC → CLCW)';
            L{end+1} = '';
            L{end+1} = st;
            L{end+1} = '';
            L{end+1} = sprintf('- Komentar: %d · Asset terdaftar: %d', rep.nComments, rep.nAssets);
            L{end+1} = sprintf('- Asset tanpa file (over-claim): %d', numel(rep.missingFiles));
            for s = rep.missingFiles, L{end+1} = sprintf('  - ❌ %s', s{1}); end %#ok<AGROW>
            L{end+1} = sprintf('- PNG tak terdaftar (yatim): %d', numel(rep.orphanFiles));
            for s = rep.orphanFiles, L{end+1} = sprintf('  - ❌ %s', s{1}); end %#ok<AGROW>
            L{end+1} = sprintf('- Fingerprint tak padan: %d', numel(rep.fpMismatch));
            for s = rep.fpMismatch, L{end+1} = sprintf('  - ❌ %s', s{1}); end %#ok<AGROW>
            L{end+1} = '';
            L{end+1} = '> Konvensi CLCW: saat melapor, sebut jumlah asset per komentar + fingerprint';
            L{end+1} = '> yang dibaca, agar CLCC bisa konfirmasi kamu memakai versi data terkini.';
            pivcore.io.pab4Comments.atomicWrite(fullfile(folder,'_HANDSHAKE.md'), strjoin(L, newline));
        end


        function writeClaudeReadme(dataFile)
        %WRITECLAUDEREADME  Tulis PAB4_claude/READ_ME_CLAUDE.md: indeks bundel +
        %   instruksi agar Claude membaca semua comments.json lalu menulis REPORT.md.
            root = pivcore.io.pab4Comments.claudeRoot(dataFile);
            if isempty(root), return; end
            if ~isfolder(root), mkdir(root); end
            subs = pivcore.io.pab4Comments.listBundles(root);
            L = {};
            L{end+1} = '# PAB4 — Berkas untuk Claude (deskripsi & interpretasi terhimpun)';
            L{end+1} = '';
            L{end+1} = 'Folder ini berisi komentar peneliti + gambar PIV (vel mag / shear / axPOT)';
            L{end+1} = 'per eksperimen. TUGAS Claude:';
            L{end+1} = '0. **Cek `<base>/_HANDSHAKE.md` DULU.** Bila statusnya ⚠️ DESYNC, JANGAN';
            L{end+1} = '   melapor — minta CLCC (Claude Code) re-export. Lapor HANYA atas bundel ✅ SINKRON.';
            L{end+1} = '1. Baca tiap `*/comments.json` (skema PAB4 Comments).';
            L{end+1} = '2. Buka gambar `velmag/shear/axpot` yang dirujuk tiap komentar.';
            L{end+1} = '2b. Baca `<base>/curves.json` untuk DATA NUMERIK kurva HW teridentifikasi';
            L{end+1} = '    (nilai |V| per-frame, puncak, cutFrame, net-slip start/nuc/fsr/end/area/dNet)';
            L{end+1} = '    -> tautkan tiap `@curve:HW-N` di komentar ke ANGKA-nya (konteks kuantitatif).';
            L{end+1} = '2c. **`<base>/hw_story.json` = PAKET CERITA ber-anchor HW** (bila ada): tiap';
            L{end+1} = '    HW = 1 gambar axPOT (`HW/HW-N_axpot.png`) + kurva + titik observasi';
            L{end+1} = '    (nukleasi→akhir) + net-slip + komentar tertaut. **Bercerita PER-HW dari';
            L{end+1} = '    sini** — HW adalah titik ikat narasi sesar (thrust). Tak perlu data raw.';
            L{end+1} = '3. Sintesiskan deskripsi + interpretasi menjadi `REPORT.md` di folder ini.';
            L{end+1} = '4. (Opsional) tulis balasan per-komentar ke `<base>_comments.json`';
            L{end+1} = '   sebagai komentar baru `role:"CLAUDE"` (frame/psgId/curve sama).';
            L{end+1} = '';
            L{end+1} = '## Gambar ber-spec (tab ④ Produksi Gambar)';
            L{end+1} = 'Tiap eksperimen punya `<base>/comments/<id>/` = SATU folder per komentar';
            L{end+1} = 'berisi PNG + `comment.json`. Tiap PNG punya `assets[].spec` (apa yang';
            L{end+1} = 'ditampilkan: panel, frame, garis PSG, kurva HW, titik) + `fingerprint`';
            L{end+1} = '(deteksi BASI bila data berubah) + `producedAt`. **Gambar selalu padan';
            L{end+1} = 'dengan spec/tag** — percayai spec saat membaca PNG. CLim terkunci ada di';
            L{end+1} = '`<base>/manifest.json` (skala sama semua gambar eksperimen).';
            L{end+1} = '';
            L{end+1} = '## Bundel eksperimen';
            if isempty(subs)
                L{end+1} = '_(belum ada)_';
            else
                for i = 1:numel(subs)
                    L{end+1} = sprintf('- `%s/comments.json`', subs{i}); %#ok<AGROW>
                end
            end
            L{end+1} = '';
            pivcore.io.pab4Comments.atomicWrite(fullfile(root,'READ_ME_CLAUDE.md'), ...
                strjoin(L, newline));
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function subs = listBundles(root)
            subs = {};
            d = dir(root);
            for k = 1:numel(d)
                if d(k).isdir && ~ismember(d(k).name, {'.','..'}) ...
                        && isfile(fullfile(root, d(k).name, 'comments.json'))
                    subs{end+1} = d(k).name; %#ok<AGROW>
                end
            end
        end


        function tf = anyImage(images)
            tf = false;
            if ~isstruct(images), return; end
            for fn = {'velmag','shear','axpot'}
                if isfield(images, fn{1}) && ~isempty(images.(fn{1})), tf = true; return; end
            end
        end


        function s = nextSeq(doc)
            s = 1;
            if ~isfield(doc,'comments'), return; end
            for k = 1:numel(doc.comments)
                c = doc.comments{k};
                if isstruct(c) && isfield(c,'id')
                    t = regexp(char(c.id), '^c(\d+)$', 'tokens', 'once');
                    if ~isempty(t), s = max(s, str2double(t{1})+1); end
                end
            end
        end


        function idx = findIdx(doc, id)
            idx = 0;
            if ~isstruct(doc) || ~isfield(doc,'comments'), return; end
            for k = 1:numel(doc.comments)
                c = doc.comments{k};
                if isstruct(c) && isfield(c,'id') && strcmp(char(c.id), char(id))
                    idx = k; return;
                end
            end
        end


        function doc = normalizeDoc(raw, dataFile)
            doc = pivcore.io.pab4Comments.emptyDoc(dataFile);
            if ~isstruct(raw), return; end
            for fn = {'formatName','formatVersion','source'}
                if isfield(raw, fn{1}), doc.(fn{1}) = raw.(fn{1}); end
            end
            C = {};
            if isfield(raw,'comments')
                src = pivcore.io.pab4Comments.tocell(raw.comments);
                for k = 1:numel(src)
                    C{end+1} = pivcore.io.pab4Comments.normComment(src{k}); %#ok<AGROW>
                end
            end
            doc.comments = C;
        end


        function c = normComment(s)
            c = struct('id','', 'time','', 'role','USER', 'frame',NaN, ...
                       'psgId','', 'curve','', 'text','', ...
                       'images',struct('velmag','','shear','','axpot',''), ...
                       'refs',struct(), 'assets',{{}});
            if ~isstruct(s), return; end
            if isfield(s,'id'),    c.id    = char(s.id); end
            if isfield(s,'time'),  c.time  = char(s.time); end
            if isfield(s,'role'),  c.role  = upper(char(s.role)); end
            if isfield(s,'frame'), c.frame = pivcore.io.pab4Comments.scal(s.frame); end
            if isfield(s,'psgId'), c.psgId = char(s.psgId); end
            if isfield(s,'curve'), c.curve = char(s.curve); end
            if isfield(s,'text'),  c.text  = pivcore.io.pab4Comments.cleanText(s.text); end
            if isfield(s,'images') && isstruct(s.images)
                for fn = {'velmag','shear','axpot'}
                    if isfield(s.images, fn{1}), c.images.(fn{1}) = char(s.images.(fn{1})); end
                end
            end
            if isfield(s,'refs') && isstruct(s.refs), c.refs = s.refs; end
            if isfield(s,'assets') && ~isempty(s.assets)
                c.assets = pivcore.io.pab4Comments.tocell(s.assets);
            end
        end


        function doc = prepForEncode(doc)
            d = pivcore.io.pab4Comments.emptyDoc('');
            fn = fieldnames(d);
            for i = 1:numel(fn)
                if ~isfield(doc, fn{i}), doc.(fn{i}) = d.(fn{i}); end
            end
            if ~iscell(doc.comments)
                doc.comments = pivcore.io.pab4Comments.tocell(doc.comments);
            end
            for k = 1:numel(doc.comments)
                doc.comments{k} = pivcore.io.pab4Comments.normComment(doc.comments{k});
            end
        end


        function s = cleanText(text)
            if isempty(text), s = ''; return; end
            if ~ischar(text)
                if iscell(text), text = strjoin(text, newline); else, text = char(text); end
            end
            s = strtrim(text);
        end


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


        function atomicWrite(p, txt)
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0, error('pivcore:pab4Comments:open','Tak bisa tulis %s', tmp); end
            cleaner = onCleanup(@() pivcore.io.pab4Comments.rmTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
            fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok, error('pivcore:pab4Comments:move','Gagal tulis %s: %s', p, msg); end
        end


        function rmTmp(tmp)
            try, if isfile(tmp), delete(tmp); end, catch, end
        end

    end
end
