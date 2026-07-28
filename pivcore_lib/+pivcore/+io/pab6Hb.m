classdef pab6Hb
%PAB6HB  Model HB (Hinterland Block) PAB6 — sidecar `<base>_hb.json` di folder
%   yang sama dgn MAT PIV. INI kebenaran milik PAB6 (analisis tampak PETA). MAT
%   PIV biner, `<base>_potdata.json` (PAB4) & `<base>_faults.json` (PAB5) TIDAK
%   disentuh — PAB6 melapis model HB di atas pipeline kurva yang sudah teruji.
%   Clone pola pivcore.io.pab5Faults (atomic write, NaN<->null).
%
%   KONSEP: garis HB = "mirip max-indenter, tapi untuk Hanging Wall aktif",
%   dibangun dari beberapa kurva KANDIDAT (lihat pivcore.pot.hbMerge). HB terikat
%   PER GARIS PSG (foto tak selalu tegak lurus -> sampling beda tiap sisi) — jadi
%   sidecar menyimpan SATU blok HB per psgId. 1 HB per garis PSG.
%
%   Identitas kurva kandidat DISIMPAN sbg posPx (posisi sampling sepanjang garis
%   PSG) — STABIL terhadap sampling ulang (pola PAB4/PAB5). Batas awal/akhir
%   kurva = x0/x1 (frame). Deret merge/values di-CACHE saat simpan (kanal Claude);
%   model murni = psgId + candidates{posPx,x0,x1}.
%
%   Penulisan WAJIB ATOMIC (tmp -> movefile). NaN <-> JSON null.
%
%   API:
%     p   = pivcore.io.pab6Hb.dataPath(dataFile)
%     doc = pivcore.io.pab6Hb.emptyDoc(dataFile [,frames])
%     doc = pivcore.io.pab6Hb.read(dataFile)        % [] -> emptyDoc
%     pivcore.io.pab6Hb.write(dataFile, doc)        % ATOMIC
%     blk = pivcore.io.pab6Hb.hbBlockStruct(psgId)
%     c   = pivcore.io.pab6Hb.candStruct(posPx, x0, x1 [,values])
%     [blk,idx] = pivcore.io.pab6Hb.findBlock(doc, psgId)   % kunci = psgId
%     doc = pivcore.io.pab6Hb.upsertBlock(doc, blk)
%     doc = pivcore.io.pab6Hb.removeBlock(doc, psgId)
%
%   Penempatan berkas: PAB/pivcore_lib/+pivcore/+io/pab6Hb.m

    methods (Static)

        % ================================================================
        function p = dataPath(dataFile)
        %DATAPATH  <dir>/<base>_hb.json untuk MAT PIV dataFile.
            p = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_hb.json', base));
        end


        % ================================================================
        function doc = emptyDoc(dataFile, frames)
        %EMPTYDOC  Kerangka dokumen kosong (default satuan px/frame).
            if nargin < 2, frames = NaN; end
            [~, base, ext] = fileparts(char(dataFile));
            doc = struct();
            doc.formatName    = 'PAB6 HB Data';
            doc.formatVersion = 1;
            doc.source        = [base ext];
            doc.meta          = struct('frames', frames, 'basename', base);
            doc.units         = 'px/frame';
            doc.mergeMode     = 'max';        % zona overlap = MAX (envelope atas)
            doc.psgHb         = {};           % cell of hbBlock (JSON array); 1 blok / garis PSG
        end


        % ================================================================
        function doc = read(dataFile)
        %READ  Baca & NORMALISASI sidecar. Tak ada berkas -> emptyDoc. Rusak ->
        %   emptyDoc + warning (tak melempar agar GUI tetap jalan).
            p = pivcore.io.pab6Hb.dataPath(dataFile);
            if isempty(p) || ~isfile(p)
                doc = pivcore.io.pab6Hb.emptyDoc(dataFile); return;
            end
            try
                txt = fileread(p);
                raw = jsondecode(txt);
            catch ME
                warning('pivcore:pab6Hb:read', ...
                    'Gagal membaca/parse %s (%s); pakai dokumen kosong.', p, ME.message);
                doc = pivcore.io.pab6Hb.emptyDoc(dataFile); return;
            end
            doc = pivcore.io.pab6Hb.normalizeDoc(raw, dataFile);
        end


        % ================================================================
        function write(dataFile, doc)
        %WRITE  Tulis dokumen ke `<base>_hb.json` secara ATOMIC.
            p = pivcore.io.pab6Hb.dataPath(dataFile);
            if isempty(p)
                error('pivcore:pab6Hb:noPath', ...
                    'Tak bisa menentukan path _hb untuk: %s', dataFile);
            end
            doc = pivcore.io.pab6Hb.prepForEncode(doc);
            txt = jsonencode(doc, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0
                error('pivcore:pab6Hb:open', 'Tak bisa membuka %s utk tulis.', tmp);
            end
            cleaner = onCleanup(@() pivcore.io.pab6Hb.cleanupTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
            fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok
                error('pivcore:pab6Hb:move', ...
                    'Gagal memindah tmp->final (%s): %s', p, msg);
            end
        end


        % ================================================================
        function blk = hbBlockStruct(psgId)
        %HBBLOCKSTRUCT  Skeleton satu blok HB (kosong) untuk 1 garis PSG.
            blk = struct();
            blk.psgId      = char(psgId);
            blk.candidates = {};      % cell of candStruct (urut = urutan tambah; [1]="kurva pertama")
            blk.merged     = [];      % CACHE deret HB gabungan (1 x nF); ditulis saat simpan
            blk.startX     = NaN;     % CACHE X0 kurva pertama (batas awal garis HB)
        end


        % ================================================================
        function c = candStruct(posPx, x0, x1, values)
        %CANDSTRUCT  Skeleton satu kurva kandidat HB.
            if nargin < 2, x0     = NaN; end
            if nargin < 3, x1     = NaN; end
            if nargin < 4, values = [];  end
            c = struct();
            c.posPx  = pivcore.io.pab6Hb.scal(posPx);
            c.x0     = pivcore.io.pab6Hb.scal(x0);
            c.x1     = pivcore.io.pab6Hb.scal(x1);
            c.values = pivcore.io.pab6Hb.rowv(values);   % CACHE deret kandidat (kanal Claude)
        end


        % ================================================================
        function [blk, idx] = findBlock(doc, psgId)
        %FINDBLOCK  Cari blok HB ber-psgId. idx=0 & blk=[] bila tak ada.
            blk = []; idx = 0;
            if ~isstruct(doc) || ~isfield(doc,'psgHb'), return; end
            B = doc.psgHb;
            for k = 1:numel(B)
                bk = B{k};
                if isstruct(bk) && isfield(bk,'psgId') && strcmp(bk.psgId, char(psgId))
                    blk = bk; idx = k; return;
                end
            end
        end


        % ================================================================
        function doc = upsertBlock(doc, blk)
        %UPSERTBLOCK  Sisipkan/ganti blok HB ber-psgId sama (psgId = kunci).
            if ~isstruct(doc), doc = pivcore.io.pab6Hb.emptyDoc(''); end
            if ~isfield(doc,'psgHb') || ~iscell(doc.psgHb), doc.psgHb = {}; end
            [~, idx] = pivcore.io.pab6Hb.findBlock(doc, blk.psgId);
            if idx > 0, doc.psgHb{idx} = blk; else, doc.psgHb{end+1} = blk; end
        end


        % ================================================================
        function doc = removeBlock(doc, psgId)
        %REMOVEBLOCK  Buang blok HB ber-psgId (no-op bila tak ada).
            [~, idx] = pivcore.io.pab6Hb.findBlock(doc, psgId);
            if idx > 0, doc.psgHb(idx) = []; end
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function doc = normalizeDoc(raw, dataFile)
            d = pivcore.io.pab6Hb.emptyDoc(dataFile);
            if ~isstruct(raw), doc = d; return; end
            doc = d;
            for fn = {'formatName','formatVersion','source','units','mergeMode'}
                k = fn{1};
                if isfield(raw, k), doc.(k) = raw.(k); end
            end
            if isfield(raw,'meta') && isstruct(raw.meta)
                if isfield(raw.meta,'frames'),   doc.meta.frames   = raw.meta.frames; end
                if isfield(raw.meta,'basename'), doc.meta.basename = raw.meta.basename; end
            end
            blocks = {};
            if isfield(raw,'psgHb')
                src = pivcore.io.pab6Hb.tocell(raw.psgHb);
                for k = 1:numel(src)
                    blocks{end+1} = pivcore.io.pab6Hb.normBlock(src{k}); %#ok<AGROW>
                end
            end
            doc.psgHb = blocks;
        end


        function blk = normBlock(s)
            blk = pivcore.io.pab6Hb.hbBlockStruct('');
            if ~isstruct(s), return; end
            if isfield(s,'psgId'),  blk.psgId  = char(s.psgId); end
            if isfield(s,'merged'), blk.merged = pivcore.io.pab6Hb.rowv(s.merged); end
            if isfield(s,'startX'), blk.startX = pivcore.io.pab6Hb.scal(s.startX); end
            cands = {};
            if isfield(s,'candidates')
                src = pivcore.io.pab6Hb.tocell(s.candidates);
                for k = 1:numel(src)
                    cands{end+1} = pivcore.io.pab6Hb.normCand(src{k}); %#ok<AGROW>
                end
            end
            blk.candidates = cands;
        end


        function c = normCand(s)
            c = pivcore.io.pab6Hb.candStruct(NaN, NaN, NaN);
            if ~isstruct(s), return; end
            if isfield(s,'posPx'),  c.posPx  = pivcore.io.pab6Hb.scal(s.posPx); end
            if isfield(s,'x0'),     c.x0     = pivcore.io.pab6Hb.scal(s.x0); end
            if isfield(s,'x1'),     c.x1     = pivcore.io.pab6Hb.scal(s.x1); end
            if isfield(s,'values'), c.values = pivcore.io.pab6Hb.rowv(s.values); end
        end


        function doc = prepForEncode(doc)
            d = pivcore.io.pab6Hb.emptyDoc('');
            fn = fieldnames(d);
            for i = 1:numel(fn)
                if ~isfield(doc, fn{i}), doc.(fn{i}) = d.(fn{i}); end
            end
            if ~iscell(doc.psgHb)
                doc.psgHb = pivcore.io.pab6Hb.tocell(doc.psgHb);
            end
            % Pastikan candidates tiap blok = cell (jsonencode array konsisten).
            for k = 1:numel(doc.psgHb)
                b = doc.psgHb{k};
                if isstruct(b) && isfield(b,'candidates') && ~iscell(b.candidates)
                    b.candidates = pivcore.io.pab6Hb.tocell(b.candidates);
                    doc.psgHb{k} = b;
                end
            end
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
