classdef step1Collect
%STEP1COLLECT  Sampler HEADLESS untuk modul Step 1: dari struct `data`
%   (hasil pivcore.data.buildDataset) + garis PSG + spacing, hasilkan array
%   record POT-PSG4 (1 baris = 1 titik) tanpa GUI/handle figure.
%
%   Inti samplingnya mereplikasi pivterry.modules.tabPOT.collectSeries, TETAPI:
%     - TIDAK memakai pivcore.util.applyOrientation (yg butuh handle UI
%       chkFlipV/chkFlipH/popRotate). Garis PSG Step-1 ditetapkan di axMain
%       TANPA orientasi (eksperimen baru = no-flip/no-rotate), jadi sampling
%       headless pakai koordinat data apa adanya -> konsisten.
%     - Dapat dijalankan dalam loop batch atas banyak eksperimen (mode
%       "ditinggal"): aman headless, progress lewat callback opsional.
%
%   Record yang dihasilkan kompatibel dengan pivcore.pot.potpsg4Model dan
%   pivcore.io.autopotSession.applyPotPsg4 (dibuka kembali di tab POT-PSG4).
%
%   API:
%     recs = pivcore.pot.step1Collect.collectAlongLine(data, p1, p2, spacing, src)
%     recs = ...collectAlongLine(data, p1, p2, spacing, src, progressFcn)
%       progressFcn(i, n) dipanggil tiap titik (opsional; [] = tak ada).
%
%   Penempatan berkas: PIVTerry/+pivterry/+pot/step1Collect.m

    methods (Static)

        % ================================================================
        function recs = collectAlongLine(data, p1, p2, spacing, src, progressFcn)
        %COLLECTALONGLINE  Sampling titik tiap `spacing` px sepanjang garis
        %   p1->p2 (koordinat data axMain). Tiap titik -> 1 record POT-PSG4
        %   dgn deret-waktu (1 x nFrames), fault=0 (belum di-assign), posPx
        %   (jarak px dari p1), origin [x y].
            if nargin < 6, progressFcn = []; end
            recs = pivcore.pot.potpsg4Model.emptyRecordArray();

            p1 = p1(:).'; p2 = p2(:).';
            if numel(p1) ~= 2 || numel(p2) ~= 2 ...
                    || any(~isfinite(p1)) || any(~isfinite(p2))
                error('pivcore:step1Collect:badLine', ...
                    'Garis PSG tidak valid (p1/p2 harus [x y] finite).');
            end
            L = hypot(p2(1)-p1(1), p2(2)-p1(2));
            if ~isfinite(L) || L <= 0
                error('pivcore:step1Collect:zeroLine', ...
                    'Panjang garis PSG nol atau tak hingga.');
            end
            if nargin < 4 || isempty(spacing) || ~isfinite(spacing) || spacing <= 0
                spacing = 10;
            end
            if nargin < 5 || isempty(src), src = 'velocity_magnitude'; end

            n  = max(2, floor(L / spacing) + 1);
            ts = linspace(0, 1, n);
            w  = 3; hh = 3;   % blok rata-rata (sama dgn default POT-PSG4)

            % Koordinat semua titik sekaligus.
            cx = p1(1) + ts*(p2(1)-p1(1));   % 1 x n
            cy = p1(2) + ts*(p2(2)-p1(2));

            % Orientasi: axMain PIVLAB SELALU vertical-flip (chkFlipV default
            % ON, lihat tabMain). Garis PSG (cx,cy) ada di ruang axMain yg SUDAH
            % di-flip; grid data mentah BELUM. Maka grid y harus di-flip vertikal
            % saat mencari sel terdekat -> hasil IDENTIK dgn POT-PSG4
            % (collectSeriesBatch yg memakai applyOrientation). flipH=0/rot=1
            % default, jadi cukup flipV.

            % --- Sampling semua titik dgn loop frame di LUAR ---------------
            % Data tiap frame (x/y/Z) hanya di-resolve SEKALI di sini, lalu
            % dipakai untuk seluruh titik. Ini menghapus duplikasi n x per
            % frame yg ada di sampleSeries lama (hasil identik, jauh lbh cepat).
            series = pivcore.pot.step1Collect.sampleSeriesBatch( ...
                data, cx, cy, w, hh, src);   % n x nFrames

            for i = 1:n
                si = series(i, :);
                if isempty(si) || all(~isfinite(si))
                    if ~isempty(progressFcn), try, progressFcn(i, n); catch, end, end %#ok<NOSEM,CTCH>
                    continue;
                end
                rec = pivcore.pot.potpsg4Model.recordFromVar( ...
                    struct('data', si, 'label', sprintf('P-%d', i), ...
                           'origin', [cx(i) cy(i)]), 0);
                rec.posPx = ts(i) * L;
                rec.toF   = data.nFrames;
                % Samakan moving-average dgn POT-PSG4 (maWindow=4) agar kurva
                % yang ditampilkan/diagregasi identik (data mentahnya sudah
                % sama; dulu default recordFromVar = 2 -> kurva tampak beda).
                rec.mode     = 'Moving average';
                rec.maWindow = 4;
                recs = pivcore.pot.step1Collect.appendRecord(recs, rec);
                if ~isempty(progressFcn), try, progressFcn(i, n); catch, end, end %#ok<NOSEM,CTCH>
            end
        end


        % ================================================================
        function [bx, by, corners] = bandGeom(p1, p2, spacing, bufferMult)
        %BANDGEOM  Geometri PITA (band) sampling di sekeliling garis PSG p1->p2.
        %   SUMBER-KEBENARAN TUNGGAL geometri band: dipakai oleh collectAlongBand
        %   (engine) DAN preview UI, supaya kotak/titik preview PERSIS = area yang
        %   benar-benar disampel (tak ada drift).
        %
        %   In:
        %     p1,p2      = [x y] ujung garis PSG (koordinat data axMain).
        %     spacing    = jarak antar-titik along-line (px); juga jarak antar-baris
        %                  offset band (biasanya = round(nodeSpacing) grid PIV).
        %     bufferMult = k (>=0). Band = 2k+1 baris pada offset j*spacing
        %                  (j = -k..+k) sepanjang NORMAL garis. k=0 -> 1 baris (garis).
        %   Out:
        %     bx,by   = grid titik band, ukuran n x (2k+1). Kolom = baris-offset
        %               (kolom tengah = di garis). Baris = titik along-line.
        %     corners = 4x2 sudut band [x y] (urut poligon; untuk patch preview).
            p1 = p1(:).'; p2 = p2(:).';
            L  = hypot(p2(1)-p1(1), p2(2)-p1(2));
            k  = 0;
            if nargin >= 4 && isscalar(bufferMult) && isfinite(bufferMult) && bufferMult > 0
                k = round(bufferMult);
            end
            if ~(isfinite(spacing) && spacing > 0), spacing = 10; end
            if ~isfinite(L) || L <= 0
                bx = []; by = []; corners = []; return;
            end
            n  = max(2, floor(L / spacing) + 1);
            ts = linspace(0, 1, n).';                 % n x 1
            cx = p1(1) + ts*(p2(1)-p1(1));            % n x 1 (titik along-line)
            cy = p1(2) + ts*(p2(2)-p1(2));

            % Arah garis (unit) & normal (unit, tegak lurus).
            t   = [p2(1)-p1(1), p2(2)-p1(2)] / L;
            nrm = [-t(2), t(1)];

            jj  = (-k):(k);                            % 1 x (2k+1) offset baris
            ox  = jj * (spacing * nrm(1));             % 1 x (2k+1)
            oy  = jj * (spacing * nrm(2));
            bx  = cx + ox;                             % n x (2k+1) (broadcast)
            by  = cy + oy;

            % Sudut band (poligon): p1/p2 digeser ±k*spacing sepanjang normal.
            d   = k * spacing;
            corners = [ p1 - d*nrm ;
                        p2 - d*nrm ;
                        p2 + d*nrm ;
                        p1 + d*nrm ];
        end


        % ================================================================
        function recs = collectAlongBand(data, p1, p2, spacing, src, bufferMult, progressFcn)
        %COLLECTALONGBAND  Seperti collectAlongLine tetapi MEMPERBANYAK titik: pita
        %   2D (band) di sekeliling garis PSG -> TIAP titik pita = 1 record (kurva)
        %   TERPISAH (TANPA perataan). Ini memperluas cakupan pengamatan (berguna
        %   utk sesar miring) & tiap titik bisa diseleksi/dibersihkan sendiri.
        %
        %   PENOMORAN "seperti garis 1D dengan stride basis-KOLOM" (column-major):
        %   kiri-atas = P-1, ke BAWAH = P-2, P-3, ... (dalam satu kolom), lalu
        %   pindah ke kolom kanan berikutnya KEMBALI ke atas, dst. Persis A(:)
        %   MATLAB dgn baris = atas->bawah, kolom = kiri->kanan.
        %
        %   bufferMult == 0 -> delegasi PERSIS ke collectAlongLine (backward-compat).
        %   bufferMult == k>0 -> 2k+1 baris offset (± k) pada arah normal, jarak
        %   antar-baris = spacing.
            if nargin < 7, progressFcn = []; end
            if nargin < 6, bufferMult  = 0;  end
            if nargin < 5 || isempty(src), src = 'velocity_magnitude'; end

            k = 0;
            if isscalar(bufferMult) && isfinite(bufferMult) && bufferMult > 0
                k = round(bufferMult);
            end
            if k == 0
                recs = pivcore.pot.step1Collect.collectAlongLine( ...
                    data, p1, p2, spacing, src, progressFcn);
                return;
            end

            p1 = p1(:).'; p2 = p2(:).';
            if numel(p1) ~= 2 || numel(p2) ~= 2 ...
                    || any(~isfinite(p1)) || any(~isfinite(p2))
                error('pivcore:step1Collect:badLine', ...
                    'Garis PSG tidak valid (p1/p2 harus [x y] finite).');
            end
            L = hypot(p2(1)-p1(1), p2(2)-p1(2));
            if ~isfinite(L) || L <= 0
                error('pivcore:step1Collect:zeroLine', ...
                    'Panjang garis PSG nol atau tak hingga.');
            end
            if nargin < 4 || isempty(spacing) || ~isfinite(spacing) || spacing <= 0
                spacing = 10;
            end

            recs = pivcore.pot.potpsg4Model.emptyRecordArray();

            % Geometri band (sumber-kebenaran bersama). bx,by = n x (2k+1):
            %   baris = titik along-line (kiri->kanan), kolom = offset normal
            %   (j = -k..+k). Kolom TENGAH (ci) = di garis PSG.
            [bx, by] = pivcore.pot.step1Collect.bandGeom(p1, p2, spacing, k);
            [n, m]   = size(bx);            % n along-line, m = 2k+1 baris band
            ts       = linspace(0, 1, n);
            w = 3; hh = 3;                  % blok 3x3 per titik band (identik lama)
            ci       = (m + 1) / 2;         % indeks kolom tengah (di garis)

            % --- Susun titik dalam URUTAN COLUMN-MAJOR (seperti garis 1D, stride
            %   basis-kolom): tiap "kolom" = 1 posisi along-line (kiri->kanan);
            %   di dalam kolom, ATAS->BAWAH. bandGeom offset j=-k..+k dgn +j = ATAS
            %   layar (YDir normal axMain: cy+ = atas). Jadi ATAS->BAWAH = j turun
            %   +k..-k -> balik urutan kolom-offset. Bangun matriks Gx/Gy dgn
            %   dim-1 = atas->bawah (2k+1), dim-2 = kiri->kanan (n); G(:) = target.
            Gx = flipud(bx.');            % (2k+1) x n : baris1=+k(atas) .. baris(2k+1)=-k(bawah)
            Gy = flipud(by.');            % kolom = along-line kiri->kanan
            ax = Gx(:).';                 % 1 x (n*m) urut column-major (target penomoran)
            ay = Gy(:).';

            % posPx per titik: pakai posPx along-line KOLOM titik itu (identik utk
            % semua baris band dalam kolom yang sama) -> identitas along-line jelas.
            posMat = repmat(ts * L, m, 1);      % (2k+1) x n : tiap kolom = posPx sama
            % (posMat sudah "atas->bawah" konsisten dgn Gx/Gy karena hanya konstan
            %  per kolom; flip tak mengubah nilai kolom.)
            apos = posMat(:).';

            % Sampel SEMUA titik sekaligus (loop frame di luar; reuse penuh,
            % termasuk flip-y konsisten). series = (n*m) x nFrames dalam urutan
            % column-major yg SAMA dgn ax/ay.
            series = pivcore.pot.step1Collect.sampleSeriesBatch( ...
                data, ax, ay, w, hh, src);
            nPts = numel(ax);

            for p = 1:nPts
                si = series(p, :);
                if isempty(si) || all(~isfinite(si))
                    if ~isempty(progressFcn), try, progressFcn(p, nPts); catch, end, end %#ok<NOSEM,CTCH>
                    continue;
                end
                rec = pivcore.pot.potpsg4Model.recordFromVar( ...
                    struct('data', si, 'label', sprintf('P-%d', p), ...
                           'origin', [ax(p) ay(p)]), 0);
                rec.posPx = apos(p);       % posisi along-line kolom titik
                rec.toF   = data.nFrames;
                rec.mode     = 'Moving average';
                rec.maWindow = 4;
                recs = pivcore.pot.step1Collect.appendRecord(recs, rec);
                if ~isempty(progressFcn), try, progressFcn(p, nPts); catch, end, end %#ok<NOSEM,CTCH>
            end
        end


        % ================================================================
        function series = sampleSeriesBatch(data, cx, cy, w, hh, srcName)
        %SAMPLESERIESBATCH  Sampling mean blok w x hh untuk SEMUA titik
        %   (cx,cy vektor 1 x n) atas tiap frame. Frame di-resolve sekali per
        %   frame (bukan sekali per titik), jadi biaya resolve/load turun dari
        %   O(nTitik x nFrame) -> O(nFrame). Hasil per titik identik dgn
        %   sampleSeries lama. TANPA orientasi (konsisten Step-1).
            nF = data.nFrames;
            n  = numel(cx);
            series = nan(n, nF);
            wHalf = floor(w/2);
            hHalf = floor(hh/2);

            for k = 1:nF
                x = pivcore.data.safeFrame(data.x, k);
                y = pivcore.data.safeFrame(data.y, k);
                if isempty(x) || isempty(y), continue; end

                [Z, ~] = pivcore.data.resolveScalar(data, srcName, k);
                [U, V] = pivcore.data.pickAnyVel(data, k);
                if isempty(Z) && ~isempty(U) && ~isempty(V) ...
                        && strcmp(srcName,'velocity_magnitude')
                    Z = hypot(U, V);
                end
                if isempty(Z) || ~isequal(size(Z), size(x)), continue; end

                xrow = x(1,:); ycol = y(:,1);
                % Vertical flip (chkFlipV default ON): cerminkan koordinat y
                % grid agar cocok dgn ruang axMain ter-flip tempat (cx,cy)
                % berada. Indeks BARIS yg ditemukan tetap menunjuk sel data
                % mentah yg benar.
                yMid  = (max(ycol) + min(ycol)) / 2;
                ycolF = 2*yMid - ycol;
                % Indeks kolom/baris terdekat utk SEMUA titik sekaligus.
                [~, icAll] = min(abs(xrow(:) - cx), [], 1);   % 1 x n
                [~, irAll] = min(abs(ycolF(:) - cy), [], 1);

                for i = 1:n
                    ic = icAll(i); ir = irAll(i);
                    ic1 = max(1, ic - wHalf);
                    ic2 = min(size(Z,2), ic + (w - wHalf - 1));
                    ir1 = max(1, ir - hHalf);
                    ir2 = min(size(Z,1), ir + (hh - hHalf - 1));
                    block = Z(ir1:ir2, ic1:ic2);
                    bv = block(isfinite(block));
                    if isempty(bv), continue; end
                    series(i, k) = mean(bv);
                end
            end
        end


        % ================================================================
        function series = sampleSeries(data, cx, cy, w, hh, srcName)
        %SAMPLESERIES  Versi headless dari tabPOT.collectSeries: mean blok
        %   w x hh di titik (cx,cy) untuk tiap bingkai. TANPA orientasi.
            nF = data.nFrames;
            series = nan(1, nF);
            for k = 1:nF
                x = pivcore.data.safeFrame(data.x, k);
                y = pivcore.data.safeFrame(data.y, k);
                if isempty(x) || isempty(y), continue; end

                [Z, ~] = pivcore.data.resolveScalar(data, srcName, k);
                [U, V] = pivcore.data.pickAnyVel(data, k);
                if isempty(Z) && ~isempty(U) && ~isempty(V) ...
                        && strcmp(srcName,'velocity_magnitude')
                    Z = hypot(U, V);
                end
                if isempty(Z) || ~isequal(size(Z), size(x)), continue; end

                xrow = x(1,:); ycol = y(:,1);
                % Vertical flip (chkFlipV default ON) — lihat sampleSeriesBatch.
                yMid  = (max(ycol) + min(ycol)) / 2;
                ycolF = 2*yMid - ycol;
                [~, ic] = min(abs(xrow - cx));
                [~, ir] = min(abs(ycolF - cy));

                wHalf = floor(w/2);
                hHalf = floor(hh/2);
                ic1 = max(1, ic - wHalf);
                ic2 = min(size(Z,2), ic + (w - wHalf - 1));
                ir1 = max(1, ir - hHalf);
                ir2 = min(size(Z,1), ir + (hh - hHalf - 1));

                block = Z(ir1:ir2, ic1:ic2);
                bv = block(isfinite(block));
                if isempty(bv), continue; end
                series(k) = mean(bv);
            end
        end


        % ================================================================
        function recs = appendRecord(recs, rec)
        %APPENDRECORD  Tambah satu record (sudah berfield lengkap) ke array,
        %   menjaga urutan field konsisten (orderfields seperti potpsg4Model).
            rec = pivcore.pot.potpsg4Model.normalizeRecord(rec);
            if isempty(recs)
                recs = orderfields(rec);
            else
                recs(end+1) = orderfields(rec, recs(1)); %#ok<AGROW>
            end
        end

    end
end
