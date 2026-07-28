classdef potpsg4Model
%POTPSG4MODEL  Model data untuk tab POT-PSG4 (pengumpulan TITIK sampling
%   dgn METODE GARIS + SPACING, lalu di-assign manual ke BIDANG SESAR).
%
%   Konsep alur kerja POT-PSG4 (beda dgn POT-PSG3):
%     - Satu GARIS sampling pada citra PSG menghasilkan deret TITIK POT
%       (P-01..P-N). Jumlah titik ditentukan oleh SPACING (jarak px antar
%       titik), bukan jumlah tetap: n = round(panjangGaris / spacing) + 1.
%     - Tiap titik = kandidat representasi pergerakan hanging wall pada lokasi
%       tertentu di sepanjang garis (dibatasi sesar lama & sesar baru).
%     - Pengguna meng-ASSIGN beberapa titik representatif ke satu bidang sesar
%       (Fault-1, Fault-2, ...). Satu bidang sesar berisi BEBERAPA titik;
%       titik pada hanging wall yang sama berbentuk kurva mirip.
%     - Tabel: SATU BARIS = SATU TITIK, dgn kolom nomor sesar (Fault#).
%       Marker Start/Nucleation(NUC)/FSR/End dideteksi OTOMATIS dari kurva
%       (potexp-style); Length = End - Start, dalam FRAME dan dalam STRAIN
%       (bila sumbu X sudah dikonversi ke strain).
%
%   Struktur:
%     M.records(i) = struct( ...
%         'point',    'P-03'              % label titik sumber (sepanjang garis)
%         'fault',    1                   % nomor bidang sesar yg di-assign
%         'data',     [1xnF double]       % salinan deret-waktu kurva titik
%         'frameDisp',NaN                 % bingkai marker probe (display)
%         'posPx',    NaN                 % posisi (px) sepanjang garis swath
%         'color',    [r g b]             % warna kurva (ikut warna sesar)
%         'mode',     'Moving average'    % transform kurva (utk plot ulang)
%         'maWindow', 2 ...
%         'fromF',    1, 'toF', nF        % rentang edit kurva
%         % --- marker auto (frame index pada deret-waktu mentah) ---
%         'startF',   NaN, 'nucF', NaN, 'fsrF', NaN, 'endF', NaN
%         'visible',  true )              % overlay tampil? (per-record)
%
%   Catatan: warna baris tabel mengikuti warna SESAR (semua titik dengan
%   fault# sama berwarna sama) agar grup mudah dibedakan.
%
%   Dipakai oleh pivterry.modules.tabPOTPSG4 dan diserialisasi oleh
%   pivcore.io.autopotSession (field S.potpsg4).

    methods (Static)

        % ================================================================
        function M = ensure(M)
        %ENSURE  Pastikan M punya field records (array struct, boleh 0).
            if ~isstruct(M), M = struct(); end
            if ~isfield(M,'records') || ~isstruct(M.records)
                M.records = pivcore.pot.potpsg4Model.emptyRecordArray();
            end
            if ~isfield(M,'activeRow') || ~isscalar(M.activeRow)
                M.activeRow = 0;
            end
            % cutOn: bila true, kurva tiap anggota sesar DIPOTONG (non-destruktif)
            % di bawah kurva pembatas (titik posPx terbesar di sesar itu).
            if ~isfield(M,'cutOn') || ~isscalar(M.cutOn)
                M.cutOn = false;
            end
            % cutLimRow: pembatas MANUAL global (baris record terpilih sbg kurva
            % pemotong). Bila >=1, SEMUA kurva dipotong di bawah kurva ini
            % (lepas dari sesar). 0 = tak ada -> fallback ke pembatas per-sesar.
            if ~isfield(M,'cutLimRow') || ~isscalar(M.cutLimRow)
                M.cutLimRow = 0;
            end
        end


        % ================================================================
        function limRows = limiterRows(M)
        %LIMITERROWS  Untuk TIAP sesar (fault>=1), baris record yg posPx
        %   TERBESAR (kurva "paling jauh" = pembatas). Mengembalikan map:
        %   limRows(faultNum) -> rowIndex. Pakai containers.Map (key double).
            M = pivcore.pot.potpsg4Model.ensure(M);
            limRows = containers.Map('KeyType','double','ValueType','double');
            faults = pivcore.pot.potpsg4Model.faultNumbers(M);
            for fi = 1:numel(faults)
                f = faults(fi);
                bestRow = 0; bestPos = -inf;
                for r = 1:numel(M.records)
                    rec = M.records(r);
                    if ~(isscalar(rec.fault) && rec.fault == f), continue; end
                    p = rec.posPx; if ~isscalar(p) || ~isfinite(p), p = -inf; end
                    if p > bestPos, bestPos = p; bestRow = r; end
                end
                if bestRow >= 1, limRows(f) = bestRow; end
            end
        end


        % ================================================================
        function y = cutData(M, row, nF)
        %CUTDATA  Deret-waktu record(row) SETELAH pemotongan (non-destruktif):
        %   untuk tiap frame, bila nilai record < nilai kurva PEMBATAS sesarnya
        %   pada frame yg sama, nilai itu di-NOL-kan. Record pembatas sendiri
        %   tidak berubah. Bila cutOn=false / record belum di-assign / pembatas
        %   tak ada -> kembalikan data apa adanya.
            M = pivcore.pot.potpsg4Model.ensure(M);
            y = [];
            if row < 1 || row > numel(M.records), return; end
            rec = pivcore.pot.potpsg4Model.normalizeRecord(M.records(row));
            y = rec.data(:).';
            if ~M.cutOn, return; end
            % --- Pembatas MANUAL global (kurva terpilih) ---------------------
            % Bila cutLimRow valid, SEMUA kurva dipotong di bawah kurva itu
            % (tanpa peduli sesar). Kurva pembatas sendiri tak dipotong.
            if isscalar(M.cutLimRow) && M.cutLimRow >= 1 && M.cutLimRow <= numel(M.records)
                limRow = M.cutLimRow;
                if limRow == row, return; end
                recL = pivcore.pot.potpsg4Model.normalizeRecord(M.records(limRow));
                yl = recL.data(:).';
                n = min(numel(y), numel(yl));
                if n < 1, return; end
                below = false(1, numel(y));
                below(1:n) = y(1:n) < yl(1:n);
                y(below) = 0;
                return;
            end
            % --- Pembatas per-sesar (perilaku lama) --------------------------
            f = rec.fault;
            if ~(isscalar(f) && isfinite(f) && f >= 1), return; end
            limRows = pivcore.pot.potpsg4Model.limiterRows(M);
            if ~isKey(limRows, f), return; end
            limRow = limRows(f);
            if limRow == row, return; end   % pembatas tak dipotong
            recL = pivcore.pot.potpsg4Model.normalizeRecord(M.records(limRow));
            yl = recL.data(:).';
            n = min(numel(y), numel(yl));
            if n < 1, return; end
            below = false(1, numel(y));
            below(1:n) = y(1:n) < yl(1:n);
            y(below) = 0;
        end


        % ================================================================
        function r = emptyRecordArray()
        %EMPTYRECORDARRAY  Array struct record kosong (0x0) berfield lengkap.
            r = struct('point',{},'fault',{},'data',{},'frameDisp',{}, ...
                       'posPx',{},'origin',{},'color',{}, ...
                       'mode',{},'maWindow',{},'fromF',{},'toF',{}, ...
                       'startF',{},'nucF',{},'fsrF',{},'endF',{}, ...
                       'visible',{},'assignLabel',{},'cutManual',{});
        end


        % ================================================================
        function rec = normalizeRecord(rec)
        %NORMALIZERECORD  Lengkapi field yang hilang pada record lama.
            if ~isfield(rec,'point'),  rec.point  = ''; end
            if ~isfield(rec,'fault') || ~isscalar(rec.fault), rec.fault = 1; end
            if ~isfield(rec,'data'),   rec.data   = []; end
            if ~isfield(rec,'frameDisp') || ~isscalar(rec.frameDisp), rec.frameDisp = NaN; end
            if ~isfield(rec,'posPx')   || ~isscalar(rec.posPx),  rec.posPx  = NaN; end
            if ~isfield(rec,'origin') || numel(rec.origin) ~= 2, rec.origin = [NaN NaN]; end
            if ~isfield(rec,'color') || numel(rec.color) ~= 3, rec.color = [0.2 0.2 0.2]; end
            if ~isfield(rec,'mode'),     rec.mode     = 'Moving average'; end
            if ~isfield(rec,'maWindow') || ~isscalar(rec.maWindow), rec.maWindow = 2; end
            if ~isfield(rec,'fromF') || ~isscalar(rec.fromF), rec.fromF = 1; end
            if ~isfield(rec,'toF')   || ~isscalar(rec.toF),   rec.toF   = NaN; end
            if ~isfield(rec,'startF') || ~isscalar(rec.startF), rec.startF = NaN; end
            if ~isfield(rec,'nucF')   || ~isscalar(rec.nucF),   rec.nucF   = NaN; end
            if ~isfield(rec,'fsrF')   || ~isscalar(rec.fsrF),   rec.fsrF   = NaN; end
            if ~isfield(rec,'endF')   || ~isscalar(rec.endF),   rec.endF   = NaN; end
            if ~isfield(rec,'visible') || ~isscalar(rec.visible), rec.visible = true; end
            % Label assignment Step-3 (HW-#/F-#/F0). Lapisan independen dari
            % `fault`; '' = belum di-assign. Diabaikan oleh Step 2/export.
            if ~isfield(rec,'assignLabel') || ~ischar(rec.assignLabel), rec.assignLabel = ''; end
            % Tanda potong-MANUAL di indenter max (Step-3 "CL"). true = kurva ini
            % dibersihkan (cut) di indenter walau checkbox auto-semua OFF. Lapisan
            % independen; tersimpan ikut record. Default false.
            if ~isfield(rec,'cutManual') || ~isscalar(rec.cutManual), rec.cutManual = false; end
        end


        % ================================================================
        function rec = recordFromVar(v, fault)
        %RECORDFROMVAR  Bangun satu record dari variabel POT v (kurva titik).
        %   Menyalin deret-waktu + metadata transform; warna ikut sesar nanti.
            if nargin < 2 || ~isscalar(fault), fault = 1; end
            rec = struct();
            rec.point     = '';
            rec.fault     = fault;
            rec.data      = [];
            rec.frameDisp = NaN;
            rec.posPx     = NaN;
            rec.origin    = [NaN NaN];
            rec.color     = [0.2 0.2 0.2];
            rec.mode      = 'Moving average';
            rec.maWindow  = 2;
            rec.fromF     = 1;
            rec.toF       = NaN;
            rec.startF    = NaN;
            rec.nucF      = NaN;
            rec.fsrF      = NaN;
            rec.endF      = NaN;
            rec.visible   = true;
            if isfield(v,'data'),     rec.data  = v.data(:).'; end
            if isfield(v,'label'),    rec.point = char(v.label); end
            if isfield(v,'color') && numel(v.color)==3, rec.color = v.color(:).'; end
            if isfield(v,'origin') && numel(v.origin)==2, rec.origin = v.origin(:).'; end
            if isfield(v,'mode'),     rec.mode     = v.mode; end
            if isfield(v,'maWindow') && isfinite(v.maWindow), rec.maWindow = v.maWindow; end
            if isfield(v,'fromF') && isfinite(v.fromF), rec.fromF = v.fromF; end
            if isfield(v,'toF')   && isfinite(v.toF),   rec.toF   = v.toF;   end
        end


        % ================================================================
        function M = addRecord(M, rec)
        %ADDRECORD  Tambah record ke tabel. activeRow -> baris baru.
            M = pivcore.pot.potpsg4Model.ensure(M);
            rec = pivcore.pot.potpsg4Model.normalizeRecord(rec);
            n = numel(M.records);
            if n == 0
                M.records = orderfields(rec);
            else
                M.records(n+1) = orderfields(rec, M.records(1));
            end
            M.activeRow = n + 1;
        end


        % ================================================================
        function M = deleteRow(M, row)
        %DELETEROW  Hapus baris 'row'.
            M = pivcore.pot.potpsg4Model.ensure(M);
            n = numel(M.records);
            if row < 1 || row > n, return; end
            M.records(row) = [];
            M.activeRow = min(max(0,row-1), numel(M.records));
            if numel(M.records) >= 1 && M.activeRow < 1, M.activeRow = 1; end
        end


        % ================================================================
        function faults = faultNumbers(M)
        %FAULTNUMBERS  Daftar nomor sesar unik yang muncul di tabel (urut).
            M = pivcore.pot.potpsg4Model.ensure(M);
            faults = [];
            for i = 1:numel(M.records)
                f = M.records(i).fault;
                % Fault < 1 (mis. 0) = belum di-assign -> bukan bidang sesar.
                if isscalar(f) && isfinite(f) && f >= 1, faults(end+1) = f; end %#ok<AGROW>
            end
            faults = unique(faults);
        end


        % ================================================================
        function M = applyFaultColors(M)
        %APPLYFAULTCOLORS  Beri warna SAMA utk semua titik pada sesar yg sama
        %   (warna terpisah antar sesar) agar grup mudah dibedakan.
            M = pivcore.pot.potpsg4Model.ensure(M);
            faults = pivcore.pot.potpsg4Model.faultNumbers(M);
            nF = numel(faults);
            if nF < 1, return; end
            C = pivcore.pot.potpsg4Model.distinctColors(nF);
            for i = 1:numel(M.records)
                f = M.records(i).fault;
                if isscalar(f) && isfinite(f) && f >= 1
                    k = find(faults == f, 1);
                    if ~isempty(k), M.records(i).color = C(k,:); end
                else
                    % Belum di-assign -> warna netral abu.
                    M.records(i).color = [0.6 0.6 0.6];
                end
            end
        end


        % ================================================================
        function [lenFrame, lenStrain] = length(rec, nF, opt)
        %LENGTH  Panjang akumulasi strain (End - Start) dlm FRAME dan STRAIN.
        %   lenStrain hanya valid bila opt.xMode='strain' (else NaN).
            lenFrame = NaN; lenStrain = NaN;
            if nargin < 3 || ~isstruct(opt), opt = struct(); end
            s = rec.startF; e = rec.endF;
            if ~isfinite(s) || ~isfinite(e), return; end
            lenFrame = e - s;
            if isfield(opt,'xMode') && strcmpi(opt.xMode,'strain') && nF > 1
                sMin = 0; sMax = 0.05;
                if isfield(opt,'sMin') && isfinite(opt.sMin), sMin = opt.sMin; end
                if isfield(opt,'sMax') && isfinite(opt.sMax), sMax = opt.sMax; end
                lenStrain = (e - s) / (nF - 1) * (sMax - sMin);
            end
        end


        % ================================================================
        function C = distinctColors(n)
        %DISTINCTCOLORS  n warna terpisah baik (hue tersebar + jitter).
            if n < 1, C = zeros(0,3); return; end
            base = (0:n-1)/n;
            jit  = (rand(1,n) - 0.5) * (0.5/n);
            hue  = mod(base(randperm(n)) + jit, 1);
            sat  = 0.65 + 0.30*rand(1,n);
            val  = 0.75 + 0.22*rand(1,n);
            C = hsv2rgb([hue(:) sat(:) val(:)]);
            C = min(1, max(0, C));
        end


        % ================================================================
        function txt = num(x, fmt)
        %NUM  Format angka aman: kosong/NaN -> ''.
            if nargin < 2, fmt = '%.4g'; end
            if isempty(x) || ~isfinite(x), txt = ''; else, txt = sprintf(fmt, x); end
        end

    end
end
