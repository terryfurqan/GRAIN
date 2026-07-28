classdef frameCatalog
%FRAMECATALOG  Render BATCH gambar AX main (velmag/shear) SEMUA bingkai sebuah
%   eksperimen ke katalog JPEG (PAB Exporter). HEADLESS: pakai figure OFFSCREEN
%   (Visible='off'), tak mengganggu GUI hidup.
%
%   Berbeda dari PAB3 (viewer efemeral 1-tatapan): di sini SEMUA bingkai x 2
%   skalar dirender ke disk -> arsip tetap, ter-katalog (manifest), sumber
%   montase siap-pakai (tak render ulang). Renderer = pivcore.montage.
%   renderScalarPanel (IDENTIK PAB3/PAB4 -> gambar konsisten).
%
%   ALUR per-eksperimen:
%     1. resolveRender(dataFile) -> tentukan garis PSG + CLim:
%          - _potdata.json PAB4 (garis terkunci + CLim) bila ada -> psgSource
%            'potdata'; else _autopot PAB3a (loadLine) -> 'autopot'; else
%            autoPSG 75% dari atas -> 'auto'. CLim |V| dari indenter-max (envelope
%            kurva POT) dibulatkan ke 0.5 (sama PAB3); CLim shear default.
%     2. renderExperiment(...) -> loadAllFrames + loop bingkai -> JPEG +
%        manifest + indeks global.
%
%   Argumen DPI & jpegQuality dari pemanggil (paper-grade; user atur DPI).
%
%   Lihat [[pab-step4-ecosystem]] (renderScalarPanel, indenter), [[pab-step3-preview]].

    methods (Static)

        % =============================================================
        function R = resolveRender(dataFile)
        %RESOLVERENDER  Turunkan setelan render (garis PSG + CLim) untuk 1 exp,
        %   TANPA GUI. R = struct: line(p1/p2/frac), psgSource, climVel, shearAbs,
        %   spacing, nFrames, indenterMax. Sumber garis PSG (prioritas):
        %     (1) _potdata.json PAB4 garis pertama, (2) _autopot PAB3a loadLine,
        %     (3) autoPSG 75% dari atas (butuh extent bingkai-1).
            R = struct('line',[], 'psgSource','auto', ...
                'climVel',[0 5], 'shearAbs',0.05, 'spacing',NaN, ...
                'nFrames',1, 'indenterMax',NaN, ...
                'strainTotalPct',NaN, 'cmPerPx',NaN, 'dtSec',NaN, 'dxCm',NaN, ...
                'velMultAuto',NaN, 'velMultCal',NaN, 'velMultGeom',NaN);
            cD = pivcore.util.climDefaults();
            R.shearAbs = cD.shearAbs;

            % --- geometri (strain % + cm/px best-effort + |X0-X1| cm) + dt EXIF ---
            [R.strainTotalPct, R.cmPerPx, R.dxCm] = pivcore.export.frameCatalog.readGeom(dataFile);
            R.dtSec = pivcore.export.frameCatalog.readExifDt(dataFile);
            % velMult OPSI 2 (calxy): cm/px ÷ dt. velMultGeom (opsi 3) dihitung
            % SETELAH indenterMax tersedia (butuh |V| indenter px/frame).
            if isfinite(R.cmPerPx) && isfinite(R.dtSec) && R.dtSec > 0
                R.velMultCal = R.cmPerPx / R.dtSec;
            end
            R.velMultAuto = R.velMultCal;   % kompat (auto = jalur calxy)

            % --- extent bingkai-1 (untuk autoPSG fallback & spacing) ---
            data1 = pivcore.io.step1Session.loadFrame1(dataFile);
            x = pivcore.data.safeFrame(data1.x, 1);
            y = pivcore.data.safeFrame(data1.y, 1);
            if isempty(x) || isempty(y)
                error('pivcore:frameCatalog:noFrame','Bingkai-1 kosong: %s', dataFile);
            end
            xExt = [min(x(:)) max(x(:))];
            yExt = [min(y(:)) max(y(:))];

            % --- spacing node (untuk sampling POT) ---
            sp = pivcore.io.step1Session.savedSpacing(dataFile);
            if ~(isscalar(sp) && isfinite(sp) && sp > 0)
                dd = pivcore.data.nodeSpacing(data1);
                if isfinite(dd) && dd > 0, sp = round(dd); else, sp = 10; end
            end
            R.spacing = sp;

            % --- garis PSG: prioritas potdata -> autopot -> autoPSG ---
            line = []; src = 'auto';
            ln = pivcore.export.frameCatalog.lineFromPotData(dataFile);
            if ~isempty(ln), line = ln; src = 'potdata';
            else
                la = pivcore.io.step1Session.loadLine(dataFile);
                if ~isempty(la) && isfield(la,'p1') && isfield(la,'p2')
                    line = struct('p1', la.p1(:).', 'p2', la.p2(:).', 'frac', NaN);
                    src = 'autopot';
                end
            end
            if isempty(line)
                frac = 0.75;
                yL = yExt(2) - frac*(yExt(2)-yExt(1));   % 75% dari ATAS (YDir normal)
                line = struct('p1',[xExt(1) yL], 'p2',[xExt(2) yL], 'frac',frac);
                src = 'auto';
            end
            R.line = line; R.psgSource = src;

            % --- CLim |V| dari indenter-max (envelope kurva POT sepanjang garis) ---
            % Sampling POT seluruh bingkai -> envelope MAX (sama dgn PAB3/PAB4).
            indMax = NaN;
            try
                dataAll = pivcore.io.step1Session.loadAllFrames(dataFile);
                R.nFrames = pivcore.data.frameCount(dataAll);
                recs = pivcore.pot.step1Collect.collectAlongLine( ...
                    dataAll, line.p1, line.p2, sp, 'velocity_magnitude');
                recs = pivcore.pot.records.normalize(recs);
                env  = pivcore.export.frameCatalog.indenterEnvelope(recs, R.nFrames);
                if ~isempty(env)
                    indMax = max(env(isfinite(env)));
                end
            catch ME
                warning('pivcore:frameCatalog:potFail', ...
                    'Sampling POT gagal (%s); CLim |V| pakai default.', ME.message);
                R.nFrames = pivcore.data.frameCount(data1);
            end
            R.indenterMax = indMax;

            % --- velMult OPSI 3 (geometri): kalibrasi via INDENTER ---
            %   kec. fisik indenter = |X0-X1| cm / ((nF-1)*dt) cm/s
            %   |V| indenter terukur = indenterMax px/frame (puncak kurva POT)
            %   multiplier (cm/s per px/frame) = kec.fisik / |V| indenter
            if isfinite(R.dxCm) && R.dxCm > 0 && isfinite(R.dtSec) && R.dtSec > 0 ...
                    && R.nFrames > 1 && isfinite(indMax) && indMax > 0
                vIndCmS = R.dxCm / ((R.nFrames-1) * R.dtSec);   % cm/s
                R.velMultGeom = vIndCmS / indMax;               % cm/s per (px/frame)
            end

            climVel = cD.velCLim;
            if isfinite(indMax) && indMax > 0
                hi = pivcore.util.snapClim(indMax, 0.5, 'ceil');  % bulat ATAS (tak potong puncak)
                if hi > 0, climVel = [0 hi]; end
            end
            R.climVel = climVel;
        end

        % =============================================================
        function spec = specFromResolve(R, userPrefs)
        %SPECFROMRESOLVE  Gabung hasil resolveRender + preferensi user (scalars,
        %   glyph/gs toggle) -> spec katalog (pivcore.io.pabExportCatalog.specStruct).
            if nargin < 2 || ~isstruct(userPrefs), userPrefs = struct(); end
            g = @(f,d) pivcore.io.pabExportCatalog.getf(userPrefs, f, d);
            p = struct();
            p.scalars    = g('scalars', {{'velmag','shear'}});
            p.climVel    = R.climVel;
            p.shearAbs   = R.shearAbs;
            p.psgSource  = R.psgSource;
            if ~isempty(R.line)
                p.psgP1 = R.line.p1; p.psgP2 = R.line.p2;
            end
            p.gsOn       = g('gsOn', true);
            p.claheOn    = g('claheOn', true);
            p.adjOn      = g('adjOn', true);
            p.gsAlpha    = g('gsAlpha', 0.5);
            p.glyphOn    = g('glyphOn', true);
            p.glyphLW    = g('glyphLW', 1);
            p.glyphSp    = g('glyphSp', 3);
            p.glyphColor = g('glyphColor', [0 0 0]);
            p.glyphColorShear = g('glyphColorShear', [NaN NaN NaN]);
            p.tickPx     = g('tickPx', true);
            p.velUnit    = g('velUnit', 'pxframe');
            p.velMult    = g('velMult', 1);
            p.strainShow = g('strainShow', true);
            p.strainPos  = g('strainPos', [0.02 0.04]);
            p.strainColor= g('strainColor', [0 0 0]);
            p.strainBg   = g('strainBg', [1 1 1]);
            spec = pivcore.io.pabExportCatalog.specStruct(p);
        end

        % =============================================================
        function manifest = renderExperiment(pabRoot, dataFile, opts)
        %RENDEREXPERIMENT  Render SEMUA bingkai (skalar di spec) -> JPEG + manifest.
        %   opts (struct):
        %     .dpi          resolusi (default 300)
        %     .jpegQuality  kualitas JPEG 1..100 (default 95)
        %     .userPrefs    preferensi spec (scalars/glyph/gs); -> specFromResolve
        %     .producedAt   stempel tanggal (string; pemanggil isi — engine tak clock)
        %     .purge        true (default) -> HAPUS folder dulu (regenerate bersih)
        %     .progressFcn  @(k,n,scalar) progres opsional
        %     .resolve      hasil resolveRender (opsional; bila kosong dihitung di sini)
        %   Mengembalikan manifest yang ditulis.
            if nargin < 3 || ~isstruct(opts), opts = struct(); end
            g = @(f,d) pivcore.io.pabExportCatalog.getf(opts, f, d);
            dpi   = g('dpi', 300);
            jq    = g('jpegQuality', 95);
            up    = g('userPrefs', struct());
            stamp = g('producedAt', '');
            doPurge = g('purge', true);
            prog  = g('progressFcn', []);

            R = g('resolve', []);
            if isempty(R) || ~isstruct(R)
                R = pivcore.export.frameCatalog.resolveRender(dataFile);
            end
            spec = pivcore.export.frameCatalog.specFromResolve(R, up);

            % Regenerate BERSIH: buang berkas lama (setelan lama) lebih dulu.
            if doPurge
                pivcore.io.pabExportCatalog.purgeExp(pabRoot, dataFile);
            end

            % Muat SEMUA bingkai (sekali) untuk loop render.
            dataAll = pivcore.io.step1Session.loadAllFrames(dataFile);
            nF = pivcore.data.frameCount(dataAll);
            if nF < 1, nF = 1; end

            % cfg renderer (sama struktur cfg yg dipakai renderScalarPanel).
            cfg = pivcore.export.frameCatalog.renderCfg(spec);

            % Opsi DEKORASI dari SPEC (single source) -> renderFrameToFile;
            % gambar arsip = persis preview kanvas (drawScalarPanel sama).
            decOpts = pivcore.export.frameCatalog.decOptsFromSpec(spec, up);
            % Batas sisi-panjang piksel (cegah file raksasa / Mac hang). 0 atau
            % kosong -> tak dibatasi (NaN).
            mlp = g('maxLongPx', 2000);
            if ~(isscalar(mlp) && isfinite(mlp) && mlp > 0), mlp = NaN; end
            decOpts.maxLongPx = mlp;

            manifest = pivcore.io.pabExportCatalog.emptyManifest(dataFile, nF);
            manifest.producedAt  = char(stamp);
            manifest.dpi         = dpi;
            manifest.jpegQuality = jq;
            manifest.spec        = spec;
            manifest.scalars     = struct();

            % --- bangun DAFTAR TUGAS datar (scalar,k,file) + siapkan folder ---
            keys = cell(1, numel(spec.scalars));
            for s = 1:numel(spec.scalars)
                keys{s} = pivcore.io.pabExportCatalog.scalarKey(spec.scalars{s});
                sdir = pivcore.io.pabExportCatalog.scalarDir(pabRoot, dataFile, spec.scalars{s});
                if ~isfolder(sdir), mkdir(sdir); end
            end
            nTask = numel(keys) * nF;
            taskKey  = cell(1, nTask);   % scalar key per tugas
            taskK    = zeros(1, nTask);  % frame
            taskFile = cell(1, nTask);   % path output
            taskName = cell(1, nTask);   % nama berkas (utk manifest)
            t = 0;
            for s = 1:numel(keys)
                sdir = pivcore.io.pabExportCatalog.scalarDir(pabRoot, dataFile, spec.scalars{s});
                for k = 1:nF
                    t = t+1;
                    fn = pivcore.io.pabExportCatalog.frameFile(dataFile, keys{s}, k, 'jpg');
                    taskKey{t}=keys{s}; taskK(t)=k;
                    taskFile{t}=fullfile(sdir, fn); taskName{t}=fn;
                end
            end

            % --- gate paralel: PCT ada + cukup tugas + tak dipaksa serial ---
            maxW = g('maxWorkers', 5);   % default 5 (user: biar tak berat)
            usedParallel = false;
            cnt = 0;                     % penghitung progress paralel (klien)
            usePar = pivcore.export.frameCatalog.canParallel(nTask, opts);
            if usePar
                try
                    pivcore.export.frameCatalog.ensurePool(maxW);
                    dq = parallel.pool.DataQueue;
                    afterEach(dq, @(kk) i_tick(kk));   % jalan di KLIEN
                    parfor (t = 1:nTask, maxW)
                        pivcore.export.frameCatalog.renderOneReuse( ...
                            dataAll, taskK(t), taskKey{t}, cfg, R, dataFile, ...
                            taskFile{t}, dpi, jq, decOpts);
                        send(dq, t);
                    end
                    usedParallel = true;
                catch ME
                    warning('pivcore:frameCatalog:parfor', ...
                        'Paralel gagal (%s) — jatuh ke serial.', ME.message);
                end
            end
            if ~usedParallel
                % SERIAL tapi REUSE 1 figure (2.6x lebih cepat dari figure/frame).
                % Cek BATAL tiap frame (cancelFcn dari GUI) -> bisa dihentikan.
                cancelFcn = g('cancelFcn', []);
                rf = pivcore.export.frameCatalog.makeRenderFig();
                clean = onCleanup(@() pivcore.export.frameCatalog.safeClose(rf.fig)); %#ok<NASGU>
                manifest.aborted = false;
                for t = 1:nTask
                    if ~isempty(cancelFcn)
                        stop = false; try, stop = logical(cancelFcn()); catch, end
                        if stop, manifest.aborted = true; break; end
                    end
                    pivcore.export.frameCatalog.renderToAxes(rf.ax, ...
                        dataAll, taskK(t), taskKey{t}, cfg, R, dataFile, ...
                        taskFile{t}, dpi, jq, decOpts);
                    if ~isempty(prog), try, prog(taskK(t), nF, taskKey{t}); catch, end, end
                end
            end

            % --- susun manifest per-skalar ---
            for s = 1:numel(keys)
                files = cell(1, nF);
                for k = 1:nF
                    files{k} = pivcore.io.pabExportCatalog.frameFile(dataFile, keys{s}, k, 'jpg');
                end
                manifest.scalars.(keys{s}) = struct('dir', keys{s}, 'count', nF, 'files', {files});
            end

            pivcore.io.pabExportCatalog.write(pabRoot, dataFile, manifest);
            pivcore.io.pabExportCatalog.rebuildIndex(pabRoot);

            % progress tick (nested) — laporkan KE KLIEN saat send() dari worker.
            function i_tick(~)
                cnt = cnt + 1; %#ok<*AGROW>
                if ~isempty(prog), try, prog(cnt, nTask, 'paralel'); catch, end, end
            end
        end

        % =============================================================
        function file = previewFrame(pabRoot, dataFile, k, scalar, opts)
        %PREVIEWFRAME  Render SATU bingkai (skalar) ke PAB_export/_preview/ untuk
        %   TES sebelum export semua. BUKAN katalog resmi (tak ada manifest/indeks
        %   /purge). Pakai resolve+spec yang SAMA dgn export -> hasil representatif.
        %   opts: dpi/jpegQuality/userPrefs/resolve/dataAll (opsional). Mengembalikan
        %   path JPEG yang ditulis.
            if nargin < 5 || ~isstruct(opts), opts = struct(); end
            g = @(f,d) pivcore.io.pabExportCatalog.getf(opts, f, d);
            dpi = g('dpi', 300); jq = g('jpegQuality', 95);
            up  = g('userPrefs', struct());
            R   = g('resolve', []);
            if isempty(R) || ~isstruct(R)
                R = pivcore.export.frameCatalog.resolveRender(dataFile);
            end
            dataAll = g('dataAll', []);
            if isempty(dataAll)
                dataAll = pivcore.io.step1Session.loadAllFrames(dataFile);
            end
            nF = pivcore.data.frameCount(dataAll); if nF<1, nF=1; end
            k = max(1, min(round(k), nF));
            spec = pivcore.export.frameCatalog.specFromResolve(R, up);
            cfg  = pivcore.export.frameCatalog.renderCfg(spec);
            decOpts = pivcore.export.frameCatalog.decOptsFromSpec(spec, up);
            key = pivcore.io.pabExportCatalog.scalarKey(scalar);
            pdir = pivcore.io.pabExportCatalog.previewDir(pabRoot);
            if ~isfolder(pdir), mkdir(pdir); end
            fn = pivcore.io.pabExportCatalog.frameFile(dataFile, key, k, 'jpg');
            file = fullfile(pdir, ['PREVIEW_' fn]);
            pivcore.export.frameCatalog.renderFrameToFile( ...
                dataAll, k, key, cfg, R, dataFile, file, dpi, jq, decOpts);
        end

        % =============================================================
        function files = exportSingleFrame(pabRoot, dataFile, k, opts)
        %EXPORTSINGLEFRAME  Render SATU bingkai untuk KEDUA skalar (velmag+shear)
        %   ke PAB_export/<exp>/_frame/ — berkas nyata (bukan preview). Memakai
        %   resolve+spec+decOpts yang SAMA dgn ekspor batch -> "what you see =
        %   what you get". TIDAK menyentuh katalog resmi (manifest/purge/indeks).
        %   opts: dpi/jpegQuality/userPrefs/resolve/dataAll (opsional, sama spt
        %   previewFrame). Mengembalikan cellstr path {velmag; shear} yg ditulis.
            if nargin < 4 || ~isstruct(opts), opts = struct(); end
            g = @(f,d) pivcore.io.pabExportCatalog.getf(opts, f, d);
            dpi = g('dpi', 300); jq = g('jpegQuality', 95);
            up  = g('userPrefs', struct());
            R   = g('resolve', []);
            if isempty(R) || ~isstruct(R)
                R = pivcore.export.frameCatalog.resolveRender(dataFile);
            end
            dataAll = g('dataAll', []);
            if isempty(dataAll)
                dataAll = pivcore.io.step1Session.loadAllFrames(dataFile);
            end
            nF = pivcore.data.frameCount(dataAll); if nF<1, nF=1; end
            k = max(1, min(round(k), nF));
            spec = pivcore.export.frameCatalog.specFromResolve(R, up);
            cfg  = pivcore.export.frameCatalog.renderCfg(spec);
            decOpts = pivcore.export.frameCatalog.decOptsFromSpec(spec, up);
            fdir = pivcore.io.pabExportCatalog.frameDir(pabRoot, dataFile);
            if ~isfolder(fdir), mkdir(fdir); end
            keys = {'velmag','shear'};
            files = cell(numel(keys),1);
            for ii = 1:numel(keys)
                key = keys{ii};
                fn  = pivcore.io.pabExportCatalog.frameFile(dataFile, key, k, 'jpg');
                files{ii} = fullfile(fdir, fn);
                pivcore.export.frameCatalog.renderFrameToFile( ...
                    dataAll, k, key, cfg, R, dataFile, files{ii}, dpi, jq, decOpts);
            end
        end

        % =============================================================
        function drawScalarPanel(ax, dataAll, k, scalarKey, cfg, R, base, opts)
        %DRAWSCALARPANEL  Gambar AX main (1 bingkai 1 skalar) + DEKORASI ke `ax`
        %   MANA PUN. SUMBER TUNGGAL rupa gambar -> dipakai BERSAMA preview
        %   WYSIWYG (axes GUI) & ekspor (figure offscreen) = "what you see = what
        %   you get". opts (semua opsional):
        %     .showPSG/.showColorbar/.showTitle  dekorasi dasar (def true)
        %     .tickPx        tickmark posisi pixel XTick/YTick (def true)
        %     .glyphColorShear  warna glyph KHUSUS shear [r g b] (NaN -> pakai cfg)
        %     .velUnit       'pxframe'|'cms' ; cms -> colorbar*velMult + label cm/s
        %     .velMult       pengali |V| -> cm/s (def 1)
        %     .strainShow    caption strain kiri-bawah (def true)
        %     .strainPos     [x y] normalized posisi caption (def [0.02 0.04])
        %     .strainPct     nilai strain kumulatif % bingkai ini (NaN -> auto via R.geom)
        %     .titleOverride teks judul kustom (kosong -> nama exp saja)
        %     .axCal         doc kalibrasi sumbu cm (pivcore.io.pabAxCal). Bila
        %                    diberikan & .enabled -> tick X/Y jadi cm + label +
        %                    segitiga indenter (override tick pixel). [] -> pixel.
            if nargin < 8 || ~isstruct(opts), opts = struct(); end
            gf = @(f,d) pivcore.export.frameCatalog.optf(opts, f, d);
            showPSG = gf('showPSG', true);
            showCB  = gf('showColorbar', true);
            showTit = gf('showTitle', true);
            tickPx  = gf('tickPx', true);
            isShear = strcmpi(scalarKey,'shear');

            % Warna glyph khusus shear (override cfg.glyphColor bila diberikan).
            gcs = gf('glyphColorShear', [NaN NaN NaN]);
            if isShear && numel(gcs)==3 && all(isfinite(gcs))
                cfg.glyphColor = gcs(:).';
            end

            pivcore.montage.renderScalarPanel(ax, dataAll, k, scalarKey, cfg);

            % PAKSA elemen sumbu HITAM-di-PUTIH (tak bergantung tema OS) supaya
            % gambar arsip = kanvas WYSIWYG walau MATLAB/OS dark-mode.
            set(ax, 'Color','w', 'XColor',[0 0 0], 'YColor',[0 0 0]);
            f = ancestor(ax,'figure'); if ~isempty(f), set(f,'Color','w'); end

            % Tickmark posisi pixel on/off.
            if ~tickPx
                set(ax, 'XTick', [], 'YTick', []);
            end

            % Colorbar + satuan. Velmag bisa cm/s (skala angka * velMult).
            velMult = gf('velMult', 1); velUnit = char(gf('velUnit','pxframe'));
            useCms = ~isShear && strcmpi(velUnit,'cms') && isfinite(velMult) && velMult > 0;
            if showCB
                cb = colorbar(ax);
                if isShear
                    cb.Label.String = 'shear strain (du/dy+dv/dx)';
                elseif useCms
                    cb.Label.String = '|V| (cm/s)';
                    % Skala angka tick = nilai px/frame * velMult (CLim tak diubah,
                    % hanya LABEL angka -> data & warna tetap, satuan tampil cm/s).
                    cl = clim(ax); t = get(cb,'Ticks');
                    if isempty(t), t = linspace(cl(1), cl(2), 6); set(cb,'Ticks',t); end
                    set(cb,'TickLabels', arrayfun(@(v) sprintf('%.3g', v*velMult), ...
                        t, 'UniformOutput', false));
                else
                    cb.Label.String = '|V| (px/frame)';
                end
                % PAKSA colorbar HITAM (tema-tahan).
                set(cb,'Color',[0 0 0]); cb.Label.Color = [0 0 0];
            end

            % Garis PSG oranye.
            if showPSG && isstruct(R) && ~isempty(R.line) && isfield(R.line,'p1')
                ps = pivui.potStyle().psgLine; hold(ax,'on');
                plot(ax, [R.line.p1(1) R.line.p2(1)], [R.line.p1(2) R.line.p2(2)], ...
                    '-','Color',ps.color,'LineWidth',ps.lineWidth);
                hold(ax,'off');
            end

            % Sumbu cm (tick X/Y + label + segitiga indenter) bila dikalibrasi.
            % Override tick pixel di atas. xExt/yExt dari data (koordinat pixel).
            axCal = gf('axCal', []);
            if isstruct(axCal) && isfield(axCal,'enabled') && axCal.enabled
                nF = pivcore.data.frameCount(dataAll);
                x = pivcore.data.safeFrame(dataAll.x, k);
                y = pivcore.data.safeFrame(dataAll.y, k);
                if isempty(x), x = pivcore.data.safeFrame(dataAll.x, 1); end
                if isempty(y), y = pivcore.data.safeFrame(dataAll.y, 1); end
                if ~isempty(x) && ~isempty(y)
                    xExt = [min(x(:)) max(x(:))]; yExt = [min(y(:)) max(y(:))];
                    pivcore.export.frameCatalog.applyCmAxes(ax, axCal, R, k, nF, xExt, yExt);
                end
            end

            % Judul = NAMA EKSPERIMEN saja (keputusan user). Paksa HITAM.
            if showTit
                ttl = char(gf('titleOverride',''));
                if isempty(ttl), ttl = char(base); end
                title(ax, ttl, 'Interpreter','none', 'Color',[0 0 0]);
            end

            % Caption strain kiri-bawah: "<cumStrain%> (<frame>/<total>)".
            if gf('strainShow', true)
                nF = pivcore.data.frameCount(dataAll);
                pct = gf('strainPct', NaN);
                if ~isfinite(pct), pct = pivcore.export.frameCatalog.strainAt(R, k, nF); end
                pos = pivcore.export.frameCatalog.optrow2(opts, 'strainPos', [0.02 0.04]);
                if isfinite(pct)
                    txt = sprintf('%.2f %% (%d/%d)', pct, k, nF);
                else
                    txt = sprintf('(%d/%d)', k, nF);
                end
                scol = pivcore.export.frameCatalog.optrow3(opts, 'strainColor', [0 0 0]);
                sbg  = pivcore.export.frameCatalog.optrow3(opts, 'strainBg',   [1 1 1]);
                text(ax, pos(1), pos(2), txt, 'Units','normalized', ...
                    'HorizontalAlignment','left','VerticalAlignment','bottom', ...
                    'FontSize',9,'FontWeight','bold','Color',scol, ...
                    'BackgroundColor',[sbg 0.6], 'Margin',1, 'Tag','strainCaption');
            end
        end

        % =============================================================
        function applyCmAxes(ax, calDoc, R, k, nF, xExt, yExt)
        %APPLYCMAXES  Terapkan tick/label sumbu cm + segitiga indenter ke `ax`.
        %   SUMBER TUNGGAL rupa sumbu-cm -> dipakai BERSAMA preview WYSIWYG,
        %   axMain live PAB4 (pab4Shell.renderMain) & ekspor (drawScalarPanel).
        %
        %   calDoc = doc pivcore.io.pabAxCal (harus .enabled utk berefek).
        %   R      = struct render (butuh R.dxCm utk segitiga; boleh []/NaN).
        %   k,nF   = bingkai aktif & total (posisi segitiga = shortening frame).
        %   xExt/yExt = extent PIXEL sumbu [min max] (utk letak segitiga & limit).
        %
        %   Tick pixel di-OVERRIDE hanya bila kalibrasi sumbu valid. Segitiga
        %   di-skip senyap bila kalibrasi X / dxCm tak tersedia (tak render palsu).
            if ~isstruct(calDoc) || ~isfield(calDoc,'enabled') || ~calDoc.enabled
                return;
            end
            ax0 = pivcore.io.pabAxCal;   %#ok<NASGU> (alias ringkas tak dipakai; kejelasan)

            % --- Sumbu-X: tick cm + label ---
            if pivcore.io.pabAxCal.isValid(calDoc, 'x')
                tx = calDoc.x.tickCm; tx = tx(isfinite(tx));
                if ~isempty(tx)
                    xt = pivcore.io.pabAxCal.cmToPx(calDoc, 'x', tx);
                    [xt, ord] = sort(xt(:).'); txs = tx(ord);
                    set(ax, 'XTick', xt, ...
                        'XTickLabel', arrayfun(@(v) sprintf('%g',v), txs, 'UniformOutput',false));
                    if isfield(calDoc.x,'autoLimit') && calDoc.x.autoLimit
                        lim = sort([min(xt) max(xt)]);
                        if diff(lim) > 0, try, xlim(ax, lim); catch, end, end
                    end
                end
                if isfield(calDoc.x,'label') && ~isempty(calDoc.x.label)
                    xlabel(ax, calDoc.x.label, 'Color',[0 0 0]);
                end
            end

            % --- Sumbu-Y: tick cm + label ---
            if pivcore.io.pabAxCal.isValid(calDoc, 'y')
                ty = calDoc.y.tickCm; ty = ty(isfinite(ty));
                if ~isempty(ty)
                    yt = pivcore.io.pabAxCal.cmToPx(calDoc, 'y', ty);
                    [yt, ord] = sort(yt(:).'); tys = ty(ord);
                    set(ax, 'YTick', yt, ...
                        'YTickLabel', arrayfun(@(v) sprintf('%g',v), tys, 'UniformOutput',false));
                    if isfield(calDoc.y,'autoLimit') && calDoc.y.autoLimit
                        lim = sort([min(yt) max(yt)]);
                        if diff(lim) > 0, try, ylim(ax, lim); catch, end, end
                    end
                end
                if isfield(calDoc.y,'label') && ~isempty(calDoc.y.label)
                    ylabel(ax, calDoc.y.label, 'Color',[0 0 0]);
                end
            end
            set(ax, 'XColor',[0 0 0], 'YColor',[0 0 0]);

            % --- Segitiga merah indenter di sumbu-X bawah ---
            ind = struct('show',false,'mode','shortening','fixedCm',NaN,'color',[1 0 0]);
            if isfield(calDoc,'indenter') && isstruct(calDoc.indenter)
                fn = fieldnames(calDoc.indenter);
                for i = 1:numel(fn), ind.(fn{i}) = calDoc.indenter.(fn{i}); end
            end
            if ~ind.show || ~pivcore.io.pabAxCal.isValid(calDoc, 'x'), return; end

            shortCm = NaN;
            if strcmpi(ind.mode,'fixed')
                shortCm = pivcore.io.pabAxCal.scal(ind.fixedCm);
            else   % 'shortening': ikut frame via dxCm
                dxCm = NaN;
                if isstruct(R) && isfield(R,'dxCm'), dxCm = pivcore.io.pabAxCal.scal(R.dxCm); end
                if isfinite(dxCm)
                    if nF <= 1, shortCm = dxCm; else, shortCm = (k-1)/(nF-1) * dxCm; end
                end
            end
            if ~isfinite(shortCm), return; end   % dxCm/geom tak ada -> skip senyap

            xTri = pivcore.io.pabAxCal.cmToPx(calDoc, 'x', shortCm);
            if ~isfinite(xTri), return; end
            yBase = min(yExt);   % tepi bawah gambar
            col = ind.color; if numel(col) ~= 3, col = [1 0 0]; end
            hold(ax,'on');
            plot(ax, xTri, yBase, '^', 'MarkerSize',10, ...
                'MarkerFaceColor',col, 'MarkerEdgeColor','k', 'LineWidth',0.75, ...
                'Clipping','off', 'HitTest','off', 'PickableParts','none', ...
                'Tag','indenterTri');
            hold(ax,'off');
        end

        % =============================================================
        function rf = makeRenderFig()
        %MAKERENDERFIG  Buat figure offscreen TERANG + axes -> dipakai-ULANG utk
        %   banyak frame (hindari biaya buat/tutup figure tiap frame, ~2.6x).
            fig = figure('Visible','off','Color','w','Units','pixels', ...
                'Position',[100 100 1100 620]);
            try, pivui.forceLightTheme(fig); catch, end
            ax = axes('Parent',fig);
            rf = struct('fig',fig, 'ax',ax);
        end

        function renderToAxes(ax, dataAll, k, scalarKey, cfg, R, dataFile, file, dpi, jq, opts)
        %RENDERTOAXES  Render 1 bingkai ke `ax` yg DIPAKAI-ULANG -> exportgraphics.
        %   cla(ax) dulu supaya bersih. WYSIWYG (drawScalarPanel sama). Lalu:
        %   (a) CAP sisi-panjang ke opts.maxLongPx (imresize) -> file tak kebesaran
        %   (cegah Mac hang & arsip raksasa), (b) JPEG QUALITY (jq) via imwrite.
            if nargin < 11 || ~isstruct(opts), opts = struct(); end
            cla(ax,'reset'); set(ax,'Color','w');
            [~, base] = fileparts(char(dataFile));
            pivcore.export.frameCatalog.drawScalarPanel(ax, dataAll, k, scalarKey, cfg, R, base, opts);
            maxLong = pivcore.export.frameCatalog.optf(opts, 'maxLongPx', NaN);
            isJpeg = ~isempty(regexpi(char(file), '\.jpe?g$', 'once'));
            qok = isscalar(jq) && isfinite(jq) && jq >= 1 && jq <= 100;
            needPost = isJpeg && ((isscalar(maxLong) && isfinite(maxLong) && maxLong>0) || (qok && jq < 100));
            try
                if needPost
                    % exportgraphics -> array (getframe-free) lalu cap+imwrite.
                    img = pivcore.export.frameCatalog.axToImage(ax, dpi);
                    [hh, ww, ~] = size(img);
                    if isscalar(maxLong) && isfinite(maxLong) && maxLong>0 && max(hh,ww) > maxLong
                        img = imresize(img, maxLong / max(hh,ww));
                    end
                    q = 95; if qok, q = round(jq); end
                    imwrite(img, file, 'jpg', 'Quality', q);
                else
                    exportgraphics(ax, file, 'Resolution', dpi);
                end
            catch ME
                warning('pivcore:frameCatalog:export', ...
                    'Gagal ekspor %s (%s).', file, ME.message);
            end
        end

        function img = axToImage(ax, dpi)
        %AXTOIMAGE  Render axes -> array RGB via exportgraphics ke PNG temporer
        %   (lossless) lalu imread. Dipakai utk pipeline cap-piksel + JPEG quality.
            tmp = [tempname '.png'];
            c = onCleanup(@() pivcore.export.frameCatalog.delIf(tmp));
            exportgraphics(ax, tmp, 'Resolution', dpi);
            img = imread(tmp);
        end

        function delIf(p)
            if ischar(p) && isfile(p), try, delete(p); catch, end, end
        end

        function renderOneReuse(dataAll, k, scalarKey, cfg, R, dataFile, file, dpi, jq, opts)
        %RENDERONEREUSE  Versi parfor-safe: figure PERSISTENT per-WORKER (dibuat
        %   sekali, dipakai-ulang seluruh frame yg jatuh ke worker itu). Tutup
        %   otomatis saat worker mati. Memanggil renderToAxes.
            persistent RF
            if isempty(RF) || ~isfield(RF,'fig') || ~ishghandle(RF.fig)
                RF = pivcore.export.frameCatalog.makeRenderFig();
            end
            pivcore.export.frameCatalog.renderToAxes(RF.ax, dataAll, k, scalarKey, ...
                cfg, R, dataFile, file, dpi, jq, opts);
        end

        function renderFrameToFile(dataAll, k, scalarKey, cfg, R, dataFile, file, dpi, jq, opts)
        %RENDERFRAMETOFILE  Render 1 bingkai -> JPEG via figure OFFSCREEN BARU
        %   (1 panggilan = 1 figure). Dipakai previewFrame (test 1 frame). Untuk
        %   batch banyak frame pakai renderToAxes/renderOneReuse (reuse figure).
            if nargin < 10 || ~isstruct(opts), opts = struct(); end
            rf = pivcore.export.frameCatalog.makeRenderFig();
            cleaner = onCleanup(@() pivcore.export.frameCatalog.safeClose(rf.fig)); %#ok<NASGU>
            pivcore.export.frameCatalog.renderToAxes(rf.ax, dataAll, k, scalarKey, ...
                cfg, R, dataFile, file, dpi, jq, opts);
        end

        % =============================================================
        function tf = canParallel(nTask, opts)
        %CANPARALLEL  true bila layak paralel: PCT terpasang + nTask cukup +
        %   tak dipaksa serial (opts.parallel=false). opts.parallel: []=auto,
        %   true/false=paksa. SENYAP saat quiet test (hindari pool di -batch CI).
            if nargin < 2, opts = struct(); end
            force = pivcore.io.pabExportCatalog.getf(opts, 'parallel', []);
            if islogical(force) && isscalar(force), tf = force; return; end
            tf = false;
            try, if pivui.quiet(), return; end, catch, end   % tes: serial
            if nTask < 8, return; end                          % terlalu kecil
            tf = ~isempty(ver('parallel'));
        end

        function ensurePool(maxW)
        %ENSUREPOOL  Pastikan parpool aktif dgn ≤ maxW worker (default 5). Pakai
        %   pool yg ada bila ukuran cocok; else buat. Sebar addpath PAB ke worker.
            if nargin < 1 || isempty(maxW), maxW = 5; end
            p = gcp('nocreate');
            if isempty(p)
                nc = maxW;
                try
                    c = parcluster(); nc = min(maxW, c.NumWorkers);
                catch
                end
                if nc < 1, nc = 1; end
                p = parpool(nc);
            elseif p.NumWorkers > maxW
                % pool kebesaran -> kecilkan agar tak berat (user minta ~5).
                delete(p); p = parpool(maxW); %#ok<NASGU>
            end
            % Sebar path PAB (pivcore/pivui) ke worker (defensif).
            try
                here = fileparts(fileparts(fileparts(mfilename('fullpath'))));  % .../pivcore_lib
                root = fileparts(here);                                          % .../PAB
                parfevalOnAll(@addpath, 0, here, root);
            catch
            end
        end

        % =============================================================
        % Helper murni
        % =============================================================
        function cfg = renderCfg(spec)
        %RENDERCFG  Bangun struct cfg yang dikonsumsi renderScalarPanel dari spec.
            cfg = struct();
            cfg.scalarSrc  = 'velocity_magnitude';
            cfg.climVel    = spec.climVel(:).';
            cfg.shearAbs   = spec.shearAbs;
            cfg.gsOn       = logical(spec.gsOn);
            cfg.claheOn    = logical(spec.claheOn);
            cfg.adjOn      = logical(spec.adjOn);
            cfg.gsAlpha    = spec.gsAlpha;
            cfg.glyphOn    = logical(spec.glyphOn);
            cfg.glyphLW    = spec.glyphLW;
            cfg.glyphSp    = spec.glyphSp;
            cfg.glyphColor = spec.glyphColor(:).';
        end

        function dec = decOptsFromSpec(spec, up)
        %DECOPTSFROMSPEC  Opsi dekorasi drawScalarPanel dari spec (+ up utk
        %   showPSG/CB/Title). SATU sumber -> preview & ekspor identik.
            if nargin < 2 || ~isstruct(up), up = struct(); end
            gu = @(f,d) pivcore.io.pabExportCatalog.getf(up, f, d);
            gs = @(f,d) pivcore.io.pabExportCatalog.getf(spec, f, d);
            dec = struct( ...
                'showPSG',         gu('showPSG', true), ...
                'showColorbar',    gu('showColorbar', true), ...
                'showTitle',       gu('showTitle', true), ...
                'tickPx',          gs('tickPx', true), ...
                'glyphColorShear', gs('glyphColorShear', [NaN NaN NaN]), ...
                'velUnit',         gs('velUnit', 'pxframe'), ...
                'velMult',         gs('velMult', 1), ...
                'strainShow',      gs('strainShow', true), ...
                'strainPos',       gs('strainPos', [0.02 0.04]), ...
                'strainColor',     gs('strainColor', [0 0 0]), ...
                'strainBg',        gs('strainBg', [1 1 1]), ...
                'axCal',           gu('axCal', []));   % kalibrasi sumbu cm (opsional; [] -> pixel)
        end

        function env = indenterEnvelope(recs, nF)
        %INDENTERENVELOPE  Envelope MAX |V| antar-kurva POT (clean-room dari
        %   pab4Shell.indenterEnvelope; tanpa flag excluded — recs mentah).
            env = [];
            if isempty(recs), return; end
            M = -inf(1, nF); any_ = false;
            for r = 1:numel(recs)
                [~, yv] = pivcore.pot.records.curveXY(recs(r), nF);
                if isempty(yv), continue; end
                m = numel(yv); seg = M(1:m); gd = isfinite(yv);
                seg(gd) = max(seg(gd), yv(gd)); M(1:m) = seg; any_ = true;
            end
            if ~any_, return; end
            M(~isfinite(M)) = NaN; env = M;
        end

        function ln = lineFromPotData(dataFile)
        %LINEFROMPOTDATA  Garis PSG pertama dari _potdata.json PAB4 (bila ada).
        %   [] bila tak ada. struct p1/p2/frac.
            ln = [];
            doc = pivcore.io.pab4PotData.read(dataFile);
            if ~isstruct(doc) || ~isfield(doc,'psgLines') || isempty(doc.psgLines)
                return;
            end
            L = doc.psgLines;
            if iscell(L), first = L{1}; else, first = L(1); end
            if ~isstruct(first) || ~isfield(first,'p1') || ~isfield(first,'p2')
                return;
            end
            p1 = double(first.p1(:).'); p2 = double(first.p2(:).');
            if numel(p1) < 2 || numel(p2) < 2 || any(~isfinite([p1(1:2) p2(1:2)]))
                return;
            end
            frac = NaN;
            if isfield(first,'frac') && ~isempty(first.frac), frac = double(first.frac(1)); end
            ln = struct('p1', p1(1:2), 'p2', p2(1:2), 'frac', frac);
        end

        function [strainPct, cmPerPx, dxCm] = readGeom(dataFile)
        %READGEOM  Baca strain_cumm_pct + skala spasial cm/px (best-effort) +
        %   pergeseran |X0-X1| cm dari .mat PIV. cm/px dari calxy PIVlab BILA
        %   terkalibrasi (calxy~=1; calxy==1 -> NaN). dxCm = |X0_cm-X1_cm|
        %   (untuk opsi-3 kecepatan indenter). Senyap; gagal -> NaN.
            strainPct = NaN; cmPerPx = NaN; dxCm = NaN;
            try
                V = whos('-file', dataFile); names = {V.name};
                if any(strcmp(names,'experiment_geometry'))
                    S = load(dataFile, 'experiment_geometry'); g = S.experiment_geometry;
                    if isstruct(g)
                        if isfield(g,'strain_cumm_pct') && isscalar(g.strain_cumm_pct) ...
                                && isfinite(g.strain_cumm_pct)
                            strainPct = double(g.strain_cumm_pct);
                        end
                        if isfield(g,'X0_cm') && isfield(g,'X1_cm') ...
                                && isscalar(g.X0_cm) && isscalar(g.X1_cm) ...
                                && isfinite(g.X0_cm) && isfinite(g.X1_cm)
                            dxCm = abs(double(g.X0_cm) - double(g.X1_cm));
                        end
                    end
                end
                if any(strcmp(names,'calxy'))
                    S = load(dataFile, 'calxy'); cx = S.calxy;
                    if isscalar(cx) && isfinite(cx) && cx > 0 && abs(cx-1) > 1e-9
                        cmPerPx = double(cx) / 10;   % mm/px -> cm/px
                    end
                end
            catch
            end
        end

        function g = readGeomFull(dataFile)
        %READGEOMFULL  Struct geometri eksperimen lengkap dari .mat PIV:
        %   .X0_cm/.X1_cm (posisi indenter awal/akhir), .Lpos_cm (posisi ref
        %   tetap), .L0_cm/.L1_cm (panjang awal/akhir = Lpos-X0 / Lpos-X1),
        %   .dL_cm, .strainPct. Field absen -> NaN. Senyap.
            g = struct('X0_cm',NaN,'X1_cm',NaN,'Lpos_cm',NaN,'L0_cm',NaN, ...
                'L1_cm',NaN,'dL_cm',NaN,'strainPct',NaN);
            try
                V = whos('-file', dataFile); names = {V.name};
                if ~any(strcmp(names,'experiment_geometry')), return; end
                S = load(dataFile, 'experiment_geometry'); e = S.experiment_geometry;
                if ~isstruct(e), return; end
                cp = @(f) (isfield(e,f) && isscalar(e.(f)) && isfinite(e.(f))) * 1;
                if cp('X0_cm'),   g.X0_cm   = double(e.X0_cm);   end
                if cp('X1_cm'),   g.X1_cm   = double(e.X1_cm);   end
                if cp('Lpos_cm'), g.Lpos_cm = double(e.Lpos_cm); end
                if cp('L0_cm'),   g.L0_cm   = double(e.L0_cm);   end
                if cp('L1_cm'),   g.L1_cm   = double(e.L1_cm);   end
                if cp('dL_cm'),   g.dL_cm   = double(e.dL_cm);   end
                if cp('strain_cumm_pct'), g.strainPct = double(e.strain_cumm_pct); end
                % Turunkan L0 bila absen tapi Lpos & X0 ada.
                if ~isfinite(g.L0_cm) && isfinite(g.Lpos_cm) && isfinite(g.X0_cm)
                    g.L0_cm = g.Lpos_cm - g.X0_cm;
                end
            catch
            end
        end

        function dt = readExifDt(dataFile)
        %READEXIFDT  dt detik/frame dari .mat (median EXIF). NaN bila tak ada.
        %   Clean-room dari PAB4 i_readExifTiming.
            dt = NaN;
            try
                V = whos('-file', dataFile); names = {V.name};
                cand = {'exif_dt_s','dt_s','exifDt','frame_dt_s','time_dt_s'};
                for c = cand
                    if ~any(strcmp(names, c{1})), continue; end
                    S = load(dataFile, c{1}); v = S.(c{1}); v = v(isfinite(v) & v>0);
                    if ~isempty(v), dt = median(v); return; end
                end
            catch
            end
        end

        function pct = strainAt(R, k, nF)
        %STRAINAT  Strain kumulatif % bingkai-k = (k-1)/(nF-1)*strainTotalPct.
        %   strainTotalPct dari R.geom.strain_cumm_pct (bila ada). NaN bila tak ada.
            pct = NaN;
            if ~isstruct(R) || ~isfield(R,'strainTotalPct'), return; end
            tot = R.strainTotalPct;
            if ~(isscalar(tot) && isfinite(tot)), return; end
            if nF <= 1, pct = tot; else, pct = (k-1)/(nF-1) * tot; end
        end

        function v = optf(opts, f, d)
            if isstruct(opts) && isfield(opts,f) && ~isempty(opts.(f)), v = opts.(f); else, v = d; end
        end

        function v = optrow2(opts, f, d)
            v = pivcore.export.frameCatalog.optf(opts, f, d);
            v = double(v(:).'); if numel(v) < 2, v = [v nan(1,2-numel(v))]; end
            v = v(1:2);
        end

        function v = optrow3(opts, f, d)
            v = pivcore.export.frameCatalog.optf(opts, f, d);
            v = double(v(:).'); if numel(v) < 3, v = d(:).'; end
            v = max(0, min(1, v(1:3)));
        end

        function safeClose(f)
            try, if ishghandle(f), close(f); end, catch, end
        end

    end
end
