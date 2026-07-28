classdef matpivEdit
%MATPIVEDIT (engine)  Operasi PENYUNTING MAT PIV — dipakai GUI MATPIVEDIT.m.
%
%   Kumpulan pembungkus TIPIS (semua static, murni/headless) yang MENYATUKAN
%   engine yang SUDAH ADA supaya file GUI tetap ramping & bisa di-tes tanpa
%   jendela. TIDAK ada logika ilmiah baru di sini — hanya perekat:
%
%     - backup .bak berlapis  (pola i_makeBackup MATPIVEDIT lama)
%     - buang frame error      -> PIVlab_automasi_dropframes (fisik, in-place)
%     - baca/tulis geometri     -> pivanalyzemat.core.pivGeomIO
%     - baca/tulis masking kotak-> pivanalyzemat.core.maskSidecar (sidecar JSON)
%
%   KONTRAK "hapus frame": PIVlab_automasi_dropframes menyimpan IN-PLACE (menimpa
%   berkas yang sama). Karena user meminta "save MAT PIV baru" TANPA merusak yang
%   lama, dropFrames() DI SINI membuat backup .bak lebih dulu (salinan MAT lama
%   yang utuh), lalu memangkas berkas asli. Jadi ".bak" = arsip versi lama,
%   berkas .mat = versi rapi tanpa frame error. Ireversibel tanpa .bak (sesuai
%   keputusan user: buang benar-benar dari blob).
%
%   Penempatan: PAB/+pivanalyzemat/+core/matpivEdit.m
%   Lihat juga: pivGeomIO, maskSidecar, maskRect, PIVlab_automasi_dropframes.

    methods (Static)

        % ================================================================
        function [bakPath, made] = backup(matFile)
        %BACKUP  Salin <nama>.mat -> <nama>.mat.bak (atau .bak2, .bak3, … bila ada).
        %   Identik i_makeBackup MATPIVEDIT lama; dipindah ke engine agar dipakai
        %   bersama (Simpan geom, buang frame, tombol Backup).
            made = false; bakPath = '';
            matFile = char(matFile);
            if isempty(matFile) || ~isfile(matFile), return; end
            cand = [matFile '.bak'];
            n = 2;
            while isfile(cand)
                cand = sprintf('%s.bak%d', matFile, n);
                n = n + 1;
            end
            [ok, msg] = copyfile(matFile, cand, 'f');
            if ~ok
                error('matpivEdit:backup', 'copyfile gagal: %s', msg);
            end
            bakPath = cand; made = true;
        end

        % ================================================================
        function info = dropFrames(matFile, dropVec, doBackup)
        %DROPFRAMES  Buang frame error (fisik) dari MAT PIV + backup .bak dulu.
        %
        %   info = pivanalyzemat.core.matpivEdit.dropFrames(matFile, dropVec)
        %   info = ...dropFrames(matFile, dropVec, doBackup)   % doBackup default true
        %
        %   dropVec : indeks frame 1-based (terhadap daftar PENUH) yang dibuang.
        %   Mengembalikan struct .nKept .nDrop .nBefore .dropped .bak (path backup).
        %   Bila dropVec kosong -> tak menyentuh berkas (info.nDrop=0, bak='').
            if nargin < 3 || isempty(doBackup), doBackup = true; end
            matFile = char(matFile);
            dropVec = unique(round(double(dropVec(:))));
            dropVec = dropVec(isfinite(dropVec) & dropVec >= 1);

            bakPath = '';
            if ~isempty(dropVec) && doBackup
                [bakPath, ~] = pivanalyzemat.core.matpivEdit.backup(matFile);
            end
            % Engine fisik yang sudah ada (buang dari semua cell + prune GS dedup).
            info = PIVlab_automasi_dropframes(matFile, dropVec);
            info.bak = bakPath;
        end

        % ================================================================
        function g = readGeom(matFile)
        %READGEOM  Baca geometri (X0/X1/Lpos + strain) — passthrough pivGeomIO.
            g = pivanalyzemat.core.pivGeomIO.read(matFile);
        end

        % ================================================================
        function [g, bakPath] = writeGeom(matFile, X0, X1, Lpos, doBackup)
        %WRITEGEOM  Backup .bak (opsional) lalu recompute+append geom ke MAT PIV.
        %   Blob PIV/GS UTUH (pivGeomIO.write hanya -append var geom kecil).
            if nargin < 5 || isempty(doBackup), doBackup = true; end
            bakPath = '';
            if doBackup
                [bakPath, ~] = pivanalyzemat.core.matpivEdit.backup(matFile);
            end
            g = pivanalyzemat.core.pivGeomIO.write(matFile, X0, X1, Lpos, 'matpiv_editor');
        end

        % ================================================================
        function m = readMask(matFile)
        %READMASK  Baca resep masking KOTAK (v1_rect) dari sidecar <nama>_mask.json.
        %   [] bila tak ada. Ter-normalisasi (struct maskRect: enabled/fill/boxes).
            m = pivanalyzemat.core.maskSidecar.read(matFile);
        end

        % ================================================================
        function ok = writeMask(matFile, masking)
        %WRITEMASK  Tulis resep masking KOTAK ke sidecar (instan, MAT tak disentuh).
        %   masking kosong/[] -> hapus sidecar (masking dinonaktifkan total).
            if isempty(masking) || ~pivanalyzemat.core.maskRect.isActive(masking)
                ok = pivanalyzemat.core.maskSidecar.remove(matFile);
                return;
            end
            ok = pivanalyzemat.core.maskSidecar.write(matFile, masking);
        end

        % ================================================================
        function m = maskFromBoxes(boxes, fill, nRef)
        %MASKFROMBOXES  Rakit struct maskRect dari array kotak GUI.
        %
        %   boxes : array struct dgn .rect_first / .rect_last [x y w h]
        %           (.frame_first/.frame_last/.keyframes opsional).
        %   fill  : nilai putih 0..255 (default 255).
        %   nRef  : jumlah frame acuan saat resep dibuat (agar kebal beda nFrames).
        %
        %   Mengembalikan struct ter-normalisasi (enabled otomatis dari isi).
            if nargin < 2 || isempty(fill), fill = 255; end
            if nargin < 3 || isempty(nRef), nRef = 0; end
            raw = struct('enabled', true, 'fill', fill, 'n_ref', nRef, 'boxes', boxes);
            m = pivanalyzemat.core.maskRect.normalize(raw);
        end

        % ================================================================
        function bb = maskBoxAtFrame(box, k, N, W, H, nRef)
        %MASKBOXATFRAME  Bbox [x1 y1 x2 y2] satu kotak pada frame k (utk overlay
        %   preview di axMain). Passthrough maskRect.interpRect. [] bila kosong.
            if nargin < 6, nRef = []; end
            bb = pivanalyzemat.core.maskRect.interpRect(box, k, N, W, H, nRef);
        end

    end
end
