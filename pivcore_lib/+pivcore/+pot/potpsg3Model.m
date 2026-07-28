classdef potpsg3Model
%POTPSG3MODEL  Model data untuk tab POT-PSG3 (pengumpulan kurva "terbaik"
%   per sesar lewat metode garis).
%
%   Konsep alur kerja POT-PSG3:
%     - Satu GARIS sampling pada citra PSG menghasilkan N kurva POT
%       (L-01..L-N, default N=10). Setiap kurva = satu kandidat representasi
%       hanging wall sebuah sesar.
%     - Pengguna memilih kurva TERBAIK (klik di plot POT) lalu "Rekam".
%       Kurva terbaik DISALIN PENUH ke tabel sesar (records), garis di-reset
%       agar siap untuk sesar berikutnya.
%     - Tabel sesar terkumpul lintas-sesar; tiap baris menyimpan salinan
%       deret-waktu kurva + posisi garis + metrik ringkas.
%
%   Struktur:
%     M.records(i) = struct( ...
%         'name',     'Fault-1'           % label otomatis (Fault-#)
%         'note',     ''                  % catatan teredit pengguna
%         'data',     [1xnF double]       % salinan deret-waktu kurva terpilih
%         'frameDisp',NaN                 % bingkai marker probe (display)
%         'posPx',    NaN                 % posisi (px) di sepanjang garis swath
%         'srcLabel', 'L-03'              % label kurva sumber saat direkam
%         'color',    [r g b]             % warna kurva sumber
%         'mode',     'Moving average'    % transform kurva (utk plot ulang)
%         'maWindow', 2 ...
%         'fromF',    1, 'toF', nF        % rentang edit kurva
%         % --- HISTORI garis sampling (penting utk telusur ulang) ---
%         'lineP1',   [frame pos]         % ujung-1 garis sampling (ruang PSG)
%         'lineP2',   [frame pos]         % ujung-2 garis sampling
%         'cand',     struct array        % SEMUA n kurva kandidat dari garis:
%                                         %   cand(j).data/label/posPx/frameDisp
%         'visible',  true )              % overlay Fault-# tampil? (per-record)
%
%   Catatan kompatibilitas: record lama (sebelum histori) tidak punya field
%   lineP1/lineP2/cand/visible; accessor memberi default aman (NaN / kosong /
%   true) sehingga progres lama tetap dapat dimuat.
%
%   Dipakai oleh pivterry.modules.tabPOTPSG3 dan diserialisasi oleh
%   pivcore.io.autopotSession (field S.potpsg3).

    methods (Static)

        % ================================================================
        function M = ensure(M)
        %ENSURE  Pastikan M memiliki field records (array struct, boleh 0).
            if ~isstruct(M), M = struct(); end
            if ~isfield(M,'records') || ~isstruct(M.records)
                M.records = pivcore.pot.potpsg3Model.emptyRecordArray();
            end
            % activeRow: baris terpilih di tabel (0 = tidak ada).
            if ~isfield(M,'activeRow') || ~isscalar(M.activeRow)
                M.activeRow = 0;
            end
        end


        % ================================================================
        function r = emptyRecordArray()
        %EMPTYRECORDARRAY  Array struct record kosong (0x0) berfield lengkap.
            r = struct('name',{},'note',{},'data',{},'frameDisp',{}, ...
                       'posPx',{},'srcLabel',{},'color',{}, ...
                       'mode',{},'maWindow',{},'fromF',{},'toF',{}, ...
                       'lineP1',{},'lineP2',{},'cand',{},'visible',{});
        end


        % ================================================================
        function c = emptyCandArray()
        %EMPTYCANDARRAY  Array struct kandidat kosong (kurva-kurva 1 garis).
            c = struct('label',{},'data',{},'posPx',{},'frameDisp',{});
        end


        % ================================================================
        function rec = normalizeRecord(rec)
        %NORMALIZERECORD  Lengkapi field histori yang hilang pada record lama.
            if ~isfield(rec,'lineP1') || numel(rec.lineP1) ~= 2, rec.lineP1 = [NaN NaN]; end
            if ~isfield(rec,'lineP2') || numel(rec.lineP2) ~= 2, rec.lineP2 = [NaN NaN]; end
            if ~isfield(rec,'cand') || ~isstruct(rec.cand)
                rec.cand = pivcore.pot.potpsg3Model.emptyCandArray();
            end
            if ~isfield(rec,'visible') || ~isscalar(rec.visible)
                rec.visible = true;
            end
        end


        % ================================================================
        function tf = hasHistory(rec)
        %HASHISTORY  Apakah record menyimpan kurva kandidat historis?
            tf = isfield(rec,'cand') && isstruct(rec.cand) && ~isempty(rec.cand);
        end


        % ================================================================
        function rec = recordFromVar(v, name, note)
        %RECORDFROMVAR  Bangun satu record dari variabel POT v (kurva sumber).
        %   Menyalin deret-waktu + metadata transform + posisi (bila ada).
            if nargin < 3, note = ''; end
            rec = struct();
            rec.name      = char(name);
            rec.note      = char(note);
            rec.data      = [];
            rec.frameDisp = NaN;
            rec.posPx     = NaN;
            rec.srcLabel  = '';
            rec.color     = [0 0 0];
            rec.mode      = 'Moving average';
            rec.maWindow  = 2;
            rec.fromF     = 1;
            rec.toF       = NaN;
            rec.lineP1    = [NaN NaN];
            rec.lineP2    = [NaN NaN];
            rec.cand      = pivcore.pot.potpsg3Model.emptyCandArray();
            rec.visible   = true;
            if isfield(v,'data'),     rec.data     = v.data(:).'; end
            if isfield(v,'label'),    rec.srcLabel = char(v.label); end
            if isfield(v,'color') && numel(v.color)==3, rec.color = v.color(:).'; end
            if isfield(v,'mode'),     rec.mode     = v.mode; end
            if isfield(v,'maWindow') && isfinite(v.maWindow), rec.maWindow = v.maWindow; end
            if isfield(v,'fromF') && isfinite(v.fromF), rec.fromF = v.fromF; end
            if isfield(v,'toF')   && isfinite(v.toF),   rec.toF   = v.toF;   end
        end


        % ================================================================
        function M = addRecord(M, rec)
        %ADDRECORD  Tambah record ke tabel; beri nama otomatis Fault-# bila
        %   nama kosong. activeRow diset ke baris baru.
            M = pivcore.pot.potpsg3Model.ensure(M);
            rec = pivcore.pot.potpsg3Model.normalizeRecord(rec);
            n = numel(M.records);
            if isempty(rec.name)
                rec.name = sprintf('Fault-%d', n+1);
            end
            % Selaraskan urutan field agar penambahan ke struct-array aman.
            if n == 0
                M.records = orderfields(rec);
            else
                M.records(n+1) = orderfields(rec, M.records(1));
            end
            M.activeRow = n + 1;
        end


        % ================================================================
        function M = deleteRow(M, row)
        %DELETEROW  Hapus baris 'row'; renumbering nama otomatis Fault-#
        %   HANYA pada baris yang masih memakai pola default.
            M = pivcore.pot.potpsg3Model.ensure(M);
            n = numel(M.records);
            if row < 1 || row > n, return; end
            M.records(row) = [];
            M = pivcore.pot.potpsg3Model.renumber(M);
            M.activeRow = min(max(0,row-1), numel(M.records));
            if numel(M.records) >= 1 && M.activeRow < 1, M.activeRow = 1; end
        end


        % ================================================================
        function M = renumber(M)
        %RENUMBER  Setel ulang nama default "Fault-#" mengikuti urutan baris.
        %   Hanya nama yang berpola "Fault-<angka>" yang di-renumber; nama
        %   kustom (mis. catatan diketik di kolom name) dibiarkan.
            for i = 1:numel(M.records)
                nm = M.records(i).name;
                if isempty(nm) || ~isempty(regexp(nm,'^Fault-\d+$','once'))
                    M.records(i).name = sprintf('Fault-%d', i);
                end
            end
        end


        % ================================================================
        function [pk, pkFrame, mn] = metrics(rec, nF, opt)
        %METRICS  Hitung metrik ringkas kurva record (sesudah transform plot):
        %   pk = nilai puncak, pkFrame = bingkai puncak, mn = rerata.
        %   Memakai potexpModel.curveXY agar konsisten dgn yang terlihat.
            pk = NaN; pkFrame = NaN; mn = NaN;
            if nargin < 3 || ~isstruct(opt), opt = struct(); end
            v = struct('data',rec.data,'mode',rec.mode,'maWindow',rec.maWindow, ...
                       'fromF',rec.fromF,'toF',rec.toF);
            if ~isfinite(v.toF), v.toF = nF; end
            [xVec, yVec] = pivcore.pot.potexpModel.curveXY(v, nF, opt);
            good = isfinite(yVec);
            if ~any(good), return; end
            [pk, idx] = max(yVec(good));
            xg = xVec(good);
            pkFrame = xg(idx);
            mn = mean(yVec(good));
        end


        % ================================================================
        function C = distinctColors(n)
        %DISTINCTCOLORS  n warna ACAK namun terpisah baik (hue tersebar +
        %   jitter, saturasi/nilai tinggi). Dipakai tombol "Randomize colors"
        %   agar kurva-kurva yang awalnya berwarna sama menjadi mudah dibeda.
            if n < 1, C = zeros(0,3); return; end
            % Hue tersebar merata lalu diacak urutannya + jitter kecil; S,V
            % acak di rentang cerah. rand di sini SAH (bukan di workflow script).
            base = (0:n-1)/n;
            jit  = (rand(1,n) - 0.5) * (0.5/n);
            hue  = mod(base(randperm(n)) + jit, 1);
            sat  = 0.65 + 0.30*rand(1,n);
            val  = 0.75 + 0.22*rand(1,n);
            C = hsv2rgb([hue(:) sat(:) val(:)]);
            C = min(1, max(0, C));
        end


        % ================================================================
        function c = randColor()
        %RANDCOLOR  Satu warna acak cerah (HSV -> RGB).
            c = hsv2rgb([rand, 0.65+0.30*rand, 0.75+0.22*rand]);
            c = min(1, max(0, c(:).'));
        end


        % ================================================================
        function txt = num(x, fmt)
        %NUM  Format angka aman: kosong/NaN -> ''.
            if nargin < 2, fmt = '%.4g'; end
            if isempty(x) || ~isfinite(x), txt = ''; else, txt = sprintf(fmt, x); end
        end

    end
end
