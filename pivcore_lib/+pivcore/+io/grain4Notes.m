classdef grain4Notes
%GRAIN4NOTES  Kanal JURNAL GRAIN4 (manusia <-> Claude) — sidecar Markdown.
%
%   DUA TINGKAT (lihat GRAIN4_PLAN §3a):
%     <base>_notes.md   — jurnal PER-EKSPERIMEN: catatan peneliti + balasan
%                         Claude. Berseksi via TAG inline (append-only):
%                            exp                 — kesan/kesimpulan global exp
%                            psg:<psgId>         — unit observasi POT (per garis)
%                            curve:<label>@<id>  — kurva tertentu PADA garis itu
%                            frame:<n>           — catatan menempel frame
%     _GRAIN4_journal.md  — jurnal SERI/FOLDER (1 per folder): tren lintas-exp.
%
%   Append-only secara semantik (entri tak pernah ditimpa/diurut ulang); berkas
%   ditulis-ulang ATOMIK (tmp->movefile) hanya untuk memperbarui satu baris
%   FOOTER cursor antrean:
%       <!-- grain4:cursor lastWriteByUser=<iso> lastReadByClaude=<iso> -->
%   Protokol (manual, filesystem-polling — MATLAB TIDAK memanggil API):
%     1. Peneliti tulis  -> appendEntry(role 'USER')  -> set lastWriteByUser.
%     2. Sesi Claude Code baca berkas yg lastWriteByUser > lastReadByClaude,
%        appendEntry(role 'CLAUDE') -> set lastReadByClaude.
%     3. GUI "Muat balasan Claude" -> loadEntries, render entri [CLAUDE] terbaru.
%
%   Penanda penulis NETRAL-AKUN: role 'USER'/'CLAUDE' (identitas akun tak
%   penting). Nama opsional diambil dari opts.author / getenv('USER').
%
%   API:
%     p   = pivcore.io.grain4Notes.notesPath(dataFile)
%     p   = pivcore.io.grain4Notes.journalPath(dirOrFile)
%     pivcore.io.grain4Notes.appendEntry(dataFile, level, key, text [, opts])
%     pivcore.io.grain4Notes.appendSeries(dirOrFile, text [, opts])
%     E   = pivcore.io.grain4Notes.loadEntries(dataFile)     % struct array
%     E   = pivcore.io.grain4Notes.loadSeries(dirOrFile)
%     c   = pivcore.io.grain4Notes.getCursor(dataFile)       % struct write/read iso
%     tf  = pivcore.io.grain4Notes.pendingForClaude(dataFile)
%     pivcore.io.grain4Notes.setCursor(dataFile, field, isoStr)
%     tag = pivcore.io.grain4Notes.curveKey(label, psgId)    % 'HW-1@frac070'
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivcore/+io/grain4Notes.m

    methods (Static)

        % ================================================================
        function p = notesPath(dataFile)
            p = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_notes.md', base));
        end


        function p = journalPath(dirOrFile)
        %JOURNALPATH  <dir>/_GRAIN4_journal.md. Terima FOLDER atau path berkas.
            p = '';
            if isempty(dirOrFile) || ~ischar(dirOrFile), return; end
            if isfolder(dirOrFile)
                d = dirOrFile;
            else
                d = fileparts(dirOrFile);
                if isempty(d), d = pwd; end
            end
            p = fullfile(d, '_GRAIN4_journal.md');
        end


        function tag = curveKey(label, psgId)
        %CURVEKEY  Kunci kurva = '<label>@<psgId>' (label kurva hanya bermakna
        %   dalam konteks satu garis PSG).
            tag = sprintf('%s@%s', char(label), char(psgId));
        end


        % ================================================================
        function appendEntry(dataFile, level, key, text, opts)
        %APPENDENTRY  Tambah satu entri ke <base>_notes.md. level ∈ {exp, psg,
        %   curve, frame}; key = psgId / 'label@psgId' / nomor frame (atau '').
            if nargin < 5, opts = struct(); end
            p   = pivcore.io.grain4Notes.notesPath(dataFile);
            tag = pivcore.io.grain4Notes.makeTag(level, key);
            [~, base] = fileparts(char(dataFile));
            title = sprintf('# GRAIN4 Notes — %s', base);
            pivcore.io.grain4Notes.appendToFile(p, title, tag, text, opts);
        end


        function appendSeries(dirOrFile, text, opts)
        %APPENDSERIES  Tambah entri ke jurnal SERI _GRAIN4_journal.md (tag 'series').
            if nargin < 3, opts = struct(); end
            p = pivcore.io.grain4Notes.journalPath(dirOrFile);
            pivcore.io.grain4Notes.appendToFile(p, '# GRAIN4 Journal (seri)', 'series', text, opts);
        end


        % ================================================================
        function E = loadEntries(dataFile)
        %LOADENTRIES  Parse <base>_notes.md -> struct array (role/time/level/
        %   key/tag/text). Kosong bila berkas tak ada.
            E = pivcore.io.grain4Notes.parseFile(pivcore.io.grain4Notes.notesPath(dataFile));
        end


        function E = loadSeries(dirOrFile)
            E = pivcore.io.grain4Notes.parseFile(pivcore.io.grain4Notes.journalPath(dirOrFile));
        end


        % ================================================================
        function c = getCursor(dataFile)
        %GETCURSOR  Baca footer cursor -> struct(lastWriteByUser, lastReadByClaude)
        %   (char ISO; '' bila belum ada).
            c = struct('lastWriteByUser','', 'lastReadByClaude','');
            p = pivcore.io.grain4Notes.notesPath(dataFile);
            if isempty(p) || ~isfile(p), return; end
            c = pivcore.io.grain4Notes.cursorFromText(fileread(p));
        end


        function tf = pendingForClaude(dataFile)
        %PENDINGFORCLAUDE  TRUE bila ada tulisan USER yg belum dibaca Claude
        %   (lastWriteByUser > lastReadByClaude).
            c = pivcore.io.grain4Notes.getCursor(dataFile);
            tf = pivcore.io.grain4Notes.cursorPending(c);
        end


        function setCursor(dataFile, field, isoStr)
        %SETCURSOR  Set salah satu field cursor (lastWriteByUser/lastReadByClaude)
        %   tanpa menambah entri (RMW atomik footer saja).
            p = pivcore.io.grain4Notes.notesPath(dataFile);
            if isempty(p) || ~isfile(p), return; end
            txt = fileread(p);
            [body, c] = pivcore.io.grain4Notes.splitBodyCursor(txt);
            if any(strcmp(field, {'lastWriteByUser','lastReadByClaude'}))
                c.(field) = isoStr;
            end
            pivcore.io.grain4Notes.atomicWrite(p, ...
                pivcore.io.grain4Notes.joinBodyCursor(body, c));
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function tag = makeTag(level, key)
            level = lower(char(level));
            key   = pivcore.io.grain4Notes.keyStr(key);
            switch level
                case 'exp',   tag = 'exp';
                case 'psg',   tag = ['psg:' key];
                case 'curve', tag = ['curve:' key];
                case 'frame', tag = ['frame:' key];
                otherwise,    tag = level; if ~isempty(key), tag = [tag ':' key]; end
            end
        end


        function s = keyStr(key)
            if isempty(key), s = ''; return; end
            if isnumeric(key), s = num2str(key(1)); else, s = char(key); end
        end


        function appendToFile(p, title, tag, text, opts)
        %APPENDTOFILE  RMW atomik: tambah blok entri sebelum footer; update cursor.
            role = 'USER';
            if isfield(opts,'role') && ~isempty(opts.role), role = upper(char(opts.role)); end
            [nowDisp, nowIso] = pivcore.io.grain4Notes.timeNow();

            if isfile(p)
                [body, c] = pivcore.io.grain4Notes.splitBodyCursor(fileread(p));
            else
                body = sprintf('%s\n', title);
                c = struct('lastWriteByUser','', 'lastReadByClaude','');
            end

            block = sprintf('\n[%s %s | %s]\n%s\n', role, nowDisp, tag, ...
                pivcore.io.grain4Notes.cleanText(text));
            body = [body block];

            if strcmp(role, 'CLAUDE')
                c.lastReadByClaude = nowIso;
            else
                c.lastWriteByUser = nowIso;
            end

            pivcore.io.grain4Notes.atomicWrite(p, ...
                pivcore.io.grain4Notes.joinBodyCursor(body, c));
        end


        function [body, c] = splitBodyCursor(txt)
        %SPLITBODYCURSOR  Pisah body (tanpa baris footer cursor) + struct cursor.
            c = pivcore.io.grain4Notes.cursorFromText(txt);
            % Buang SEMUA baris footer cursor (jaga-jaga bila ganda).
            body = regexprep(txt, '(?m)^<!-- grain4:cursor[^\n]*-->\s*$', '');
            body = regexprep(body, '\s*$', '');   % rapikan whitespace ekor
        end


        function s = joinBodyCursor(body, c)
            footer = sprintf('<!-- grain4:cursor lastWriteByUser=%s lastReadByClaude=%s -->', ...
                c.lastWriteByUser, c.lastReadByClaude);
            s = sprintf('%s\n\n%s\n', regexprep(body, '\s*$', ''), footer);
        end


        function c = cursorFromText(txt)
            c = struct('lastWriteByUser','', 'lastReadByClaude','');
            tw = regexp(txt, 'lastWriteByUser=(\S*)', 'tokens', 'once');
            tr = regexp(txt, 'lastReadByClaude=(\S*)', 'tokens', 'once');
            if ~isempty(tw), c.lastWriteByUser = strrep(tw{1}, '-->',''); end
            if ~isempty(tr), c.lastReadByClaude = strrep(tr{1}, '-->',''); end
            % Token '-->' bisa nempel bila field kosong di akhir; bersihkan.
            c.lastWriteByUser = pivcore.io.grain4Notes.cleanTok(c.lastWriteByUser);
            c.lastReadByClaude = pivcore.io.grain4Notes.cleanTok(c.lastReadByClaude);
        end


        function s = cleanTok(s)
            s = strtrim(strrep(s, '-->', ''));
        end


        function tf = cursorPending(c)
            tf = false;
            if isempty(c.lastWriteByUser), return; end
            if isempty(c.lastReadByClaude), tf = true; return; end
            try
                tf = pivcore.io.grain4Notes.isoNum(c.lastWriteByUser) > ...
                     pivcore.io.grain4Notes.isoNum(c.lastReadByClaude);
            catch
                tf = ~strcmp(c.lastWriteByUser, c.lastReadByClaude);
            end
        end


        function d = isoNum(iso)
        %ISONUM  ISO 'yyyy-mm-ddTHH:MM:SS' -> datenum (untuk perbandingan cursor).
            d = datenum(iso, 'yyyy-mm-ddTHH:MM:SS'); %#ok<DATNM>
        end


        function E = parseFile(p)
        %PARSEFILE  Pisah entri pakai header [ROLE TIME | tag] -> struct array.
            E = struct('role',{},'time',{},'level',{},'key',{},'tag',{},'text',{});
            if isempty(p) || ~isfile(p), return; end
            txt = pivcore.io.grain4Notes.splitBodyCursor(fileread(p));
            lines = regexp(txt, '\r?\n', 'split');
            hdrRe = '^\[(USER|CLAUDE)\s+([0-9\- :]+?)\s*\|\s*([^\]]*)\]\s*$';
            cur = []; buf = {};
            for i = 1:numel(lines)
                tok = regexp(lines{i}, hdrRe, 'tokens', 'once');
                if ~isempty(tok)
                    if ~isempty(cur)
                        cur.text = pivcore.io.grain4Notes.joinTrim(buf);
                        E(end+1) = cur; %#ok<AGROW>
                    end
                    [lvl, key] = pivcore.io.grain4Notes.splitTag(strtrim(tok{3}));
                    cur = struct('role',tok{1}, 'time',strtrim(tok{2}), ...
                        'level',lvl, 'key',key, 'tag',strtrim(tok{3}), 'text','');
                    buf = {};
                elseif ~isempty(cur)
                    buf{end+1} = lines{i}; %#ok<AGROW>
                end
            end
            if ~isempty(cur)
                cur.text = pivcore.io.grain4Notes.joinTrim(buf);
                E(end+1) = cur;
            end
        end


        function [lvl, key] = splitTag(tag)
            i = find(tag == ':', 1, 'first');
            if isempty(i), lvl = tag; key = ''; else
                lvl = tag(1:i-1); key = tag(i+1:end);
            end
        end


        function s = joinTrim(buf)
            while ~isempty(buf) && isempty(strtrim(buf{1})),   buf(1)   = []; end
            while ~isempty(buf) && isempty(strtrim(buf{end})), buf(end) = []; end
            s = strjoin(buf, newline);
        end


        function s = cleanText(text)
        %CLEANTEXT  Cegah teks merusak parser: buang baris yg menyamar header.
            if isempty(text), s = '(kosong)'; return; end
            if ~ischar(text)
                if iscell(text), text = strjoin(text, newline); else, text = char(text); end
            end
            s = regexprep(text, '(?m)^\[(USER|CLAUDE)\b', ' [\1');
            s = strtrim(s);
            if isempty(s), s = '(kosong)'; end
        end


        function [disp, iso] = timeNow()
            disp = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<DATST,TNOW1>
            iso  = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<DATST,TNOW1>
        end


        function atomicWrite(p, txt)
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0, error('pivcore:grain4Notes:open','Tak bisa tulis %s', tmp); end
            cleaner = onCleanup(@() pivcore.io.grain4Notes.rmTmp(tmp));
            fwrite(fid, txt, 'char');
            fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok, error('pivcore:grain4Notes:move','Gagal tulis %s: %s', p, msg); end
        end


        function rmTmp(tmp)
            try, if isfile(tmp), delete(tmp); end, catch, end
        end

    end
end
