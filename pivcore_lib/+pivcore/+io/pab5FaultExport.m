classdef pab5FaultExport
%PAB5FAULTEXPORT  Kanal EXPORT SESAR PAB5 (TAB ⑨) untuk CLCW (Claude Cowork).
%   Alih-alih menceritakan sesar seperti prosa, kita EKSPOR DATANYA: tiap sesar
%   F# yang sudah diidentifikasi -> 1 FOLDER berisi screenshot + JSON, sehingga
%   CLCW cukup MEMBACA folder itu.
%
%   TATA LETAK (folder induk = di dalam PAB/, konsisten pola PABEXPORT):
%     <pabRoot>/PAB5_export/<exp>/F<no>/
%        <exp>_F<no>.json                      metadata + kurva + net-slip + POI
%        <exp>_F<no>_axpot.png                 screenshot AX POT (sesar highlight)
%        <exp>_F<no>_velmag_start.png          AX main velmag @ frame START
%        <exp>_F<no>_velmag_nuc.png            ... NUC
%        <exp>_F<no>_velmag_fsr.png            ... FSR
%        <exp>_F<no>_velmag_end.png            ... END
%        <exp>_F<no>_shear_start.png           AX main shear @ frame START
%        ... (shear nuc/fsr/end)
%     <pabRoot>/PAB5_export/_export_index.json  indeks global (histori ekspor)
%
%   PENAMAAN "F<no>" pakai NOMOR TAMPIL sesar (uiNum) bila ada, else id record.
%   Nomor tampil boleh duplikat -> disambiguasi dgn suffix id internal bila perlu
%   (folderTag). ENGINE INI MURNI/HEADLESS: menentukan path, membangun struct
%   JSON, tulis atomic, purge. Logika GUI (render screenshot, iterasi sesar,
%   highlight) ada di PAB5_temp.m (TAB ⑨).
%
%   POI = 4 frame perkembangan: START · NUC (nukleasi) · FSR (fault surface
%   rupture) · END. Tiap POI -> 1 gambar velmag + 1 gambar shear di AX main.
%
%   API:
%     r    = pivcore.io.pab5FaultExport.rootDir(pabRoot)
%     d    = pivcore.io.pab5FaultExport.expDir(pabRoot, dataFile)
%     tag  = pivcore.io.pab5FaultExport.folderTag(f)         % 'F3' / 'F3_id12'
%     d    = pivcore.io.pab5FaultExport.faultDir(pabRoot, dataFile, f)
%     nm   = pivcore.io.pab5FaultExport.imageFile(dataFile, f, scalar, poi)
%     nm   = pivcore.io.pab5FaultExport.axpotFile(dataFile, f)
%     p    = pivcore.io.pab5FaultExport.jsonPath(pabRoot, dataFile, f)
%     s    = pivcore.io.pab5FaultExport.buildFaultJson(dataFile, f, info)
%     pivcore.io.pab5FaultExport.writeFaultJson(pabRoot, dataFile, f, s)
%     pivcore.io.pab5FaultExport.purgeFault(pabRoot, dataFile, f)
%     pivcore.io.pab5FaultExport.appendIndex(pabRoot, dataFile, f, stamp)
%
%   Penempatan berkas: PAB/pivcore_lib/+pivcore/+io/pab5FaultExport.m

    methods (Static)

        % ================================================================
        function names = poiNames()
        %POINAMES  Urutan kanonik nama POI (untuk penamaan file & JSON).
            names = {'start','nuc','fsr','end'};
        end

        function names = scalarNames()
        %SCALARNAMES  Skalar AX main yang di-screenshot per POI.
            names = {'velmag','shear'};
        end


        % ================================================================
        function r = rootDir(pabRoot)
        %ROOTDIR  Folder induk ekspor sesar: <pabRoot>/PAB5_export.
            if nargin < 1 || isempty(pabRoot), pabRoot = pwd; end
            r = fullfile(char(pabRoot), 'PAB5_export');
        end


        % ================================================================
        function d = expDir(pabRoot, dataFile)
        %EXPDIR  <root>/<exp> (nama exp = basename .mat, disanitasi).
            [~, base] = fileparts(char(dataFile));
            d = fullfile(pivcore.io.pab5FaultExport.rootDir(pabRoot), ...
                pivcore.io.pab5FaultExport.safeName(base));
        end


        % ================================================================
        function tag = folderTag(f)
        %FOLDERTAG  Nama subfolder sesar = "F<uiNum>" BERSIH (nomor tampil). Tak lagi
        %   menyematkan id internal global (dulu "F3_F12" — bikin nama kacau). uiNum
        %   kosong -> fallback id record. Untuk kasus multi-PSG di mana uiNum bisa
        %   duplikat antar-garis, keunikan folder ditangani caller (subfolder per-PSG);
        %   di single-PSG (kasus umum) uiNum sudah unik 1..N.
            num = pivcore.io.pab5FaultExport.uiNumOf(f);
            if isfinite(num)
                tag = sprintf('F%d', round(num));
                return;
            end
            idc = '';
            if isstruct(f) && isfield(f,'id'), idc = char(f.id); end
            if ~isempty(idc)
                tag = pivcore.io.pab5FaultExport.safeName(idc);
            else
                tag = 'F0';
            end
        end


        % ================================================================
        function d = faultDir(pabRoot, dataFile, f)
        %FAULTDIR  <root>/<exp>/<folderTag(f)>/
            d = fullfile(pivcore.io.pab5FaultExport.expDir(pabRoot, dataFile), ...
                pivcore.io.pab5FaultExport.folderTag(f));
        end


        % ================================================================
        function nm = fileStem(dataFile, f)
        %FILESTEM  Awalan berkas: "<exp>_<folderTag>".
            [~, base] = fileparts(char(dataFile));
            nm = sprintf('%s_%s', pivcore.io.pab5FaultExport.safeName(base), ...
                pivcore.io.pab5FaultExport.folderTag(f));
        end


        function nm = imageFile(dataFile, f, scalar, poi)
        %IMAGEFILE  Nama berkas gambar AX main: "<stem>_<scalar>_<poi>.png".
            stem = pivcore.io.pab5FaultExport.fileStem(dataFile, f);
            nm = sprintf('%s_%s_%s.png', stem, ...
                pivcore.io.pab5FaultExport.safeName(scalar), ...
                pivcore.io.pab5FaultExport.safeName(poi));
        end


        function nm = axpotFile(dataFile, f)
        %AXPOTFILE  AX POT screenshot (full span) filename: "<stem>_axpot.png".
            nm = sprintf('%s_axpot.png', pivcore.io.pab5FaultExport.fileStem(dataFile, f));
        end

        function nm = axpotZoomFile(dataFile, f)
        %AXPOTZOOMFILE  AX POT screenshot (zoom 200-frame): "<stem>_axpot_zoom.png".
            nm = sprintf('%s_axpot_zoom.png', pivcore.io.pab5FaultExport.fileStem(dataFile, f));
        end

        function nm = netslipFile(dataFile, f)
        %NETSLIPFILE  Net-slip plot (full span): "<stem>_netslip.png".
            nm = sprintf('%s_netslip.png', pivcore.io.pab5FaultExport.fileStem(dataFile, f));
        end

        function nm = netslipZoomFile(dataFile, f)
        %NETSLIPZOOMFILE  Net-slip plot (zoom 200-frame): "<stem>_netslip_zoom.png".
            nm = sprintf('%s_netslip_zoom.png', pivcore.io.pab5FaultExport.fileStem(dataFile, f));
        end

        function nm = netslipAllFile(dataFile, f)
        %NETSLIPALLFILE  Net-slip SEMUA sesar bertumpuk (full): "<stem>_netslip_all.png".
            nm = sprintf('%s_netslip_all.png', pivcore.io.pab5FaultExport.fileStem(dataFile, f));
        end

        function nm = netslipAllZoomFile(dataFile, f)
        %NETSLIPALLZOOMFILE  Net-slip SEMUA sesar (zoom 200): "<stem>_netslip_all_zoom.png".
            nm = sprintf('%s_netslip_all_zoom.png', pivcore.io.pab5FaultExport.fileStem(dataFile, f));
        end


        function nm = jsonFile(dataFile, f)
        %JSONFILE  Nama berkas JSON: "<stem>.json".
            nm = sprintf('%s.json', pivcore.io.pab5FaultExport.fileStem(dataFile, f));
        end


        function p = jsonPath(pabRoot, dataFile, f)
        %JSONPATH  Path penuh JSON sesar.
            p = fullfile(pivcore.io.pab5FaultExport.faultDir(pabRoot, dataFile, f), ...
                pivcore.io.pab5FaultExport.jsonFile(dataFile, f));
        end


        % ================================================================
        function pct = strainAtFrame(frameK, nF, strainTotalPct)
        %STRAINATFRAME  Cumulative strain % at frame k: (k-1)/(nF-1)*strainTotalPct.
        %   Returns NaN if inputs invalid. Frame 1 -> 0%, frame nF -> strainTotalPct.
            pct = NaN;
            if ~(isscalar(frameK) && isfinite(frameK)), return; end
            if ~(isscalar(strainTotalPct) && isfinite(strainTotalPct)), return; end
            if ~(isscalar(nF) && isfinite(nF)), return; end
            if nF <= 1, pct = strainTotalPct; else, pct = (frameK-1)/(nF-1) * strainTotalPct; end
        end


        % ================================================================
        function s = buildFaultJson(dataFile, f, info)
        %BUILDFAULTJSON  Assemble the CALIBRATED per-fault JSON struct (read by
        %   CLCW). All quantities are stored ALREADY CALIBRATED — NOT in raw
        %   frames/(px per frame):
        %     · POI (start/nuc/fsr/end) -> CUMULATIVE STRAIN PERCENT. The amount
        %       of strain between two events = their percent DIFFERENCE.
        %     · net-slip series & area -> cm/s (px/frame * velMult).
        %   Raw frame numbers are ALSO kept under poiFrame{} for traceability.
        %   f    = fault struct (pivcore.io.pab5Faults) with id/uiNum/hwPosPx/
        %          fwPosPx/nuc/fsr/startF/endF/area/dNet/values/angleDeg.
        %   info = optional context struct (all optional):
        %     .experiment     experiment name (default basename dataFile)
        %     .nFrames        frame count (needed for strain conversion)
        %     .signConvention 'signed'|'absolute'
        %     .spacingPx      PSG node spacing
        %     .strainTotalPct total cumulative strain % (from experiment geometry)
        %     .velMult        multiplier px/frame -> cm/s (default 0.005)
        %     .hwCurveNum     HW curve number (shown in table)
        %     .fwCurveNum     FW curve number
        %     .netslip        net-slip series per-frame in px/frame (override f.values)
        %     .images         struct of relative image paths (axpot + per-poi)
        %     .producedAt     date stamp (caller fills — engine does not clock)
            if nargin < 3 || ~isstruct(info), info = struct(); end
            g = @(k,d) pivcore.io.pab5FaultExport.getf(info, k, d);
            [~, base] = fileparts(char(dataFile));

            nF        = pivcore.io.pab5FaultExport.numScalar(g('nFrames', NaN));
            strainTot = pivcore.io.pab5FaultExport.numScalar(g('strainTotalPct', NaN));
            velMult   = pivcore.io.pab5FaultExport.numScalar(g('velMult', 0.005));
            if ~isfinite(velMult), velMult = 0.005; end

            s = struct();
            s.formatName    = 'PAB5 Fault Export';
            s.formatVersion = 2;                          % v2 = calibrated units
            s.experiment    = char(g('experiment', base));
            s.source        = base;
            % faultId & faultNumber = NOMOR TAMPIL (uiNum) supaya SELALU sinkron &
            % rapi 1..N — tak bocor id internal global lama (mis. F16). id record
            % internal (kunci _faults.json) disimpan terpisah sbg faultKey (jejak).
            uinum = pivcore.io.pab5FaultExport.uiNumOrNull(f);
            if ~isempty(uinum)
                s.faultId = sprintf('F%d', round(uinum));
            else
                s.faultId = pivcore.io.pab5FaultExport.strf(f, 'id', '');
            end
            s.faultNumber   = uinum;
            s.faultKey      = pivcore.io.pab5FaultExport.strf(f, 'id', '');   % id internal (kunci record)
            s.producedAt    = char(g('producedAt', ''));

            % --- units + calibration constants used ---
            s.units = struct('x','cumulative strain (%)', 'netslip','cm/s', ...
                'poi','cumulative strain (%)');
            s.calibration = struct( ...
                'strainTotalPct', pivcore.io.pab5FaultExport.numOrNull(strainTot), ...
                'velMult',        pivcore.io.pab5FaultExport.numOrNull(velMult), ...
                'nFrames',        pivcore.io.pab5FaultExport.numOrNull(nF));
            s.signConvention = char(g('signConvention', 'signed'));
            s.spacingPx      = pivcore.io.pab5FaultExport.numOrNull(g('spacingPx', NaN));

            % --- HW & FW curves (posPx identity + display number) ---
            s.hw = struct( ...
                'posPx',    pivcore.io.pab5FaultExport.fld(f,'hwPosPx'), ...
                'curveNum', pivcore.io.pab5FaultExport.numOrNull(g('hwCurveNum', NaN)));
            s.fw = struct( ...
                'posPx',    pivcore.io.pab5FaultExport.fld(f,'fwPosPx'), ...
                'curveNum', pivcore.io.pab5FaultExport.numOrNull(g('fwCurveNum', NaN)));

            % --- POI as CUMULATIVE STRAIN % (primary) ---
            saf = @(fr) pivcore.io.pab5FaultExport.numOrNull( ...
                pivcore.io.pab5FaultExport.strainAtFrame(fr, nF, strainTot));
            s.poi = struct( ...
                'start', saf(pivcore.io.pab5FaultExport.rawf(f,'startF')), ...
                'nuc',   saf(pivcore.io.pab5FaultExport.rawf(f,'nuc')), ...
                'nucT',  saf(pivcore.io.pab5FaultExport.rawf(f,'nucT')), ...
                'fsr',   saf(pivcore.io.pab5FaultExport.rawf(f,'fsr')), ...
                'fsrT',  saf(pivcore.io.pab5FaultExport.rawf(f,'fsrT')), ...
                'end',   saf(pivcore.io.pab5FaultExport.rawf(f,'endF')));
            % Raw frames kept for traceability.
            s.poiFrame = struct( ...
                'start', pivcore.io.pab5FaultExport.fld(f,'startF'), ...
                'nuc',   pivcore.io.pab5FaultExport.fld(f,'nuc'), ...
                'nucT',  pivcore.io.pab5FaultExport.fld(f,'nucT'), ...
                'fsr',   pivcore.io.pab5FaultExport.fld(f,'fsr'), ...
                'fsrT',  pivcore.io.pab5FaultExport.fld(f,'fsrT'), ...
                'end',   pivcore.io.pab5FaultExport.fld(f,'endF'));

            % --- net-slip series in cm/s (px/frame * velMult) ---
            ns = g('netslip', []);
            if isempty(ns) && isstruct(f) && isfield(f,'values'), ns = f.values; end
            nsCms = pivcore.io.pab5FaultExport.rowv(ns) * velMult;
            s.netslip = nsCms;

            % --- magnitudes (area recomputed on calibrated series over START..END) ---
            % area = ∫ net-slip[cm/s] over START..END in strain% domain? -> keep the
            % engine trapz value scaled by velMult for cm/s-consistency (frame domain).
            areaRaw = pivcore.io.pab5FaultExport.fld(f,'area');
            dNetRaw = pivcore.io.pab5FaultExport.fld(f,'dNet');
            s.area = pivcore.io.pab5FaultExport.scaleOrNull(areaRaw, velMult);   % cm/s * frames
            s.dNet = pivcore.io.pab5FaultExport.scaleOrNull(dNetRaw, velMult);   % cm/s
            s.angleDeg = pivcore.io.pab5FaultExport.fld(f,'angleDeg');           % ° (unchanged)

            % --- image manifest (paths relative to fault folder) ---
            s.images = g('images', struct());
        end


        % ================================================================
        function writeFaultJson(pabRoot, dataFile, f, s)
        %WRITEFAULTJSON  Tulis JSON sesar ke <faultDir>/<jsonFile> (atomic).
        %   Pastikan folder ada dulu.
            d = pivcore.io.pab5FaultExport.faultDir(pabRoot, dataFile, f);
            if ~isfolder(d), mkdir(d); end
            p = fullfile(d, pivcore.io.pab5FaultExport.jsonFile(dataFile, f));
            pivcore.io.pab5FaultExport.writeJsonAtomic(p, s);
        end


        % ================================================================
        function purgeFault(pabRoot, dataFile, f)
        %PURGEFAULT  Hapus TOTAL folder 1 sesar (regenerate bersih). No-op bila
        %   tak ada. IMMUTABLE: PAB5_temp satu-satunya penulis PAB5_export.
            d = pivcore.io.pab5FaultExport.faultDir(pabRoot, dataFile, f);
            if isfolder(d)
                try, rmdir(d, 's'); catch, end
            end
        end


        % ================================================================
        function idx = readIndex(pabRoot)
        %READINDEX  Baca indeks global _export_index.json (-> struct dgn .entries).
            idx = struct('formatName','PAB5 Fault Export Index','formatVersion',1,'entries',{{}});
            p = fullfile(pivcore.io.pab5FaultExport.rootDir(pabRoot), '_export_index.json');
            if ~isfile(p), return; end
            try
                raw = jsondecode(fileread(p));
                if isstruct(raw) && isfield(raw,'entries')
                    idx.entries = pivcore.io.pab5FaultExport.tocell(raw.entries);
                end
            catch
            end
        end


        function appendIndex(pabRoot, dataFile, f, stamp)
        %APPENDINDEX  Catat 1 entri ekspor ke indeks global (histori). Ganti entri
        %   lama untuk (exp,faultTag) yang sama supaya tak menumpuk duplikat.
            if nargin < 4, stamp = ''; end
            r = pivcore.io.pab5FaultExport.rootDir(pabRoot);
            if ~isfolder(r), mkdir(r); end
            idx = pivcore.io.pab5FaultExport.readIndex(pabRoot);
            [~, base] = fileparts(char(dataFile));
            exp = pivcore.io.pab5FaultExport.safeName(base);
            tag = pivcore.io.pab5FaultExport.folderTag(f);
            e = struct('experiment', exp, 'fault', tag, ...
                'faultNumber', pivcore.io.pab5FaultExport.uiNumOrNull(f), ...
                'folder', fullfile(exp, tag), 'producedAt', char(stamp));
            % Buang entri lama (exp,tag) sama.
            keep = {};
            for k = 1:numel(idx.entries)
                ek = idx.entries{k};
                if isstruct(ek) && isfield(ek,'experiment') && isfield(ek,'fault') ...
                        && strcmp(ek.experiment,exp) && strcmp(ek.fault,tag)
                    continue;
                end
                keep{end+1} = ek; %#ok<AGROW>
            end
            keep{end+1} = e;
            idx.entries = keep;
            p = fullfile(r, '_export_index.json');
            pivcore.io.pab5FaultExport.writeJsonAtomic(p, idx);
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function n = uiNumOf(f)
        %UINUMOF  Nomor tampil sesar (uiNum finite, else turunkan dari id "F<n>").
            n = NaN;
            if ~isstruct(f), return; end
            if isfield(f,'uiNum') && isscalar(f.uiNum) && isfinite(f.uiNum)
                n = double(f.uiNum); return;
            end
            if isfield(f,'id')
                t = regexp(char(f.id), '^F(\d+)', 'tokens', 'once');
                if ~isempty(t), n = str2double(t{1}); end
            end
        end

        function v = uiNumOrNull(f)
            n = pivcore.io.pab5FaultExport.uiNumOf(f);
            if isfinite(n), v = round(n); else, v = []; end   % [] -> JSON null
        end

        function v = fld(f, name)
        %FLD  Fault scalar field -> double or [] (JSON null when NaN/absent).
            v = [];
            if isstruct(f) && isfield(f, name) && isscalar(f.(name)) && isfinite(f.(name))
                v = double(f.(name));
            end
        end

        function v = rawf(f, name)
        %RAWF  Fault scalar field -> double or NaN (for numeric conversion input).
            v = NaN;
            if isstruct(f) && isfield(f, name) && isscalar(f.(name)) && isfinite(f.(name))
                v = double(f.(name));
            end
        end

        function v = numScalar(x)
        %NUMSCALAR  Coerce to finite scalar double or NaN.
            if isscalar(x) && isnumeric(x) && isfinite(x), v = double(x); else, v = NaN; end
        end

        function v = scaleOrNull(x, k)
        %SCALEORNULL  x*k as double, or [] (JSON null) if x invalid.
            if isscalar(x) && isnumeric(x) && isfinite(x) && isscalar(k) && isfinite(k)
                v = double(x) * double(k);
            else
                v = [];
            end
        end

        function s = strf(f, name, dflt)
            s = char(dflt);
            if isstruct(f) && isfield(f, name) && ~isempty(f.(name)), s = char(f.(name)); end
        end

        function v = numOrNull(x)
            if isscalar(x) && isnumeric(x) && isfinite(x), v = double(x); else, v = []; end
        end

        function v = rowv(x)
        %ROWV  Deret -> row double; NaN -> null (jsonencode: NaN jadi null otomatis).
            if isempty(x), v = []; return; end
            v = double(x(:)).';
        end

        function nm = safeName(s)
            nm = regexprep(char(s), '[^\w\-\.]+', '_');
            nm = regexprep(nm, '_+', '_');
            nm = regexprep(nm, '^_+|_+$', '');
            if isempty(nm), nm = 'exp'; end
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

        function writeJsonAtomic(p, obj)
            txt = jsonencode(obj, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0, error('pivcore:pab5FaultExport:open','Tak bisa tulis %s', tmp); end
            c = onCleanup(@() pivcore.io.pab5FaultExport.cleanupTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char'); fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok, error('pivcore:pab5FaultExport:move','Gagal pindah %s: %s', p, msg); end
        end

        function cleanupTmp(tmp)
            if isfile(tmp), try, delete(tmp); catch, end, end
        end

    end
end
