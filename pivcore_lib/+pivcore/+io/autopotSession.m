classdef autopotSession
%AUTOPOTSESSION  Serialisasi progres kerja AutoPOT ke berkas .mat.
%
%   Berbeda dengan potSession (progres sampling titik POT) dan psgSession
%   (ekspor citra PSG mentah), modul ini menyimpan SELURUH KONTEKS KERJA
%   AutoPOT agar dapat dilanjutkan di sesi berikutnya tanpa mengulang:
%
%   KONFIGURASI / LOKASI
%     - lineSnap        : garis PSG saat shear dihitung (p1,p2,lineLen,nSamples)
%     - faults          : SEMUA garis sesar (polyline frame x pos px)
%     - roi / roiOn     : poligon ROI pembatas deteksi
%     - cleanLine       : garis pembersih (batas dinding)
%     - probes          : titik sampling POT (origin citra + frame + pos px
%                         + label + warna + sumber), agar bisa dipulihkan
%     - parameter deteksi & offset (algo, smooth, thr, band, N, sisi, dst.)
%
%   DATA CITRA (hasil analisis)
%     - shear.image     : citra shear_rate_magnitude (nSamples x nFrames)
%     - velocity.image  : citra velocity/displacement magnitude (di-sampling
%                         ulang sepanjang lineSnap saat menyimpan)
%
%   Format self-describing (boleh diparse skrip eksternal):
%       S = load('namafile.mat');  S.autopotSession  % struct utama
%
%   API:
%     pivcore.io.autopotSession.saveDialog(fig)
%     pivcore.io.autopotSession.loadDialog(fig)
%     pivcore.io.autopotSession.saveToFile(fig, fname)
%     pivcore.io.autopotSession.loadFromFile(fig, fname)
%     S = pivcore.io.autopotSession.toStruct(h)
%     h = pivcore.io.autopotSession.fromStruct(h, S)   % state saja (tanpa probe)

    methods (Static)

        % ================================================================
        function S = toStruct(h)
        %TOSTRUCT  Bangun struct sesi AutoPOT (config + 2 citra).
            ap = h.state.autopot;
            if ~ap.computed || isempty(ap.shearM)
                error('pivcore:autopotSession:notComputed', ...
                    'Belum ada citra shear AutoPOT. Tekan "Hitung shear PSG" dulu.');
            end
            [nS, nF] = size(ap.shearM);

            % --- Citra velocity/displacement magnitude sepanjang lineSnap ---
            %   CORE (pivcore): citra ini artefak AutoPOT-old yang dulu
            %   di-sampling ulang via GUI (tabPSG). Core TIDAK bergantung pada
            %   GUI: pakai citra yang sudah dihitung host bila tersedia
            %   (ap.velM / ap.velocityM, ukuran nS x nF), selain itu isi NaN.
            %   Field S.velocity tetap ada agar format .mat konsisten & dapat
            %   diparse skrip eksternal. GUI host yang butuh citra ini wajib
            %   menaruhnya di state.autopot.velM sebelum menyimpan.
            Vmag = nan(nS, nF);
            if isfield(ap,'velM') && isequal(size(ap.velM),[nS nF])
                Vmag = ap.velM;
            elseif isfield(ap,'velocityM') && isequal(size(ap.velocityM),[nS nF])
                Vmag = ap.velocityM;
            end

            % --- Detail probe (agar bisa dipulihkan sebagai variabel POT) ---
            %   fromF/toF (rentang bingkai kurva POT) IKUT disimpan agar
            %   progres edit awal/akhir kurva tidak hilang saat dimuat ulang.
            probes = struct('slot',{},'label',{},'color',{},'origin',{}, ...
                            'srcName',{},'frameDisp',{},'posPx',{}, ...
                            'fromF',{},'toF',{});
            pot = h.state.pot;
            for i = 1:numel(ap.probeVars)
                slot = ap.probeVars(i);
                if slot < 1 || slot > numel(pot.vars), continue; end
                v = pot.vars(slot);
                probes(end+1) = struct( ...
                    'slot',slot, 'label',v.label, 'color',v.color, ...
                    'origin',v.origin, 'srcName',v.srcName, ...
                    'frameDisp',ap.probeFrame(i), 'posPx',ap.probePos(i), ...
                    'fromF',v.fromF, 'toF',v.toF); %#ok<AGROW>
            end

            S = struct();
            S.formatName    = 'PIVTerry AutoPOT Session';
            S.formatVersion = 1;
            S.savedAt       = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<DATST,TNOW1>
            S.matFile       = '';
            if isfield(h,'matFile') && ischar(h.matFile), S.matFile = h.matFile; end
            % Nama BERKAS DATA UTAMA (basename saja). Data utama & berkas
            % progres SELALU berada di folder yang sama, sehingga saat
            % "Muat progres" data utama dapat ditemukan & dimuat ulang dari
            % folder berkas progres lalu progres diterapkan di atasnya.
            S.mainDataFile  = '';
            if isfield(h,'matFile') && ischar(h.matFile) && ~isempty(h.matFile)
                [~, b, e] = fileparts(h.matFile);
                S.mainDataFile = [b e];
            end
            S.nFramesAtSave = h.data.nFrames;
            S.nSamples      = nS;

            % --- Konfigurasi / lokasi ---
            S.lineSnap     = ap.lineSnap;
            S.faults       = ap.faults;
            S.activeFault  = ap.activeFault;
            S.maxFaults    = ap.maxFaults;
            S.roiOn        = ap.roiOn;
            S.roi          = ap.roi;
            S.cleanOn      = ap.cleanOn;
            S.cleanLine    = ap.cleanLine;
            S.climLo       = ap.climLo;
            S.climHi       = ap.climHi;
            S.detectAlgo   = ap.detectAlgo;
            S.localContrast= ap.localContrast;
            S.smoothFrame  = ap.smoothFrame;
            S.detectThr    = ap.detectThr;
            S.detectBand   = ap.detectBand;
            S.offsetN      = ap.offsetN;
            S.side         = ap.side;
            S.genSpacing   = ap.genSpacing;
            S.showOffset   = ap.showOffset;
            S.probes       = probes;

            % --- Data citra (hasil analisis) ---
            [sLo, sHi] = i_dataRange(ap.shearM);
            [vLo, vHi] = i_dataRange(Vmag);
            S.shear = struct('name','shear_rate_magnitude', 'image',ap.shearM, ...
                'dataMin',sLo, 'dataMax',sHi, 'clim',[ap.climLo ap.climHi]);
            S.velocity = struct('name','velocity_magnitude', 'image',Vmag, ...
                'dataMin',vLo, 'dataMax',vHi);

            % --- Info eksperimen (seluruh setelan tab Strain) ---
            %   init pos, max/end pos, n of files, dll. ikut tersimpan agar
            %   sesi POT-PSG menyimpan konteks eksperimen secara lengkap.
            S.strain = i_grabStrain(h);

            % --- POT-EXP: titik pengamatan (Start/Nuc/FSR/END), delta antar
            %     titik, dan integral antar kurva. Disertakan agar progres
            %     eksplorasi tersimpan SEAMLESS di berkas _autopot yang sama. ---
            S.potexp = i_grabPotExp(h);

            % --- POT-PSG3: tabel sesar (kurva terbaik per sesar). Salinan
            %     PENUH deret-waktu tiap kurva terpilih -> mandiri dari probe
            %     POT, tersimpan SEAMLESS di berkas _autopot yang sama. ---
            S.potpsg3 = i_grabPotPsg3(h);

            % --- POT-PSG4: tabel titik/sesar (1 baris = 1 titik) dgn marker
            %     Start/NUC/FSR/End. Salinan PENUH deret-waktu tiap titik. ---
            S.potpsg4 = i_grabPotPsg4(h);

            % --- Auto POT (baru): data mentah POT-PSG (PSG velocity + PSG shear
            %     mentah/nSamples x nFrames), kurva indenter (envelope atas
            %     gabungan), dan band kesimpulan POT-PSG5. Disertakan agar 4 data
            %     dasar analisis bidang sesar tersimpan SEAMLESS. ---
            S.potpsgRaw       = i_grabPotPsgRaw(h);
            S.indenterMagnitude = i_grabIndenter(h);
            S.potpsg5Bands    = i_grabPotPsg5Bands(h);
        end


        % ================================================================
        function h = fromStruct(h, S)
        %FROMSTRUCT  Terapkan KONFIGURASI + citra ke h.state.autopot.
        %   Tidak memulihkan probe (perlu fig -> dilakukan di loadFromFile).
            ap = h.state.autopot;

            ap.shearM   = S.shear.image;
            ap.computed = true;
            ap.lineSnap = i_getf(S, 'lineSnap', ap.lineSnap);
            ap.faults   = i_normFaults(i_getf(S, 'faults', ap.faults));
            ap.activeFault = i_getf(S, 'activeFault', 1);
            ap.maxFaults   = i_getf(S, 'maxFaults', 3);
            ap.roiOn       = logical(i_getf(S, 'roiOn', false));
            ap.roi         = i_normRoi(i_getf(S, 'roi', struct('frames',[],'pos',[])));
            ap.cleanOn     = logical(i_getf(S, 'cleanOn', false));
            ap.cleanLine   = i_getf(S, 'cleanLine', struct('p1',[NaN NaN],'p2',[NaN NaN]));
            ap.climLo      = i_getf(S, 'climLo', NaN);
            ap.climHi      = i_getf(S, 'climHi', NaN);
            ap.detectAlgo  = i_getf(S, 'detectAlgo', 'ridge');
            ap.localContrast = logical(i_getf(S, 'localContrast', true));
            ap.smoothFrame = i_getf(S, 'smoothFrame', 7);
            ap.detectThr   = i_getf(S, 'detectThr', 0.3);
            ap.detectBand  = i_getf(S, 'detectBand', []);
            ap.offsetN     = i_getf(S, 'offsetN', 50);
            ap.side        = i_getf(S, 'side', -1);
            ap.genSpacing  = i_getf(S, 'genSpacing', 25);
            ap.showOffset  = logical(i_getf(S, 'showOffset', true));
            ap.dragging    = []; ap.dragKind = '';
            ap.activeFault = max(1, min(ap.activeFault, max(1,numel(ap.faults))));

            h.state.autopot = ap;

            % Garis PSG mengikuti snapshot (agar tampilan & koordinat konsisten).
            if all(isfinite([ap.lineSnap.p1 ap.lineSnap.p2]))
                h.state.psg.line.p1 = ap.lineSnap.p1;
                h.state.psg.line.p2 = ap.lineSnap.p2;
            end
            if isfinite(ap.lineSnap.nSamples) && ap.lineSnap.nSamples >= 2
                h.state.psg.nSamples = ap.lineSnap.nSamples;
            end
        end


        % ================================================================
        function saveToFile(fig, fname)
            h = guidata(fig);
            autopotSession = pivcore.io.autopotSession.toStruct(h); %#ok<NASGU>
            save(fname, 'autopotSession', '-v7');
        end


        function loadFromFile(fig, fname)
        %LOADFROMFILE  Muat progres. Berkas progres MENYIMPAN nama berkas
        %   data utama; data utama & berkas progres SELALU di folder yang
        %   sama. Jika data utama yang sedang terbuka BUKAN milik sesi ini,
        %   data utama dimuat ULANG (segar) lebih dulu lalu progres
        %   diterapkan di atasnya -> "lanjutkan progres sebelumnya". Memuat
        %   data utama secara langsung (PIVTerry / "Reset ... berikutnya")
        %   tetap memberi setelan segar tanpa progres.
            Sin = load(fname);
            if ~isfield(Sin, 'autopotSession')
                error('pivcore:autopotSession:badFile', ...
                    'Berkas bukan sesi AutoPOT (variabel autopotSession tidak ada).');
            end
            S = Sin.autopotSession;
            if ~isfield(S,'formatName') || ~strcmp(S.formatName,'PIVTerry AutoPOT Session')
                warning('pivcore:autopotSession:format', ...
                    'formatName tidak dikenali; mencoba memuat apa adanya.');
            end

            % --- Tentukan berkas data utama milik sesi (folder yang sama) ---
            sessionDir = fileparts(fname);
            mainName = '';
            if isfield(S,'mainDataFile') && ischar(S.mainDataFile)
                mainName = S.mainDataFile;
            end
            if isempty(mainName) && isfield(S,'matFile') && ischar(S.matFile) ...
                    && ~isempty(S.matFile)
                [~, b, e] = fileparts(S.matFile);
                mainName = [b e];
            end
            mainPath = '';
            if ~isempty(mainName)
                cand = fullfile(sessionDir, mainName);
                if isfile(cand), mainPath = cand; end
            end

            % --- Perlu memuat ulang data utama? (sesi milik dataset lain) ---
            h = guidata(fig);
            curMain = '';
            if isfield(h,'matFile') && ischar(h.matFile), curMain = h.matFile; end
            % CORE (pivcore): core TIDAK membuka jendela data utama baru
            %   (itu tugas GUI host). Progres selalu diterapkan ke `fig` saat
            %   ini; host sebaiknya membuka berkas data utama yang cocok lebih
            %   dulu. Kita hanya memperingatkan bila datanya tampak beda/hilang.
            if ~isempty(mainPath) && ~i_sameFile(curMain, mainPath)
                warning('pivcore:autopotSession:mainDiffer', ...
                    ['Sesi ini milik data utama "%s" (beda dgn yang terbuka). ', ...
                     'Progres tetap diterapkan ke figure saat ini.'], mainPath);
            elseif isempty(mainPath)
                warning('pivcore:autopotSession:mainMissing', ...
                    ['Berkas data utama (%s) tidak ditemukan di folder sesi; ', ...
                     'progres diterapkan ke data yang sedang terbuka.'], mainName);
            end

            % Terapkan progres (state) ke figure saat ini.
            pivcore.io.autopotSession.applySession(fig, S);
        end


        % ================================================================
        function applySession(fig, S)
        %APPLYSESSION  (CORE) Terapkan struct sesi S ke STATE figure fig:
        %   konfigurasi + citra shear (+velocity bila ada) + tabel POT-EXP/
        %   POT-PSG3/POT-PSG4 + setelan Strain. Hanya menulis guidata(state);
        %   TIDAK membangun ulang kontrol GUI, probe POT, popup sesar, atau
        %   redraw -- itu TANGGUNG JAWAB GUI HOST. Pola pakai: panggil
        %   applySession lalu refresh kontrol & gambar sendiri.
        %   (Lihat core/README.md - "load via core -> refresh UI sendiri".)
        %
        %   PRASYARAT: fig sudah punya state.autopot ber-skema LENGKAP
        %   (lineSnap/faults/roi/cleanLine/detect*/...). Lihat fromStruct;
        %   GUI host menyemai skema itu saat inisialisasi.
        %
        %   CATATAN: S.probes (variabel POT gaya AutoPOT-old) sengaja TIDAK
        %   dipulihkan di core; bila GUI host memerlukannya, bangun sendiri
        %   dari S.probes setelah memanggil applySession.

            % 1) Konfigurasi + citra -> state.autopot / state.psg.
            h = guidata(fig);
            h = pivcore.io.autopotSession.fromStruct(h, S);
            guidata(fig, h);

            % 2) Setelan tab Strain (info eksperimen) bila ada.
            if isfield(S,'strain'), i_applyStrain(fig, S.strain); end

            % 3) Tabel POT-EXP / POT-PSG3 / POT-PSG4 (state saja; tiap record
            %    mandiri membawa salinan deret-waktunya).
            if isfield(S,'potexp'),  pivcore.io.autopotSession.applyPotExp(fig,  S.potexp);  end
            if isfield(S,'potpsg3'), pivcore.io.autopotSession.applyPotPsg3(fig, S.potpsg3); end
            if isfield(S,'potpsg4'), pivcore.io.autopotSession.applyPotPsg4(fig, S.potpsg4); end
        end


        % ================================================================
        function syncUI(fig)
        %SYNCUI  Dorong nilai state.autopot ke kontrol UI tab AutoPOT.
            h = guidata(fig); c = h.ctl.autopot; ap = h.state.autopot;
            i_set(c,'edClimMin', i_autoStr(ap.climLo));
            i_set(c,'edClimMax', i_autoStr(ap.climHi));
            i_setpop(c,'popMethod', strcmpi(ap.detectAlgo,'peak')+1);   % ridge=1 peak=2
            i_setval(c,'chkLocal', double(logical(ap.localContrast)));
            i_set(c,'edSmooth', num2str(ap.smoothFrame));
            i_set(c,'edThr',    num2str(ap.detectThr,'%g'));
            i_set(c,'edMaxF',   num2str(ap.maxFaults));
            if isempty(ap.detectBand)
                i_set(c,'edBandLo','auto'); i_set(c,'edBandHi','auto');
            else
                i_set(c,'edBandLo', i_autoStr(ap.detectBand(1)));
                i_set(c,'edBandHi', i_autoStr(ap.detectBand(end)));
            end
            i_setval(c,'chkRoi',   double(logical(ap.roiOn)));
            i_setval(c,'chkClean', double(logical(ap.cleanOn)));
            i_set(c,'edN', num2str(ap.offsetN,'%g'));
            i_setpop(c,'popSide', (ap.side>0)+1);                       % -1->1 +1->2
            i_setval(c,'chkOffLine', double(logical(ap.showOffset)));
            i_set(c,'edSpacing', num2str(ap.genSpacing));
            % CORE: info garis & kontrol khusus tab AutoPOT-old di-refresh
            %   oleh GUI host (bila ada). syncUI hanya mendorong nilai ke
            %   kontrol generik yang dijaga ishghandle.
        end


        % ================================================================
        function saveDialog(fig)
            h = guidata(fig);
            if ~isfield(h,'state') || ~isfield(h.state,'autopot') ...
                    || ~h.state.autopot.computed || isempty(h.state.autopot.shearM)
                warndlg(['Belum ada citra shear AutoPOT. Aktifkan AutoPOT lalu ' ...
                         '"Hitung shear PSG" sebelum menyimpan progres.'],'Simpan AutoPOT');
                return;
            end
            % Default ke FOLDER data utama (sesi & data utama satu folder).
            defaultName = 'autopot_session.mat';
            if isfield(h,'matFile') && ischar(h.matFile) && ~isempty(h.matFile)
                [d, base] = fileparts(h.matFile);
                nm = sprintf('%s_autopot.mat', base);
                if ~isempty(d) && isfolder(d)
                    defaultName = fullfile(d, nm);
                else
                    defaultName = nm;
                end
            end
            [fn, fp] = uiputfile({'*.mat','PIVTerry AutoPOT Session (*.mat)'}, ...
                'Simpan progres AutoPOT', defaultName);
            if isequal(fn, 0), return; end
            outFile = fullfile(fp, fn);
            try
                pivcore.io.autopotSession.saveToFile(fig, outFile);
            catch ME
                errordlg(sprintf('Gagal menyimpan sesi AutoPOT: %s', ME.message), 'Simpan AutoPOT');
                return;
            end
            % CORE: laporan status sukses diserahkan ke GUI host.
        end


        function loadDialog(fig)
            % Mulai dialog di FOLDER data utama (sesi & data utama satu folder).
            h = guidata(fig);
            startDir = pwd;
            if isfield(h,'matFile') && ischar(h.matFile) && ~isempty(h.matFile)
                d = fileparts(h.matFile);
                if ~isempty(d) && isfolder(d), startDir = d; end
            end
            [fn, fp] = uigetfile({'*.mat','PIVTerry AutoPOT Session (*.mat)'}, ...
                'Muat progres AutoPOT', [startDir filesep]);
            if isequal(fn, 0), return; end
            inFile = fullfile(fp, fn);
            try
                pivcore.io.autopotSession.loadFromFile(fig, inFile);
            catch ME
                errordlg(sprintf('Gagal memuat sesi AutoPOT: %s', ME.message), 'Muat AutoPOT');
            end
        end


        % ================================================================
        function applyPotExp(fig, P)
        %APPLYPOTEXP  Terapkan struct POT-EXP (titik pengamatan + integral)
        %   ke h.state.pot.exp, disesuaikan dengan jumlah kurva terkini.
            if ~isstruct(P), return; end
            h = guidata(fig);
            nV = h.state.pot.nVars;
            exp = pivcore.pot.potexpModel.ensure(struct(), nV);
            % Pulihkan titik per kurva (kolom xy 4x2).
            if isfield(P,'points') && isstruct(P.points)
                m = min(numel(P.points), numel(exp.points));
                for k = 1:m
                    xy = [];
                    if isfield(P.points(k),'xy'), xy = P.points(k).xy; end
                    if isnumeric(xy) && ~isempty(xy)
                        fixed = nan(4,2);
                        r = min(size(xy,1),4); c = min(size(xy,2),2);
                        fixed(1:r,1:c) = xy(1:r,1:c);
                        exp.points(k).xy = fixed;
                    end
                end
            end
            if isfield(P,'integral') && isnumeric(P.integral)
                iv = nan(1, nV);
                m = min(numel(P.integral), nV);
                if m > 0, iv(1:m) = P.integral(1:m); end
                exp.integral = iv;
            end
            h.state.pot.exp = exp;
            guidata(fig, h);
            % CORE: refresh marker/plot POT-EXP diserahkan ke GUI host.
        end


        % ================================================================
        function applyPotPsg3(fig, P)
        %APPLYPOTPSG3  Terapkan struct POT-PSG3 (tabel sesar = kurva terbaik
        %   per sesar) ke h.state.pot.psg3. Record mandiri dari probe POT
        %   (menyimpan salinan deret-waktu), jadi cukup disalin apa adanya.
            h = guidata(fig);
            M = pivcore.pot.potpsg3Model.ensure(struct());
            if isstruct(P) && isfield(P,'records') && isstruct(P.records)
                recs = pivcore.pot.potpsg3Model.emptyRecordArray();
                src = P.records;
                for k = 1:numel(src)
                    rec = pivcore.pot.potpsg3Model.recordFromVar(struct(), '', '');
                    fn = fieldnames(rec);
                    for i = 1:numel(fn)
                        if isfield(src(k), fn{i}), rec.(fn{i}) = src(k).(fn{i}); end
                    end
                    rec = pivcore.pot.potpsg3Model.normalizeRecord(rec);
                    if isempty(recs), recs = orderfields(rec); ...
                    else, recs(end+1) = orderfields(rec, recs(1)); end %#ok<AGROW>
                end
                M.records = recs;
                M = pivcore.pot.potpsg3Model.renumber(M);
                M.activeRow = min(1, numel(M.records));
                if numel(M.records) >= 1, M.activeRow = 1; end
            end
            h.state.pot.psg3 = M;
            guidata(fig, h);
            % CORE: refresh tabel POT-PSG3 diserahkan ke GUI host.
        end


        % ================================================================
        function applyPotPsg4(fig, P)
        %APPLYPOTPSG4  Terapkan struct POT-PSG4 (tabel titik/sesar) ke
        %   h.state.pot.psg4. Tiap record mandiri (salinan deret-waktu).
            h = guidata(fig);
            M = pivcore.pot.potpsg4Model.ensure(struct());
            if isstruct(P) && isfield(P,'records') && isstruct(P.records)
                recs = pivcore.pot.potpsg4Model.emptyRecordArray();
                src = P.records;
                for k = 1:numel(src)
                    rec = pivcore.pot.potpsg4Model.recordFromVar(struct(), 1);
                    fn = fieldnames(rec);
                    for i = 1:numel(fn)
                        if isfield(src(k), fn{i}), rec.(fn{i}) = src(k).(fn{i}); end
                    end
                    rec = pivcore.pot.potpsg4Model.normalizeRecord(rec);
                    if isempty(recs), recs = orderfields(rec); ...
                    else, recs(end+1) = orderfields(rec, recs(1)); end %#ok<AGROW>
                end
                M.records = recs;
                M = pivcore.pot.potpsg4Model.applyFaultColors(M);
                if numel(M.records) >= 1, M.activeRow = 1; end
            end
            if isstruct(P) && isfield(P,'cutOn') && isscalar(P.cutOn)
                M.cutOn = logical(P.cutOn);
            end
            h.state.pot.psg4 = M;
            guidata(fig, h);
            % CORE: refresh tabel POT-PSG4 diserahkan ke GUI host.
        end


        % ================================================================
        function fname = seamlessFile(h)
        %SEAMLESSFILE  Tentukan path berkas progres <data>_autopot.mat di
        %   folder data utama (konvensi nama konsisten). '' bila tak bisa.
            fname = '';
            if ~isfield(h,'matFile') || ~ischar(h.matFile) || isempty(h.matFile)
                return;
            end
            [d, base] = fileparts(h.matFile);
            nm = sprintf('%s_autopot.mat', base);
            if ~isempty(d) && isfolder(d)
                fname = fullfile(d, nm);
            else
                fname = nm;
            end
        end


        function saveSeamless(fig)
        %SAVESEAMLESS  Simpan progres ke <data>_autopot.mat TANPA dialog
        %   (auto dari nama data utama). Fallback ke saveDialog bila nama
        %   tak dapat ditentukan. Berbagi format dengan saveDialog.
            h = guidata(fig);
            if ~isfield(h,'state') || ~isfield(h.state,'autopot') ...
                    || ~h.state.autopot.computed || isempty(h.state.autopot.shearM)
                warndlg(['Belum ada citra shear AutoPOT. Aktifkan AutoPOT lalu ' ...
                         '"Hitung shear PSG" sebelum menyimpan progres.'], ...
                         'Simpan progres');
                return;
            end
            outFile = pivcore.io.autopotSession.seamlessFile(h);
            if isempty(outFile)
                pivcore.io.autopotSession.saveDialog(fig); return;
            end
            try
                pivcore.io.autopotSession.saveToFile(fig, outFile);
            catch ME
                errordlg(sprintf('Gagal menyimpan progres: %s', ME.message), ...
                    'Simpan progres');
                return;
            end
            % CORE: laporan status sukses diserahkan ke GUI host.
        end


        function ok = autoSave(fig)
        %AUTOSAVE  Simpan progres SENYAP ke <data>_autopot.mat (tanpa dialog &
        %   tanpa kotak peringatan). Mengembalikan true bila berhasil. Dipakai
        %   untuk auto-save POT-PSG3 setelah perubahan. Tidak menyimpan bila
        %   shear belum dihitung atau nama berkas tak diketahui.
            ok = false;
            h = guidata(fig);
            if ~isfield(h,'state') || ~isfield(h.state,'autopot') ...
                    || ~h.state.autopot.computed || isempty(h.state.autopot.shearM)
                return;
            end
            outFile = pivcore.io.autopotSession.seamlessFile(h);
            if isempty(outFile), return; end
            try
                pivcore.io.autopotSession.saveToFile(fig, outFile);
                ok = true;
            catch
                ok = false;
            end
        end


        function fname = backupFile(h)
        %BACKUPFILE  Path cadangan berikutnya yang BELUM ada:
        %   <base>_autopot_1.mat, _2, ... di folder data utama. '' bila nama
        %   tak dapat ditentukan. Tidak pernah menimpa berkas yang ada.
            fname = '';
            if ~isfield(h,'matFile') || ~ischar(h.matFile) || isempty(h.matFile)
                return;
            end
            [d, base] = fileparts(h.matFile);
            if isempty(d) || ~isfolder(d), d = pwd; end
            k = 1;
            while true
                cand = fullfile(d, sprintf('%s_autopot_%d.mat', base, k));
                if ~isfile(cand), fname = cand; return; end
                k = k + 1;
                if k > 100000, return; end   % pengaman
            end
        end


        function saveBackup(fig)
        %SAVEBACKUP  Tulis SNAPSHOT state saat ini ke berkas cadangan bernomor
        %   <base>_autopot_#.mat (tak menimpa _autopot utama maupun cadangan
        %   lama). Berguna untuk menyimpan titik-titik aman berurutan.
            h = guidata(fig);
            if ~isfield(h,'state') || ~isfield(h.state,'autopot') ...
                    || ~h.state.autopot.computed || isempty(h.state.autopot.shearM)
                warndlg(['No AutoPOT shear image yet. Enable AutoPOT and ', ...
                         '"Compute shear" before making a backup.'], 'Backup');
                return;
            end
            outFile = pivcore.io.autopotSession.backupFile(h);
            if isempty(outFile)
                pivcore.io.autopotSession.saveDialog(fig); return;
            end
            try
                pivcore.io.autopotSession.saveToFile(fig, outFile);
            catch ME
                errordlg(sprintf('Failed to write backup: %s', ME.message), 'Backup');
                return;
            end
            % CORE: laporan status sukses diserahkan ke GUI host.
        end


        function loadSeamless(fig)
        %LOADSEAMLESS  Muat <data>_autopot.mat dari folder data utama TANPA
        %   dialog. Fallback ke loadDialog bila berkas tak ditemukan.
            h = guidata(fig);
            inFile = pivcore.io.autopotSession.seamlessFile(h);
            if isempty(inFile) || ~isfile(inFile)
                if ~isempty(inFile)
                    warndlg(sprintf(['Berkas progres "%s" belum ada di folder ', ...
                        'data. Pilih berkas secara manual.'], inFile), 'Muat progres');
                end
                pivcore.io.autopotSession.loadDialog(fig); return;
            end
            try
                pivcore.io.autopotSession.loadFromFile(fig, inFile);
            catch ME
                errordlg(sprintf('Gagal memuat progres: %s', ME.message), 'Muat progres');
            end
        end

    end
end


% =====================================================================
% Helpers
% =====================================================================

function v = i_getf(S, name, default)
    if isstruct(S) && isfield(S, name), v = S.(name); else, v = default; end
end

function tf = i_sameFile(a, b)
%I_SAMEFILE  Apakah dua path menunjuk berkas yang sama (perbandingan
%   absolut; case-insensitive di Windows/macOS).
    if isempty(a) || isempty(b), tf = false; return; end
    ca = i_canonPath(a); cb = i_canonPath(b);
    if ispc || ismac, tf = strcmpi(ca, cb); else, tf = strcmp(ca, cb); end
end

function p = i_canonPath(p)
%I_CANONPATH  Bentuk path absolut yang dinormalisasi (tanpa resolusi
%   symlink; cukup untuk membandingkan berkas data utama vs sesi).
    [d, n, e] = fileparts(p);
    if isempty(d), d = pwd; end
    isAbs = ~isempty(d) && (d(1) == '/' || (ispc && numel(d) >= 2 && d(2) == ':'));
    if ~isAbs, d = fullfile(pwd, d); end
    p = fullfile(d, [n e]);
end

function F = i_normFaults(F)
    if ~isstruct(F) || ~isfield(F,'frames') || ~isfield(F,'pos')
        F = struct('frames',{},'pos',{}); return;
    end
    % Pastikan vektor baris.
    for j = 1:numel(F)
        F(j).frames = F(j).frames(:).';
        F(j).pos    = F(j).pos(:).';
    end
end

function R = i_normRoi(R)
    if ~isstruct(R) || ~isfield(R,'frames') || ~isfield(R,'pos')
        R = struct('frames',[],'pos',[]); return;
    end
    R.frames = R.frames(:).';
    R.pos    = R.pos(:).';
end

function s = i_autoStr(v)
    if ~isfinite(v), s = 'auto'; else, s = num2str(v,'%.4g'); end
end

function i_set(c, fld, str)
    if isfield(c, fld) && ishghandle(c.(fld)), set(c.(fld),'String',str); end
end
function i_setval(c, fld, val)
    if isfield(c, fld) && ishghandle(c.(fld)), set(c.(fld),'Value',val); end
end
function i_setpop(c, fld, idx)
    if isfield(c, fld) && ishghandle(c.(fld))
        n = numel(get(c.(fld),'String')); set(c.(fld),'Value', max(1,min(idx,n)));
    end
end

function [lo, hi] = i_dataRange(M)
    v = M(isfinite(M));
    if isempty(v), lo = 0; hi = 1;
    else
        lo = min(v(:)); hi = max(v(:));
        if lo == hi, hi = lo + eps(lo) + 1e-12; end
    end
end


% --- Setelan tab Strain (info eksperimen) -----------------------------
function St = i_grabStrain(h)
%I_GRABSTRAIN  Ambil seluruh setelan tab Strain ke struct (string apa adanya).
    St = struct();
    St.on       = i_hval(h,'chkStrainOn');
    St.auto     = i_hval(h,'chkStrainAuto');
    St.min      = i_hstr(h,'edStrainMin');      % nilai minimum
    St.max      = i_hstr(h,'edStrainMax');      % nilai maksimum
    St.cmAwal   = i_hstr(h,'edStrainCmAwal');   % posisi awal / init pos (cm)
    St.cmAkhir  = i_hstr(h,'edStrainCmAkhir');  % posisi akhir / end pos (cm)
    St.cmUjung  = i_hstr(h,'edStrainCmUjung');  % posisi ujung / max pos (cm)
    St.unit     = i_hstr(h,'edStrainUnit');
    St.prefix   = i_hstr(h,'edStrainPrefix');
    St.dec      = i_hstr(h,'edStrainDec');
    St.fontSize = i_hstr(h,'edStrainFontSize');
    St.nFiles   = h.data.nFrames;               % n of files (bingkai)
end

function i_applyStrain(fig, St)
%I_APPLYSTRAIN  Terapkan kembali setelan tab Strain dari struct ke UI.
    if ~isstruct(St), return; end
    h = guidata(fig);
    i_hset(h,'edStrainMin',     i_field(St,'min'));
    i_hset(h,'edStrainMax',     i_field(St,'max'));
    i_hset(h,'edStrainCmAwal',  i_field(St,'cmAwal'));
    i_hset(h,'edStrainCmAkhir', i_field(St,'cmAkhir'));
    i_hset(h,'edStrainCmUjung', i_field(St,'cmUjung'));
    i_hset(h,'edStrainUnit',    i_field(St,'unit'));
    i_hset(h,'edStrainPrefix',  i_field(St,'prefix'));
    i_hset(h,'edStrainDec',     i_field(St,'dec'));
    i_hset(h,'edStrainFontSize',i_field(St,'fontSize'));
    if isfield(St,'on') && isfield(h,'chkStrainOn') && ishghandle(h.chkStrainOn)
        set(h.chkStrainOn,'Value', double(logical(St.on)));
    end
    if isfield(St,'auto') && isfield(h,'chkStrainAuto') && ishghandle(h.chkStrainAuto)
        set(h.chkStrainAuto,'Value', double(logical(St.auto)));
    end
    % CORE: sinkronisasi visibilitas mode auto/manual + recompute strain
    %   max auto adalah tanggung jawab GUI host (tab Strain), bukan core.
end

function v = i_hval(h, f)
    if isfield(h,f) && ishghandle(h.(f)), v = get(h.(f),'Value'); else, v = []; end
end
function s = i_hstr(h, f)
    if isfield(h,f) && ishghandle(h.(f)), s = get(h.(f),'String'); else, s = ''; end
end
function i_hset(h, f, s)
    if ~isempty(s) && isfield(h,f) && ishghandle(h.(f)), set(h.(f),'String',s); end
end
function v = i_field(S, f)
    if isstruct(S) && isfield(S,f), v = S.(f); else, v = ''; end
end


% --- POT-EXP (titik pengamatan + delta + integral) --------------------
function P = i_grabPotExp(h)
%I_GRABPOTEXP  Ambil state POT-EXP ke struct yang dapat diserialisasi.
%   Menyertakan delta antar SEMUA titik (dihitung, hanya disimpan).
    P = struct('points', struct('xy',{}), 'integral', [], 'deltas', struct('dX',{},'dY',{},'grad',{}));
    if ~isfield(h,'state') || ~isfield(h.state,'pot'), return; end
    pot = h.state.pot;
    nV = pot.nVars;
    exp = pivcore.pot.potexpModel.ensure( ...
        i_field2(pot,'exp',struct()), nV);
    for k = 1:numel(exp.points)
        P.points(k).xy = exp.points(k).xy; %#ok<AGROW>
    end
    P.integral = exp.integral;
    % Delta antar titik (Start->Nuc->FSR->END) per kurva: disimpan saja.
    P.deltas = pivcore.pot.potexpModel.deltas(exp);
end

function v = i_field2(S, f, dflt)
    if isstruct(S) && isfield(S,f), v = S.(f); else, v = dflt; end
end


% --- POT-PSG3 (tabel sesar: kurva terbaik per sesar) ------------------
function P = i_grabPotPsg3(h)
%I_GRABPOTPSG3  Ambil tabel sesar POT-PSG3 ke struct serializable.
    P = struct('records', pivcore.pot.potpsg3Model.emptyRecordArray());
    if ~isfield(h,'state') || ~isfield(h.state,'pot'), return; end
    M = pivcore.pot.potpsg3Model.ensure(i_field2(h.state.pot,'psg3',struct()));
    P.records = M.records;
end


% --- POT-PSG4 (tabel titik/sesar: 1 baris = 1 titik) ------------------
function P = i_grabPotPsg4(h)
%I_GRABPOTPSG4  Ambil tabel titik/sesar POT-PSG4 ke struct serializable.
    P = struct('records', pivcore.pot.potpsg4Model.emptyRecordArray());
    if ~isfield(h,'state') || ~isfield(h.state,'pot'), return; end
    M = pivcore.pot.potpsg4Model.ensure(i_field2(h.state.pot,'psg4',struct()));
    P.records = M.records;
    P.cutOn   = M.cutOn;
end


% --- Auto POT (baru): data mentah POT-PSG, indenter, band kesimpulan ----
function R = i_grabPotPsgRaw(h)
%I_GRABPOTPSGRAW  Data mentah PSG (velocity + shear, nSamples x nFrames)
%   yang dihitung sistem Auto POT baru. Disimpan di h.state.autopot2.raw.
    R = struct('psgVelocity',[],'psgShear',[],'line',struct('p1',[NaN NaN],'p2',[NaN NaN]));
    if ~isfield(h,'state') || ~isfield(h.state,'autopot2'), return; end
    a2 = h.state.autopot2;
    if isfield(a2,'raw') && isstruct(a2.raw)
        if isfield(a2.raw,'psgVelocity'), R.psgVelocity = a2.raw.psgVelocity; end
        if isfield(a2.raw,'psgShear'),    R.psgShear    = a2.raw.psgShear;    end
        if isfield(a2.raw,'line'),        R.line        = a2.raw.line;        end
    end
end

function v = i_grabIndenter(h)
%I_GRABINDENTER  Kurva indenter (envelope atas gabungan, 1 x nFrames).
    v = [];
    if isfield(h,'state') && isfield(h.state,'autopot2') ...
            && isfield(h.state.autopot2,'indenter')
        v = h.state.autopot2.indenter;
    end
end

function B = i_grabPotPsg5Bands(h)
%I_GRABPOTPSG5BANDS  Band kesimpulan POT-PSG5 (POT kesimpulan) bila ada.
    B = [];
    if isfield(h,'state') && isfield(h.state,'potpsg5') ...
            && isfield(h.state.potpsg5,'bands')
        B = h.state.potpsg5.bands;
    end
end
