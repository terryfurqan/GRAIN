function GRAIN1(rootDir)
%GRAIN1  STEP 1 — PENENTUAN ROI jitter/anchor MULTI-EKSPERIMEN.
%
%   GRAIN1                 % pilih folder ROOT (dialog), scan rekursif
%   GRAIN1(rootDir)        % langsung ke ROOT
%
%   CATATAN NAMA (2026-06-25): alat ROI jitter ini dulu memakai nomor 0; kini
%   = Step 1, sesudah Step 0 (QPIV exclusion) yang dipegang GRAIN0. Diluncurkan
%   dari GRAIN0 lewat tombol "Lanjut → Step 1". GUI BatchPIVPrep2 (produksi
%   .mat) turun jadi PAB1_old (_compat).
%
%   FOKUS: menentukan ROI
%   anchor stabilisasi (uji jitter area kecil) untuk BANYAK eksperimen
%   sekaligus, lalu menyerahkannya ke Step 1 untuk produksi .mat.
%
%   ALUR (satu-per-satu, bukan batch di akhir):
%     1. Pilih ROOT -> scan SELURUH subfolder (rekursif) = daftar eksperimen
%        (memakai batchpivprep2.io.collectFolders, identik Step 1).
%     2. Pilih sebuah exp di tabel (kolom kiri) -> frame-1 tampil (kolom tengah).
%     3. Gambar ROI KECIL: tombol ▭ (tarik SEKALI -> langsung tersimpan) atau
%        ⬡ (klik titik-titik, tersimpan saat polygon ditutup). TANPA double-click.
%     4. Tekan "Hitung Jitter" -> 4 kurva di-overlay (dx, dy, cumDx, cumDy)
%        tampil di bawah gambar. (ROI digambar = SIMPAN saja; perhitungan
%        eksplisit, supaya bisa set ROI banyak exp dulu baru hitung.)
%        Cocok -> "Next Exp".
%     5. Setelah semua exp punya ROI: "Ekspor -> Step 2" (tulis progress
%        BatchPIVPrep2) atau "Lanjutkan ke Step 2" (tutup GRAIN1 + buka GRAIN2).
%
%   KOLOM TABEL: Eksperimen | Frame | ROI | Jitter | ✓. Kolom "Frame" =
%   keluaran QPIV (GRAIN0 kolom 4 "output") bila ada progres Step 0; jika tidak,
%   jumlah gambar lolos QPIV. Kolom nomor urut "#" sudah DIBUANG.
%
%   PROGRESS GRAIN1: tombol "Simpan/Muat Progress" -> berkas KHUSUS
%   <ROOT>/PAB1_progress.mat (ROI + hasil jitter), beda dari QPIV
%   <ROOT>/PAB0_progress.mat & handoff <ROOT>/PAB_progress.mat. Auto-load saat
%   scan ROOT bila berkas itu ada.
%
%   FILOSOFI VONIS (konteks sandbox): jitter analisis dilakukan pada bagian
%   yang SEHARUSNYA DIAM (rangka tetap, BUKAN pasir/dinding pendorong). Drift
%   kumulatif besar di ROI diam itu BUKAN kegagalan — justru getaran eksternal
%   (kamera/shutter) yang akan DI-NOL-kan stabilisasi Step 1. Maka tool TIDAK
%   memvonis besar jitter; penilaian (ROI di bagian diam?) ada di tangan
%   pengguna yang melihat 4 kurva + foto. Tidak ada panel statistik angka —
%   semua sudah tercermin di gambar & kurva.
%
%   ENGINE jitter = SAMA Step 1 (tanpa duplikasi): pivprep.stab.buildReference
%   + estimateTransform, dgn roiPad=0 (terkurung di ROI), lastGoodTform=I
%   (dx/dy ABSOLUT vs frame-1 -> cumDx/cumDy = cumsum), jitterTol besar (semua
%   frame terukur). Crop default tiap exp = full-frame (cropPreset.makeNone);
%   atur crop sebenarnya nanti di Step 1.
%
%   Jalankan grain_setup sekali per sesi. SELALU MATLAB R2025b. Tema TERANG
%   dipaksa; jendela di-minimize saat dialog berkas, restore sesudah.

    here = fileparts(mfilename('fullpath'));
    if isempty(which('grain_setup'))
        addpath(here);
    end
    if isempty(which('pivprep.stab.buildReference')) || isempty(which('pivui.forceLightTheme'))
        try, grain_setup(); catch, end
    end

    if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
        rootDir = uigetdir(pwd, ...
            'Pick a ROOT folder — every subfolder is scanned as an experiment');
        if isequal(rootDir, 0), return; end
    end

    h          = struct();
    h.root     = rootDir;
    h.exps     = i_emptyExps();   % struct array eksperimen
    h.activeRow= 0;
    h.selRows  = [];              % baris tabel terpilih (multi) utk hapus
    h.method   = 'surf';          % 'surf' | 'phasecorr' (default per-exp)
    h.cumAbs   = false;           % mode drift kumulatif: false=SIGNED (net),
                                  % true=ABSOLUT (panjang lintasan, cumsum|d|)

    h = i_buildUI(h);
    guidata(h.fig, h);
    i_rescan(h.fig);
end


% =====================================================================
% UI 3-KOLOM (tema TERANG dipaksa)
%   Kolom kiri  : tabel eksperimen.
%   Kolom tengah: frame-1 + gambar ROI (atas) & plot 4-kurva (bawah).
%   Kolom kanan : kontrol (param, Next, simpan/ekspor/buka Step 1).
% =====================================================================
function h = i_buildUI(h)
    WHITE = [1 1 1];
    h.fig = figure('Name',pivui.titleWithVersion('GRAIN1 (Step 1) — Multi-experiment jitter/anchor ROI setup'), ...
        'NumberTitle','off','Color',WHITE, ...
        'Units','pixels','Position',[40 50 1480 820], ...
        'MenuBar','none','ToolBar','figure');
    pivui.forceLightTheme(h.fig);
    fig = h.fig;

    % ---------------- KOLOM KIRI: tabel eksperimen --------------------
    pnlL = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.006 0.01 0.250 0.985],'Title','Experiments (ROOT subfolders)', ...
        'FontWeight','bold','BackgroundColor',WHITE);
    h.txtRoot = uicontrol('Parent',pnlL,'Style','text', ...
        'Units','normalized','Position',[0.03 0.955 0.94 0.035], ...
        'HorizontalAlignment','left','FontSize',8, ...
        'BackgroundColor',WHITE,'String',h.root);
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.915 0.46 0.038],'String','Pick ROOT…', ...
        'TooltipString','Pick a ROOT folder; its subfolders are scanned as experiments.', ...
        'Callback',@(s,e) i_onPickRoot(fig));
    uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.915 0.46 0.038],'String','Rescan', ...
        'TooltipString','Rescan the subfolders (recursive).', ...
        'Callback',@(s,e) i_rescan(fig));
    h.tbl = uitable('Parent',pnlL,'Units','normalized', ...
        'Position',[0.03 0.100 0.94 0.807], ...
        'ColumnName',{'Experiment','Frame','ROI','Jitter','✓'}, ...
        'ColumnWidth',{150 46 32 60 26}, ...
        'ColumnEditable',[false false false false false], ...
        'RowName',[],'FontSize',9, ...
        'CellSelectionCallback',@(s,e) i_onSelectRow(fig, e));
    % Hapus eksperimen TAK RELEVAN dari daftar (scan rekursif agresif).
    % Hanya buang dari DAFTAR/progress — folder di disk TIDAK disentuh.
    h.btnDelExp = uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.055 0.62 0.040],'String','Remove selected', ...
        'TooltipString',['Drop the selected experiments from the list (multi-select ok). ', ...
                         'Folders on disk are NOT deleted — they just leave the Step 1 input.'], ...
        'Callback',@(s,e) i_onDeleteExps(fig));
    h.btnClearExp = uicontrol('Parent',pnlL,'Style','pushbutton','Units','normalized', ...
        'Position',[0.67 0.055 0.30 0.040],'String','Clear all', ...
        'TooltipString','Clear the whole experiment list (folders on disk are untouched).', ...
        'Callback',@(s,e) i_onClearExps(fig));
    h.txtCount = uicontrol('Parent',pnlL,'Style','text','Units','normalized', ...
        'Position',[0.03 0.012 0.94 0.035],'HorizontalAlignment','left', ...
        'FontSize',8,'BackgroundColor',WHITE,'String','0 experiments.');

    % ---------------- KOLOM TENGAH: gambar + ROI + plot ---------------
    pnlM = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.260 0.01 0.470 0.985],'Title','Frame-1 + ROI  /  jitter curves', ...
        'FontWeight','bold','BackgroundColor',WHITE);
    % Strip baris-1: gambar ROI (tarik = simpan ROI; TIDAK auto-hitung).
    h.btnRect = uicontrol('Parent',pnlM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.952 0.22 0.038],'String','ROI Rectangle ▭', ...
        'FontWeight','bold','Enable','off', ...
        'TooltipString','Drag ONCE -> the ROI is saved. Then press "Compute Jitter".', ...
        'Callback',@(s,e) i_onDrawROI(fig,'rect'));
    h.btnPoly = uicontrol('Parent',pnlM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.26 0.952 0.22 0.038],'String','ROI Polygon ⬡', ...
        'Enable','off', ...
        'TooltipString','Click the vertices; saved once the polygon closes. No double-click needed.', ...
        'Callback',@(s,e) i_onDrawROI(fig,'poly'));
    h.btnClearRoi = uicontrol('Parent',pnlM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.49 0.952 0.16 0.038],'String','Clear ROI', ...
        'Enable','off', ...
        'TooltipString','Clear this exp''s ROI.', ...
        'Callback',@(s,e) i_onClearROI(fig));
    h.txtRoiInfo = uicontrol('Parent',pnlM,'Style','text','Units','normalized', ...
        'Position',[0.66 0.952 0.32 0.038],'HorizontalAlignment','left', ...
        'FontName','FixedWidth','FontSize',8,'BackgroundColor',WHITE, ...
        'String','ROI: (none)');
    % Strip baris-1b: pinjam/sebar ROI (posisi piksel sama; TIDAK auto-hitung).
    h.btnRoiFromPrev = uicontrol('Parent',pnlM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.908 0.30 0.038],'String','⇇ ROI from previous exp', ...
        'Enable','off', ...
        'TooltipString',['Copy the ROI from the PREVIOUS experiment in the list to the ', ...
                         'same pixel position. Editable right away; then "Compute Jitter".'], ...
        'Callback',@(s,e) i_onRoiFromPrev(fig));
    h.btnRoiToOthers = uicontrol('Parent',pnlM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.34 0.908 0.31 0.038],'String','ROI ⇉ other exps (empty)', ...
        'Enable','off', ...
        'TooltipString',['Apply this exp''s ROI to EVERY experiment that has NO ROI yet ', ...
                         '(same pixel position). Exps that already have one are not overwritten.'], ...
        'Callback',@(s,e) i_onRoiToOthers(fig));
    % "Hitung jitter SEMUA": loop semua exp ber-ROI yang belum punya hasil,
    % hitung jitter masing-masing sekaligus (mis. ROI sama disebar ke semua exp).
    h.btnComputeAll = uicontrol('Parent',pnlM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 0.908 0.31 0.038],'String','Compute jitter for ALL ⏩', ...
        'FontWeight','bold','BackgroundColor',[0.83 0.90 0.97], ...
        'TooltipString',['Compute jitter for EVERY experiment that already has an ROI ', ...
                         '(skips those without an ROI / that already have a result).'], ...
        'Callback',@(s,e) i_onComputeAll(fig));
    % Strip baris-2: HITUNG JITTER (kiri) + SIMPAN+NEXT (kanan), dibagi 2.
    % Jitter dihitung HANYA di tombol biru ini.
    h.btnCompute = uicontrol('Parent',pnlM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.03 0.864 0.30 0.038],'String','Compute Jitter ▶', ...
        'FontWeight','bold','Enable','off', ...
        'BackgroundColor',[0.83 0.90 0.97], ...
        'TooltipString','Measure this exp''s ROI jitter across all frames & render the 4 curves.', ...
        'Callback',@(s,e) i_recompute(fig));
    % "Simpan + Next" di sebelah kanan "Hitung Jitter": tandai exp ini SELESAI
    % (ROI+jitter terkunci), lalu lompat ke exp berikutnya. Butuh HASIL jitter.
    h.btnDoneNext = uicontrol('Parent',pnlM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.35 0.864 0.30 0.038],'String','✓ Save + Next Exp ▶', ...
        'FontWeight','bold','Enable','off','BackgroundColor',[0.80 0.92 0.80], ...
        'TooltipString',['Mark this experiment DONE (saveNextSweep: sweep to the next ', ...
                         'unfinished exp; pop-up once everything is complete).'], ...
        'Callback',@(s,e) i_onDoneNext(fig));
    % "Simpan + Next + JIT!": idem Simpan+Next, TAPI begitu sampai exp berikutnya
    % yang sudah ber-ROI (mis. ROI disebar sama ke semua exp), langsung HITUNG
    % jitter exp itu otomatis — hemat klik bila semua ROI sama.
    h.btnDoneNextJit = uicontrol('Parent',pnlM,'Style','pushbutton','Units','normalized', ...
        'Position',[0.66 0.864 0.31 0.038],'String','✓ Save + Next + JIT! ▶', ...
        'FontWeight','bold','Enable','off','BackgroundColor',[0.78 0.90 0.74], ...
        'TooltipString',['Save+Next, then AUTOMATICALLY compute the next exp''s jitter ', ...
                         'if it already has an ROI (e.g. one ROI spread to every exp).'], ...
        'Callback',@(s,e) i_onDoneNextJit(fig));
    % Axes gambar (atas).
    h.ax = axes('Parent',pnlM,'Units','normalized', ...
        'Position',[0.06 0.500 0.90 0.350]);
    axis(h.ax,'off'); title(h.ax,'Pick an experiment on the left');
    % Dua axes kurva bertumpuk (apa adanya, tanpa smoothing):
    %   atas  = dx, dy        (jitter per-bingkai, SIGNED)
    %   bawah = cumDx, cumDy  (lintasan drift kumulatif)
    h.axJit = axes('Parent',pnlM,'Units','normalized', ...
        'Position',[0.10 0.270 0.86 0.175]);
    axis(h.axJit,'off'); title(h.axJit,'Per-frame jitter (dx, dy)');
    h.axCum = axes('Parent',pnlM,'Units','normalized', ...
        'Position',[0.10 0.055 0.86 0.175]);
    axis(h.axCum,'off'); title(h.axCum,'Cumulative drift (cumDx, cumDy)');

    % ---------------- KOLOM KANAN: kontrol ----------------------------
    pnlR = uipanel('Parent',fig,'Units','normalized', ...
        'Position',[0.734 0.01 0.260 0.985],'Title','Controls', ...
        'FontWeight','bold','BackgroundColor',WHITE);

    % -- Parameter uji --
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.05 0.945 0.90 0.030],'HorizontalAlignment','left', ...
        'FontWeight','bold','BackgroundColor',WHITE,'String','Jitter test parameters');
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.05 0.905 0.34 0.028],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'String','Method:');
    h.popMethod = uicontrol('Parent',pnlR,'Style','popupmenu','Units','normalized', ...
        'Position',[0.42 0.905 0.53 0.030],'String',{'SURF (features)','Phase-corr (patch)'}, ...
        'Value',1, ...
        'TooltipString',['SURF: texture-rich areas. Phase-corr: small/smooth patches ', ...
                         '(more reliable for VERY small areas).'], ...
        'Callback',@(s,e) i_onMethod(fig));
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.05 0.862 0.55 0.028],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'String','Reference band ±(px):');
    h.edTol = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.62 0.862 0.30 0.030],'String','2','BackgroundColor',WHITE, ...
        'TooltipString','A ±N px band as a VISUAL REFERENCE on the plot. It does not judge the ROI.');
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.05 0.820 0.55 0.028],'HorizontalAlignment','left', ...
        'BackgroundColor',WHITE,'String','Max frames (0=all):');
    h.edMax = uicontrol('Parent',pnlR,'Style','edit','Units','normalized', ...
        'Position',[0.62 0.820 0.30 0.030],'String','0','BackgroundColor',WHITE, ...
        'TooltipString','Limit how many frames are tested (faster). 0 = use every frame.');
    h.btnRecalc = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.05 0.778 0.90 0.034],'String','Recompute (params above)', ...
        'Enable','off', ...
        'TooltipString',['RECOMPUTE the selected exp''s jitter with the method/max-frames above. ', ...
                         'Same as "Compute Jitter" in the middle column.'], ...
        'Callback',@(s,e) i_recompute(fig));
    % Toggle MODE drift kumulatif (hanya cara plot/ukur — TIDAK hitung ulang
    % frame). SIGNED = perpindahan bersih (cumsum d, bisa saling meniadakan).
    % ABSOLUT = panjang lintasan total (cumsum|d|, selalu naik — total getaran).
    h.chkCumAbs = uicontrol('Parent',pnlR,'Style','checkbox','Units','normalized', ...
        'Position',[0.05 0.742 0.90 0.030],'BackgroundColor',WHITE, ...
        'String','ABSOLUTE cumulative (path length)', 'Value',0, ...
        'TooltipString',['OFF = SIGNED: net displacement, +/- can cancel each ', ...
                         'other out. ON = ABSOLUTE: sum of |d| (always rising) ', ...
                         '= total vibration. Changes only the curves & "drift", ', ...
                         'not the per-frame measurement.'], ...
        'Callback',@(s,e) i_onToggleCumAbs(fig));

    % -- Navigasi --
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.05 0.706 0.90 0.024],'HorizontalAlignment','left', ...
        'FontWeight','bold','BackgroundColor',WHITE,'String','Navigation');
    h.btnPrev = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.05 0.666 0.43 0.036],'String','◀ Previous', ...
        'Callback',@(s,e) i_nav(fig,-1));
    h.btnNext = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.52 0.666 0.43 0.036],'String','Next Exp ▶', ...
        'TooltipString','Go to the next experiment (preferring one without an ROI).', ...
        'Callback',@(s,e) i_nav(fig,+1));
    h.txtProg = uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.05 0.602 0.90 0.024],'HorizontalAlignment','left', ...
        'FontSize',9,'BackgroundColor',WHITE,'String','Done: 0/0   ROI: 0/0');

    % -- Progress GRAIN1 (ROI/jitter) — simpan/muat lintas sesi --
    %    Berkas KHUSUS GRAIN1: <ROOT>/PAB1_progress.mat (beda dgn QPIV
    %    <ROOT>/PAB0_progress.mat & handoff <ROOT>/PAB_progress.mat).
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.05 0.572 0.90 0.026],'HorizontalAlignment','left', ...
        'FontWeight','bold','BackgroundColor',WHITE,'String','Progress GRAIN1 (ROI + jitter)');
    h.btnSaveProg = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.05 0.534 0.44 0.040],'String','💾 Save Progress', ...
        'BackgroundColor',[0.80 0.90 0.80], ...
        'TooltipString','Overwrite <ROOT>/PAB1_progress.mat (ROI + jitter results of every exp). No dialog.', ...
        'Callback',@(s,e) i_onSavePab1Progress(fig));
    h.btnLoadProg = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.51 0.534 0.44 0.040],'String','📂 Load Progress', ...
        'BackgroundColor',[0.86 0.93 0.99], ...
        'TooltipString','Load <ROOT>/PAB1_progress.mat (or pick a file) — carry on with the ROI work.', ...
        'Callback',@(s,e) i_onLoadPab1Progress(fig));

    % -- Keluaran / handoff ke Step 2 (GRAIN) --
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.05 0.500 0.90 0.026],'HorizontalAlignment','left', ...
        'FontWeight','bold','BackgroundColor',WHITE,'String','Output (Step 2 input)');
    h.btnExport = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.05 0.462 0.90 0.038],'String','Export → Step 2 (pick location)…', ...
        'TooltipString',['Write a BatchPIVPrep2 progress file holding every exp + ', ...
                         'anchor to the chosen location. Open Step 2 -> Load Progress -> Run.'], ...
        'Callback',@(s,e) i_onExport(fig));
    % Alur kanonik: GRAIN1 -> GRAINMASK (masking) -> GRAIN2 (produksi MAT PIV).
    % Tombol utama produksi MAT PREP lalu buka GRAINMASK. Tombol kedua = jalur
    % pintas langsung ke Step 2 bagi yang tak perlu masking.
    % URUTAN BARU (GRAIN0->GRAINMASK->GRAIN1->GRAIN2): masking sudah digambar di GRAINMASK
    % (foto mentah). Tombol UTAMA = produksi MAT PREP (+tempel resep masking dari
    % progres terpadu sbg sidecar) lalu ke GRAIN2. Tombol KEDUA = alur lama (buka
    % GRAINMASK di atas MAT PREP) utk yang belum masking.
    h.btnOpenStep1 = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.05 0.420 0.90 0.040],'String','Produce MAT PREP → GRAIN2 ▶', ...
        'FontWeight','bold','BackgroundColor',[0.90 0.94 0.99], ...
        'TooltipString',['Pick the LOCATION + NAME of the output folder, produce MAT PREP there ', ...
                         '(+attach the GRAINMASK masking recipe as a sidecar), then open GRAIN2. ', ...
                         'Flow: GRAIN0 -> GRAINMASK -> GRAIN1 -> GRAIN2.'], ...
        'Callback',@(s,e) i_produceAndAdvance(fig,'step2'));
    h.btnOpenMask = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.05 0.380 0.90 0.036],'String','…or open GRAINMASK on MAT PREP (legacy)', ...
        'BackgroundColor',[0.93 0.90 0.99], ...
        'TooltipString',['Produce MAT PREP then open GRAINMASK POINTED at the .mat folder ', ...
                         '(legacy GRAIN1->GRAINMASK flow). Use it if the raw photos were not masked yet.'], ...
        'Callback',@(s,e) i_produceAndAdvance(fig,'mask'));
    h.btnSaveAnchor = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.05 0.340 0.90 0.030],'String','Save this exp''s anchor…', ...
        'Enable','off', ...
        'TooltipString','Save the selected exp''s anchor preset (.mat) — for a manual Load in Step 1.', ...
        'Callback',@(s,e) i_onSaveAnchor(fig));
    h.btnExportPNG = uicontrol('Parent',pnlR,'Style','pushbutton','Units','normalized', ...
        'Position',[0.05 0.302 0.90 0.030],'String','Export this exp''s curves as PNG…', ...
        'Enable','off', ...
        'TooltipString','Save the selected exp''s jitter plot (2 panels) as a PNG.', ...
        'Callback',@(s,e) i_onExportPNG(fig));

    % -- Petunjuk --
    uicontrol('Parent',pnlR,'Style','text','Units','normalized', ...
        'Position',[0.05 0.045 0.90 0.300],'HorizontalAlignment','left', ...
        'FontSize',8,'BackgroundColor',WHITE, ...
        'String',{ ...
            'Flow:', ...
            ' 1. Pick an exp on the left.', ...
            ' 2. Draw a SMALL ROI on a part', ...
            '    that SHOULD BE STILL (fixed', ...
            '    frame — NOT the sand/pushing', ...
            '    wall). ▭ drag once.', ...
            ' 3. Press "Compute Jitter ▶"; check', ...
            '    the 4 curves. Drift = external', ...
            '    vibration, zeroed out in Step 1.', ...
            ' 4. "Save + Next" -> sweep to the', ...
            '    next unfinished exp.', ...
            ' 5. "Export/Open Step 1".', ...
            '', ...
            'ROI shortcuts:', ...
            ' • "⇇ ROI from previous exp": borrow', ...
            '   the ROI (same spot), edit if needed.', ...
            ' • "ROI ⇉ other exps": spread it to', ...
            '   every exp without an ROI.', ...
            'Drift: toggle SIGNED (net) vs', ...
            'ABSOLUTE (path length/total).', ...
            '', ...
            'Crop of each exp = full-frame;', ...
            'set the real crop in Step 1.'});

    % -- Status (strip bawah, full width) --
    h.txtStatus = uicontrol('Parent',fig,'Style','text','Units','normalized', ...
        'Position',[0.006 0.001 0.985 0.022], ...
        'HorizontalAlignment','left','FontSize',9,'BackgroundColor',WHITE, ...
        'String','Pick a ROOT, then scan its subfolders.');
end


% =====================================================================
% Pindai ROOT -> daftar eksperimen (rekursif, identik Step 1)
% =====================================================================
function i_onPickRoot(fig)
    h = guidata(fig);
    i_minimize(fig);
    d = uigetdir(h.root, 'Pick a ROOT folder (subfolders are scanned as experiments)');
    i_restore(fig);
    if isequal(d, 0), return; end
    h.root = d; set(h.txtRoot,'String',d);
    guidata(fig, h);
    i_rescan(fig);
end


function i_rescan(fig)
    h = guidata(fig);
    i_setStatus(fig,'Scanning subfolders…'); set(fig,'Pointer','watch'); drawnow;
    cleaner = onCleanup(@() set(fig,'Pointer','arrow'));

    % Arahkan engine progres ke berkas QPIV per-root (<root>/PAB0_progress.mat)
    % supaya filter "frame lolos QPIV" membaca progres yang BENAR — baik saat
    % diluncurkan dari GRAIN0 maupun standalone.
    try
        pf = fullfile(h.root, 'PAB0_progress.mat');
        if isfile(pf); PIVlab_automasi_progress('setfile', pf); end
    catch
    end

    try
        found = batchpivprep2.io.collectFolders(h.root, true);   % rekursif
    catch ME
        i_setStatus(fig, sprintf('Scan failed: %s', ME.message));
        found = struct('path',{},'files',{},'nImg',{});
    end

    exps = i_emptyExps();
    nFiltered = 0; nDropTot = 0; warnExps = {};
    for i = 1:numel(found)
        e = i_emptyExps(); e(1).path = found(i).path; %#ok<NASGU>
        % SARING: hanya gambar yang LOLOS QPIV (Step 0). Frame ber-drop dibuang.
        [keptFiles, qinfo] = i_qpivKeptImages(found(i).path, found(i).files);
        if qinfo.hasQpiv && qinfo.nDrop > 0
            nFiltered = nFiltered + 1; nDropTot = nDropTot + qinfo.nDrop;
        end
        if isfield(qinfo,'mapWarn') && ~isempty(qinfo.mapWarn)
            warnExps{end+1} = sprintf('%s: %s', ...
                i_expName(h.root, found(i).path), qinfo.mapWarn); %#ok<AGROW>
        end
        ne = struct( ...
            'path',   found(i).path, ...
            'name',   i_expName(h.root, found(i).path), ...
            'files',  {keptFiles}, ...
            'nImg',   numel(keptFiles), ...
            'qOut',   qinfo.qOut, ...    % output frame QPIV (GRAIN0 kolom 4); [] bila tak ada
            'hasQpiv',qinfo.hasQpiv, ... % true bila exp sudah lewat QPIV (Step 0)
            'roiPts', [], 'roiBox', [], ...
            'method', h.method, ...
            'result', [], 'done', false);
        exps(end+1) = ne; %#ok<AGROW>
    end
    h.exps = exps; h.activeRow = 0; h.selRows = [];
    guidata(fig, h);

    % AUTO-LOAD progress GRAIN1 per-root bila ada (kembalikan ROI+jitter).
    if ~isempty(exps) && isfile(fullfile(h.root,'PAB1_progress.mat'))
        try, i_onLoadPab1Progress(fig); h = guidata(fig); exps = h.exps; catch, end
    end

    i_fillTable(fig);
    i_setEnableOutputs(fig,false,false);
    cla(h.ax); axis(h.ax,'off'); title(h.ax,'Pick an experiment on the left');
    i_clearCurves(fig);
    i_setEnableDraw(fig,false);
    i_updateProgText(fig);
    if isempty(exps)
        set(h.txtCount,'String','0 experiments (no subfolder holds images).');
        i_setStatus(fig,'No subfolder in this ROOT holds an image sequence.');
    else
        set(h.txtCount,'String',sprintf('%d experiments found.', numel(exps)));
        if ~isempty(warnExps)
            % PEMETAAN QPIV bermasalah (nama tak cocok) -> peringatan TEGAS,
            % diprioritaskan di atas ringkasan biasa.
            i_setStatus(fig, sprintf('⚠ QPIV MAPPING: %s', strjoin(warnExps, '  |  ')));
        elseif nFiltered > 0
            i_setStatus(fig,sprintf(['%d experiments. %d exps filtered by QPIV (%d images ' ...
                'dropped) — only frames that passed QPIV are used.'], numel(exps), nFiltered, nDropTot));
        else
            i_setStatus(fig,sprintf('%d experiments. Pick one, then draw an ROI.', numel(exps)));
        end
    end
end


function i_fillTable(fig)
    h = guidata(fig);
    n = numel(h.exps);
    C = cell(n,5);
    for i = 1:n
        e = h.exps(i);
        C{i,1} = e.name;
        % Kolom "Frame" = output QPIV (GRAIN0 kolom 4) bila ada; jika tidak, jumlah
        % gambar. Exp yang BELUM lewat QPIV ditandai "~N ⚠" (frame diam/mati belum
        % tersaring -> berisiko membesarkan MAT PREP; lihat i_produceAndAdvance).
        if isfield(e,'qOut') && ~isempty(e.qOut)
            C{i,2} = e.qOut;
        elseif isfield(e,'hasQpiv') && ~isempty(e.hasQpiv) && ~e.hasQpiv
            C{i,2} = sprintf('~%d ⚠', e.nImg);
        else
            C{i,2} = e.nImg;
        end
        if isempty(e.roiBox), C{i,3} = '—'; else, C{i,3} = '✓'; end
        C{i,4} = i_jitLabel(e, h.cumAbs);
        if isfield(e,'done') && ~isempty(e.done) && e.done, C{i,5} = '✓'; else, C{i,5} = ''; end
    end
    set(h.tbl,'Data',C);
end


function lbl = i_jitLabel(e, cumAbs)
%I_JITLABEL  Label ringkas status jitter exp (BUKAN vonis layak/tidak).
%   Drift mengikuti mode kumulatif aktif (SIGNED vs ABSOLUT).
    if nargin < 2, cumAbs = false; end
    if isempty(e.result)
        if isempty(e.roiBox), lbl = '—'; else, lbl = '(ready)'; end
        return;
    end
    R = e.result;
    if isfield(R,'failMsg') && ~isempty(R.failMsg)
        lbl = '! meas'; return;     % gagal terukur (mis. fitur kurang)
    end
    if cumAbs && isfield(R,'driftMagAbs')
        lbl = sprintf('drift %.1f', R.driftMagAbs);
    else
        lbl = sprintf('drift %.1f', R.driftMag);
    end
end


% =====================================================================
% Pilih baris / navigasi
% =====================================================================
function i_onSelectRow(fig, evt)
    if isempty(evt) || isempty(evt.Indices), return; end
    h = guidata(fig);
    % Rekam SEMUA baris terpilih (untuk hapus multi); muat baris pertama ke view.
    rows = unique(evt.Indices(:,1))';
    rows = rows(rows >= 1 & rows <= numel(h.exps));
    h.selRows = rows;
    if isempty(rows), guidata(fig, h); return; end
    row = rows(1);
    h.activeRow = row; guidata(fig, h);
    i_loadExp(fig);
end


% =====================================================================
% Hapus eksperimen dari DAFTAR (bukan dari disk) — scan rekursif agresif
% =====================================================================
function i_onDeleteExps(fig)
    h = guidata(fig);
    n = numel(h.exps);
    if n == 0, i_setStatus(fig,'The list is empty.'); return; end

    rows = h.selRows;
    if isempty(rows) && h.activeRow >= 1, rows = h.activeRow; end
    rows = unique(rows(:))';
    rows = rows(rows >= 1 & rows <= n);
    if isempty(rows)
        i_setStatus(fig,'Select the experiments to remove in the table first.'); return;
    end

    if numel(rows) == 1
        nm = h.exps(rows).name;
        q = sprintf('Remove experiment "%s" from the list?', nm);
    else
        q = sprintf('Remove %d selected experiments from the list?', numel(rows));
    end
    % Tegaskan: hanya keluar dari daftar/input Step 1, folder tetap di disk.
    btn = questdlg([q char(10) char(10) ...
        'Folders on disk are NOT deleted — they just leave the Step 1 input.'], ...
        'GRAIN1 — Remove from list', 'Remove', 'Cancel', 'Cancel');
    if ~strcmp(btn,'Remove'), return; end

    keep = true(1, n); keep(rows) = false;
    h.exps     = h.exps(keep);
    h.selRows  = [];
    % Sesuaikan baris aktif.
    if isempty(h.exps)
        h.activeRow = 0;
    else
        h.activeRow = min(max(1, min(rows)), numel(h.exps));
    end
    guidata(fig, h);

    i_fillTable(fig);
    set(h.txtCount,'String',sprintf('%d experiments.', numel(h.exps)));
    i_updateProgText(fig);
    if isempty(h.exps)
        cla(h.ax); axis(h.ax,'off'); title(h.ax,'Pick an experiment on the left');
        i_clearCurves(fig);
        i_setEnableDraw(fig,false);
        i_setEnableOutputs(fig,false,false);
    else
        i_selectTableRow(fig, h.activeRow);
        i_loadExp(fig);
    end
    i_setStatus(fig, sprintf('%d experiments removed from the list (folders on disk intact).', ...
        numel(rows)));
end


function i_onClearExps(fig)
    h = guidata(fig);
    if isempty(h.exps), i_setStatus(fig,'The list is already empty.'); return; end
    btn = questdlg(['Clear the WHOLE experiment list?' char(10) char(10) ...
        'Folders on disk are NOT deleted.'], ...
        'GRAIN1 — Clear list', 'Clear', 'Cancel', 'Cancel');
    if ~strcmp(btn,'Clear'), return; end
    h.exps = i_emptyExps(); h.activeRow = 0; h.selRows = [];
    guidata(fig, h);
    i_fillTable(fig);
    set(h.txtCount,'String','0 experiments.');
    i_updateProgText(fig);
    cla(h.ax); axis(h.ax,'off'); title(h.ax,'Pick an experiment on the left');
    i_clearCurves(fig);
    i_setEnableDraw(fig,false); i_setEnableOutputs(fig,false,false);
    i_setStatus(fig,'List cleared. Rescan the ROOT if needed.');
end


function i_nav(fig, dir)
    h = guidata(fig);
    n = numel(h.exps);
    if n == 0, return; end
    cur = h.activeRow; if cur < 1, cur = 0; end
    if dir > 0
        % Next: utamakan exp BERIKUTNYA yang belum punya ROI; jika tak ada,
        % maju satu langkah biasa (melingkar).
        nxt = 0;
        for k = cur+1:n
            if isempty(h.exps(k).roiBox), nxt = k; break; end
        end
        if nxt == 0, nxt = min(n, max(1,cur+1)); end
        if nxt == cur, nxt = min(n, cur+1); end
        row = nxt;
    else
        row = max(1, cur-1);
    end
    h.activeRow = row; guidata(fig, h);
    i_selectTableRow(fig, row);
    i_loadExp(fig);
end


function i_loadExp(fig)
%I_LOADEXP  Tampilkan frame-1 exp aktif + ROI + kurva (bila ada).
    h = guidata(fig);
    row = h.activeRow;
    if row < 1 || row > numel(h.exps), return; end
    e = h.exps(row);

    % Set kontrol metode ke milik exp.
    set(h.popMethod,'Value', strcmp(e.method,'phasecorr')+1);

    i_showRef(fig);
    i_updateRoiInfo(fig);
    i_renderJitter(fig);
    i_setEnableDraw(fig, true);
    i_setEnableOutputs(fig, ~isempty(e.roiBox), ~isempty(e.result));
    % "ROI exp sebelumnya": aktif bila ada exp di urutan sebelumnya yg ber-ROI.
    canPrev = row >= 2 && ~isempty(h.exps(row-1).roiBox);
    set(h.btnRoiFromPrev, 'Enable', i_on(canPrev));
    if isempty(e.roiBox)
        msg = sprintf('Exp %d/%d: %s — draw a small ROI on a still part.', ...
            row, numel(h.exps), e.name);
    elseif isempty(e.result)
        msg = sprintf('Exp %d/%d: %s — ROI set; press "Compute Jitter ▶".', ...
            row, numel(h.exps), e.name);
    else
        msg = sprintf('Exp %d/%d: %s — drift |%.2f| px.', ...
            row, numel(h.exps), e.name, e.result.driftMag);
    end
    i_setStatus(fig, msg);
end


function i_showRef(fig)
    h = guidata(fig);
    row = h.activeRow; e = h.exps(row);
    cla(h.ax,'reset');
    img = i_readRef(e);
    if isempty(img)
        axis(h.ax,'off'); title(h.ax,'(failed to read frame-1)'); return;
    end
    imshow(img,'Parent',h.ax);
    title(h.ax, sprintf('%s — frame 1 (%s)', e.name, e.files{1}), 'Interpreter','none');
    if ~isempty(e.roiPts)
        hold(h.ax,'on'); p = e.roiPts;
        patch(h.ax,'XData',p(:,1),'YData',p(:,2), ...
            'FaceColor','y','FaceAlpha',0.18,'EdgeColor','y','LineWidth',1.6);
        plot(h.ax,[p(:,1);p(1,1)],[p(:,2);p(1,2)],'y-','LineWidth',1.6);
        hold(h.ax,'off');
    end
end


% =====================================================================
% Gambar ROI — TARIK SEKALI, langsung tersimpan (drawrectangle blocking)
% =====================================================================
function i_onDrawROI(fig, mode)
    h = guidata(fig);
    row = h.activeRow;
    if row < 1, i_setStatus(fig,'Pick an experiment first.'); return; end

    i_showRef(fig);   % bersihkan overlay lama
    i_setStatus(fig,'Draw the ROI now (drag/click)…');

    % drawrectangle/drawpolygon BLOCKING: kembali setelah user SELESAI menggambar
    % (rect: lepas-mouse; poly: tutup polygon). Tarik SEKALI, tanpa double-click.
    % (Dulu pakai listener DrawingFinished -> RACE: event sudah lewat saat
    %  listener dipasang, jadi ROI tak pernah ter-commit & tombol Hitung tetap
    %  grey. Sekarang commit langsung dari objek yg dikembalikan.)
    try
        if strcmp(mode,'rect')
            roi = drawrectangle(h.ax,'Color','y','LineWidth',1.6);
        else
            roi = drawpolygon(h.ax,'Color','y','LineWidth',1.6);
        end
    catch ME
        i_setStatus(fig, sprintf('Failed to draw the ROI: %s', ME.message));
        return;
    end
    if isempty(roi) || ~isvalid(roi)
        i_setStatus(fig,'ROI cancelled.'); return;
    end
    i_commitROI(fig, roi, mode);
end


function i_commitROI(fig, roi, mode)
%I_COMMITROI  Commit ROI yg baru selesai digambar -> SIMPAN saja (TIDAK
%   auto-hitung). Jitter dihitung HANYA saat user tekan "Hitung Jitter".
    h = guidata(fig);
    row = h.activeRow;
    if row < 1 || ~isvalid(roi), return; end
    e = h.exps(row);

    if strcmp(mode,'rect')
        pos = roi.Position;             % [x y w h]
        if isempty(pos) || pos(3) < 1 || pos(4) < 1
            i_setStatus(fig,'ROI dropped (too small).'); return;
        end
        x=pos(1); y=pos(2); w=pos(3); hh=pos(4);
        pts = [x y; x+w y; x+w y+hh; x y+hh];
    else
        pts = roi.Position;             % Nx2
        if size(pts,1) < 3
            i_setStatus(fig,'ROI dropped (polygon has < 3 points).'); return;
        end
    end

    img = i_readRef(e);
    if isempty(img), i_setStatus(fig,'Failed to read frame-1.'); return; end
    H = size(img,1); W = size(img,2);
    pts(:,1) = min(max(pts(:,1),1), W);
    pts(:,2) = min(max(pts(:,2),1), H);
    box = [min(pts(:,1)), min(pts(:,2)), ...
           max(pts(:,1))-min(pts(:,1)), max(pts(:,2))-min(pts(:,2))];

    h.exps(row).roiPts = pts;
    h.exps(row).roiBox = box;
    h.exps(row).result = [];
    guidata(fig, h);

    % Buang ROI interaktif (kita gambar overlay statis sendiri).
    try, delete(roi); catch, end

    i_showRef(fig);
    i_updateRoiInfo(fig);
    i_renderJitter(fig);                 % kosongkan kurva lama (result di-reset)
    i_fillTable(fig);
    i_selectTableRow(fig, row);
    i_setEnableOutputs(fig, true, false);  % ROI ada, hasil belum
    i_updateProgText(fig);
    i_setStatus(fig, sprintf('ROI[%.0f %.0f %.0f %.0f] saved — press "Compute Jitter ▶".', ...
        box(1),box(2),box(3),box(4)));
end


function i_onClearROI(fig)
    h = guidata(fig);
    row = h.activeRow; if row < 1, return; end
    h.exps(row).roiPts = []; h.exps(row).roiBox = []; h.exps(row).result = [];
    guidata(fig, h);
    i_showRef(fig); i_updateRoiInfo(fig); i_renderJitter(fig);
    i_fillTable(fig); i_selectTableRow(fig, row);
    i_setEnableOutputs(fig, false, false);
    i_updateProgText(fig);
    i_setStatus(fig,'ROI cleared for this exp.');
end


% =====================================================================
% Pinjam / sebar ROI antar-eksperimen (posisi piksel SAMA; TIDAK auto-hitung)
% =====================================================================
function i_onRoiFromPrev(fig)
%I_ONROIFROMPREV  Salin ROI dari exp nomor urut SEBELUMNYA ke exp aktif (posisi
%   piksel sama). User boleh langsung mengubah, lalu tekan "Hitung Jitter".
    h = guidata(fig);
    row = h.activeRow;
    if row < 2
        i_setStatus(fig,'There is no previous experiment.'); return;
    end
    prev = h.exps(row-1);
    if isempty(prev.roiPts) || isempty(prev.roiBox)
        i_setStatus(fig, sprintf('The previous exp ("%s") has no ROI yet.', prev.name));
        return;
    end
    [pts, box, ok] = i_applyRoiPts(h.exps(row), prev.roiPts);
    if ~ok, i_setStatus(fig,'Failed to read this exp''s frame-1.'); return; end
    h.exps(row).roiPts = pts;
    h.exps(row).roiBox = box;
    h.exps(row).result = [];          % ROI berubah -> hasil lama batal
    guidata(fig, h);

    i_showRef(fig); i_updateRoiInfo(fig); i_renderJitter(fig);
    i_fillTable(fig); i_selectTableRow(fig, row);
    i_setEnableOutputs(fig, true, false);
    i_updateProgText(fig);
    i_setStatus(fig, sprintf(['ROI copied from "%s". Edit if needed, then ', ...
        '"Compute Jitter ▶".'], prev.name));
end


function i_onRoiToOthers(fig)
%I_ONROITOOTHERS  Terapkan ROI exp aktif ke SEMUA exp yang BELUM punya ROI
%   (posisi piksel sama). Yang sudah ber-ROI TIDAK ditimpa (aman). TIDAK
%   menghitung jitter — biar "Next Exp" menampilkan ROI siap diubah.
    h = guidata(fig);
    row = h.activeRow;
    if row < 1 || isempty(h.exps(row).roiPts)
        i_setStatus(fig,'Pick an exp that has an ROI first.'); return;
    end
    src = h.exps(row);
    targets = find(arrayfun(@(e) isempty(e.roiBox), h.exps));
    targets = targets(targets ~= row);
    if isempty(targets)
        i_setStatus(fig,'Every other experiment already has an ROI (nothing overwritten).');
        return;
    end
    nApplied = 0; nFail = 0;
    for t = targets(:)'
        [pts, box, ok] = i_applyRoiPts(h.exps(t), src.roiPts);
        if ~ok, nFail = nFail + 1; continue; end
        h.exps(t).roiPts = pts;
        h.exps(t).roiBox = box;
        h.exps(t).result = [];
        nApplied = nApplied + 1;
    end
    guidata(fig, h);

    i_fillTable(fig); i_selectTableRow(fig, row);
    i_updateProgText(fig);
    msg = sprintf('ROI "%s" applied to %d exps that had no ROI.', src.name, nApplied);
    if nFail > 0, msg = sprintf('%s (%d failed to read a frame).', msg, nFail); end
    i_setStatus(fig, msg);
end


function [pts, box, ok] = i_applyRoiPts(e, srcPts)
%I_APPLYROIPTS  Klem titik ROI sumber ke ukuran frame-1 exp tujuan & hitung box.
    pts = []; box = []; ok = false;
    img = i_readRef(e);
    if isempty(img), return; end
    H = size(img,1); W = size(img,2);
    pts = srcPts;
    pts(:,1) = min(max(pts(:,1),1), W);
    pts(:,2) = min(max(pts(:,2),1), H);
    box = [min(pts(:,1)), min(pts(:,2)), ...
           max(pts(:,1))-min(pts(:,1)), max(pts(:,2))-min(pts(:,2))];
    ok = true;
end


function i_updateRoiInfo(fig)
    h = guidata(fig); row = h.activeRow;
    if row < 1 || isempty(h.exps(row).roiBox)
        set(h.txtRoiInfo,'String','ROI: (none)'); return;
    end
    b = h.exps(row).roiBox;
    set(h.txtRoiInfo,'String',sprintf('ROI[%.0f %.0f %.0f %.0f]', b(1),b(2),b(3),b(4)));
end


% =====================================================================
% Hitung jitter SATU exp — engine SAMA Step 1 (roiPad=0, lastGood=I)
% =====================================================================
function i_computeExp(fig, row, advanceOnDone, prog)
%   prog (opsional): struct progress bar bersama dari "Hitung jitter SEMUA"
%   berisi .wb (handle waitbar), .base & .span (segmen 0..1), .prefix (teks).
%   Bila kosong -> buat waitbar sendiri (mode single) lalu tutup saat selesai.
    if nargin < 4, prog = []; end
    h = guidata(fig);
    if row < 1 || row > numel(h.exps), return; end
    e = h.exps(row);
    if isempty(e.roiBox), return; end

    set(fig,'Pointer','watch'); drawnow;
    cleaner = onCleanup(@() set(fig,'Pointer','arrow'));

    % Progress bar: pakai milik pemanggil (mode SEMUA) atau buat sendiri (single).
    ownWb = isempty(prog);
    if ownWb
        wb = i_makeWaitbar(sprintf('Computing jitter for "%s"…', e.name));
        prog = struct('wb',wb,'base',0,'span',1,'prefix',sprintf('"%s" ', e.name));
    end
    cleanerWb = onCleanup(@() i_closeIf(ownWb, prog.wb)); %#ok<NASGU>

    method = e.method;
    img1 = i_readRef(e);
    if isempty(img1), i_setStatus(fig,'Failed to read frame-1.'); return; end

    R = struct('fr',[],'dx',[],'dy',[],'cumDx',[],'cumDy',[],'jit',[], ...
        'ok',[],'tol',max(0,i_readNum(h.edTol,2)),'method',method, ...
        'nUse',0,'nAll',e.nImg,'driftMag',0,'failMsg','');

    % Referensi atas ROI KECIL persis.
    try
        ref = pivprep.stab.buildReference(img1, e.roiBox, method);
    catch ME
        R.failMsg = sprintf('buildReference: %s', ME.message);
        h.exps(row).result = R; guidata(fig,h);
        i_fillTable(fig); i_renderJitter(fig);
        i_setStatus(fig, ['Failed: ' R.failMsg]); return;
    end
    if strcmp(method,'surf') && isfield(ref,'nPoints') && ref.nPoints == 0
        R.failMsg = 'No SURF features inside the ROI (try a textured ROI / Phase-corr).';
        h.exps(row).result = R; guidata(fig,h);
        i_fillTable(fig); i_renderJitter(fig);
        i_setStatus(fig, R.failMsg); return;
    end

    nMax = i_readNum(h.edMax,0);
    if nMax > 0, nUse = min(nMax, e.nImg); else, nUse = e.nImg; end

    Iform = pivprep.util.utilities.identityTform();
    prm = struct('roiPad',0,'jitterTol',1e9,'lastGoodTform',Iform);

    % Sapu jitter SEMUA frame thd referensi frame-1. Loop antar-frame ini
    % INDEPENDEN: prm.lastGoodTform = identitas TETAP, jadi dx/dy diukur
    % LANGSUNG thd frame-1 (cumsum di bawah), tak ada ketergantungan k thd
    % k-1 -> aman diparalelkan. i_sweepFrames pakai PARFOR bila Parallel
    % Computing Toolbox ada & frame cukup banyak, selain itu serial; progress
    % (waitbar) di-update di KLIEN via DataQueue.
    [fr, dx, dy, jit, ok] = i_sweepFrames(fig, e, ref, prm, nUse, prog);
    % Simpan kedua basis kumulatif sekaligus (murah) supaya toggle
    % SIGNED<->ABSOLUT instan tanpa hitung ulang frame:
    %   cumDx/cumDy   = SIGNED   : cumsum(d)   (perpindahan bersih)
    %   cumAbsDx/Dy   = ABSOLUT  : cumsum(|d|) (panjang lintasan/total getaran)
    cumDx = cumsum(i_nz(dx));      cumDy = cumsum(i_nz(dy));
    cumAbsDx = cumsum(abs(i_nz(dx))); cumAbsDy = cumsum(abs(i_nz(dy)));

    R.fr=fr; R.dx=dx; R.dy=dy; R.cumDx=cumDx; R.cumDy=cumDy; R.jit=jit;
    R.cumAbsDx=cumAbsDx; R.cumAbsDy=cumAbsDy;
    R.ok=ok; R.nUse=nUse;
    R.driftMag    = hypot(cumDx(end),cumDy(end));      % SIGNED (perpindahan bersih)
    R.driftMagAbs = hypot(cumAbsDx(end),cumAbsDy(end)); % ABSOLUT (panjang lintasan)
    % CATATAN: 'done' (SELESAI) di-set HANYA oleh tombol "Simpan + Next",
    % bukan oleh hitung jitter. Menghitung ulang TIDAK mengubah status selesai.
    h.exps(row).result = R;
    guidata(fig, h);

    i_fillTable(fig); i_selectTableRow(fig, row);
    i_renderJitter(fig);
    i_setEnableOutputs(fig, true, true);
    i_updateProgText(fig);

    nFail = sum(~ok(2:end));
    msg = sprintf('Exp "%s": %d frames, drift |%.2f| px.', e.name, nUse, R.driftMag);
    if nFail>0, msg = sprintf('%s  (%d frames could not be measured)', msg, nFail); end
    i_setStatus(fig, msg);

    if advanceOnDone
        % biarkan pengguna melihat kurva; tidak auto-loncat. Sorot tombol Next.
    end
end


% =====================================================================
% Sapu jitter antar-frame — PARFOR bila tersedia (engine SAMA Step 1)
% =====================================================================
function [fr,dx,dy,jit,ok] = i_sweepFrames(fig, e, ref, prm, nUse, prog)
%I_SWEEPFRAMES  Ukur jitter tiap frame thd referensi frame-1.
%   Antar-frame INDEPENDEN (prm.lastGoodTform identitas tetap) sehingga aman
%   diparalelkan: pakai PARFOR bila Parallel Computing Toolbox ada & nUse
%   cukup besar, selain itu serial. cumsum kumulatif dilakukan pemanggil
%   (i_computeExp). Progress lewat waitbar di-update di KLIEN via DataQueue
%   (afterEach), jadi aman thd GUI meski badan loop jalan di worker.
    fr  = (1:nUse)';
    dx  = zeros(nUse,1);  dy  = zeros(nUse,1);
    jit = zeros(nUse,1);  ok  = false(nUse,1);
    ok(1) = true;                       % frame-1 = referensi (0,0)
    if nUse < 2, return; end

    files = e.files;  basePath = e.path;     % broadcast read-only ke worker
    nDone = 1;                               % frame-1 dianggap selesai (progress)
    hasWb = ~isempty(prog) && isfield(prog,'wb') && ...
            ~isempty(prog.wb) && isvalid(prog.wb);

    if i_useParfor(nUse)
        dq = parallel.pool.DataQueue;
        afterEach(dq, @(k) i_sweepTick());   % callback jalan di KLIEN (aman GUI)
        parfor k = 2:nUse
            [dx(k),dy(k),jit(k),ok(k)] = ...
                i_oneFrameJitter(basePath, files{k}, ref, prm);
            send(dq, k);
        end
    else
        for k = 2:nUse
            [dx(k),dy(k),jit(k),ok(k)] = ...
                i_oneFrameJitter(basePath, files{k}, ref, prm);
            if hasWb
                i_sweepTick();
            elseif mod(k,25)==0
                i_setStatus(fig,sprintf('… %d/%d frame', k, nUse));
                drawnow limitrate;
            end
        end
    end

    function i_sweepTick()
    %I_SWEEPTICK  (nested) Maju-kan progress waitbar di klien. Tak menyentuh
    %   variabel apa pun yang dipakai badan parfor -> aman thd transparansi.
        nDone = nDone + 1;
        if hasWb
            frac = prog.base + prog.span * (nDone/max(1,nUse));
            waitbar(min(1,max(0,frac)), prog.wb, ...
                sprintf('%sframe %d/%d', prog.prefix, nDone, nUse));
        end
    end
end


function [dx,dy,jit,ok] = i_oneFrameJitter(basePath, fname, ref, prm)
%I_ONEFRAMEJITTER  Ukur jitter SATU frame thd referensi (parfor-safe).
%   Tak menyentuh GUI/handle apa pun -> aman dipanggil di worker. Engine
%   identik Step 1 (pivprep.stab.estimateTransform). dx/dy SIGNED, jit>=0.
    try
        im  = imread(fullfile(basePath, fname));
        o   = pivprep.stab.estimateTransform(im, ref, prm);
        dx  = o.dx;  dy = o.dy;  jit = o.jitter;
        ok  = ~startsWith(o.status,'REJECT');
    catch
        dx = NaN;  dy = NaN;  jit = NaN;  ok = false;
    end
end


function tf = i_useParfor(nUse)
%I_USEPARFOR  Putuskan pakai parfor: butuh Parallel Computing Toolbox & frame
%   cukup banyak agar overhead pool sepadan. Tak memaksa worker-count — parfor
%   memakai pool aktif / auto-start pool default bila perlu (sekali, lalu
%   dipakai ulang antar-exp pd "Hitung jitter SEMUA").
    tf = false;
    if nUse < 24,                 return; end  % terlalu sedikit: serial lebih cepat
    if isempty(ver('parallel')),  return; end  % PCT tak ada -> serial
    tf = true;
end


function i_onComputeAll(fig)
%I_ONCOMPUTEALL  Hitung jitter untuk SEMUA exp ber-ROI yang belum ada hasilnya.
%   Exp tanpa ROI dilewati; exp yang sudah punya hasil tidak dihitung ulang.
%   Berguna saat ROI sama disebar ke semua exp ("ROI ⇉ exp lain").
    h = guidata(fig);
    n = numel(h.exps);
    if n == 0, i_setStatus(fig,'The list is empty.'); return; end

    rows = find(arrayfun(@(e) ~isempty(e.roiBox) && isempty(e.result), h.exps));
    if isempty(rows)
        if any(arrayfun(@(e) ~isempty(e.result), h.exps))
            i_setStatus(fig,'Every exp with an ROI already has a jitter result.');
        else
            i_setStatus(fig,'No exp has an ROI yet. Draw/spread one first.');
        end
        return;
    end

    wb = i_makeWaitbar('Computing jitter for ALL experiments…');
    cleanerWb = onCleanup(@() i_closeIf(true, wb)); %#ok<NASGU>
    N = numel(rows); nDone = 0;
    for ii = 1:N
        r = rows(ii);
        i_setStatus(fig, sprintf('Jitter for ALL — exp %d/%d: "%s"…', ...
            ii, N, h.exps(r).name)); drawnow;
        h.exps(r).method = h.method; guidata(fig, h);
        % Segmen progress bar bersama untuk exp ini: [ (ii-1)/N , ii/N ].
        prog = struct('wb',wb,'base',(ii-1)/N,'span',1/N, ...
            'prefix',sprintf('[%d/%d] %s — ', ii, N, h.exps(r).name));
        i_computeExp(fig, r, false, prog);
        h = guidata(fig);   % i_computeExp menyimpan hasil; muat ulang state
        nDone = nDone + 1;
    end
    i_setStatus(fig, sprintf('Finished computing jitter for %d experiments.', nDone));
end


function wb = i_makeWaitbar(msg)
%I_MAKEWAITBAR  Waitbar bertema terang (preferensi global) untuk progres jitter.
    if pivui.quiet(), wb = []; return; end   % tes senyap: tanpa waitbar (hasWb/i_closeIf aman utk [])
    wb = waitbar(0, msg, 'Name','GRAIN1 — jitter progress');
    try, set(wb,'Color',[1 1 1]); catch, end
    try, pivui.forceLightTheme(wb); catch, end
end

function i_closeIf(tf, wb)
%I_CLOSEIF  Tutup waitbar bila tf benar & handle masih valid.
    if tf && ~isempty(wb) && isvalid(wb), delete(wb); end
end


function i_recompute(fig)
    h = guidata(fig); row = h.activeRow;
    if row < 1 || isempty(h.exps(row).roiBox)
        i_setStatus(fig,'Pick an exp that has an ROI first.'); return;
    end
    % perbarui metode exp dari popup sebelum hitung.
    h.exps(row).method = h.method; guidata(fig,h);
    i_computeExp(fig, row, false);
end


% =====================================================================
% Render kurva DIPISAH 2 plot bertumpuk (APA ADANYA, tanpa smoothing):
%   axJit (atas)  = dx, dy           (jitter per-bingkai, SIGNED)
%   axCum (bawah) = cumDx, cumDy     (lintasan drift kumulatif)
% =====================================================================
function i_renderJitter(fig)
    h = guidata(fig);
    axT = h.axJit; axB = h.axCum;
    row = h.activeRow;
    cla(axT,'reset'); cla(axB,'reset');

    if row < 1 || isempty(h.exps(row).result)
        axis(axT,'off'); title(axT,'Per-frame jitter (dx, dy)');
        axis(axB,'off'); title(axB,'Cumulative drift (cumDx, cumDy)');
        return;
    end
    R = h.exps(row).result;
    if ~isempty(R.failMsg)
        axis(axT,'off');
        text(axT,0.5,0.5,R.failMsg,'Units','normalized', ...
            'HorizontalAlignment','center','Color',[0.7 0.2 0.1],'FontSize',9);
        title(axT,'Jitter — not measurable');
        axis(axB,'off'); title(axB,'');
        return;
    end

    fr = R.fr;
    nm = h.exps(row).name;
    head = sprintf('%s — %s, %d frame', nm, upper(R.method), R.nUse);

    % ---- ATAS: dx, dy (per-bingkai, apa adanya: garis lurus antar titik + '.') ----
    i_prepAxis(axT); hold(axT,'on');
    if R.tol > 0 && numel(fr) > 1
        xl = [min(fr) max(fr)];
        patch(axT,'XData',[xl(1) xl(2) xl(2) xl(1)],'YData',[-R.tol -R.tol R.tol R.tol], ...
            'FaceColor',[0.6 0.6 0.6],'FaceAlpha',0.10,'EdgeColor','none');
        plot(axT, xl, [ R.tol  R.tol], ':','Color',[0.45 0.45 0.45],'LineWidth',0.8);
        plot(axT, xl, [-R.tol -R.tol], ':','Color',[0.45 0.45 0.45],'LineWidth',0.8);
    end
    a1 = plot(axT, fr, R.dx, '-', 'Marker','.','MarkerSize',7, ...
        'Color',[0.20 0.45 0.85],'LineWidth',1.1);
    a2 = plot(axT, fr, R.dy, '-', 'Marker','.','MarkerSize',7, ...
        'Color',[0.85 0.25 0.20],'LineWidth',1.1);
    yline(axT, 0, '-', 'Color',[0.6 0.6 0.6],'LineWidth',0.7);
    if numel(fr) > 1, xlim(axT,[min(fr) max(fr)]); end
    ylabel(axT,'pixels');
    legend(axT,[a1 a2],{'dx','dy'},'Location','best','FontSize',7,'Orientation','horizontal');
    title(axT, sprintf('%s — per-frame jitter (dx, dy)', head),'Interpreter','none');
    hold(axT,'off');

    % ---- BAWAH: drift kumulatif — basis SIGNED atau ABSOLUT sesuai toggle ----
    %   SIGNED  : cumDx/cumDy   (perpindahan bersih; +/- bisa saling meniadakan)
    %   ABSOLUT : cumAbsDx/Dy   (panjang lintasan; cumsum|d|, selalu naik)
    [cx, cy, drift, modeStr, leg] = i_cumBasis(h, R);
    i_prepAxis(axB); hold(axB,'on');
    b1 = plot(axB, fr, cx, '-', 'Marker','.','MarkerSize',7, ...
        'Color',[0.05 0.20 0.55],'LineWidth',1.3);
    b2 = plot(axB, fr, cy, '-', 'Marker','.','MarkerSize',7, ...
        'Color',[0.55 0.10 0.10],'LineWidth',1.3);
    yline(axB, 0, '-', 'Color',[0.6 0.6 0.6],'LineWidth',0.7);
    if numel(fr) > 1, xlim(axB,[min(fr) max(fr)]); end
    xlabel(axB,'Frame'); ylabel(axB,'pixels');
    legend(axB,[b1 b2],leg,'Location','best','FontSize',7,'Orientation','horizontal');
    title(axB, sprintf('cumulative drift [%s] — final |%.2f| px', modeStr, drift), ...
        'Interpreter','none');
    hold(axB,'off');
end


function i_prepAxis(ax)
%I_PREPAXIS  Setel axes kurva (tema terang, grid). Tanpa smoothing apa pun.
    set(ax,'Color','w','XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
        'Box','on','Layer','top');
    grid(ax,'on');
end


function i_clearCurves(fig)
%I_CLEARCURVES  Kosongkan kedua axes kurva (atas dx/dy, bawah cumDx/cumDy).
    h = guidata(fig);
    cla(h.axJit); axis(h.axJit,'off'); title(h.axJit,'Per-frame jitter (dx, dy)');
    cla(h.axCum); axis(h.axCum,'off'); title(h.axCum,'Cumulative drift (cumDx, cumDy)');
end


% =====================================================================
% Keluaran: progress BatchPIVPrep2 / buka Step 1 / anchor / PNG
% =====================================================================
function prog = i_buildProgress(fig)
%I_BUILDPROGRESS  Bangun struct progress 'BatchPIVPrep2Progress' dari exps
%   yang punya ROI. Anchor = anchorPreset dari ROI; crop = full-frame.
    h = guidata(fig);
    folders = i_emptyFolders();
    nAnchor = 0; activeAnchor = [];
    for i = 1:numel(h.exps)
        e = h.exps(i);
        if isempty(e.roiBox), continue; end     % hanya exp yg sudah punya ROI
        img = i_readRef(e);
        imgSize = size(img,[1 2]);
        anchor = batchpivprep2.io.anchorPreset.fromPoints( ...
            e.roiPts, imgSize, e.method, img, ...
            sprintf('anchor0-%s', e.name), fullfile(e.path, e.files{1}));
        crop = batchpivprep2.io.cropPreset.makeNone(sprintf('full-%s', e.name));
        fe = struct( ...
            'path',       e.path, ...
            'files',      {e.files}, ...    % WAJIB: processFolder pakai folder.files
            'nImg',       e.nImg, ...
            'outName',    i_sanitize(e.name), ...
            'seqMode',    'consecutive', ...
            'seqStep',    1, ...
            'anchor',     anchor, ...
            'anchorName', anchor.name, ...
            'crop',       crop, ...
            'cropName',   crop.name);
        folders(end+1) = fe; %#ok<AGROW>
        nAnchor = nAnchor + 1; activeAnchor = anchor;
    end

    prog = struct();
    prog.type    = 'BatchPIVPrep2Progress';
    prog.version = 1;
    prog.folders       = folders;
    prog.activeAnchor  = activeAnchor;
    prog.activeCrop    = [];
    prog.cropMode      = 'crop';
    prog.marginEnabled = true;
    prog.marginPx      = 10;
    prog.outputRoot    = h.root;
    prog.settings = struct( ...
        'suffix','', 'stabMethodVal',1, ...
        'jitterTol', get(h.edTol,'String'), ...
        'rawFmtVal',1, 'rawQual','90', 'gsScale','50', 'gsQual','85', ...
        'cropModeVal',1, 'cropModeStr','crop', 'outLocRoot',1, ...
        'cumDriftAbs', h.cumAbs);   % mode drift kumulatif aktif (catatan)
    prog.savedAt = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    prog.nAnchored = nAnchor;
end


function i_onExport(fig)
    h = guidata(fig);
    prog = i_buildProgress(fig); %#ok<NASGU>
    if prog.nAnchored == 0
        i_setStatus(fig,'No exp with an ROI to export yet.'); return;
    end
    def = 'PAB_progress.mat';
    i_minimize(fig);
    [fn, fp] = uiputfile({'*.mat','BatchPIVPrep2 progress (*.mat)'}, ...
        'Export progress (Load it in Step 1)', def);
    i_restore(fig);
    if isequal(fn,0), return; end
    out = fullfile(fp, fn);
    try
        progress = prog; %#ok<NASGU>   % Step 1 mengharap variabel bernama 'progress'
        save(out, 'progress');
        i_setStatus(fig, sprintf('Exported: %s (%d exps). Open Step 1 -> Load Progress.', ...
            out, prog.nAnchored));
    catch ME
        i_setStatus(fig, sprintf('Export failed: %s', ME.message));
    end
end


function i_produceAndAdvance(fig, target)
%I_PRODUCEANDADVANCE  Handoff: TANYA lokasi+nama folder keluaran DULU, lalu
%   PRODUKSI MAT PREP semua exp ber-ROI (batch stabilisasi -> 1 .mat/exp dgn
%   EXIF+jitter+crop+flag), lalu LANJUT ke modul berikut menunjuk folder MAT
%   PREP itu (pola Simpan-Tutup-Lanjut). `target`:
%     'mask'  -> buka GRAINMASK(prepDir)  (alur kanonik: GRAIN1->GRAINMASK->GRAIN2)
%     'step2' -> buka GRAIN2(prepDir,true) (jalur pintas, lewati masking)
%   MAT PIV diproduksi PER-EXP on-demand di GRAIN2. Lokasi keluaran TIDAK default
%   ke root input.
    if nargin < 2 || isempty(target), target = 'mask'; end
    h = guidata(fig);
    prog = i_buildProgress(fig);
    if prog.nAnchored == 0
        i_setStatus(fig,'No exp has an ROI yet. Draw one first.'); return;
    end

    % PERINGATAN anti-bengkak: exp ber-ROI yang BELUM lewat QPIV (Step 0) akan
    % dikemas dengan SEMUA frame (termasuk frame diam/mati) -> MAT PREP membesar
    % tanpa disadari. Beri tahu user (non-blokir; boleh lanjut) SEBELUM memilih
    % folder & memproses.
    nNoQpiv = sum(arrayfun(@(e) ~isempty(e.roiBox) && ...
        isfield(e,'hasQpiv') && ~isempty(e.hasQpiv) && ~e.hasQpiv, h.exps));
    if nNoQpiv > 0
        btn = questdlg(sprintf([ ...
            '%d exps with an ROI have NOT been through QPIV (Step 0).' char(10) char(10) ...
            'Still/dead frames (machine stopped) are not filtered out yet, so EVERY frame ' ...
            'gets packed and BLOATS the MAT PREP.' char(10) char(10) ...
            'Better run Step 0 (GRAIN0) first. Produce anyway?'], ...
            nNoQpiv), ...
            'GRAIN1 — Experiments without QPIV', 'Produce anyway', 'Cancel', 'Cancel');
        if ~strcmp(btn,'Produce anyway')
            i_setStatus(fig, sprintf(['Cancelled — %d exps have no QPIV. ' ...
                'Run Step 0 (GRAIN0) first so dead frames do not bloat the MAT PREP.'], ...
                nNoQpiv));
            return;
        end
    end

    % Folder tujuan MAT PREP: TANYA user (LOKASI + NAMA folder) DULU, SEBELUM
    % menyimpan/memproses stabilisasi. JANGAN default diam-diam ke root input.
    prepDir = i_pickPrepOutput(fig);
    if isempty(prepDir)
        i_setStatus(fig,'Cancelled — no MAT PREP output location was picked.'); return;
    end

    % Simpan handoff BatchPIVPrep2 ke folder keluaran (jejak; tak wajib produksi).
    % (scanMats GRAIN2 hanya kenal pivprep_single_v1, jadi berkas ini diabaikan.)
    try
        progress = prog; %#ok<NASGU>
        save(fullfile(prepDir, 'PAB_progress.mat'), 'progress');
    catch
        % non-fatal: produksi MAT PREP tetap jalan dari prog di memori.
    end

    % cfg produksi MAT PREP (kemas 1 .mat/exp; RAW-only, GS diregen di GRAIN2).
    % Nilai diambil dari parameter GRAIN1 (jitterTol) + default selaras Step 1.
    jitterTol = str2double(get(h.edTol,'String'));
    if isnan(jitterTol), jitterTol = 50; end
    cfg = struct( ...
        'suffix','', 'stabMethod','surf', 'jitterTol', jitterTol, ...
        'roiPad',50, 'surfMaxRatio',0.60, 'minMatchPts',4, ...
        'marginEnabled', prog.marginEnabled, 'marginPx', prog.marginPx, ...
        'rawFormat','jpg', 'rawQuality',90, 'gsScale',0.5, 'gsQuality',85, ...
        'outputMode','root', 'outputRoot', prepDir, ...
        'packSingleMat', true, 'keepFolder', false, 'matOutDir', prepDir, ...
        'showSummaryDialog', false);   % tanpa pop-up ringkasan; lanjut ke GRAIN2

    i_setStatus(fig, sprintf('Producing MAT PREP for %d exps into %s …', prog.nAnchored, prepDir));
    drawnow;
    try
        results = batchpivprep2.core.runBatch(prog.folders, cfg);
    catch ME
        i_setStatus(fig, sprintf('MAT PREP production failed: %s', ME.message)); return;
    end

    % Verifikasi minimal: ada .mat PREP yang lahir?
    nMat = sum(arrayfun(@(r) isfield(r,'singleMat') && ~isempty(r.singleMat), results));
    if nMat == 0
        i_setStatus(fig, ['No MAT PREP was produced (check the console log). ', ...
            'The next module was not launched.']);
        return;
    end

    % URUTAN BARU (GRAIN0->GRAINMASK->GRAIN1): resep masking (kotak, ruang MENTAH)
    % sudah digambar di GRAINMASK & tersimpan di progres terpadu. Tempelkan sbg
    % SIDECAR '<matbase>_mask.json' di samping tiap MAT PREP yg baru lahir —
    % NON-DESTRUKTIF (blob asli utuh; ter-decode otomatis oleh GRAIN2/unpackMat).
    nSide = i_writeMaskSidecars(h.root, results);
    if nSide > 0
        i_setStatus(fig, sprintf('%d MAT PREP + %d masking recipes attached (sidecar).', nMat, nSide));
        drawnow;
    end

    % Pola SIMPAN-TUTUP-LANJUT: tutup GRAIN1, buka modul berikut menunjuk folder
    % MAT PREP. target 'mask' -> GRAINMASK (edit kotak putih), 'step2' -> GRAIN2.
    switch target
        case 'mask'
            i_setStatus(fig, sprintf('%d MAT PREP created. Launching GRAINMASK (masking)…', nMat));
            drawnow;
            try, delete(fig); catch, end
            try
                GRAINMASK(prepDir);
            catch ME
                warning('GRAIN1:openMask', 'MAT PREP saved in %s but GRAINMASK failed to open: %s', ...
                    prepDir, ME.message);
            end
        otherwise   % 'step2'
            i_setStatus(fig, sprintf('%d MAT PREP created. Launching Step 2 (GRAIN2)…', nMat));
            drawnow;
            try, delete(fig); catch, end
            try
                GRAIN2(prepDir, true);
            catch ME
                warning('GRAIN1:openStep2', 'MAT PREP saved in %s but GRAIN2 failed to open: %s', ...
                    prepDir, ME.message);
            end
    end
end


function prepDir = i_pickPrepOutput(fig)
%I_PICKPREPOUTPUT  Tanya LOKASI + NAMA folder keluaran MAT PREP SEBELUM produksi
%   stabilisasi. Kembalikan path folder (dibuat bila perlu) atau '' bila user
%   batal. Sengaja TIDAK default diam-diam ke root input — user wajib memilih.
    prepDir = '';
    h = guidata(fig);

    % 1) LOKASI (folder induk) keluaran. Mulai dari root input demi praktis,
    %    tapi user tetap harus mengonfirmasi/memilih (tak ada default senyap).
    startDir = h.root;
    if isempty(startDir) || ~isfolder(startDir), startDir = pwd; end
    i_minimize(fig);
    try
        parentDir = uigetdir(startDir, 'Pick the LOCATION of the MAT PREP output folder (Step 2 input)');
    catch
        parentDir = 0;
    end
    i_restore(fig);
    if isequal(parentDir, 0), return; end          % user batal

    % 2) NAMA folder keluaran (di dalam lokasi tadi). Pertahankan spasi, hanya
    %    buang karakter ilegal path; default 'MATPREP'.
    defName = 'MATPREP';
    answer = inputdlg('Name of the MAT PREP output folder:', 'Output folder name', ...
        [1 60], {defName});
    if isempty(answer), return; end                % user batal
    name = strtrim(answer{1});
    if isempty(name), name = defName; end
    name = regexprep(name, '[\\/:*?"<>|]+', '_');   % buang karakter ilegal path
    name = regexprep(name, '^[.\s]+|[.\s]+$', '');  % rapikan titik/spasi tepi
    if isempty(name), name = defName; end

    % 3) Bentuk path final; buat folder bila belum ada.
    candidate = fullfile(parentDir, name);
    try
        if ~isfolder(candidate), mkdir(candidate); end
    catch ME
        i_setStatus(fig, sprintf('Failed to create the output folder: %s', ME.message));
        return;
    end
    prepDir = candidate;
end


function i_onSavePab1Progress(fig)
%I_ONSAVEGRAIN1PROGRESS  Simpan state ROI+jitter GRAIN1 ke <ROOT>/PAB1_progress.mat
%   (berkas KHUSUS GRAIN1, beda dari QPIV/handoff). Tanpa dialog.
    h = guidata(fig);
    if isempty(h.exps), i_setStatus(fig,'No experiment to save yet.'); return; end
    out = fullfile(h.root, 'PAB1_progress.mat');
    pab1 = i_pab1State(h); %#ok<NASGU>
    try
        save(out, 'pab1');
        nRoi = sum(arrayfun(@(e) ~isempty(e.roiBox), h.exps));
        i_setStatus(fig, sprintf('GRAIN1 progress saved: %s (%d exps, %d with an ROI).', ...
            out, numel(h.exps), nRoi));
    catch ME
        i_setStatus(fig, sprintf('Failed to save the GRAIN1 progress: %s', ME.message));
    end
end


function i_onLoadPab1Progress(fig)
%I_ONLOADGRAIN1PROGRESS  Muat <ROOT>/PAB1_progress.mat (auto bila ada; jika tidak,
%   dialog). Kembalikan ROI + hasil jitter ke exp dengan path yang cocok.
    h = guidata(fig);
    def = fullfile(h.root, 'PAB1_progress.mat');
    if isfile(def)
        pf = def;
    else
        i_minimize(fig);
        [fn, fp] = uigetfile({'*.mat','GRAIN1 progress (*.mat)'}, ...
            'Load the GRAIN1 progress', h.root);
        i_restore(fig);
        if isequal(fn,0), return; end
        pf = fullfile(fp, fn);
    end
    try
        S = load(pf);
    catch ME
        i_setStatus(fig, sprintf('Failed to read the progress: %s', ME.message)); return;
    end
    if ~isfield(S,'pab1') || ~isfield(S.pab1,'exps')
        i_setStatus(fig,'That file is not a valid GRAIN1 progress.'); return;
    end
    saved = S.pab1.exps;
    nApplied = 0;
    for i = 1:numel(h.exps)
        idx = find(strcmp({saved.path}, h.exps(i).path), 1);
        if isempty(idx), continue; end
        s = saved(idx);
        h.exps(i).roiPts = s.roiPts; h.exps(i).roiBox = s.roiBox;
        h.exps(i).method = s.method; h.exps(i).result = s.result;
        h.exps(i).done   = s.done;
        nApplied = nApplied + 1;
    end
    if isfield(S.pab1,'cumAbs'), h.cumAbs = logical(S.pab1.cumAbs); end
    guidata(fig, h);
    try, set(h.chkCumAbs,'Value', h.cumAbs); catch, end
    i_fillTable(fig); i_updateProgText(fig);
    if h.activeRow >= 1 && h.activeRow <= numel(h.exps), i_loadExp(fig); end
    i_setStatus(fig, sprintf('GRAIN1 progress loaded: %d/%d exps restored from %s', ...
        nApplied, numel(h.exps), pf));
end


function pab1 = i_pab1State(h)
%I_GRAIN1STATE  Struct ringkas state GRAIN1 (tanpa daftar files besar) utk disimpan.
    flds = {'path','name','nImg','qOut','roiPts','roiBox','method','result','done'};
    se = struct();
    for i = numel(h.exps):-1:1
        for f = flds
            se(i).(f{1}) = h.exps(i).(f{1});
        end
    end
    pab1 = struct('type','PAB1Progress','version',1, ...
        'root', h.root, 'cumAbs', h.cumAbs, 'exps', se, ...
        'savedAt', char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
end


function i_onSaveProgress(fig)
%I_ONSAVEPROGRESS  Timpa <ROOT>/PAB_progress.mat (tanpa dialog).
    h = guidata(fig);
    prog = i_buildProgress(fig);
    if prog.nAnchored == 0
        i_setStatus(fig,'No exp with an ROI to save yet.'); return;
    end
    out = fullfile(h.root, 'PAB_progress.mat');
    try
        progress = prog; %#ok<NASGU>   % Step 1 mengharap variabel 'progress'
        save(out, 'progress');
        i_setStatus(fig, sprintf('Progress saved: %s (%d exps with an ROI).', ...
            out, prog.nAnchored));
    catch ME
        i_setStatus(fig, sprintf('Failed to save the progress: %s', ME.message));
    end
end


function i_onDoneNext(fig)
%I_ONDONENEXT  Tombol "Simpan + Next Exp" — implementasi perilaku saveNextSweep
%   (lihat I_SAVENEXTSWEEP). Tandai exp aktif SELESAI, lalu menyapu ke exp
%   BELUM SELESAI berikutnya; bila semua sudah selesai -> pop-up tuntas.
    h = guidata(fig);
    row = h.activeRow;
    if row < 1 || row > numel(h.exps)
        i_setStatus(fig,'Pick an experiment first.'); return;
    end
    e = h.exps(row);
    if isempty(e.roiBox)
        i_setStatus(fig,'No ROI yet. Draw one first.'); return;
    end
    if isempty(e.result) || ~isempty(e.result.failMsg)
        i_setStatus(fig,'Compute the jitter first (no result yet / measurement failed).'); return;
    end
    h.exps(row).done = true;
    guidata(fig, h);
    i_fillTable(fig);
    i_selectTableRow(fig, row);
    i_updateProgText(fig);
    i_saveNextSweep(fig, row, e.name, false);
end


function i_onDoneNextJit(fig)
%I_ONDONENEXTJIT  Tombol "Simpan + Next + JIT!" — sama dgn i_onDoneNext, tetapi
%   setelah menyapu ke exp belum-selesai berikutnya, OTOMATIS menghitung jitter
%   exp itu bila sudah ber-ROI (mis. ROI sama disebar ke semua exp). Hemat klik.
    h = guidata(fig);
    row = h.activeRow;
    if row < 1 || row > numel(h.exps)
        i_setStatus(fig,'Pick an experiment first.'); return;
    end
    e = h.exps(row);
    if isempty(e.roiBox)
        i_setStatus(fig,'No ROI yet. Draw one first.'); return;
    end
    if isempty(e.result) || ~isempty(e.result.failMsg)
        i_setStatus(fig,'Compute the jitter first (no result yet / measurement failed).'); return;
    end
    h.exps(row).done = true;
    guidata(fig, h);
    i_fillTable(fig);
    i_selectTableRow(fig, row);
    i_updateProgText(fig);
    i_saveNextSweep(fig, row, e.name, true);
end


function i_saveNextSweep(fig, fromRow, doneName, autoJit)
%I_SAVENEXTSWEEP  Perilaku "saveNextSweep" untuk tombol Simpan + Next Exp.
%
%   Setelah sebuah eksperimen ditandai SELESAI, JANGAN langsung memvonis
%   "semua selesai" hanya karena ini exp terakhir nomor urutnya. Sebaliknya:
%   SAPU (sweep) daftar secara melingkar untuk menemukan eksperimen yang
%   BELUM selesai berikutnya, dan pindah ke sana — sehingga lubang (exp yang
%   dilewati di tengah) tetap dikerjakan. Pop-up "seluruh eksperimen selesai"
%   muncul HANYA bila tidak ada lagi exp yang belum selesai.
%
%   Sweep dimulai dari fromRow+1 dan membungkus ke awal (1..fromRow-1), jadi
%   exp nomor 5-dari-10 yang ditandai terakhir akan memicu pop-up tuntas
%   begitu nomor 5 itu yang melengkapi seluruh set.
%
%   Perilaku ini KHUSUS dipasang di GRAIN0. Modul lain yang memakai tombol
%   serupa ("Simpan + Next") akan ditindaklanjuti terpisah memakai nama yang
%   sama (saveNextSweep) demi konsistensi.
    if nargin < 4 || isempty(autoJit), autoJit = false; end
    h = guidata(fig);
    n = numel(h.exps);
    if n == 0, return; end

    % Cari exp BELUM selesai berikutnya (melingkar), mulai setelah fromRow.
    nxt = 0;
    for off = 1:n
        k = mod(fromRow - 1 + off, n) + 1;   % fromRow+1, …, bungkus ke 1..
        if ~(isfield(h.exps(k),'done') && ~isempty(h.exps(k).done) && h.exps(k).done)
            nxt = k; break;
        end
    end

    if nxt == 0
        % Tidak ada lagi yang belum selesai -> SELURUH eksperimen tuntas.
        % (Pop-up konfirmasi dibuang — cukup status bar; pop-up dianggap mengganggu.)
        i_setStatus(fig, sprintf(['Exp "%s" done. ALL %d experiments have been ' ...
            'analysed — carry on with "Save Progress" / "Open in Step 2".'], doneName, n));
        return;
    end

    h.activeRow = nxt; guidata(fig, h);
    i_selectTableRow(fig, nxt);
    i_loadExp(fig);

    % "Simpan + Next + JIT!": bila exp tujuan sudah ber-ROI tapi belum dihitung,
    % langsung hitung jitter otomatis (ROI dianggap sama/disebar ke semua exp).
    if autoJit
        e2 = h.exps(nxt);
        if ~isempty(e2.roiBox) && isempty(e2.result)
            h.exps(nxt).method = h.method; guidata(fig, h);
            i_setStatus(fig, sprintf('Exp "%s" DONE. Next "%s" — computing jitter…', ...
                doneName, e2.name));
            i_computeExp(fig, nxt, false);
            return;
        end
    end

    i_setStatus(fig, sprintf('Exp "%s" marked DONE. Moving to exp "%s" (unfinished)…', ...
        doneName, h.exps(nxt).name));
end


function i_onSaveAnchor(fig)
    h = guidata(fig); row = h.activeRow;
    if row < 1 || isempty(h.exps(row).roiPts)
        i_setStatus(fig,'Pick an exp that has an ROI first.'); return;
    end
    e = h.exps(row);
    img = i_readRef(e); imgSize = size(img,[1 2]);
    preset = batchpivprep2.io.anchorPreset.fromPoints( ...
        e.roiPts, imgSize, e.method, img, ...
        sprintf('anchor0-%s', e.name), fullfile(e.path, e.files{1}));
    def = sprintf('anchor0-%s.mat', i_sanitize(e.name));
    i_minimize(fig);
    [fn, fp] = uiputfile({'*.mat','Anchor preset (*.mat)'}, 'Save the anchor preset', def);
    i_restore(fig);
    if isequal(fn,0), return; end
    out = fullfile(fp, fn);
    try
        batchpivprep2.io.anchorPreset.savePreset(preset, out);
        i_setStatus(fig, sprintf('Anchor saved: %s', out));
    catch ME
        i_setStatus(fig, sprintf('Failed to save the anchor: %s', ME.message));
    end
end


function i_onExportPNG(fig)
    h = guidata(fig); row = h.activeRow;
    if row < 1 || isempty(h.exps(row).result) || ~isempty(h.exps(row).result.failMsg)
        i_setStatus(fig,'This exp has no curve to export yet.'); return;
    end
    def = sprintf('jitter0_%s.png', i_sanitize(h.exps(row).name));
    i_minimize(fig);
    [fn, fp] = uiputfile({'*.png','PNG (*.png)'}, 'Save the jitter plot (2 panels)', def);
    i_restore(fig);
    if isequal(fn,0), return; end
    out = fullfile(fp, fn);
    % Salin KEDUA axes (atas dx/dy, bawah cumDx/cumDy) bertumpuk ke figure bersih.
    tmp = figure('Visible','off','Color','w','Units','pixels','Position',[0 0 980 720]);
    cu = onCleanup(@() i_tryClose(tmp));
    try
        axTop = copyobj(h.axJit, tmp);
        set(axTop,'Units','normalized','Position',[0.10 0.575 0.86 0.375]);
        axBot = copyobj(h.axCum, tmp);
        set(axBot,'Units','normalized','Position',[0.10 0.090 0.86 0.375]);
        exportgraphics(tmp, out, 'Resolution',150);
        i_setStatus(fig, sprintf('Saved: %s', out));
    catch ME
        i_setStatus(fig, sprintf('PNG export failed: %s', ME.message));
    end
end


% =====================================================================
% Helper kecil
% =====================================================================
function s = i_emptyExps()
    s = struct('path',{},'name',{},'files',{},'nImg',{},'qOut',{},'hasQpiv',{}, ...
        'roiPts',{},'roiBox',{},'method',{},'result',{},'done',{});
end

function f = i_emptyFolders()
    f = struct('path',{},'files',{},'nImg',{},'outName',{}, ...
        'seqMode',{},'seqStep',{},'anchor',{},'anchorName',{},'crop',{},'cropName',{});
end

function nWritten = i_writeMaskSidecars(root, results)
%I_WRITEMASKSIDECARS  Utk tiap MAT PREP baru (results.singleMat), baca resep
%   masking dari progres terpadu (getmask by folder sumber = results.folder) &
%   tulis sidecar '<matbase>_mask.json' di sampingnya. NON-DESTRUKTIF (blob utuh).
%   Mengembalikan jumlah sidecar yang ditulis. Aman bila resep kosong (dilewati).
    nWritten = 0;
    if isempty(results); return; end
    % Arahkan engine progres ke acuan terpadu <root>/PAB0_progress.mat.
    try
        pf = fullfile(root, 'PAB0_progress.mat');
        if isfile(pf); PIVlab_automasi_progress('setfile', pf); end
    catch
    end
    nHaveRecipe = 0;   % exp yang PUNYA resep aktif di progres terpadu
    for i = 1:numel(results)
        r = results(i);
        if ~isfield(r,'singleMat') || isempty(r.singleMat) || ~isfield(r,'folder'); continue; end
        matPath = r.singleMat;
        wrote = false; hasRecipe = false;
        % Layer-1 kotak (GRAINMASK).
        try, recipe = PIVlab_automasi_progress('getmask', r.folder); catch, recipe = []; end
        if ~isempty(recipe) && isstruct(recipe)
            try
                m = pivanalyzemat.core.maskRect.normalize(recipe);
                if m.enabled && ~isempty(m.boxes)
                    hasRecipe = true;
                    if pivanalyzemat.core.maskSidecar.write(matPath, m); wrote = true; end
                end
            catch ME
                warning('GRAIN1:maskSidecar', 'Failed to write the rect recipe for %s: %s', matPath, ME.message);
            end
        end
        % Layer-2 polygon (GRAINMASK2).
        try, prec = PIVlab_automasi_progress('getpoly', r.folder); catch, prec = []; end
        if ~isempty(prec) && isstruct(prec)
            try
                p = pivanalyzemat.core.maskPoly.normalize(prec);
                if p.enabled && ~isempty(p.polygons)
                    hasRecipe = true;
                    if pivanalyzemat.core.maskSidecar.writePoly(matPath, p); wrote = true; end
                end
            catch ME
                warning('GRAIN1:polySidecar', 'Failed to write the polygon recipe for %s: %s', matPath, ME.message);
            end
        end
        if hasRecipe; nHaveRecipe = nHaveRecipe + 1; end
        if wrote; nWritten = nWritten + 1; end
    end
    % Deteksi kegagalan pencocokan key SENYAP: bila ada resep di progres tapi
    % lebih sedikit yang tertulis, kemungkinan folder/key input tak cocok
    % (mis. GRAINMASK & GRAIN1 pakai bentuk path berbeda). Beri tahu di konsol.
    if nHaveRecipe > nWritten
        warning('GRAIN1:maskSidecarMismatch', ...
            ['%d masking recipes are active in the progress, but only %d sidecars were written. ' ...
             'The rest probably failed the folder-key match (GRAINMASK vs GRAIN1 path shapes ' ...
             'differ) -> those MAT PREP have NO masking. Check that the root is the same.'], ...
            nHaveRecipe, nWritten);
    end
    fprintf('[GRAIN1] masking sidecars: %d recipes active, %d written (out of %d MAT PREP).\n', ...
        nHaveRecipe, nWritten, numel(results));
end

function [keptFiles, info] = i_qpivKeptImages(expPath, files)
%I_QPIVKEPTIMAGES  Saring daftar gambar -> HANYA yang LOLOS QPIV (Step 0).
%   Membaca progres QPIV (PIVlab_automasi_progress) utk expPath. Frame yang
%   ditandai "abaikan" di Step 0 -> gambarnya dibuang. Mengembalikan subset
%   `files` yang lolos. Bila tak ada progres QPIV -> `files` apa adanya.
%
%   TIGA JALUR berjenjang (utama -> fallback), utk KEBAL beda urutan/ekstensi
%   antar-modul (GRAIN0 pakai sort+satu-ekstensi; GRAIN1/listImages pakai naturalSort
%   +gabung-ekstensi -> indeks POSISIONAL meleset). Solusi: buang by-NAMA.
%     (1) qpiv_kept_names ada -> WHITELIST by basename, urut ikut daftar QPIV.
%     (2) ignore_names ada    -> post-skip lalu buang file yg basename-nya cocok.
%     (3) fallback INDEKS lama (entry pra-patch; ig=indeks pasangan).
    files = files(:);
    keptFiles = files;
    nAll = numel(files);
    % qOut = jumlah gambar TERSISA setelah saringan QPIV (= numel(keptFiles));
    % diteruskan ke kolom "Frame" GRAIN1. [] bila tak ada progres QPIV.
    info = struct('hasQpiv',false,'nDrop',0,'nKept',nAll,'nAll',nAll, ...
        'qOut',[],'mapWarn','');
    try
        e = PIVlab_automasi_progress('get', expPath);
    catch
        e = [];
    end
    if isempty(e) || ~isfield(e,'qpiv_done') || ~e.qpiv_done; return; end
    info.hasQpiv = true;

    keptNames   = i_cellNames(i_getfield(e,'qpiv_kept_names'));
    ignoreNames = i_cellNames(i_getfield(e,'ignore_names'));
    baseAll     = i_baseLower(files);   % basename lower dari daftar disk GRAIN1

    % --- JALUR 1: whitelist by nama (urutan QPIV) ---
    if ~isempty(keptNames)
        want = i_baseLower(keptNames);        % basename lower, urutan QPIV
        [tf, loc] = ismember(want, baseAll);  % posisi tiap 'want' di files
        hit = loc(tf);
        keptFiles = files(hit);
        nMiss = sum(~tf);                     % nama QPIV tak ketemu di disk
        if isempty(keptFiles) && nAll > 0
            % Mismatch total (folder salah/rename) -> JANGAN buang semua; lebih
            % aman tampilkan semua + peringatan tegas daripada kehilangan data.
            keptFiles = files;
            info.mapWarn = sprintf(['QPIV stored %d names, NONE of them match this ' ...
                'folder (renamed/wrong folder?). All %d frames are used.'], ...
                numel(want), nAll);
        elseif nMiss > 0
            info.mapWarn = sprintf('QPIV had %d names, %d matched, %d not found in the folder.', ...
                numel(want), numel(keptFiles), nMiss);
        end
        info.nKept = numel(keptFiles);
        info.nDrop = nAll - info.nKept;
        info.qOut  = info.nKept;
        return;
    end

    % --- JALUR 2: buang by nama (ignore_names) pada daftar post-skip ---
    seq  = 'consecutive'; if isfield(e,'sequencing') && ~isempty(e.sequencing); seq = e.sequencing; end
    skip = 0; if isfield(e,'skip') && ~isempty(e.skip); skip = round(double(e.skip)); end
    if ~isempty(ignoreNames)
        stride = max(1, skip + 1);
        if stride > 1 && nAll >= 1; files = files(1:stride:end); end
        basePost = i_baseLower(files);
        drop = ismember(basePost, i_baseLower(ignoreNames));
        keptFiles = files(~drop);
        info.nKept = numel(keptFiles);
        info.nDrop = nAll - info.nKept;
        info.qOut  = info.nKept;
        return;
    end

    % --- JALUR 3 (FALLBACK LAMA): indeks pasangan posisional ---
    %   Dipakai HANYA utk entry progres pra-patch (tanpa field nama). Rentan beda
    %   urutan file; dipertahankan demi backward-compat data lama.
    nFr = 0; if isfield(e,'qpiv_nframes'); nFr = e.qpiv_nframes; end
    ig = []; if isfield(e,'ignore_frames'); ig = round(e.ignore_frames(:)'); end
    if nFr <= 0; return; end
    stride = max(1, skip + 1);
    if stride > 1 && nAll >= 1; files = files(1:stride:end); end
    igMask = false(1, nFr);
    igv = ig(ig>=1 & ig<=nFr); igMask(unique(igv)) = true;
    nPost = numel(files);
    drop = false(nPost,1);
    if strcmpi(seq,'pairs')
        for k = find(igMask)
            a = 2*k-1; b = 2*k;
            if a>=1 && a<=nPost; drop(a)=true; end
            if b>=1 && b<=nPost; drop(b)=true; end
        end
    else
        for k = find(igMask)
            j = k+1;                     % gambar ke-2 dari pasangan k
            if j>=1 && j<=nPost; drop(j)=true; end
        end
    end
    keptFiles = files(~drop);
    info.nKept = numel(keptFiles);
    info.nDrop = nAll - info.nKept;
    info.qOut  = info.nKept;
end

function v = i_getfield(s, f)
%I_GETFIELD  Ambil field bila ada, else [].
    if isstruct(s) && isfield(s,f); v = s.(f); else; v = []; end
end

function c = i_cellNames(x)
%I_CELLNAMES  Apa-pun -> cellstr baris (buang kosong). Toleran [], char, string.
    c = {};
    if isempty(x); return; end
    if ischar(x); c = {x}; return; end
    if isstring(x); x = cellstr(x); end
    if ~iscell(x); return; end
    x = x(:)'; keep = false(1,numel(x));
    for i = 1:numel(x)
        if (ischar(x{i}) && ~isempty(x{i})); keep(i)=true; end
    end
    c = x(keep);
end

function b = i_baseLower(names)
%I_BASELOWER  cellstr path/nama -> basename (nama+ext) lower-case, baris.
    names = i_cellNames(names);
    b = cell(1,numel(names));
    for i = 1:numel(names)
        [~,nm,ext] = fileparts(char(names{i})); b{i} = lower([nm ext]);
    end
end

function nm = i_expName(root, p)
%I_EXPNAME  Nama exp = path relatif thd ROOT (atau basename bila = root).
    root = i_stripSep(root); p = i_stripSep(p);
    if strcmpi(root, p)
        [~, nm] = fileparts(p);
    else
        rel = p;
        if startsWith(lower(p), lower(root))
            rel = p(numel(root)+1:end);
            rel = regexprep(rel, '^[\\/]+', '');
        end
        nm = strrep(rel, filesep, '/');
    end
    if isempty(nm), nm = 'exp'; end
end

function img = i_readRef(e)
    img = [];
    if isempty(e) || isempty(e.files), return; end
    try, img = imread(fullfile(e.path, e.files{1})); catch, img = []; end
end

function i_setEnableDraw(fig, tf)
%I_SETENABLEDRAW  Aktifkan tombol GAMBAR ROI (saat ada exp terpilih). Tombol
%   HITUNG diatur terpisah oleh i_setEnableOutputs (butuh ROI, bukan sekadar
%   exp terpilih) — jadi "Hitung Jitter" hanya hidup setelah ROI digambar.
    h = guidata(fig);
    s = 'off'; if tf, s = 'on'; end
    set([h.btnRect h.btnPoly h.btnClearRoi], 'Enable', s);
    if ~tf
        set([h.btnCompute h.btnRecalc h.btnDoneNext h.btnDoneNextJit ...
             h.btnRoiFromPrev h.btnRoiToOthers], 'Enable', 'off');
    end
end

function i_setEnableOutputs(fig, hasRoi, hasResult)
    h = guidata(fig);
    set(h.btnCompute,    'Enable', i_on(hasRoi));     % Hitung Jitter butuh ROI
    set(h.btnRecalc,     'Enable', i_on(hasRoi));
    set(h.btnSaveAnchor, 'Enable', i_on(hasRoi));
    set(h.btnExportPNG,  'Enable', i_on(hasResult));
    set(h.btnDoneNext,   'Enable', i_on(hasResult));  % Simpan+Next butuh HASIL jitter
    set(h.btnDoneNextJit,'Enable', i_on(hasResult));  % Simpan+Next+JIT idem
    set(h.btnRoiToOthers,'Enable', i_on(hasRoi));     % sebar ROI butuh ROI sumber
end

function s = i_on(tf), if tf, s='on'; else, s='off'; end, end

function i_updateProgText(fig)
    h = guidata(fig);
    n = numel(h.exps);
    nRoi  = sum(arrayfun(@(e) ~isempty(e.roiBox), h.exps));
    nDone = sum(arrayfun(@(e) isfield(e,'done') && ~isempty(e.done) && e.done, h.exps));
    set(h.txtProg,'String',sprintf('Done: %d/%d   ROI: %d/%d', nDone, n, nRoi, n));
end

function i_onMethod(fig)
    h = guidata(fig);
    if get(h.popMethod,'Value')==2, h.method='phasecorr'; else, h.method='surf'; end
    row = h.activeRow;
    if row >= 1, h.exps(row).method = h.method; end
    guidata(fig, h);
end

function i_onToggleCumAbs(fig)
%I_ONTOGGLECUMABS  Ganti basis drift kumulatif (SIGNED<->ABSOLUT). Hanya
%   mengubah kurva bawah, "drift" di tabel/judul, dan PNG — TIDAK menghitung
%   ulang jitter per-frame (kedua basis sudah tersimpan di hasil).
    h = guidata(fig);
    h.cumAbs = logical(get(h.chkCumAbs,'Value'));
    guidata(fig, h);
    i_renderJitter(fig);
    i_fillTable(fig);
    if h.activeRow >= 1, i_selectTableRow(fig, h.activeRow); end
    if h.cumAbs
        i_setStatus(fig,'Cumulative drift mode: ABSOLUTE (path length, cumsum|d|).');
    else
        i_setStatus(fig,'Cumulative drift mode: SIGNED (net displacement, cumsum d).');
    end
end

function [cx, cy, drift, modeStr, leg] = i_cumBasis(h, R)
%I_CUMBASIS  Pilih kurva & angka drift kumulatif sesuai mode aktif (h.cumAbs).
    if h.cumAbs && isfield(R,'cumAbsDx')
        cx = R.cumAbsDx; cy = R.cumAbsDy;
        drift = R.driftMagAbs; modeStr = 'ABS';
        leg = {'cum|dx|','cum|dy|'};
    else
        cx = R.cumDx; cy = R.cumDy;
        drift = R.driftMag; modeStr = 'signed';
        leg = {'cumDx','cumDy'};
    end
end

function i_selectTableRow(fig, row)
    h = guidata(fig);
    try, pivui.selectTableRow(h.tbl, row); catch, end
end

function v = i_readNum(hEdit, def)
    v = str2double(get(hEdit,'String')); if ~isfinite(v), v = def; end
end

function y = i_nz(x), y = x; y(~isfinite(y)) = 0; end

function s = i_stripSep(p)
    s = char(p);
    while ~isempty(s) && (s(end)=='/' || s(end)=='\'), s(end)=[]; end
end

function s = i_sanitize(nm)
    s = regexprep(char(nm), '[^\w\-]+', '_');
    s = regexprep(s, '_+', '_'); s = regexprep(s, '^_|_$', '');
    if isempty(s), s = 'exp'; end
end

function i_minimize(fig),  pivui.minimizeForDialog(fig);  end
function i_restore(fig),   pivui.restoreAfterDialog(fig); end
function i_setStatus(fig, msg),  pivui.setStatus(fig, msg);  end

function i_tryClose(hh), try, if ishghandle(hh), close(hh); end, catch, end, end
