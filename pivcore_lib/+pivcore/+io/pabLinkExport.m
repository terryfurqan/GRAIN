classdef pabLinkExport
%PABLINKEXPORT  Ekspor BATCH foto TAMPAK PETA (target) pada frame-frame yang
%   bersesuaian dengan peristiwa FSR di PENAMPANG (acuan). Orkestrasi murni/
%   headless di atas engine yang sudah ada:
%     - kalibrasi strain↔frame  : pivcore.io.pabLink  (frameAtTgt/strainAtRef)
%     - FSR penampang           : pivcore.io.pab5Faults (doc.faults{}.fsr = frame)
%     - render panel PIV        : pivcore.export.frameCatalog (drawScalarPanel)
%     - foto GS asli            : pivcore.data.bgAt + pivcore.util.grayCLAHE
%     - manifest/atomic/hash    : pivcore.io.pabExportCatalog (writeJsonAtomic/…)
%
%   KONTRAK. `_link.json` (di samping MAT peta) tetap SATU-SATUNYA kebenaran
%   korelasi strain↔frame. Engine ini TIDAK menulis `_link.json`; ia hanya
%   MEMBACA kalibrasi + FSR lalu memproduksi FOTO + `manifest_fsr.json` (jejak
%   ekspor: sesar mana → frame peta mana → berkas apa; skip & alasannya).
%
%   PENURUNAN FRAME PETA per sesar (satu-satunya rumus):
%       sFsr    = pabLink.strainAtRef(linkDoc, fault.fsr)   % strain FSR (bertanda)
%       fTgtRaw = pabLink.frameAtTgt(linkDoc, sFsr)          % frame peta (kalibrasi)
%       frameTgt= clamp(round(fTgtRaw), 1, target.nFrames)
%   `ready=false` (skip, tak produksi berkas) bila: fault.fsr NaN, kalibrasi
%   invalid (frameAtTgt NaN), atau frameTgt non-finite. `clamped=true` bila
%   fTgtRaw jatuh di luar [1,nF] (sinyal kalibrasi mungkin perlu di-adjust).
%
%   STRUKTUR FOLDER (di root PAB/, default):
%       PABLINK_export/
%         <refbase>__VS__<tgtbase>/
%           manifest_fsr.json
%           gs/    <tgtbase>_F1_fsr_peta_f061_gs.png   …   % foto GS asli
%           panel/ <tgtbase>_F1_fsr_peta_f061_velmag.jpg
%                  <tgtbase>_F1_fsr_peta_f061_shear.jpg …  % panel PIV
%
%   Penempatan berkas: PAB/pivcore_lib/+pivcore/+io/pabLinkExport.m
%
%   Lihat [[pab5-fault-first]] (FSR penampang), [[pabexport-catalog]] (pola
%   manifest/fingerprint), [[pab-step4-ecosystem]] (renderScalarPanel).

    methods (Static)

        % =============================================================
        % LOKASI & PENAMAAN
        % =============================================================
        function r = rootDir(pabRoot)
        %ROOTDIR  Folder induk ekspor link: <pabRoot>/PABLINK_export.
            if nargin < 1 || isempty(pabRoot), pabRoot = pwd; end
            r = fullfile(char(pabRoot), 'PABLINK_export');
        end

        function nm = pairName(refFile, tgtFile)
        %PAIRNAME  Nama pasangan = <refbase>__VS__<tgtbase> (di-sanitasi).
            [~, rb] = fileparts(char(refFile));
            [~, tb] = fileparts(char(tgtFile));
            sn = @(s) pivcore.io.pabExportCatalog.safeName(s);
            nm = sprintf('%s__VS__%s', sn(rb), sn(tb));
        end

        function d = pairDir(pabRoot, refFile, tgtFile)
        %PAIRDIR  Folder 1 pasangan: PABLINK_export/<pair>/.
            d = fullfile(pivcore.io.pabLinkExport.rootDir(pabRoot), ...
                pivcore.io.pabLinkExport.pairName(refFile, tgtFile));
        end

        function d = gsDir(pabRoot, refFile, tgtFile)
        %GSDIR  Folder foto GS asli: <pair>/gs/.
            d = fullfile(pivcore.io.pabLinkExport.pairDir(pabRoot, refFile, tgtFile), 'gs');
        end

        function d = panelDir(pabRoot, refFile, tgtFile)
        %PANELDIR  Folder panel PIV: <pair>/panel/.
            d = fullfile(pivcore.io.pabLinkExport.pairDir(pabRoot, refFile, tgtFile), 'panel');
        end

        function p = manifestPath(pabRoot, refFile, tgtFile)
        %MANIFESTPATH  Path manifest_fsr.json pasangan.
            p = fullfile(pivcore.io.pabLinkExport.pairDir(pabRoot, refFile, tgtFile), ...
                'manifest_fsr.json');
        end

        function nm = gsFileName(tgtFile, faultId, fTgt)
        %GSFILENAME  <tgtbase>_<F#>_fsr_peta_f###_gs.png.
            [~, tb] = fileparts(char(tgtFile));
            tb = pivcore.io.pabExportCatalog.safeName(tb);
            fid = pivcore.io.pabExportCatalog.safeName(char(faultId));
            nm = sprintf('%s_%s_fsr_peta_%s_gs.png', tb, fid, ...
                pivcore.io.pabLinkExport.frameTag(fTgt));
        end

        function nm = panelFileName(tgtFile, faultId, fTgt, scalarKey)
        %PANELFILENAME  <tgtbase>_<F#>_fsr_peta_f###_<velmag|shear>.jpg.
            [~, tb] = fileparts(char(tgtFile));
            tb = pivcore.io.pabExportCatalog.safeName(tb);
            fid = pivcore.io.pabExportCatalog.safeName(char(faultId));
            sk  = pivcore.io.pabExportCatalog.scalarKey(scalarKey);
            nm = sprintf('%s_%s_fsr_peta_%s_%s.jpg', tb, fid, ...
                pivcore.io.pabLinkExport.frameTag(fTgt), sk);
        end

        % =============================================================
        % PENURUNAN FRAME PETA (rencana ekspor per sesar)
        % =============================================================
        function rows = planRows(linkDoc, faultsDoc)
        %PLANROWS  Untuk tiap sesar → frame peta FSR + status kesiapan. TIDAK
        %   memproduksi berkas. Kembalikan struct-array (baris; kosong bila tak
        %   ada sesar) dgn field:
        %     faultId, fsrRef, strainPct, frameTgt, frameTgtRaw, ready, clamped, reason
            rows = struct('faultId',{}, 'fsrRef',{}, 'strainPct',{}, ...
                'frameTgt',{}, 'frameTgtRaw',{}, 'ready',{}, 'clamped',{}, 'reason',{});
            if ~isstruct(faultsDoc) || ~isfield(faultsDoc,'faults'), return; end
            F = faultsDoc.faults;
            if ~iscell(F), F = pivcore.io.pabLinkExport.tocell(F); end

            calValid = pivcore.io.pabLinkExport.calibValid(linkDoc);
            tgtNF = NaN;
            if isstruct(linkDoc) && isfield(linkDoc,'target') && isstruct(linkDoc.target)
                tgtNF = pivcore.io.pabLinkExport.scal(linkDoc.target.nFrames);
            end

            for k = 1:numel(F)
                f = F{k};
                if ~isstruct(f), continue; end
                fid = ''; if isfield(f,'id'), fid = char(f.id); end
                if isempty(fid), fid = sprintf('F%d', k); end
                fsr = NaN; if isfield(f,'fsr'), fsr = pivcore.io.pabLinkExport.scal(f.fsr); end

                r = struct('faultId',fid, 'fsrRef',fsr, 'strainPct',NaN, ...
                    'frameTgt',NaN, 'frameTgtRaw',NaN, 'ready',false, ...
                    'clamped',false, 'reason','');

                if ~isfinite(fsr)
                    r.reason = 'fsr NaN (belum ditandai di PAB5)';
                    rows(end+1) = r; continue; %#ok<AGROW>
                end
                if ~calValid
                    r.reason = 'kalibrasi invalid (butuh 2 titik ikat)';
                    rows(end+1) = r; continue; %#ok<AGROW>
                end

                sFsr = pivcore.io.pabLink.strainAtRef(linkDoc, fsr);
                r.strainPct = sFsr;
                fRaw = pivcore.io.pabLink.frameAtTgt(linkDoc, sFsr);
                r.frameTgtRaw = fRaw;
                if ~isfinite(fRaw)
                    r.reason = 'frame peta tak terhitung';
                    rows(end+1) = r; continue; %#ok<AGROW>
                end
                [fClamp, wasClamped] = pivcore.io.pabLinkExport.clampFrame(fRaw, tgtNF);
                r.frameTgt = fClamp;
                r.clamped  = wasClamped;
                r.ready    = true;
                if wasClamped, r.reason = 'frame peta di-clamp ke tepi (cek kalibrasi)'; end
                rows(end+1) = r; %#ok<AGROW>
            end
        end

        % =============================================================
        % EKSPOR BATCH
        % =============================================================
        function manifest = exportFSR(pabRoot, refFile, tgtFile, linkDoc, faultsDoc, dataTgtAll, opts)
        %EXPORTFSR  Produksi foto GS + panel velmag/shear tiap sesar READY, lalu
        %   tulis manifest_fsr.json (ATOMIC). `dataTgtAll` = dataset TARGET yang
        %   SUDAH memuat semua bingkai (bg_images) — pemanggil pastikan ensureFull.
        %   opts (struct):
        %     .doGS         (true)  produksi foto GS asli
        %     .doPanel      (true)  produksi panel velmag+shear
        %     .userPrefs    (struct) preferensi render panel (→ specFromResolve)
        %     .dpi          (300)   resolusi panel
        %     .jpegQuality  (95)    kualitas JPEG panel
        %     .producedAt   ('')    stempel tanggal (pemanggil isi — engine tak clock)
        %     .onlyFaultIds ({} = semua) daftar id sesar yg diekspor
        %     .progressFcn  @(i,n,faultId) progres opsional
        %     .resolve      (Rtgt hasil resolveRender; kosong → dihitung di sini)
            if nargin < 7 || ~isstruct(opts), opts = struct(); end
            g = @(f,d) pivcore.io.pabExportCatalog.getf(opts, f, d);
            doGS    = logical(g('doGS', true));
            doPanel = logical(g('doPanel', true));
            up      = g('userPrefs', struct());
            dpi     = g('dpi', 300);
            jq      = g('jpegQuality', 95);
            stamp   = char(g('producedAt', ''));
            only    = g('onlyFaultIds', {});
            prog    = g('progressFcn', []);

            manifest = pivcore.io.pabLinkExport.emptyManifest(refFile, tgtFile);
            manifest.producedAt = stamp;
            manifest.pair       = pivcore.io.pabLinkExport.pairName(refFile, tgtFile);
            manifest.doGS       = doGS;
            manifest.doPanel    = doPanel;
            manifest.dpi        = dpi;
            manifest.jpegQuality= jq;
            manifest = pivcore.io.pabLinkExport.fillSummary(manifest, linkDoc);

            rows = pivcore.io.pabLinkExport.planRows(linkDoc, faultsDoc);
            rows = pivcore.io.pabLinkExport.filterOnly(rows, only);

            % Spec render (untuk fingerprint + panel). Rtgt sekali.
            R = g('resolve', []);
            if (isempty(R) || ~isstruct(R)) && doPanel
                R = pivcore.export.frameCatalog.resolveRender(tgtFile);
            end
            spec = struct();
            if isstruct(R)
                spec = pivcore.export.frameCatalog.specFromResolve(R, up);
            end
            manifest.spec = spec;

            % Siapkan folder hanya bila ada yg diproduksi.
            gsdir = pivcore.io.pabLinkExport.gsDir(pabRoot, refFile, tgtFile);
            pndir = pivcore.io.pabLinkExport.panelDir(pabRoot, refFile, tgtFile);
            anyReady = any([rows.ready]);
            if anyReady && doGS  && ~isfolder(gsdir), mkdir(gsdir); end
            if anyReady && doPanel && ~isfolder(pndir), mkdir(pndir); end

            % Figure reuse untuk panel (offscreen).
            rf = [];
            if anyReady && doPanel
                rf = pivcore.export.frameCatalog.makeRenderFig();
            end
            clean = onCleanup(@() pivcore.io.pabLinkExport.closeFig(rf)); %#ok<NASGU>

            cfg = struct(); dec = struct();
            if doPanel && isstruct(spec) && isfield(spec,'scalars')
                cfg = pivcore.export.frameCatalog.renderCfg(spec);
                dec = pivcore.export.frameCatalog.decOptsFromSpec(spec, up);
            end

            exports = {};
            nReady = sum([rows.ready]);
            iReady = 0;
            for i = 1:numel(rows)
                r = rows(i);
                e = struct('faultId',r.faultId, 'fsrRef',r.fsrRef, ...
                    'strainPct',r.strainPct, 'frameTgt',r.frameTgt, ...
                    'frameTgtRaw',r.frameTgtRaw, ...
                    'skipped',~r.ready, 'clamped',r.clamped, 'reason',r.reason, ...
                    'gsFile','', 'panelVelmag','', 'panelShear','');
                if ~r.ready
                    exports{end+1} = e; %#ok<AGROW>
                    continue;
                end
                iReady = iReady + 1;
                k = r.frameTgt;

                % (a) GS asli.
                if doGS
                    try
                        bg  = pivcore.data.bgAt(dataTgtAll, k);
                        rgb = pivcore.util.grayCLAHE(bg, true, true);
                        if ~isempty(rgb)
                            nm = pivcore.io.pabLinkExport.gsFileName(tgtFile, r.faultId, k);
                            imwrite(rgb, fullfile(gsdir, nm));
                            e.gsFile = fullfile('gs', nm);
                        end
                    catch ME
                        warning('pivcore:pabLinkExport:gs', ...
                            'GS %s f%d gagal: %s', r.faultId, k, ME.message);
                    end
                end

                % (b) panel velmag + shear (strain dari KALIBRASI, override).
                if doPanel && ~isempty(rf)
                    decK = dec; decK.strainPct = r.strainPct; decK.strainShow = true;
                    for scalarKey = {'velmag','shear'}
                        sk = scalarKey{1};
                        try
                            nm = pivcore.io.pabLinkExport.panelFileName(tgtFile, r.faultId, k, sk);
                            file = fullfile(pndir, nm);
                            pivcore.export.frameCatalog.renderToAxes(rf.ax, ...
                                dataTgtAll, k, sk, cfg, R, tgtFile, file, dpi, jq, decK);
                            if strcmp(sk,'velmag'), e.panelVelmag = fullfile('panel', nm);
                            else,                   e.panelShear  = fullfile('panel', nm); end
                        catch ME
                            warning('pivcore:pabLinkExport:panel', ...
                                'Panel %s %s f%d gagal: %s', r.faultId, sk, k, ME.message);
                        end
                    end
                end

                exports{end+1} = e; %#ok<AGROW>
                if ~isempty(prog)
                    try, prog(iReady, nReady, r.faultId); catch, end
                end
            end

            manifest.exports    = exports;
            manifest.nFaults    = numel(rows);
            manifest.nExported  = nReady;
            pivcore.io.pabLinkExport.write(pabRoot, refFile, tgtFile, manifest);
        end

        % =============================================================
        % MANIFEST I/O (delegasi ATOMIC ke pabExportCatalog)
        % =============================================================
        function m = emptyManifest(refFile, tgtFile)
        %EMPTYMANIFEST  Kerangka manifest_fsr.
            [~, rb] = fileparts(char(refFile));
            [~, tb] = fileparts(char(tgtFile));
            m = struct();
            m.formatName    = 'PAB Link FSR Export';
            m.formatVersion = 1;
            m.pair          = pivcore.io.pabLinkExport.pairName(refFile, tgtFile);
            m.reference     = struct('path',char(refFile), 'basename',rb, ...
                'nFrames',NaN, 'strainTotalPct',NaN);
            m.target        = struct('path',char(tgtFile), 'basename',tb, 'nFrames',NaN);
            m.calibration   = struct('valid',false, 'slopePctPerFrame',NaN, ...
                'frame0',NaN, 'strain0',NaN);
            m.producedAt    = '';
            m.doGS          = true;
            m.doPanel       = true;
            m.dpi           = 300;
            m.jpegQuality   = 95;
            m.spec          = struct();
            m.nFaults       = 0;
            m.nExported     = 0;
            m.exports       = {};      % cell of export-struct
        end

        function m = read(pabRoot, refFile, tgtFile)
        %READ  Baca manifest_fsr.json. Tak ada → emptyManifest.
            p = pivcore.io.pabLinkExport.manifestPath(pabRoot, refFile, tgtFile);
            if isempty(p) || ~isfile(p)
                m = pivcore.io.pabLinkExport.emptyManifest(refFile, tgtFile); return;
            end
            try
                m = jsondecode(fileread(p));
            catch ME
                warning('pivcore:pabLinkExport:read', ...
                    'Gagal parse %s (%s); pakai manifest kosong.', p, ME.message);
                m = pivcore.io.pabLinkExport.emptyManifest(refFile, tgtFile);
            end
        end

        function write(pabRoot, refFile, tgtFile, manifest)
        %WRITE  Tulis manifest_fsr.json ATOMIC. Buat folder pair bila perlu.
            d = pivcore.io.pabLinkExport.pairDir(pabRoot, refFile, tgtFile);
            if ~isfolder(d), mkdir(d); end
            p = pivcore.io.pabLinkExport.manifestPath(pabRoot, refFile, tgtFile);
            pivcore.io.pabExportCatalog.writeJsonAtomic(p, manifest);
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function tag = frameTag(f)
        %FRAMETAG  'f###' (zero-pad min 3 digit).
            f = round(pivcore.io.pabLinkExport.scal(f));
            if ~isfinite(f), f = 0; end
            w = max(3, numel(num2str(abs(f))));
            tag = sprintf('f%0*d', w, f);
        end

        function tf = calibValid(linkDoc)
            tf = false;
            if isstruct(linkDoc) && isfield(linkDoc,'calibration') ...
                    && isstruct(linkDoc.calibration) && isfield(linkDoc.calibration,'valid')
                tf = logical(linkDoc.calibration.valid);
            end
        end

        function [fr, clamped] = clampFrame(f, nF)
        %CLAMPFRAME  Bulat + clamp ke [1,nF]. clamped=true bila jatuh di luar.
            clamped = false;
            f  = pivcore.io.pabLinkExport.scal(f);
            fr = round(f);
            if ~isfinite(fr), fr = NaN; return; end
            lo = 1; hi = Inf;
            nF = pivcore.io.pabLinkExport.scal(nF);
            if isfinite(nF) && nF >= 1, hi = nF; end
            if fr < lo, fr = lo; clamped = true; end
            if fr > hi, fr = hi; clamped = true; end
        end

        function m = fillSummary(m, linkDoc)
        %FILLSUMMARY  Salin identitas ref/target + snapshot kalibrasi ke manifest.
            if ~isstruct(linkDoc), return; end
            if isfield(linkDoc,'reference') && isstruct(linkDoc.reference)
                rr = linkDoc.reference;
                m.reference.basename       = pivcore.io.pabLinkExport.strf(rr,'basename',m.reference.basename);
                m.reference.nFrames        = pivcore.io.pabLinkExport.numf(rr,'nFrames');
                m.reference.strainTotalPct = pivcore.io.pabLinkExport.numf(rr,'strainTotalPct');
                m.reference.path           = pivcore.io.pabLinkExport.strf(rr,'path',m.reference.path);
            end
            if isfield(linkDoc,'target') && isstruct(linkDoc.target)
                tt = linkDoc.target;
                m.target.basename = pivcore.io.pabLinkExport.strf(tt,'basename',m.target.basename);
                m.target.nFrames  = pivcore.io.pabLinkExport.numf(tt,'nFrames');
                m.target.path     = pivcore.io.pabLinkExport.strf(tt,'path',m.target.path);
            end
            if isfield(linkDoc,'calibration') && isstruct(linkDoc.calibration)
                cc = linkDoc.calibration;
                m.calibration.valid            = pivcore.io.pabLinkExport.calibValid(linkDoc);
                m.calibration.slopePctPerFrame = pivcore.io.pabLinkExport.numf(cc,'slopePctPerFrame');
                m.calibration.frame0           = pivcore.io.pabLinkExport.numf(cc,'frame0');
                m.calibration.strain0          = pivcore.io.pabLinkExport.numf(cc,'strain0');
            end
        end

        function rows = filterOnly(rows, only)
        %FILTERONLY  Simpan hanya sesar ber-id ∈ only (kosong → semua).
        %   Ratakan nested cell (defensif thd struct('f',{cell}) yang bisa
        %   membungkus id di dalam cell tambahan).
            if isempty(only), return; end
            if ischar(only) || isstring(only), only = {char(only)}; end
            if ~iscell(only), return; end
            flat = {};
            for i = 1:numel(only)
                v = only{i};
                if iscell(v)
                    for j = 1:numel(v), flat{end+1} = char(v{j}); end %#ok<AGROW>
                else
                    flat{end+1} = char(v); %#ok<AGROW>
                end
            end
            if isempty(flat), return; end
            keep = false(1, numel(rows));
            for i = 1:numel(rows)
                keep(i) = any(strcmp(rows(i).faultId, flat));
            end
            rows = rows(keep);
        end

        function closeFig(rf)
            try
                if isstruct(rf) && isfield(rf,'fig') && ishghandle(rf.fig)
                    pivcore.export.frameCatalog.safeClose(rf.fig);
                end
            catch
            end
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

        function v = scal(x)
            if isscalar(x) && isnumeric(x), v = double(x);
            elseif islogical(x) && isscalar(x), v = double(x);
            else, v = NaN; end
        end

        function v = numf(s, f)
            if isstruct(s) && isfield(s, f), v = pivcore.io.pabLinkExport.scal(s.(f));
            else, v = NaN; end
        end

        function v = strf(s, f, d)
            if isstruct(s) && isfield(s, f) && (ischar(s.(f)) || isstring(s.(f)))
                v = char(s.(f));
            else, v = d; end
        end

    end
end
