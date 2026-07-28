classdef grain4Shell
%GRAIN4SHELL  Kerangka GUI BERSAMA ekosistem GRAIN4 (GRAIN4A & GRAIN4B) — namespace
%   `pivui.*`. Membangun tata-letak yang dipakai BERSAMA (panel berkas kiri +
%   axMain skalar/GS/glyph/slider + axPOT POT on-the-fly + panel kanan KOSONG
%   untuk diisi pemanggil) dan MENYEDIAKAN perilaku bersama sebagai METHOD
%   STATIK yang bekerja atas guidata(fig). Inilah yang paling memangkas baris:
%   GRAIN4A/GRAIN4B hanya mengisi panel kanan + memasang HOOK, TANPA menulis ulang
%   axMain/axPOT/sampling POT.
%
%   PRINSIP EMAS GRAIN4: tak ada perhitungan di file GUI — semua di engine pivcore
%   /pivui. Shell ini = perekat panel + pemanggil engine (reuse GRAIN3 yang teruji).
%
%   HOOK (opsional; function handle di opts.hooks / h.hooks, dipanggil aman):
%     onExpLoaded(fig)        setelah eksperimen dimuat + auto-PSG + POT awal
%     onPotChanged(fig)       setelah POT (re)disampel (garis digeser/ditarik/spacing)
%     onLineChanged(fig)      setelah GEOMETRI garis berubah (utk psgId/notes)
%     onCurveClick(fig, r)    kurva ke-r di axPOT diklik
%     onFrameChanged(fig)     frame di-scrub (slider / klik axPOT)
%     decoratePOT(fig)        setelah base renderPOT — pemanggil overlay sendiri
%
%   PEMAKAIAN:
%     h = pivui.grain4Shell.build(struct('Name','GRAIN4A …','rightTitle','Jurnal'));
%     ... isi h.pnlR + set h.hooks ... ; guidata(h.fig, h);
%     pivui.grain4Shell.initIndex(h.fig);
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivui/grain4Shell.m

    methods (Static)

        % =============================================================
        function h = build(opts)
        %BUILD  Bangun figure + tata-letak bersama. Mengembalikan h berisi
        %   SEMUA handle + state default (siap di-guidata oleh pemanggil).
            if nargin < 1, opts = struct(); end
            h = pivui.grain4Shell.defaultState();
            h.hooks = struct();
            if isfield(opts,'hooks') && isstruct(opts.hooks), h.hooks = opts.hooks; end
            name = 'GRAIN4 — ekosistem';
            if isfield(opts,'Name') && ~isempty(opts.Name), name = opts.Name; end
            rightTitle = 'Panel';
            if isfield(opts,'rightTitle') && ~isempty(opts.rightTitle), rightTitle = opts.rightTitle; end

            WHITE = [1 1 1];
            h.fig = figure('Name',name,'NumberTitle','off','Color',WHITE, ...
                'Units','pixels','Position',[50 50 1380 820], ...
                'MenuBar','none','ToolBar','figure');
            pivui.forceLightTheme(h.fig);
            fig = h.fig;

            % --- Panel kiri: folder + tabel eksperimen -------------------
            pnlL = uipanel('Parent',fig,'Units','normalized', ...
                'Position',[0.006 0.01 0.168 0.985],'Title','Berkas PIV (.mat)', ...
                'FontWeight','bold','BackgroundColor',WHITE);
            h.txtRoot = uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
                'Position',[0.03 0.945 0.94 0.045],'HorizontalAlignment','left', ...
                'FontSize',8,'BackgroundColor',WHITE,'String',h.root);
            uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
                'Position',[0.03 0.90 0.46 0.045],'String','Pilih Folder…', ...
                'TooltipString','Pilih folder berisi .mat PIV (output Step 2).', ...
                'Callback',@(s,e) pivui.grain4Shell.onPickFolder(fig));
            uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
                'Position',[0.51 0.90 0.46 0.045],'String','Segarkan', ...
                'TooltipString','Pindai ulang folder (termasuk subfolder PIV_<tgl>/).', ...
                'Callback',@(s,e) pivui.grain4Shell.rescan(fig));
            h.btnLeftMode = uicontrol('Parent',pnlL,'Style','togglebutton','Units','normalized', ...
                'Position',[0.03 0.852 0.70 0.040],'String','Kolom: Eksperimen ⇄ Kurva','Value',0, ...
                'FontSize',8, ...
                'TooltipString',['Tukar isi kolom kiri: daftar EKSPERIMEN (.mat) <-> daftar KURVA POT ' ...
                'garis aktif. Mode Kurva: klik baris -> sorot kurva + tandai posisi sampling.'], ...
                'Callback',@(s,e) pivui.grain4Shell.toggleLeftMode(fig));
            h.btnLeftHelp = uicontrol('Parent',pnlL,'Style','togglebutton','Units','normalized', ...
                'Position',[0.75 0.852 0.22 0.040],'String','❓ Help','Value',0,'FontSize',8, ...
                'TooltipString','Tampilkan daftar HOTKEY di kolom kiri (klik lagi = kembali ke Kurva).', ...
                'Callback',@(s,e) pivui.grain4Shell.toggleHelpMode(fig));
            h.tbl = uitable('Parent',pnlL,'Units','normalized', ...
                'Position',[0.03 0.02 0.94 0.825], ...
                'ColumnName',{'Eksperimen','MB','Frame'}, ...
                'ColumnWidth',{120 36 42}, 'ColumnEditable',[false false false], ...
                'RowName',[],'FontSize',9, ...
                'CellSelectionCallback',@(s,e) pivui.grain4Shell.onSelectRow(fig, e));

            % --- Strip kontrol tampilan (atas axMain, 3 baris) -----------
            pnlC = uipanel('Parent',fig,'Units','normalized', ...
                'Position',[0.180 0.895 0.500 0.098],'BackgroundColor',WHITE);
            h.btnDisp = uicontrol('Parent',pnlC,'Style','togglebutton','Units','normalized', ...
                'Position',[0.01 0.69 0.165 0.27],'String','Vel mag','Value',0, ...
                'FontWeight','bold', ...
                'TooltipString','Tukar bidang skalar axMain: Vel mag <-> Shear strain.', ...
                'Callback',@(s,e) pivui.grain4Shell.onDisp(fig));
            h.txtLo = uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
                'Position',[0.19 0.69 0.06 0.26],'String','min:', ...
                'HorizontalAlignment','right','BackgroundColor',WHITE);
            h.edLo = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
                'Position',[0.255 0.70 0.085 0.26],'String','0', ...
                'TooltipString','Batas bawah warna (velocity).', ...
                'Callback',@(s,e) pivui.grain4Shell.onClim(fig));
            h.txtHi = uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
                'Position',[0.345 0.69 0.06 0.26],'String','max:', ...
                'HorizontalAlignment','right','BackgroundColor',WHITE);
            h.edHi = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
                'Position',[0.41 0.70 0.085 0.26],'String','5', ...
                'TooltipString','Velocity: batas atas. Shear: ±X -> CLim [-X X].', ...
                'Callback',@(s,e) pivui.grain4Shell.onClim(fig));
            uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
                'Position',[0.50 0.69 0.085 0.27],'String','Auto', ...
                'TooltipString','Vel mag: batas atas = maks kurva indenter (bulat 0.5).', ...
                'Callback',@(s,e) pivui.grain4Shell.onAutoClim(fig));
            h.chkGS = uicontrol('Parent',pnlC,'Style','checkbox','Units','normalized', ...
                'Position',[0.60 0.70 0.155 0.26],'String','GS overlay','Value',1, ...
                'BackgroundColor',WHITE, ...
                'TooltipString','Overlay grayscale (abu-abu) di atas bidang skalar.', ...
                'Callback',@(s,e) pivui.grain4Shell.onGS(fig));
            uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
                'Position',[0.76 0.69 0.085 0.25],'String','alpha:', ...
                'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
            h.edAlpha = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
                'Position',[0.85 0.70 0.085 0.26],'String',sprintf('%.2f',h.gsAlpha), ...
                'TooltipString','Transparansi overlay grayscale (0..1).', ...
                'Callback',@(s,e) pivui.grain4Shell.onGS(fig));
            h.chkGlyph = uicontrol('Parent',pnlC,'Style','checkbox','Units','normalized', ...
                'Position',[0.01 0.385 0.10 0.25],'String','Glyph','Value',1, ...
                'BackgroundColor',WHITE,'FontWeight','bold', ...
                'TooltipString','Overlay glyph vektor (panah). DEFAULT ON.', ...
                'Callback',@(s,e) pivui.grain4Shell.onGlyph(fig));
            uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
                'Position',[0.155 0.385 0.05 0.24],'String','tebal:', ...
                'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
            h.edGlyphLW = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
                'Position',[0.20 0.40 0.055 0.24],'String',sprintf('%g',h.glyphLW), ...
                'TooltipString','Tebal garis glyph (default 1.2).', ...
                'Callback',@(s,e) pivui.grain4Shell.onGlyph(fig));
            uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
                'Position',[0.26 0.385 0.07 0.24],'String','spacing:', ...
                'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
            h.edGlyphSp = uicontrol('Parent',pnlC,'Style','edit','Units','normalized', ...
                'Position',[0.335 0.40 0.05 0.24],'String',sprintf('%g',h.glyphSp), ...
                'TooltipString','Spacing glyph: ambil tiap-N node (default 3).', ...
                'Callback',@(s,e) pivui.grain4Shell.onGlyph(fig));
            h.chkCLAHE = uicontrol('Parent',pnlC,'Style','checkbox','Units','normalized', ...
                'Position',[0.42 0.385 0.18 0.25],'String','CLAHE','Value',1, ...
                'BackgroundColor',WHITE, ...
                'TooltipString','CLAHE: kontras lokal adaptif GS. DEFAULT ON.', ...
                'Callback',@(s,e) pivui.grain4Shell.onGS(fig));
            h.chkAdj = uicontrol('Parent',pnlC,'Style','checkbox','Units','normalized', ...
                'Position',[0.61 0.385 0.36 0.25],'String','Auto kontras+brightness', ...
                'Value',1,'BackgroundColor',WHITE, ...
                'TooltipString','Regang intensitas GS ke rentang optimum. DEFAULT ON.', ...
                'Callback',@(s,e) pivui.grain4Shell.onGS(fig));
            uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
                'Position',[0.01 0.06 0.075 0.24],'String','Frame:', ...
                'HorizontalAlignment','left','BackgroundColor',WHITE);
            h.sldFrame = uicontrol('Parent',pnlC,'Style','slider','Units','normalized', ...
                'Position',[0.09 0.07 0.375 0.23],'Min',1,'Max',2,'Value',1, ...
                'SliderStep',[1 10]/1, ...
                'TooltipString','Geser men-scrub bingkai citra axMain.', ...
                'Callback',@(s,e) pivui.grain4Shell.onFrameSlider(fig));
            % Tombol mundur/maju 1 frame — langkah dari h.frame (BUKAN nilai slider
            % yg bisa basi setelah klik kurva). Hotkey: Ctrl+< / Ctrl+>.
            uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
                'Position',[0.470 0.065 0.075 0.25],'String','<< f', ...
                'FontWeight','bold','FontSize',8, ...
                'TooltipString','Bingkai SEBELUMNYA. Hotkey: Ctrl+, (−1) / Ctrl+< (−5).', ...
                'Callback',@(s,e) pivui.grain4Shell.stepFrame(fig,-1));
            uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
                'Position',[0.550 0.065 0.075 0.25],'String','f >>', ...
                'FontWeight','bold','FontSize',8, ...
                'TooltipString','Bingkai BERIKUTNYA. Hotkey: Ctrl+. (+1) / Ctrl+> (+5).', ...
                'Callback',@(s,e) pivui.grain4Shell.stepFrame(fig,+1));
            h.txtFrame = uicontrol('Parent',pnlC,'Style','text','Units','normalized', ...
                'Position',[0.630 0.06 0.075 0.24],'String','f 1/1', ...
                'HorizontalAlignment','left','BackgroundColor',WHITE,'FontSize',8);
            uicontrol('Parent',pnlC,'Style','pushbutton','Units','normalized', ...
                'Position',[0.708 0.065 0.140 0.25],'String','Muat semua', ...
                'TooltipString','Muat seluruh bingkai -> slider men-scrub citra.', ...
                'Callback',@(s,e) pivui.grain4Shell.onLoadFull(fig));
            h.btnGlyphColor = uicontrol('Parent',pnlC,'Style','togglebutton','Units','normalized', ...
                'Position',[0.855 0.065 0.10 0.25],'String','Panah ⬛','Value',0, ...
                'TooltipString','Tukar warna panah glyph: hitam (latar terang) <-> putih (latar gelap).', ...
                'Callback',@(s,e) pivui.grain4Shell.onGlyph(fig));

            % --- axMain (atas) + axPOT (bawah) ---------------------------
            h.axMain = axes('Parent',fig,'Units','normalized', ...
                'Position',[0.205 0.505 0.455 0.385]);
            pivui.lockAxInteractions(h.axMain);
            title(h.axMain,'axMain — pilih eksperimen di kiri');
            h.axPOT = axes('Parent',fig,'Units','normalized', ...
                'Position',[0.205 0.065 0.455 0.325]);
            title(h.axPOT,'axPOT — POT analysis (tarik garis PSG di axMain)');
            xlabel(h.axPOT,'Frame'); ylabel(h.axPOT,'|V| (px/frame)');
            % --- AX-AC (Area Curve): 2 panel bertumpuk di area axMain, TERSEMBUNYI.
            %     Toggle menukar axMain <-> AX-AC. Atas=ΔLuas tunggal, bawah=kumulatif.
            % axACtop/axACbot ditumpuk PERSIS di atas axMain (separuh atas & bawah).
            % Saat tersembunyi HARUS non-pickable, kalau tidak menelan klik di area
            % itu -> garis PSG ROI tak bisa diseret di tengah/bawah axMain.
            h.axACtop = axes('Parent',fig,'Units','normalized', ...
                'Position',[0.205 0.715 0.455 0.175],'Visible','off', ...
                'HitTest','off','PickableParts','none');
            h.axACbot = axes('Parent',fig,'Units','normalized', ...
                'Position',[0.205 0.505 0.455 0.175],'Visible','off', ...
                'HitTest','off','PickableParts','none');
            h.mainView = 'main'; h.cbMain = [];

            % --- Strip kontrol POT (antara axMain & axPOT) ---------------
            % (Tombol "Tarik garis PSG" & "Hapus" DIBUANG: garis baru dibuat via
            %  Buka kunci -> geser ROI -> Kunci -> "Simpan garis"; hapus via panel
            %  "Garis PSG tersimpan" -> "Hapus garis".)
            h.btnAxView = uicontrol('Parent',fig,'Style','togglebutton','Units','normalized', ...
                'Position',[0.182 0.432 0.168 0.036],'String','Plot: axMain','Value',0, ...
                'FontWeight','bold', ...
                'TooltipString',['Tukar panel atas: axMain (citra) <-> AX-AC ' ...
                '(ΔLuas antar kurva: tunggal di atas, kumulatif di bawah).'], ...
                'Callback',@(s,e) pivui.grain4Shell.toggleMainView(fig));
            uicontrol('Parent',fig,'Style','text','Units','normalized', ...
                'Position',[0.356 0.430 0.060 0.034],'String','Spacing px:', ...
                'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
            h.edSpacing = uicontrol('Parent',fig,'Style','edit','Units','normalized', ...
                'Position',[0.418 0.432 0.040 0.034],'String','auto', ...
                'BackgroundColor',WHITE,'FontSize',8, ...
                'TooltipString','Spacing sampling (px). "auto" = nodeSpacing data.', ...
                'Callback',@(s,e) pivui.grain4Shell.onSpacing(fig));
            uicontrol('Parent',fig,'Style','text','Units','normalized', ...
                'Position',[0.470 0.430 0.054 0.034],'String','Skala-V:', ...
                'HorizontalAlignment','right','BackgroundColor',WHITE,'FontSize',8);
            Lv = pivcore.pot.vscale.levels();
            h.sldVScale = uicontrol('Parent',fig,'Style','slider','Units','normalized', ...
                'Position',[0.526 0.434 0.064 0.032], ...
                'Min',Lv(1),'Max',Lv(end),'Value',pivcore.pot.vscale.defaultLevel(), ...
                'SliderStep',[0.25 0.5]/(Lv(end)-Lv(1)), ...
                'TooltipString','Skala vertikal axPOT (snap). Sumbu-frame dijaga.', ...
                'Callback',@(s,e) pivui.grain4Shell.onVScale(fig));
            % Kunci garis PSG: TERKUNCI = tak bisa digeser + POT disampel otomatis.
            % Buka kunci = mode EDIT (geser ujung mulus), sampling DITUNDA sampai dikunci lagi.
            h.btnLock = uicontrol('Parent',fig,'Style','togglebutton','Units','normalized', ...
                'Position',[0.596 0.432 0.088 0.036],'String','🔒 Terkunci','Value',1, ...
                'FontWeight','bold', ...
                'TooltipString',['Terkunci: garis PSG TAK bisa digeser & POT disampel otomatis. ' ...
                'Klik untuk BUKA kunci -> geser ujung garis dengan mulus; ' ...
                'sampling POT ditunda sampai dikunci lagi.'], ...
                'Callback',@(s,e) pivui.grain4Shell.onToggleLock(fig));

            % --- Panel kanan: KOSONG untuk diisi pemanggil ---------------
            h.pnlR = uipanel('Parent',fig,'Units','normalized', ...
                'Position',[0.686 0.045 0.308 0.950],'Title',rightTitle, ...
                'FontWeight','bold','BackgroundColor',WHITE);

            % --- Status (strip bawah) ------------------------------------
            h.txtStatus = uicontrol('Parent',fig,'Style','text','Units','normalized', ...
                'Position',[0.180 0.008 0.500 0.03],'HorizontalAlignment','left', ...
                'FontSize',9,'BackgroundColor',WHITE, ...
                'String','Pilih folder lalu sebuah eksperimen dari tabel di kiri.');

            pivui.grain4Shell.syncClimControls(h);
        end


        % =============================================================
        function h = defaultState()
        %DEFAULTSTATE  State numerik/flag awal bersama (mirror GRAIN3).
            cD = pivcore.util.climDefaults();
            gD = pivcore.util.glyphDefaults();
            pD = pivcore.util.potDefaults();
            h = struct();
            h.root       = pwd;
            h.list       = struct('name',{},'file',{},'sizeMB',{},'nFrames',{});
            h.activeRow  = 0;
            h.realData   = '';
            h.data       = [];
            h.fullLoaded = false;
            h.imgFrames  = 1;
            h.recs       = [];
            h.selRows    = [];
            h.nF         = 1;
            h.frame      = 1;
            h.scalarSrc  = 'velocity_magnitude';
            h.climVel    = cD.velCLim;
            h.shearAbs   = cD.shearAbs;
            h.gsOn       = true;
            h.gsAlpha    = 0.5;    % GRAIN4: overlay GS default 0.5 (lebih tebal dari pD.gsAlpha)
            h.claheOn    = true;
            h.adjOn      = true;
            h.glyphOn    = true;
            h.glyphLW    = gD.lineWidth;
            h.glyphSp    = gD.spacing;
            h.glyphColor = [0 0 0];   % warna panah glyph: hitam (default) / putih
            h.xExt       = [];
            h.yExt       = [];
            h.line       = [];
            h.roi        = [];
            h.loadWb     = [];     % handle waitbar muat (dipakai bersama loadExperiment<->ensureFull)
            h.psgLocked  = true;   % garis PSG terkunci (tak bisa digeser) & POT disampel otomatis
            h.psgFrac    = pD.psgFrac;
            h.spacing    = NaN;
            h.indenter   = [];
            h.yBase      = [];
            h.vScale     = 1;
            h.geom       = [];
            h.leftMode   = 'exp';  % kolom kiri: 'exp' (daftar eksperimen) | 'curve' (daftar kurva POT)
            h.lwAssigned = 2.6;    % tebal garis kurva BER-LABEL (HW/F/F0/FFW) — stand out
            h.lwRaw      = 0.6;    % tebal garis kurva MENTAH (belum di-assign) — tipis
            h.viewLock   = false;  % kunci tampilan axPOT (XLim/YLim & skala-V beku saat pindah)
            h.viewLim    = [];     % [xmin xmax ymin ymax] tersimpan saat dikunci
            h.potView    = 'pot';  % plot bawah: 'pot' (kurva POT) | 'slip' (net-slip AXSLIP)
            h.slipHW     = NaN;    % nomor HW yang net-slipnya ditampilkan di AXSLIP
        end


        % =============================================================
        function tf = silent()
        %SILENT  Mode SENYAP untuk tes (delegasi ke pivui.quiet bersama).
            tf = pivui.quiet();
        end


        % =============================================================
        function setRoot(fig, rootDir)
        %SETROOT  Set folder root + segarkan tabel.
            h = guidata(fig);
            h.root = rootDir; set(h.txtRoot,'String',rootDir);
            guidata(fig, h);
            pivui.grain4Shell.initIndex(fig);
        end

        function initIndex(fig), pivui.grain4Shell.rescan(fig); end


        function onPickFolder(fig)
            h = guidata(fig);
            pivui.minimizeForDialog(fig);
            d = uigetdir(h.root, 'Pilih folder berisi .mat PIV (output Step 2)');
            pivui.restoreAfterDialog(fig);
            if isequal(d, 0), return; end
            pivui.grain4Shell.setRoot(fig, d);
        end


        function rescan(fig)
            h = guidata(fig);
            pivui.setStatus(fig, 'Memindai folder…'); set(fig,'Pointer','watch'); drawnow;
            cleaner = onCleanup(@() set(fig,'Pointer','arrow')); %#ok<NASGU>
            if pivui.grain4Shell.silent()
                wb = [];   % tes: tanpa waitbar (tak merebut fokus)
            else
                wb = waitbar(0, 'Memindai folder berisi .mat PIV…', 'Name','GRAIN4');
                pivui.forceLightTheme(wb);
            end
            wbCleaner = onCleanup(@() pivcore.util.safeCloseWb(wb)); %#ok<NASGU>  % tutup walau error
            files = pivanalyzemat.core.scanPivMats(h.root);
            list  = struct('name',{},'file',{},'sizeMB',{},'nFrames',{});
            nF = numel(files);
            for i = 1:nF
                if ishghandle(wb), waitbar(i/max(nF,1), wb, ...
                    sprintf('Memeriksa berkas %d/%d…', i, nF)); end
                [meta, ok] = pivanalyzemat.core.probePivMat(files{i});
                if ~ok, continue; end
                [~, base] = fileparts(files{i});
                list(end+1) = struct('name',base,'file',files{i}, ...
                    'sizeMB',meta.sizeMB,'nFrames',meta.nFrames); %#ok<AGROW>
            end
            h.list = list; guidata(fig, h);
            pivui.grain4Shell.fillTable(fig);
            pivcore.util.safeCloseWb(wb);
            if isempty(list)
                pivui.setStatus(fig, 'Tak ada .mat PIV ditemukan. Coba folder PIV_<tgl>/.');
                return;
            end
            % AUTO-LOAD eksperimen BARIS PERTAMA (default) — KECUALI modul minta
            % OFF via h.noAutoLoadExp (mis. GRAIN5: user pilih exp manual). Field
            % absen -> auto-load (kompat GRAIN4/GRAIN6).
            if isfield(h,'noAutoLoadExp') && h.noAutoLoadExp
                pivui.setStatus(fig, sprintf('%d berkas PIV. Pilih eksperimen di daftar kiri untuk dibuka.', numel(list)));
                return;
            end
            % Langsung tampilkan eksperimen BARIS PERTAMA tanpa perlu disuruh.
            if strcmp(h.leftMode,'exp')
                try, h.tbl.Selection = 1; catch, end   % sorot baris-1 (bila didukung)
                guidata(fig, h);
            end
            pivui.setStatus(fig, sprintf('%d berkas PIV. Menampilkan eksperimen pertama…', numel(list)));
            drawnow;
            pivui.grain4Shell.loadExperiment(fig, 1);
        end


        function fillTable(fig)
        %FILLTABLE  Isi tabel kiri menurut h.leftMode: 'exp' = daftar berkas .mat,
        %   'curve' = daftar kurva POT garis aktif (klik -> sorot + posisi sampling).
            h = guidata(fig);
            if isfield(h,'leftMode') && strcmp(h.leftMode,'help')
                % Mode HELP: tampilkan daftar hotkey (via hook h.helpLines ->
                % cellstr). Bila hook absen -> pesan singkat.
                L = {};
                if isfield(h,'helpLines') && isa(h.helpLines,'function_handle')
                    try, L = h.helpLines(); catch, L = {}; end
                end
                if ~iscell(L) || isempty(L), L = {'(daftar hotkey tak tersedia)'}; end
                C = cell(numel(L),1); for i=1:numel(L), C{i,1} = char(L{i}); end
                set(h.tbl,'ColumnName',{'Hotkey'}, 'ColumnWidth',{'auto'}, 'Data',C);
                return;
            end
            if isfield(h,'leftMode') && strcmp(h.leftMode,'curve')
                recs = h.recs; n = numel(recs); C = cell(n,4);
                dA = pivui.grain4Shell.curveAreas(recs, h.nF);   % ΔLuas antar-kurva
                for i = 1:n
                    num = pivui.grain4Shell.curveNum(recs(i), i);   % nomor saja (tanpa P-)
                    lbl = pivcore.pot.records.label(recs(i));
                    if isfield(recs(i),'cutManual') && isscalar(recs(i).cutManual) && recs(i).cutManual
                        lbl = [lbl '*'];   % * = ter-trim ke max indenter
                    end
                    if pivui.grain4Shell.isExcluded(recs(i))
                        lbl = ['🗑 ' lbl];   % 🗑 = kurva dibuang
                    end
                    px = recs(i).posPx;
                    C{i,1} = num;
                    C{i,2} = ''; if isscalar(px) && isfinite(px), C{i,2} = sprintf('%.0f', px); end
                    C{i,3} = lbl;
                    C{i,4} = ''; if isfinite(dA(i)), C{i,4} = sprintf('%.0f', dA(i)); end
                end
                set(h.tbl,'ColumnName',{'#','posPx','Label','ΔLuas'}, ...
                    'ColumnWidth',{36 46 58 56}, 'Data',C);
            else
                % Kolom EXTRA opsional per-modul via hook h.expTableExtra =
                %   @(dataFile)->{names(cellstr), values(cellstr per-exp)} atau
                %   @(dataFile)->{val1,val2,...} per-exp. Bila absen -> 3 kolom
                %   standar (kompat GRAIN4/GRAIN6). GRAIN5 pakai utk jumlah F# id/checklist.
                hasExtra = isfield(h,'expTableExtra') && isa(h.expTableExtra,'function_handle');
                extraNames = {};
                if hasExtra
                    try, extraNames = h.expTableExtra('__names__'); catch, extraNames = {}; end
                    if ~iscell(extraNames), extraNames = {}; end
                end
                nE = numel(extraNames);
                n = numel(h.list); C = cell(n, 3+nE);
                for i = 1:n
                    C{i,1} = h.list(i).name;
                    C{i,2} = sprintf('%.0f', h.list(i).sizeMB);
                    C{i,3} = num2str(h.list(i).nFrames);
                    if nE > 0
                        vals = {};
                        try, vals = h.expTableExtra(h.list(i).file); catch, vals = {}; end
                        for k = 1:nE
                            v = ''; if iscell(vals) && numel(vals)>=k, v = vals{k}; end
                            C{i,3+k} = v;
                        end
                    end
                end
                % PLACEHOLDER: isi baris kosong agar grid tabel PENUH sampai
                %   bawah (tak menggantung setengah saat exp sedikit). Estimasi
                %   kapasitas baris dari tinggi tabel (px) / tinggi baris (~18px).
                nPad = pivui.grain4Shell.padRowsToFill(h.tbl, n);
                if nPad > 0
                    Cpad = repmat({''}, nPad, 3+nE);
                    C = [C; Cpad];
                end
                cn = [{'Eksperimen','MB','Frame'} extraNames(:).'];
                % Kolom exp dipersempit sedikit saat ada kolom extra (beri ruang).
                w1 = 120; if nE > 0, w1 = 104; end
                % Kolom extra: default 38px; kolom EXTRA TERAKHIR 'auto' (bisa
                % memuat rincian per-PSG mis. "16 (6+5+5)" tanpa terpotong).
                extraW = repmat({38}, 1, nE);
                if nE > 0, extraW{nE} = 'auto'; end
                cw = [{w1 34 40} extraW];
                set(h.tbl,'ColumnName',cn,'ColumnWidth',cw,'Data',C);
            end
        end


        function toggleLeftMode(fig)
            h = guidata(fig);
            if isfield(h,'leftMode') && strcmp(h.leftMode,'exp')
                h.leftMode = 'curve';
            else
                h.leftMode = 'exp';
            end
            guidata(fig, h);
            pivui.grain4Shell.fillTable(fig);
            if strcmp(h.leftMode,'curve')
                pivui.setStatus(fig, ['Kolom kiri: KURVA POT. Klik (ctrl/shift = MULTI) -> sorot ' ...
                    'semua di axPOT; "✂ Trim" memproses semua kurva terpilih.']);
            else
                pivui.setStatus(fig, 'Kolom kiri: EKSPERIMEN. Klik baris -> muat eksperimen.');
            end
        end


        function toggleHelpMode(fig)
        %TOGGLEHELPMODE  Kolom kiri: HELP (daftar hotkey) <-> KURVA. Klik saat mode
        %   help aktif -> kembali ke kurva.
            h = guidata(fig);
            if isfield(h,'leftMode') && strcmp(h.leftMode,'help')
                h.leftMode = 'curve';
            else
                h.leftMode = 'help';
            end
            guidata(fig, h);
            if isfield(h,'btnLeftHelp') && ishghandle(h.btnLeftHelp)
                set(h.btnLeftHelp,'Value', double(strcmp(h.leftMode,'help')));
            end
            pivui.grain4Shell.fillTable(fig);
            if strcmp(h.leftMode,'help')
                pivui.setStatus(fig, 'Kolom kiri: DAFTAR HOTKEY. Klik ❓ Help lagi untuk kembali.');
            else
                pivui.setStatus(fig, 'Kolom kiri: KURVA POT.');
            end
        end


        function onSelectRow(fig, evt)
            if isempty(evt) || isempty(evt.Indices), return; end
            h = guidata(fig);
            if isfield(h,'leftMode') && strcmp(h.leftMode,'help'), return; end   % help = read-only
            if isfield(h,'leftMode') && strcmp(h.leftMode,'curve')
                % MULTI-SELEKSI: ambil SEMUA baris terpilih (ctrl/shift-klik /
                % rubber-band) -> sorot SEMUA kurva di axPOT + tandai sampling.
                rows = unique(evt.Indices(:,1)).';
                rows = rows(rows>=1 & rows<=numel(h.recs));
                if isempty(rows), return; end
                h.selRows = rows; guidata(fig, h);
                pivui.grain4Shell.highlightSelPOT(fig);
                pivui.grain4Shell.highlightSelAC(fig);
                pivui.grain4Shell.drawSampleMarker(fig);
                if isscalar(rows)
                    pt = h.recs(rows).point; if isempty(pt), pt = sprintf('P-%d', rows); end
                    pivui.setStatus(fig, sprintf('Kurva "%s" (titik %d) terpilih.', pt, rows));
                else
                    pivui.setStatus(fig, sprintf('%d kurva terpilih (Trim akan memproses semuanya).', ...
                        numel(rows)));
                end
                pivui.grain4Shell.callHook(fig, 'onCurveClick', rows(1));
                return;
            end
            row = evt.Indices(1,1);
            if row < 1 || row > numel(h.list), return; end
            pivui.grain4Shell.loadExperiment(fig, row);
        end


        % =============================================================
        function loadExperiment(fig, row)
        %LOADEXPERIMENT  Muat bingkai-1 ringan + reset garis/POT + auto-PSG +
        %   POT awal. Setelah selesai -> hook onExpLoaded. SEBELUM mengganti
        %   dataset -> hook opsional `beforeLoad` (mis. auto-flush progres exp lama
        %   sebelum state di-reset). Kompat GRAIN4: hook absen -> tak ada efek.
            pivui.grain4Shell.callHook(fig, 'beforeLoad');
            h = guidata(fig);
            df = h.list(row).file;
            [~, base] = fileparts(df);

            h.activeRow=row; h.realData=df; h.data=[]; h.fullLoaded=false;
            h.imgFrames=1; h.recs=[]; h.selRows=[]; h.frame=1; h.line=[];
            if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
            h.roi=[]; h.indenter=[];
            % Buka eksperimen BARU -> lepas kunci tampilan axPOT. Kalau tidak,
            % XLim/YLim beku dari eksperimen SEBELUMNYA ikut terbawa (renderPOT
            % menghormati viewLim) -> kurva exp baru tampil di rentang yg salah.
            h.viewLock=false; h.viewLim=[];
            % Selalu mulai di panel axMain (citra) saat buka eksperimen.
            h.mainView='main';
            if isfield(h,'axACtop'), pivui.grain4Shell.setAxShown(h.axACtop,false); end
            if isfield(h,'axACbot'), pivui.grain4Shell.setAxShown(h.axACbot,false); end
            if isfield(h,'axMain'),  set(h.axMain,'Visible','on'); end
            if isfield(h,'btnAxView') && ishghandle(h.btnAxView)
                set(h.btnAxView,'Value',0,'String','Plot: axMain');
            end
            h.geom = pivui.grain4Shell.loadGeom(df);
            % Waitbar MENERUS (dipakai ulang ensureFull) supaya tak terkesan hang.
            if pivui.grain4Shell.silent()
                wb = [];   % tes: tanpa waitbar
            else
                wb = waitbar(0.05, sprintf('Membuka eksperimen %s…', base), 'Name','GRAIN4');
                pivui.forceLightTheme(wb);
            end
            h.loadWb = wb;
            guidata(fig, h);
            pivui.grain4Shell.syncViewLockBtns(fig, false);   % tombol kunci-view ikut reset
            cleanerWb = onCleanup(@() pivui.grain4Shell.closeLoadWb(fig)); %#ok<NASGU>

            pivui.setStatus(fig, sprintf('Memuat bingkai-1: %s …', base));
            set(fig,'Pointer','watch'); drawnow;
            cleaner = onCleanup(@() set(fig,'Pointer','arrow')); %#ok<NASGU>
            if ishghandle(wb), waitbar(0.15, wb, sprintf('Memuat bingkai-1: %s…', base)); end
            try
                data1 = pivcore.io.step1Session.loadFrame1(df);
            catch ME
                pivui.setStatus(fig, sprintf('GAGAL memuat %s: %s', base, ME.message));
                return;
            end

            h = guidata(fig);
            h.data = data1;
            h.imgFrames = pivcore.data.frameCount(data1);
            nfTrue = 1;
            if row >= 1 && row <= numel(h.list)
                nfTrue = pivcore.util.scalarOr(h.list(row).nFrames, 1);
            end
            h.nF = max(1, max(nfTrue, h.imgFrames));
            h.frame = 1;
            x = pivcore.data.safeFrame(data1.x, 1);
            y = pivcore.data.safeFrame(data1.y, 1);
            if ~isempty(x) && ~isempty(y)
                h.xExt = [min(x(:)) max(x(:))]; h.yExt = [min(y(:)) max(y(:))];
            end
            guidata(fig, h);

            pivui.grain4Shell.autoClimFromFrame(fig, 1);
            pivui.grain4Shell.syncFrameSlider(fig);
            if ishghandle(wb), waitbar(0.35, wb, 'Menyiapkan tampilan…'); end
            pivui.grain4Shell.renderMain(fig);
            if ishghandle(wb), waitbar(0.55, wb, 'Memuat semua bingkai + sampling POT…'); end
            pivui.grain4Shell.autoPSG(fig);   % -> ensureFull memakai ulang wb (0.55..0.95)

            if ishghandle(wb), waitbar(1.0, wb, 'Selesai.'); end
            pivui.grain4Shell.callHook(fig, 'onExpLoaded');
            h = guidata(fig);
            pivui.setStatus(fig, sprintf('%s: %d bingkai. Garis PSG OTOMATIS (75%% dari atas) -> POT siap.', ...
                base, h.imgFrames));
        end


        function closeLoadWb(fig)
        %CLOSELOADWB  Tutup waitbar muat bersama (h.loadWb) & bersihkan handle.
            if ~ishghandle(fig), return; end
            h = guidata(fig);
            if isfield(h,'loadWb') && ~isempty(h.loadWb)
                pivcore.util.safeCloseWb(h.loadWb);
                h.loadWb = []; guidata(fig, h);
            end
        end


        function autoPSG(fig)
        %AUTOPSG  Garis PSG horizontal end-to-end di psgFrac (default 75% dari
        %   ATAS) sebagai ROI. MULAI TAK-TERKUNCI & BELUM disampel: user setel
        %   posisi dulu lalu KUNCI -> baru POT disampel (lihat onToggleLock).
            h = guidata(fig);
            if isempty(h.data), return; end
            xE = h.xExt; yE = h.yExt;
            if isempty(xE) || isempty(yE), return; end
            frac = h.psgFrac; if ~(isfinite(frac) && frac>=0 && frac<=1), frac = 0.75; end
            % frac diukur dari ATAS: 0 = tepi atas, 1 = tepi bawah. yE(2)=tepi
            % ATAS tampilan (YDir normal), jadi turun frac*tinggi dari atas.
            yL = yE(2) - frac*(yE(2)-yE(1));
            h.line = struct('p1',[xE(1) yL], 'p2',[xE(2) yL], 'frac',frac);
            h.psgLocked = false;             % MULAI mode EDIT (belum disampel)
            guidata(fig, h);
            if isfield(h,'btnLock') && ishghandle(h.btnLock)
                set(h.btnLock,'Value',0,'String','🔓 Edit');
            end
            pivui.grain4Shell.ensureROI(fig);  % bisa digeser (unlocked)
            pivui.grain4Shell.callHook(fig, 'onLineChanged');
            pivui.setStatus(fig, ['Garis PSG di 75% dari atas (mode EDIT). Setel posisi lalu klik ' ...
                '"🔓 Edit" untuk KUNCI -> POT disampel.']);
        end


        function ensureROI(fig)
            h = guidata(fig);
            if isempty(h.line) || ~ishghandle(h.axMain), return; end
            if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
            roi = pivui.makePsgLineROI(h.axMain, h.line.p1, h.line.p2, ...
                @() pivui.grain4Shell.onROIMoved(fig), ...
                @() pivui.grain4Shell.onROIMoving(fig));
            % Override tebal garis & ukuran titik PSG bila modul menyetelnya
            % (GRAIN5_temp: garis tipis + titik kecil, dpt diatur). Kompat GRAIN4:
            % field absen -> pakai potStyle default (tak diubah).
            try
                if isfield(h,'psgLineWidth') && isscalar(h.psgLineWidth) && h.psgLineWidth>0
                    roi.LineWidth = h.psgLineWidth;
                end
                if isfield(h,'psgMarkerSize') && isscalar(h.psgMarkerSize) && h.psgMarkerSize>0
                    roi.MarkerSize = h.psgMarkerSize;
                end
            catch
            end
            h.roi = roi; guidata(fig, h);
            pivui.grain4Shell.applyLockToROI(fig);
            % PENTING (R2025b): membuat images.roi.Line MEMULIHKAN axes toolbar +
            % interaksi bawaan (zoom/pan/datatip) di figure yg tampil. Toolbar/mode
            % itu mengintersep drag mouse di TENGAH axes -> garis PSG hanya bisa
            % diseret di tepi. lockAxInteractions dipanggil SEBELUM ROI (renderMain)
            % jadi tak berpengaruh; ulangi SETELAH ROI dibuat supaya benar-benar
            % mati & seluruh badan garis bisa diseret.
            pivui.lockAxInteractions(h.axMain);
        end


        function L = currentLine(h)
            roi = [];
            if isfield(h,'roi'), roi = h.roi; end
            L = pivui.currentLineFromROI(roi, h.line);
            % BAWA field frac dari h.line apa adanya (currentLineFromROI hanya
            % membaca p1/p2). frac di-NaN-kan SAAT digeser di onROIMoved, BUKAN
            % di sini — supaya garis auto frac yg belum digeser tetap "frac".
            if ~isempty(L)
                if isstruct(h.line) && isfield(h.line,'frac'), L.frac = h.line.frac;
                else, L.frac = NaN; end
            end
        end


        function onROIMoving(fig)
        %ONROIMOVING  Umpan-balik LANGSUNG saat ujung garis masih ditarik: hanya
        %   sinkronkan geometri h.line (ringan), TANPA sampling POT. Bikin
        %   geseran mulus (tak nge-lag oleh collectPOT tiap gerak).
            h = guidata(fig);
            L = pivui.grain4Shell.currentLine(h);
            if isempty(L), return; end
            L.frac = NaN;
            h.line = L; guidata(fig, h);
        end


        function onROIMoved(fig)
            h = guidata(fig);
            L = pivui.grain4Shell.currentLine(h);
            if isempty(L), return; end
            L.frac = NaN;            % digeser pengguna -> bukan lagi frac murni
            h.line = L; guidata(fig, h);
            pivui.grain4Shell.callHook(fig, 'onLineChanged');
            % Mode EDIT (tak terkunci): JANGAN sampel POT sekarang -> ditunda
            % sampai user mengunci garis (onToggleLock -> collectPOT sekali).
            if isfield(h,'psgLocked') && ~h.psgLocked
                pivui.setStatus(fig, ['Garis disetel (BELUM disampel). ' ...
                    'Klik "🔓 Edit" lagi untuk KUNCI -> POT disampel.']);
                return;
            end
            pivui.grain4Shell.collectPOT(fig);
        end


        function onToggleLock(fig)
        %ONTOGGLELOCK  Tombol kunci garis PSG. Terkunci -> sampel POT sekarang.
        %   Buka kunci -> mode edit (geser ujung mulus, sampling ditunda).
            h = guidata(fig);
            locked = true;
            if isfield(h,'btnLock') && ishghandle(h.btnLock)
                locked = (get(h.btnLock,'Value') == 1);
            end
            pivui.grain4Shell.setPsgLock(fig, locked);
        end


        function setPsgLock(fig, locked)
            h = guidata(fig);
            h.psgLocked = logical(locked); guidata(fig, h);
            if isfield(h,'btnLock') && ishghandle(h.btnLock)
                set(h.btnLock,'Value', double(h.psgLocked));
                if h.psgLocked, set(h.btnLock,'String','🔒 Terkunci');
                else,           set(h.btnLock,'String','🔓 Edit'); end
            end
            pivui.grain4Shell.applyLockToROI(fig);
            if h.psgLocked
                % Mengunci = sampel POT sekali dari posisi garis terakhir.
                if ~isempty(h.line)
                    pivui.grain4Shell.collectPOT(fig);
                    pivui.setStatus(fig, 'Garis PSG DIKUNCI -> POT disampel.');
                else
                    pivui.setStatus(fig, 'Garis PSG terkunci (belum ada garis).');
                end
            else
                pivui.setStatus(fig, ['Mode EDIT: seret ujung garis PSG di axMain ' ...
                    '(mulus). Sampling POT ditunda sampai dikunci lagi.']);
            end
        end


        function applyLockToROI(fig)
        %APPLYLOCKTOROI  Selaraskan kebisaan-geser ROI dengan status kunci.
            h = guidata(fig);
            if ~isfield(h,'roi') || isempty(h.roi) || ~isvalid(h.roi), return; end
            locked = ~isfield(h,'psgLocked') || h.psgLocked;
            try
                if locked, h.roi.InteractionsAllowed = 'none';
                else,      h.roi.InteractionsAllowed = 'all'; end
            catch
            end
            % Mode EDIT (tak terkunci): mode figure ZOOM/PAN axMain (GRAIN5 tombol
            % "Zoom axMain") mengintersep SEMUA drag di dalam axes -> garis PSG
            % ROI tak bisa diseret di tengah (hanya lolos di tepi). Zoom & edit-ROI
            % FUNDAMENTAL bentrok; matikan mode figure saat masuk edit supaya
            % seluruh badan garis + kedua ujung bisa diseret. Beri tahu modul agar
            % status tombol zoom-nya ikut sinkron.
            if ~locked
                pivui.clearFigModes(fig);
                pivui.grain4Shell.callHook(fig, 'onPsgEditEnter');
            end
        end


        function onDrawLine(fig)
            h = guidata(fig);
            if isempty(h.data)
                pivui.setStatus(fig, 'Pilih eksperimen dulu sebelum menarik garis.'); return;
            end
            if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
            pivui.clearFigModes(fig);
            pivui.setStatus(fig, 'Seret garis PSG di axMain (klik-tahan ujung ke ujung)…');
            ps = pivui.potStyle().psgLine;
            roi = drawline(h.axMain, 'Color',ps.color, 'LineWidth',ps.lineWidth, ...
                'MarkerSize',ps.markerSize, 'Label','PSG', 'LabelVisible','hover');
            if isempty(roi) || ~isvalid(roi) || isempty(roi.Position)
                guidata(fig, h); pivui.grain4Shell.ensureROI(fig);
                pivui.setStatus(fig, 'Batal menarik garis (garis lama dipulihkan).'); return;
            end
            h.line = struct('p1',roi.Position(1,:), 'p2',roi.Position(2,:), 'frac',NaN);
            delete(roi);                    % ganti dgn ROI ber-wiring penuh (moving+lock)
            guidata(fig, h);
            pivui.grain4Shell.ensureROI(fig); % rebuild ROI di posisi sama
            pivui.grain4Shell.callHook(fig, 'onLineChanged');
            % Garis baru -> kunci & sampel sekali (tombol kembali ke "Terkunci").
            pivui.grain4Shell.setPsgLock(fig, true);
            pivui.setStatus(fig, 'Garis PSG ditetapkan & disampel. Klik "🔓 Edit" untuk menyetel ujung.');
        end


        function onClearLine(fig)
            h = guidata(fig);
            h.line=[]; h.recs=[]; h.selRows=[]; h.indenter=[];
            if ~isempty(h.roi) && isvalid(h.roi), delete(h.roi); end
            h.roi=[]; guidata(fig, h);
            try, delete(findall(h.axMain,'Tag','psgLine')); catch, end
            try, delete(findall(h.axMain,'Tag','potSampleMarker')); catch, end
            pivui.grain4Shell.renderPOT(fig);
            pivui.grain4Shell.callHook(fig, 'onPotChanged');
            pivui.setStatus(fig, 'Garis PSG dihapus.');
        end


        % =============================================================
        function ok = ensureFull(fig)
            ok = false;
            h = guidata(fig);
            if pivcore.util.isFullLoaded(h) && ~isempty(h.data), ok = true; return; end
            if isempty(h.realData), return; end
            [~, base] = fileparts(h.realData);
            pivui.setStatus(fig, sprintf('Memuat SEMUA bingkai: %s …', base));
            set(fig,'Pointer','watch'); drawnow;
            cleaner = onCleanup(@() set(fig,'Pointer','arrow')); %#ok<NASGU>
            % Pakai ULANG waitbar muat bersama bila ada (loadExperiment) supaya
            % tak ada dua jendela waitbar; selain itu buat sendiri.
            shared = isfield(h,'loadWb') && ~isempty(h.loadWb) && ishghandle(h.loadWb);
            if shared
                wb = h.loadWb; waitbar(0.7, wb, sprintf('Memuat semua bingkai %s…', base));
            elseif pivui.grain4Shell.silent()
                wb = [];   % tes: tanpa waitbar
            else
                wb = waitbar(0.2, sprintf('Memuat semua bingkai %s…', base)); pivui.forceLightTheme(wb);
            end
            try
                data = pivcore.io.step1Session.loadAllFrames(h.realData);
            catch ME
                if ~shared, pivcore.util.safeCloseWb(wb); end
                pivui.setStatus(fig, sprintf('GAGAL memuat semua bingkai: %s', ME.message));
                return;
            end
            if ~shared, pivcore.util.safeCloseWb(wb); end
            h = guidata(fig);
            h.data=data; h.fullLoaded=true; h.imgFrames=pivcore.data.frameCount(data);
            x = pivcore.data.safeFrame(data.x, 1);
            y = pivcore.data.safeFrame(data.y, 1);
            if ~isempty(x) && ~isempty(y)
                h.xExt=[min(x(:)) max(x(:))]; h.yExt=[min(y(:)) max(y(:))];
            end
            guidata(fig, h); ok = true;
        end


        function onLoadFull(fig)
            h = guidata(fig);
            if isempty(h.realData), pivui.setStatus(fig,'Pilih eksperimen dulu.'); return; end
            if ~pivui.grain4Shell.ensureFull(fig), return; end
            pivui.grain4Shell.renderMain(fig);
            h = guidata(fig);
            pivui.setStatus(fig, sprintf('Semua %d bingkai dimuat. Geser slider untuk men-scrub.', ...
                h.imgFrames));
        end


        % =============================================================
        function toggleMainView(fig)
            h = guidata(fig);
            if isfield(h,'mainView') && strcmp(h.mainView,'ac')
                pivui.grain4Shell.setMainView(fig,'main');
            else
                pivui.grain4Shell.setMainView(fig,'ac');
            end
        end


        function setMainView(fig, mode)
        %SETMAINVIEW  Tukar panel atas: 'main' (citra axMain) <-> 'ac' (AX-AC
        %   ΔLuas antar kurva). Sembunyikan axMain+colorbar+ROI saat 'ac'.
            h = guidata(fig);
            if ~any(strcmp(mode,{'main','ac'})), return; end
            h.mainView = mode; guidata(fig, h);
            isAC = strcmp(mode,'ac');
            pivui.grain4Shell.setAxShown(h.axMain, ~isAC);
            if isfield(h,'cbMain') && ~isempty(h.cbMain) && ishghandle(h.cbMain)
                set(h.cbMain,'Visible', pivui.grain4Shell.onoff(~isAC));
            end
            if isfield(h,'roi') && ~isempty(h.roi) && isvalid(h.roi)
                try, h.roi.Visible = pivui.grain4Shell.onoff(~isAC); catch, end
            end
            pivui.grain4Shell.setAxShown(h.axACtop, isAC);
            pivui.grain4Shell.setAxShown(h.axACbot, isAC);
            if isfield(h,'btnAxView') && ishghandle(h.btnAxView)
                set(h.btnAxView,'Value',double(isAC), ...
                    'String', pivui.grain4Shell.tern(isAC,'Plot: AX-AC','Plot: axMain'));
            end
            if isAC
                pivui.grain4Shell.renderAC(fig);
            else
                pivui.grain4Shell.renderMain(fig);
            end
        end


        function renderAC(fig)
        %RENDERAC  Plot AX-AC: atas = ΔLuas tunggal per kurva (bar), bawah =
        %   kumulatif (garis). x = nomor kurva berurutan.
            h = guidata(fig);
            if ~ishghandle(h.axACtop) || ~ishghandle(h.axACbot), return; end
            [dA, cA] = pivui.grain4Shell.curveAreas(h.recs, h.nF);
            idx = 1:numel(dA); gd = isfinite(dA); gc = isfinite(cA);
            axT = h.axACtop; cla(axT); set(axT,'Color','w','Box','on','Layer','top');
            hold(axT,'on');
            if any(gd), bar(axT, idx(gd), dA(gd), 0.8, 'FaceColor',[0.30 0.55 0.85],'EdgeColor','none'); end
            hold(axT,'off'); grid(axT,'on'); ylabel(axT,'ΔLuas (tunggal)');
            title(axT,'AX-AC — ΔLuas antar kurva berurutan','Interpreter','none');
            axB = h.axACbot; cla(axB); set(axB,'Color','w','Box','on','Layer','top');
            hold(axB,'on');
            if any(gc), plot(axB, idx(gc), cA(gc), '-o','Color',[0.85 0.35 0.10], ...
                    'LineWidth',1.6,'MarkerFaceColor','w','MarkerSize',4); end
            hold(axB,'off'); grid(axB,'on');
            xlabel(axB,'# kurva'); ylabel(axB,'ΣΔLuas (kumulatif)');
            if any(gd), xlim(axT,[0.5 numel(dA)+0.5]); xlim(axB,[0.5 numel(dA)+0.5]); end
            pivui.grain4Shell.highlightSelAC(fig);   % sorot kurva terpilih (garis vertikal)
        end


        function setAxShown(ax, shown)
        %SETAXSHOWN  Tampilkan/sembunyikan axes BESERTA anak-anaknya & colorbar.
            if ~ishghandle(ax), return; end
            v = pivui.grain4Shell.onoff(shown);
            set(ax,'Visible',v);
            ch = get(ax,'Children');
            for k = 1:numel(ch), try, set(ch(k),'Visible',v); catch, end, end
            % PENTING: Visible='off' TIDAK mematikan hit-test — axes tersembunyi
            % TETAP menangkap klik mouse. axACtop/axACbot ditumpuk PERSIS di atas
            % axMain (separuh atas & bawah); saat disembunyikan mereka menelan klik
            % di bagian itu -> garis PSG ROI tak bisa diseret di tengah/bawah axMain
            % (klik malah kena axes tersembunyi & memunculkan colorbar sisa). Buang
            % axes tersembunyi dari jalur pick; kembalikan saat ditampilkan.
            isShown = ~(isempty(shown) || isequal(shown,0) || isequal(shown,false));
            if isShown, hitv = 'on';  pv = 'all';
            else,       hitv = 'off'; pv = 'none'; end
            try, set(ax,'HitTest',hitv,'PickableParts',pv); catch, end
            for k = 1:numel(ch)
                try, set(ch(k),'HitTest',hitv,'PickableParts',pv); catch, end
            end
        end

        function s = onoff(tf), if tf, s='on'; else, s='off'; end, end
        function v = tern(tf,a,b), if tf, v=a; else, v=b; end, end


        function renderMain(fig)
        %RENDERMAIN  Skalar+GS+glyph via pivcore.montage.renderScalarPanel
        %   (sumber tunggal bersama montase) + chrome GUI. Identik pola GRAIN3.
            h = guidata(fig);
            % Saat panel atas = AX-AC, jangan gambar axMain (tetap tersembunyi).
            if isfield(h,'mainView') && strcmp(h.mainView,'ac'), return; end
            ax = h.axMain;
            if isempty(h.data), return; end
            L = pivui.grain4Shell.currentLine(h);
            if ~isempty(L), h.line = L; guidata(fig, h); end
            k = max(1, min(pivcore.util.scalarOr(h.frame,1), pivcore.util.scalarOr(h.imgFrames,1)));

            x = pivcore.data.safeFrame(h.data.x, k);
            y = pivcore.data.safeFrame(h.data.y, k);
            if isempty(x) || isempty(y)
                x = pivcore.data.safeFrame(h.data.x, 1);
                y = pivcore.data.safeFrame(h.data.y, 1); k = 1;
            end
            if isempty(x) || isempty(y), return; end
            xExt = [min(x(:)) max(x(:))]; yExt = [min(y(:)) max(y(:))];

            cla(ax); colorbar(ax,'off');
            pivcore.montage.renderScalarPanel(ax, h.data, k, h.scalarSrc, h);

            if strcmp(h.scalarSrc,'shear')
                Z = pivcore.data.computeShearRate(h.data, k, 'mode','engineering');
                lab = 'shear strain (du/dy+dv/dx)';
            else
                [Z, lab] = pivcore.data.resolveScalar(h.data, 'velocity_magnitude', k);
            end
            if ~isempty(Z)
                cb = colorbar(ax); cb.Label.String = lab; h.cbMain = cb; guidata(fig, h);
            else
                text(ax,0.5,0.5,sprintf('Bidang "%s" kosong di bingkai %d', lab, k), ...
                    'Units','normalized','HorizontalAlignment','center');
            end

            set(ax,'YDir','normal'); xlim(ax,xExt); ylim(ax,yExt);
            daspect(ax,[1 1 1]); set(ax,'Layer','top'); box(ax,'on');
            pivui.lockAxInteractions(ax);
            title(ax, sprintf('axMain — %s — bingkai %d/%d', ...
                pivcore.util.baseName(h.realData), k, h.imgFrames), 'Interpreter','none');

            % Sumbu cm (tick X/Y + label + segitiga indenter) bila pemanggil
            % menyediakan kalibrasi ter-cache (h.axCal enabled). Netral utk modul
            % tanpa axCal (field absen -> lewati). Segitiga butuh h.axCalR.dxCm.
            if isfield(h,'axCal') && isstruct(h.axCal) ...
                    && isfield(h.axCal,'enabled') && h.axCal.enabled
                Rc = [];
                if isfield(h,'axCalR'), Rc = h.axCalR; end
                pivcore.export.frameCatalog.applyCmAxes(ax, h.axCal, Rc, k, ...
                    max(1,h.imgFrames), xExt, yExt);
            end

            h.xExt=xExt; h.yExt=yExt; guidata(fig, h);
            if ~isempty(h.line), pivui.grain4Shell.ensureROI(fig); end
            % Label STATE cummulative strain frame aktif (kanan-atas axMain).
            % Sumber tunggal utk GRAIN4/GRAIN5 (keduanya pakai renderMain shell ini).
            pivui.grain4Shell.drawStrainState(fig, ax, k, max(1,h.imgFrames));
            % cla() menghapus overlay pemanggil (anotasi/marker di axMain) ->
            % beri kesempatan menggambar ulang setelah render.
            pivui.grain4Shell.callHook(fig, 'afterRenderMain');
            pivui.grain4Shell.drawSampleMarker(fig);   % posisi sampling kurva terpilih (selalu tampil)
        end


        % =============================================================
        function drawStrainState(fig, ax, k, nF)
        %DRAWSTRAINSTATE  Label state cummulative strain di axMain untuk
        %   bingkai aktif. Isi = "<short> cm · <strain> % · (k/N)"; komponen yg
        %   geom-nya tak tersedia (NaN) DILEWATI, jadi label selalu jujur.
        %
        %   Sumber geom (best-effort) via h.axCalR:
        %     dxCm          -> cummulative shortening = (k-1)/(nF-1)*dxCm  (cm)
        %     strainTotalPct-> cummulative strain     = (k-1)/(nF-1)*total (%)
        %   Frame k/N selalu tampil. Netral utk modul tanpa axCalR (skip 2 komponen).
        %   Posisi label (kiri atas / kanan atas) diatur via h.frameLabelPos.
            if ~ishghandle(ax), return; end
            try, delete(findall(ax,'Tag','strainStateLbl')); catch, end
            h = guidata(fig);
            dxCm = NaN; strTot = NaN;
            if isfield(h,'axCalR') && isstruct(h.axCalR)
                if isfield(h.axCalR,'dxCm'),          dxCm   = pivcore.io.grainAxCal.scal(h.axCalR.dxCm); end
                if isfield(h.axCalR,'strainTotalPct'),strTot = pivcore.io.grainAxCal.scal(h.axCalR.strainTotalPct); end
            end
            frac = 0; if nF > 1, frac = (max(1,k)-1)/(nF-1); end
            parts = {};
            if isfinite(dxCm)   && dxCm   > 0, parts{end+1} = sprintf('%.2f cm', frac*dxCm);   end %#ok<AGROW>
            if isfinite(strTot),               parts{end+1} = sprintf('%.2f %%', frac*strTot); end %#ok<AGROW>
            parts{end+1} = sprintf('(%d/%d)', max(1,k), max(1,nF));
            txt = strjoin(parts, ' · ');

            pos = 'left';
            if isfield(h,'frameLabelPos') && ~isempty(h.frameLabelPos)
                pos = lower(char(h.frameLabelPos));
            end
            if any(strcmp(pos, {'right','kanan','kanan atas','top-right'}))
                posX = 0.985; alignH = 'right';
            elseif any(strcmp(pos, {'off','none','sembunyikan','hidden'}))
                return;
            else
                posX = 0.015; alignH = 'left';
            end

            % Anotasi di data-space (Units normalized axes).
            text(ax, posX, 0.965, txt, 'Units','normalized', ...
                'HorizontalAlignment',alignH, 'VerticalAlignment','top', ...
                'FontSize',11, 'FontWeight','bold', 'Color',[0 0 0], ...
                'BackgroundColor',[1 1 1], 'EdgeColor',[0.35 0.35 0.35], ...
                'Margin',3, 'Clipping','off', 'Interpreter','none', ...
                'Tag','strainStateLbl');
        end


        % =============================================================
        function collectPOT(fig)
        %COLLECTPOT  Sampel POT sepanjang garis aktif (semua bingkai) via
        %   step1Collect (IDENTIK PIVTerry Step 1). Setelah -> hook onPotChanged.
            h = guidata(fig);
            L = pivui.grain4Shell.currentLine(h);
            if ~isempty(L), h.line = L; guidata(fig, h); end
            if isempty(h.line) || isempty(h.realData), return; end
            if ~pivui.grain4Shell.ensureFull(fig), return; end
            h = guidata(fig);

            sp = pivcore.util.scalarOr(h.spacing, NaN);
            if ~(isfinite(sp) && sp > 0)
                dd = pivcore.data.nodeSpacing(h.data);
                if isfinite(dd) && dd > 0, sp = round(dd); else, sp = 10; end
            end

            pivui.setStatus(fig, 'Menyampel POT sepanjang garis PSG…');
            set(fig,'Pointer','watch'); drawnow;
            cleaner = onCleanup(@() set(fig,'Pointer','arrow')); %#ok<NASGU>
            % Buffer band opsional (GRAIN5 set h.bufferMult; GRAIN4/GRAIN6 TANPA field
            % -> bm=0 -> jalur collectAlongLine LAMA IDENTIK). Guard isfield dulu
            % karena mengakses field absen akan error sebelum scalarOr dipanggil.
            bm = 0;
            if isfield(h, 'bufferMult'), bm = pivcore.util.scalarOr(h.bufferMult, 0); end
            try
                if bm > 0
                    recs = pivcore.pot.step1Collect.collectAlongBand( ...
                        h.data, h.line.p1, h.line.p2, sp, 'velocity_magnitude', bm);
                else
                    recs = pivcore.pot.step1Collect.collectAlongLine( ...
                        h.data, h.line.p1, h.line.p2, sp, 'velocity_magnitude');
                end
            catch ME
                pivui.setStatus(fig, sprintf('GAGAL menyampel POT: %s', ME.message)); return;
            end
            recs = pivcore.pot.records.normalize(recs);
            recs = pivcore.pot.records.applyColors(recs);

            h = guidata(fig);
            % Pertahankan label assignment lama bila jumlah & posisi titik sama
            % (mis. setelah seed/labeling 4B, garis tak berubah). Pemanggil yg
            % butuh re-seed menangani via hook onPotChanged.
            h.recs = recs;
            nF = 0; for r=1:numel(recs), nF = max(nF, numel(recs(r).data)); end
            h.nF = max(1, nF);
            guidata(fig, h);
            pivui.grain4Shell.syncFrameSlider(fig);
            pivui.grain4Shell.renderPOT(fig);
            pivui.grain4Shell.climFromIndenter(fig);
            pivui.grain4Shell.callHook(fig, 'onPotChanged');
            if bm > 0
                pivui.setStatus(fig, sprintf(['POT: %d titik sepanjang garis ' ...
                    '(spacing %d px, buffer ×%d = band %d baris).'], ...
                    numel(recs), sp, round(bm), 2*round(bm)+1));
            else
                pivui.setStatus(fig, sprintf('POT: %d titik sepanjang garis (spacing %d px).', ...
                    numel(recs), sp));
            end
        end


        % =============================================================
        function renderPOT(fig)
        %RENDERPOT  Plot bawah. Bila h.potView=='slip' -> AXSLIP (net-slip 1 HW).
        %   Selain itu spaghetti kurva POT: tebal per-KELOMPOK (ber-label tebal /
        %   mentah tipis) + envelope indenter + indikator frame. Klik kurva ->
        %   onCurveClick. Hormati h.viewLock (XLim/YLim beku). Setelah -> hook
        %   decoratePOT (pemanggil overlay titik sendiri).
            h = guidata(fig);
            if isfield(h,'potView') && strcmp(h.potView,'slip')
                pivui.grain4Shell.renderSlip(fig); return;
            end
            ax = h.axPOT; cla(ax);
            set(ax,'Color','w','XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
                'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top');
            hold(ax,'on');

            if isempty(h.recs)
                text(ax,0.5,0.5,'Kunci garis PSG (🔓 Edit) di axMain untuk menyampel POT', ...
                    'Units','normalized','HorizontalAlignment','center','Color',[0.5 0.5 0.5]);
                hold(ax,'off'); xlabel(ax,'Frame'); ylabel(ax,'|V| (px/frame)');
                grid(ax,'on'); title(ax,'axPOT — POT analysis');
                h.indenter=[]; h.yBase=[]; guidata(fig, h);
                pivui.grain4Shell.callHook(fig, 'decoratePOT');
                return;
            end
            lwA = pivcore.util.scalarOr(h.lwAssigned, 2.6);
            lwR = pivcore.util.scalarOr(h.lwRaw, 0.6);
            nF = h.nF;
            % Precompute curveXY tiap kurva SEKALI (movavg mahal) -> reuse di
            % indenterEnvelope + loop plot + highlightSelPOT dalam render ini.
            h.potXYcache = pivui.grain4Shell.potCurveXYAll(h); guidata(fig, h);
            env = pivui.grain4Shell.indenterEnvelope(h);
            ymin=inf; ymax=-inf; nShown=0;
            for r = 1:numel(h.recs)
                if pivui.grain4Shell.isExcluded(h.recs(r)), continue; end  % kurva dibuang
                nShown = nShown + 1;
                [xv,yv] = pivui.grain4Shell.potCurveXY(h, r);       % cache intra-render
                yv = pivui.grain4Shell.applyTrimYV(h.recs(r), yv);  % buang pasca-kontak indenter
                yv = pivui.grain4Shell.dispYV(h, yv);               % transformasi tampil (mis. moving avg)
                g = isfinite(xv) & isfinite(yv); if ~any(g), continue; end
                col = h.recs(r).color; if numel(col)~=3, col=[0.4 0.4 0.4]; end
                if isempty(pivcore.pot.records.label(h.recs(r))), lw = lwR; else, lw = lwA; end
                plot(ax, xv(g), yv(g), '-', 'Color',col, 'LineWidth',lw, ...
                    'UserData',r, 'Tag','potCurve', ...
                    'ButtonDownFcn',@(s,e) pivui.grain4Shell.onCurveClick(fig, s));
                ymin=min(ymin,min(yv(g))); ymax=max(ymax,max(yv(g)));
            end
            if ~isempty(env)
                xe=1:numel(env); ge=isfinite(env);
                if any(ge)
                    plot(ax, xe(ge), env(ge), '-', 'Color',[0 0 0], 'LineWidth',3, ...
                        'Tag','potIndenter','HitTest','off','PickableParts','none');
                    ymin=min(ymin,min(env(ge))); ymax=max(ymax,max(env(ge)));
                end
            end
            hold(ax,'off');
            xlabel(ax,'Frame'); ylabel(ax,'|V| (px/frame)');
            nDel = numel(h.recs) - nShown;
            if nDel > 0
                ttl = sprintf('axPOT — %d kurva (%d dibuang; garis hitam = max indenter)', nShown, nDel);
            else
                ttl = sprintf('axPOT — %d kurva (garis hitam = max indenter)', nShown);
            end
            title(ax, ttl, 'Color',[0 0 0]);
            grid(ax,'on');
            set(ax,'ButtonDownFcn',@(s,e) pivui.grain4Shell.onAxPotClick(fig));
            if isfinite(ymin) && isfinite(ymax) && ymax > ymin, h.yBase=[ymin ymax]; else, h.yBase=[]; end
            h.indenter = env; guidata(fig, h);

            if pivui.grain4Shell.viewIsLocked(h)
                pivui.grain4Shell.applyViewLock(fig);   % XLim/YLim beku
            else
                if nF > 1, xlim(ax,[1 nF]); end
                pivui.grain4Shell.applyVScale(fig);
            end
            pivui.grain4Shell.highlightSelPOT(fig);
            pivui.grain4Shell.updateFrameLine(fig);
            if isfield(h,'leftMode') && strcmp(h.leftMode,'curve')
                pivui.grain4Shell.fillTable(fig);   % daftar kurva ikut termutakhir
            end
            pivui.grain4Shell.callHook(fig, 'decoratePOT');
        end


        % =============================================================
        function renderSlip(fig)
        %RENDERSLIP  AXSLIP: kurva NET-SLIP satu HW (h.slipHW) di plot bawah.
        %   Net-slip = HWₙ − pasangan; NEGATIF auto-dipotong ke 0 (selisih
        %   menyempit -> 0, tak boleh < 0 akibat kurva ter-trim). Titik
        %   Start/NUC/FSR/END digambar oleh hook decoratePOT.
        %
        %   HOOK opsional `slipOverride(fig)->logical`: bila ADA & mengembalikan
        %   TRUE, modul memgambar net-slip versi-nya sendiri (mis. GRAIN5 net-slip
        %   per-SESAR HW−FW) lalu shell BERHENTI. FALSE/absen -> render HW bawaan
        %   ini (GRAIN4 tak punya hook -> perilaku identik).
            h = guidata(fig);
            if isfield(h,'hooks') && isstruct(h.hooks) && isfield(h.hooks,'slipOverride') ...
                    && isa(h.hooks.slipOverride,'function_handle')
                handled = false;
                try, handled = h.hooks.slipOverride(fig); catch ME
                    warning('pivui:grain4Shell:slipOverride','slipOverride gagal: %s', ME.message);
                end
                if isequal(handled, true), return; end
                h = guidata(fig);   % hook mungkin mengubah state -> baca ulang
            end
            ax = h.axPOT; cla(ax);
            set(ax,'Color',[0.99 0.99 0.96],'XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
                'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top');
            hold(ax,'on');
            recsHW = pivui.grain4Shell.recsForHW(h.recs);   % abaikan kurva dibuang
            nums = pivcore.pot.hwLabel.hwNumbers(recsHW);
            num = h.slipHW;
            if ~(isscalar(num) && isfinite(num)) || ~ismember(num, nums)
                if ~isempty(nums), num = nums(1); else, num = NaN; end
            end
            ns = []; nF = h.nF;
            if isfinite(num)
                [A,B,~,okB] = pivcore.pot.hwLabel.pair(recsHW, num, nF);
                if okB
                    sgn = 'signed';
                    if isfield(h,'signConv') && ~isempty(h.signConv), sgn = h.signConv; end
                    ns = pivcore.pot.netslip.netslipVec(A,B);
                    ns = pivcore.pot.netslip.applySign(ns, sgn);
                    ns = pivui.grain4Shell.clipNeg(ns);   % auto-clip negatif -> 0
                end
            end
            if isempty(ns) || ~any(isfinite(ns))
                text(ax,0.5,0.5,'AXSLIP — pilih HW dgn pasangan (≥2 HW / HW+FFW)', ...
                    'Units','normalized','HorizontalAlignment','center','Color',[0.5 0.5 0.5]);
                hold(ax,'off'); xlabel(ax,'Frame'); ylabel(ax,'net-slip (px/frame)');
                grid(ax,'on'); title(ax,'AXSLIP — net-slip'); h.slipHW=num; guidata(fig,h);
                pivui.grain4Shell.callHook(fig, 'decoratePOT'); return;
            end
            xe = 1:numel(ns); g = isfinite(ns);
            col = pivcore.pot.labels.labelColor('HW', num);
            plot(ax, xe(g), ns(g), '-', 'Color',col, 'LineWidth',2.4, 'Tag','slipCurve');
            hold(ax,'off');
            xlabel(ax,'Frame'); ylabel(ax,'net-slip (px/frame, ≥0)');
            title(ax, sprintf('AXSLIP — net-slip HW-%d (negatif dipotong ke 0)', num), 'Color',[0 0 0]);
            grid(ax,'on');
            set(ax,'ButtonDownFcn',@(s,e) pivui.grain4Shell.onAxPotClick(fig));
            yb=[0 max(ns(g))]; if yb(2)<=0, yb(2)=1; end
            h.yBase=yb; h.slipHW=num; guidata(fig, h);
            if pivui.grain4Shell.viewIsLocked(h)
                pivui.grain4Shell.applyViewLock(fig);
            else
                if nF>1, xlim(ax,[1 nF]); end, ylim(ax, yb);
            end
            pivui.grain4Shell.updateFrameLine(fig);
            pivui.grain4Shell.callHook(fig, 'decoratePOT');
        end


        function v = clipNeg(v)
        %CLIPNEG  NaN-aman: nilai < 0 -> 0 (net-slip tak boleh negatif).
            v = double(v); m = isfinite(v) & (v < 0); v(m) = 0;
        end


        function tf = viewIsLocked(h)
            tf = isfield(h,'viewLock') && h.viewLock && isfield(h,'viewLim') ...
                && numel(h.viewLim)==4 && all(isfinite(h.viewLim));
        end


        function applyViewLock(fig)
        %APPLYVIEWLOCK  Set XLim/YLim axPOT ke nilai beku (h.viewLim).
            h = guidata(fig);
            if ~pivui.grain4Shell.viewIsLocked(h) || ~ishghandle(h.axPOT), return; end
            vl = h.viewLim;
            try, xlim(h.axPOT,[vl(1) vl(2)]); ylim(h.axPOT,[vl(3) vl(4)]); catch, end
        end


        function setViewLock(fig, locked)
        %SETVIEWLOCK  Kunci/buka tampilan axPOT. Mengunci = bekukan XLim/YLim
        %   SEKARANG -> pindah kurva/frame tak menggeser layar sampai dibuka.
            h = guidata(fig);
            h.viewLock = logical(locked);
            if h.viewLock && ishghandle(h.axPOT)
                xl = get(h.axPOT,'XLim'); yl = get(h.axPOT,'YLim');
                h.viewLim = [xl(1) xl(2) yl(1) yl(2)];
            end
            guidata(fig, h);
            pivui.grain4Shell.syncViewLockBtns(fig, h.viewLock);
            if h.viewLock
                pivui.setStatus(fig, 'Tampilan axPOT DIKUNCI: pindah kurva/frame tak menggeser layar.');
            else
                pivui.setStatus(fig, 'Tampilan axPOT bebas (skala-V & rentang mengikuti data).');
                pivui.grain4Shell.renderPOT(fig);   % kembalikan ke fit
            end
        end


        function zoomBoxPOT(fig)
        %ZOOMBOXPOT  Zoom-in axPOT dengan TARIK KOTAK (drawrectangle). Set XLim/
        %   YLim ke kotak; otomatis MENGUNCI view supaya zoom bertahan saat
        %   pindah kurva/frame.
            h = guidata(fig);
            if ~ishghandle(h.axPOT) || isempty(h.recs), ...
                pivui.setStatus(fig,'Belum ada kurva untuk di-zoom.'); return; end
            pivui.setStatus(fig, 'Tarik kotak di axPOT untuk ZOOM-IN…'); drawnow;
            try
                rr = drawrectangle(h.axPOT, 'Color',[0.10 0.45 0.90], 'LineWidth',1.0);
            catch
                pivui.setStatus(fig,'Zoom dibatalkan.'); return;
            end
            if isempty(rr) || ~isvalid(rr) || isempty(rr.Position)
                if ~isempty(rr) && isvalid(rr), delete(rr); end   % buang ROI sisa saat batal
                pivui.setStatus(fig,'Zoom dibatalkan.'); return;
            end
            p = rr.Position; delete(rr);     % [x y w h]
            if p(3) <= 0 || p(4) <= 0, pivui.setStatus(fig,'Kotak zoom tak valid.'); return; end
            try
                xlim(h.axPOT,[p(1) p(1)+p(3)]); ylim(h.axPOT,[p(2) p(2)+p(4)]);
            catch
            end
            pivui.grain4Shell.setViewLock(fig, true);   % bekukan zoom
            pivui.setStatus(fig, 'Zoom-in + view DIKUNCI. Pindah kurva/frame aman; buka kunci utk reset.');
        end


        function resetViewPOT(fig)
        %RESETVIEWPOT  Lepas kunci + kembalikan axPOT ke fit penuh.
            pivui.grain4Shell.setViewLock(fig, false);
        end


        function setPotView(fig, mode)
        %SETPOTVIEW  Tukar plot bawah: 'pot' (kurva POT) <-> 'slip' (AXSLIP).
            h = guidata(fig);
            if any(strcmp(mode,{'pot','slip'})), h.potView = mode; end
            % Ganti tampilan -> lepas kunci view (rentang beda).
            h.viewLock = false; h.viewLim = [];
            guidata(fig, h);
            pivui.grain4Shell.syncViewLockBtns(fig, false);
            pivui.grain4Shell.renderPOT(fig);
        end


        function syncViewLockBtns(fig, locked)
        %SYNCVIEWLOCKBTNS  Selaraskan SEMUA tombol kunci-view (ber-Tag
        %   'grain4ViewLock', bisa >1 tab) dgn status kunci.
            b = findall(fig,'Tag','grain4ViewLock');
            if isempty(b), return; end
            set(b,'Value',double(logical(locked)));
            if locked, set(b,'String','🔒 View terkunci');
            else,      set(b,'String','🔓 View bebas'); end
        end


        function setSlipHW(fig, num)
            h = guidata(fig); h.slipHW = num; guidata(fig, h);
            if strcmp(h.potView,'slip'), pivui.grain4Shell.renderPOT(fig); end
        end


        function setLineWidths(fig, lwA, lwR)
        %SETLINEWIDTHS  Set tebal kurva ber-label / mentah lalu render real-time.
            h = guidata(fig);
            if isfinite(lwA) && lwA > 0, h.lwAssigned = lwA; end
            if isfinite(lwR) && lwR > 0, h.lwRaw = lwR; end
            guidata(fig, h);
            pivui.grain4Shell.renderPOT(fig);
        end


        function XY = potCurveXYAll(h)
        %POTCURVEXYALL  Hitung curveXY(rec,nF) SEKALI untuk tiap record -> cell
        %   XY{r} = struct('xv',xv,'yv',yv) (yv = mentah, BELUM trim/disp).
        %   curveXY memanggil movavg yang MAHAL (O(n*w)); dulu dipanggil ~3x
        %   per record per renderPOT (indenterEnvelope + loop plot + highlight).
        %   Precompute ini membuangnya jadi 1x per record per renderPOT.
        %   BYTE-IDENTIK: hanya memoisasi hasil deterministik dari data yg sama.
            XY = {};
            if isempty(h.recs), return; end
            nF = h.nF; n = numel(h.recs);
            XY = cell(1, n);
            for r = 1:n
                [xv,yv] = pivcore.pot.records.curveXY(h.recs(r), nF);
                XY{r} = struct('xv',xv,'yv',yv);
            end
        end


        function [xv,yv] = potCurveXY(h, r)
        %POTCURVEXY  Ambil curveXY record r dari cache intra-render (h.potXYcache)
        %   bila valid; jika absen (mis. dipanggil di luar renderPOT) hitung.
        %   yv = mentah (pemanggil menerapkan applyTrimYV/dispYV sendiri).
            if isfield(h,'potXYcache') && iscell(h.potXYcache) ...
                    && numel(h.potXYcache) == numel(h.recs) ...
                    && r >= 1 && r <= numel(h.potXYcache) ...
                    && ~isempty(h.potXYcache{r}) && isstruct(h.potXYcache{r})
                xv = h.potXYcache{r}.xv; yv = h.potXYcache{r}.yv; return;
            end
            [xv,yv] = pivcore.pot.records.curveXY(h.recs(r), h.nF);
        end


        function env = indenterEnvelope(h)
            env = [];
            if isempty(h.recs), return; end
            nF = h.nF; M = -inf(1,nF); any_=false;
            for r = 1:numel(h.recs)
                if pivui.grain4Shell.isExcluded(h.recs(r)), continue; end  % kurva dibuang
                [~,yv] = pivui.grain4Shell.potCurveXY(h, r);          % cache intra-render
                yv = pivui.grain4Shell.dispYV(h, yv);                % transformasi tampil (moving avg); no-op GRAIN4
                if isempty(yv), continue; end
                m=numel(yv); seg=M(1:m); g=isfinite(yv);
                seg(g)=max(seg(g), yv(g)); M(1:m)=seg; any_=true;
            end
            if ~any_, return; end
            M(~isfinite(M))=NaN; env=M;
        end


        function climFromIndenter(fig)
            h = guidata(fig);
            if isempty(h.indenter), return; end
            mx = max(h.indenter(isfinite(h.indenter)));
            if isempty(mx) || ~isfinite(mx) || mx <= 0, return; end
            hi = pivcore.util.snapClim(mx, 0.5, 'round'); if hi <= 0, return; end
            h.climVel = [0 hi]; guidata(fig, h);
            pivui.grain4Shell.syncClimControls(h);
            if strcmp(h.scalarSrc,'velocity_magnitude') && ~isempty(h.data)
                pivui.grain4Shell.renderMain(fig);
            end
        end


        function updateFrameLine(fig)
            h = guidata(fig); ax = h.axPOT;
            if ~ishghandle(ax), return; end
            try, delete(findall(ax,'Tag','frameLine')); delete(findall(ax,'Tag','frameTxt')); catch, end
            if isempty(h.recs), return; end
            yl = get(ax,'YLim'); k = max(1, min(h.frame, h.nF));
            hs = ishold(ax); hold(ax,'on');
            plot(ax,[k k],yl,'-','Color',[0.10 0.45 0.90],'LineWidth',1.4, ...
                'Tag','frameLine','HitTest','off','PickableParts','none');
            text(ax,k,yl(2),sprintf(' f%d',k),'Color',[0.10 0.45 0.90], ...
                'VerticalAlignment','top','FontSize',8,'FontWeight','bold', ...
                'Tag','frameTxt','HitTest','off','PickableParts','none');
            if ~hs, hold(ax,'off'); end
        end


        function highlightSelPOT(fig)
            h = guidata(fig); ax = h.axPOT;
            if ~ishghandle(ax), return; end
            try, delete(findall(ax,'Tag','selCurve')); catch, end
            rows = h.selRows(:).'; rows = rows(rows>=1 & rows<=numel(h.recs));
            if isempty(rows), return; end
            % Warna sorot: default MERAH; modul boleh override via h.selCurveColor
            % (mis. GRAIN5 = hijau). Kompat GRAIN4: field absen -> merah.
            selCol = [1 0 0];
            if isfield(h,'selCurveColor') && numel(h.selCurveColor)==3, selCol = h.selCurveColor; end
            hs = ishold(ax); hold(ax,'on');
            for r = rows
                if pivui.grain4Shell.isExcluded(h.recs(r)), continue; end  % kurva dibuang
                [xv,yv] = pivui.grain4Shell.potCurveXY(h, r);       % cache intra-render
                yv = pivui.grain4Shell.applyTrimYV(h.recs(r), yv);
                yv = pivui.grain4Shell.dispYV(h, yv);               % transformasi tampil (mis. moving avg)
                g = isfinite(xv)&isfinite(yv); if ~any(g), continue; end
                plot(ax,xv(g),yv(g),'-','Color',selCol,'LineWidth',3.0, ...
                    'Tag','selCurve','HitTest','off','PickableParts','none');
            end
            if ~hs, hold(ax,'off'); end
        end


        function highlightSelAC(fig)
        %HIGHLIGHTSELAC  Sorot kurva terpilih (h.selRows) di plot AX-AC sebagai
        %   garis vertikal pada posisi # kurva (= indeks recs). Hanya aktif saat
        %   panel atas = AX-AC. Dipanggil dari onSelectRow & renderAC.
            h = guidata(fig);
            if ~isfield(h,'mainView') || ~strcmp(h.mainView,'ac'), return; end
            for ax = [h.axACtop h.axACbot]
                if ~ishghandle(ax), continue; end
                try, delete(findall(ax,'Tag','selAC')); catch, end
                rows = h.selRows(:).'; rows = rows(rows>=1 & rows<=numel(h.recs));
                if isempty(rows), continue; end
                yl = get(ax,'YLim'); hs = ishold(ax); hold(ax,'on');
                for r = rows
                    plot(ax,[r r],yl,'-','Color',[1 0 0],'LineWidth',2.0, ...
                        'Tag','selAC','HitTest','off','PickableParts','none');
                end
                if ~hs, hold(ax,'off'); end
            end
        end


        function drawSampleMarker(fig)
        %DRAWSAMPLEMARKER  Tandai di axMain DI MANA kurva POT terpilih disampel
        %   (origin record = titik di sepanjang garis PSG). SELALU tampil saat
        %   ada kurva terpilih; digambar ulang tiap renderMain (cla menghapusnya).
            h = guidata(fig);
            if ~isfield(h,'axMain') || ~ishghandle(h.axMain), return; end
            ax = h.axMain;
            try, delete(findall(ax,'Tag','potSampleMarker')); catch, end
            if isfield(h,'showSampleMarker') && ~h.showSampleMarker, return; end  % gated per-tab oleh pemanggil
            if isempty(h.recs) || isempty(h.selRows), return; end
            rows = h.selRows(:).'; rows = rows(rows>=1 & rows<=numel(h.recs));
            if isempty(rows), return; end
            hs = ishold(ax); hold(ax,'on');
            % Ukuran marker sampling: modul boleh override via h.indMarkerSize
            % (GRAIN5 spinner "titik"). Absen -> 11 (kompat GRAIN4/GRAIN6). Skala +3 dari
            % ukuran indikator supaya sedikit > titik HW/FW tapi tak sebesar 11.
            smSz = 11;
            if isfield(h,'indMarkerSize') && isscalar(h.indMarkerSize) && h.indMarkerSize>0
                smSz = max(3, h.indMarkerSize + 3);
            end
            % Marker bulat di tiap titik sampling terpilih.
            for r = rows
                o = h.recs(r).origin;
                if numel(o)~=2 || ~all(isfinite(o)), continue; end
                col = h.recs(r).color; if numel(col)~=3, col=[1 0 0]; end
                plot(ax, o(1), o(2), 'o', 'MarkerSize',smSz, 'LineWidth',1.4, ...
                    'MarkerEdgeColor',[0 0 0], 'MarkerFaceColor',col, ...
                    'Tag','potSampleMarker','HitTest','off','PickableParts','none');
            end
            % Label PENUNJUK (leader-line) HANYA saat 1 kurva terpilih -> tak
            % berantakan: kotak label tegak lurus di ATAS titik, dekat batas atas
            % plot (margin), dihubungkan garis tipis.
            if isscalar(rows)
                r = rows; o = h.recs(r).origin;
                if numel(o)==2 && all(isfinite(o))
                    yl = get(ax,'YLim'); rng = yl(2)-yl(1);
                    labelY = yl(2) - 0.05*rng;            % margin ~5% dari batas atas
                    if labelY > o(2) + 0.02*rng           % titik cukup di bawah label
                        plot(ax, [o(1) o(1)], [o(2) labelY], '-', ...
                            'Color',[0.25 0.25 0.25], 'LineWidth',0.8, ...
                            'Tag','potSampleMarker','HitTest','off','PickableParts','none');
                        pt = h.recs(r).point; if isempty(pt), pt = sprintf('P-%d', r); end
                        lbl = pivcore.pot.records.label(h.recs(r));
                        if ~isempty(lbl), pt = sprintf('%s · %s', lbl, pt); end
                        text(ax, o(1), labelY, pt, 'Color',[0 0 0], 'FontSize',8, ...
                            'FontWeight','bold', 'HorizontalAlignment','center', ...
                            'VerticalAlignment','top', 'Margin',2, ...
                            'BackgroundColor',[1 1 1], 'EdgeColor',[0.4 0.4 0.4], ...
                            'Tag','potSampleMarker','HitTest','off','PickableParts','none');
                    end
                end
            end
            if ~hs, hold(ax,'off'); end
        end


        % =============================================================
        % Trim kurva POT ke max indenter (non-destruktif)
        % =============================================================
        function yv = applyTrimYV(rec, yv)
        %APPLYTRIMYV  NaN-kan deret tampil `yv` SETELAH frame potong bila record
        %   ditandai trim (cutManual + cutFrame beku). No-op bila tak ditandai.
            if ~(isstruct(rec) && isfield(rec,'cutManual') && isscalar(rec.cutManual) ...
                    && logical(rec.cutManual)), return; end
            df = NaN;
            if isfield(rec,'cutFrame') && isscalar(rec.cutFrame) && isfinite(rec.cutFrame)
                df = rec.cutFrame;
            end
            if isfinite(df) && df >= 1 && df < numel(yv), yv(df+1:end) = NaN; end
        end


        function yv = dispYV(h, yv)
        %DISPYV  Transformasi TAMPIL opsional pada deret `yv` (SETELAH applyTrimYV).
        %   Bila state h punya function handle `h.curveTransform`, terapkan
        %   (mis. GRAIN5 moving-average). GRAIN4 tak set field ini -> no-op IDENTIK.
        %   Aman (try): bug transform tak merusak render.
            if isstruct(h) && isfield(h,'curveTransform') ...
                    && isa(h.curveTransform,'function_handle')
                try, yv = h.curveTransform(yv); catch, end
            end
        end


        function trimSelectedToIndenter(fig)
        %TRIMSELECTEDTOINDENTER  Tandai kurva terpilih utk DIPOTONG di titik
        %   sentuh max indenter (non-destruktif): bagian PASCA-KONTAK dibuang.
            h = guidata(fig);
            rows = h.selRows(:).'; rows = rows(rows>=1 & rows<=numel(h.recs));
            if isempty(rows)
                pivui.setStatus(fig,'Pilih kurva dulu (klik kurva di axPOT / daftar), lalu Trim.'); return;
            end
            env = h.indenter; if isempty(env), env = pivui.grain4Shell.indenterEnvelope(h); end
            if isempty(env), pivui.setStatus(fig,'Max indenter belum ada (belum ada kurva).'); return; end
            opt = struct('minHeightFrac',0.70, 'tolFrac',0.01, 'minHold',1);
            nHit = 0;
            for r = rows
                [~, yv] = pivcore.pot.records.curveXY(h.recs(r), h.nF);
                [~, dieF] = pivcore.pot.hw0Clean.cutAtIndenter(yv, env, opt);
                h.recs(r).cutManual = true;
                h.recs(r).cutFrame  = dieF;
                if isfinite(dieF), nHit = nHit + 1; end
            end
            guidata(fig, h);
            pivui.grain4Shell.renderPOT(fig);
            pivui.grain4Shell.drawSampleMarker(fig);
            pivui.grain4Shell.callHook(fig, 'onPotChanged');
            pivui.setStatus(fig, sprintf('Trim ke max indenter: %d kurva (%d menyentuh indenter).', ...
                numel(rows), nHit));
        end


        function clearTrimSelected(fig)
        %CLEARTRIMSELECTED  Batalkan trim kurva terpilih (atau SEMUA bila tak ada
        %   seleksi) -> kembali utuh.
            h = guidata(fig);
            rows = h.selRows(:).'; rows = rows(rows>=1 & rows<=numel(h.recs));
            scope = 'terpilih';
            if isempty(rows), rows = 1:numel(h.recs); scope = 'semua'; end
            for r = rows
                h.recs(r).cutManual = false;
                h.recs(r).cutFrame  = NaN;
                h.recs(r).dataCut   = [];
            end
            guidata(fig, h);
            pivui.grain4Shell.renderPOT(fig);
            pivui.grain4Shell.drawSampleMarker(fig);
            pivui.grain4Shell.callHook(fig, 'onPotChanged');
            pivui.setStatus(fig, sprintf('Batal trim (%s): kurva dikembalikan utuh.', scope));
        end


        function tf = isExcluded(rec)
        %ISEXCLUDED  True bila record kurva ditandai DIBUANG (non-destruktif).
            tf = isstruct(rec) && isfield(rec,'excluded') && isscalar(rec.excluded) ...
                && logical(rec.excluded);
        end


        function num = curveNum(rec, idx)
        %CURVENUM  Nomor kurva (string) tanpa awalan 'P-': dari digit .point,
        %   else indeks baris.
            num = '';
            if isstruct(rec) && isfield(rec,'point') && ~isempty(rec.point)
                d = regexp(char(rec.point), '\d+', 'match', 'once');
                if ~isempty(d), num = d; end
            end
            if isempty(num), num = sprintf('%d', idx); end
        end


        function [dA, cA] = curveAreas(recs, nF)
        %CURVEAREAS  ΔLuas antar kurva BERURUTAN (overlapping ke bawah): luas
        %   |selisih| deret kurva-k vs kurva valid SEBELUMNYA (trapz thd indeks
        %   frame). Kurva pertama = 0. Kurva DIBUANG (excluded) dilewati (NaN) &
        %   tak memutus rantai (yang berikutnya dibandingkan ke valid sebelumnya).
        %   cA = kumulatif (cumsum, mengabaikan NaN).
            n = numel(recs); dA = nan(n,1); cA = nan(n,1);
            prev = []; acc = 0; haveFirst = false;
            for k = 1:n
                if pivui.grain4Shell.isExcluded(recs(k)), continue; end
                [~, yv] = pivcore.pot.records.curveXY(recs(k), nF);
                yv = pivui.grain4Shell.applyTrimYV(recs(k), yv);
                if ~haveFirst
                    dA(k) = 0; acc = 0; cA(k) = 0; prev = yv; haveFirst = true; continue;
                end
                m = min(numel(prev), numel(yv));
                a = prev(1:m); b = yv(1:m); g = isfinite(a) & isfinite(b);
                ar = 0;
                if sum(g) >= 2, xf = find(g); ar = trapz(xf, abs(a(g) - b(g))); end
                dA(k) = ar; acc = acc + ar; cA(k) = acc; prev = yv;
            end
        end


        function R = recsForHW(recs)
        %RECSFORHW  Salinan recs di mana kurva DIBUANG (excluded) dikosongkan
        %   label-nya -> hwLabel/netslip MENGABAIKANNYA. Proteksi: kurva ber-label
        %   HW yang dibuang keluar dari perhitungan net-slip/HW. Panjang & urutan
        %   array DIPERTAHANKAN supaya indeks rowsForHW↔groupCurves tetap padan.
            R = recs;
            for r = 1:numel(R)
                if pivui.grain4Shell.isExcluded(R(r))
                    R(r).assignLabel = '';
                    if isfield(R(r),'point'), R(r).point = ''; end
                end
            end
        end


        function deleteSelectedCurves(fig)
        %DELETESELECTEDCURVES  Tandai kurva terpilih DIBUANG (excluded): hilang
        %   dari axPOT, envelope indenter, net-slip & tabel label. Non-destruktif
        %   (pulihkan via restoreDeletedCurves). Untuk kurva yang gagal naik ke
        %   puncak / nyangkut di tengah plot.
            h = guidata(fig);
            rows = h.selRows(:).'; rows = rows(rows>=1 & rows<=numel(h.recs));
            if isempty(rows)
                pivui.setStatus(fig,'Pilih kurva dulu (klik kurva di axPOT / daftar), lalu Buang.'); return;
            end
            for r = rows, h.recs(r).excluded = true; end
            h.selRows = []; guidata(fig, h);
            pivui.grain4Shell.renderPOT(fig);
            pivui.grain4Shell.drawSampleMarker(fig);
            pivui.grain4Shell.callHook(fig, 'onPotChanged');
            pivui.setStatus(fig, sprintf('🗑 Buang %d kurva (non-destruktif; Pulih kurva utk kembalikan).', ...
                numel(rows)));
        end


        function restoreDeletedCurves(fig)
        %RESTOREDELETEDCURVES  Batalkan buang kurva terpilih (atau SEMUA bila tak
        %   ada seleksi) -> kurva tampil lagi.
            h = guidata(fig);
            rows = h.selRows(:).'; rows = rows(rows>=1 & rows<=numel(h.recs));
            scope = 'terpilih';
            if isempty(rows), rows = 1:numel(h.recs); scope = 'semua'; end
            for r = rows, h.recs(r).excluded = false; end
            guidata(fig, h);
            pivui.grain4Shell.renderPOT(fig);
            pivui.grain4Shell.drawSampleMarker(fig);
            pivui.grain4Shell.callHook(fig, 'onPotChanged');
            pivui.setStatus(fig, sprintf('Pulih kurva (%s): kurva ditampilkan lagi.', scope));
        end


        function applyVScale(fig)
            h = guidata(fig); ax = h.axPOT;
            if ~ishghandle(ax) || isempty(h.yBase), return; end
            yb=h.yBase; c=(yb(1)+yb(2))/2; half=(yb(2)-yb(1))/2;
            s=h.vScale; if ~(isfinite(s)&&s>0), s=1; end
            half=half/s; if half<=0, return; end
            ylim(ax,[c-half c+half]);
        end


        function onVScale(fig)
            h = guidata(fig);
            v = pivcore.pot.vscale.snap(get(h.sldVScale,'Value'));
            set(h.sldVScale,'Value',v); h.vScale=v; guidata(fig, h);
            pivui.grain4Shell.applyVScale(fig);
            pivui.grain4Shell.updateFrameLine(fig);
            pivui.grain4Shell.callHook(fig, 'decoratePOT');
        end


        % =============================================================
        function onCurveClick(fig, src)
            if ~ishghandle(src), return; end
            r = get(src,'UserData');
            if ~isscalar(r) || ~isfinite(r), return; end
            h = guidata(fig);
            % Toggle seleksi kurva (default ON bila field absen -> kompat GRAIN4).
            % OFF -> klik kurva "jatuh" ke frame-pick (bila itu aktif), spt klik area.
            if isfield(h,'clickCurveOn') && ~h.clickCurveOn
                if ~(isfield(h,'clickFrameOn') && ~h.clickFrameOn)
                    pivui.grain4Shell.onAxPotClick(fig);
                end
                return;
            end
            if r < 1 || r > numel(h.recs), return; end
            h.selRows = r; guidata(fig, h);
            pivui.grain4Shell.highlightSelPOT(fig);
            pivui.grain4Shell.highlightSelAC(fig);
            pivui.grain4Shell.drawSampleMarker(fig);
            pivui.grain4Shell.highlightCurveRow(fig, r);   % sorot baris tabel Kurva bila aktif
            pt = h.recs(r).point; if isempty(pt), pt = sprintf('P-%d', r); end
            pivui.setStatus(fig, sprintf('Kurva "%s" (titik %d) terpilih.', pt, r));
            pivui.grain4Shell.callHook(fig, 'onCurveClick', r);
        end


        function highlightCurveRow(fig, r)
        %HIGHLIGHTCURVEROW  Bila kolom kiri sedang mode 'curve', sorot baris-r di
        %   tabel (best-effort; uitable lawas mungkin tak dukung Selection).
            h = guidata(fig);
            if ~(isfield(h,'leftMode') && strcmp(h.leftMode,'curve')), return; end
            if ~isfield(h,'tbl') || ~ishghandle(h.tbl), return; end
            try, h.tbl.Selection = r; catch, end
        end


        function onAxPotClick(fig)
            h = guidata(fig);
            if isempty(h.recs), return; end
            % Toggle seleksi frame (default ON bila field absen -> kompat GRAIN4).
            if isfield(h,'clickFrameOn') && ~h.clickFrameOn, return; end
            cp = get(h.axPOT,'CurrentPoint');
            k = max(1, min(pivcore.util.scalarOr(round(cp(1,1)),1), pivcore.util.scalarOr(h.nF,1)));
            h.frame = k; guidata(fig, h);
            if k > 1 && ~pivcore.util.isFullLoaded(h), pivui.grain4Shell.ensureFull(fig); end
            pivui.grain4Shell.renderMain(fig);
            pivui.grain4Shell.updateFrameLine(fig);
            pivui.grain4Shell.syncFrameSlider(fig);
            h = guidata(fig);
            set(h.txtFrame,'String', sprintf('f %d/%d', pivcore.util.scalarOr(h.frame,1), ...
                pivcore.util.scalarOr(h.nF,1)));
            pivui.grain4Shell.callHook(fig, 'onFrameChanged');
        end


        function stepFrame(fig, delta)
        %STEPFRAME  Maju/mundur frame RELATIF terhadap h.frame (SUMBER KEBENARAN),
        %   BUKAN nilai slider (peer Java bisa basi setelah set programatik / klik
        %   kurva -> panah slider melompat ke nilai lama). delta = +1/-1 (atau lain).
        %   Semua jalur pindah frame lewat gotoFrame (sinkron slider + garis + hook).
            h = guidata(fig);
            if isempty(h.recs) && isempty(h.data), return; end
            cur = pivcore.util.scalarOr(round(h.frame), 1);
            pivui.grain4Shell.gotoFrame(fig, cur + round(delta));
        end


        function gotoFrame(fig, k)
        %GOTOFRAME  Pindah ke frame k (clamp 1..nF): muat bila perlu, render,
        %   sinkron slider/garis frame. Dipakai mis. klik baris komentar.
            h = guidata(fig);
            if isempty(h.recs) && isempty(h.data), return; end
            k = max(1, min(pivcore.util.scalarOr(round(k),1), pivcore.util.scalarOr(h.nF,1)));
            h.frame = k; guidata(fig, h);
            if k > 1 && ~pivcore.util.isFullLoaded(h), pivui.grain4Shell.ensureFull(fig); end
            pivui.grain4Shell.renderMain(fig);
            pivui.grain4Shell.updateFrameLine(fig);
            pivui.grain4Shell.syncFrameSlider(fig);
            h = guidata(fig);
            set(h.txtFrame,'String', sprintf('f %d/%d', pivcore.util.scalarOr(h.frame,1), ...
                pivcore.util.scalarOr(h.nF,1)));
            pivui.grain4Shell.callHook(fig, 'onFrameChanged');
        end


        function setFrameQuiet(fig, k)
        %SETFRAMEQUIET  Pindah ke frame k (clamp 1..nF) TANPA render live: hanya
        %   set h.frame + ensureFull bila perlu. Dipakai loop EKSPOR (Commit/Report)
        %   di mana shot axMain offscreen membaca arg `k` langsung, bukan h.frame —
        %   jadi renderMain figure UTAMA terbuang. Buang ia -> ekspor jauh lebih
        %   cepat, output byte-identik. gotoFrame (render live) tetap utk jalur
        %   interaktif & restore.
            h = guidata(fig);
            if isempty(h.recs) && isempty(h.data), return; end
            k = max(1, min(pivcore.util.scalarOr(round(k),1), pivcore.util.scalarOr(h.nF,1)));
            h.frame = k; guidata(fig, h);
            if k > 1 && ~pivcore.util.isFullLoaded(h), pivui.grain4Shell.ensureFull(fig); end
        end


        % =============================================================
        % Ekspor gambar (offscreen) untuk bundel komentar/Claude
        % =============================================================
        function ok = exportScalarPNG(fig, scalar, file)
        %EXPORTSCALARPNG  Render panel skalar (vel mag / shear) bingkai aktif ke
        %   PNG via figure OFFSCREEN (tak mengganggu tampilan hidup). Sertakan
        %   garis PSG (oranye) sbg konteks lokasi sampling.
            ok = false;
            h = guidata(fig);
            if isempty(h.data), return; end
            kWant = pivcore.util.scalarOr(h.frame,1);
            if kWant > 1 && ~pivcore.util.isFullLoaded(h)
                pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
            end
            k = max(1, min(kWant, pivcore.util.scalarOr(h.imgFrames,1)));
            tmpF = figure('Visible','off','Color','w','Units','pixels', ...
                'Position',[100 100 1000 560]);
            cleaner = onCleanup(@() pivui.grain4Shell.safeClose(tmpF)); %#ok<NASGU>
            ax = axes('Parent',tmpF);
            cfg = h; cfg.scalarSrc = scalar;
            pivcore.montage.renderScalarPanel(ax, h.data, k, scalar, cfg);
            if strcmpi(scalar,'shear')
                [~, lab] = deal([], 'shear strain (du/dy+dv/dx)');
            else
                lab = '|V| (vel mag)';
            end
            cb = colorbar(ax); cb.Label.String = lab;
            if ~isempty(h.line) && isfield(h.line,'p1')
                ps = pivui.potStyle().psgLine; hold(ax,'on');
                plot(ax,[h.line.p1(1) h.line.p2(1)],[h.line.p1(2) h.line.p2(2)], ...
                    '-','Color',ps.color,'LineWidth',ps.lineWidth); hold(ax,'off');
            end
            title(ax, sprintf('%s — %s — frame %d/%d', ...
                pivcore.util.baseName(h.realData), lab, k, h.imgFrames), 'Interpreter','none');
            try
                exportgraphics(ax, file, 'Resolution', 150); ok = true;
            catch
                ok = false;
            end
        end


        function ok = exportAxPotPNG(fig, file)
        %EXPORTAXPOTPNG  Salin axPOT (spaghetti + garis vertikal frame aktif) ke
        %   PNG. Garis frame digambar di posisi h.frame sbg "frame representatif".
            ok = false;
            h = guidata(fig);
            if ~isfield(h,'axPOT') || ~ishghandle(h.axPOT), return; end
            pivui.grain4Shell.updateFrameLine(fig);   % pastikan garis frame mutakhir
            try
                exportgraphics(h.axPOT, file, 'Resolution', 150); ok = true;
            catch
                ok = false;
            end
        end


        function safeClose(f)
            try, if ishghandle(f), close(f); end, catch, end
        end


        % =============================================================
        % PRODUKSI GAMBAR ber-spec (tab ④) — render dari shotSpec (1 sumber)
        % =============================================================
        function lc = lockedClim(fig)
        %LOCKEDCLIM  CLim TERKUNCI per-eksperimen: Vel mag [0 ceil(maxIndenter/0.5)]
        %   (sama climFromIndenter), Shear = h.shearAbs terkini. Dipakai SAMA utk
        %   semua gambar eksperimen -> skala konsisten (komparabilitas paper).
            h = guidata(fig);
            vel = h.climVel; if numel(vel)~=2, vel = [0 5]; end
            env = pivui.grain4Shell.indenterEnvelope(h);
            if ~isempty(env)
                mx = max(env(isfinite(env)));
                if ~isempty(mx) && isfinite(mx) && mx > 0
                    hi = pivcore.util.snapClim(mx, 0.5, 'ceil');   % bulat ke ATAS -> tak memotong puncak
                    if hi > 0, vel = [0 hi]; end
                end
            end
            sa = h.shearAbs; if ~(isscalar(sa) && isfinite(sa) && sa>0), sa = 1; end
            lc = struct('velmag', vel, 'shearAbs', sa);
        end


        function ok = exportShotScalarPNG(fig, scalar, spec, file)
        %EXPORTSHOTSCALARPNG  Panel skalar (velmag/shear) OFFSCREEN dgn CLim
        %   TERKUNCI dari spec + caption tertanam (judul). Sertakan garis PSG.
            ok = false;
            h = guidata(fig);
            if isempty(h.data), return; end
            kWant = pivcore.util.scalarOr(spec.frame, h.frame);
            if kWant > 1 && ~pivcore.util.isFullLoaded(h)
                pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
            end
            k = max(1, min(round(kWant), pivcore.util.scalarOr(h.imgFrames,1)));
            tmpF = figure('Visible','off','Color','w','Units','pixels', ...
                'Position',[100 100 1000 560]);
            cleaner = onCleanup(@() pivui.grain4Shell.safeClose(tmpF)); %#ok<NASGU>
            ax = axes('Parent',tmpF);
            cfg = h; cfg.scalarSrc = scalar;
            if strcmpi(scalar,'shear')
                if isfield(spec,'shearAbs') && isscalar(spec.shearAbs) && isfinite(spec.shearAbs)
                    cfg.shearAbs = spec.shearAbs;
                end
                lab = 'shear strain (du/dy+dv/dx)';
            else
                if isfield(spec,'climVel') && numel(spec.climVel)==2
                    cfg.climVel = spec.climVel(:).';
                end
                lab = '|V| (vel mag)';
            end
            pivcore.montage.renderScalarPanel(ax, h.data, k, scalar, cfg);
            cb = colorbar(ax); cb.Label.String = lab;
            if ~isempty(h.line) && isfield(h.line,'p1')
                ps = pivui.potStyle().psgLine; hold(ax,'on');
                plot(ax,[h.line.p1(1) h.line.p2(1)],[h.line.p1(2) h.line.p2(2)], ...
                    '-','Color',ps.color,'LineWidth',ps.lineWidth); hold(ax,'off');
            end
            cap = ''; if isfield(spec,'caption'), cap = char(spec.caption); end
            if isempty(cap), cap = sprintf('%s — %s — frame %d', ...
                    pivcore.util.baseName(h.realData), lab, k); end
            title(ax, cap, 'Interpreter','none');
            try, exportgraphics(ax, file, 'Resolution', 150); ok = true; catch, ok = false; end
        end


        function ok = exportShotAxPotPNG(fig, spec, file)
        %EXPORTSHOTAXPOTPNG  axPOT OFFSCREEN yang HANYA menggambar isi sesuai spec
        %   (kurva ber-label terpilih + opsi kurva mentah + envelope indenter +
        %   titik observasi). Unsur grafik (grid/label sumbu) tetap; caption
        %   tertanam di judul. SATU spec -> gambar & JSON padan.
            ok = false;
            h = guidata(fig);
            if isempty(h.recs), return; end
            nF = h.nF;
            cv = {}; if isfield(spec,'curvesVisible'), cv = spec.curvesVisible; end
            rawOn  = isfield(spec,'rawVisible') && spec.rawVisible;
            indOn  = ~isfield(spec,'indenterVisible') || spec.indenterVisible;
            ptsOn  = ~isfield(spec,'pointsVisible')   || spec.pointsVisible;
            % Layer KOMPOSER CERITA (tab ⑤; default OFF -> kompat tab ④):
            hwLabOn   = isfield(spec,'hwLabel')     && spec.hwLabel;       % label HW# di puncak
            ptsAllHW  = isfield(spec,'pointsAllHW') && spec.pointsAllHW;   % titik utk SEMUA HW
            frameLine = NaN; if isfield(spec,'frameLine'), frameLine = spec.frameLine; end
            lwA = pivcore.util.scalarOr(h.lwAssigned, 2.6);
            lwR = pivcore.util.scalarOr(h.lwRaw, 0.6);
            % Sumbu-X: 'strain' -> remap frame->strain kumulatif % (untuk paper);
            % default 'frame' (akuisisi titik). Butuh strainTotal & nF>1.
            useStrain = isfield(spec,'xUnit') && strcmpi(spec.xUnit,'strain') ...
                && isfield(spec,'strainTotal') && isscalar(spec.strainTotal) ...
                && isfinite(spec.strainTotal) && spec.strainTotal ~= 0 && nF > 1;   % strain bisa negatif (kompresi)
            if useStrain, xmap = @(xf) (xf-1)/(nF-1)*spec.strainTotal; else, xmap = @(xf) xf; end

            tmpF = figure('Visible','off','Color','w','Units','pixels', ...
                'Position',[100 100 1000 520]);
            cleaner = onCleanup(@() pivui.grain4Shell.safeClose(tmpF)); %#ok<NASGU>
            ax = axes('Parent',tmpF);
            set(ax,'Color','w','XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
                'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top');
            hold(ax,'on');
            ymin=inf; ymax=-inf; nShown=0;
            for r = 1:numel(h.recs)
                if pivui.grain4Shell.isExcluded(h.recs(r)), continue; end
                lab = pivcore.pot.records.label(h.recs(r));
                if isempty(lab), show = rawOn; lw = lwR; else, show = any(strcmp(lab, cv)); lw = lwA; end
                if ~show, continue; end
                [xv,yv] = pivcore.pot.records.curveXY(h.recs(r), nF);
                yv = pivui.grain4Shell.applyTrimYV(h.recs(r), yv);
                g = isfinite(xv) & isfinite(yv); if ~any(g), continue; end
                col = h.recs(r).color; if numel(col)~=3, col=[0.4 0.4 0.4]; end
                plot(ax, xmap(xv(g)), yv(g), '-', 'Color',col, 'LineWidth',lw);
                ymin=min(ymin,min(yv(g))); ymax=max(ymax,max(yv(g))); nShown=nShown+1;
            end
            if indOn
                env = pivui.grain4Shell.indenterEnvelope(h);
                if ~isempty(env)
                    xe=1:numel(env); ge=isfinite(env);
                    if any(ge)
                        plot(ax, xmap(xe(ge)), env(ge), '-', 'Color',[0 0 0], 'LineWidth',3);
                        ymin=min(ymin,min(env(ge))); ymax=max(ymax,max(env(ge)));
                    end
                end
            end
            recsHW = pivui.grain4Shell.recsForHW(h.recs);
            if ptsOn && isfield(h,'pts') && ~isempty(h.pts)
                % Titik POI: untuk SEMUA HW (komposer cerita) atau hanya kurva
                % yang ditampilkan (tab ④). ptNums = daftar nomor HW yang dipakai.
                if ptsAllHW
                    ptNums = pivcore.pot.hwLabel.hwNumbers(recsHW);
                else
                    ptNums = [];
                    for ci = 1:numel(cv)
                        tk = regexp(cv{ci}, '^HW-(\d+)$', 'tokens', 'once');
                        if ~isempty(tk), ptNums(end+1) = str2double(tk{1}); end %#ok<AGROW>
                    end
                end
                for num = ptNums(:).'
                    rows = pivcore.pot.hwLabel.rowsForHW(recsHW, num);
                    if isempty(rows), continue; end
                    rep = pivcore.pot.netslip.repVec(pivcore.pot.hwLabel.groupCurves(recsHW, rows, nF), nF);
                    row = pivcore.pot.snapPoints.getHW(h.pts, num);
                    if isempty(row), continue; end
                    pivui.grain4Shell.plotShotPt(ax, rep, row.startF, 'start', xmap(row.startF));
                    pivui.grain4Shell.plotShotPt(ax, rep, row.nclF,   'nuc',   xmap(row.nclF));
                    pivui.grain4Shell.plotShotPt(ax, rep, row.fsrF,   'fsr',   xmap(row.fsrF));
                    pivui.grain4Shell.plotShotPt(ax, rep, row.endF,   'end',   xmap(row.endF));
                end
            end
            hold(ax,'off');
            ylabel(ax,'|V| (px/frame)');
            if useStrain
                xlabel(ax,'Strain kumulatif (%)'); xlim(ax, sort([0 spec.strainTotal]));   % urut (strain bisa negatif)
            else
                xlabel(ax,'Frame'); if nF > 1, xlim(ax,[1 nF]); end
            end
            grid(ax,'on');
            if isfinite(ymin) && isfinite(ymax) && ymax > ymin
                pad = 0.05*(ymax-ymin); ylim(ax,[max(0,ymin-pad) ymax+pad]);
            end
            % --- Layer komposer cerita: label HW# + garis vertikal frame ---
            % (digambar SETELAH limit sumbu supaya posisi teks/garis benar)
            xl = get(ax,'XLim'); yl = get(ax,'YLim');
            hold(ax,'on');
            if hwLabOn
                for num = pivcore.pot.hwLabel.hwNumbers(recsHW)
                    rows = pivcore.pot.hwLabel.rowsForHW(recsHW, num);
                    if isempty(rows), continue; end
                    rep = pivcore.pot.netslip.repVec(pivcore.pot.hwLabel.groupCurves(recsHW, rows, nF), nF);
                    rep = pivui.grain4Shell.applyTrimYV(recsHW(rows(1)), rep);
                    g = isfinite(rep); if ~any(g), continue; end
                    [yp, xp] = max(rep); xpp = xmap(xp);
                    if ~(isfinite(xpp) && isfinite(yp)), continue; end
                    xpp = min(max(xpp, xl(1)), xl(2));
                    col = pivcore.pot.labels.labelColor('HW', num);
                    text(ax, xpp, yp, sprintf(' HW-%d', num), 'Color',[0 0 0], ...
                        'BackgroundColor','w','EdgeColor',col,'Margin',1, ...
                        'FontWeight','bold','FontSize',8, ...
                        'HorizontalAlignment','center','VerticalAlignment','bottom');
                end
            end
            if isscalar(frameLine) && isfinite(frameLine) && frameLine >= 1 && frameLine <= nF
                xf = xmap(frameLine);
                if isfinite(xf)
                    plot(ax, [xf xf], yl, '--', 'Color',[0.45 0.45 0.45], 'LineWidth',1.2);
                    if useStrain, lab = sprintf(' %.1f%% ', xmap(frameLine)); else, lab = sprintf(' f%d ', round(frameLine)); end
                    text(ax, xf, yl(2), lab, 'Color',[0.25 0.25 0.25], ...
                        'BackgroundColor','w','EdgeColor',[0.6 0.6 0.6],'Margin',1, ...
                        'FontSize',8,'HorizontalAlignment','center','VerticalAlignment','top');
                end
            end
            hold(ax,'off');
            cap = ''; if isfield(spec,'caption'), cap = char(spec.caption); end
            if isempty(cap), cap = sprintf('axPOT — %s', pivcore.util.baseName(h.realData)); end
            title(ax, cap, 'Color',[0 0 0], 'Interpreter','none');
            try, exportgraphics(ax, file, 'Resolution', 150); ok = true; catch, ok = false; end
        end


        function plotShotPt(ax, yvec, f, which, xPlot)
        %PLOTSHOTPT  Titik observasi (Start/NUC/FSR/END) di axPOT offscreen. y dari
        %   frame f; x = xPlot (default f) supaya bisa dipetakan ke strain%.
            if ~(isscalar(f) && isfinite(f) && f>=1 && f<=numel(yvec)), return; end
            yv = yvec(round(f)); if ~isfinite(yv), return; end
            if nargin < 5 || ~isscalar(xPlot) || ~isfinite(xPlot), xPlot = f; end
            col = pivcore.pot.snapPoints.color(which);
            plot(ax, xPlot, yv, 'o', 'MarkerSize',9, 'LineWidth',1.4, ...
                'MarkerEdgeColor',col, 'MarkerFaceColor','w');
        end


        % =============================================================
        % Kontrol tampilan
        % =============================================================
        function onDisp(fig)
            h = guidata(fig);
            if get(h.btnDisp,'Value')==1
                h.scalarSrc='shear'; set(h.btnDisp,'String','Shear strain');
            else
                h.scalarSrc='velocity_magnitude'; set(h.btnDisp,'String','Vel mag');
            end
            guidata(fig, h); pivui.grain4Shell.syncClimControls(h);
            if isempty(h.data), return; end
            pivui.grain4Shell.renderMain(fig);
        end


        function onClim(fig)
            h = guidata(fig);
            lo = str2double(get(h.edLo,'String')); hi = str2double(get(h.edHi,'String'));
            if strcmp(h.scalarSrc,'shear')
                if isfinite(hi)&&hi>0, h.shearAbs=hi; end
            else
                if isfinite(lo)&&isfinite(hi)&&hi>lo, h.climVel=[lo hi]; end
            end
            guidata(fig, h); pivui.grain4Shell.syncClimControls(h);
            pivui.grain4Shell.renderMain(fig);
        end


        function onAutoClim(fig)
            h = guidata(fig);
            if isempty(h.data), return; end
            if strcmp(h.scalarSrc,'velocity_magnitude') && ~isempty(h.indenter) ...
                    && any(isfinite(h.indenter))
                pivui.grain4Shell.climFromIndenter(fig); return;
            end
            pivui.grain4Shell.autoClimFromFrame(fig, max(1, min(h.frame, h.imgFrames)));
            h = guidata(fig); pivui.grain4Shell.syncClimControls(h);
            pivui.grain4Shell.renderMain(fig);
        end


        function autoClimFromFrame(fig, k)
            h = guidata(fig);
            if isempty(h.data), return; end
            if strcmp(h.scalarSrc,'shear')
                Z = pivcore.data.computeShearRate(h.data, k, 'mode','engineering');
                if any(isfinite(Z(:)))
                    c = pivcore.util.robustCLim(abs(Z)); if c(2)>0, h.shearAbs=c(2); end
                end
            else
                Z = pivcore.data.resolveScalar(h.data, 'velocity_magnitude', k);
                if any(isfinite(Z(:))), h.climVel = pivcore.util.robustCLim(Z); end
            end
            guidata(fig, h);
        end


        function syncClimControls(h)
            if strcmp(h.scalarSrc,'shear')
                set(h.txtLo,'String','±:');
                set(h.edLo,'String',sprintf('-%g',h.shearAbs),'Enable','off');
                set(h.txtHi,'String','X:');
                set(h.edHi,'String',sprintf('%g',h.shearAbs),'Enable','on');
            else
                set(h.txtLo,'String','min:');
                set(h.edLo,'String',sprintf('%g',h.climVel(1)),'Enable','on');
                set(h.txtHi,'String','max:');
                set(h.edHi,'String',sprintf('%g',h.climVel(2)),'Enable','on');
            end
        end


        function onGS(fig)
            h = guidata(fig);
            h.gsOn = get(h.chkGS,'Value')==1;
            a = str2double(get(h.edAlpha,'String'));
            if isfinite(a)&&a>=0&&a<=1, h.gsAlpha=a; end
            set(h.edAlpha,'String',sprintf('%.2f',h.gsAlpha));
            if isfield(h,'chkCLAHE')&&ishghandle(h.chkCLAHE), h.claheOn=get(h.chkCLAHE,'Value')==1; end
            if isfield(h,'chkAdj')&&ishghandle(h.chkAdj), h.adjOn=get(h.chkAdj,'Value')==1; end
            guidata(fig, h);
            if isempty(h.data), return; end
            pivui.grain4Shell.renderMain(fig);
        end


        function onGlyph(fig)
            h = guidata(fig);
            h.glyphOn = get(h.chkGlyph,'Value')==1;
            lw = str2double(get(h.edGlyphLW,'String'));
            if isfinite(lw)&&lw>0, h.glyphLW=lw; end
            set(h.edGlyphLW,'String',sprintf('%g',h.glyphLW));
            sp = str2double(get(h.edGlyphSp,'String'));
            if isfinite(sp)&&sp>=1, h.glyphSp=round(sp); end
            set(h.edGlyphSp,'String',num2str(h.glyphSp));
            if isfield(h,'btnGlyphColor') && ishghandle(h.btnGlyphColor)
                if get(h.btnGlyphColor,'Value')==1
                    h.glyphColor=[1 1 1]; set(h.btnGlyphColor,'String','Panah ⬜');
                else
                    h.glyphColor=[0 0 0]; set(h.btnGlyphColor,'String','Panah ⬛');
                end
            end
            guidata(fig, h);
            if isempty(h.data), return; end
            pivui.grain4Shell.renderMain(fig);
        end


        function onSpacing(fig)
            h = guidata(fig);
            s = strtrim(get(h.edSpacing,'String'));
            if isempty(s) || strcmpi(s,'auto')
                h.spacing=NaN; set(h.edSpacing,'String','auto');
            else
                v = str2double(s);
                if isfinite(v)&&v>0, h.spacing=v; set(h.edSpacing,'String',num2str(v));
                else, h.spacing=NaN; set(h.edSpacing,'String','auto'); end
            end
            guidata(fig, h);
            if ~isempty(h.line), pivui.grain4Shell.collectPOT(fig); end
        end


        function onFrameSlider(fig)
            h = guidata(fig);
            if isempty(h.data), return; end
            k = max(1, min(pivcore.util.scalarOr(round(get(h.sldFrame,'Value')),1), ...
                pivcore.util.scalarOr(h.nF,1)));
            h.frame=k; guidata(fig, h);
            if k>1 && ~pivcore.util.isFullLoaded(h), pivui.grain4Shell.ensureFull(fig); end
            pivui.grain4Shell.renderMain(fig);
            pivui.grain4Shell.updateFrameLine(fig);
            h = guidata(fig);
            set(h.txtFrame,'String',sprintf('f %d/%d', pivcore.util.scalarOr(h.frame,1), ...
                pivcore.util.scalarOr(h.nF,1)));
            pivui.grain4Shell.callHook(fig, 'onFrameChanged');
        end


        function syncFrameSlider(fig)
            h = guidata(fig); nF = max(1, h.nF);
            if nF>1, step=[1 10]/(nF-1); else, step=[1 1]; end
            set(h.sldFrame,'Min',1,'Max',nF,'Value',max(1,min(h.frame,nF)),'SliderStep',step);
            set(h.txtFrame,'String',sprintf('f %d/%d', max(1,min(h.frame,nF)), nF));
        end


        % =============================================================
        function g = loadGeom(matFile)
            g = [];
            if isempty(matFile) || ~isfile(matFile), return; end
            try
                mf = matfile(matFile); info = whos(mf);
                if ~ismember('experiment_geometry', {info.name}), return; end
                g = mf.experiment_geometry;
            catch, g = []; end
        end


        % =============================================================
        function nPad = padRowsToFill(tbl, nData)
        %PADROWSTOFILL  Jumlah baris KOSONG (placeholder) yg perlu ditambahkan
        %   agar grid uitable `tbl` PENUH sampai bawah (tak menggantung setengah
        %   saat data sedikit). Kapasitas baris = tinggi tabel piksel / ~18px per
        %   baris, dikurangi 1 (header) & jumlah data. Aman; gagal -> 0.
            nPad = 0;
            try
                u0 = get(tbl,'Units'); set(tbl,'Units','pixels');
                p  = get(tbl,'Position'); set(tbl,'Units',u0);
                hPx = p(4);
                if ~isfinite(hPx) || hPx <= 0, return; end
                rowH = 18;                       % perkiraan tinggi baris default
                cap  = floor((hPx - 24) / rowH); % -24 ≈ header + scrollbar
                nPad = cap - nData;
                if ~isfinite(nPad) || nPad < 0, nPad = 0; end
            catch
                nPad = 0;
            end
        end


        % =============================================================
        function callHook(fig, name, varargin)
        %CALLHOOK  Panggil hook h.hooks.(name)(fig, varargin{:}) bila ada &
        %   function handle. Aman (try) agar bug pemanggil tak merusak shell.
            h = guidata(fig);
            if ~isfield(h,'hooks') || ~isstruct(h.hooks), return; end
            if ~isfield(h.hooks, name), return; end
            fn = h.hooks.(name);
            if isempty(fn) || ~isa(fn,'function_handle'), return; end
            try
                fn(fig, varargin{:});
            catch ME
                warning('pivui:grain4Shell:hook', 'Hook %s gagal: %s', name, ME.message);
            end
        end

    end
end
