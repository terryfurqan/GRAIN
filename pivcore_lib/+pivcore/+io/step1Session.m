classdef step1Session
%STEP1SESSION  I/O stateless modul Step 1: baca/tulis GARIS PSG manual +
%   status collect data (titik POT-PSG4) ke berkas progres <base>_autopot.mat,
%   serta deteksi progres untuk tab Index. TANPA GUI/handle figure.
%
%   Konvensi berkas (sama dgn sistem yg ada): data utama <base>.mat dan
%   progres <base>_autopot.mat selalu di folder yg sama. Penulisan bersifat
%   READ-MODIFY-WRITE atas variabel `autopotSession` agar progres lain
%   (potexp, potpsg3/4, potpsgRaw, ...) TIDAK hilang.
%
%   Garis PSG Step-1 disimpan di autopotSession.step1.psgLine = struct(
%       'p1',[x y], 'p2',[x y], 'orient',struct(...))  % orient: flip/rot flags
%   Titik hasil collect disimpan di autopotSession.potpsg4.records (format
%   pivcore.pot.potpsg4Model), kompatibel dgn autopotSession.applyPotPsg4.
%
%   API:
%     f    = pivcore.io.step1Session.autopotPath(dataFile)
%     L    = pivcore.io.step1Session.loadLine(dataFile)     % [] bila tak ada
%     pivcore.io.step1Session.saveLine(dataFile, p1, p2 [, orient])
%     data1= pivcore.io.step1Session.loadFrame1(dataFile)   % data 1-bingkai
%     tf   = pivcore.io.step1Session.hasLine(dataFile)
%     tf   = pivcore.io.step1Session.hasPot(dataFile)
%     pivcore.io.step1Session.saveRecords(dataFile, records [, line])
%
%   Penempatan berkas: PIVTerry/+pivterry/+io/step1Session.m

    methods (Static)

        % ================================================================
        function f = autopotPath(dataFile)
        %AUTOPOTPATH  Path <dir>/<base>_autopot.mat untuk berkas data utama.
            f = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            f = fullfile(d, sprintf('%s_autopot.mat', base));
        end


        % ================================================================
        function L = loadLine(dataFile)
        %LOADLINE  Baca garis PSG Step-1 dari <base>_autopot.mat. [] bila tak
        %   ada berkas / field. Mengembalikan struct p1/p2/orient.
        %
        %   FALLBACK lintas-modul: bila step1.psgLine TIDAK ADA (mis. berkas
        %   _autopot dibuat AutoPOT/POT-PSG4 lama, BUKAN Step 1), pakai garis
        %   yang sudah ada di situ -> `lineSnap` (AutoPOT) lalu `potpsgRaw.line`.
        %   Ini PENTING: tanpa fallback, Step 1 tak tahu garis (sering DIAGONAL
        %   mengikuti morfologi) yang dipakai POT-PSG4 -> sampling di garis
        %   default (horizontal) -> kurva BERBEDA. Dgn fallback, Step 1 memakai
        %   garis yang SAMA -> sampling identik.
            L = [];
            ap = pivcore.io.step1Session.readSession(dataFile);
            if isempty(ap) || ~isstruct(ap), return; end

            % 1) Sumber utama: step1.psgLine (ditulis modul Step 1).
            ln = [];
            if isfield(ap,'step1') && isstruct(ap.step1) ...
                    && isfield(ap.step1,'psgLine') && isstruct(ap.step1.psgLine)
                ln = ap.step1.psgLine;
            end
            L = i_lineFrom(ln);
            if ~isempty(L), return; end

            % 2) Fallback: lineSnap (AutoPOT) -> garis sampling PSG aktual.
            if isfield(ap,'lineSnap') && isstruct(ap.lineSnap)
                L = i_lineFrom(ap.lineSnap);
                if ~isempty(L), return; end
            end

            % 3) Fallback: potpsgRaw.line.
            if isfield(ap,'potpsgRaw') && isstruct(ap.potpsgRaw) ...
                    && isfield(ap.potpsgRaw,'line') && isstruct(ap.potpsgRaw.line)
                L = i_lineFrom(ap.potpsgRaw.line);
                if ~isempty(L), return; end
            end
        end


        % ================================================================
        function saveLine(dataFile, p1, p2, orient, edited)
        %SAVELINE  Tulis garis PSG Step-1 ke <base>_autopot.mat (read-modify-
        %   write). Membuat berkas baru bila belum ada. TIDAK menyentuh
        %   progres lain.
        %   `edited` (default true): TRUE = garis ditetapkan sungguh oleh
        %   pengguna (bukan midline default). hasLine hanya TRUE bila edited
        %   -> kolom PSG di Index/daftar tercentang hanya saat garis betul-
        %   betul disesuaikan, bukan saat masih di posisi tengah default.
            if nargin < 4, orient = struct(); end
            if nargin < 5, edited = true; end
            p1 = p1(:).'; p2 = p2(:).';
            if numel(p1) ~= 2 || numel(p2) ~= 2 ...
                    || any(~isfinite(p1)) || any(~isfinite(p2))
                error('pivcore:step1Session:badLine', ...
                    'Garis tidak valid: p1/p2 harus [x y] finite.');
            end
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f)
                error('pivcore:step1Session:noPath', ...
                    'Tak bisa menentukan path _autopot untuk: %s', dataFile);
            end
            ap = pivcore.io.step1Session.readSession(dataFile);
            ap = pivcore.io.step1Session.ensureSession(ap, dataFile);
            ap.step1.psgLine = struct('p1', p1, 'p2', p2, ...
                'edited', logical(edited), ...
                'orient', pivcore.io.step1Session.normOrient(orient));
            autopotSession = ap; %#ok<NASGU>
            save(f, 'autopotSession', '-v7');
        end


        % ================================================================
        function saveRecords(dataFile, records, line)
        %SAVERECORDS  Tulis titik hasil collect (records POT-PSG4) ke
        %   <base>_autopot.mat (read-modify-write). Bila `line` diberikan,
        %   pastikan step1.psgLine ikut tersimpan. TIDAK menyentuh progres
        %   lain.
            if nargin < 3, line = []; end
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f)
                error('pivcore:step1Session:noPath', ...
                    'Tak bisa menentukan path _autopot untuk: %s', dataFile);
            end
            ap = pivcore.io.step1Session.readSession(dataFile);
            ap = pivcore.io.step1Session.ensureSession(ap, dataFile);
            if ~isfield(ap,'potpsg4') || ~isstruct(ap.potpsg4)
                ap.potpsg4 = struct();
            end
            ap.potpsg4.records = records;
            if ~isfield(ap.potpsg4,'cutOn'), ap.potpsg4.cutOn = false; end
            if ~isempty(line) && isstruct(line) ...
                    && isfield(line,'p1') && isfield(line,'p2')
                ap.step1.psgLine = struct('p1', line.p1(:).', 'p2', line.p2(:).', ...
                    'orient', pivcore.io.step1Session.normOrient( ...
                        i_getf(line,'orient',struct())));
            end
            autopotSession = ap; %#ok<NASGU>
            save(f, 'autopotSession', '-v7');
        end


        % ================================================================
        function saveBands(dataFile, bands)
        %SAVEBANDS  Tulis band agregasi Step-3 (potpsg5) ke <base>_autopot.mat
        %   (read-modify-write field `potpsg5Bands`). Ringan: TIDAK butuh shear
        %   AutoPOT. TIDAK menyentuh progres lain.
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f)
                error('pivcore:step1Session:noPath', ...
                    'Tak bisa menentukan path _autopot untuk: %s', dataFile);
            end
            ap = pivcore.io.step1Session.readSession(dataFile);
            ap = pivcore.io.step1Session.ensureSession(ap, dataFile);
            ap.potpsg5Bands = bands;
            autopotSession = ap; %#ok<NASGU>
            save(f, 'autopotSession', '-v7');
        end


        % ================================================================
        function bands = loadBands(dataFile)
        %LOADBANDS  Baca band agregasi Step-3 dari <base>_autopot.mat. []
        %   bila tak ada.
            bands = [];
            ap = pivcore.io.step1Session.readSession(dataFile);
            if isempty(ap) || ~isstruct(ap), return; end
            if isfield(ap,'potpsg5Bands'), bands = ap.potpsg5Bands; end
        end


        % ================================================================
        function saveAssignments(dataFile, assign, records, indenter)
        %SAVEASSIGNMENTS  Tulis assignment kurva Step-3 (HW-#/F-#/F0) ke
        %   <base>_autopot.mat (read-modify-write). Menyimpan:
        %     ap.step3Assign     = struct-array agregat (label/type/num/curveIdx/
        %                          color/feat)
        %     ap.potpsg4.records = records dgn field `assignLabel` terisi
        %     ap.step3Indenter   = envelope MAX (vektor) "Maximum Indenter" bila
        %                          diberikan (auto-save dari Step 3)
        %   Ringan & TIDAK menyentuh progres lain (shear AutoPOT, garis, dst).
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f)
                error('pivcore:step1Session:noPath', ...
                    'Tak bisa menentukan path _autopot untuk: %s', dataFile);
            end
            ap = pivcore.io.step1Session.readSession(dataFile);
            ap = pivcore.io.step1Session.ensureSession(ap, dataFile);
            ap.step3Assign = assign;
            if nargin >= 3 && ~isempty(records)
                if ~isfield(ap,'potpsg4') || ~isstruct(ap.potpsg4)
                    ap.potpsg4 = struct();
                end
                ap.potpsg4.records = records;
            end
            if nargin >= 4
                ap.step3Indenter = indenter(:).';
            end
            autopotSession = ap; %#ok<NASGU>
            save(f, 'autopotSession', '-v7');
        end


        % ================================================================
        function assign = loadAssignments(dataFile)
        %LOADASSIGNMENTS  Baca assignment kurva Step-3 dari <base>_autopot.mat.
        %   [] bila tak ada.
            assign = [];
            ap = pivcore.io.step1Session.readSession(dataFile);
            if isempty(ap) || ~isstruct(ap), return; end
            if isfield(ap,'step3Assign'), assign = ap.step3Assign; end
        end


        % ================================================================
        function saveContacts(dataFile, contacts)
        %SAVECONTACTS  Tulis titik kontak Step-3v2 ke <base>_autopot.mat (RMW):
        %   ap.step3v2Contacts = struct-array (i/j/frame/value/label). Ringan &
        %   tak menyentuh progres lain. Dipakai tab Step 3v2 (deteksi kontak).
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f)
                error('pivcore:step1Session:noPath', ...
                    'Tak bisa menentukan path _autopot untuk: %s', dataFile);
            end
            ap = pivcore.io.step1Session.readSession(dataFile);
            ap = pivcore.io.step1Session.ensureSession(ap, dataFile);
            ap.step3v2Contacts = contacts;
            autopotSession = ap; %#ok<NASGU>
            save(f, 'autopotSession', '-v7');
        end


        % ================================================================
        function contacts = loadContacts(dataFile)
        %LOADCONTACTS  Baca titik kontak Step-3v2 dari <base>_autopot.mat.
        %   [] bila tak ada.
            contacts = [];
            ap = pivcore.io.step1Session.readSession(dataFile);
            if isempty(ap) || ~isstruct(ap), return; end
            if isfield(ap,'step3v2Contacts'), contacts = ap.step3v2Contacts; end
        end


        % ================================================================
        function saveRecordsBoth(dataFile, velRecs, shearRecs, line)
        %SAVERECORDSBOTH  Simpan DUA set records dari satu garis PSG:
        %   velocity_magnitude -> potpsg4.records (utama; dipakai Step 2/3/
        %   export & POT-PSG4), shear_rate -> step1.shearRecords (paralel).
        %   Read-modify-write; tak menyentuh progres lain.
            if nargin < 4, line = []; end
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f)
                error('pivcore:step1Session:noPath', ...
                    'Tak bisa menentukan path _autopot untuk: %s', dataFile);
            end
            ap = pivcore.io.step1Session.readSession(dataFile);
            ap = pivcore.io.step1Session.ensureSession(ap, dataFile);
            if ~isfield(ap,'potpsg4') || ~isstruct(ap.potpsg4)
                ap.potpsg4 = struct();
            end
            ap.potpsg4.records = velRecs;
            if ~isfield(ap.potpsg4,'cutOn'), ap.potpsg4.cutOn = false; end
            ap.step1.shearRecords = shearRecs;
            if ~isempty(line) && isstruct(line) ...
                    && isfield(line,'p1') && isfield(line,'p2')
                ap.step1.psgLine = struct('p1', line.p1(:).', 'p2', line.p2(:).', ...
                    'orient', pivcore.io.step1Session.normOrient( ...
                        i_getf(line,'orient',struct())));
            end
            autopotSession = ap; %#ok<NASGU>
            save(f, 'autopotSession', '-v7');
        end


        % ================================================================
        function saveStep4Points(dataFile, step4)
        %SAVESTEP4POINTS  Tulis identifikasi titik Step-4 (Start/NUC/FSR/END per
        %   Hanging Wall) ke <base>_autopot.mat (read-modify-write):
        %     ap.step4Points = struct('pts', struct-array(hw/startF/nclF/fsrF/
        %                              endF), 'savedAt', char)
        %   Ringan & TIDAK menyentuh progres lain (garis, records, step3Assign).
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f)
                error('pivcore:step1Session:noPath', ...
                    'Tak bisa menentukan path _autopot untuk: %s', dataFile);
            end
            ap = pivcore.io.step1Session.readSession(dataFile);
            ap = pivcore.io.step1Session.ensureSession(ap, dataFile);
            ap.step4Points = step4;
            autopotSession = ap; %#ok<NASGU>
            save(f, 'autopotSession', '-v7');
        end


        % ================================================================
        function step4 = loadStep4Points(dataFile)
        %LOADSTEP4POINTS  Baca identifikasi titik Step-4 dari <base>_autopot.mat.
        %   [] bila tak ada.
            step4 = [];
            ap = pivcore.io.step1Session.readSession(dataFile);
            if isempty(ap) || ~isstruct(ap), return; end
            if isfield(ap,'step4Points'), step4 = ap.step4Points; end
        end


        % ================================================================
        function tf = hasStep4(dataFile)
        %HASSTEP4  TRUE bila eksperimen sudah punya >=1 titik Step-4 yang
        %   diidentifikasi (Start/NUC/FSR/END pada salah satu HW). "Index only":
        %   hanya menyentuh berkas progres kecil (tanpa load data utama).
            tf = false;
            ap = pivcore.io.step1Session.readSession(dataFile);
            if isempty(ap) || ~isstruct(ap), return; end
            if ~isfield(ap,'step4Points'), return; end
            s4 = ap.step4Points;
            if ~isstruct(s4) || ~isfield(s4,'pts') || isempty(s4.pts), return; end
            pts = s4.pts;
            for k = 1:numel(pts)
                for fld = {'startF','nclF','fsrF','endF'}
                    if isfield(pts(k),fld{1})
                        v = pts(k).(fld{1});
                        if isscalar(v) && isfinite(v), tf = true; return; end
                    end
                end
            end
        end


        % ================================================================
        function recs = loadShearRecords(dataFile)
        %LOADSHEARRECORDS  Baca records shear_rate (step1.shearRecords) dari
        %   <base>_autopot.mat. [] bila tak ada.
            recs = [];
            ap = pivcore.io.step1Session.readSession(dataFile);
            if isempty(ap) || ~isstruct(ap), return; end
            if ~isfield(ap,'step1') || ~isstruct(ap.step1), return; end
            if isfield(ap.step1,'shearRecords'), recs = ap.step1.shearRecords; end
        end


        % ================================================================
        function tf = hasLine(dataFile)
        %HASLINE  TRUE bila garis PSG Step-1 sudah DITETAPKAN/DIEDIT pengguna
        %   (bukan midline default). Index only. Garis yang tersimpan tapi
        %   masih ber-flag edited=false (mis. posisi tengah) -> FALSE.
            L = pivcore.io.step1Session.loadLine(dataFile);
            tf = ~isempty(L) && isfield(L,'edited') && L.edited;
        end


        % ================================================================
        function tf = hasPot(dataFile)
        %HASPOT  TRUE bila collect data sudah selesai (>=1 record POT-PSG4).
        %   "Index only": hanya menyentuh berkas progres kecil; berkas
        %   _autopot tak wajar besar (>200 MB) dianggap dikerjakan tanpa load.
            tf = false;
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f) || ~isfile(f), return; end
            di = dir(f);
            if ~isempty(di) && di(1).bytes > 200e6, tf = true; return; end
            ap = pivcore.io.step1Session.readSession(dataFile);
            if isempty(ap) || ~isstruct(ap), return; end
            if ~isfield(ap,'potpsg4') || ~isstruct(ap.potpsg4), return; end
            if ~isfield(ap.potpsg4,'records'), return; end
            tf = ~isempty(ap.potpsg4.records);
        end


        % ================================================================
        function data1 = loadFrame1(dataFile)
        %LOADFRAME1  Bangun struct `data` RINGAN berisi HANYA bingkai 1
        %   (nFrames=1) untuk menampilkan eksperimen di axMain & mengedit
        %   garis PSG.
        %
        %   Berkas data PIVLAB berformat MATLAB v7.3/HDF5 berukuran ratusan MB
        %   (tiap bingkai = dataset HDF5 terpisah). Karena itu kita coba
        %   PARTIAL-LOAD lewat matfile() -> hanya bingkai-1 yang dibaca dari
        %   disk, bukan seluruh deret-waktu. Bila partial-load gagal (mis.
        %   berkas v5/v7 yang tak mendukung indexing matfile cell), kita
        %   FALLBACK ke load penuh + trimToFrame1 (perilaku lama, tetap benar).
            if isempty(dataFile) || ~isfile(dataFile)
                error('pivcore:step1Session:noData', ...
                    'Berkas data tidak ditemukan: %s', dataFile);
            end
            % Partial-load HANYA bermanfaat untuk berkas v7.3/HDF5 (tiap bingkai
            % = dataset terpisah -> matfile membacanya lazy). Untuk v5/v7,
            % matfile-indexing malah memuat seluruh variabel ke memori
            % (inefficientPartialLoad) + memunculkan warning -> langsung
            % fallback ke load penuh (perilaku lama, tetap benar).
            if pivcore.io.step1Session.isV73(dataFile)
                try
                    data1 = pivcore.io.step1Session.loadFrame1Partial(dataFile);
                catch
                    data1 = [];   % degradasi ke fallback di bawah
                end
                if ~isempty(data1) && isstruct(data1) ...
                        && isfield(data1,'nFrames') && data1.nFrames >= 1
                    return;
                end
            end
            % --- Fallback: load penuh lalu pangkas (perilaku lama) ---
            S = load(dataFile);
            S = pivcore.io.step1Session.trimToFrame1(S);
            data1 = pivcore.data.buildDataset(S);
        end


        function tf = isV73(dataFile)
        %ISV73  True bila berkas .mat berformat MATLAB 7.3 (HDF5). Dibaca dari
        %   128 byte header teks ("MATLAB 7.3 MAT-file ..."). Murah & andal.
            tf = false;
            fid = fopen(dataFile, 'r');
            if fid < 0, return; end
            hdr = fread(fid, 116, '*char')';
            fclose(fid);
            tf = ~isempty(strfind(hdr, 'MATLAB 7.3')); %#ok<STREMP>
        end


        function data1 = loadFrame1Partial(dataFile)
        %LOADFRAME1PARTIAL  Muat HANYA bingkai-1 lewat matfile() (lazy HDF5).
        %   Untuk berkas v7.3, `mf.(name)(1,1)` hanya menyentuh byte bingkai-1
        %   pada disk, bukan seluruh cell-array -> hemat ratusan MB & cepat.
        %
        %   Hanya field per-bingkai (cell) yang dipangkas ke {1}; skalar/meta
        %   dibaca utuh (kecil). Background: jpeg_dedup_v1 baca blob + index(1);
        %   skema lama baca bg_images{1}. Hasil dirakit jadi struct lalu
        %   diberikan ke pivcore.data.buildDataset (TANPA perubahan) sehingga
        %   bentuknya identik dgn jalur trimToFrame1+buildDataset.
        %
        %   Melempar error bila matfile tak bisa membuka berkas -> pemanggil
        %   (loadFrame1) menangkapnya dan fallback ke load penuh.
            mf = matfile(dataFile);             % lempar bila tak terbaca
            info = whos(mf);                    % daftar var + kelas (murah)
            names = {info.name};
            classes = {info.class};

            % Field per-bingkai yg dibaca buildDataset (termasuk alias).
            frameFields = { ...
                'x','y', ...
                'u_original','v_original','u_filtered','v_filtered', ...
                'u_smoothed','v_smoothed','u_component','v_component', ...
                'velocity_magnitude','vorticity','divergence','shear_rate', ...
                'strain_rate','q_criterion','LIC','vectorangle', ...
                'correlation_map','correlation_m','correlation_matrix', ...
                'typevector_original','typevector_or', ...
                'typevector_filtered','typevector_filt'};
            % Skalar/metadata yg dibaca buildDataset (dibaca utuh; kecil).
            scalarFields = {'calu','calv','calxy','units','information'};
            S = struct();

            % --- 1. Field per-bingkai: ambil HANYA elemen {1} bila cell ---
            for k = 1:numel(frameFields)
                nm = frameFields{k};
                ix = find(strcmp(names, nm), 1);
                if isempty(ix), continue; end
                try
                    if strcmp(classes{ix}, 'cell')
                        S.(nm) = mf.(nm)(1,1);      % 1x1 cell -> hanya frame 1
                    else
                        S.(nm) = mf.(nm);           % non-cell: buildDataset abaikan
                    end
                catch
                    % Field aneh -> lewati; buildDataset cukup toleran.
                end
            end

            % --- 2. Skalar / metadata: baca utuh ---
            for k = 1:numel(scalarFields)
                nm = scalarFields{k};
                if any(strcmp(names, nm))
                    try, S.(nm) = mf.(nm); catch, end %#ok<NOSEM,CTCH>
                end
            end

            % --- 3. Background: jpeg_dedup_v1 atau cell lama, bingkai-1 saja ---
            if any(strcmp(names,'bg_images_format')) ...
                    && any(strcmp(names,'bg_images_blobs')) ...
                    && any(strcmp(names,'bg_images_index'))
                try
                    S.bg_images_format = mf.bg_images_format;     % char kecil
                    S.bg_images_blobs  = mf.bg_images_blobs;      % JPEG dedup (kecil)
                    idx = mf.bg_images_index;                     % vektor uint32
                    if ~isempty(idx), S.bg_images_index = idx(1); end
                    if any(strcmp(names,'bg_images_quality'))
                        S.bg_images_quality = mf.bg_images_quality;
                    end
                catch
                    % biarkan tanpa background bila gagal
                end
            else
                % Skema lama: cell uint8 -> ambil frame 1 saja.
                for k = 1:numel({'bg_images','images','bg_img_A','background_images'})
                    cand = {'bg_images','images','bg_img_A','background_images'};
                    nm = cand{k};
                    ix = find(strcmp(names, nm), 1);
                    if isempty(ix), continue; end
                    try
                        if strcmp(classes{ix}, 'cell')
                            S.(nm) = mf.(nm)(1,1);
                        else
                            S.(nm) = mf.(nm);
                        end
                    catch
                    end
                    break;   % satu sumber bg cukup
                end
            end

            data1 = pivcore.data.buildDataset(S);
        end


        function data = loadAllFrames(dataFile)
        %LOADALLFRAMES  Bangun struct `data` PENUH (semua bingkai) untuk Step 3
        %   mode "All frames" (slider men-scrub citra PIV tiap bingkai).
        %
        %   Sama strategi dgn loadFrame1: untuk berkas v7.3/HDF5, PARTIAL-LOAD
        %   lewat matfile() -> baca HANYA variabel yang dibaca buildDataset
        %   (channel + bg), LEWATI variabel lain di berkas (mis. sesi/scratch
        %   PIVLAB yg tak dipakai axMain). Ini hemat I/O + RAM tanpa mengubah
        %   daftar channel di dropdown (fieldMap buildDataset yang menentukan,
        %   identik dgn jalur load penuh). Bila partial gagal / berkas v5/v7,
        %   FALLBACK ke load() penuh + buildDataset (perilaku lama, tetap benar).
            if isempty(dataFile) || ~isfile(dataFile)
                error('pivcore:step1Session:noData', ...
                    'Berkas data tidak ditemukan: %s', dataFile);
            end
            if pivcore.io.step1Session.isV73(dataFile)
                try
                    data = pivcore.io.step1Session.loadAllFramesPartial(dataFile);
                catch
                    data = [];   % degradasi ke fallback
                end
                if ~isempty(data) && isstruct(data) ...
                        && isfield(data,'nFrames') && data.nFrames >= 1
                    return;
                end
            end
            % --- Fallback: load penuh (perilaku lama) ---
            S    = load(dataFile);
            data = pivcore.data.buildDataset(S);
        end


        function data = loadAllFramesPartial(dataFile)
        %LOADALLFRAMESPARTIAL  Muat SEMUA bingkai lewat matfile() (lazy HDF5),
        %   tetapi HANYA variabel yang dibaca buildDataset. Cell per-bingkai
        %   dibaca UTUH (semua frame, beda dari loadFrame1Partial yg memangkas
        %   ke {1}); skalar/meta & background dibaca utuh. Variabel lain dalam
        %   berkas (sesi PIVLAB, dsb) TIDAK disentuh -> hemat I/O & memori.
        %
        %   Melempar error bila matfile tak bisa membuka berkas -> pemanggil
        %   (loadAllFrames) menangkapnya dan fallback ke load penuh.
            mf = matfile(dataFile);             % lempar bila tak terbaca
            info = whos(mf);                    % daftar var + kelas (murah)
            names = {info.name};

            % Field per-bingkai yg dibaca buildDataset (termasuk alias) +
            % skalar/metadata. Sama daftar dgn loadFrame1Partial, TANPA
            % memangkas cell -> seluruh deret-waktu dibaca.
            wantFields = { ...
                'x','y', ...
                'u_original','v_original','u_filtered','v_filtered', ...
                'u_smoothed','v_smoothed','u_component','v_component', ...
                'velocity_magnitude','vorticity','divergence','shear_rate', ...
                'strain_rate','q_criterion','LIC','vectorangle', ...
                'correlation_map','correlation_m','correlation_matrix', ...
                'typevector_original','typevector_or', ...
                'typevector_filtered','typevector_filt', ...
                'calu','calv','calxy','units','information'};
            S = struct();
            for k = 1:numel(wantFields)
                nm = wantFields{k};
                if ~any(strcmp(names, nm)), continue; end
                try
                    S.(nm) = mf.(nm);           % baca utuh (semua frame)
                catch
                    % Field aneh -> lewati; buildDataset cukup toleran.
                end
            end

            % --- Background: jpeg_dedup_v1 (blob+index penuh) atau cell lama ---
            if any(strcmp(names,'bg_images_format')) ...
                    && any(strcmp(names,'bg_images_blobs')) ...
                    && any(strcmp(names,'bg_images_index'))
                for nm = {'bg_images_format','bg_images_blobs','bg_images_index','bg_images_quality'}
                    if any(strcmp(names, nm{1}))
                        try, S.(nm{1}) = mf.(nm{1}); catch, end %#ok<NOSEM,CTCH>
                    end
                end
            else
                cand = {'bg_images','images','bg_img_A','background_images'};
                for k = 1:numel(cand)
                    nm = cand{k};
                    if ~any(strcmp(names, nm)), continue; end
                    try, S.(nm) = mf.(nm); catch, end %#ok<NOSEM,CTCH>
                    break;   % satu sumber bg cukup
                end
            end

            data = pivcore.data.buildDataset(S);
        end


        % ================================================================
        function sp = savedSpacing(dataFile)
        %SAVEDSPACING  Baca spacing tersimpan (autopotSession.step1.spacing) dari
        %   sidecar SE-FOLDER. NaN bila tak ada. (Port dari step1 i_savedSpacing.)
            sp = NaN;
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f) || ~isfile(f), return; end
            try
                S = load(f, 'autopotSession');
            catch
                return;
            end
            if ~isfield(S,'autopotSession'), return; end
            ap = S.autopotSession;
            if isstruct(ap) && isfield(ap,'step1') && isstruct(ap.step1) ...
                    && isfield(ap.step1,'spacing')
                v = ap.step1.spacing;
                if isscalar(v) && isfinite(v), sp = double(v); end
            end
        end


        function saveStep1Meta(dataFile, spacing, dispSrc)
        %SAVESTEP1META  Sisipkan spacing & sumber tampilan ke autopotSession.step1
        %   (read-modify-write ringan, sidecar SE-FOLDER). Panggil SETELAH
        %   saveLine/saveRecords menulis berkasnya. (Port dari step1 i_stashStep1Meta.)
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f) || ~isfile(f), return; end
            S = load(f, 'autopotSession');
            if ~isfield(S,'autopotSession'), return; end
            ap = S.autopotSession;
            if ~isfield(ap,'step1') || ~isstruct(ap.step1), ap.step1 = struct(); end
            ap.step1.spacing = spacing;
            ap.step1.dispSrc = dispSrc;
            autopotSession = ap; %#ok<NASGU>
            save(f, 'autopotSession', '-v7');
        end


        function saveScale(dataFile, scale)
        %SAVESCALE  Sisipkan kalibrasi ruang+waktu Step-1 (posisi cm awal/akhir/
        %   ujung + detik per bingkai + satuan tampilan) ke
        %   autopotSession.step1.scale (read-modify-write ringan, sidecar
        %   SE-FOLDER). Dipakai Step 1 saat pengguna mengisi kolom skala di
        %   tabel; Step 2 membacanya utk menampilkan kurva POT dlm cm/s atau
        %   cm/hr. Deret RAW records (px/frame) TIDAK diubah -> konversi murni
        %   tampilan. Membuat berkas baru bila belum ada. TIDAK menyentuh
        %   progres lain (garis, spacing, records, step3/4, ...).
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f)
                error('pivcore:step1Session:noPath', ...
                    'Tak bisa menentukan path _autopot untuk: %s', dataFile);
            end
            scale = pivcore.pot.units.normalize(scale);
            scale.savedAt = char(datetime('now'));
            ap = pivcore.io.step1Session.readSession(dataFile);
            ap = pivcore.io.step1Session.ensureSession(ap, dataFile);
            ap.step1.scale = scale;
            autopotSession = ap; %#ok<NASGU>
            save(f, 'autopotSession', '-v7');
        end


        function scale = loadScale(dataFile)
        %LOADSCALE  Baca kalibrasi Step-1 (autopotSession.step1.scale) dari
        %   sidecar SE-FOLDER, dikembalikan ter-normalisasi (pivcore.pot.units).
        %   [] bila tak ada berkas/field -> pemanggil pakai default mentah
        %   (tampilan px/frame).
            scale = [];
            ap = pivcore.io.step1Session.readSession(dataFile);
            if isempty(ap) || ~isstruct(ap), return; end
            if ~isfield(ap,'step1') || ~isstruct(ap.step1), return; end
            if ~isfield(ap.step1,'scale'), return; end
            scale = pivcore.pot.units.normalize(ap.step1.scale);
        end


        function n = collectAndSave(dataFile)
        %COLLECTANDSAVE  Sampel ulang SATU eksperimen dari disk (headless): garis
        %   tersimpan -> loadAllFrames -> spacing (tersimpan/nodeSpacing/10) ->
        %   step1Collect.collectAlongLine(velocity_magnitude) -> saveRecords
        %   (se-folder, MENIMPA). Dipakai akuisisi batch Step 1. Error bila garis
        %   PSG belum ada. Mengembalikan jumlah titik tersimpan.
            L = pivcore.io.step1Session.loadLine(dataFile);
            if isempty(L)
                error('pivcore:step1Session:noLine', 'Garis PSG belum ada');
            end
            data = pivcore.io.step1Session.loadAllFrames(dataFile);
            sp = pivcore.io.step1Session.savedSpacing(dataFile);
            if ~isfinite(sp) || sp <= 0
                dd = pivcore.data.nodeSpacing(data);
                if isfinite(dd) && dd > 0, sp = round(dd); else, sp = 10; end
            end
            recs = pivcore.pot.step1Collect.collectAlongLine( ...
                data, L.p1, L.p2, sp, 'velocity_magnitude');
            line = struct('p1', L.p1, 'p2', L.p2, 'orient', struct());
            pivcore.io.step1Session.saveRecords(dataFile, recs, line);
            n = numel(recs);
        end

    end


    methods (Static, Access = private)

        function ap = readSession(dataFile)
        %READSESSION  Muat var autopotSession dari <base>_autopot.mat ([] bila
        %   tak ada / korup). Dipakai semua operasi read-modify-write.
            ap = [];
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f) || ~isfile(f), return; end
            try
                Sin = load(f, 'autopotSession');
                if isfield(Sin, 'autopotSession'), ap = Sin.autopotSession; end
            catch
                ap = [];
            end
        end


        function ap = ensureSession(ap, dataFile)
        %ENSURESESSION  Pastikan struct sesi minimal lengkap untuk ditulis.
        %   Bila belum ada, buat struct self-describing minimal (tanpa citra
        %   shear/velocity -> Step-1 tak butuh AutoPOT penuh).
            if isempty(ap) || ~isstruct(ap)
                ap = struct();
                ap.formatName    = 'PIVTerry AutoPOT Session';
                ap.formatVersion = 1;
                [~, b, e] = fileparts(dataFile);
                ap.mainDataFile  = [b e];
            end
            if ~isfield(ap,'step1') || ~isstruct(ap.step1)
                ap.step1 = struct();
            end
        end


        function o = normOrient(o)
        %NORMORIENT  Lengkapi flag orientasi (default no-flip/no-rotate).
            if ~isstruct(o), o = struct(); end
            if ~isfield(o,'flipV')  || ~isscalar(o.flipV),  o.flipV  = false; end
            if ~isfield(o,'flipH')  || ~isscalar(o.flipH),  o.flipH  = false; end
            if ~isfield(o,'rotIdx') || ~isscalar(o.rotIdx), o.rotIdx = 1; end
        end


        function S = trimToFrame1(S)
        %TRIMTOFRAME1  Pangkas semua cell-array per-bingkai di S ke elemen {1}
        %   (background images juga). Field non-cell dibiarkan apa adanya.
            fn = fieldnames(S);
            for k = 1:numel(fn)
                v = S.(fn{k});
                if iscell(v) && numel(v) >= 1
                    S.(fn{k}) = v(1);
                end
            end
            % Format bg terkompresi (jpeg_dedup_v1): pangkas index ke 1 elemen
            % agar buildDataset hanya men-decode satu bingkai.
            if isfield(S,'bg_images_index') && ~isempty(S.bg_images_index)
                idx = S.bg_images_index;
                S.bg_images_index = idx(1);
            end
        end

    end
end


% =====================================================================
% Helper lokal
% =====================================================================
function v = i_getf(S, name, default)
    if isstruct(S) && isfield(S, name), v = S.(name); else, v = default; end
end

function L = i_lineFrom(ln)
%I_LINEFROM  Validasi struct garis {p1,p2} -> struct L lengkap, atau [] bila
%   tak valid (p1/p2 bukan 2 elemen finite). Dipakai loadLine + fallback.
    L = [];
    if isempty(ln) || ~isstruct(ln), return; end
    if ~isfield(ln,'p1') || ~isfield(ln,'p2'), return; end
    p1 = ln.p1; p2 = ln.p2;
    if numel(p1) ~= 2 || numel(p2) ~= 2, return; end
    if any(~isfinite(p1)) || any(~isfinite(p2)), return; end
    edited = true;   % berkas lama / fallback dianggap sudah ditetapkan
    if isfield(ln,'edited') && isscalar(ln.edited), edited = logical(ln.edited); end
    L = struct('p1', p1(:).', 'p2', p2(:).', 'edited', edited, ...
        'orient', pivcore.io.step1Session.normOrient(i_getf(ln,'orient',struct())));
end
