classdef assignDataset
%ASSIGNDATASET  Penulis dataset karakteristik assignment kurva Step-3 ke folder
%   `_context/`. MEREKAM cara pengguna mengidentifikasi agregat HW-#/F-#/F0
%   secara manual (fitur per-kurva + per-grup) ke dua berkas:
%
%     _context/assignment_dataset.jsonl  -- 1 baris JSON per KURVA ter-assign
%                                            (append-only; mudah dibaca mesin/
%                                            Claude lintas sesi & jadi calon
%                                            data training model).
%     _context/ASSIGNMENTS.md            -- ringkasan human-readable (tabel per
%                                            eksperimen; ditambah/diperbarui).
%
%   Stateless: tak menyentuh GUI. Hanya I/O berkas teks.
%
%   API:
%     dir = pivcore.io.assignDataset.contextDir(rootDir)
%     n   = pivcore.io.assignDataset.append(ctxDir, expName, assign, records, ...
%                                            dataFile, tsStr)
%
%   Penempatan: PIVTerry/+pivterry/+io/assignDataset.m

    methods (Static)

        % ================================================================
        function d = contextDir(rootDir)
        %CONTEXTDIR  Resolusi folder `_context`. Bila rootDir sudah berujung
        %   `_context`, dipakai apa adanya; bila folder kerja proyek, tambah
        %   `_context`. Folder dibuat bila belum ada.
            if nargin < 1 || isempty(rootDir), rootDir = pwd; end
            [~, leaf] = fileparts(rootDir);
            if strcmpi(leaf, '_context')
                d = rootDir;
            else
                d = fullfile(rootDir, '_context');
            end
            if ~isfolder(d)
                try, mkdir(d); catch, end %#ok<NOSEM,CTCH>
            end
        end


        % ================================================================
        function n = append(ctxDir, expName, assign, records, dataFile, tsStr)
        %APPEND  Tambah baris dataset untuk SEMUA kurva ter-assign + perbarui
        %   ringkasan markdown. Mengembalikan jumlah baris kurva yang ditulis.
        %
        %   assign  : struct-array agregat (label/type/num/curveIdx/feat)
        %   records : struct-array record POT-PSG4 (punya .data/.posPx/.point)
        %   tsStr   : stempel waktu (char) -- diberikan pemanggil (Date.now tak
        %             tersedia headless; GUI kirim datestr).
            n = 0;
            if nargin < 6 || isempty(tsStr), tsStr = ''; end
            if isempty(assign) || ~isstruct(assign), return; end
            ctxDir = pivcore.io.assignDataset.contextDir(ctxDir);

            jsonlPath = fullfile(ctxDir, 'assignment_dataset.jsonl');
            fid = fopen(jsonlPath, 'a');
            if fid < 0
                warning('pivcore:assignDataset:open', ...
                    'Tak bisa menulis dataset: %s', jsonlPath);
                return;
            end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

            % Pastikan gap antar-grup terisi (lompatan integral, sinyal F0).
            assign = pivcore.pot.curveFeatures.fillGroupGaps(assign);

            for a = 1:numel(assign)
                grp = assign(a);
                gfeat = struct();
                if isfield(grp,'feat') && isstruct(grp.feat), gfeat = grp.feat; end
                idx = [];
                if isfield(grp,'curveIdx'), idx = grp.curveIdx(:).'; end
                for k = 1:numel(idx)
                    ri = idx(k);
                    if ri < 1 || ri > numel(records), continue; end
                    r = records(ri);
                    pos = NaN; if isfield(r,'posPx'), pos = r.posPx; end
                    cf = pivcore.pot.curveFeatures.featCurve(r.data, pos);

                    rec = struct();
                    rec.exp    = char(expName);
                    rec.dataFile = char(i_baseName(dataFile));
                    rec.point  = i_str(r, 'point');
                    rec.label  = i_field(grp, 'label', '');
                    rec.type   = i_field(grp, 'type', '');
                    rec.num    = i_field(grp, 'num', NaN);
                    % --- fitur per-kurva ---
                    rec.curve  = cf;
                    % --- fitur grup (ringkas; gap integral utk F0) ---
                    rec.group  = gfeat;
                    rec.ts     = char(tsStr);

                    line = jsonencode(rec);
                    fprintf(fid, '%s\n', line);
                    n = n + 1;
                end
            end
            clear cleanup;  % tutup file sebelum tulis markdown

            % Ringkasan human-readable (di-regenerasi dari JSONL agar konsisten).
            try
                pivcore.io.assignDataset.writeMarkdown(ctxDir);
            catch ME
                warning('pivcore:assignDataset:md', ...
                    'Gagal menulis ASSIGNMENTS.md: %s', ME.message);
            end
        end


        % ================================================================
        function writeMarkdown(ctxDir)
        %WRITEMARKDOWN  Regenerasi _context/ASSIGNMENTS.md dari JSONL: tabel
        %   ringkas per eksperimen (label, type, #kurva, posPx span, integral
        %   mean, gap integral prev/next).
            ctxDir = pivcore.io.assignDataset.contextDir(ctxDir);
            jsonlPath = fullfile(ctxDir, 'assignment_dataset.jsonl');
            mdPath    = fullfile(ctxDir, 'ASSIGNMENTS.md');
            rows = pivcore.io.assignDataset.readJsonl(jsonlPath);

            fid = fopen(mdPath, 'w');
            if fid < 0, return; end
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '# Assignment kurva HW-#/F-#/F0 (rekam karakteristik)\n\n');
            fprintf(fid, ['> Dibuat otomatis oleh pivcore.io.assignDataset dari ', ...
                '`assignment_dataset.jsonl`.\n> Satu agregat = satu baris (label + ', ...
                'fitur grup). Detail per-kurva ada di JSONL.\n\n']);
            if isempty(rows)
                fprintf(fid, '_Belum ada assignment._\n');
                return;
            end

            % Kumpulkan unik per (exp,label) -> ambil fitur grup (sama utk semua
            % kurva dalam grup).
            keyList = {}; seen = containers.Map('KeyType','char','ValueType','logical');
            byExp = containers.Map('KeyType','char','ValueType','any');
            for i = 1:numel(rows)
                r = rows(i);
                key = sprintf('%s||%s', i_get(r,'exp'), i_get(r,'label'));
                if isKey(seen, key), continue; end
                seen(key) = true; keyList{end+1} = key; %#ok<AGROW>
                e = i_get(r,'exp');
                if ~isKey(byExp, e), byExp(e) = {}; end
                lst = byExp(e); lst{end+1} = r; byExp(e) = lst; %#ok<AGROW>
            end

            exps = keys(byExp);
            for ei = 1:numel(exps)
                e = exps{ei};
                fprintf(fid, '## %s\n\n', e);
                fprintf(fid, '| Label | Type | #curves | posPx span | ∫ mean | gap prev | gap next |\n');
                fprintf(fid, '|---|---|---|---|---|---|---|\n');
                lst = byExp(e);
                for k = 1:numel(lst)
                    r = lst{k};
                    g = i_getstruct(r,'group');
                    fprintf(fid, '| %s | %s | %s | %s–%s | %s | %s | %s |\n', ...
                        i_get(r,'label'), i_get(r,'type'), ...
                        i_numstr(i_gf(g,'nCurves')), ...
                        i_numstr(i_gf(g,'posPxMin')), i_numstr(i_gf(g,'posPxMax')), ...
                        i_numstr(i_gf(g,'integralMean')), ...
                        i_numstr(i_gf(g,'integralGapPrev')), ...
                        i_numstr(i_gf(g,'integralGapNext')));
                end
                fprintf(fid, '\n');
            end
        end


        % ================================================================
        function rows = readJsonl(path)
        %READJSONL  Baca berkas JSONL -> struct-array (tiap baris satu entri).
        %   Baris kosong/rusak dilewati.
            rows = struct([]);
            if isempty(path) || ~isfile(path), return; end
            txt = fileread(path);
            lines = regexp(txt, '\r?\n', 'split');
            out = {};
            for i = 1:numel(lines)
                s = strtrim(lines{i});
                if isempty(s), continue; end
                try
                    out{end+1} = jsondecode(s); %#ok<AGROW>
                catch
                    % lewati baris rusak
                end
            end
            if isempty(out), return; end
            % Samakan field agar bisa jadi struct-array.
            rows = i_concatStructs(out);
        end

    end
end


% =====================================================================
% Helper lokal
% =====================================================================
function s = i_baseName(p)
    s = '';
    if isempty(p) || ~ischar(p), return; end
    [~, b, e] = fileparts(p);
    s = [b e];
end

function v = i_field(s, name, def)
    v = def;
    if isstruct(s) && isfield(s, name), v = s.(name); end
end

function s = i_str(r, name)
    s = '';
    if isstruct(r) && isfield(r, name) && ischar(r.(name)), s = r.(name); end
end

function v = i_get(r, name)
    v = '';
    if isstruct(r) && isfield(r, name)
        v = r.(name);
        if isnumeric(v), v = num2str(v); end
        if ~ischar(v), v = ''; end
    end
end

function g = i_getstruct(r, name)
    g = struct();
    if isstruct(r) && isfield(r, name) && isstruct(r.(name)), g = r.(name); end
end

function v = i_gf(g, name)
    v = NaN;
    if isstruct(g) && isfield(g, name), v = g.(name); end
end

function s = i_numstr(v)
    if isempty(v) || (isnumeric(v) && ~isfinite(v)), s = '-'; return; end
    if isnumeric(v)
        if v == round(v), s = sprintf('%d', v); else, s = sprintf('%.1f', v); end
    else
        s = char(string(v));
    end
end

function out = i_concatStructs(cellOfStructs)
%I_CONCATSTRUCTS  Gabung cell of struct (field mungkin beda) jadi struct-array
%   dgn union field (yg hilang -> []).
    allF = {};
    for i = 1:numel(cellOfStructs)
        if isstruct(cellOfStructs{i})
            allF = union(allF, fieldnames(cellOfStructs{i}));
        end
    end
    out = struct([]);
    for i = 1:numel(cellOfStructs)
        s = cellOfStructs{i};
        if ~isstruct(s), continue; end
        for k = 1:numel(allF)
            if ~isfield(s, allF{k}), s.(allF{k}) = []; end
        end
        if isempty(out), out = s; else, out(end+1) = orderfields(s, out); end %#ok<AGROW>
    end
end
