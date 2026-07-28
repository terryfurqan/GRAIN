classdef step1Index
%STEP1INDEX  Cache INDEX + PROGRES pra-pemrosesan Step-1 (seri StandAlone) di
%   level folder kerja (root). Logika murni, TANPA GUI.
%
%   Tujuan: pindai sekali SEMUA eksperimen di root + rangkum progres kerja
%   (garis PSG sudah ditetapkan? spacing? sudah disampling?) ke SATU berkas
%   kecil, agar pemuatan berikutnya SANGAT CEPAT (tak perlu membuka sidecar
%   tiap eksperimen lagi). Progres dibaca dari sidecar SUBFOLDER yang ditulis
%   step1.m:  <root>/<base>/<base>_autopot.mat  (lihat pivcore.io.step1Session).
%
%   Berkas index:  <root>/_pivterry_index_step1.mat   (var `step1Index`)
%   Berawalan `_pivterry_index` -> otomatis dilewati indexScanner.isProgressName
%   (oleh scanner ini MAUPUN suite lama), jadi tak pernah disalah-anggap
%   sebagai eksperimen.
%
%   STRUKTUR satu entri (struct array):
%     name        char    base name eksperimen
%     dataFile    char    path penuh berkas data utama (besar)
%     sizeMB      double  ukuran berkas data utama (MB)
%     hasLine     logical garis PSG sudah ditetapkan & diedit
%     spacing     double  spacing sampling (px); NaN bila belum
%     nSamples    double  jumlah titik POT tersampling (0 bila belum)
%     hasPot      logical nSamples > 0
%     startCm     double  posisi awal (cm) kalibrasi skala; NaN bila belum
%     endCm       double  posisi akhir (cm); NaN bila belum
%     lengthCm    double  posisi ujung / panjang (cm); NaN bila belum
%     secPerFrame double  rata-rata interval antar foto (s/frame); NaN bila belum
%     unit        char    satuan tampilan ('cm/s'|'cm/hr'); '' bila belum
%   (lima field skala terakhir = pivcore.pot.units; dibaca dari step1.scale.)
%
%   API:
%     f    = pivcore.io.step1Index.indexFile(root)
%     tf   = pivcore.io.step1Index.exists(root)
%     e    = pivcore.io.step1Index.scanOne(dataFile)          % 1 entri dari sidecar
%     list = pivcore.io.step1Index.scan(root)                 % pindai semua (agak lama)
%     pivcore.io.step1Index.saveIndex(root, list)
%     list = pivcore.io.step1Index.loadIndex(root)            % [] bila tak ada/rusak
%     list = pivcore.io.step1Index.scanAndSave(root)          % pindai + simpan
%     list = pivcore.io.step1Index.updateEntry(list, e)       % sisip/ganti per dataFile
%     list = pivcore.io.step1Index.refreshAndSave(root, dataFile, list)
%
%   Penempatan berkas: PIVTerry/core/+pivcore/+io/step1Index.m

    methods (Static)

        % ================================================================
        function f = indexFile(root)
        %INDEXFILE  Path berkas index di dalam folder kerja.
            f = '';
            if isempty(root) || ~ischar(root), return; end
            f = fullfile(root, '_pivterry_index_step1.mat');
        end


        % ================================================================
        function tf = exists(root)
        %EXISTS  TRUE bila berkas index untuk folder ini sudah ada.
            f = pivcore.io.step1Index.indexFile(root);
            tf = ~isempty(f) && isfile(f);
        end


        % ================================================================
        function e = scanOne(dataFile)
        %SCANONE  Bangun satu entri progres dari sidecar SUBFOLDER eksperimen.
        %   Membaca <dir>/<base>/<base>_autopot.mat SEKALI lalu mengekstrak
        %   garis/spacing/jumlah titik. Tak ada sidecar -> entri "belum apa-apa".
            e = pivcore.io.step1Index.blankEntry();
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [~, base] = fileparts(dataFile);
            e.name     = base;
            e.dataFile = dataFile;
            di = dir(dataFile);
            if ~isempty(di), e.sizeMB = di(1).bytes / 1e6; end

            % Sidecar SE-FOLDER (sibling) — konvensi tunggal, sama dgn main
            % suite & step1Session.autopotPath. (Dulu di subfolder; disatukan.)
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f) || ~isfile(f), return; end
            ap = [];
            try
                S = load(f, 'autopotSession');
                if isfield(S, 'autopotSession'), ap = S.autopotSession; end
            catch
                return;
            end
            if isempty(ap) || ~isstruct(ap), return; end

            if isfield(ap,'step1') && isstruct(ap.step1)
                s1 = ap.step1;
                if isfield(s1,'psgLine') && isstruct(s1.psgLine)
                    ln = s1.psgLine;
                    if isfield(ln,'p1') && isfield(ln,'p2') ...
                            && numel(ln.p1)==2 && numel(ln.p2)==2 ...
                            && all(isfinite(ln.p1)) && all(isfinite(ln.p2))
                        e.hasLine = ~isfield(ln,'edited') || logical(ln.edited);
                    end
                end
                if isfield(s1,'spacing') && isscalar(s1.spacing) && isfinite(s1.spacing)
                    e.spacing = double(s1.spacing);
                end
                if isfield(s1,'scale') && isstruct(s1.scale)
                    sc = pivcore.pot.units.normalize(s1.scale);
                    e.startCm     = sc.startCm;
                    e.endCm       = sc.endCm;
                    e.lengthCm    = sc.lengthCm;
                    e.secPerFrame = sc.secPerFrame;
                    e.unit        = sc.unit;
                end
            end
            if isfield(ap,'potpsg4') && isstruct(ap.potpsg4) ...
                    && isfield(ap.potpsg4,'records')
                e.nSamples = numel(ap.potpsg4.records);
                e.hasPot   = e.nSamples > 0;
            end
        end


        % ================================================================
        function list = scan(root)
        %SCAN  Pindai root (rekursif) -> struct array progres semua eksperimen.
        %   Berkas progres/index dilewati via indexScanner.isProgressName.
            list = pivcore.io.step1Index.emptyArray();
            if isempty(root) || ~isfolder(root), return; end
            D = dir(fullfile(root, '**', '*.mat'));
            for i = 1:numel(D)
                if D(i).isdir, continue; end
                [~, base] = fileparts(D(i).name);
                if pivcore.io.indexScanner.isProgressName(base), continue; end
                df = fullfile(D(i).folder, D(i).name);
                list(end+1) = pivcore.io.step1Index.scanOne(df); %#ok<AGROW>
            end
            if ~isempty(list)
                [~, ord] = sort(lower({list.name}));
                list = list(ord);
            end
        end


        % ================================================================
        function saveIndex(root, list)
        %SAVEINDEX  Tulis index ke <root>/_pivterry_index_step1.mat.
            f = pivcore.io.step1Index.indexFile(root);
            if isempty(f) || ~isfolder(root)
                error('pivcore:step1Index:badRoot', ...
                    'Folder kerja tidak valid: %s', root);
            end
            S = struct('step1Index', ...
                pivcore.io.step1Index.toStruct(list, root));
            save(f, '-struct', 'S');     % menulis var `step1Index`
        end


        % ================================================================
        function list = loadIndex(root)
        %LOADINDEX  Muat index dari folder kerja. [] bila tak ada / rusak /
        %   skema tak cocok (-> pemanggil sebaiknya scan ulang).
            list = [];
            f = pivcore.io.step1Index.indexFile(root);
            if isempty(f) || ~isfile(f), return; end
            try
                S = load(f, 'step1Index');
            catch
                return;
            end
            if ~isfield(S,'step1Index') || ~isstruct(S.step1Index) ...
                    || ~isfield(S.step1Index,'entries')
                return;
            end
            ent = S.step1Index.entries;
            if ~isstruct(ent), return; end
            req = {'name','dataFile','sizeMB','hasLine','spacing','nSamples','hasPot', ...
                   'startCm','endCm','lengthCm','secPerFrame','unit'};
            if ~isempty(ent) && ~all(isfield(ent, req)), return; end
            list = ent;
        end


        % ================================================================
        function list = scanAndSave(root)
        %SCANANDSAVE  Pindai folder LALU simpan index. Dipakai saat boot
        %   pertama / tombol "Segarkan".
            list = pivcore.io.step1Index.scan(root);
            try
                pivcore.io.step1Index.saveIndex(root, list);
            catch
                % folder read-only: lanjut tanpa menyimpan (non-fatal)
            end
        end


        % ================================================================
        function list = updateEntry(list, e)
        %UPDATEENTRY  Sisipkan/ganti entri `e` di `list` dicocokkan berdasarkan
        %   dataFile. Menjaga urutan (ganti di tempat bila sudah ada).
            if isempty(e) || ~isstruct(e) || ~isfield(e,'dataFile'), return; end
            if isempty(list), list = e; return; end
            j = find(strcmpi({list.dataFile}, e.dataFile), 1);
            if isempty(j)
                list(end+1) = e;
            else
                list(j) = e;
            end
        end


        % ================================================================
        function list = refreshAndSave(root, dataFile, list)
        %REFRESHANDSAVE  Baca ulang progres SATU eksperimen dari sidecar-nya,
        %   perbarui `list`, lalu simpan index. Dipakai setelah Simpan di GUI
        %   agar cache tetap mutakhir tanpa pindai-ulang seluruh folder.
            e = pivcore.io.step1Index.scanOne(dataFile);
            list = pivcore.io.step1Index.updateEntry(list, e);
            try
                pivcore.io.step1Index.saveIndex(root, list);
            catch
            end
        end


        % ================================================================
        function S = toStruct(list, root)
        %TOSTRUCT  Bangun struct index self-describing untuk disimpan.
            S = struct();
            S.formatName    = 'PIVTerry Step1 Index';
            S.formatVersion = 2;   % v2: + field skala (startCm/endCm/lengthCm/secPerFrame/unit)
            S.rootDir       = char(root);
            S.savedAt       = char(datetime('now'));
            S.entries       = list;
        end


        % ================================================================
        function e = blankEntry()
        %BLANKENTRY  Satu entri (1x1) berformat standar, nilai default.
            e = struct('name','', 'dataFile','', 'sizeMB',0, ...
                       'hasLine',false, 'spacing',NaN, 'nSamples',0, 'hasPot',false, ...
                       'startCm',NaN, 'endCm',NaN, 'lengthCm',NaN, ...
                       'secPerFrame',NaN, 'unit','');
        end


        % ================================================================
        function e = emptyArray()
        %EMPTYARRAY  Struct array 1x0 berformat sama (untuk akumulasi).
            e = pivcore.io.step1Index.blankEntry();
            e(1) = [];
        end

    end
end
