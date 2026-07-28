classdef pab4DescExport
%PAB4DESCEXPORT  Kanal EXPORT DESKRIPSI PAB4 (tombol ✅ Commit) untuk CLCW.
%   Saat user COMMIT satu garis PSG, kita arsipkan pengamatan-nya sebagai
%   FOLDER ber-VERSI (timestamp) berisi gambar dunia-nyata + JSON interpretasi,
%   sehingga CLCW cukup MEMBACA folder itu untuk membuat laporan MD.
%
%   TATA LETAK (folder induk = di dalam PAB/, konsisten pola PAB5_export):
%     <pabRoot>/PAB4_DESC/<exp>/<ddmmyy-HHMMSS>_<psgName>/
%        <exp>_desc.json                       JSON interpretasi + baris tabel DESC
%        <F#>/                                  satu folder per sesar yg di-mention
%          <exp>_<F#>_frame<k>_axmain_velmag.jpg
%          <exp>_<F#>_frame<k>_axmain_shear.jpg
%          <exp>_<F#>_frame<k>_axpot.jpg
%        _no_fault/                             baris </blank> tanpa F# (bila ada)
%          <exp>_frame<k>_axmain_velmag.jpg ...
%
%   VERSIONING: tiap Commit membuat folder ber-timestamp BARU (IMMUTABLE, tak
%   ditimpa). Timestamp = datestr(now,'ddmmyy-HHMMSS') (pola PABAXPOT). Nama
%   folder menyertakan nama garis PSG supaya tiap garis punya arsipnya sendiri.
%
%   ENGINE INI MURNI/HEADLESS: menentukan path, membangun struct JSON sesi,
%   tulis atomic. Logika GUI (render gambar, iterasi frame) ada di PAB4.m.
%
%   API:
%     r    = pivcore.io.pab4DescExport.rootDir(pabRoot)
%     d    = pivcore.io.pab4DescExport.expDir(pabRoot, dataFile)
%     ts   = pivcore.io.pab4DescExport.stamp()                 % 'ddmmyy-HHMMSS'
%     d    = pivcore.io.pab4DescExport.sessionDir(pabRoot, dataFile, ts, psgName)
%     d    = pivcore.io.pab4DescExport.faultDir(sessDir, fTag)
%     nm   = pivcore.io.pab4DescExport.axmainFile(dataFile, fTag, frame, scalar)
%     nm   = pivcore.io.pab4DescExport.axpotFile(dataFile, fTag, frame)
%     p    = pivcore.io.pab4DescExport.jsonPath(sessDir, dataFile)
%     s    = pivcore.io.pab4DescExport.buildSessionJson(dataFile, info)
%     pivcore.io.pab4DescExport.writeSessionJson(sessDir, dataFile, s)
%     nm   = pivcore.io.pab4DescExport.safeName(s)
%     tag  = pivcore.io.pab4DescExport.faultTag(fNum)          % 'F3' / '_no_fault'
%
%   Penempatan berkas: PAB/pivcore_lib/+pivcore/+io/pab4DescExport.m

    methods (Static)

        function names = scalarNames()
        %SCALARNAMES  Skalar AX main yang diekspor per frame.
            names = {'velmag','shear'};
        end


        % ================================================================
        function r = rootDir(pabRoot)
        %ROOTDIR  Folder induk ekspor: <pabRoot>/PAB4_DESC.
            if nargin < 1 || isempty(pabRoot), pabRoot = pwd; end
            r = fullfile(char(pabRoot), 'PAB4_DESC');
        end


        function d = expDir(pabRoot, dataFile)
        %EXPDIR  <root>/<exp> (nama exp = basename .mat, disanitasi).
            [~, base] = fileparts(char(dataFile));
            d = fullfile(pivcore.io.pab4DescExport.rootDir(pabRoot), ...
                pivcore.io.pab4DescExport.safeName(base));
        end


        function ts = stamp()
        %STAMP  Timestamp folder ekspor 'ddmmyy-HHMMSS' (pola PABAXPOT.m).
            ts = datestr(now, 'ddmmyy-HHMMSS'); %#ok<TNOW1,DATST>
        end


        % ================================================================
        function d = sessionDir(pabRoot, dataFile, ts, psgName)
        %SESSIONDIR  <root>/<exp>/<ts>_<psgName>/ — folder sesi Commit (ber-versi).
            if nargin < 3 || isempty(ts), ts = pivcore.io.pab4DescExport.stamp(); end
            if nargin < 4, psgName = ''; end
            pn = pivcore.io.pab4DescExport.safeName(psgName);
            if isempty(pn), pn = 'PSG'; end
            d = fullfile(pivcore.io.pab4DescExport.expDir(pabRoot, dataFile), ...
                sprintf('%s_%s', pivcore.io.pab4DescExport.safeName(ts), pn));
        end


        % ================================================================
        function tag = faultTag(fNum)
        %FAULTTAG  Nama subfolder sesar. fNum string F# ('F3','F19_F12'); kosong
        %   -> '_no_fault' (baris </blank> tanpa F#).
            s = pivcore.io.pab4DescExport.tostr(fNum);
            s = pivcore.io.pab4DescExport.safeName(s);
            if isempty(s) || strcmpi(s,'exp'), tag = '_no_fault'; else, tag = s; end
        end


        function d = faultDir(sessDir, fTag)
        %FAULTDIR  <sessDir>/<fTag>/
            d = fullfile(char(sessDir), pivcore.io.pab4DescExport.faultTag(fTag));
        end


        % ================================================================
        function nm = axmainFile(dataFile, fTag, frame, scalar)
        %AXMAINFILE  "<exp>_<fTag>_frame<k>_axmain_<scalar>.jpg".
            [~, base] = fileparts(char(dataFile));
            ftg = pivcore.io.pab4DescExport.faultTag(fTag);
            nm = sprintf('%s_%s_frame%d_axmain_%s.jpg', ...
                pivcore.io.pab4DescExport.safeName(base), ftg, round(frame), ...
                pivcore.io.pab4DescExport.safeName(scalar));
        end


        function nm = axpotFile(dataFile, fTag, frame)
        %AXPOTFILE  "<exp>_<fTag>_frame<k>_axpot.jpg".
            [~, base] = fileparts(char(dataFile));
            ftg = pivcore.io.pab4DescExport.faultTag(fTag);
            nm = sprintf('%s_%s_frame%d_axpot.jpg', ...
                pivcore.io.pab4DescExport.safeName(base), ftg, round(frame));
        end


        function nm = axslipFile(dataFile, fTag, frame)
        %AXSLIPFILE  "<exp>_<fTag>_frame<k>_axslip.jpg" (net-slip HW−FW; menyertai
        %   axpot — apa yang diekspor pada AX POT diterapkan juga pada AX SLIP).
            [~, base] = fileparts(char(dataFile));
            ftg = pivcore.io.pab4DescExport.faultTag(fTag);
            nm = sprintf('%s_%s_frame%d_axslip.jpg', ...
                pivcore.io.pab4DescExport.safeName(base), ftg, round(frame));
        end


        function d = movieDir(pabRoot, dataFile, ts, psgName)
        %MOVIEDIR  Folder sesi MP4 (ber-versi): <root>/<exp>/<ts>_<psgName>_mp4/.
        %   Terpisah dari sessionDir Commit supaya video tak tercampur JPG per-sesar.
            if nargin < 3 || isempty(ts), ts = pivcore.io.pab4DescExport.stamp(); end
            if nargin < 4, psgName = ''; end
            pn = pivcore.io.pab4DescExport.safeName(psgName);
            if isempty(pn), pn = 'PSG'; end
            d = fullfile(pivcore.io.pab4DescExport.expDir(pabRoot, dataFile), ...
                sprintf('%s_%s_mp4', pivcore.io.pab4DescExport.safeName(ts), pn));
        end


        function nm = movieFile(dataFile, scalar)
        %MOVIEFILE  "<exp>_axmain_<scalar>.mp4" (velmag / shear).
            [~, base] = fileparts(char(dataFile));
            nm = sprintf('%s_axmain_%s.mp4', ...
                pivcore.io.pab4DescExport.safeName(base), ...
                pivcore.io.pab4DescExport.safeName(scalar));
        end


        function d = framesDir(pabRoot, dataFile, ts, psgName)
        %FRAMESDIR  Folder sesi ekspor GAMBAR per-bingkai (ber-versi):
        %   <root>/<exp>/<ts>_<psgName>_frames/. Terpisah dari mp4/ & commit.
            if nargin < 3 || isempty(ts), ts = pivcore.io.pab4DescExport.stamp(); end
            if nargin < 4, psgName = ''; end
            pn = pivcore.io.pab4DescExport.safeName(psgName);
            if isempty(pn), pn = 'PSG'; end
            d = fullfile(pivcore.io.pab4DescExport.expDir(pabRoot, dataFile), ...
                sprintf('%s_%s_frames', pivcore.io.pab4DescExport.safeName(ts), pn));
        end


        function nm = frameImgFile(dataFile, scalar, k, ext)
        %FRAMEIMGFILE  "<exp>_axmain_<scalar>_f###.<ext>" (velmag / shear).
        %   k di-zero-pad minimal 3 digit.
            if nargin < 4 || isempty(ext), ext = 'jpg'; end
            [~, base] = fileparts(char(dataFile));
            w = max(3, numel(num2str(k)));
            nm = sprintf('%s_axmain_%s_f%0*d.%s', ...
                pivcore.io.pab4DescExport.safeName(base), ...
                pivcore.io.pab4DescExport.safeName(scalar), w, k, ext);
        end


        function nm = jsonFile(dataFile)
        %JSONFILE  "<exp>_desc.json".
            [~, base] = fileparts(char(dataFile));
            nm = sprintf('%s_desc.json', pivcore.io.pab4DescExport.safeName(base));
        end


        function p = jsonPath(sessDir, dataFile)
        %JSONPATH  Path penuh JSON sesi di root sesi.
            p = fullfile(char(sessDir), pivcore.io.pab4DescExport.jsonFile(dataFile));
        end


        % ================================================================
        function s = buildSessionJson(dataFile, info)
        %BUILDSESSIONJSON  Rakit JSON sesi Commit (dibaca CLCW). Berisi konteks
        %   garis PSG + daftar sesar (interpretasi) + baris tabel DESC.
        %   info (opsional):
        %     .experiment     nama exp (default basename)
        %     .psgId          id garis PSG yang di-commit
        %     .psgName        nama garis PSG (untuk folder / judul)
        %     .producedAt     stamp tanggal (caller isi)
        %     .nFrames        jumlah frame
        %     .strainTotalPct total strain kumulatif %
        %     .velMult        multiplier px/frame -> cm/s (dipakai; = velMultUsed)
        %     .calib          struct kalibrasi ruang-waktu diperluas (i_descCalib):
        %                       velMultGeom/velMultUsed/velMultSource/dxCm/dtSec/
        %                       dtSource/indenterMax/refHorizonDeg. Bila ada, isi
        %                       s.calibration; else fallback field lama (velMult).
        %     .faults         cell of per-fault JSON struct (pab5FaultExport.buildFaultJson
        %                       + blok geometry + lifecycle dari PAB4)
        %     .rows           cell of row-struct tabel DESC (pab4Desc)
            if nargin < 2 || ~isstruct(info), info = struct(); end
            g = @(k,d) pivcore.io.pab4DescExport.getf(info, k, d);
            no = @(x) pivcore.io.pab4DescExport.numOrNull(x);
            [~, base] = fileparts(char(dataFile));

            s = struct();
            s.formatName    = 'PAB4 Description Export';
            s.formatVersion = 2;   % v2: calibration diperluas + faults.geometry/lifecycle
            s.experiment    = char(g('experiment', base));
            s.source        = base;
            s.producedAt    = char(g('producedAt', ''));
            s.psgId         = char(g('psgId', ''));
            s.psgName       = char(g('psgName', ''));
            % --- KALIBRASI ruang-waktu (diperluas; ambil dari info.calib bila ada) ---
            velMult = g('velMult', NaN);
            cal = g('calib', []);
            cg  = @(k,d) pivcore.io.pab4DescExport.getf(cal, k, d);
            if isstruct(cal)
                s.calibration = struct( ...
                    'strainTotalPct', no(g('strainTotalPct', NaN)), ...
                    'nFrames',        no(g('nFrames', NaN)), ...
                    'velMultGeom',    no(cg('velMultGeom', NaN)), ...
                    'velMultUsed',    no(cg('velMultUsed', velMult)), ...
                    'velMultSource',  char(cg('velMultSource', 'fallback')), ...
                    'dxCm',           no(cg('dxCm', NaN)), ...
                    'dtSec',          no(cg('dtSec', NaN)), ...
                    'dtSource',       char(cg('dtSource', '')), ...
                    'indenterMax',    no(cg('indenterMax', NaN)), ...
                    'refHorizonDeg',  no(cg('refHorizonDeg', NaN)), ...
                    'velMult',        no(cg('velMultUsed', velMult)));   % alias backward-compat
            else
                % Kompat lama: hanya strainTotalPct/velMult/nFrames.
                s.calibration = struct( ...
                    'strainTotalPct', no(g('strainTotalPct', NaN)), ...
                    'velMult',        no(velMult), ...
                    'nFrames',        no(g('nFrames', NaN)));
            end
            % REFERENSI GEOMETRI (koordinat robust; dari meta _desc.json PAB4):
            % garis ref horizontal (datum kedalaman) + dinding pembatas + base +
            % ketebalan model. Di-passthrough apa adanya bila caller isi info.referenceGeom.
            rg = g('referenceGeom', []);
            if isstruct(rg), s.referenceGeom = rg; end
            % daftar sesar (interpretasi; struct hasil pab5FaultExport.buildFaultJson
            % + blok geometry/lifecycle yg ditempel PAB4)
            s.faults = pivcore.io.pab4DescExport.tocell(g('faults', {}));
            % baris tabel DESC (pengamatan per-frame; row-struct pab4Desc)
            s.rows   = pivcore.io.pab4DescExport.tocell(g('rows', {}));
        end


        function writeSessionJson(sessDir, dataFile, s)
        %WRITESESSIONJSON  Tulis JSON sesi ke <sessDir>/<exp>_desc.json (atomic).
            if ~isfolder(sessDir), mkdir(sessDir); end
            p = pivcore.io.pab4DescExport.jsonPath(sessDir, dataFile);
            pivcore.io.pab4DescExport.writeJsonAtomic(p, s);
        end


        % ================================================================
        %                        HELPER (publik; reusable)
        % ================================================================
        function nm = safeName(s)
            nm = regexprep(char(s), '[^\w\-\.]+', '_');
            nm = regexprep(nm, '_+', '_');
            nm = regexprep(nm, '^_+|_+$', '');
            if isempty(nm), nm = 'exp'; end
        end

        function v = numOrNull(x)
        %NUMORNULL  Skalar finite -> double; else [] (jsonencode -> null).
            if isscalar(x) && isnumeric(x) && isfinite(x), v = double(x); else, v = []; end
        end

        function v = getf(s, f, d)
            if isstruct(s) && isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
        end

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

        function s = tostr(x)
            if isempty(x), s = ''; return; end
            if ischar(x), s = reshape(x, 1, []); return; end
            try, s = char(string(x)); s = reshape(s, 1, []); catch, s = ''; end
        end

        function writeJsonAtomic(p, obj)
            txt = jsonencode(obj, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0, error('pivcore:pab4DescExport:open','Tak bisa tulis %s', tmp); end
            c = onCleanup(@() pivcore.io.pab4DescExport.cleanupTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char'); fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok, error('pivcore:pab4DescExport:move','Gagal pindah %s: %s', p, msg); end
        end

        function cleanupTmp(tmp)
            if isfile(tmp), try, delete(tmp); catch, end, end
        end

    end
end
