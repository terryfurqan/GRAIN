classdef grain5PsgExport
%GRAIN5PSGEXPORT  Kanal EXPORT "L-GRID PSG" GRAIN5 (garis PSG acuan L1 + N garis di
%   bawahnya). Tujuan: MEMBUKTIKAN bahwa sampling PSG dekat permukaan memberi
%   informasi paling kaya & termudah diinterpretasi tanpa bias — dengan mengekspor
%   plot AXPOT tiap garis L1..Ln (dalam SATUAN DUNIA NYATA: X = cumulative strain %,
%   Y = cm/s, mengikuti aturan TAB ⑨).
%
%   TATA LETAK (folder induk = di dalam GRAIN/, konsisten pola grain5FaultExport):
%     <grainRoot>/PAB5_export/<exp>/PSG_LGRID/
%        <exp>_LGRID_axmain.png        AX main + garis L1..Ln (berlabel) oranye
%        <exp>_L1_axpot.png            AXPOT garis L1 (acuan, paling atas)
%        <exp>_L2_axpot.png            AXPOT garis L2 (di bawah L1)
%        ...
%        <exp>_Ln_axpot.png            AXPOT garis Ln (paling bawah)
%
%   ENGINE INI MURNI/HEADLESS: hanya menentukan PATH folder & nama berkas. Semua
%   logika GUI (buat garis temporer, sampling buffer-OFF, replikasi hapus/clean
%   plot L1 -> Ln, screenshot terkalibrasi copyobj+remap) ada di GRAIN5_temp.m.
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivcore/+io/grain5PsgExport.m

    methods (Static)

        % ================================================================
        function r = rootDir(grainRoot)
        %ROOTDIR  Folder induk ekspor: <grainRoot>/PAB5_export (SAMA dgn ekspor sesar).
            if nargin < 1 || isempty(grainRoot), grainRoot = pwd; end
            r = fullfile(char(grainRoot), 'PAB5_export');
        end


        % ================================================================
        function d = expDir(grainRoot, dataFile)
        %EXPDIR  <root>/<exp> (nama exp = basename .mat, disanitasi).
            [~, base] = fileparts(char(dataFile));
            d = fullfile(pivcore.io.grain5PsgExport.rootDir(grainRoot), ...
                pivcore.io.grain5PsgExport.safeName(base));
        end


        % ================================================================
        function d = lgridDir(grainRoot, dataFile)
        %LGRIDDIR  <root>/<exp>/PSG_LGRID/  (1 folder utk seluruh L-grid).
            d = fullfile(pivcore.io.grain5PsgExport.expDir(grainRoot, dataFile), 'PSG_LGRID');
        end


        % ================================================================
        function stem = fileStem(dataFile)
        %FILESTEM  Awalan berkas = "<exp>".
            [~, base] = fileparts(char(dataFile));
            stem = pivcore.io.grain5PsgExport.safeName(base);
        end


        % ================================================================
        function nm = axMainFile(dataFile)
        %AXMAINFILE  Nama file AX main gabungan (garis L1..Ln).
            nm = sprintf('%s_LGRID_axmain.png', pivcore.io.grain5PsgExport.fileStem(dataFile));
        end


        % ================================================================
        function nm = axpotFile(dataFile, i)
        %AXPOTFILE  Nama file AXPOT garis ke-i (1-based). L1 = acuan (paling atas).
            i = max(1, round(pivcore.io.grain5PsgExport.numScalar(i)));
            nm = sprintf('%s_L%d_axpot.png', pivcore.io.grain5PsgExport.fileStem(dataFile), i);
        end


        % ================================================================
        function purge(grainRoot, dataFile)
        %PURGE  Hapus TOTAL folder PSG_LGRID (regenerate bersih). No-op bila tak ada.
            d = pivcore.io.grain5PsgExport.lgridDir(grainRoot, dataFile);
            if isfolder(d)
                try, rmdir(d, 's'); catch, end
            end
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function v = numScalar(x)
            if isscalar(x) && isnumeric(x) && isfinite(x), v = double(x); else, v = 1; end
        end

        function nm = safeName(s)
            nm = regexprep(char(s), '[^\w\-\.]+', '_');
            nm = regexprep(nm, '_+', '_');
            nm = regexprep(nm, '^_+|_+$', '');
            if isempty(nm), nm = 'exp'; end
        end

    end
end
