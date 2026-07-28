classdef grain4Desc
%GRAIN4DESC  Model TABEL DESKRIPSI GRAIN4 — sidecar `<base>_desc.json` di folder
%   yang sama dgn MAT PIV. INI kebenaran milik GRAIN4 (pencatat pengamatan per-
%   frame gaya Excel). MAT PIV biner, `<base>_faults.json` (GRAIN5) &
%   `<base>_potdata.json` (GRAIN4 lama) TIDAK disentuh — GRAIN4 hanya MEMBACA
%   `_faults.json` untuk konteks sesar, lalu menulis tabel DESC di sini.
%
%   KONSEP: user mencatat baris observasi per-frame. Tiap baris = 6 kolom
%   (spec `Tabel DESC V1.xlsx`) + `psgId` internal (scoping garis PSG):
%     psgId   id garis PSG pemilik (sesar terikat ke garis PSG; bisa >1 garis)
%     fNum    nomor sesar tampil (string, mis. 'F1', 'F19_F12'); '' = tanpa F#
%     frame   nomor frame yang diamati (di AX main)
%     poi     titik siklus hidup: Start/NUC-T/NUC-D/FSR-T/FSR-D/MSR/End/</blank>
%     actF    # active fault: jumlah sesar aktif tampil di frame (angka, manual)
%     fTrx    frame AKHIR transisi (baris POI='TRX'; frame=awal) -> fill hijau
%     isOost  1 = in-sequence, 2 = OOST (out-of-sequence thrust)
%     fsrDir  arah pembentukan FSR: 'UP'/'DWN'/'both'/'SIM' (SIM=simultan, pasangan
%             nucPos='ALL')
%     nucPos  posisi nukleasi (hanya POI='NUC-FSR'): 'T'/'M'/'B'/'FT'/'ALL' (Top/Mid/
%             Bottom/Fault-Tip/semua posisi; else ''). Skema lama A/T/B/F-Tip
%             dimigrasi otomatis.
%     desc    deskripsi lisan (teks bebas; user paste dari aplikasi luar)
%
%   Satu `_desc.json` per-eksperimen menampung baris untuk SEMUA garis PSG
%   (dibedakan `psgId`). Tabel DESC di GUI hanya menampilkan baris milik garis
%   PSG aktif (lihat rowsForPsg).
%
%   GRAIN4 = GROUND TRUTH laporan final. TIDAK menulis balik ke `_faults.json`
%   (GRAIN5 dibiarkan apa adanya; diskrepansi GRAIN4↔GRAIN5 diterima).
%
%   Penulisan WAJIB ATOMIC (tmp -> movefile). NaN <-> JSON null.
%
%   API:
%     p   = pivcore.io.grain4Desc.dataPath(dataFile)
%     doc = pivcore.io.grain4Desc.emptyDoc(dataFile)
%     doc = pivcore.io.grain4Desc.read(dataFile)          % [] -> emptyDoc
%     pivcore.io.grain4Desc.write(dataFile, doc)          % ATOMIC
%     r   = pivcore.io.grain4Desc.rowStruct(psgId,fNum,frame,poi,actF,isOost,desc)
%     rows= pivcore.io.grain4Desc.rowsForPsg(doc, psgId)  % cell baris milik garis
%     doc = pivcore.io.grain4Desc.setRowsForPsg(doc, psgId, rows) % ganti baris garis
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivcore/+io/grain4Desc.m

    methods (Static)

        % ================================================================
        function p = dataPath(dataFile)
        %DATAPATH  <dir>/<base>_desc.json untuk MAT PIV dataFile.
            p = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_desc.json', base));
        end


        % ================================================================
        function doc = emptyDoc(dataFile)
        %EMPTYDOC  Kerangka dokumen kosong.
            if nargin < 1, dataFile = ''; end
            [~, base, ext] = fileparts(char(dataFile));
            doc = struct();
            doc.formatName    = 'GRAIN4 Description Table';
            doc.formatVersion = 2;   % v2: NUC POS skema T/M/B/FT (dulu A/T/B/F-Tip)
            doc.source        = [base ext];
            % meta.refHorizonDeg = sudut REFERENSI HORIZONTAL (koreksi kemiringan
            % kamera; derajat vs horizontal citra). NaN = tak diset (pakai 0°).
            % meta.refHorizonPts = POSISI garis ref (2x2 [x y] pixel axMain; datum
            % KEDALAMAN nukleasi). [] = tak diset. Dulu hanya sudut di _faultgeom.json;
            % kini sudut+posisi menyatu di _desc.json.
            % REFERENSI GEOMETRI (koordinat robust; semua garis 2x2 [x y] pixel axMain):
            %   limitWallPts     = garis DINDING PEMBATAS (batas model sisi tetap; =Lpos).
            %   basePts          = garis REFERENSI BASE (dasar/alas model).
            %   indenterInitPts  = garis POSISI INDENTER AWAL (pra-eksperimen; =X0 cm).
            %                      DATUM X jarak nukleasi (proyeksi horizontal) +
            %                      pasangan kalibrasi cmPerPx (bersama dinding pembatas).
            %   modelThicknessCm = KETEBALAN model (tinggi lapisan pasir; cm; default 4).
            % (Dinding PENDORONG TIDAK disimpan sbg garis tetap: = titik-2 garis nukleasi
            %  tiap DX -> berubah, memungkinkan ukur dari sesar pertama.)
            %   modelBoxPts = 4 TITIK SUDUT kotak model [KiAtas;KaAtas;KiBawah;KaBawah]
            %                 (4x2 [x y] px). Sumber TUNGGAL semua referensi: sisi kiri=
            %                 dinding pendorong (X0), kanan=dinding pembatas (Lpos), bawah=
            %                 base, atas=ref horizontal/permukaan. Garis-garis terpisah
            %                 (refHorizonPts/limitWallPts/basePts/indenterInitPts) jadi
            %                 FALLBACK/kompat bila kotak belum diinput.
            doc.meta          = struct('basename', base, 'refHorizonDeg', NaN, ...
                                       'refHorizonPts', [], 'limitWallPts', [], ...
                                       'basePts', [], 'indenterInitPts', [], ...
                                       'modelBoxPts', [], 'modelThicknessCm', 4);
            doc.rows          = {};    % cell of row-struct (JSON array)
            % INTERPRETASI (di-rebuild tiap Save): tiap sesar ber-HW di garis PSG
            % aktif -> HW/FW values + POI + net-slip (AXSLIP) + area/dNet/angle.
            % Diisi GRAIN4 i_onSaveDescProgress (via grain5FaultExport.buildFaultJson).
            doc.faults        = {};    % cell of fault-interpretation struct
            doc.interpretation= struct('psgId','', 'psgName','', 'producedAt', '', ...
                'nFrames', [], 'strainTotalPct', [], 'velMult', []);
        end


        % ================================================================
        function doc = read(dataFile)
        %READ  Baca & NORMALISASI sidecar. Tak ada berkas -> emptyDoc. Rusak ->
        %   emptyDoc + warning (tak melempar agar GUI tetap jalan).
            p = pivcore.io.grain4Desc.dataPath(dataFile);
            if isempty(p) || ~isfile(p)
                doc = pivcore.io.grain4Desc.emptyDoc(dataFile); return;
            end
            try
                txt = fileread(p);
                raw = jsondecode(txt);
            catch ME
                warning('pivcore:grain4Desc:read', ...
                    'Gagal membaca/parse %s (%s); pakai dokumen kosong.', p, ME.message);
                doc = pivcore.io.grain4Desc.emptyDoc(dataFile); return;
            end
            doc = pivcore.io.grain4Desc.normalizeDoc(raw, dataFile);
        end


        % ================================================================
        function write(dataFile, doc, allowShrink)
        %WRITE  Tulis dokumen ke `<base>_desc.json` secara ATOMIC.
        %
        %   GUARD ANTI-PENYUSUTAN: kecuali `allowShrink`=TRUE, penulisan yang
        %   membuat #baris BERKURANG dari yang ada di disk DITOLAK + backup byte
        %   asli ke `<base>_desc.json.SAFEBAK`. Melindungi dari auto-save/efek-
        %   samping yang menimpa data lengkap dengan tabel kosong/terfilter/menyusut
        %   (insiden data-hilang P-CON-F1 2026-07-17 & auto-save-on-close 2026-07-18:
        %   95 baris -> 0/1/3). `allowShrink`=TRUE HANYA dari jalur SAVE EKSPLISIT
        %   yang sudah minta KONFIRMASI user (i_confirmWriteDesc di GRAIN4) — di situ
        %   user memang sengaja mengurangi baris. Default (arg absen) = FALSE =
        %   lindungi. Menambah/sama boleh; berkurang tanpa izin = tolak+backup.
            if nargin < 3 || isempty(allowShrink), allowShrink = false; end
            p = pivcore.io.grain4Desc.dataPath(dataFile);
            if isempty(p)
                error('pivcore:grain4Desc:noPath', ...
                    'Tak bisa menentukan path _desc untuk: %s', dataFile);
            end
            % --- GUARD: cegah penyusutan tak-berizin (berisi -> lebih sedikit) --
            newN = pivcore.io.grain4Desc.rowCount(doc);
            if ~allowShrink && isfile(p)
                oldN = 0;
                try, oldN = pivcore.io.grain4Desc.rowCount(pivcore.io.grain4Desc.read(dataFile)); catch, end
                if newN < oldN
                    bak = [p '.SAFEBAK'];
                    try, copyfile(p, bak, 'f'); catch, end
                    warning('pivcore:grain4Desc:shrinkOverwrite', ...
                        ['Menolak menimpa %s (berisi %d baris) dengan %d baris (MENYUSUT). ' ...
                         'Kemungkinan tabel terfilter/kosong / garis PSG bergeser. Backup: %s. ' ...
                         'Simpan via tombol Save (berkonfirmasi) bila memang disengaja.'], ...
                        p, oldN, newN, bak);
                    return;   % TIDAK menulis -> data lama utuh
                end
            end
            % ----------------------------------------------------------------
            doc = pivcore.io.grain4Desc.prepForEncode(doc);
            txt = jsonencode(doc, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0
                error('pivcore:grain4Desc:open', 'Tak bisa membuka %s utk tulis.', tmp);
            end
            cleaner = onCleanup(@() pivcore.io.grain4Desc.cleanupTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
            fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok
                error('pivcore:grain4Desc:move', ...
                    'Gagal memindah tmp->final (%s): %s', p, msg);
            end
        end


        % ================================================================
        function r = rowStruct(psgId, fNum, frame, poi, actF, isOost, desc, fsrDir, nucPos, fTrx)
        %ROWSTRUCT  Skeleton satu baris tabel DESC. Semua argumen opsional.
        %   fsrDir = arah pembentukan FSR: 'UP' (nukleasi tengah->permukaan) atau
        %   'DWN' (permukaan->tengah); kolom antara IS/OOST & DESC.
        %   nucPos = posisi nukleasi (HANYA relevan saat POI='NUC-FSR'): 'T'(Top)/
        %          'M'(Mid)/'B'(Bottom)/'FT'(Fault-Tip). Char; kosong = tak diisi.
        %          (Skema lama A/T/B/F-Tip dimigrasi otomatis saat baca file v<2.)
        %   fTrx = FRAME AKHIR TRANSISI (untuk baris POI='TRX'; hand-off antar
        %          imbrikasi). frame=awal, fTrx=akhir -> fill hijau di axPOT.
            if nargin < 1, psgId  = ''; end
            if nargin < 2, fNum   = ''; end
            if nargin < 3, frame  = NaN; end
            if nargin < 4, poi    = '</blank>'; end
            if nargin < 5, actF   = NaN; end
            if nargin < 6, isOost = ''; end
            if nargin < 7, desc   = ''; end
            if nargin < 8, fsrDir = ''; end
            if nargin < 9, nucPos = ''; end
            if nargin < 10, fTrx  = NaN; end
            r = struct();
            r.psgId  = pivcore.io.grain4Desc.tostr(psgId);
            r.fNum   = pivcore.io.grain4Desc.tostr(fNum);
            r.frame  = pivcore.io.grain4Desc.scal(frame);
            r.fTrx   = pivcore.io.grain4Desc.scal(fTrx);
            r.poi    = pivcore.io.grain4Desc.tostr(poi);
            r.actF   = pivcore.io.grain4Desc.scal(actF);
            r.isOost = pivcore.io.grain4Desc.tostr(isOost);
            r.fsrDir = pivcore.io.grain4Desc.tostr(fsrDir);
            r.nucPos = pivcore.io.grain4Desc.nucPosVal(nucPos);
            r.desc   = pivcore.io.grain4Desc.tostr(desc);
            % GEOMETRI BIDANG SESAR per-DX (polyline di axMain, Ctrl+Q). Tiap titik
            % pengamatan (POI/DX) punya bentuk+sudut+panjang sesarnya SENDIRI.
            %   vertices = Nx2 [x y] pixel gambar axMain (data-coord).
            %   angleDeg = sudut regresi vertex relatif ref horizontal.
            %   lenCm    = panjang polyline (cm; cmPerPx isotropik dxCm/lebar).
            % Growth per-DX TAK disimpan (turunan; dihitung antar-DX berurutan).
            r.vertices = zeros(0,2);
            r.angleDeg = NaN;
            r.lenCm    = NaN;
            % TAPER ANGLE (kemiringan topografi) per-DX. Garis 2-titik di axMain
            % (topografi permukaan) -> sudut relatif ref horizontal. Beda dari
            % bidang sesar (vertices/angleDeg): ini kemiringan TOPOGRAFI, bukan
            % sesar. Dipakai untuk interpolasi keyframe + taper awal/akhir/change
            % per-F#. taperVerts = Nx2 [x y] pixel axMain; taperDeg = sudut (°).
            r.taperVerts = zeros(0,2);
            r.taperDeg   = NaN;
            % TITIK NUKLEASI (HANYA relevan saat POI='NUC-FSR'). Input = garis
            % 2-titik di axMain: VERTEX-1 = posisi nukleasi; VERTEX-2 = titik pd
            % bidang sesar F-1 yang dihubungkan user (eyeballing). Turunan:
            %   nucVerts    = Nx2 [x y] pixel axMain (>=2 titik; [1]=nukleasi).
            %   nucDistCm   = panjang garis nukleasi->bidang sesar (cm) = jarak.
            %   nucDepthCm  = KEDALAMAN tegak-lurus vertex-1 ke ref horizontal (cm).
            %   nucDistF1Cm = jarak vertex-1 ke vertex TERDEKAT bidang sesar F-1
            %                 (cross-check; diisi saat commit/geometri).
            r.nucVerts    = zeros(0,2);
            r.nucDistCm   = NaN;
            r.nucDepthPx  = NaN;   % KEDALAMAN tegak-lurus nukleasi ke garis ref (PIXEL)
            r.nucDepthCm  = NaN;   % = nucDepthPx * cmPerPx (kalibrasi)
            r.nucDistF1Cm = NaN;
        end


        % ================================================================
        function rows = rowsForPsg(doc, psgId)
        %ROWSFORPSG  Cell baris (row-struct) milik garis PSG `psgId`. psgId ''
        %   -> baris tanpa psgId (kompat/legacy). Urutan asli dipertahankan.
            rows = {};
            if ~isstruct(doc) || ~isfield(doc,'rows'), return; end
            all = pivcore.io.grain4Desc.tocell(doc.rows);
            key = pivcore.io.grain4Desc.tostr(psgId);
            for k = 1:numel(all)
                r = pivcore.io.grain4Desc.normRow(all{k});
                if strcmp(r.psgId, key), rows{end+1} = r; end %#ok<AGROW>
            end
        end


        % ================================================================
        function doc = setRowsForPsg(doc, psgId, rows)
        %SETROWSFORPSG  Ganti SEMUA baris milik `psgId` dengan `rows` (cell of
        %   row-struct). Baris garis PSG LAIN dipertahankan apa adanya. Baris
        %   baru ditaruh di akhir (setelah baris garis lain).
            if ~isstruct(doc), doc = pivcore.io.grain4Desc.emptyDoc(''); end
            if ~isfield(doc,'rows'), doc.rows = {}; end
            key  = pivcore.io.grain4Desc.tostr(psgId);
            keep = {};
            all  = pivcore.io.grain4Desc.tocell(doc.rows);
            for k = 1:numel(all)
                r = pivcore.io.grain4Desc.normRow(all{k});
                if ~strcmp(r.psgId, key), keep{end+1} = r; end %#ok<AGROW>
            end
            add = pivcore.io.grain4Desc.tocell(rows);
            for k = 1:numel(add)
                r = pivcore.io.grain4Desc.normRow(add{k});
                r.psgId = key;                      % paksa psgId konsisten
                keep{end+1} = r; %#ok<AGROW>
            end
            doc.rows = keep;
        end


        % ================================================================
        %                        NORMALISASI / ENCODE
        % ================================================================
        function doc = normalizeDoc(raw, dataFile)
        %NORMALIZEDOC  Rakit dokumen bersih dari hasil jsondecode.
            doc = pivcore.io.grain4Desc.emptyDoc(dataFile);
            if ~isstruct(raw), return; end
            if isfield(raw,'formatVersion') && isscalar(raw.formatVersion)
                doc.formatVersion = double(raw.formatVersion);
            end
            if isfield(raw,'source') && ischar(raw.source), doc.source = raw.source; end
            % meta.refHorizonDeg (referensi horizontal; koreksi kemiringan kamera)
            % + meta.refHorizonPts (posisi garis; datum kedalaman nukleasi).
            if isfield(raw,'meta') && isstruct(raw.meta)
                if isfield(raw.meta,'refHorizonDeg')
                    doc.meta.refHorizonDeg = pivcore.io.grain4Desc.scal(raw.meta.refHorizonDeg);
                end
                for lf = {'refHorizonPts','limitWallPts','basePts','indenterInitPts'}
                    if isfield(raw.meta, lf{1})
                        Vr = pivcore.io.grain4Desc.normVerts(raw.meta.(lf{1}));
                        if size(Vr,1) >= 2, doc.meta.(lf{1}) = Vr(1:2,:); end
                    end
                end
                if isfield(raw.meta,'modelBoxPts')
                    Vb = pivcore.io.grain4Desc.normVerts(raw.meta.modelBoxPts);
                    if size(Vb,1) >= 4, doc.meta.modelBoxPts = Vb(1:4,:); end
                end
                if isfield(raw.meta,'modelThicknessCm')
                    v = pivcore.io.grain4Desc.scal(raw.meta.modelThicknessCm);
                    if isscalar(v) && isfinite(v) && v > 0, doc.meta.modelThicknessCm = v; end
                end
            end
            % MIGRASI NUC POS: file skema LAMA (formatVersion < 2) -> peta A/T/B/F-Tip
            % ke T/M/B/FT SEKALI di sini (sebelum normRow). File baru (>=2) lewat.
            legacyNuc = doc.formatVersion < 2;
            rows = {};
            if isfield(raw,'rows')
                rc = pivcore.io.grain4Desc.tocell(raw.rows);
                for k = 1:numel(rc)
                    rk = rc{k};
                    if legacyNuc && isstruct(rk) && isfield(rk,'nucPos')
                        rk.nucPos = pivcore.io.grain4Desc.migrateNucPosLegacy(rk.nucPos);
                    end
                    rows{end+1} = pivcore.io.grain4Desc.normRow(rk); %#ok<AGROW>
                end
            end
            doc.rows = rows;
            doc.formatVersion = 2;   % pasca-migrasi -> stamp versi baru
            % Blok interpretasi (opsional; di-passthrough apa adanya bila ada).
            if isfield(raw,'faults'), doc.faults = pivcore.io.grain4Desc.tocell(raw.faults); end
            if isfield(raw,'interpretation') && isstruct(raw.interpretation)
                doc.interpretation = raw.interpretation;
            end
        end


        function r = normRow(s)
        %NORMROW  Normalkan satu baris -> row-struct lengkap (field selalu ada).
            r = pivcore.io.grain4Desc.rowStruct();
            if ~isstruct(s), return; end
            if isfield(s,'psgId'),  r.psgId  = pivcore.io.grain4Desc.tostr(s.psgId);  end
            if isfield(s,'fNum'),   r.fNum   = pivcore.io.grain4Desc.tostr(s.fNum);   end
            if isfield(s,'frame'),  r.frame  = pivcore.io.grain4Desc.scal(s.frame);   end
            if isfield(s,'fTrx'),   r.fTrx   = pivcore.io.grain4Desc.scal(s.fTrx);    end
            if isfield(s,'poi'),    r.poi    = pivcore.io.grain4Desc.tostr(s.poi);    end
            if isfield(s,'actF'),   r.actF   = pivcore.io.grain4Desc.scal(s.actF);    end
            if isfield(s,'isOost'), r.isOost = pivcore.io.grain4Desc.tostr(s.isOost); end
            if isfield(s,'fsrDir'), r.fsrDir = pivcore.io.grain4Desc.tostr(s.fsrDir); end
            if isfield(s,'nucPos'), r.nucPos = pivcore.io.grain4Desc.nucPosVal(s.nucPos); end
            if isfield(s,'desc'),   r.desc   = pivcore.io.grain4Desc.tostr(s.desc);   end
            % GEOMETRI bidang sesar per-DX.
            if isfield(s,'vertices'), r.vertices = pivcore.io.grain4Desc.normVerts(s.vertices); end
            if isfield(s,'angleDeg'), r.angleDeg = pivcore.io.grain4Desc.scal(s.angleDeg); end
            if isfield(s,'lenCm'),    r.lenCm    = pivcore.io.grain4Desc.scal(s.lenCm);    end
            % TAPER (kemiringan topografi) per-DX.
            if isfield(s,'taperVerts'), r.taperVerts = pivcore.io.grain4Desc.normVerts(s.taperVerts); end
            if isfield(s,'taperDeg'),   r.taperDeg   = pivcore.io.grain4Desc.scal(s.taperDeg);   end
            % TITIK NUKLEASI (garis 2-titik; POI='NUC-FSR').
            if isfield(s,'nucVerts'),    r.nucVerts    = pivcore.io.grain4Desc.normVerts(s.nucVerts); end
            if isfield(s,'nucDistCm'),   r.nucDistCm   = pivcore.io.grain4Desc.scal(s.nucDistCm);   end
            if isfield(s,'nucDepthPx'),  r.nucDepthPx  = pivcore.io.grain4Desc.scal(s.nucDepthPx);  end
            if isfield(s,'nucDepthCm'),  r.nucDepthCm  = pivcore.io.grain4Desc.scal(s.nucDepthCm);  end
            if isfield(s,'nucDistF1Cm'), r.nucDistF1Cm = pivcore.io.grain4Desc.scal(s.nucDistF1Cm); end
            if isempty(r.poi), r.poi = '</blank>'; end
            % MIGRASI POI (2026-07-14, studi lifecycle FSR): nama lama -> baru.
            %   'FS-max' -> 'ACT-FSR' (FSR aktif; boleh ukur panjang, beberapa POI)
            %   'FS-x'   -> 'X-FS'    (FSR berhenti aktif; panjang = 0)
            % Data lama _desc.json terbaca & ditulis-ulang dgn nama baru.
            switch upper(strtrim(r.poi))
                case 'FS-MAX', r.poi = 'ACT-FSR';
                case 'FS-X',   r.poi = 'X-FS';
            end
            % LIFECYCLE FSR: panjang bidang sesar HANYA relevan utk FSR aktif
            % (PRP-FSR = mulai terbentuk; ACT-FSR = aktif/maksimum). Di UJUNG
            % siklus FSR_length := 0 (tanpa gambar): NUC-FSR (nukleasi, belum ada
            % bidang) & X-FS (FSR berhenti). -> lenCm=0, angleDeg kosong, vertices [].
            switch upper(strtrim(r.poi))
                case {'NUC-FSR','X-FS'}
                    r.lenCm = 0; r.angleDeg = NaN; r.vertices = zeros(0,2);
            end
            % CATATAN: 'NUC-TF' kini POI TERSENDIRI (bukan alias NUC-FSR). Migrasi
            % lama NUC-TF->NUC-FSR DIHENTIKAN supaya keduanya bisa dipakai bersamaan.
        end


        function doc = prepForEncode(doc)
        %PREPFORENCODE  Siapkan dokumen utk jsonencode. rows: cell -> pastikan
        %   tiap elemen row-struct bersih (NaN dibiarkan; jsonencode -> null).
            if ~isstruct(doc), doc = pivcore.io.grain4Desc.emptyDoc(''); end
            if ~isfield(doc,'rows'), doc.rows = {}; end
            all = pivcore.io.grain4Desc.tocell(doc.rows);
            out = cell(1, numel(all));
            for k = 1:numel(all)
                r = pivcore.io.grain4Desc.normRow(all{k});
                % vertices Nx2 -> cell-of-[x y] supaya jsonencode selalu array-of-
                % arrays (round-trip stabil termasuk N=1). Kosong -> {} (JSON []).
                r.vertices   = pivcore.io.grain4Desc.vertsToCell(r.vertices);
                r.taperVerts = pivcore.io.grain4Desc.vertsToCell(r.taperVerts);
                r.nucVerts   = pivcore.io.grain4Desc.vertsToCell(r.nucVerts);
                out{k} = r;
            end
            doc.rows = out;   % selalu cell -> JSON array (bahkan bila 1 elemen)
            % Blok interpretasi: pastikan CELL (JSON array) supaya konsisten.
            if isfield(doc,'faults'), doc.faults = pivcore.io.grain4Desc.tocell(doc.faults); end
            % meta garis referensi 2x2 -> cell-of-[x y] (jsonencode array-of-arrays).
            if isfield(doc,'meta') && isstruct(doc.meta)
                for lf = {'refHorizonPts','limitWallPts','basePts','indenterInitPts'}
                    if isfield(doc.meta, lf{1})
                        Pr = pivcore.io.grain4Desc.normVerts(doc.meta.(lf{1}));
                        if size(Pr,1) >= 2, doc.meta.(lf{1}) = pivcore.io.grain4Desc.vertsToCell(Pr(1:2,:));
                        else, doc.meta.(lf{1}) = []; end
                    end
                end
                if isfield(doc.meta,'modelBoxPts')
                    Pb = pivcore.io.grain4Desc.normVerts(doc.meta.modelBoxPts);
                    if size(Pb,1) >= 4, doc.meta.modelBoxPts = pivcore.io.grain4Desc.vertsToCell(Pb(1:4,:));
                    else, doc.meta.modelBoxPts = []; end
                end
            end
        end


        % ================================================================
        %              REFERENSI HORIZONTAL + GEOMETRI per-DX
        % ================================================================
        function deg = refHorizonDeg(doc)
        %REFHORIZONDEG  Sudut referensi horizontal (meta) atau NaN.
            deg = NaN;
            if isstruct(doc) && isfield(doc,'meta') && isstruct(doc.meta) ...
                    && isfield(doc.meta,'refHorizonDeg')
                deg = pivcore.io.grain4Desc.scal(doc.meta.refHorizonDeg);
            end
        end

        function doc = setRefHorizonDeg(doc, deg)
        %SETREFHORIZONDEG  Set sudut referensi horizontal di meta.
            if ~isstruct(doc), doc = pivcore.io.grain4Desc.emptyDoc(''); end
            if ~isfield(doc,'meta') || ~isstruct(doc.meta), doc.meta = struct(); end
            doc.meta.refHorizonDeg = pivcore.io.grain4Desc.scal(deg);
        end

        function P = refHorizonPts(doc)
        %REFHORIZONPTS  Posisi garis ref horizontal (2x2 [x y] pixel) atau [] bila
        %   tak diset. Datum KEDALAMAN nukleasi.
            P = [];
            if isstruct(doc) && isfield(doc,'meta') && isstruct(doc.meta) ...
                    && isfield(doc.meta,'refHorizonPts')
                P = pivcore.io.grain4Desc.normVerts(doc.meta.refHorizonPts);
                if size(P,1) < 2, P = []; end
            end
        end

        function doc = setRefHorizonPts(doc, P)
        %SETREFHORIZONPTS  Set posisi garis ref horizontal (2x2 [x y] pixel) di meta.
        %   P kosong -> hapus (garis ref dihapus).
            if ~isstruct(doc), doc = pivcore.io.grain4Desc.emptyDoc(''); end
            if ~isfield(doc,'meta') || ~isstruct(doc.meta), doc.meta = struct(); end
            V = pivcore.io.grain4Desc.normVerts(P);
            if size(V,1) >= 2, doc.meta.refHorizonPts = V(1:2,:); else, doc.meta.refHorizonPts = []; end
        end

        function P = metaLine(doc, fld)
        %METALINE  Ambil garis referensi 2x2 [x y] dari meta.(fld) atau [] bila
        %   tak diset (fld = 'limitWallPts'/'basePts'/'refHorizonPts').
            P = [];
            if isstruct(doc) && isfield(doc,'meta') && isstruct(doc.meta) ...
                    && isfield(doc.meta, fld)
                P = pivcore.io.grain4Desc.normVerts(doc.meta.(fld));
                if size(P,1) < 2, P = []; end
            end
        end

        function doc = setMetaLine(doc, fld, P)
        %SETMETALINE  Set garis referensi meta.(fld) = 2x2 [x y] (kosong -> hapus).
            if ~isstruct(doc), doc = pivcore.io.grain4Desc.emptyDoc(''); end
            if ~isfield(doc,'meta') || ~isstruct(doc.meta), doc.meta = struct(); end
            V = pivcore.io.grain4Desc.normVerts(P);
            if size(V,1) >= 2, doc.meta.(fld) = V(1:2,:); else, doc.meta.(fld) = []; end
        end

        function P = modelBoxPts(doc)
        %MODELBOXPTS  4 titik sudut kotak model [KiAtas;KaAtas;KaBawah;KiBawah]
        %   (4x2 [x y] px; urutan CLOCKWISE dari kiri-atas) atau [] bila tak diset.
            P = [];
            if isstruct(doc) && isfield(doc,'meta') && isstruct(doc.meta) ...
                    && isfield(doc.meta,'modelBoxPts')
                V = pivcore.io.grain4Desc.normVerts(doc.meta.modelBoxPts);
                if size(V,1) >= 4, P = V(1:4,:); end
            end
        end

        function doc = setModelBoxPts(doc, P)
        %SETMODELBOXPTS  Set 4 titik sudut kotak model (kosong -> hapus).
            if ~isstruct(doc), doc = pivcore.io.grain4Desc.emptyDoc(''); end
            if ~isfield(doc,'meta') || ~isstruct(doc.meta), doc.meta = struct(); end
            V = pivcore.io.grain4Desc.normVerts(P);
            if size(V,1) >= 4, doc.meta.modelBoxPts = V(1:4,:); else, doc.meta.modelBoxPts = []; end
        end

        function s = boxSides(P)
        %BOXSIDES  Turunkan sisi-sisi kotak model dari 4 titik CLOCKWISE
        %   P = [KiAtas;KaAtas;KaBawah;KiBawah]. Kembalikan struct:
        %     .left   = [x1 y1; x2 y2] sisi KIRI  (KiAtas->KiBawah) = DINDING PENDORONG (X0)
        %     .right  = sisi KANAN (KaAtas->KaBawah)                = DINDING PEMBATAS (Lpos)
        %     .top    = sisi ATAS  (KiAtas->KaAtas)                 = REF HORIZONTAL/permukaan
        %     .bottom = sisi BAWAH (KiBawah->KaBawah)               = BASE
        %     .xLeft/.xRight = x rata-rata sisi kiri/kanan (datum X)
        %   [] semua bila P bukan 4 titik.
            s = struct('left',[],'right',[],'top',[],'bottom',[],'xLeft',NaN,'xRight',NaN);
            P = pivcore.io.grain4Desc.normVerts(P);
            if size(P,1) < 4, return; end
            KiA = P(1,:); KaA = P(2,:); KaB = P(3,:); KiB = P(4,:);
            s.left   = [KiA; KiB];
            s.right  = [KaA; KaB];
            s.top    = [KiA; KaA];
            s.bottom = [KiB; KaB];
            s.xLeft  = mean([KiA(1) KiB(1)]);
            s.xRight = mean([KaA(1) KaB(1)]);
        end

        function c = modelThicknessCm(doc)
        %MODELTHICKNESSCM  Ketebalan model (cm) dari meta atau default 4.
            c = 4;
            if isstruct(doc) && isfield(doc,'meta') && isstruct(doc.meta) ...
                    && isfield(doc.meta,'modelThicknessCm')
                v = pivcore.io.grain4Desc.scal(doc.meta.modelThicknessCm);
                if isscalar(v) && isfinite(v) && v > 0, c = v; end
            end
        end

        function doc = setModelThicknessCm(doc, c)
        %SETMODELTHICKNESSCM  Set ketebalan model (cm) di meta (>0; else 4).
            if ~isstruct(doc), doc = pivcore.io.grain4Desc.emptyDoc(''); end
            if ~isfield(doc,'meta') || ~isstruct(doc.meta), doc.meta = struct(); end
            v = pivcore.io.grain4Desc.scal(c);
            if ~(isscalar(v) && isfinite(v) && v > 0), v = 4; end
            doc.meta.modelThicknessCm = v;
        end

        function dPx = pointToSegLineDistPx(p, P)
        %POINTTOSEGLINEDISTPX  Jarak TEGAK-LURUS (searah normal) titik p (1x2 [x y])
        %   ke GARIS TAK HINGGA yang melewati 2 titik P (2x2 [x y]). = |cross| / |arah|.
        %   NaN bila p/P tak valid atau P berimpit. Dipakai utk KEDALAMAN nukleasi
        %   dari garis ref horizontal (piksel; kali cmPerPx -> cm).
            dPx = NaN;
            if numel(p) < 2 || any(~isfinite(p(1:2))), return; end
            P = pivcore.io.grain4Desc.normVerts(P);
            if size(P,1) < 2 || any(~isfinite(P(1,:))) || any(~isfinite(P(2,:))), return; end
            a = P(1,:); b = P(2,:);
            dvec = b - a; L = hypot(dvec(1), dvec(2));
            if L < eps, return; end
            % jarak titik ke garis lewat a,b = |(p-a) x (b-a)| / |b-a|.
            ap = [p(1)-a(1), p(2)-a(2)];
            crossv = ap(1)*dvec(2) - ap(2)*dvec(1);
            dPx = abs(crossv) / L;
        end

        function g = growthPerDx(rowsSortedByFrame, idx, dtSec)
        %GROWTHPERDX  Growth rate (cm/s) DX ke-idx = (lenCm[idx]-lenCm[idx-1]) /
        %   (Δframe[idx-1..idx] * dt). rowsSortedByFrame = cell baris SATU F# urut
        %   frame menaik. idx=1 (DX pertama) -> NaN (tak ada n-1). NaN bila len/
        %   frame tak lengkap. dt default 10.
            g = NaN;
            if nargin < 3 || isempty(dtSec) || ~isfinite(dtSec) || dtSec <= 0, dtSec = 10; end
            if ~iscell(rowsSortedByFrame) || idx < 2 || idx > numel(rowsSortedByFrame), return; end
            a = pivcore.io.grain4Desc.normRow(rowsSortedByFrame{idx-1});
            b = pivcore.io.grain4Desc.normRow(rowsSortedByFrame{idx});
            if ~(isfinite(a.lenCm) && isfinite(b.lenCm)), return; end
            if ~(isfinite(a.frame) && isfinite(b.frame)), return; end
            df = abs(b.frame - a.frame);
            if df <= 0, return; end
            g = (b.lenCm - a.lenCm) / (df * dtSec);
        end

        % ================================================================
        %              DETEKSI: jumlah sesar AKTIF per frame
        % ================================================================
        function [f0, f1, ok, xfsExcl] = faultActiveRange(rowsOfFault)
        %FAULTACTIVERANGE  Rentang FRAME "aktif" satu sesar dari baris-baris DX-nya.
        %   ATURAN (revisi 2026-07-19 — dua BATAS eksklusif, isi inklusif):
        %   Setiap sesar SELALU diawali NUC dan (bila selesai) diakhiri X-FS. Kedua
        %   batas itu EKSKLUSIF; SEMUA frame di antaranya INKLUSIF (aktif).
        %     f0 = frame NUC-* PERTAMA (jenis/nucPos apa pun) — batas AWAL eksklusif
        %          (di frame NUC sesar BELUM terbentuk -> aktif mulai f0+1).
        %     f1 = frame X-FS (batas AKHIR eksklusif; sesar SUDAH mati di X-FS) atau
        %          max frame (tak ada X-FS -> ujung akhir INKLUSIF, siklus belum tutup).
        %   AKTIF  <=>  f0 < frame < f1  (bila ada X-FS)  |  f0 < frame <= f1 (tanpa).
        %   ok=false bila tak ada NUC-* sama sekali (sesar tak pernah "ternukleasi").
        %   xfsExcl = true bila batas akhir dari X-FS (eksklusif); false = max (inklusif).
        %   Batas AWAL SELALU eksklusif -> f0 tak pernah ikut dihitung.
        %   rowsOfFault = cell baris DX SATU F# (urutan bebas).
        %   Contoh F5: NUC-FSR@140 · X-FS@166 -> aktif 141..165 (140 & 166 dibuang).
            f0 = NaN; f1 = NaN; ok = false; xfsExcl = false;
            if ~iscell(rowsOfFault) || isempty(rowsOfFault), return; end
            nucFrames = []; xfsFrame = NaN; allFrames = [];
            for k = 1:numel(rowsOfFault)
                r = pivcore.io.grain4Desc.normRow(rowsOfFault{k});
                v = r.frame; if ~(isscalar(v) && isfinite(v)), continue; end
                allFrames(end+1) = v; %#ok<AGROW>
                poiU = upper(strtrim(char(r.poi)));
                if strncmp(poiU, 'NUC-', 4), nucFrames(end+1) = v; end %#ok<AGROW>
                if any(strcmp(poiU, {'X-FS','X-FSR'})), xfsFrame = v; end
            end
            % f_start: frame NUC-* PERTAMA (apa pun). Tanpa NUC -> tak pernah ternukleasi.
            if isempty(nucFrames), return; end
            f0 = min(nucFrames);
            if isfinite(xfsFrame)
                f1 = xfsFrame; xfsExcl = true;          % X-FS -> batas akhir eksklusif
            else
                f1 = max(allFrames); xfsExcl = false;   % tak ada X-FS -> ujung inklusif
            end
            % Valid bila ada minimal SATU frame di dalam (batas awal selalu eksklusif).
            ok = (xfsExcl && (f1 > f0 + 1)) || (~xfsExcl && (f1 > f0));
        end

        function c = activeCountAtFrame(rowsAllFaults, frame)
        %ACTIVECOUNTATFRAME  DETEKSI: jumlah sesar AKTIF pada `frame`. rowsAllFaults =
        %   cell SEMUA baris DX (1 garis PSG, semua F#). Kelompokkan per fNum ->
        %   faultActiveRange -> hitung sesar yg rentang aktifnya MENCAKUP `frame`.
        %   Batas AWAL (NUC) & batas X-FS EKSKLUSIF; isi inklusif:
        %     f0 < frame < f1 (bila xfsExcl) | f0 < frame <= f1 (tanpa X-FS).
            c = 0;
            f = round(pivcore.io.grain4Desc.scal(frame));
            if ~isfinite(f) || ~iscell(rowsAllFaults), return; end
            grp = containers.Map('KeyType','char','ValueType','any');
            for k = 1:numel(rowsAllFaults)
                r = pivcore.io.grain4Desc.normRow(rowsAllFaults{k});
                key = strtrim(char(r.fNum)); if isempty(key), continue; end
                if isKey(grp,key), grp(key) = [grp(key) {r}]; else, grp(key) = {r}; end
            end
            ks = keys(grp);
            for i = 1:numel(ks)
                [f0, f1, ok, xfsExcl] = pivcore.io.grain4Desc.faultActiveRange(grp(ks{i}));
                if ~ok, continue; end
                if xfsExcl
                    inRange = (f > f0 && f < f1);      % NUC & X-FS eksklusif
                else
                    inRange = (f > f0 && f <= f1);     % NUC eksklusif, ujung inklusif
                end
                if inRange, c = c + 1; end
            end
        end

        function V = normVerts(x)
        %NORMVERTS  Ratakan input vertex -> Nx2 double [x y]. Terima Nx2 / cell-of-
        %   [x y] (dari kami) / 1x2 (N=1) / 2xN. Bentuk tak dikenal -> 0x2.
            V = zeros(0,2);
            if isempty(x), return; end
            if iscell(x)
                rows = zeros(0,2);
                for k = 1:numel(x)
                    v = x{k};
                    if isnumeric(v) && numel(v) == 2, rows(end+1,:) = reshape(double(v),1,2); end %#ok<AGROW>
                end
                V = rows; return;
            end
            if isnumeric(x)
                M = double(x);
                if isvector(M) && numel(M) == 2, V = reshape(M,1,2); return; end
                if size(M,2) == 2, V = M; return; end
                if size(M,1) == 2, V = M.'; return; end
            end
        end

        function c = vertsToCell(V)
        %VERTSTOCELL  Nx2 -> cell{1xN} of [x y] (utk jsonencode array-of-arrays).
            V = pivcore.io.grain4Desc.normVerts(V);
            c = cell(1, size(V,1));
            for k = 1:size(V,1), c{k} = V(k,:); end
        end

        function L = polylineLenPx(V)
        %POLYLINELENPX  Panjang polyline (pixel) = Σ hypot antar-vertex.
            L = 0;
            V = pivcore.io.grain4Desc.normVerts(V);
            if size(V,1) < 2, return; end
            for k = 2:size(V,1)
                a = V(k-1,:); b = V(k,:);
                if any(~isfinite([a b])), continue; end
                L = L + hypot(b(1)-a(1), b(2)-a(2));
            end
        end

        function Lcm = lenCmOf(V, cmPerPx)
        %LENCMOF  Panjang polyline (cm). NaN bila cmPerPx tak valid.
            Lcm = NaN;
            if nargin < 2 || ~isscalar(cmPerPx) || ~isfinite(cmPerPx) || cmPerPx <= 0, return; end
            Lcm = pivcore.io.grain4Desc.polylineLenPx(V) * double(cmPerPx);
        end

        function deg = angleDegOf(V)
        %ANGLEDEGOF  Sudut/dip polyline via REGRESI least-squares vs horizontal
        %   citra, dinormalkan (-90,90] lewat pivcore.pot.faultAngle.fromPoints.
        %   Vertikal -> ±90. NaN bila <2 vertex valid.
            deg = NaN;
            V = pivcore.io.grain4Desc.normVerts(V);
            V = V(all(isfinite(V),2), :);
            if size(V,1) < 2, return; end
            x = V(:,1); y = V(:,2);
            if (max(x)-min(x)) < eps
                deg = pivcore.pot.faultAngle.fromPoints([0 0], [0 1]);
                if ~isfinite(deg), deg = 90; end
                return;
            end
            p = polyfit(x, y, 1);
            deg = pivcore.pot.faultAngle.fromPoints([0 0], [1 p(1)]);
        end

        function deg = angleDegRelOf(V, refDeg)
        %ANGLEDEGRELOF  Sudut polyline RELATIF referensi horizontal (koreksi
        %   kemiringan kamera) = angleDegOf(V) - refDeg, ternormalkan (-90,90].
        %   refDeg NaN/absen -> = angleDegOf.
            deg = pivcore.io.grain4Desc.angleDegOf(V);
            if ~isfinite(deg), return; end
            if nargin < 2 || ~isscalar(refDeg) || ~isfinite(refDeg), return; end
            d = deg - double(refDeg);
            deg = pivcore.pot.faultAngle.fromPoints([0 0], [cosd(d) sind(d)]);
        end

        function cpp = cmPerPxFromGeom(dxCm, widthPx)
        %CMPERPXFROMGEOM  cmPerPx ISOTROPIK = dxCm / widthPx. NaN bila tak valid.
            cpp = NaN;
            if ~isscalar(dxCm)  || ~isfinite(dxCm)  || dxCm  <= 0, return; end
            if ~isscalar(widthPx) || ~isfinite(widthPx) || widthPx <= 0, return; end
            cpp = double(dxCm) / double(widthPx);
        end


        % ================================================================
        %                   TITIK NUKLEASI (murni/headless)
        % ================================================================
        function p = nucPointPx(V)
        %NUCPOINTPX  Posisi nukleasi (1x2 [x y] pixel) = VERTEX PERTAMA garis
        %   nukleasi. [] bila <1 vertex valid.
            p = [];
            V = pivcore.io.grain4Desc.normVerts(V);
            V = V(all(isfinite(V),2), :);
            if isempty(V), return; end
            p = V(1,:);
        end

        function dCm = nucDistCmOf(V, cmPerPx)
        %NUCDISTCMOF  Jarak (cm) nukleasi->bidang sesar = PANJANG garis 2-titik
        %   (vertex-1 -> vertex-2). = lenCmOf. NaN bila cmPerPx/vertices tak valid.
            dCm = pivcore.io.grain4Desc.lenCmOf(V, cmPerPx);
        end

        function dPx = pointToLineDistPx(p, refDeg)
        %POINTTOLINEDISTPX  Jarak TEGAK-LURUS titik `p` (1x2 [x y]) ke garis
        %   referensi horizontal. refDeg = sudut ref (° dari horizontal citra;
        %   NaN/absen -> 0 = horizontal murni). Garis ref dianggap melewati
        %   ORIGIN citra (y=0 di refDeg=0 -> depth = |y|). Untuk refDeg!=0,
        %   depth = jarak tegak-lurus p ke garis berarah refDeg lewat origin.
        %   Dipakai utk KEDALAMAN nukleasi (koreksi kemiringan kamera). >=0.
            dPx = NaN;
            if numel(p) < 2 || any(~isfinite(p(1:2))), return; end
            if nargin < 2 || ~isscalar(refDeg) || ~isfinite(refDeg), refDeg = 0; end
            % Vektor arah garis ref (unit) & normal-nya.
            th = double(refDeg) * pi/180;
            nrm = [-sin(th), cos(th)];      % normal terhadap arah (cosθ, sinθ)
            dPx = abs(p(1)*nrm(1) + p(2)*nrm(2));
        end

        function dPx = nearestVertexDistPx(p, V)
        %NEARESTVERTEXDISTPX  Jarak (pixel) titik `p` (1x2) ke VERTEX TERDEKAT di
        %   antara vertices `V` (Nx2). NaN bila p/V tak valid.
            dPx = NaN;
            if numel(p) < 2 || any(~isfinite(p(1:2))), return; end
            V = pivcore.io.grain4Desc.normVerts(V);
            V = V(all(isfinite(V),2), :);
            if isempty(V), return; end
            d = hypot(V(:,1)-p(1), V(:,2)-p(2));
            dPx = min(d);
        end

        function xPx = lineMeanX(P)
        %LINEMEANX  Koordinat X (pixel) rata-rata garis 2-titik P (2x2 [x y]) =
        %   x rata-rata endpoint (garis indenter awal umumnya tegak -> x konstan).
        %   NaN bila P tak valid.
            xPx = NaN;
            P = pivcore.io.grain4Desc.normVerts(P);
            if size(P,1) < 2, return; end
            xPx = mean(P(1:2,1));
        end

        function dPx = horizDistPx(p, xRefPx)
        %HORIZDISTPX  Jarak HORIZONTAL (pixel) titik p (1x2 [x y]) ke datum X
        %   (garis vertikal x=xRefPx) = |x_p - xRefPx|. Proyeksi ke sumbu
        %   shortening (1-D horizontal). NaN bila tak valid.
            dPx = NaN;
            if numel(p) < 2 || ~isfinite(p(1)), return; end
            if ~(isscalar(xRefPx) && isfinite(xRefPx)), return; end
            dPx = abs(double(p(1)) - double(xRefPx));
        end

        function cpp = cmPerPxFromRefPair(x0Px, xWallPx, distCm)
        %CMPERPXFROMREFPAIR  cmPerPx kalibrasi dari SEPASANG datum X ber-jarak-cm
        %   diketahui: garis indenter awal (x0Px = X0) & dinding pembatas
        %   (xWallPx = Lpos), berjarak `distCm` cm (= L0_cm = |Lpos-X0|).
        %   cmPerPx = distCm / |xWallPx - x0Px| (pixel horizontal). NaN bila tak valid.
            cpp = NaN;
            if ~(isscalar(x0Px) && isfinite(x0Px)), return; end
            if ~(isscalar(xWallPx) && isfinite(xWallPx)), return; end
            if ~(isscalar(distCm) && isfinite(distCm) && distCm > 0), return; end
            dpx = abs(double(xWallPx) - double(x0Px));
            if dpx < eps, return; end
            cpp = double(distCm) / dpx;
        end


        function [doc, nAdopted] = adoptOrphanRows(doc, knownPsgIds, targetPsgId)
        %ADOPTORPHANROWS  Re-map baris DESC YATIM ke `targetPsgId`. Baris yatim =
        %   psgId-nya TIDAK ada di `knownPsgIds` (cellstr id garis PSG NYATA dari
        %   _potdata psgLines). Terjadi saat garis PSG bergeser -> id psg berubah
        %   (lihat [[multi-psg-per-side-scoping]], insiden P-CON-F1) -> baris lama
        %   tak lagi cocok garis mana pun -> tabel kosong walau data ADA.
        %
        %   AMAN HANYA saat 1 garis PSG (mayoritas eksperimen 1-sisi): tak ada
        %   ambiguitas baris yatim milik garis yang mana. Bila >1 garis PSG,
        %   TIDAK mengadopsi (kembalikan apa adanya) supaya tak salah kaitkan.
        %
        %   knownPsgIds : cellstr id garis PSG nyata (mis. dari psgLines[].id).
        %   targetPsgId : id garis PSG aktif tujuan adopsi.
        %   nAdopted    : jumlah baris yang di-remap.
            nAdopted = 0;
            if ~isstruct(doc) || ~isfield(doc,'rows'), return; end
            if nargin < 3 || isempty(targetPsgId), return; end
            targetPsgId = pivcore.io.grain4Desc.tostr(targetPsgId);
            if isempty(targetPsgId), return; end
            % Hanya adopsi bila targetPsgId memang salah satu garis nyata & jumlah
            % garis nyata == 1 (tak ambigu).
            known = {};
            if iscell(knownPsgIds)
                for k = 1:numel(knownPsgIds)
                    s = pivcore.io.grain4Desc.tostr(knownPsgIds{k});
                    if ~isempty(s), known{end+1} = s; end %#ok<AGROW>
                end
            end
            if numel(known) ~= 1 || ~strcmp(known{1}, targetPsgId), return; end
            knownSet = containers.Map(known, num2cell(true(1,numel(known))));
            all = pivcore.io.grain4Desc.tocell(doc.rows);
            out = cell(1, numel(all));
            for k = 1:numel(all)
                r = pivcore.io.grain4Desc.normRow(all{k});
                if ~isKey(knownSet, r.psgId)   % yatim -> adopsi
                    r.psgId = targetPsgId; nAdopted = nAdopted + 1;
                end
                out{k} = r;
            end
            doc.rows = out;
        end

        function n = rowCount(doc)
        %ROWCOUNT  Jumlah baris DESC di dokumen (0 bila tak ada/rusak). Dipakai
        %   guard anti-timpa-kosong di write.
            n = 0;
            if isstruct(doc) && isfield(doc,'rows')
                n = numel(pivcore.io.grain4Desc.tocell(doc.rows));
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

        function v = scal(x)
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end

        function s = nucPosVal(x)
        %NUCPOSVAL  Normalkan posisi nukleasi ke skema 'T'/'M'/'B'/'FT'/'ALL'
        %   (Top/Mid/Bottom/Fault-Tip/semua posisi; else ''). Terima char/string; numerik/NaN
        %   -> '' (kompat kolom FS lama). PURE passthrough skema baru — migrasi
        %   skema lama (A/T/B/F-Tip) ditangani SEKALI di normalizeDoc (via
        %   migrateNucPosLegacy) saat formatVersion < 2, supaya 'T' baru (top)
        %   TIDAK tertukar dgn 'T' lama (tengah).
            s = '';
            if isempty(x), return; end
            if isnumeric(x), return; end   % nilai FS lama (angka) -> kosong
            t = upper(strtrim(char(pivcore.io.grain4Desc.tostr(x))));
            switch t
                case 'T',   s = 'T';   % Top
                case 'M',   s = 'M';   % Mid
                case 'B',   s = 'B';   % Bottom
                case 'FT',  s = 'FT';  % Fault-Tip
                case 'ALL', s = 'ALL'; % nukleasi di SEMUA posisi (pasangan PRP DIR=SIM)
                otherwise,  s = '';
            end
        end

        function s = migrateNucPosLegacy(x)
        %MIGRATENUCPOSLEGACY  Peta skema LAMA (A/T/B/F-Tip) -> BARU (T/M/B/FT).
        %   A(atas)->T(top) · T(tengah lama)->M(mid) · B->B · F-Tip->FT. Dipakai
        %   HANYA di normalizeDoc utk file formatVersion < 2 (sekali). Nilai lain
        %   dilewatkan apa adanya (biar nucPosVal yg validasi).
            s = x;
            if isempty(x) || isnumeric(x), s = x; return; end
            t = upper(strtrim(char(pivcore.io.grain4Desc.tostr(x))));
            switch t
                case 'A',      s = 'T';
                case 'T',      s = 'M';
                case 'B',      s = 'B';
                case 'F-TIP',  s = 'FT';
                otherwise,     s = x;
            end
        end

        function v = fsVal(x)
        %FSVAL  Normalkan FAULT SLIP ke {0,1,2} (default 0). Terima angka/char.
            v = 0;
            if isempty(x), return; end
            if ischar(x) || isstring(x)
                t = str2double(x); if isfinite(t), x = t; else, return; end
            end
            if isscalar(x) && isnumeric(x) && isfinite(x)
                x = round(double(x)); if x >= 0 && x <= 2, v = x; end
            end
        end

        function s = tostr(x)
        %TOSTR  Ratakan apa pun ke char row aman (cell/charmatrix/string ->
        %   1 baris). Cegah bug parser teks multi-baris (pelajaran komentar lama).
            if isempty(x), s = ''; return; end
            if ischar(x)
                if size(x,1) > 1, x = strjoin(cellstr(x), newline); end
                s = reshape(char(x), 1, []); return;
            end
            if isstring(x)
                s = char(strjoin(x(:).', newline)); s = reshape(s, 1, []); return;
            end
            if iscell(x)
                parts = cellfun(@(e) pivcore.io.grain4Desc.tostr(e), x(:).', 'uni', 0);
                s = strjoin(parts, newline); s = reshape(char(s), 1, []); return;
            end
            if isnumeric(x) && isscalar(x)
                if isfinite(x), s = num2str(x); else, s = ''; end
                return;
            end
            try, s = reshape(char(string(x)), 1, []); catch, s = ''; end
        end

        function cleanupTmp(tmp)
            try, if isfile(tmp), delete(tmp); end, catch, end
        end

    end
end
