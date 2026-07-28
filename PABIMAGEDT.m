function PABIMAGEDT(rootDir)
%PABIMAGEDT  Plot DT (interval waktu antar-foto) dari EXIF timelapse.
%
%   PABIMAGEDT                % pilih folder (dialog)
%   PABIMAGEDT(rootDir)       % langsung dari sebuah folder / root
%
%   = modul STANDALONE berbasis fungsi EXIF/DT yang sudah ada di PAB0
%   (pivprepRawExifDt). Tujuannya: MEMERIKSA keseragaman interval waktu
%   pemotretan timelapse SEBELUM PIV. Eksperimen yang normal punya DT rata
%   (semua sama); eksperimen bermasalah (mis. shutter counter roll-over,
%   mesin jeda) punya DT yang tidak seragam.
%
%   TAHAP 1 (file ini): PLOT DT antar-foto pada bidang Cartesian —
%   sumbu-X = nomor frame, sumbu-Y = DT (detik). Garis rata = ideal.
%   Frame ber-DT anomali (jauh dari modus) DITANDAI MERAH.
%
%   TAHAP 2 (menyusul): mengekstrak koleksi frame dengan DT SERAGAM
%   (mengambil subset foto ber-interval sama). Tombol placeholder sudah
%   disiapkan di kolom kanan.
%
%   LAYOUT 3 KOLOM (meniru PAB4 — lebar kolom PERSIS sama):
%     KIRI   daftar foto (tabel: No | berkas | DT(s)) + folder picker
%     TENGAH axMain = plot Cartesian DT vs frame (garis + titik)
%     KANAN  tombol-tombol kontrol
%
%   ENGINE (dipakai ulang, TAK ditulis ulang):
%     - pivprepRawExifDt(folder, fn1, fn2)  : dt EXIF antar-pasangan foto.
%       Untuk timelapse: fn1 = names(1:end-1), fn2 = names(2:end) → dt(k)
%       adalah selisih waktu foto ke-k dan ke-(k+1).
%
%   Jalankan pab_setup sekali per sesi. SELALU MATLAB R2025b. Tema TERANG.

here = fileparts(mfilename('fullpath'));
addpath(here);
if isempty(which('pivprepRawExifDt'))
    try
        pab_setup();
    catch
    end
end
if isempty(which('pivprepRawExifDt'))
    error('PABIMAGEDT:noEngine', ...
        'Engine pivprepRawExifDt tak di-path. Jalankan pab_setup.');
end

if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
    rootDir = '';
end

%% ----------------------------------------------------------- state
folders  = {};          % daftar folder berisi gambar (root + subfolder)
folderSel = 0;          % indeks folder aktif
rootSel  = rootDir;
names    = {};          % nama berkas gambar folder aktif (terurut)
dtSec    = [];          % dt(k) = t(k+1)-t(k), panjang = numel(names)-1
exInfo   = struct();    % info lengkap pivprepRawExifDt
frameSel = 0;           % baris tabel foto aktif (0 = belum)
busy     = false;

%% ----------------------------------------------------------- figure
% Ukuran & warna PERSIS meniru kerangka PAB4 (pivui.pab4Shell).
WHITE = [1 1 1];
fig = figure('Name', pivui.titleWithVersion('PABIMAGEDT — Plot DT antar-foto (EXIF timelapse)'), ...
    'NumberTitle','off','Color',WHITE, ...
    'Units','pixels','Position',[50 50 1380 820], ...
    'MenuBar','none','ToolBar','figure');
try
    pivui.forceLightTheme(fig);
catch
end

%% ===================== KOLOM KIRI: daftar foto ========================
% Lebar & posisi kolom kiri IDENTIK pnlL PAB4: [0.006 0.01 0.168 0.985].
pnlL = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.006 0.01 0.168 0.985],'Title','Daftar foto (timelapse)', ...
    'FontWeight','bold','BackgroundColor',WHITE);
txtRoot = uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
    'Position',[0.03 0.945 0.94 0.045],'HorizontalAlignment','left', ...
    'FontSize',8,'BackgroundColor',WHITE,'String','(folder: belum dipilih)');
uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
    'Position',[0.03 0.90 0.46 0.045],'String','Pilih Folder…', ...
    'TooltipString','Pilih folder berisi foto timelapse (atau root berisi subfolder).', ...
    'Callback',@(s,e) onPickFolder());
uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
    'Position',[0.51 0.90 0.46 0.045],'String','Segarkan', ...
    'TooltipString','Pindai ulang folder (termasuk subfolder).', ...
    'Callback',@(s,e) onRescan());
% Pemilih folder/eksperimen (bila root punya banyak subfolder gambar).
uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
    'Position',[0.03 0.862 0.30 0.032],'String','Folder:', ...
    'HorizontalAlignment','left','FontSize',8,'BackgroundColor',WHITE);
popFolder = uicontrol('Parent',pnlL,'Style','popupmenu','Units','normalized', ...
    'Position',[0.30 0.858 0.67 0.040],'String',{'(kosong)'}, ...
    'TooltipString','Pilih folder gambar bila root berisi banyak subfolder.', ...
    'Callback',@(s,e) onPickFolderPop());
% Tabel foto: No | berkas | DT(s). Baris anomali diwarnai merah.
imgTable = uitable('Parent',pnlL,'Units','normalized', ...
    'Position',[0.03 0.02 0.94 0.825], ...
    'ColumnName',{'No','Berkas','DT(s)'}, ...
    'ColumnWidth',{34 118 46}, 'ColumnEditable',[false false false], ...
    'RowName',[],'FontSize',9, ...
    'CellSelectionCallback',@(s,e) onImgSelect(e));

%% ===================== KOLOM TENGAH: plot DT (axMain) =================
% Strip judul/status di atas axMain — meniru pnlC PAB4 [0.180 0.895 0.500 0.098].
pnlC = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.180 0.895 0.500 0.098],'BackgroundColor',WHITE);
uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
    'Position',[0.01 0.55 0.98 0.40],'String', ...
    'Plot DT antar-foto — X: nomor frame · Y: interval waktu (detik).', ...
    'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE);
statusLbl = uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
    'Position',[0.01 0.08 0.98 0.42],'String','Pilih folder untuk memulai.', ...
    'HorizontalAlignment','left','FontAngle','italic','ForegroundColor',[0.3 0.3 0.3], ...
    'BackgroundColor',WHITE);

% axMain — geometri PERSIS PAB4 axMain [0.205 0.505 0.455 0.385] tetapi kita
% pakai TINGGI penuh area tengah (plot Cartesian, bukan citra) → naikkan bawah.
axMain = axes('Parent',fig,'Units','normalized', ...
    'Position',[0.235 0.095 0.415 0.760]);
box(axMain,'on'); grid(axMain,'on');
xlabel(axMain,'Nomor frame'); ylabel(axMain,'DT (detik)');
title(axMain,'(belum ada data)');

%% ===================== KOLOM KANAN: tombol kontrol ====================
% Lebar & posisi kolom kanan IDENTIK pnlR PAB4: [0.686 0.010 0.308 0.985].
pnlR = uipanel('Parent',fig,'Units','normalized', ...
    'Position',[0.686 0.010 0.308 0.985],'Title','Kontrol', ...
    'FontWeight','bold','BackgroundColor',WHITE);

% --- Ringkasan DT ---
uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
    'Position',[0.03 0.940 0.94 0.030],'String','Ringkasan interval (DT):', ...
    'HorizontalAlignment','left','FontWeight','bold','BackgroundColor',WHITE);
summaryLbl = uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
    'Position',[0.03 0.800 0.94 0.135],'String','(belum ada data)', ...
    'HorizontalAlignment','left','FontSize',9,'BackgroundColor',WHITE);

% --- Toleransi anomali ---
uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
    'Position',[0.03 0.752 0.60 0.030],'String','Toleransi anomali (± % modus):', ...
    'HorizontalAlignment','left','BackgroundColor',WHITE);
edTol = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
    'Position',[0.64 0.752 0.15 0.032],'String','25', ...
    'TooltipString','Frame di-tandai MERAH bila |dt - modus| > toleransi ini (persen dari modus).', ...
    'Callback',@(s,e) onRedraw());
uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
    'Position',[0.80 0.752 0.10 0.030],'String','%', ...
    'HorizontalAlignment','left','BackgroundColor',WHITE);

% --- Opsi tampilan plot ---
cbMode = uicontrol('Parent',pnlR,'Style','popupmenu','Units','normalized', ...
    'Position',[0.03 0.700 0.60 0.036], ...
    'String',{'Garis + titik','Titik saja (stem)','Batang (bar)'}, ...
    'TooltipString','Gaya plot DT vs frame.', ...
    'Callback',@(s,e) onRedraw());
cbShowMode = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
    'Position',[0.65 0.700 0.33 0.036],'String','Garis modus','Value',1, ...
    'BackgroundColor',WHITE,'Callback',@(s,e) onRedraw());
cbMarkAnom = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
    'Position',[0.03 0.660 0.94 0.036],'String','Tandai frame anomali (merah)', ...
    'Value',1,'BackgroundColor',WHITE,'Callback',@(s,e) onRedraw());

% --- Aksi ---
uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
    'Position',[0.03 0.596 0.46 0.046],'String','↻ Hitung DT', ...
    'FontWeight','bold', ...
    'TooltipString','Baca EXIF semua foto & hitung DT antar-foto.', ...
    'Callback',@(s,e) onCompute());
uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
    'Position',[0.51 0.596 0.46 0.046],'String','💾 Ekspor plot (PNG)', ...
    'TooltipString','Simpan plot DT saat ini ke PNG di folder gambar.', ...
    'Callback',@(s,e) onExportPlot());
uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
    'Position',[0.03 0.544 0.94 0.044],'String','📄 Ekspor tabel DT (CSV)', ...
    'TooltipString','Simpan tabel No/Berkas/DT ke CSV di folder gambar.', ...
    'Callback',@(s,e) onExportCsv());

% --- Placeholder TAHAP 2 (ekstraksi frame DT seragam) ---
uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
    'Position',[0.03 0.470 0.94 0.030],'String','— Tahap 2 (menyusul) —', ...
    'HorizontalAlignment','center','FontAngle','italic', ...
    'ForegroundColor',[0.4 0.4 0.4],'BackgroundColor',WHITE);
uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
    'Position',[0.03 0.418 0.94 0.044],'String','⛏ Ekstrak frame DT seragam…', ...
    'Enable','off', ...
    'TooltipString','TAHAP 2: ambil subset foto ber-interval seragam (belum diimplementasi).', ...
    'Callback',@(s,e) onExtractStub());

%% ----------------------------------------------------------- init
% Saat start: bila belum diberi folder, LANGSUNG minta folder (dialog).
if ~isempty(rootSel)
    scanRoot(rootSel);
else
    onPickFolder();
end

% =====================================================================
%% Callbacks
    function onPickFolder()
        restoreWin = i_minimizeMain(); %#ok<NASGU> minimize jendela utama sebelum dialog
        d = uigetdir(i_pickStart(), 'Pilih folder foto timelapse (atau root)');
        clear restoreWin;                % restore jendela utama sesudah dialog (onCleanup)
        if isequal(d,0); return; end
        scanRoot(d);
    end

    function c = i_minimizeMain()
        % ATURAN GLOBAL: minimize jendela utama sebelum dialog berkas
        % (uigetdir/uigetfile/uiputfile), restore sesudah — via onCleanup
        % supaya tetap pulih walau dialog dibatalkan/error. Senyap saat tes.
        c = [];
        if pivui.quiet(); return; end
        try
            prev = fig.WindowState;
            fig.WindowState = 'minimized'; drawnow;
            c = onCleanup(@() i_restoreWin(prev));
        catch
        end
    end

    function i_restoreWin(prev)
        try
            if ~ishghandle(fig); return; end
            if isempty(prev) || strcmp(prev,'minimized'); prev = 'normal'; end
            fig.WindowState = prev; drawnow;
            figure(fig);
        catch
        end
    end

    function onRescan()
        if isempty(rootSel); onPickFolder(); return; end
        scanRoot(rootSel);
    end

    function onPickFolderPop()
        k = get(popFolder,'Value');
        if k>=1 && k<=numel(folders); activateFolder(k); end
    end

    function onImgSelect(ev)
        if isempty(ev.Indices); return; end
        frameSel = ev.Indices(1);
        redrawPlot();   % sorot frame terpilih di plot
    end

    function onCompute()
        if folderSel==0; setStatus('Belum ada folder aktif.'); return; end
        activateFolder(folderSel);   % baca EXIF + hitung dt + render
    end

    function onRedraw()
        redrawPlot();
    end

    function onExportPlot()
        if isempty(dtSec); setStatus('Belum ada data DT untuk diekspor.'); return; end
        fld = folders{folderSel};
        fn = fullfile(fld, sprintf('%s_DTplot.png', i_folderTag(fld)));
        try
            f2 = figure('Visible','off','Color',WHITE,'Position',[0 0 1000 500]);
            ax2 = axes('Parent',f2);
            drawInto(ax2);
            exportgraphics(ax2, fn, 'Resolution', 150);
            close(f2);
            setStatus(sprintf('Plot disimpan: %s', fn));
        catch err
            if exist('f2','var') && ishandle(f2); close(f2); end
            setStatus(['Gagal ekspor plot: ' err.message]);
        end
    end

    function onExportCsv()
        if isempty(names); setStatus('Belum ada data untuk diekspor.'); return; end
        fld = folders{folderSel};
        fn = fullfile(fld, sprintf('%s_DT.csv', i_folderTag(fld)));
        try
            no = (1:numel(names))';
            dtCol = [dtSec(:); NaN];            % foto terakhir tak punya dt maju
            dtCol = dtCol(1:numel(names));
            T = table(no, string(names(:)), dtCol, ...
                'VariableNames', {'No','Berkas','DT_s'});
            writetable(T, fn);
            setStatus(sprintf('Tabel disimpan: %s', fn));
        catch err
            setStatus(['Gagal ekspor CSV: ' err.message]);
        end
    end

    function onExtractStub()
        uialertBox(['TAHAP 2 belum diimplementasi.\n\n' ...
            'Rencana: pilih modus DT, lalu ambil subset foto yang ' ...
            'ber-interval seragam (mendekati modus) supaya interval ' ...
            'semua foto menjadi sama.']);
    end

% =====================================================================
%% Core
    function scanRoot(root)
        rootSel = root;
        set(txtRoot,'String', i_short(root, 46));
        setStatus('Memindai folder…'); drawnow;
        folders = i_findImageFolders(root);
        if isempty(folders)
            folders = {}; folderSel = 0;
            set(popFolder,'String',{'(tak ada folder gambar)'},'Value',1);
            set(imgTable,'Data',{});
            names = {}; dtSec = []; frameSel = 0;
            cla(axMain); title(axMain,'(tak ada gambar)');
            setStatus('Tak ada folder berisi gambar di bawah root ini.');
            return;
        end
        labels = cell(size(folders));
        for k = 1:numel(folders); labels{k} = i_folderLabel(folders{k}, root); end
        set(popFolder,'String',labels,'Value',1);
        activateFolder(1);
    end

    function activateFolder(k)
        if k<1 || k>numel(folders); return; end
        if busy; return; end
        busy = true; c = onCleanup(@() setBusy(false));
        folderSel = k;
        set(popFolder,'Value',k);
        fld = folders{k};
        setStatus('Membaca EXIF & menghitung DT…'); drawnow;

        names = i_listImgs(fld);
        if numel(names) < 2
            dtSec = []; frameSel = 0;
            set(imgTable,'Data', i_tableData(names, []));
            cla(axMain); title(axMain,'(butuh >= 2 foto)');
            setStatus(sprintf('Folder hanya %d foto — butuh >= 2 untuk DT.', numel(names)));
            set(summaryLbl,'String','(butuh >= 2 foto)');
            return;
        end

        % dt antar-foto berurutan: dt(k) = t(k+1) - t(k).
        fn1 = names(1:end-1); fn2 = names(2:end);
        exInfo = pivprepRawExifDt(fld, fn1, fn2);
        dtSec = exInfo.dt_s(:)';           % panjang = numel(names)-1

        set(imgTable,'Data', i_tableData(names, dtSec));
        frameSel = 0;
        redrawPlot();
        updateSummary();
        setStatus(sprintf('%s — %d foto, %d DT valid (%s).', ...
            exInfo.status, numel(names), exInfo.n_valid, i_msgShort(exInfo)));
    end

    function updateSummary()
        if isempty(dtSec) || all(isnan(dtSec))
            set(summaryLbl,'String','(dt EXIF tak terbaca)'); return;
        end
        d = dtSec(isfinite(dtSec));
        md = i_modeApprox(dtSec);
        tol = i_tolFrac();
        nAnom = nnz(i_anomMask());
        s = sprintf(['Modus  : %.3g s\n' ...
                     'Median : %.3g s\n' ...
                     'Min–Max: %.3g – %.3g s\n' ...
                     'Rentang: %.3g s\n' ...
                     'Anomali: %d frame (> %.0f%%)'], ...
            md, median(d), min(d), max(d), max(d)-min(d), nAnom, tol*100);
        set(summaryLbl,'String', s);
    end

    function redrawPlot()
        cla(axMain);
        if isempty(dtSec) || all(isnan(dtSec))
            title(axMain,'(dt EXIF tak terbaca)'); return;
        end
        drawInto(axMain);
        updateSummary();
    end

    function drawInto(ax)
        % Gambar plot DT vs frame ke sumbu `ax` (dipakai layar & ekspor).
        cla(ax); hold(ax,'on');
        x = 1:numel(dtSec);
        y = dtSec(:)';
        md = i_modeApprox(dtSec);
        style = get(cbMode,'Value');
        col = [0.10 0.35 0.75];

        switch style
            case 2   % titik saja (stem)
                stem(ax, x, y, 'filled', 'Color', col, 'MarkerFaceColor', col, ...
                    'MarkerSize', 4);
            case 3   % batang
                bar(ax, x, y, 0.7, 'FaceColor', [0.55 0.70 0.90], 'EdgeColor', col);
            otherwise % garis + titik
                plot(ax, x, y, '-o', 'Color', col, 'MarkerFaceColor', col, ...
                    'MarkerSize', 3.5, 'LineWidth', 1.0);
        end

        % Garis modus (interval ideal).
        if get(cbShowMode,'Value') && isfinite(md)
            plot(ax, [x(1) x(end)], [md md], '--', 'Color', [0.2 0.6 0.2], ...
                'LineWidth', 1.2);
        end

        % Tandai frame anomali MERAH.
        if get(cbMarkAnom,'Value')
            m = i_anomMask();
            if any(m)
                plot(ax, x(m), y(m), 'o', 'MarkerEdgeColor',[0.85 0 0], ...
                    'MarkerFaceColor',[0.95 0.3 0.3], 'MarkerSize', 7, 'LineWidth', 1.2);
            end
        end

        % Sorot frame terpilih (dari tabel foto). Frame k tabel -> dt index k
        % (dt maju foto-k). Foto terakhir tak punya dt maju.
        if frameSel>=1 && frameSel<=numel(dtSec) && isfinite(dtSec(frameSel))
            plot(ax, frameSel, dtSec(frameSel), 'o', 'MarkerEdgeColor',[0 0 0], ...
                'MarkerFaceColor','none', 'MarkerSize', 11, 'LineWidth', 1.5);
        end

        hold(ax,'off'); box(ax,'on'); grid(ax,'on');
        xlabel(ax,'Nomor frame'); ylabel(ax,'DT (detik)');
        xlim(ax, [0.5, numel(dtSec)+0.5]);
        if isfinite(md) && md>0
            title(ax, sprintf('DT antar-foto — modus %.3g s', md));
        else
            title(ax, 'DT antar-foto');
        end
    end

% =====================================================================
%% Helpers
    function tf = i_tolFrac()
        v = str2double(get(edTol,'String'));
        if ~isfinite(v) || v < 0; v = 25; set(edTol,'String','25'); end
        tf = v/100;
    end

    function m = i_anomMask()
        m = false(1, numel(dtSec));
        if isempty(dtSec); return; end
        d = dtSec(:)';
        md = i_modeApprox(d);
        if ~isfinite(md) || md==0; return; end
        tol = i_tolFrac();
        m = isfinite(d) & (abs(d - md) > max(0.5, tol*abs(md)));
    end

    function D = i_tableData(nm, dt)
        n = numel(nm);
        D = cell(n, 3);
        for r = 1:n
            D{r,1} = r;
            D{r,2} = nm{r};
            if r <= numel(dt) && isfinite(dt(r))
                D{r,3} = round(dt(r)*1000)/1000;
            else
                D{r,3} = NaN;   % foto terakhir tak punya dt maju
            end
        end
    end

    function setStatus(s)
        set(statusLbl,'String', s); drawnow limitrate;
    end

    function setBusy(tf)
        busy = tf;
    end

    function s = i_pickStart()
        if ~isempty(rootSel) && isfolder(rootSel); s = rootSel; else; s = pwd; end
    end

    function uialertBox(msg)
        msg = strrep(msg,'\n',newline);
        try
            uiwait(msgbox(msg, 'PABIMAGEDT', 'help'));
        catch
            disp(msg);
        end
    end
end

% ============================ fungsi lokal (murni) ====================
function folders = i_findImageFolders(root)
%I_FINDIMAGEFOLDERS  Semua folder di bawah root yang berisi >=2 gambar.
%   Root sendiri diperiksa lebih dulu; lalu subfolder rekursif (lewati folder
%   turunan PIVPrep/output RAW/GS/EXIF).
    folders = {};
    if i_hasImages(root); folders{end+1} = root; end
    try
        d = dir(fullfile(root, '**'));
    catch
        d = dir(root);
    end
    d = d([d.isdir]);
    seen = containers.Map('KeyType','char','ValueType','logical');
    if ~isempty(folders); seen(i_norm(folders{1})) = true; end
    for k = 1:numel(d)
        nm = d(k).name;
        if strcmp(nm,'.') || strcmp(nm,'..'); continue; end
        if any(strcmpi(nm, {'RAW','GS','EXIF'})); continue; end
        p = fullfile(d(k).folder, nm);
        key = i_norm(p);
        if isKey(seen, key); continue; end
        if i_hasImages(p); folders{end+1} = p; seen(key) = true; end %#ok<AGROW>
    end
end

function tf = i_hasImages(folder)
    tf = numel(i_listImgs(folder)) >= 2;
end

function names = i_listImgs(folder)
%I_LISTIMGS  Nama berkas gambar (terurut) di sebuah folder; ekstensi paling
%   umum dipilih (meniru i_listImgs PAB0 tanpa suffix eksplisit). Pencocokan
%   ekstensi CASE-INSENSITIVE (mis. .JPG vs .jpg) via satu pindai `dir`.
    exts = {'.jpg','.jpeg','.tif','.tiff','.png','.bmp'};
    d = dir(folder); d = d(~[d.isdir]);
    if isempty(d); names = {}; return; end
    allNames = {d.name};
    [~,~,e] = cellfun(@fileparts, allNames, 'UniformOutput', false);
    best = {}; bestN = 0;
    for k = 1:numel(exts)
        sel = strcmpi(e, exts{k});
        if nnz(sel) > bestN
            bestN = nnz(sel); best = sort(allNames(sel));
        end
    end
    names = best(:);
end

function md = i_modeApprox(v)
%I_MODEAPPROX  Nilai dt yang PALING SERING muncul (interval seharusnya).
%   Sama semangatnya dgn i_modeApprox PAB0: histogram dt valid, ambil bin
%   modus, kembalikan median nilai di bin itu (robust thd noise sub-detik).
    v = v(isfinite(v));
    md = NaN;
    if isempty(v); return; end
    if isscalar(v); md = v(1); return; end
    rng = max(v) - min(v);
    if rng <= eps; md = median(v); return; end
    nb = max(5, min(50, round(sqrt(numel(v)))));
    edges = linspace(min(v), max(v), nb+1);
    [~,~,bin] = histcounts(v, edges);
    bin(bin==0) = nb;
    [~, dom] = max(accumarray(bin(:), 1, [nb 1]));
    md = median(v(bin==dom));
end

function s = i_msgShort(info)
    s = '';
    if isstruct(info) && isfield(info,'median_dt') && isfinite(info.median_dt)
        s = sprintf('median %.3g s', info.median_dt);
    end
end

function lbl = i_folderLabel(folder, root)
    r = i_rel(folder, root);
    if isempty(r); r = i_folderTag(folder); end
    n = numel(i_listImgs(folder));
    lbl = sprintf('%s  (%d)', r, n);
end

function t = i_folderTag(folder)
    [~, t] = fileparts(strip(folder, 'right', filesep));
    if isempty(t); t = 'folder'; end
end

function r = i_rel(folder, root)
    a = i_norm(folder); b = i_norm(root);
    if strcmp(a, b); r = '.'; return; end
    if startsWith(a, [b filesep]) || startsWith(a, [b '/'])
        r = a(numel(b)+2:end);
    else
        r = folder;
    end
end

function s = i_norm(p)
    s = char(p);
    if numel(s) > 1 && (s(end)==filesep || s(end)=='/'); s(end) = []; end
end

function s = i_short(str, n)
    str = char(str);
    if numel(str) <= n; s = str; return; end
    s = ['…' str(end-n+2:end)];
end
