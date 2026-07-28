classdef pab5Faults
%PAB5FAULTS  Model SESAR (fault-first) PAB5 — sidecar `<base>_faults.json` di
%   folder yang sama dgn MAT PIV. INI kebenaran milik PAB5 (Tab ① Sesar). MAT
%   PIV biner & `<base>_potdata.json` (kebenaran PAB4) TIDAK disentuh — PAB5
%   melapis model sesar di atas pipeline kurva PAB4 yang sudah teruji.
%
%   KONSEP (≠ PAB4 yang berpusat HW): tiap SESAR F# = SATU baris berisi DUA
%   kurva POT — HANGING WALL (HW) & FOOTWALL (FW) — plus titik perkembangan:
%     nuc     frame NUKLEASI (peristiwa pertama)
%     fsr     frame FAULT SURFACE RUPTURE (puncak kurva)
%     startF  frame AWAL aktivitas sesar
%     endF    frame AKHIR aktivitas sesar
%   Net-slip(frame) = repHW(frame) − repFW(frame); area = ∫ net-slip dari
%   START..END (trapz BERTANDA — "1 sesar = 1 luas di antara kurva HW & FW").
%
%   Identitas kurva DISIMPAN sebagai posPx (posisi sampling di sepanjang garis
%   PSG) — STABIL terhadap sampling ulang (cocok dgn pola PAB4 curvesFromRecs).
%   Saat dibuka ulang, posPx dipetakan kembali ke baris record terdekat.
%
%   Field derivatif (area/dNet/values) di-CACHE saat simpan untuk kanal Claude;
%   model murni = id/hwPosPx/fwPosPx/nuc/fsr/startF/endF.
%
%   Penulisan WAJIB ATOMIC (tmp -> movefile). NaN <-> JSON null.
%
%   API:
%     p   = pivcore.io.pab5Faults.dataPath(dataFile)
%     doc = pivcore.io.pab5Faults.emptyDoc(dataFile [,frames])
%     doc = pivcore.io.pab5Faults.read(dataFile)        % [] -> emptyDoc
%     pivcore.io.pab5Faults.write(dataFile, doc)        % ATOMIC
%     f   = pivcore.io.pab5Faults.faultStruct(id,hwPosPx,fwPosPx,nuc,fsr,startF,endF [,area,dNet,values])
%     doc = pivcore.io.pab5Faults.upsertFault(doc, f)   % kunci = id
%     [f,idx] = pivcore.io.pab5Faults.findFault(doc, id)
%     doc = pivcore.io.pab5Faults.removeFault(doc, id)
%
%   Penempatan berkas: PAB/pivcore_lib/+pivcore/+io/pab5Faults.m

    methods (Static)

        % ================================================================
        function p = dataPath(dataFile)
        %DATAPATH  <dir>/<base>_faults.json untuk MAT PIV dataFile.
            p = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_faults.json', base));
        end


        % ================================================================
        function doc = emptyDoc(dataFile, frames)
        %EMPTYDOC  Kerangka dokumen kosong (default satuan px/frame, signed).
            if nargin < 2, frames = NaN; end
            [~, base, ext] = fileparts(char(dataFile));
            doc = struct();
            doc.formatName    = 'PAB5 Fault Data';
            doc.formatVersion = 1;
            doc.source        = [base ext];
            doc.meta          = struct('frames', frames, 'basename', base);
            doc.units         = 'px/frame';
            doc.signConvention= 'signed';
            doc.detachment    = pivcore.pot.faultAngle.emptyDetachment();  % bidang ref sudut (Tab ②)
            doc.faults        = {};           % cell of fault-struct (JSON array)
        end


        % ================================================================
        function doc = read(dataFile)
        %READ  Baca & NORMALISASI sidecar. Tak ada berkas -> emptyDoc. Rusak ->
        %   emptyDoc + warning (tak melempar agar GUI tetap jalan).
            p = pivcore.io.pab5Faults.dataPath(dataFile);
            if isempty(p) || ~isfile(p)
                doc = pivcore.io.pab5Faults.emptyDoc(dataFile); return;
            end
            try
                txt = fileread(p);
                raw = jsondecode(txt);
            catch ME
                warning('pivcore:pab5Faults:read', ...
                    'Gagal membaca/parse %s (%s); pakai dokumen kosong.', p, ME.message);
                doc = pivcore.io.pab5Faults.emptyDoc(dataFile); return;
            end
            doc = pivcore.io.pab5Faults.normalizeDoc(raw, dataFile);
        end


        % ================================================================
        function write(dataFile, doc)
        %WRITE  Tulis dokumen ke `<base>_faults.json` secara ATOMIC.
            p = pivcore.io.pab5Faults.dataPath(dataFile);
            if isempty(p)
                error('pivcore:pab5Faults:noPath', ...
                    'Tak bisa menentukan path _faults untuk: %s', dataFile);
            end
            doc = pivcore.io.pab5Faults.prepForEncode(doc);
            txt = jsonencode(doc, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0
                error('pivcore:pab5Faults:open', 'Tak bisa membuka %s utk tulis.', tmp);
            end
            cleaner = onCleanup(@() pivcore.io.pab5Faults.cleanupTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
            fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok
                error('pivcore:pab5Faults:move', ...
                    'Gagal memindah tmp->final (%s): %s', p, msg);
            end
        end


        % ================================================================
        function f = faultStruct(id, hwPosPx, fwPosPx, nuc, fsr, startF, endF, area, dNet, values)
        %FAULTSTRUCT  Skeleton satu sesar. Field derivatif opsional (default NaN/[]).
            if nargin < 8,  area   = NaN; end
            if nargin < 9,  dNet   = NaN; end
            if nargin < 10, values = [];  end
            f = struct();
            f.id      = char(id);
            f.parentId= '';                                  % '' = sesar utama; id F = SUB-FAULT (anak)
            f.uiNum   = NaN;                                 % NOMOR TAMPIL sesar (kolom F#); BOLEH duplikat.
                                                             %   id = kunci unik internal; uiNum = label yg dilihat user.
                                                             %   NaN -> turunkan dari id (kompat record lama).
            f.enabled = true;                                % ON/OFF sesar: false -> tak dirender/diekspor
                                                             %   (input DIPERTAHANKAN). Default true (kompat lama).
            f.psgId   = '';                                  % id GARIS PSG pemilik sesar (scoping multi-PSG).
                                                             %   '' = belum ter-scope (file lama/PAB4/PAB6) -> di-migrasi
                                                             %   ke garis pertama saat dibuka (assignOrphanFaultsTo).
            f.hwPosPx = pivcore.io.pab5Faults.scal(hwPosPx);
            f.fwPosPx = pivcore.io.pab5Faults.scal(fwPosPx);
            f.nuc     = pivcore.io.pab5Faults.scal(nuc);      % NUC-D (descriptive, manual)
            f.nucT    = NaN;                                  % NUC-T (theoretical, auto = titik belok net-slip)
            f.fsr     = pivcore.io.pab5Faults.scal(fsr);      % FSR-D (descriptive, manual)
            f.fsrT    = NaN;                                  % FSR-T (theoretical, auto = minimum FW / MinFW)
            f.startF  = pivcore.io.pab5Faults.scal(startF);
            f.endF    = pivcore.io.pab5Faults.scal(endF);
            f.area    = pivcore.io.pab5Faults.scal(area);
            f.dNet    = pivcore.io.pab5Faults.scal(dNet);
            f.angleDeg= NaN;   % sudut sesar relatif detachment (°) — diisi Tab ② (Fase 2+)
            f.values  = pivcore.io.pab5Faults.rowv(values);
        end


        % ================================================================
        function [f, idx] = findFault(doc, id)
        %FINDFAULT  Cari sesar ber-id. idx=0 & f=[] bila tak ada.
            f = []; idx = 0;
            if ~isstruct(doc) || ~isfield(doc,'faults'), return; end
            F = doc.faults;
            for k = 1:numel(F)
                fk = F{k};
                if isstruct(fk) && isfield(fk,'id') && strcmp(fk.id, char(id))
                    f = fk; idx = k; return;
                end
            end
        end


        % ================================================================
        function doc = upsertFault(doc, f)
        %UPSERTFAULT  Sisipkan/ganti sesar ber-id sama (id = kunci stabil).
            if ~isstruct(doc), doc = pivcore.io.pab5Faults.emptyDoc(''); end
            if ~isfield(doc,'faults') || ~iscell(doc.faults), doc.faults = {}; end
            [~, idx] = pivcore.io.pab5Faults.findFault(doc, f.id);
            if idx > 0, doc.faults{idx} = f; else, doc.faults{end+1} = f; end
        end


        % ================================================================
        function doc = removeFault(doc, id)
        %REMOVEFAULT  Buang sesar ber-id (no-op bila tak ada).
            [~, idx] = pivcore.io.pab5Faults.findFault(doc, id);
            if idx > 0, doc.faults(idx) = []; end
        end


        % ================================================================
        function doc = reorderFaults(doc, orderedIds)
        %REORDERFAULTS  Susun ulang `doc.faults` sehingga sesar ber-id ∈ orderedIds
        %   muncul sesuai URUTAN di orderedIds (dipakai "Kunci+Urut" -> persist
        %   urutan tampil ke _faults.json supaya SEMUA modul PAB4/5/6 memuat urutan
        %   yang SAMA). Sesar yang id-nya TIDAK ada di orderedIds (mis. milik garis
        %   PSG lain) DIPERTAHANKAN pada posisi relatifnya. id di orderedIds yang
        %   tak punya record diabaikan.
        %
        %   Metode: pertahankan "kerangka" posisi lama. Tiap slot yang DULU diisi
        %   fault yang di-reorder -> isi ulang berurutan dari orderedIds (yang
        %   punya record). Slot lain (PSG lain) tak disentuh.
            if ~(isstruct(doc) && isfield(doc,'faults') && iscell(doc.faults)), return; end
            if nargin < 2 || isempty(orderedIds), return; end
            oids = orderedIds; if ~iscell(oids), oids = {oids}; end
            % Kumpulkan id yang termasuk reorder DAN punya record (jaga urutan).
            newSeq = {};
            for k = 1:numel(oids)
                idk = char(oids{k});
                if isempty(idk), continue; end
                [~, ix] = pivcore.io.pab5Faults.findFault(doc, idk);
                if ix > 0, newSeq{end+1} = idk; end %#ok<AGROW>
            end
            if isempty(newSeq), return; end
            reset = @(x) any(strcmp(newSeq, x));   % apakah id ini ikut di-reorder
            out = cell(1, numel(doc.faults));
            p = 1;   % penunjuk newSeq
            for k = 1:numel(doc.faults)
                fk = doc.faults{k};
                idk = ''; if isstruct(fk) && isfield(fk,'id'), idk = char(fk.id); end
                if reset(idk)
                    % slot ini "milik" grup reorder -> ambil id berikutnya dari newSeq
                    [nf, ~] = pivcore.io.pab5Faults.findFault(doc, newSeq{p});
                    out{k} = nf; p = p + 1;
                else
                    out{k} = fk;   % PSG lain / tak di-reorder -> tetap
                end
            end
            doc.faults = out;
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function doc = normalizeDoc(raw, dataFile)
            d = pivcore.io.pab5Faults.emptyDoc(dataFile);
            if ~isstruct(raw), doc = d; return; end
            doc = d;
            for fn = {'formatName','formatVersion','source','units','signConvention'}
                k = fn{1};
                if isfield(raw, k), doc.(k) = raw.(k); end
            end
            if isfield(raw,'meta') && isstruct(raw.meta)
                if isfield(raw.meta,'frames'),   doc.meta.frames   = raw.meta.frames; end
                if isfield(raw.meta,'basename'), doc.meta.basename = raw.meta.basename; end
            end
            if isfield(raw,'detachment')
                doc.detachment = pivcore.io.pab5Faults.normDetachment(raw.detachment);
            end
            faults = {};
            if isfield(raw,'faults')
                src = pivcore.io.pab5Faults.tocell(raw.faults);
                for k = 1:numel(src)
                    faults{end+1} = pivcore.io.pab5Faults.normFault(src{k}); %#ok<AGROW>
                end
            end
            doc.faults = faults;
        end


        function f = normFault(s)
            f = pivcore.io.pab5Faults.faultStruct('', NaN, NaN, NaN, NaN, NaN, NaN);
            if ~isstruct(s), return; end
            if isfield(s,'id'),       f.id       = char(s.id); end
            if isfield(s,'parentId'), f.parentId = char(s.parentId); end
            if isfield(s,'uiNum'),    f.uiNum    = pivcore.io.pab5Faults.scal(s.uiNum); end
            if isfield(s,'enabled'),  f.enabled  = logical(s.enabled); end   % absen -> default true
            if isfield(s,'psgId'),    f.psgId    = char(s.psgId); end        % absen -> '' (di-migrasi saat load)
            if isfield(s,'hwPosPx'), f.hwPosPx = pivcore.io.pab5Faults.scal(s.hwPosPx); end
            if isfield(s,'fwPosPx'), f.fwPosPx = pivcore.io.pab5Faults.scal(s.fwPosPx); end
            if isfield(s,'nuc'),     f.nuc     = pivcore.io.pab5Faults.scal(s.nuc); end
            if isfield(s,'nucT'),    f.nucT    = pivcore.io.pab5Faults.scal(s.nucT); end   % NUC-T (additive)
            if isfield(s,'fsr'),     f.fsr     = pivcore.io.pab5Faults.scal(s.fsr); end
            if isfield(s,'fsrT'),    f.fsrT    = pivcore.io.pab5Faults.scal(s.fsrT); end   % FSR-T (additive)
            if isfield(s,'startF'),  f.startF  = pivcore.io.pab5Faults.scal(s.startF); end
            if isfield(s,'endF'),    f.endF    = pivcore.io.pab5Faults.scal(s.endF); end
            if isfield(s,'area'),    f.area    = pivcore.io.pab5Faults.scal(s.area); end
            if isfield(s,'dNet'),    f.dNet    = pivcore.io.pab5Faults.scal(s.dNet); end
            if isfield(s,'angleDeg'),f.angleDeg= pivcore.io.pab5Faults.scal(s.angleDeg); end
            if isfield(s,'values'),  f.values  = pivcore.io.pab5Faults.rowv(s.values); end
        end


        function doc = prepForEncode(doc)
            d = pivcore.io.pab5Faults.emptyDoc('');
            fn = fieldnames(d);
            for i = 1:numel(fn)
                if ~isfield(doc, fn{i}), doc.(fn{i}) = d.(fn{i}); end
            end
            if ~iscell(doc.faults)
                doc.faults = pivcore.io.pab5Faults.tocell(doc.faults);
            end
        end


        function d = normDetachment(s)
        %NORMDETACHMENT  Normalkan bidang detachment -> struct('p1',[x y],'p2',[x y]).
        %   Nilai hilang/invalid -> [NaN NaN]. Backward-compat: raw tanpa
        %   detachment ditangani pemanggil (tak memanggil ini).
            d = pivcore.pot.faultAngle.emptyDetachment();
            if ~isstruct(s), return; end
            if isfield(s,'p1'), d.p1 = pivcore.io.pab5Faults.pt2(s.p1); end
            if isfield(s,'p2'), d.p2 = pivcore.io.pab5Faults.pt2(s.p2); end
        end

        function v = pt2(x)
        %PT2  Titik -> baris [x y] double; invalid/kurang elemen -> [NaN NaN].
            v = [NaN NaN];
            if isnumeric(x) && numel(x) >= 2
                x = double(x(:)).'; v = x(1:2);
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
