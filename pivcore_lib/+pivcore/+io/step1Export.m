classdef step1Export
%STEP1EXPORT  I/O stateless modul Step 1: ekspor tampilan MENTAH "apa adanya"
%   tiap eksperimen ke folder keluaran tunggal di root kerja. SATU berkas PNG
%   gabungan per eksperimen: bingkai-1 axMain (persis tampilan default Step 1,
%   beserta garis PSG) di ATAS + plot POT semua titik (records POT-PSG4) di
%   BAWAH. TANPA pemrosesan: kurva ditampilkan apa adanya.
%
%   Konvensi: semua keluaran ditaruh di <root>/Step1_output/<nama>.png .
%   Kehadiran berkas itulah penanda kolom "OUT" tercentang (deteksi murni
%   dari sistem berkas, tak menyentuh _autopot).
%
%   API:
%     d   = pivcore.io.step1Export.outDir(root)
%     f   = pivcore.io.step1Export.pngPath(root, name)
%     tf  = pivcore.io.step1Export.hasExport(root, name)
%     recs= pivcore.io.step1Export.loadRecords(dataFile)   % [] bila tak ada
%     f   = pivcore.io.step1Export.exportOne(axMain, recs, root, name, titleTxt)
%
%   Penempatan berkas: PIVTerry/+pivterry/+io/step1Export.m

    methods (Static)

        % ================================================================
        function d = outDir(root)
        %OUTDIR  Folder keluaran tunggal <root>/Step1_output (string kosong
        %   bila root tak valid).
            d = '';
            if isempty(root) || ~ischar(root), return; end
            d = fullfile(root, 'Step1_output');
        end


        % ================================================================
        function f = pngPath(root, name)
        %PNGPATH  Path PNG keluaran utk satu eksperimen.
            f = '';
            d = pivcore.io.step1Export.outDir(root);
            if isempty(d) || isempty(name), return; end
            f = fullfile(d, sprintf('%s.png', pivcore.io.step1Export.safeName(name)));
        end


        % ================================================================
        function tf = hasExport(root, name)
        %HASEXPORT  TRUE bila PNG keluaran eksperimen ini sudah ada.
            tf = false;
            f = pivcore.io.step1Export.pngPath(root, name);
            if isempty(f), return; end
            tf = isfile(f);
        end


        % ================================================================
        function recs = loadRecords(dataFile)
        %LOADRECORDS  Baca records POT-PSG4 (titik POT) dari <base>_autopot.mat.
        %   [] bila tak ada. Dipakai untuk plot POT mentah.
            recs = [];
            f = pivcore.io.step1Session.autopotPath(dataFile);
            if isempty(f) || ~isfile(f), return; end
            try
                Sin = load(f, 'autopotSession');
            catch
                return;
            end
            if ~isfield(Sin,'autopotSession'), return; end
            ap = Sin.autopotSession;
            if ~isstruct(ap) || ~isfield(ap,'potpsg4') || ~isstruct(ap.potpsg4), return; end
            if ~isfield(ap.potpsg4,'records'), return; end
            recs = ap.potpsg4.records;
        end


        % ================================================================
        function f = exportOne(axMain, recs, root, name, titleTxt)
        %EXPORTONE  Tulis SATU PNG gabungan: salinan axMain (atas) + plot POT
        %   semua titik dari `recs` (bawah). axMain disalin via copyobj agar
        %   PERSIS tampilan default Step 1 (citra bingkai-1 + garis PSG).
        %   Mengembalikan path berkas yg ditulis.
            if nargin < 5, titleTxt = ''; end
            f = pivcore.io.step1Export.pngPath(root, name);
            if isempty(f)
                error('pivcore:step1Export:noPath', ...
                    'Tak bisa menentukan path keluaran (root/name kosong).');
            end
            d = pivcore.io.step1Export.outDir(root);
            if ~isfolder(d), mkdir(d); end

            % Figure luar-layar utk komposit dua panel.
            fig = figure('Visible','off','Color','w', ...
                'Units','pixels','Position',[100 100 900 1000]);
            cleaner = onCleanup(@() i_closeFig(fig)); %#ok<NASGU>

            % --- Panel ATAS: salinan axMain (tampilan mentah Step 1) ---------
            axTop = axes('Parent',fig,'Units','normalized', ...
                'Position',[0.08 0.55 0.88 0.40]);
            pivcore.io.step1Export.copyAxInto(axMain, axTop);
            % Titik lokasi pengambilan data (origin) di axMain, warna = warna
            % kurva POT-nya. copyobj sudah membawa marker yg ada di axMain on-
            % screen; gambar ulang di sini agar PNG tetap benar walau axMain
            % sumber tak punya marker (mis. dipanggil headless).
            pivcore.io.step1Export.drawPointsOnAx(axTop, recs, 'expPt');
            if ~isempty(titleTxt)
                title(axTop, char(titleTxt), 'Interpreter','none');
            end

            % --- Panel BAWAH: plot POT semua titik (apa adanya) -------------
            axBot = axes('Parent',fig,'Units','normalized', ...
                'Position',[0.08 0.07 0.88 0.40]);
            pivcore.io.step1Export.plotPot(axBot, recs);

            % --- Tulis PNG -------------------------------------------------
            try
                exportgraphics(fig, f, 'Resolution', 150, 'BackgroundColor','white');
            catch ME
                error('pivcore:step1Export:writeFail', ...
                    'Gagal menulis PNG %s: %s', f, ME.message);
            end
        end


        % ================================================================
        function copyAxInto(axSrc, axDst)
        %COPYAXINTO  Salin isi (children) + properti tampilan axSrc ke axDst,
        %   sehingga panel atas PERSIS seperti axMain default Step 1.
            if isempty(axSrc) || ~ishghandle(axSrc), return; end
            try
                kids = allchild(axSrc);
                if ~isempty(kids), copyobj(flipud(kids(:)), axDst); end
            catch
            end
            % Tiru properti tampilan inti.
            props = {'XLim','YLim','CLim','YDir','Colormap','DataAspectRatio', ...
                     'DataAspectRatioMode','PlotBoxAspectRatio','PlotBoxAspectRatioMode'};
            for k = 1:numel(props)
                try, set(axDst, props{k}, get(axSrc, props{k})); catch, end %#ok<NOSEM,CTCH>
            end
            % Buang marker titik yg ikut tersalin (s1Pt/s2Pt/pp4AxPt) -> akan
            % digambar ulang sbg 'expPt' agar tak dobel.
            for tg = {'s1Pt','s2Pt','pp4AxPt'}
                try, delete(findall(axDst,'Tag',tg{1})); catch, end %#ok<NOSEM,CTCH>
            end
            try, axis(axDst,'off'); catch, end %#ok<NOSEM,CTCH>
        end


        % ================================================================
        function plotPot(ax, recs, doReset, conv)
        %PLOTPOT  Plot SEMUA titik POT (records) di ax PERSIS spt axPOT di
        %   POT-PSG4: tema PUTIH, tiap kurva BERWARNA BERBEDA (warna terpisah
        %   per titik, spt POT-PSG4 'Recolor'), X = frame, Y = nilai skalar
        %   MENTAH (tanpa moving-average). Bila record sudah punya rec.color
        %   non-default (mis. di-assign ke sesar di POT-PSG4), warna itu
        %   dihormati; titik default (fault=0, abu-abu) diberi warna distinct.
        %   doReset (default true): cla 'reset' (utk axes ekspor sekali pakai).
        %   Set false utk axPOT GUI live agar properti interaksi tak hilang.
        %
        %   `conv` (opsional): struct('factor',<pengali>,'label',<ylabel>) untuk
        %   menampilkan deret dlm satuan tampilan, mis. laju metrik cm/s atau
        %   cm/hr (pengali & label dari pivcore.pot.units.factor). Default
        %   IDENTITAS (factor=1, label 'Value') -> perilaku lama tak berubah,
        %   jadi pemanggil lama (exportOne) & salinan +pivterry tak terpengaruh.
        %   Faktor diterapkan SETELAH moving-average (linear -> urutan tak
        %   penting); konversi murni tampilan (data record tetap px/frame).
            if nargin < 3, doReset = true; end
            if nargin < 4 || isempty(conv) || ~isstruct(conv), conv = struct(); end
            if ~isfield(conv,'factor') || ~isscalar(conv.factor) || ~isfinite(conv.factor)
                conv.factor = 1;
            end
            if ~isfield(conv,'label') || ~ischar(conv.label) || isempty(conv.label)
                conv.label = 'Value';
            end
            if doReset, cla(ax,'reset'); else, cla(ax); end
            hold(ax,'on');
            % Tema putih bersih (axPOT POT-PSG4): latar putih, sumbu hitam,
            % grid abu muda. Reset colormap agar 'Color' garis tak terpeta.
            set(ax,'Color','w','XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
                   'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top');
            try, colormap(ax, gray(256)); catch, end %#ok<NOSEM,CTCH>

            if isempty(recs)
                text(ax, 0.5, 0.5, 'No POT points collected', ...
                    'Units','normalized','HorizontalAlignment','center', ...
                    'Color',[0.5 0.5 0.5]);
                hold(ax,'off');
                xlabel(ax,'Frame'); ylabel(ax,conv.label); grid(ax,'on');
                return;
            end
            n = numel(recs);
            % Palet warna distinct DETERMINISTIK (stabil lintas-run & identik
            % antara tampilan layar vs ekspor): hue tersebar merata.
            C = pivcore.io.step1Export.distinctColors(n);
            for i = 1:n
                y = recs(i).data;
                if isempty(y), continue; end
                y = y(:).';
                % Terapkan moving-average sesuai metadata record (sama dgn
                % POT-PSG4 redrawPOT) agar kurva yang TAMPIL identik dgn
                % POT-PSG4. Tanpa ini kurva tampak mentah/berisik & berbeda.
                if isfield(recs(i),'mode') && strcmpi(recs(i).mode,'Moving average') ...
                        && isfield(recs(i),'maWindow') && recs(i).maWindow >= 2
                    y = pivcore.util.movavg(y, recs(i).maWindow);
                end
                if conv.factor ~= 1, y = y * conv.factor; end   % -> satuan tampilan
                x = 1:numel(y);
                % SELALU warna distinct per-indeks (kurva warna-warni). TIDAK
                % memakai rec.color: setelah auto-aggregate Step 3, rec.color
                % jadi warna sesar (cuma sedikit warna) -> plot tampak kusam.
                plot(ax, x, y, '-', 'Color', C(i,:), 'LineWidth', 0.7);
            end
            hold(ax,'off');
            xlabel(ax,'Frame'); ylabel(ax,conv.label);
            title(ax, sprintf('Plot Over Time — %d points', n), ...
                'Interpreter','none','Color',[0 0 0]);
            grid(ax,'on');
        end


        % ================================================================
        function drawPointsOnAx(ax, recs, tagName)
        %DRAWPOINTSONAX  Gambar marker LOKASI tiap titik pengambilan data di
        %   axMain (pada koordinat rec.origin), warna SAMA dgn kurva POT-nya
        %   (lihat distinctColors), lingkaran kecil bertepi hitam. Marker
        %   diberi `tagName` agar bisa dibersihkan ulang. Lewati origin tak
        %   valid. Tak mengubah hold/lim axes secara permanen.
            if nargin < 3 || isempty(tagName), tagName = 's1Pt'; end
            if isempty(ax) || ~ishghandle(ax), return; end
            try, delete(findall(ax, 'Tag', tagName)); catch, end %#ok<NOSEM,CTCH>
            if isempty(recs), return; end
            n = numel(recs);
            C = pivcore.io.step1Export.distinctColors(n);
            hs = ishold(ax); hold(ax,'on');
            for i = 1:n
                o = [];
                if isfield(recs(i),'origin'), o = recs(i).origin; end
                if numel(o) ~= 2 || ~all(isfinite(o)), continue; end
                % SELALU warna distinct per-indeks (sinkron dgn kurva di plot).
                plot(ax, o(1), o(2), 'o','MarkerSize',5,'LineWidth',0.8, ...
                    'MarkerEdgeColor',[0 0 0],'MarkerFaceColor',C(i,:), ...
                    'Tag',tagName,'HitTest','off','PickableParts','none');
            end
            if ~hs, hold(ax,'off'); end
        end


        % ================================================================
        function C = distinctColors(n)
        %DISTINCTCOLORS  n warna UNIK & KONTRAS per kurva, DETERMINISTIK (tanpa
        %   rand) -> tampilan layar & ekspor identik dan stabil tiap run.
        %
        %   BUKAN gradien posisi: hue di-increment dgn rasio emas (golden-ratio
        %   ~0.618) sehingga kurva BERURUTAN (mis. titik kiri vs kiri+1) dapat
        %   warna yang BERJAUHAN di roda warna -> tiap kurva menonjol & terlihat
        %   walau tumpang tindih dgn ratusan kurva lain (gaya POT-PSG4: warna
        %   kontras per kurva, bukan biru->merah berurutan). Saturasi/nilai
        %   berselang 3 tingkat agar hue yang kebetulan berdekatan tetap beda.
            if n < 1, C = zeros(0,3); return; end
            g = 0.6180339887498949;               % konjugat rasio emas
            idx = (0:n-1).';
            hue = mod(0.13 + idx * g, 1);          % lompatan besar antar kurva
            sat = 0.85 - 0.20 * mod(idx, 3) / 2;   % 0.85 / 0.75 / 0.65
            val = 0.95 - 0.22 * mod(idx, 2);       % 0.95 / 0.73 berselang
            C = hsv2rgb([hue sat val]);
            C = min(1, max(0, C));
        end


        % ================================================================
        function s = safeName(name)
        %SAFENAME  Sanitasi nama eksperimen jadi nama berkas aman.
            s = char(name);
            s = regexprep(s, '[^\w\-. ]', '_');
            if isempty(s), s = 'experiment'; end
        end

    end
end


% =====================================================================
% Helper lokal
% =====================================================================
function i_closeFig(fig)
    if isempty(fig) || ~ishghandle(fig), return; end
    try, close(fig); catch, end %#ok<NOSEM,CTCH>
end
