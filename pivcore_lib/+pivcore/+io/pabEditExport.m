classdef pabEditExport
%PABEDITEXPORT  Penamaan berkas + folder untuk ekspor 1-gambar PABEDIT (editor
%   WYSIWYG). BEDA dgn pab5FaultExport (batch per-sesar, folder per-F#): di sini
%   user memproduksi SATU gambar spesifik per klik → 1 PNG/JPEG + 1 sidecar JSON
%   setelan di `<pabRoot>/PABEDIT_export/<exp>/`. Murni/headless (path saja).
%
%   Penempatan: PAB/pivcore_lib/+pivcore/+io/pabEditExport.m

    methods (Static)

        % ================================================================
        function r = rootDir(pabRoot)
        %ROOTDIR  Folder induk ekspor: <pabRoot>/PABEDIT_export.
            if nargin < 1 || isempty(pabRoot), pabRoot = pwd; end
            r = fullfile(char(pabRoot), 'PABEDIT_export');
        end


        % ================================================================
        function d = expDir(pabRoot, dataFile)
        %EXPDIR  <root>/<exp> (nama exp = basename .mat, disanitasi).
            [~, base] = fileparts(char(dataFile));
            d = fullfile(pivcore.io.pabEditExport.rootDir(pabRoot), ...
                pivcore.io.pabEditExport.safeName(base));
        end


        % ================================================================
        function nm = fileStem(dataFile, mode, name)
        %FILESTEM  Awalan berkas: "<exp>_<mode>[_<name>]".
        %   mode = 'pot'|'netslip'|'main'; name = nama kustom opsional dari user.
            [~, base] = fileparts(char(dataFile));
            io = pivcore.io.pabEditExport;
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
            nm = sprintf('%s.%s', pivcore.io.pabEditExport.fileStem(dataFile, mode, name), ext);
        end


        % ================================================================
        function nm = jsonFile(dataFile, mode, name)
        %JSONFILE  Nama sidecar setelan "<stem>.json".
            if nargin < 3, name = ''; end
            nm = sprintf('%s.json', pivcore.io.pabEditExport.fileStem(dataFile, mode, name));
        end


        % ================================================================
        function p = imagePath(pabRoot, dataFile, mode, name, ext)
        %IMAGEPATH  Path penuh gambar (expDir + imageFile).
            if nargin < 4, name = ''; end
            if nargin < 5, ext = 'png'; end
            p = fullfile(pivcore.io.pabEditExport.expDir(pabRoot, dataFile), ...
                pivcore.io.pabEditExport.imageFile(dataFile, mode, name, ext));
        end


        % ================================================================
        function p = jsonPath(pabRoot, dataFile, mode, name)
        %JSONPATH  Path penuh sidecar setelan (expDir + jsonFile).
            if nargin < 4, name = ''; end
            p = fullfile(pivcore.io.pabEditExport.expDir(pabRoot, dataFile), ...
                pivcore.io.pabEditExport.jsonFile(dataFile, mode, name));
        end


        % ================================================================
        function ensureDir(pabRoot, dataFile)
        %ENSUREDIR  Buat folder expDir bila belum ada.
            d = pivcore.io.pabEditExport.expDir(pabRoot, dataFile);
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
