classdef indexScanner
%INDEXSCANNER  Pemindai folder kerja + manajemen index eksperimen PIVTerry.
%
%   Kelas statik (logika murni, TANPA GUI). Memindai sebuah folder kerja
%   secara rekursif, mengenali setiap "eksperimen" (= berkas data utama
%   PIVLAB), mendeteksi progres yang sudah dikerjakan (POT / PSG / POT-EXP)
%   dari keberadaan berkas sibling, dan menyimpan seluruh daftar (beserta
%   klasifikasi L1-L4 yang di-assign manual oleh pengguna) ke satu berkas
%   index .mat agar bisa dieksplorasi lintas-sesi.
%
%   KONVENSI NAMA (sudah dipakai di repo):
%     - Data utama : <base>.mat                (berkas PIVLAB, biasanya besar)
%     - Progres POT: <base>_pot.mat            (pivcore.io.potSession)
%     - Progres PSG: <base>_psg.mat            (pivcore.io.psgSession)
%     - AutoPOT/POT-EXP: <base>_autopot.mat    (pivcore.io.autopotSession;
%                        POT-EXP tersimpan di field autopotSession.potexp)
%     - Index      : _pivterry_index.mat       (di folder kerja)
%
%   Sebuah berkas dianggap "data utama" bila nama-nya TIDAK berakhiran salah
%   satu suffix progres/index di atas. Klasifikasi (L1-L4) di-assign MANUAL
%   lewat tab Index, lalu dipersistensikan; saat re-scan, klasifikasi lama
%   dipertahankan via mergeClassification.
%
%   STRUKTUR satu entri (struct array `list`):
%     name        char    base name eksperimen (nama berkas tanpa ext)
%     dataFile    char    path penuh berkas data utama ('' bila hanya progres)
%     folder      char    folder tempat berkas berada
%     bytes       double  ukuran data utama (byte; 0 bila tak ada)
%     sizeMB      double  bytes/1e6
%     L1,L2,L3,L4 char    klasifikasi manual (kosong = belum di-assign)
%     done        struct  field logical per kunci checklist (lihat CHECKLIST_DEFS)
%
%   API:
%     defs   = pivcore.io.indexScanner.CHECKLIST_DEFS()
%     list   = pivcore.io.indexScanner.scanFolder(rootDir)
%     merged = pivcore.io.indexScanner.mergeClassification(scanned, saved)
%     S      = pivcore.io.indexScanner.toStruct(list, rootDir)
%     list   = pivcore.io.indexScanner.fromStruct(S)
%     f      = pivcore.io.indexScanner.indexFile(rootDir)
%     pivcore.io.indexScanner.saveIndex(rootDir, list)
%     list   = pivcore.io.indexScanner.loadIndex(rootDir)   % [] bila tak ada
%
%   Penempatan berkas: PIVTerry/+pivterry/+io/indexScanner.m

    methods (Static)

        % ================================================================
        function defs = CHECKLIST_DEFS()
        %CHECKLIST_DEFS  Definisi kolom checklist progres.
        %   Mengembalikan struct array; SATU titik untuk menambah kolom baru:
        %     key    : nama field di entry.done (huruf/angka, valid fieldname)
        %     label  : judul kolom di tabel Index
        %     detect : function handle f(base, folder) -> logical (sudah/blm)
        %
        %   Untuk menambah kolom checklist baru di masa depan, cukup tambahkan
        %   satu baris di sini -- scanner & tabel Index ikut otomatis.
            defs = struct('key', {}, 'label', {}, 'detect', {});

            % --- Step 1 (modul tabStep1) ---
            %   PSG = garis sampling PSG sudah ditetapkan manual per eksperimen.
            %   POT = collect data (titik probing sepanjang garis) sudah selesai.
            %   Keduanya tersimpan di <base>_autopot.mat (step1.psgLine /
            %   potpsg4.records). Lihat pivcore.io.step1Session.
            defs(end+1) = struct('key','PSG1', 'label','PSG', ...
                'detect', @(base, folder) ...
                    pivcore.io.step1Session.hasLine( ...
                        fullfile(folder, [base '.mat'])));
            defs(end+1) = struct('key','POT1', 'label','POT', ...
                'detect', @(base, folder) ...
                    pivcore.io.step1Session.hasPot( ...
                        fullfile(folder, [base '.mat'])));

            % POT-PSG = data mentah analisis bidang sesar (gabungan POT & PSG):
            %   PSG velocity + PSG shear + POT lengkap (records POT-PSG4) +
            %   POT kesimpulan (band POT-PSG5). Terdeteksi dari _autopot.mat
            %   yang ditulis oleh sistem Auto POT baru.
            defs(end+1) = struct('key','POTPSG', 'label','POT-PSG', ...
                'detect', @(base, folder) ...
                    pivcore.io.indexScanner.hasPotPsg( ...
                        fullfile(folder, [base '_autopot.mat'])));

            defs(end+1) = struct('key','POTEXP', 'label','POT-EXP', ...
                'detect', @(base, folder) ...
                    pivcore.io.indexScanner.hasPotExp( ...
                        fullfile(folder, [base '_autopot.mat'])));
        end


        % ================================================================
        function list = scanFolder(rootDir)
        %SCANFOLDER  Pindai rootDir (rekursif) -> struct array eksperimen.
        %   TIDAK memuat berkas data utama (besar); ukuran dibaca dari dir().
            list = pivcore.io.indexScanner.emptyEntry();
            if nargin < 1 || isempty(rootDir) || ~isfolder(rootDir)
                return;
            end

            defs = pivcore.io.indexScanner.CHECKLIST_DEFS();

            D = dir(fullfile(rootDir, '**', '*.mat'));
            for i = 1:numel(D)
                if D(i).isdir, continue; end
                fname  = D(i).name;
                folder = D(i).folder;
                [~, base, ~] = fileparts(fname);

                % Lewati berkas progres & berkas index (bukan data utama).
                % isProgressName mengenali _pot/_psg/_autopot dan
                % _pivterry_index<...>.
                if pivcore.io.indexScanner.isProgressName(base), continue; end

                e          = pivcore.io.indexScanner.scalarEntry();
                e.name     = base;
                e.dataFile = fullfile(folder, fname);
                e.folder   = folder;
                e.bytes    = D(i).bytes;
                e.sizeMB   = D(i).bytes / 1e6;

                for k = 1:numel(defs)
                    try
                        tf = logical(defs(k).detect(base, folder));
                    catch
                        tf = false;
                    end
                    e.done.(defs(k).key) = tf;
                end

                list(end+1) = e; %#ok<AGROW>
            end

            % Urutkan menurut nama agar daftar stabil.
            if ~isempty(list)
                [~, ord] = sort(lower({list.name}));
                list = list(ord);
            end
        end


        % ================================================================
        function merged = mergeClassification(scanned, saved)
        %MERGECLASSIFICATION  Pertahankan L1-L4 (assign manual) dari `saved`
        %   ke hasil `scanned` baru, dicocokkan berdasarkan dataFile (lalu
        %   name sebagai fallback). Status checklist selalu dari `scanned`.
            merged = scanned;
            if isempty(saved) || isempty(scanned), return; end

            savedKeyFile = {saved.dataFile};
            savedKeyName = {saved.name};

            for i = 1:numel(merged)
                j = find(strcmpi(savedKeyFile, merged(i).dataFile), 1);
                if isempty(j)
                    j = find(strcmpi(savedKeyName, merged(i).name), 1);
                end
                if ~isempty(j)
                    merged(i).L1 = saved(j).L1;
                    merged(i).L2 = saved(j).L2;
                    merged(i).L3 = saved(j).L3;
                    merged(i).L4 = saved(j).L4;
                end
            end
        end


        % ================================================================
        function S = toStruct(list, rootDir)
        %TOSTRUCT  Bangun struct index self-describing untuk disimpan.
            if nargin < 2, rootDir = ''; end
            S = struct();
            S.formatName    = 'pivterry_index';
            S.formatVersion = 1;
            S.rootDir       = rootDir;
            S.checklistKeys = {pivcore.io.indexScanner.CHECKLIST_DEFS().key};
            S.entries       = list;   % struct array apa adanya (self-describing)
        end


        % ================================================================
        function list = fromStruct(S)
        %FROMSTRUCT  Pulihkan struct array `list` dari struct index tersimpan.
            list = pivcore.io.indexScanner.emptyEntry();
            if ~isstruct(S) || ~isfield(S, 'entries') || isempty(S.entries)
                return;
            end
            src = S.entries;
            for i = 1:numel(src)
                e = pivcore.io.indexScanner.scalarEntry();
                fn = fieldnames(e);
                for k = 1:numel(fn)
                    if isfield(src(i), fn{k})
                        e.(fn{k}) = src(i).(fn{k});
                    end
                end
                list(end+1) = e; %#ok<AGROW>
            end
        end


        % ================================================================
        function f = indexFile(rootDir)
        %INDEXFILE  Path berkas index UNIK per folder kerja, di dalam folder
        %   itu. Nama = _pivterry_index_<hash8>.mat, dengan <hash8> diturunkan
        %   dari path folder yang dikanonikalisasi -> unik & stabil per folder
        %   (boot berikutnya menemukan kembali index tanpa scan ulang).
            h8 = pivcore.io.indexScanner.pathHash(rootDir);
            nm = sprintf('_pivterry_index_%s.mat', h8);
            f  = fullfile(rootDir, nm);
        end


        % ================================================================
        function tf = indexExists(rootDir)
        %INDEXEXISTS  Apakah berkas index untuk folder ini sudah tersimpan.
            tf = false;
            if isempty(rootDir) || ~isfolder(rootDir), return; end
            tf = isfile(pivcore.io.indexScanner.indexFile(rootDir));
        end


        % ================================================================
        function saveIndex(rootDir, list)
        %SAVEINDEX  Tulis index ke <rootDir>/_pivterry_index_<hash>.mat
        %   (var `pivterryIndex`).
            if isempty(rootDir) || ~isfolder(rootDir)
                error('pivcore:indexScanner:badRoot', ...
                    'Folder kerja tidak valid: %s', rootDir);
            end
            pivterryIndex = pivcore.io.indexScanner.toStruct(list, rootDir); %#ok<NASGU>
            f = pivcore.io.indexScanner.indexFile(rootDir);
            save(f, 'pivterryIndex', '-v7');
        end


        % ================================================================
        function list = scanAndSave(rootDir)
        %SCANANDSAVE  Pindai folder, merge klasifikasi dari index lama (bila
        %   ada), LALU simpan index. Dipakai saat boot pertama / tombol Scan.
            list  = pivcore.io.indexScanner.scanFolder(rootDir);
            saved = pivcore.io.indexScanner.loadIndex(rootDir);
            if ~isempty(saved)
                list = pivcore.io.indexScanner.mergeClassification(list, saved);
            end
            try
                pivcore.io.indexScanner.saveIndex(rootDir, list);
            catch
                % folder read-only: lanjut tanpa menyimpan (non-fatal)
            end
        end


        % ================================================================
        function list = loadIndex(rootDir)
        %LOADINDEX  Muat index dari folder kerja. [] bila tak ada / korup.
            list = [];
            if isempty(rootDir), return; end
            f = pivcore.io.indexScanner.indexFile(rootDir);
            if ~isfile(f), return; end
            try
                S = load(f);
                if isfield(S, 'pivterryIndex')
                    list = pivcore.io.indexScanner.fromStruct(S.pivterryIndex);
                end
            catch
                list = [];
            end
        end


        % ================================================================
        function tf = hasPotPsg(autopotFile)
        %HASPOTPSG  Apakah _autopot.mat memuat data mentah POT-PSG (hasil Auto
        %   POT baru): PSG velocity + PSG shear + POT lengkap (records POT-PSG4)
        %   + POT kesimpulan (band POT-PSG5). Prinsip "index only": hanya
        %   menyentuh berkas progres kecil; lewati bila tak wajar besar.
            tf = false;
            if isempty(autopotFile) || ~isfile(autopotFile), return; end

            di = dir(autopotFile);
            MAXBYTES = 200e6;
            if ~isempty(di) && di(1).bytes > MAXBYTES
                tf = true;   % anggap dikerjakan; jangan load (hemat memori)
                return;
            end

            ap = [];
            try
                mf = matfile(autopotFile);
                w  = whos(mf, 'autopotSession');
                if isempty(w), return; end
                ap = mf.autopotSession;
            catch
                try
                    S  = load(autopotFile, 'autopotSession');
                    if isfield(S, 'autopotSession'), ap = S.autopotSession; end
                catch
                    return;
                end
            end
            if isempty(ap) || ~isstruct(ap) || ~isfield(ap, 'potpsgRaw'), return; end
            pr = ap.potpsgRaw;
            if ~isstruct(pr), return; end
            % Cukup: ada PSG velocity & shear + setidaknya satu record POT-PSG4.
            hasPsg = isfield(pr,'psgVelocity') && ~isempty(pr.psgVelocity) ...
                  && isfield(pr,'psgShear')    && ~isempty(pr.psgShear);
            hasPot = isfield(ap,'potpsg4') && isstruct(ap.potpsg4) ...
                  && isfield(ap.potpsg4,'records') && ~isempty(ap.potpsg4.records);
            tf = hasPsg && hasPot;
        end


        function tf = hasPotExp(autopotFile)
        %HASPOTEXP  Apakah berkas _autopot.mat memuat progres POT-EXP nyata
        %   (>=1 kurva dgn koordinat finite di potexp.points(k).xy).
        %
        %   PRINSIP "index only": JANGAN pernah memuat berkas data utama
        %   (besar). Fungsi ini HANYA menyentuh berkas *_autopot.mat -- berkas
        %   PROGRES yang kecil (~MB). Sebagai pengaman ekstra, berkas autopot
        %   yang ukurannya tak wajar besar (>200 MB) DILEWATI tanpa dimuat;
        %   POT-EXP cukup diasumsikan ada berdasarkan keberadaan berkas saja.
            tf = false;
            if isempty(autopotFile) || ~isfile(autopotFile), return; end

            % Pengaman ukuran: jangan muat berkas progres yang tak wajar besar.
            di = dir(autopotFile);
            MAXBYTES = 200e6;
            if ~isempty(di) && di(1).bytes > MAXBYTES
                tf = true;   % anggap dikerjakan; jangan load (hemat memori)
                return;
            end

            ap = [];
            try
                mf = matfile(autopotFile);
                w  = whos(mf, 'autopotSession');
                if isempty(w), return; end
                ap = mf.autopotSession;
            catch
                try
                    S  = load(autopotFile, 'autopotSession');
                    if isfield(S, 'autopotSession'), ap = S.autopotSession; end
                catch
                    return;
                end
            end
            if isempty(ap) || ~isstruct(ap) || ~isfield(ap, 'potexp'), return; end
            pe = ap.potexp;
            if ~isstruct(pe) || ~isfield(pe, 'points') || isempty(pe.points)
                return;
            end
            for k = 1:numel(pe.points)
                p = pe.points(k);
                if isfield(p, 'xy') && ~isempty(p.xy) && any(isfinite(p.xy(:)))
                    tf = true; return;
                end
            end
        end


        % ================================================================
        function tf = isProgressName(base)
        %ISPROGRESSNAME  Apakah base name berakhiran suffix progres/index
        %   (mis. '..._pot', '..._psg', '..._autopot') atau berkas internal
        %   PIVTerry (apa pun yang berawalan '_pivterry_': index, cache
        %   pratinjau Step-1, dsb) -> BUKAN eksperimen.
            tf = false;
            sfx = {'_pot', '_psg', '_autopot'};
            for k = 1:numel(sfx)
                if numel(base) >= numel(sfx{k}) ...
                        && strcmpi(base(end-numel(sfx{k})+1:end), sfx{k})
                    tf = true; return;
                end
            end
            % Berkas internal PIVTerry (index/cache pratinjau/…) — apa pun yang
            % berawalan _pivterry_ (10 char) bukan eksperimen.
            if numel(base) >= 10 && strcmpi(base(1:10), '_pivterry_')
                tf = true;
            end
        end

    end


    methods (Static, Access = private)

        function e = scalarEntry()
        %SCALARENTRY  Satu entri (1x1) berformat standar, semua field default.
            defs = pivcore.io.indexScanner.CHECKLIST_DEFS();
            done = struct();
            for k = 1:numel(defs)
                done.(defs(k).key) = false;
            end
            e = struct('name','', 'dataFile','', 'folder','', ...
                       'bytes',0, 'sizeMB',0, ...
                       'L1','', 'L2','', 'L3','', 'L4','', ...
                       'done', done);
        end

        function e = emptyEntry()
        %EMPTYENTRY  Struct array 1x0 berformat sama (untuk akumulasi).
            e = pivcore.io.indexScanner.scalarEntry();
            e(1) = [];
        end

        function h8 = pathHash(rootDir)
        %PATHHASH  Hash 8-hex stabil dari path folder yang dikanonikalisasi.
        %   Dipakai untuk nama berkas index unik per folder. Tidak memerlukan
        %   toolbox: pakai DataHash bila tersedia, jika tidak hash sederhana
        %   (djb2) atas string path ter-normalisasi (case-insensitive di
        %   macOS/Windows).
            p = char(rootDir);
            try
                p = char(java.io.File(p).getCanonicalPath());
            catch
                % biarkan apa adanya bila Java tak tersedia
            end
            if ispc || ismac, p = lower(p); end

            v = uint64(5381);
            b = uint64(double(p));
            for i = 1:numel(b)
                v = mod(v * uint64(33) + b(i), uint64(2)^uint64(32));
            end
            h8 = lower(dec2hex(double(v), 8));
            if numel(h8) > 8, h8 = h8(end-7:end); end
        end

    end
end
