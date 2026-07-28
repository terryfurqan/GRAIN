classdef grainEditExport
%GRAINEDITEXPORT  Penamaan berkas + folder untuk ekspor 1-gambar GRAINEDIT (editor
%   WYSIWYG). BEDA dgn grain5FaultExport (batch per-sesar, folder per-F#): di sini
%   user memproduksi SATU gambar spesifik per klik → 1 PNG/JPEG + 1 sidecar JSON
%   setelan di `<grainRoot>/PABEDIT_export/<exp>/`. Murni/headless (path saja).
%
%   Penempatan: GRAIN/pivcore_lib/+pivcore/+io/grainEditExport.m

    methods (Static)

        % ================================================================
        function r = rootDir(grainRoot)
        %ROOTDIR  Folder induk ekspor: <grainRoot>/PABEDIT_export.
            if nargin < 1 || isempty(grainRoot), grainRoot = pwd; end
            r = fullfile(char(grainRoot), 'PABEDIT_export');
        end


        % ================================================================
        function d = expDir(grainRoot, dataFile)
        %EXPDIR  <root>/<exp> (nama exp = basename .mat, disanitasi).
            [~, base] = fileparts(char(dataFile));
            d = fullfile(pivcore.io.grainEditExport.rootDir(grainRoot), ...
                pivcore.io.grainEditExport.safeName(base));
        end


        % ================================================================
        function nm = fileStem(dataFile, mode, name)
        %FILESTEM  Awalan berkas: "<exp>_<mode>[_<name>]".
        %   mode = 'pot'|'netslip'|'main'; name = nama kustom opsional dari user.
            [~, base] = fileparts(char(dataFile));
            io = pivcore.io.grainEditExport;
            stem = sprintf('%s_%s', io.safeName(base), io.safeName(char(mode)));
            if nargin >= 3 && ~isempty(name)
                stem = sprintf('%s_%s', stem, io.safeName(char(name)));
            end
            nm = stem;
        end


        % ================================================================
        function nm = imageFile(dataFile, mode, name, ext)
        %IMAGEFILE  Nama berkas gambar "<stem>.<ext>" (ext default 'png').
            if nargin < 3, name = ''; end
            if nargin < 4 || isempty(ext), ext = 'png'; end
            ext = regexprep(char(ext), '^\.', '');
            nm = sprintf('%s.%s', pivcore.io.grainEditExport.fileStem(dataFile, mode, name), ext);
        end


        % ================================================================
        function nm = jsonFile(dataFile, mode, name)
        %JSONFILE  Nama sidecar setelan "<stem>.json".
            if nargin < 3, name = ''; end
            nm = sprintf('%s.json', pivcore.io.grainEditExport.fileStem(dataFile, mode, name));
        end


        % ================================================================
        function p = imagePath(grainRoot, dataFile, mode, name, ext)
        %IMAGEPATH  Path penuh gambar (expDir + imageFile).
            if nargin < 4, name = ''; end
            if nargin < 5, ext = 'png'; end
            p = fullfile(pivcore.io.grainEditExport.expDir(grainRoot, dataFile), ...
                pivcore.io.grainEditExport.imageFile(dataFile, mode, name, ext));
        end


        % ================================================================
        function p = jsonPath(grainRoot, dataFile, mode, name)
        %JSONPATH  Path penuh sidecar setelan (expDir + jsonFile).
            if nargin < 4, name = ''; end
            p = fullfile(pivcore.io.grainEditExport.expDir(grainRoot, dataFile), ...
                pivcore.io.grainEditExport.jsonFile(dataFile, mode, name));
        end


        % ================================================================
        function ensureDir(grainRoot, dataFile)
        %ENSUREDIR  Buat folder expDir bila belum ada.
            d = pivcore.io.grainEditExport.expDir(grainRoot, dataFile);
            if ~isfolder(d), mkdir(d); end
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function s = safeName(s)
        %SAFENAME  Sanitasi nama berkas/folder (buang karakter tak aman).
            s = char(s);
            s = regexprep(s, '[^\w\-\.]+', '_');
            s = regexprep(s, '_+', '_');
            s = regexprep(s, '^_|_$', '');
            if isempty(s), s = 'x'; end
        end

    end
end
