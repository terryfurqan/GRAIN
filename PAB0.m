function PAB0(rootDir)
%PAB0  STEP 0 (QPIV) — QPIV multi-folder, EXCLUSION frame problematik.
%
%   PAB0                % pilih ROOT (dialog) lalu deteksi exp otomatis
%   PAB0(rootDir)       % langsung dari sebuah folder root
%
%   = LANGKAH PERTAMA workflow (QPIV). Tujuannya MENYARING foto bermasalah
%   SEBELUM langkah berikutnya, lewat Quick PIV pada strip TIPIS, untuk:
%     1. MESIN BERHENTI GERAK  -> "frame mati": |V| puncak QPIV ~nol.
%     2. SHUTTER COUNTER ROLL-OVER -> "interval tak teratur": dt EXIF outlier.
%
%   Setelah daftar exclusion tersimpan, tombol "Lanjut → Step 1" membuka
%   penentuan ROI stabilisasi jitter (PAB0 lama). Idenya: tiap langkah punya
%   tombol lanjut, jadi pekerjaan tak ditinggal sebelum tuntas.
%
%   LAYOUT 3 KOLOM: KIRI daftar exp + kontrol; TENGAH axMain/axPSG/axPOT;
%   KANAN tabel frame (No | |V|max | dt | Abaikan).
%
%   TABEL EXP: Eksperimen | #img | drop | output | status. Kolom "output" =
%   jumlah berkas gambar TERSISA setelah frame bermasalah dibuang (hasil bersih
%   yang akan diteruskan ke Step 1).
%
%   PROGRES PER-ROOT: saat ROOT dipilih, tool otomatis mencari berkas progres
%   "<root>/PAB0_progress.mat" dan memuatnya bila ada. Tombol "💾 Save Progress"
%   menyimpan ke berkas itu; "📂 Load Progress" memuat manual bila auto-load
%   gagal. Jadi pekerjaan QPIV bisa dianalisis satu-per-satu lintas sesi: cukup
%   pilih root, status semua exp ikut kembali.
%
%   FITUR: strip TIPIS (IW + 2*pad) utk hemat komputasi; pass default 1;
%   "Proses PIV tanpa excluded" (re-PIV pada foto bersih) + "Kembalikan" utk
%   bandingkan POT/PSG sebelum vs sesudah eksklusi; klik axPOT untuk loncat
%   frame + sorot baris tabel; slider selebar plot axPOT; "Simpan & exp
%   berikutnya"; exp aktif disorot oranye, yang selesai hijau + ceklis.
%
%   Engine = PIVlab_automasi (sama dgn PIV penuh; strip dibuat lokal supaya
%   bisa tipis). dt EXIF dibaca langsung dari JPG (pivprepRawExifDt). Saran
%   exclusion: pivprepFrameExclusion. Disimpan ke PIVlab_automasi_progress.
%
%   CATATAN RENAME: file ini = "true PAB0" (Step 0 · QPIV exclusion). PAB0
%   lama (ROI jitter) kini PAB1.m ("Step 1"); BatchPIVPrep2 -> PAB1_old. PAB0b =
%   forwarder ke PAB0.
%
%   Jalankan pab_setup sekali per sesi. SELALU MATLAB R2025b. Tema TERANG.

here = fileparts(mfilename('fullpath'));
addpath(here);
if exist('pab_setup','file') ~= 2 || isempty(which('PIVlab_automasi')) ...
        || isempty(which('pivcore.data.buildDataset'))
    try, pab_setup(); catch, end
end
if isempty(which('PIVlab_automasi'))
    error('PAB0:noEngine', 'Engine PIVlab_automasi is not on the path. Run pab_setup.');
end

if nargin < 1 || isempty(rootDir) || ~ischar(rootDir) || ~isfolder(rootDir)
    rootDir = '';
end

%% ----------------------------------------------------------- state
exps    = struct('path', {}, 'name', {}, 'nImg', {});
expSel  = 0;            % indeks exp aktif (0 = belum)
rootSel = rootDir;
progFileName = 'PAB0_progress.mat';   % berkas progres per-root (di dalam ROOT)

% Konfigurasi QPIV (global, dipakai exp yang dijalankan)
orient = 'Horizontal'; pos = 50; iw = [64 32 25 16]; npass = 1;    % pass default = 1
seqv = 'consecutive';  skip = 0; nWork = 8;
tilt = 0;              % sudut kemiringan garis scan (derajat, CW; 0 = sesuai orientasi)
stripPad = 10;         % strip TIPIS: lebar = IW + 2*stripPad (atas+bawah utk POT)
cancelReq = false;     % flag pembatalan QPIV (tombol "Batal")

% KUNCI konfigurasi: bila aktif, pindah exp TIDAK mengembalikan param ke default
% / ke nilai tersimpan exp itu — nilai di layar dipertahankan (kunci menang).
lockIW = false;        % kunci IW pass 1-4 + #pass
lockPos = false;       % kunci Posisi% + Sudut°
lockOther = false;     % kunci Orientasi + Pasangan + Skip

% State exp aktif
rawFolder=''; expdir=''; expname=''; suffix=''; cacheFile='';
out=[]; data=[]; recs=[]; M=[]; posPx=[]; peak=[]; dtSec=[]; exInfo=[];
nF=0; frame=1; ignore=false(0);
climVel=[0 1]; gsOn=true; imgCache={}; busy=false;

% State pratinjau "PIV bersih" (re-PIV tanpa frame diabaikan)
viewClean=false; origState=[]; cleanTmp='';

% Pratinjau axMain: full-frame GS (dump 50% Q50) + garis estimasi POT/PSG kuning.
% gsDumpFile dihapus saat pindah exp / figure ditutup (hemat disk).
previewMode=false; gsPreview=[]; previewHW=[1 1]; gsDumpFile=''; scanLineH=[];

%% ----------------------------------------------------------- figure
% Tinggi <= 800 px; muncul di KIRI-ATAS layar (sisakan ruang menubar/title bar).
figW = 1500; figH = 790;
scrH = 900;
try, ss = get(0,'ScreenSize'); if numel(ss) >= 4 && ss(4) > 200; scrH = ss(4); end; catch, end
figPos = [1, max(40, scrH - figH - 58), figW, figH];
fig = uifigure('Name',pivui.titleWithVersion('PAB0 (Step 0 · QPIV) — frame exclusion (dead + interval)'), ...
    'Position', figPos, 'Color',[1 1 1], 'AutoResizeChildren','off');
i_forceLight(fig);
fig.SizeChangedFcn = @(~,~) i_alignSlider();
fig.DeleteFcn = @(~,~) i_clearDump();   % hapus dump GS saat figure ditutup

%% ===================== KOLOM KIRI: daftar exp + kontrol ===============
lp = uipanel(fig,'Position',[8 8 296 770],'Title','Experiments & exclusion controls', ...
    'FontWeight','bold','BackgroundColor',[1 1 1]);
uibutton(lp,'Position',[10 716 140 26],'Text','Pick Root…','FontWeight','bold', ...
    'ButtonPushedFcn',@(~,~) onPickRoot());
uibutton(lp,'Position',[156 716 130 26],'Text','Rescan', ...
    'Tooltip','Rescan the root folder recursively.','ButtonPushedFcn',@(~,~) onRescan());
rootLbl = uilabel(lp,'Position',[10 698 276 16],'Text','(root: none selected)', ...
    'FontSize',8,'FontColor',[0.35 0.35 0.35]);
% Tabel exp DIPERPANJANG + scroll vertikal + font kecil (lebar kolom sempit).
expTable = uitable(lp,'Position',[10 144 276 546], 'FontSize',10, ...
    'ColumnName',{'Experiment','#img','drop','output','status'}, ...
    'ColumnWidth',{116 36 32 42 44}, 'ColumnEditable',[false false false false false], ...
    'RowName',{}, 'CellSelectionCallback',@(~,ev) onExpSelect(ev));

% --- Kontrol bawah-kiri (urutan dari ATAS ke BAWAH) ---
clearBtn = uibutton(lp,'Position',[10 106 276 26],'Text','Clear checkmarks', ...
    'ButtonPushedFcn',@(~,~) onClearSel());
selLbl = uilabel(lp,'Position',[10 80 276 18],'Text','0 frames marked ignore.','FontAngle','italic');

% Hapus dari daftar — DI ATAS Save/Load.
uibutton(lp,'Position',[10 44 150 26],'Text','Remove from list', ...
    'ButtonPushedFcn',@(~,~) onRemoveFolder());
expInfoLbl = uilabel(lp,'Position',[166 46 120 22],'Text','0 exp','FontAngle','italic', ...
    'HorizontalAlignment','right');

% Save/Load Progress per-root — DI DASAR kolom kiri.
saveProgBtn = uibutton(lp,'Position',[10 12 138 26],'Text','💾 Save Progress', ...
    'FontWeight','bold','BackgroundColor',[1.00 0.92 0.55], ...
    'Tooltip','Save the QPIV status of every exp to <root>/PAB0_progress.mat.', ...
    'ButtonPushedFcn',@(~,~) onSaveProgress());
loadProgBtn = uibutton(lp,'Position',[152 12 134 26],'Text','📂 Load Progress', ...
    'BackgroundColor',[0.86 0.93 0.99], ...
    'Tooltip','Load a progress file (default <root>/PAB0_progress.mat) if auto-load fails.', ...
    'ButtonPushedFcn',@(~,~) onLoadProgress());

%% ===================== KOLOM TENGAH: config + 3 axes ==================
% Panel cfg 3 BARIS: BARIS-1 param engine QPIV; BARIS-2 slider Posisi% (0:5:100);
% BARIS-3 slider Sudut° (0:1:90) + warna. Posisi & sudut pakai SLIDER (bukan
% ketik) -> garis estimasi POT/PSG kuning di axMain digeser realtime, tanpa coba2.
cfg = uipanel(fig,'Position',[310 654 848 124], ...
    'Title','QPIV configuration — drag the Position/Angle sliders; the yellow line in axMain updates live', ...
    'BackgroundColor',[1 1 1]);
% --- BARIS 1 (y=74): parameter engine QPIV ---
uilabel(cfg,'Position',[12 74 58 20],'Text','Orientation:');
orientDd = uidropdown(cfg,'Position',[72 74 92 22],'Items',{'Horizontal','Vertical'}, ...
    'Value',orient,'ValueChangedFcn',@(~,~) onCfgChange());
uilabel(cfg,'Position',[176 74 22 20],'Text','IW:');
iwF = gobjects(1,4);
for j=1:4
    iwF(j) = uieditfield(cfg,'numeric','Position',[200+(j-1)*44 74 42 22],'Value',iw(j), ...
        'Limits',[8 512],'RoundFractionalValues','on','ValueDisplayFormat','%d', ...
        'ValueChangedFcn',@(~,~) onCfgChange());
end
uilabel(cfg,'Position',[384 74 40 20],'Text','#pass:');
npassDd = uidropdown(cfg,'Position',[424 74 44 22],'Items',{'1','2','3','4'}, ...
    'Value',num2str(npass),'ValueChangedFcn',@(~,~) onCfgChange());
uilabel(cfg,'Position',[480 74 58 20],'Text','Pairing:');
seqDd = uidropdown(cfg,'Position',[538 74 160 22], ...
    'Items',{'Consecutive: 1-2,2-3,…','Paired: 1-2,3-4,…'}, ...
    'ItemsData',{'consecutive','pairs'},'Value',seqv,'ValueChangedFcn',@(~,~) onCfgChange());
uilabel(cfg,'Position',[704 74 30 20],'Text','Skip:');
skipField = uieditfield(cfg,'numeric','Position',[736 74 44 22],'Value',skip,'Limits',[0 Inf], ...
    'RoundFractionalValues','on','ValueDisplayFormat','%d','ValueChangedFcn',@(~,~) onCfgChange());

% --- KUNCI konfigurasi (3 ceklis, kolom kanan panel cfg) ---
% Saat dicentang, parameter terkait TIDAK kembali ke default / nilai exp
% tersimpan saat pindah eksperimen (kunci menang). Cocok utk analisis QPIV
% berulang: IW pass-1 dll tetap, tak usah set ulang tiap exp.
lockIWcb = uicheckbox(cfg,'Position',[788 74 66 20],'Text','🔒 IW','Value',lockIW, ...
    'Tooltip','Lock IW (pass 1-4) + #pass: unchanged when switching exp.', ...
    'ValueChangedFcn',@(s,~) onLockChange());
lockPosCb = uicheckbox(cfg,'Position',[788 44 66 20],'Text','🔒 Pos','Value',lockPos, ...
    'Tooltip','Lock Position% + Angle°: unchanged when switching exp.', ...
    'ValueChangedFcn',@(s,~) onLockChange());
lockOtherCb = uicheckbox(cfg,'Position',[788 12 66 20],'Text','🔒 etc','Value',lockOther, ...
    'Tooltip','Lock Orientation + Pairing + Skip: unchanged when switching exp.', ...
    'ValueChangedFcn',@(s,~) onLockChange());

% --- BARIS 2 (y=42): slider POSISI % (0:5:100) ---
uilabel(cfg,'Position',[12 42 56 20],'Text','Position %:');
posSlider = uislider(cfg,'Position',[74 49 360 3],'Limits',[0 100], ...
    'MajorTicks',0:25:100,'MinorTicks',[],'Value',pos, ...
    'ValueChangingFcn',@(~,ev) onPosSlide(ev.Value,false), ...
    'ValueChangedFcn', @(~,ev) onPosSlide(ev.Value,true));
posValLbl = uilabel(cfg,'Position',[470 42 64 20],'Text',sprintf('%g %%',pos),'FontWeight','bold');
gsCb = uicheckbox(cfg,'Position',[560 42 160 22],'Text','Strip image overlay','Value',true, ...
    'ValueChangedFcn',@(~,~) onToggleGS());

% --- BARIS 3 (y=10): slider SUDUT ° (0:1:90, CW) + warna |V| ---
uilabel(cfg,'Position',[12 10 50 20],'Text','Angle °:');
angSlider = uislider(cfg,'Position',[64 17 360 3],'Limits',[0 90], ...
    'MajorTicks',[],'MinorTicks',[],'Value',tilt, ...
    'ValueChangingFcn',@(~,ev) onAngSlide(ev.Value,false), ...
    'ValueChangedFcn', @(~,ev) onAngSlide(ev.Value,true));
angValLbl = uilabel(cfg,'Position',[458 10 60 20],'Text',sprintf('%g °',tilt),'FontWeight','bold');
uilabel(cfg,'Position',[540 10 52 20],'Text','Color|V|:');
climLoField = uieditfield(cfg,'numeric','Position',[594 10 44 22],'Value',climVel(1), ...
    'ValueDisplayFormat','%.3g','ValueChangedFcn',@(~,~) onClimEdit());
uilabel(cfg,'Position',[640 10 10 20],'Text','–');
climHiField = uieditfield(cfg,'numeric','Position',[652 10 44 22],'Value',climVel(2), ...
    'ValueDisplayFormat','%.3g','ValueChangedFcn',@(~,~) onClimEdit());
uibutton(cfg,'Position',[702 9 46 24],'Text','Auto','ButtonPushedFcn',@(~,~) onAutoClim());

axMain = uiaxes(fig,'Position',[330 520 818 128]);   % full-frame GS + garis estimasi POT/PSG
title(axMain,'axMain — full frame (GS) + POT/PSG line'); axMain.XTick=[]; axMain.YTick=[];
axPSG = uiaxes(fig,'Position',[330 362 818 146]);
title(axPSG,'axPSG — kymograph (position × frame)');
axPOT = uiaxes(fig,'Position',[330 198 818 150]);
title(axPOT,'axPOT — Plot Over Time'); xlabel(axPOT,'Frame'); ylabel(axPOT,'|V| (px/frame)');
try, disableDefaultInteractivity(axPOT); catch, end     % klik = loncat frame (bukan zoom)
axPOT.ButtonDownFcn = @(~,~) i_onClickPOT();
i_styleAxes();

frSlider = uislider(fig,'Position',[376 172 760 3],'Limits',[1 2],'Value',1,'MajorTicks',[], ...
    'Tooltip','Drag to change frame. Width = axPOT plot width; position = blue line.', ...
    'ValueChangedFcn',@(~,~) onSlider());

viewBtn = uibutton(fig,'Position',[330 130 214 28],'Text','Process PIV without excluded ▶', ...
    'BackgroundColor',[0.86 0.93 0.99], ...
    'Tooltip','Re-run PIV on the CLEAN photos (ignored frames dropped) -> see the POT/PSG effect.', ...
    'ButtonPushedFcn',@(~,~) onProcessClean());
revertBtn = uibutton(fig,'Position',[552 130 150 28],'Text','◀ Restore all','Enable','off', ...
    'Tooltip','Back to the all-frames view (checkmark edit mode).', ...
    'ButtonPushedFcn',@(~,~) onRevertClean());
stepBtn = uibutton(fig,'Position',[860 130 288 28],'Text','Next → PABMASK (area masking)', ...
    'FontWeight','bold','BackgroundColor',[0.93 0.90 0.99], ...
    'Tooltip','Open the next step: jitter-stabilisation ROI (the old PAB0).', ...
    'ButtonPushedFcn',@(~,~) onGoStep1());

% Run QPIV pada SEMUA exp dengan parameter (config) yang SAMA — di celah antara
% "Kembalikan" dan "Lanjut → Step 1". Berguna utk batch saat semua exp dianggap
% punya geometri/IW serupa (set config sekali, lalu sapu semua exp sekaligus).
runAllBtn = uibutton(fig,'Position',[708 130 148 28],'Text','▶▶ QPIV all exps', ...
    'FontWeight','bold','BackgroundColor',[0.78 0.89 0.97], ...
    'Tooltip',['Run QPIV on ALL experiments using the SAME parameters (config) as the ' ...
               'ones on screen right now. You can pick: all exps, or only the unfinished ones.'], ...
    'ButtonPushedFcn',@(~,~) onRunAll());

% --- Tombol aksi utama (baris y=92) dibagi 4 sama lebar (198px, gap 8) ---
runBtn = uibutton(fig,'Position',[330 92 198 32],'Text','▶ Run QPIV', ...
    'FontWeight','bold','BackgroundColor',[0.82 0.92 0.82], ...
    'Tooltip','Run QPIV on the selected experiment (config on screen).', ...
    'ButtonPushedFcn',@(~,~) onRun());
cancelBtn = uibutton(fig,'Position',[536 92 198 32],'Text','✖ Cancel QPIV','Enable','off', ...
    'FontWeight','bold','BackgroundColor',[0.97 0.80 0.78], ...
    'Tooltip','Cancel the QPIV run in progress (e.g. wrong settings).', ...
    'ButtonPushedFcn',@(~,~) onCancelQpiv());
saveNextBtn = uibutton(fig,'Position',[742 92 198 32],'Text','✓ Save ▸ Next ▸ QPIV', ...
    'FontWeight','bold','BackgroundColor',[0.80 0.90 0.80], ...
    'Tooltip','Save this exp''s exclusion, move to the next unfinished exp, then RUN QPIV automatically.', ...
    'ButtonPushedFcn',@(~,~) onSaveNext());
saveNextNoQpivBtn = uibutton(fig,'Position',[948 92 198 32],'Text','✓ Save ▸ Next (no QPIV)', ...
    'FontWeight','bold','BackgroundColor',[0.86 0.90 0.80], ...
    'Tooltip','Save this exp''s exclusion then move to the next exp WITHOUT running QPIV.', ...
    'ButtonPushedFcn',@(~,~) onSaveNextNoQpiv());

midStatus = uilabel(fig,'Position',[330 10 818 76],'Text','Ready.','FontAngle','italic', ...
    'VerticalAlignment','top','WordWrap','on');

%% ===================== KOLOM KANAN: tabel frame ======================
rp = uipanel(fig,'Position',[1166 8 326 770],'Title','Dead detection & frame table', ...
    'FontWeight','bold','BackgroundColor',[1 1 1]);
% --- Deteksi "mati" dipindah ke ATAS kolom kanan ---
autoBtn = uibutton(rp,'Position',[10 716 306 28],'Text','Auto-detect dead frames', ...
    'FontWeight','bold','BackgroundColor',[0.84 0.91 0.97], ...
    'Tooltip','Mark frames whose peak |V| is below the threshold as "dead".', ...
    'ButtonPushedFcn',@(~,~) onAutoDetect());
uilabel(rp,'Position',[10 688 64 20],'Text','Dead |V|<');
motionMinField = uieditfield(rp,'numeric','Position',[78 688 70 22],'Value',0, ...
    'Limits',[0 Inf],'ValueDisplayFormat','%.3g', ...
    'Tooltip','LOWER threshold on peak |V|: frames below it = dead (machine stopped).', ...
    'ValueChangedFcn',@(~,~) onAutoDetect());
uilabel(rp,'Position',[160 688 30 20],'Text','max');
motionMaxField = uieditfield(rp,'numeric','Position',[192 688 70 22],'Value',Inf, ...
    'Limits',[0 Inf],'ValueDisplayFormat','%.3g','Tooltip','UPPER threshold on |V| (Inf = no cut).', ...
    'ValueChangedFcn',@(~,~) onAutoDetect());
dtInfoLbl = uilabel(rp,'Position',[10 664 306 18],'Text','(dt: not computed yet)', ...
    'FontSize',9,'FontColor',[0.35 0.35 0.35]);

% --- Skip frame manual dipindah ke kolom KANAN (atas tabel frame) ---
uilabel(rp,'Position',[10 640 306 16],'Text','Manual frame skip (e.g. 1,2,5-9):','FontWeight','bold');
skipFld = uieditfield(rp,'text','Position',[10 614 160 24],'Value','','Placeholder','1,2,5-9', ...
    'ValueChangedFcn',@(~,~) onAddSkip());
addSkipBtn = uibutton(rp,'Position',[176 614 66 24],'Text','Add', ...
    'BackgroundColor',[0.84 0.91 0.97],'ButtonPushedFcn',@(~,~) onAddSkip());
setSkipBtn = uibutton(rp,'Position',[250 614 66 24],'Text','Set', ...
    'ButtonPushedFcn',@(~,~) onSetSkip());

frTable = uitable(rp,'Position',[10 150 306 452], ...
    'ColumnName',{'Frame','|V|max','dt (s)','Ignore'}, ...
    'ColumnWidth',{54 70 68 72}, 'ColumnEditable',[false false false true], ...
    'ColumnSortable',[false false false true], ...
    'RowName',{}, 'SelectionType','row', ...
    'CellEditCallback',@(~,ev) onTableEdit(ev), ...
    'SelectionChangedFcn',@(~,ev) onTableRowSel(ev));
uilabel(rp,'Position',[10 8 306 134],'VerticalAlignment','top','WordWrap','on', ...
    'FontSize',9,'FontColor',[0.3 0.3 0.3], ...
    'Text',['Column dt = EXIF interval between the photos of a pair. The MOST COMMON ' ...
            'dt is taken as the interval it should be; deviating rows are marked ' ...
            'RED (interval anomaly / counter wrap-around) — you decide via the ' ...
            '"Ignore" checkmark. Small |V|max = dead frame. Click the axPOT curve or a ' ...
            'table row to jump to that frame.']);

%% ----------------------------------------------------------- init
i_forceLight(fig);
i_updateEnables();
i_fitToScreen(fig);   % skala seragam GUI agar muat layar (mis. 1440x800), font ikut
if ~isempty(rootSel) && isfolder(rootSel)
    doScan(rootSel);
else
    setStatus('Click "Pick Root…" to detect experiments (folders containing JPEGs).');
end
drawnow; i_alignSlider();

%% ======================= FUNGSI NESTED =============================
    function onPickRoot()
        if busy; return; end
        pivui.minimizeForDialog(fig);
        d = uigetdir(i_orPwd(rootSel), 'Pick a ROOT (containing JPEG experiment subfolders)');
        pivui.restoreAfterDialog(fig);
        if isequal(d,0); return; end
        doScan(d);
    end

    function onRescan()
        if busy || isempty(rootSel); return; end
        doScan(rootSel);
    end

    function doScan(root)
        rootSel = root; rootLbl.Text = root;
        % AUTO-LOAD progres per-root: arahkan engine progres ke berkas di ROOT.
        loaded = i_pointProgressToRoot(root);
        setStatus('Scanning folders (recursive, aggressive)…');
        try
            f = batchpivprep2.io.collectFolders(root, true);
        catch ME
            setStatus(sprintf('Scan failed: %s', ME.message)); return;
        end
        exps = struct('path',{},'name',{},'nImg',{});
        for k = 1:numel(f)
            [~, nm] = fileparts(regexprep(f(k).path,'[\\/]+$',''));
            exps(end+1) = struct('path',f(k).path,'name',nm,'nImg',f(k).nImg); %#ok<AGROW>
        end
        expSel = 0;
        refreshExpTable();
        if isempty(exps)
            setStatus('No folder with an image sequence found in this root.');
        else
            if loaded
                setStatus(sprintf(['%d experiments detected. Saved progress LOADED from ' ...
                    '%s — continue from the last status.'], numel(exps), progFileName));
            else
                setStatus(sprintf(['%d experiments detected (no %s yet). Pick one then ' ...
                    '"Run QPIV"; "Save Progress" to store it.'], numel(exps), progFileName));
            end
        end
    end

    % ---- Progres per-root: arah berkas + simpan/muat manual -----------
    function tf = i_pointProgressToRoot(root)
        % Arahkan PIVlab_automasi_progress ke <root>/PAB0_progress.mat utk sesi
        % ini. Mengembalikan true bila berkas itu SUDAH ADA (= auto-load sukses).
        tf = false;
        if isempty(root) || ~isfolder(root)
            try, PIVlab_automasi_progress('resetfile'); catch, end
            return;
        end
        pf = fullfile(root, progFileName);
        try, PIVlab_automasi_progress('setfile', pf); catch, end
        tf = isfile(pf);
    end

    function p = i_progPath()
        if isempty(rootSel) || ~isfolder(rootSel); p = ''; return; end
        p = fullfile(rootSel, progFileName);
    end

    function onSaveProgress()
        if busy; return; end
        if isempty(rootSel); setStatus('Pick a root before saving progress.'); return; end
        % Pastikan engine menulis ke berkas ROOT, lalu flush exp aktif (bila ada).
        i_pointProgressToRoot(rootSel);
        if expSel >= 1 && nF > 0 && ~viewClean
            try, saveIgnore(false); catch, end   % saveIgnore -> persistEntry -> tulis berkas
        end
        pf = i_progPath();
        n  = 0;
        try, n = numel(PIVlab_automasi_progress('all')); catch, end
        refreshExpTable();
        if isfile(pf)
            setStatus(sprintf('Progress saved: %d entries → %s', n, pf));
            uialert(fig, sprintf('%d progress entries saved to:\n%s', n, pf), ...
                'Progress saved','Icon','success');
        else
            setStatus('No entry to save yet (run QPIV / save an exp first).');
        end
    end

    function onLoadProgress()
        if busy; return; end
        defDir = i_orPwd(rootSel);
        defFile = i_progPath();
        if ~isempty(defFile) && isfile(defFile); startPath = defFile; else; startPath = defDir; end
        pivui.minimizeForDialog(fig);
        [fn,fp] = uigetfile({'*.mat','Progress file (*.mat)'}, ...
            'Pick a progress file (PAB0_progress.mat)', startPath);
        pivui.restoreAfterDialog(fig);
        if isequal(fn,0); return; end
        pf = fullfile(fp, fn);
        try
            PIVlab_automasi_progress('setfile', pf);
        catch ME
            setStatus(sprintf('Failed to load progress: %s', ME.message)); return;
        end
        refreshExpTable();
        if expSel >= 1 && expSel <= numel(exps)
            i_restoreCfg(); loadOrPrompt();   % segarkan exp aktif dari progres baru
        end
        n = 0; try, n = numel(PIVlab_automasi_progress('all')); catch, end
        setStatus(sprintf('Progress loaded (%d entries) from %s', n, pf));
    end

    function refreshExpTable()
        n = numel(exps);
        C = cell(n,5);
        for k = 1:n
            e = PIVlab_automasi_progress('get', exps(k).path);
            nd = 0; st = 'new'; nout = [];
            if ~isempty(e)
                nd = i_field(e,'n_drop',0);
                if i_field(e,'qpiv_done',false); st = '✓ qpiv'; else; st = 'saved'; end
                nout = i_outputCountFromEntry(e, exps(k).nImg);
            elseif isfile(fullfile(exps(k).path, [exps(k).name '_QPIV_cache.mat']))
                st = 'cache';
            end
            C{k,1} = exps(k).name; C{k,2} = exps(k).nImg; C{k,3} = nd;
            if isempty(nout); C{k,4} = '—'; else; C{k,4} = nout; end
            C{k,5} = st;
        end
        expTable.Data = C;
        expInfoLbl.Text = sprintf('%d exp', n);
        i_styleExpTable();
    end

    function nout = i_outputCountFromEntry(e, nImg)
        % Jumlah berkas gambar TERSISA setelah frame bermasalah dibuang.
        % Hitung dari entry progres tersimpan (qpiv_nframes + ignore + seq).
        nout = [];
        nFr = i_field(e,'qpiv_nframes',0);
        if nFr <= 0; return; end
        ig  = i_field(e,'ignore_frames',[]); ig = round(ig(:)');
        ig  = ig(ig>=1 & ig<=nFr);
        seq = i_field(e,'sequencing','consecutive');
        ignVec = false(1,nFr); ignVec(ig) = true;
        % Banyak gambar total dari nFrames pasangan + sequencing.
        if strcmpi(seq,'pairs')
            nTotImg = 2*nFr;                 % tiap pasangan = 2 gambar terpisah
            nout = nTotImg - 2*nnz(ignVec);  % buang dua gambar per pasangan
        else
            nTotImg = nFr + 1;               % consecutive: N pasangan = N+1 gambar
            nout = nTotImg - nnz(ignVec);    % tiap frame buang 1 gambar (yg ke-2)
        end
        if nargin>=2 && ~isempty(nImg) && nImg>0; nout = min(nout, nImg); end
        nout = max(0, nout);
    end

    function n = i_liveOutputCount()
        % Output count utk exp aktif dari state in-memory (live, pra-simpan).
        n = [];
        if nF <= 0 || viewClean; return; end
        if strcmpi(seqv,'pairs'); n = 2*nF - 2*nnz(ignore);
        else;                     n = (nF+1) - nnz(ignore); end
        n = max(0, n);
    end

    function i_updateActiveOutputCell()
        % Perbarui sel "output" baris exp aktif tanpa baca-ulang seluruh tabel.
        if expSel < 1 || expSel > numel(exps); return; end
        D = expTable.Data;
        if isempty(D) || size(D,1) < expSel || size(D,2) < 5; return; end
        n = i_liveOutputCount();
        if isempty(n); return; end
        D{expSel,4} = n; expTable.Data = D; i_styleExpTable();
    end

    function i_styleExpTable()
        try, removeStyle(expTable); catch, end
        D = expTable.Data; if isempty(D); return; end
        n = size(D,1);
        for k = 1:n
            if contains(string(D{k,5}),'✓')   % QPIV selesai -> sel status HIJAU
                try, addStyle(expTable, uistyle('BackgroundColor',[0.80 0.94 0.80]), 'cell', [k 5]); catch, end
            end
        end
        if expSel>=1 && expSel<=n        % exp aktif -> baris ORANYE
            try, addStyle(expTable, uistyle('BackgroundColor',[1.0 0.86 0.55]), 'row', expSel); catch, end
        end
    end

    function onExpSelect(ev)
        if isempty(ev.Indices) || busy; return; end
        r = ev.Indices(1);
        if r < 1 || r > numel(exps) || r == expSel; return; end
        if viewClean; onRevertClean(); end
        if expSel >= 1 && nF > 0; try, saveIgnore(false); catch, end; end
        expSel = r; i_styleExpTable();
        i_applyExp(exps(r)); i_restoreCfg(); loadOrPrompt();
    end

    function i_applyExp(e)
        rawFolder = e.path; expdir = e.path; expname = e.name;
        cacheFile = fullfile(expdir, [expname '_QPIV_cache.mat']);
        suffix = ''; viewClean = false; origState = [];
        out=[]; data=[]; recs=[]; M=[]; posPx=[]; peak=[]; dtSec=[]; exInfo=[];
        nF=0; frame=1; ignore=false(0); imgCache={}; climVel=[0 1];
        i_updateEnables(); i_clearAxes(); refreshTable();
        i_loadPreview();   % dump GS full-frame + tampilkan garis estimasi POT/PSG
    end

    function i_restoreCfg()
        % Kembalikan config exp dari progres tersimpan — KECUALI yang DIKUNCI.
        % Param dikunci (lockIW/lockPos/lockOther) DIPERTAHANKAN apa adanya
        % (kunci menang), jadi pindah exp tak mengubahnya. syncCfgUI tetap
        % dipanggil agar UI selaras dengan state (termasuk yang dikunci).
        pe = PIVlab_automasi_progress('get', expdir);
        if ~isempty(pe)
            if ~lockIW
                iw    = i_field(pe,'iw_passes',iw); iw=double(iw(:)'); if numel(iw)<4; iw(end+1:4)=16; end
                npass = i_field(pe,'num_passes',npass);
            end
            if ~lockPos
                pos  = i_field(pe,'scan_pos_pct',pos);
                tilt = i_field(pe,'tilt_deg',tilt);
            end
            if ~lockOther
                orient = i_field(pe,'scan_orient',orient);
                seqv   = i_field(pe,'sequencing',seqv);
                skip   = i_field(pe,'skip',skip);
            end
        end
        syncCfgUI();
        i_refreshScanLine();   % garis kuning ikut posisi/sudut (kunci/tersimpan)
    end

    function onLockChange()
        lockIW    = lockIWcb.Value;
        lockPos   = lockPosCb.Value;
        lockOther = lockOtherCb.Value;
        nL = lockIW + lockPos + lockOther;
        if nL > 0
            setMid(sprintf(['%d config group(s) LOCKED — current values are kept ' ...
                'when switching exp (no reset to default/saved).'], nL));
        else
            setMid('Config lock off — config follows each exp''s saved values.');
        end
    end

    function P = i_cfgStruct()
        P = struct('orient',orient,'pos',pos,'iw',iw,'npass',npass,'seqv',seqv, ...
            'skip',skip,'nWork',nWork,'stripPad',stripPad,'suffix',suffix,'tilt',tilt);
    end

    function P = i_cleanCfgStruct()
        % Config utk re-PIV BERSIH: PERSIS setting QPIV yang sudah berjalan
        % (dibaca dari `out`), TAPI skip=0 — daftar gambar bersih sudah
        % ter-stride sejak run pertama, jadi striding ulang = buang setengah.
        % suffix='' -> auto-deteksi di folder bersih (nama berkas dipertahankan).
        P = i_cfgStruct();
        if ~isempty(out)
            P.orient = i_field(out,'orient',P.orient);
            P.pos    = i_field(out,'posPct',P.pos);
            P.iw     = i_field(out,'iw_passes',P.iw);
            P.npass  = i_field(out,'num_passes',P.npass);
            P.seqv   = i_field(out,'sequencing',P.seqv);
            P.tilt   = i_field(out,'tiltDeg',P.tilt);
        end
        P.skip   = 0;     % JANGAN stride lagi (gambar bersih sudah post-skip)
        P.suffix = '';    % auto-deteksi suffix di folder bersih
    end

    function loadOrPrompt()
        if isfile(cacheFile)
            try
                setBusy(true,'Loading saved QPIV result…');
                out = i_runQpivThin(rawFolder, i_cfgStruct(), cacheFile, true, []);
                ingestCache();
                setBusy(false,sprintf('Loaded from cache: %d frames. Change the config then "Run QPIV" if needed.', nF));
                return;
            catch ME
                setBusy(false,sprintf('Cache unreadable (%s). Click "Run QPIV".', ME.message));
            end
        else
            setStatus(sprintf('Exp "%s": no QPIV yet. Click "Run QPIV (selected exp)".', expname));
        end
    end

    function onRun()
        if busy; return; end
        if expSel < 1; setStatus('Pick an experiment in the table first.'); return; end
        if viewClean; onRevertClean(); end
        readCfg();
        cancelReq = false;
        try
            setBusy(true,'Running QPIV on the thin strip…');
            out = i_runQpivThin(rawFolder, i_cfgStruct(), cacheFile, false, @i_qpivProgress);
            ignore = false(1,out.nFrames);
            ingestCache(); autoSuggest(); persistEntry(); refreshExpTable();
            setBusy(false,sprintf('QPIV done: %d frames (strip %dpx). %d suggested for ignore.', ...
                nF, out.Lwidth, nnz(ignore)));
        catch ME
            if strcmp(ME.identifier,'PAB0:cancel')
                setBusy(false,'QPIV CANCELLED by the user — nothing saved.');
            else
                setBusy(false,sprintf('QPIV FAILED: %s', ME.message));
                uialert(fig, ME.message, 'QPIV failed');
            end
        end
        cancelReq = false;
    end

    function i_qpivProgress(f,m)
        % Dipanggil engine PIVlab tiap langkah. drawnow memproses klik tombol
        % "Batal QPIV"; bila cancelReq menyala, lempar error -> hentikan run.
        if cancelReq; error('PAB0:cancel','Cancelled by the user.'); end
        setMid(sprintf('[%3.0f%%] %s',100*f,m));
        drawnow;
    end

    function onCancelQpiv()
        if ~busy; return; end
        cancelReq = true;
        setMid('Cancelling QPIV… (waiting for the current step to finish).');
    end

    function ingestCache()
        previewMode = false;   % hasil QPIV tampil di axMain (bukan lagi pratinjau GS)
        S = load(out.cache_file);
        data = pivcore.data.buildDataset(S);
        nF = data.nFrames;
        x1 = pivcore.data.safeFrame(data.x,1); y1 = pivcore.data.safeFrame(data.y,1);
        [p1,p2] = i_linePoints(out, x1, y1);
        recs = pivcore.pot.step1Collect.collectAlongLine(data, p1, p2, out.iw_max_pass, 'velocity_magnitude');
        [M, posPx] = i_recsMatrix(recs, nF);
        if isempty(M); peak = zeros(1,nF); else; peak = max(M,[],1,'omitnan'); peak(~isfinite(peak))=0; end
        if numel(ignore) ~= nF; ignore = false(1,nF); end
        try
            exDt = pivprepRawExifDt(rawFolder, out.fn1, out.fn2);
            dtSec = exDt.dt_s(:)';
            md = i_modeApprox(dtSec);
            if isfinite(md)
                dtInfoLbl.Text = sprintf('most common dt (expected) = %.3g s — red rows = anomaly', md);
            else
                dtInfoLbl.Text = '(dt EXIF unreadable)';
            end
        catch
            dtSec = nan(1,nF); dtInfoLbl.Text = '(dt EXIF failed)';
        end
        if numel(dtSec) ~= nF; dtSec = [dtSec, nan(1, max(0,nF-numel(dtSec)))]; dtSec = dtSec(1:nF); end
        climVel = i_robustClim(M); i_syncClim();
        imgCache = cell(1,nF);
        frame = max(1, min(frame, max(1,nF)));
        syncSlider(); renderAll(); refreshTable(); i_alignSlider();
    end

    % --------------------------- saran exclusion -----------------------
    function ex = computeExclusion()
        % Hanya DETEKTOR MATI (|V| puncak rendah). Deteksi interval dipensiunkan:
        % anomali dt cukup DITANDAI MERAH di tabel (lihat i_dtAnomalyMask), bukan
        % otomatis di-abaikan — keputusan akhir lewat ceklis "Abaikan" oleh user.
        op = struct();
        op.useMotion = true; op.useTime = false;
        mn = motionMinField.Value; if mn > 0; op.motionMin = mn; end
        op.motionMax = motionMaxField.Value;
        ex = pivprepFrameExclusion(peak, dtSec, op);
    end

    function autoSuggest()
        if nF == 0; return; end
        ex = computeExclusion(); exInfo = ex; ignore = ex.ignore(1:nF);
        if motionMinField.Value <= 0; motionMinField.Value = ex.motionMin; end
        syncSlider(); refreshTable(); renderAll();
    end

    function onAutoDetect()
        if nF == 0; setStatus('No QPIV result yet — run it first.'); return; end
        if viewClean; return; end
        ex = computeExclusion(); exInfo = ex; ignore = ex.ignore(1:nF);
        syncSlider(); refreshTable(); renderAll();
        nd = nnz(ex.deadMask(1:nF));
        setStatus(sprintf('Dead auto-detect: %d frames marked (|V| < threshold). dt anomalies = red rows (decide via the checkmarks).', nd));
    end

    function onClearSel()
        if nF == 0 || viewClean; return; end
        ignore = false(1,nF); exInfo=[];
        syncSlider(); refreshTable(); renderAll();
        setStatus('All checkmarks cleared.');
    end

    % --------------------------- skip manual ---------------------------
    function onAddSkip()
        if nF == 0 || viewClean; setStatus('Run QPIV first.'); return; end
        [vec,bad] = i_parseFrameList(skipFld.Value, nF);
        if ~isempty(bad); uialert(fig, sprintf('Outside 1..%d: %s', nF, mat2str(bad)),'Partly invalid'); end
        ignore(vec) = true; refreshTable(); renderAll();
        setStatus(sprintf('Added %d frames (total %d/%d).', numel(vec), nnz(ignore), nF));
    end

    function onSetSkip()
        if nF == 0 || viewClean; setStatus('Run QPIV first.'); return; end
        [vec,bad] = i_parseFrameList(skipFld.Value, nF);
        if ~isempty(bad); uialert(fig, sprintf('Outside 1..%d: %s', nF, mat2str(bad)),'Partly invalid'); end
        ignore = false(1,nF); ignore(vec) = true; refreshTable(); renderAll();
        setStatus(sprintf('Skip set to %d frames (%d/%d).', numel(vec), nnz(ignore), nF));
    end

    % --------------------------- simpan --------------------------------
    function onSave()
        if nF == 0; uialert(fig,'No QPIV result to save yet.','Empty'); return; end
        if viewClean; setStatus('Restore the all-frames view before saving.'); return; end
        saveIgnore(true);
    end

    function onSaveNext()
        % Save ▸ Next exp ▸ QPIV: simpan exclusion exp ini, SAPU MELINGKAR ke
        % exp belum-selesai berikutnya (saveNextSweep), lalu JALANKAN QPIV
        % otomatis di sana. Config yang DIKUNCI ikut dipertahankan (i_restoreCfg).
        if busy; return; end
        if nF == 0; setStatus('No result to save yet.'); return; end
        if viewClean; onRevertClean(); end
        saveIgnore(false);
        setStatus(sprintf('Saved %d ignores for %s. Looking for the next exp…', nnz(ignore), expname));
        nx = i_nextUnfinished(expSel);
        if nx == 0
            % Tak ada exp belum-selesai berikutnya: cukup status, TANPA pop-up
            % (permintaan user — jangan ganggu alur dengan dialog "semua selesai").
            setStatus('All experiments are finished (QPIV + exclusion saved).');
            return;
        end
        expSel = nx; i_styleExpTable();
        i_applyExp(exps(expSel)); i_restoreCfg();
        % Langsung jalankan QPIV pada exp tujuan (pakai config saat ini/dikunci).
        onRun();
    end

    function onSaveNextNoQpiv()
        % Save ▸ Next (tanpa QPIV): pindah ke exp BERIKUTNYA (melingkar, apa
        % adanya — tak memfilter selesai/belum) TANPA menjalankan QPIV. Bila exp
        % ini SUDAH punya hasil QPIV (nF>0), exclusion-nya disimpan dulu; bila
        % belum, langsung LEWATI (skip) ke exp berikutnya. Exp tujuan dimuat spt
        % dipilih manual (loadOrPrompt: cache bila ada, atau pratinjau GS). Tanpa
        % pop-up.
        if busy; return; end
        if expSel < 1; setStatus('Pick an experiment first.'); return; end
        if viewClean; onRevertClean(); end
        if nF > 0
            saveIgnore(false);
            saveMsg = sprintf('Saved %d ignores for %s. ', nnz(ignore), expname);
        else
            saveMsg = sprintf('%s has no QPIV yet — skipped. ', expname);
        end
        nx = i_nextExp(expSel);
        if nx == 0 || nx == expSel
            setStatus([saveMsg 'Only 1 experiment.']);
            return;
        end
        setStatus([saveMsg 'Moving to the next exp (no QPIV)…']);
        expSel = nx; i_styleExpTable();
        i_applyExp(exps(expSel)); i_restoreCfg(); loadOrPrompt();
    end

    function nx = i_nextExp(fromRow)
        % Exp BERIKUTNYA melingkar (apa adanya, tanpa filter selesai). 0 bila
        % daftar kosong; = fromRow bila hanya 1 exp.
        nx = 0; n = numel(exps);
        if n == 0; return; end
        if n == 1; nx = fromRow; return; end
        nx = mod(fromRow, n) + 1;   % fromRow+1 melingkar ke 1
    end

    function nx = i_nextUnfinished(fromRow)
        % Sapu MELINGKAR (saveNextSweep): mulai fromRow+1, bungkus 1..fromRow-1,
        % cari exp pertama yang BELUM selesai QPIV. 0 bila semua sudah selesai.
        nx = 0; n = numel(exps);
        if n == 0; return; end
        for off = 1:n
            k = mod((fromRow-1) + off, n) + 1;   % fromRow+1, …, melingkar
            if k == fromRow; continue; end
            if ~i_expDone(k); nx = k; return; end
        end
    end

    function tf = i_expDone(k)
        % Exp "selesai" = entri progres ada & qpiv_done true.
        tf = false;
        if k < 1 || k > numel(exps); return; end
        e = PIVlab_automasi_progress('get', exps(k).path);
        if ~isempty(e) && i_field(e,'qpiv_done',false); tf = true; end
    end

    function saveIgnore(announce)
        vec = find(ignore);
        PIVlab_automasi_progress('setIgnore', expdir, vec);
        persistEntry(); refreshExpTable();
        if announce
            setStatus(sprintf('Saved: %d frames ignored for %s.', numel(vec), expname));
            uialert(fig, sprintf('%d frames marked to be ignored during the full PIV.', numel(vec)), ...
                'Saved','Icon','success');
        end
    end

    function persistEntry()
        e = PIVlab_automasi_progress('empty');
        e.expdir = expdir; e.key = PIVlab_automasi_progress('key', expdir); e.name = expname;
        e.raw_suffix = i_field(out,'suffix',suffix); e.sequencing = seqv;
        e.scan_orient = orient; e.scan_pos_pct = pos;
        e.iw_passes = iw; e.num_passes = npass; e.skip = skip; e.tilt_deg = tilt;
        e.qpiv_done = true; e.qpiv_cache = cacheFile; e.qpiv_nframes = nF;
        e.qpiv_run_time = datestr(now,'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1>
        e.ignore_frames = find(ignore); e.n_drop = nnz(ignore);
        % Simpan nama berkas (basename) yang LOLOS & yang DIBUANG QPIV, pada urutan
        % QPIV yang BENAR (dari out.fn1/out.fn2). PAB1 memakai ini utk membuang
        % frame error by-NAME (kebal beda urutan/ekstensi antar-modul).
        [e.qpiv_kept_names, e.ignore_names] = i_qpivNameLists(out, ignore, seqv);
        e.pos_hash = PIVlab_automasi_progress('sig', orient, pos, iw, suffix, nF, skip, seqv);
        PIVlab_automasi_progress('set', e);
    end

    % --------------------------- run semua -----------------------------
    function onRunAll()
        % Run QPIV pada SEMUA eksperimen dengan parameter (config) yang SAMA:
        % baca config UI sekali (readCfg) lalu pakai i_cfgStruct() identik utk
        % tiap exp — TANPA i_restoreCfg, jadi tak ada override per-exp. Hasil
        % ter-simpan ke progres (saveIgnore) seperti run tunggal.
        if busy; return; end
        if isempty(exps); setStatus('No experiments yet — pick a root & scan first.'); return; end
        if viewClean; onRevertClean(); end
        readCfg();   % parameter SAMA utk semua exp (snapshot dari layar saat ini)

        % Berapa exp yang sudah selesai (utk opsi resume "hanya yang belum").
        nDone = 0; for k = 1:numel(exps); if i_expDone(k); nDone = nDone + 1; end; end
        nLeft = numel(exps) - nDone;
        cfgStr = sprintf(['IW=[%s], #pass=%d, %s, position=%g%%, angle=%g°, ' ...
            'pairing=%s, skip=%d'], strtrim(sprintf('%d ',iw)), npass, lower(orient), ...
            pos, tilt, seqv, skip);
        msg = sprintf(['Run QPIV on the experiments with the SAME parameters:\n\n%s\n\n' ...
            'Total %d exps — %d finished, %d not yet.'], cfgStr, numel(exps), nDone, nLeft);
        if nDone > 0 && nLeft > 0
            opts = {'Run all','Only unfinished','Cancel'}; canOpt = 3;
        else
            opts = {'Run all','Cancel'}; canOpt = 2;
        end
        choice = uiconfirm(fig, msg, 'Run QPIV — all experiments', ...
            'Options', opts, 'DefaultOption', 1, 'CancelOption', canOpt, 'Icon','question');
        if strcmp(choice,'Cancel'); setStatus('Run all cancelled.'); return; end
        onlyUnfinished = strcmp(choice,'Only unfinished');

        targets = 1:numel(exps);
        if onlyUnfinished; targets = targets(~arrayfun(@i_expDone, targets)); end
        if isempty(targets); setStatus('No exp needs running.'); return; end

        setBusy(true, sprintf('Running QPIV on %d exps with identical parameters…', numel(targets)));
        dlg = uiprogressdlg(fig,'Title','QPIV — all experiments','Message','Starting…','Cancelable','on');
        cu = onCleanup(@() i_closeDlg(dlg)); %#ok<NASGU>
        nOk = 0; nFail = 0; canceled = false;
        for ii = 1:numel(targets)
            k = targets(ii);
            if dlg.CancelRequested; canceled = true; break; end
            dlg.Value = (ii-1)/numel(targets);
            dlg.Message = sprintf('(%d/%d) %s — QPIV…', ii, numel(targets), exps(k).name);
            expSel = k; i_applyExp(exps(k)); i_styleExpTable(); drawnow;
            try
                out = i_runQpivThin(rawFolder, i_cfgStruct(), cacheFile, false, ...
                    @(f,m) i_runAllTick(dlg, ii, numel(targets), f, exps(k).name));
                ignore = false(1,out.nFrames);
                ingestCache(); autoSuggest(); saveIgnore(false);
                nOk = nOk + 1;
            catch ME
                if strcmp(ME.identifier,'PAB0:cancel'); canceled = true; break; end
                nFail = nFail + 1;
                setMid(sprintf('Skipped %s: %s', exps(k).name, ME.message));
            end
        end
        i_closeDlg(dlg); setBusy(false); refreshExpTable();
        if canceled
            setStatus(sprintf('Run all CANCELLED: %d done, %d failed before stopping.', nOk, nFail));
        else
            setStatus(sprintf(['Run all finished: %d/%d exps processed & saved with ' ...
                'identical parameters%s.'], nOk, numel(targets), i_failNote(nFail)));
        end
    end

    function onRemoveFolder()
        if expSel < 1 || expSel > numel(exps); setStatus('Pick the exp to remove from the list.'); return; end
        if viewClean; onRevertClean(); end
        nm = exps(expSel).name;
        exps(expSel) = []; expSel = 0;
        i_clearDump(); gsPreview=[]; previewHW=[1 1]; scanLineH=[]; previewMode=false;
        i_clearAxes(); refreshExpTable(); refreshTable();
        nF = 0; ignore = false(0); out=[]; data=[]; i_updateEnables();
        setStatus(sprintf('"%s" removed from the list (files were NOT deleted from disk).', nm));
    end

    % ------------------- proses PIV bersih (re-PIV) --------------------
    function onProcessClean()
        if busy || nF==0 || viewClean; return; end
        if ~any(ignore); setStatus('No frame is ignored yet. Mark some first, then process.'); return; end
        % Pakai SEQUENCING & config dari run QPIV yang sebenarnya (out), bukan
        % UI saat ini — supaya foto bersih identik dgn yang baru saja diproses.
        seqRun  = i_field(out,'sequencing',seqv);
        cleanP  = i_cleanCfgStruct();          % config = persis QPIV, skip=0
        kept = i_cleanImageSet(out.fn1, out.fn2, seqRun, ignore);
        if numel(kept) < 2; uialert(fig,'Fewer than 2 frames left — cannot process.','Empty'); return; end
        nKept = numel(kept); nDropImg = i_origImgCount() - nKept;
        setBusy(true,sprintf('Processing CLEAN PIV: %d images used (%d dropped)…', nKept, max(0,nDropImg)));
        try
            tmp = i_buildCleanFolder(kept);
            tag = regexprep(expname,'[^a-zA-Z0-9]','_'); if isempty(tag); tag='exp'; end
            ccache = fullfile(tempdir, sprintf('pab0_clean_%s_QPIV.mat', tag));
            co = i_runQpivThin(tmp, cleanP, ccache, false, ...
                @(f,m) setMid(sprintf('[clean %3.0f%%] %s',100*f,m)));
            i_backupOrig();
            out = co; ingestCache();        % nF kini = jumlah pasangan bersih
            viewClean = true; cleanTmp = tmp;
            setBusy(false, sprintf(['CLEAN PIV preview: %d pairs from %d clean images ' ...
                '(originally %d pairs, %d frames dropped). "Restore" to go back.'], ...
                nF, nKept, origState.nF, origState.nF - nF));
        catch ME
            setBusy(false, sprintf('Clean processing failed: %s', ME.message));
            uialert(fig, ME.message, 'Clean processing failed');
        end
    end

    function n = i_origImgCount()
        % Banyak gambar total (pra-buang) dari run QPIV asli (out).
        seqRun = i_field(out,'sequencing',seqv);
        N = numel(out.fn1);
        if strcmpi(seqRun,'pairs'); n = 2*N; else; n = N + 1; end
    end

    function onRevertClean()
        if ~viewClean || isempty(origState); viewClean=false; i_updateEnables(); return; end
        out=origState.out; data=origState.data; recs=origState.recs; M=origState.M;
        posPx=origState.posPx; peak=origState.peak; dtSec=origState.dtSec; nF=origState.nF;
        ignore=origState.ignore; frame=origState.frame; climVel=origState.climVel;
        imgCache=origState.imgCache; exInfo=origState.exInfo;
        viewClean=false; origState=[];
        if ~isempty(cleanTmp) && isfolder(cleanTmp); try, rmdir(cleanTmp,'s'); catch, end; end
        cleanTmp='';
        i_updateEnables(); i_syncClim(); syncSlider(); renderAll(); refreshTable(); i_alignSlider();
        setStatus('Back to the all-frames view (edit mode).');
    end

    function i_backupOrig()
        origState = struct();
        origState.out=out; origState.data=data; origState.recs=recs; origState.M=M;
        origState.posPx=posPx; origState.peak=peak; origState.dtSec=dtSec; origState.nF=nF;
        origState.ignore=ignore; origState.frame=frame; origState.climVel=climVel;
        origState.imgCache=imgCache; origState.exInfo=exInfo;
    end

    function tmp = i_buildCleanFolder(keptNames)
        tag = regexprep(expname,'[^a-zA-Z0-9]','_'); if isempty(tag); tag='exp'; end
        tmp = fullfile(tempdir, ['pab0_clean_' tag]);
        if isfolder(tmp); try, rmdir(tmp,'s'); catch, end; end
        mkdir(tmp);
        for i=1:numel(keptNames)
            src = fullfile(rawFolder, keptNames{i}); dst = fullfile(tmp, keptNames{i});
            ok=false;
            try, [st,~]=system(sprintf('ln -s "%s" "%s"', src, dst)); ok=(st==0 && isfile(dst)); catch, ok=false; end
            if ~ok; try, copyfile(src,dst); catch, end; end
        end
    end

    % ----------------------------- render ------------------------------
    function renderAll(); renderMain(); renderPSG(); renderPOT(); end

    function renderMain()
        ax = axMain; cla(ax);
        if isempty(data) || nF==0; title(ax,'axMain'); return; end
        k = frame;
        x = pivcore.data.safeFrame(data.x,k); y = pivcore.data.safeFrame(data.y,k);
        Z = pivcore.data.safeFrame(data.velocity_magnitude,k);
        if isempty(Z); [Z,~] = pivcore.data.resolveScalar(data,'velocity_magnitude',k); end
        if isempty(x)||isempty(y)||isempty(Z); return; end
        xExt=[min(x(:)) max(x(:))]; yExt=[min(y(:)) max(y(:))];
        rv = i_viewRoi(); vx=[rv(1) rv(1)+rv(3)]; vy=[rv(2) rv(2)+rv(4)];
        hold(ax,'on'); haveBg=false;
        if gsOn
            g = i_stripImg(k);
            if ~isempty(g); image(ax,'XData',vx,'YData',vy,'CData',g,'HitTest','off'); haveBg=true; end
        end
        hV = imagesc(ax,xExt,yExt,Z); colormap(ax,turbo); try clim(ax,climVel); catch; end
        if haveBg; try set(hV,'AlphaData',0.60*ones(size(Z))); catch; end; end
        hold(ax,'off'); set(ax,'YDir','reverse'); xlim(ax,vx); ylim(ax,vy);
        daspect(ax,[1 1 1]); ax.XTick=[]; ax.YTick=[]; box(ax,'on');
        cb=colorbar(ax); cb.Label.String='|V| px/frame';
        ttl = sprintf('axMain — frame %d/%d', k, nF);
        if k<=numel(out.fn2) && ~isempty(out.fn2{k}); ttl=[ttl '  ·  ' out.fn2{k}]; end
        if ~viewClean && k<=numel(ignore) && ignore(k); ttl=[ttl '  [IGNORE]']; end
        if viewClean; ttl=['[CLEAN] ' ttl]; end
        title(ax, ttl, 'Interpreter','none');
    end

    function renderPSG()
        ax = axPSG; cla(ax);
        if isempty(M); title(ax,'axPSG'); return; end
        imagesc(ax, 1:nF, posPx, M); colormap(ax,turbo); try clim(ax,climVel); catch; end
        set(ax,'YDir','normal'); axis(ax,'tight');
        xlabel(ax,'Frame'); ylabel(ax,'position (px)');
        cb=colorbar(ax); cb.Label.String='|V|';
        tg=''; if viewClean; tg=' [CLEAN]'; end
        title(ax,['axPSG — kymograph (dark column = ~dead frame)' tg]);
        drawIgnoreBands(ax); drawFrameLine(ax);
    end

    function renderPOT()
        ax = axPOT; cla(ax); hold(ax,'on');
        if isempty(M); title(ax,'axPOT'); hold(ax,'off'); return; end
        for r=1:size(M,1); plot(ax,1:nF,M(r,:),'-','Color',[0.6 0.6 0.62],'PickableParts','none'); end
        plot(ax,1:nF,peak,'-','Color',[0 0 0],'LineWidth',2,'PickableParts','none');
        thr=[];
        mn = motionMinField.Value; if mn<=0 && ~isempty(exInfo); mn = exInfo.motionMin; end
        if isfinite(mn)&&mn>0
            plot(ax,[1 nF],[mn mn],'--','Color',[0.85 0.20 0.15],'LineWidth',1.2,'PickableParts','none'); thr(end+1)=mn;
        end
        mx = motionMaxField.Value;
        if isfinite(mx)
            plot(ax,[1 nF],[mx mx],'--','Color',[0.95 0.55 0.10],'LineWidth',1.2,'PickableParts','none'); thr(end+1)=mx;
        end
        hold(ax,'off'); xlabel(ax,'Frame'); ylabel(ax,'|V| (px/frame)'); grid(ax,'on');
        if nF>1; xlim(ax,[1 nF]); end
        ymax = max([M(isfinite(M)); peak(isfinite(peak)).'; thr(:)]);   % sumbu-y lega: maks + 1
        if isempty(ymax)||~isfinite(ymax)||ymax<=0; ymax=1; end
        ylim(ax,[0 ymax+1]);
        tg=''; if viewClean; tg=' [CLEAN]'; end
        title(ax, sprintf('axPOT — f %d/%d · %d curves%s', frame, nF, size(M,1), tg));
        drawIgnoreBands(ax); drawFrameLine(ax);
    end

    function drawFrameLine(axh)
        yl=ylim(axh); hold(axh,'on');
        plot(axh,[frame frame],yl,'-','Color',[0.10 0.45 0.90],'LineWidth',1.4,'HitTest','off');
        hold(axh,'off');
    end

    function drawIgnoreBands(axh)
        if viewClean; return; end
        ig = find(ignore); if isempty(ig); return; end
        yl=ylim(axh); hold(axh,'on');
        for kk = ig(:)'
            patch(axh,[kk-0.5 kk+0.5 kk+0.5 kk-0.5],[yl(1) yl(1) yl(2) yl(2)], ...
                [1 0.45 0.45],'FaceAlpha',0.30,'EdgeColor','none','HitTest','off');
        end
        hold(axh,'off');
    end

    % ----------------------------- tabel frame -------------------------
    function refreshTable()
        if nF == 0; frTable.Data = {}; selLbl.Text='0 frames marked ignore.'; return; end
        C = cell(nF,4);
        for r=1:nF
            C{r,1}=r;
            C{r,2}=round(peak(r)*1000)/1000;
            if r<=numel(dtSec) && isfinite(dtSec(r)); C{r,3}=round(dtSec(r)*1000)/1000; else; C{r,3}=NaN; end
            C{r,4}=logical(ignore(r));
        end
        frTable.Data = C;
        if viewClean
            selLbl.Text = sprintf('CLEAN PREVIEW: %d frames.', nF);
        else
            selLbl.Text = sprintf('%d / %d frames marked ignore.', nnz(ignore), nF);
        end
        i_styleFrameTable();
        i_highlightFrameRow();
        i_updateActiveOutputCell();
        i_updateEnables();   % viewBtn ikut nyala/mati sesuai ada-tidaknya exclusion
    end

    function i_styleFrameTable()
        % Baris MERAH = dt menyimpang dari nilai TERBANYAK (anomali interval).
        % Murni penanda visual; tidak otomatis meng-abaikan frame.
        try, removeStyle(frTable); catch, end
        if nF == 0 || viewClean; return; end
        am = i_dtAnomalyMask();
        for r = find(am)
            try, addStyle(frTable, uistyle('BackgroundColor',[1.0 0.80 0.80]), 'row', r); catch, end
        end
    end

    function m = i_dtAnomalyMask()
        m = false(1,nF);
        if nF == 0 || isempty(dtSec); return; end
        d = dtSec(:)'; if numel(d) < nF; d(end+1:nF) = NaN; end; d = d(1:nF);
        md = i_modeApprox(d);
        if ~isfinite(md) || md <= 0; return; end
        tol = max(0.5, 0.25*md);                 % toleransi: 25% dari mode atau 0.5 s
        m = isfinite(d) & abs(d - md) > tol;
    end

    function onTableEdit(ev)
        if isempty(ev.Indices) || viewClean; return; end
        r=ev.Indices(1); c=ev.Indices(2);
        if c==4 && r>=1 && r<=nF
            ignore(r)=logical(ev.NewData);
            selLbl.Text=sprintf('%d / %d frames marked ignore.', nnz(ignore), nF);
            renderPSG(); renderPOT(); i_updateActiveOutputCell(); i_updateEnables();
        end
    end

    function onTableRowSel(ev)
        if isempty(ev.Selection); return; end
        r=ev.Selection(1);
        if r>=1 && r<=nF && r~=frame
            frame=r; syncSlider(); renderAll(); i_alignSlider();
        end
    end

    function i_highlightFrameRow()
        try, frTable.Selection = frame; catch, end
        try, scroll(frTable,'row',frame); catch, end
    end

    function i_onClickPOT()
        if nF==0; return; end
        cp = axPOT.CurrentPoint; xf = round(cp(1,1));
        xf = max(1, min(xf, nF));
        if xf==frame; return; end
        frame = xf; syncSlider(); renderAll(); i_alignSlider(); i_highlightFrameRow();
    end

    % ----------------------------- frame slider ------------------------
    function onSlider()
        if nF==0; return; end
        frame=max(1,min(round(frSlider.Value),nF));
        renderAll(); i_alignSlider(); i_highlightFrameRow();
    end
    function syncSlider()
        if nF<2; frSlider.Limits=[1 2]; frSlider.Value=1; frSlider.Enable='off';
        else; frSlider.Limits=[1 nF]; frSlider.Value=max(1,min(frame,nF)); frSlider.Enable='on'; end
    end
    function i_alignSlider()
        % Lebar & posisi slider = kotak plot axPOT (thumb sejajar garis frame).
        try
            ip = axPOT.InnerPosition;
            if numel(ip)==4 && ip(3) > 20
                frSlider.Position = [ip(1), frSlider.Position(2), ip(3), 3];
            end
        catch
        end
    end

    % ----------------------------- config ------------------------------
    function readCfg()
        orient=orientDd.Value; pos=round(max(0,min(100,posSlider.Value))/5)*5;
        for jj=1:4; iw(jj)=iwF(jj).Value; end
        npass=str2double(npassDd.Value); seqv=seqDd.Value; skip=round(skipField.Value);
        tilt=round(max(0,min(90,angSlider.Value)));
    end
    function syncCfgUI()
        orientDd.Value=i_capOrient(orient);
        posSlider.Value=max(0,min(100,pos)); posValLbl.Text=sprintf('%g %%',pos);
        for jj=1:4; iwF(jj).Value=iw(jj); end
        npassDd.Value=num2str(max(1,min(4,round(npass))));
        seqDd.Value=seqv; skipField.Value=skip;
        angSlider.Value=max(0,min(90,tilt)); angValLbl.Text=sprintf('%g °',tilt);
    end
    function onCfgChange()
        % Orientasi/IW/skip dll. Orientasi mengubah bentuk garis -> segarkan
        % pratinjau + garis kuning (tanpa menjalankan QPIV).
        readCfg(); i_enterPreview(); i_refreshScanLine();
        setMid('Configuration changed — click "Run QPIV".');
    end

    % ---- Slider Posisi%/Sudut° + pratinjau garis estimasi POT/PSG ------
    function onPosSlide(val, committed)
        pos = round(max(0,min(100,val))/5)*5;        % snap kelipatan 5
        posValLbl.Text = sprintf('%g %%', pos);
        i_enterPreview(); i_refreshScanLine();
        if committed; posSlider.Value = pos; setMid('Line position changed — click "Run QPIV".'); end
    end
    function onAngSlide(val, committed)
        tilt = round(max(0,min(90,val)));            % snap kelipatan 1
        angValLbl.Text = sprintf('%g °', tilt);
        i_enterPreview(); i_refreshScanLine();
        if committed; angSlider.Value = tilt; setMid('Line angle changed — click "Run QPIV".'); end
    end
    function i_enterPreview()
        % Saat slider/orientasi diubah, kembali ke pratinjau GS full-frame agar
        % garis kuning terlihat di atas frame (bukan di atas hasil |V| QPIV).
        if isempty(gsPreview); return; end
        if ~previewMode; previewMode=true; renderPreview(); end
    end
    function i_refreshScanLine()
        % Realtime: cukup pindahkan garis kuning + perbarui judul (tak render
        % ulang gambar) — hemat & responsif saat slider digeser.
        if ~previewMode || isempty(gsPreview); return; end
        if ~isempty(scanLineH) && all(isgraphics(scanLineH))
            [xs,ys] = i_scanLineFF(); set(scanLineH,'XData',xs,'YData',ys);
            i_previewTitle(); drawnow limitrate;
        else
            renderPreview();
        end
    end
    function i_previewTitle()
        title(axMain, sprintf('axMain — %s · %s line, position %g%%, angle %g°', ...
            expname, lower(orient), pos, tilt),'Interpreter','none');
    end
    function renderPreview()
        ax = axMain; cla(ax);
        try, colorbar(ax,'off'); catch, end
        if isempty(gsPreview); title(ax,'axMain'); scanLineH=[]; return; end
        H=previewHW(1); W=previewHW(2);
        imagesc(ax,[1 W],[1 H],gsPreview); colormap(ax,gray);
        set(ax,'YDir','reverse'); xlim(ax,[1 W]); ylim(ax,[1 H]);
        daspect(ax,[1 1 1]); ax.XTick=[]; ax.YTick=[]; box(ax,'on');
        [xs,ys] = i_scanLineFF();
        hold(ax,'on');
        scanLineH = plot(ax,xs,ys,'--','Color',[1 1 0],'LineWidth',1.8,'HitTest','off');
        hold(ax,'off');
        i_previewTitle();
    end
    function [xs,ys] = i_scanLineFF()
        % Endpoint garis estimasi POT/PSG di KOORDINAT PIKSEL full-frame.
        % Konvensi sama dgn i_stripRoi (CW): horizontal row=rc+(x-xc)*t;
        % vertical col=cc-(y-yc)*t.
        H=previewHW(1); W=previewHW(2); t=tand(max(0,min(89.5,tilt)));  % cap 89.5: tand(90)=Inf
        if strcmpi(orient,'vertical')
            cc=1+(pos/100)*(W-1); yc=(1+H)/2;
            xs=[cc+(yc-1)*t, cc-(H-yc)*t]; ys=[1 H];
        else
            rc=1+(pos/100)*(H-1); xc=(1+W)/2;
            xs=[1 W]; ys=[rc+(1-xc)*t, rc+(W-xc)*t];
        end
    end
    function i_loadPreview()
        % Ekstrak GS frame-1 (resize 50%, JPEG Q50) -> dump temp, lalu tampilkan
        % full-frame di axMain + garis estimasi. Dump dihapus saat pindah exp.
        i_clearDump();
        gsPreview=[]; previewHW=[1 1]; scanLineH=[]; previewMode=true;
        try
            [names,~] = i_listImgs(rawFolder, '');
            im = imread(fullfile(rawFolder, names{1}));
            if size(im,3)==3; g=rgb2gray(im); else; g=im(:,:,1); end
            previewHW = [size(im,1) size(im,2)];
            gsmall = imresize(g, 0.5);
            tag = regexprep(expname,'[^a-zA-Z0-9]','_'); if isempty(tag); tag='exp'; end
            gsDumpFile = fullfile(tempdir, sprintf('pab0_gs_%s.jpg', tag));
            imwrite(gsmall, gsDumpFile, 'jpg', 'Quality', 50);
            gsPreview = imread(gsDumpFile);
        catch ME
            gsPreview=[]; setMid(sprintf('GS preview failed: %s', ME.message));
        end
        renderPreview();
    end
    function i_clearDump()
        try, if ~isempty(gsDumpFile) && isfile(gsDumpFile); delete(gsDumpFile); end; catch, end
        gsDumpFile='';
    end
    function onToggleGS()
        gsOn=gsCb.Value;
        % Saat pratinjau (belum ada hasil QPIV) renderMain hanya akan cla+keluar
        % -> kosongkan axMain. Render pratinjau GS sebagai gantinya.
        if previewMode || isempty(data) || nF==0; renderPreview(); else; renderMain(); end
    end
    function onClimEdit()
        lo=climLoField.Value; hi=climHiField.Value;
        if isfinite(lo)&&isfinite(hi)&&hi>lo; climVel=[lo hi]; else; i_syncClim(); return; end
        if previewMode || isempty(data); return; end   % clim tak berlaku di pratinjau GS
        renderMain(); renderPSG();
    end
    function onAutoClim()
        if isempty(M); return; end
        climVel=i_robustClim(M); i_syncClim(); renderMain(); renderPSG();
    end
    function i_syncClim(); climLoField.Value=climVel(1); climHiField.Value=climVel(2); end

    % ----------------------------- nav step ----------------------------
    function onGoStep1()
        % Pola "SIMPAN-TUTUP-LANJUT" (saveCloseAdvance): simpan progres exp
        % aktif, TUTUP jendela ini, lalu BUKA langkah berikutnya. Dipakai untuk
        % transisi antar-modul PAB supaya tak menumpuk jendela & progres aman.
        %   1. SIMPAN  : flush exclusion exp aktif + pastikan berkas per-root.
        %   2. TUTUP   : tutup figure PAB0 (Step 0).
        %   3. LANJUT  : luncurkan PABMASK (masking area) dgn root sama.
        %   URUTAN BARU: PAB0 -> PABMASK (kotak di foto MENTAH) -> PAB1 (jitter +
        %   MAT PREP). Masking digambar sebelum stabilisasi; resep di progres
        %   terpadu, ditempel non-destruktif saat produksi.
        if busy; setStatus('Busy — wait for the current process to finish.'); return; end
        if viewClean; onRevertClean(); end
        try
            % 1. SIMPAN
            i_pointProgressToRoot(rootSel);
            if expSel >= 1 && nF > 0; try, saveIgnore(false); catch, end; end
            % 3. (siapkan) argumen lanjut sebelum figure ditutup
            goRoot = rootSel;
            % 2. TUTUP
            setStatus('Saving progress & closing Step 0…');
            drawnow;
            try, delete(fig); catch, end
            % 3. LANJUT -> PABMASK (urutan baru)
            if ~isempty(goRoot) && isfolder(goRoot)
                PABMASK(goRoot);   % teruskan root -> masking di foto mentah
            else
                PABMASK;
            end
        catch ME
            if isvalid(fig); uialert(fig, ME.message, 'Failed to open PABMASK'); end
        end
    end

    % ----------------------------- util --------------------------------
    function rv = i_viewRoi()
        VIEW_MULT=5; r=out.roi; sz=out.imageSize; H=sz(1); W=sz(2);
        if i_field(out,'tiltDeg',0) > 0; rv=r; return; end   % ROI miring sudah lebar

        if strcmpi(out.orient,'vertical')
            cx=r(1)+r(3)/2; wNew=min(W-1,VIEW_MULT*(r(3)+1)-1);
            x0=max(1,min(round(cx-wNew/2),W-wNew)); rv=[x0 r(2) wNew r(4)];
        else
            cy=r(2)+r(4)/2; hNew=min(H-1,VIEW_MULT*(r(4)+1)-1);
            y0=max(1,min(round(cy-hNew/2),H-hNew)); rv=[r(1) y0 r(3) hNew];
        end
    end

    function g = i_stripImg(kf)
        g=[];
        if kf<1 || kf>numel(out.fn2) || isempty(out.fn2{kf}); return; end
        if numel(imgCache)>=kf && ~isempty(imgCache{kf}); g=imgCache{kf}; return; end
        p=fullfile(out.raw_folder,out.fn2{kf});
        if ~isfile(p); return; end
        try
            im=imread(p); r=i_viewRoi();
            rr=r(2):min(size(im,1),r(2)+r(4)); ccx=r(1):min(size(im,2),r(1)+r(3));
            g=im(rr,ccx,:); if size(g,3)==1; g=repmat(g,1,1,3); end
        catch; g=[]; end
        if numel(imgCache)<nF; imgCache{nF}=[]; end
        imgCache{kf}=g;
    end

    function i_clearAxes()
        cla(axMain); cla(axPSG); cla(axPOT);
        title(axMain,'axMain'); title(axPSG,'axPSG'); title(axPOT,'axPOT');
    end
    function i_styleAxes()
        for ax=[axMain axPSG axPOT]; ax.Color=[1 1 1]; box(ax,'on'); end
    end

    function setStatus(msg); if isvalid(fig); midStatus.Text=msg; drawnow limitrate; end; end
    function setMid(msg); if isvalid(fig); midStatus.Text=msg; drawnow limitrate; end; end

    function setBusy(tf,msg)
        busy=tf; i_updateEnables();
        if nargin>1; setMid(msg); end
        drawnow;
    end

    function i_updateEnables()
        edit = ~busy && ~viewClean;
        ec = {runBtn,runAllBtn,autoBtn,clearBtn,saveNextBtn,saveNextNoQpivBtn,addSkipBtn,setSkipBtn, ...
            orientDd,posSlider,npassDd,seqDd,skipField,gsCb,angSlider,motionMinField,motionMaxField, ...
            climLoField,climHiField,lockIWcb,lockPosCb,lockOtherCb};
        for cc=1:numel(ec); try ec{cc}.Enable=i_onoff(edit); catch; end; end
        for jj=1:4; try iwF(jj).Enable=i_onoff(edit); catch; end; end
        try revertBtn.Enable=i_onoff(~busy && viewClean); catch; end
        % Tombol "Batal QPIV": HANYA aktif saat sedang sibuk (QPIV berjalan).
        try cancelBtn.Enable=i_onoff(busy); catch; end
        % "Proses PIV tanpa excluded": HANYA aktif bila QPIV sudah jalan (nF>0)
        % DAN ada frame yang ditandai abaikan — kalau belum, greyed out.
        try viewBtn.Enable=i_onoff(edit && nF>0 && any(ignore)); catch; end
        % Save/Load Progress aktif kapan saja kecuali sedang sibuk (tak bergantung exp).
        try saveProgBtn.Enable=i_onoff(~busy); catch; end
        try loadProgBtn.Enable=i_onoff(~busy); catch; end
        try frTable.ColumnEditable=[false false false (~busy && ~viewClean)]; catch; end
    end
end

%% ========================= SUBFUNGSI (lokal) =====================
function out = i_runQpivThin(rawFolder, P, cacheFile, dryRun, progFcn)
%I_RUNQPIVTHIN  QPIV strip TIPIS (IW + 2*pad) -> PIVlab_automasi (engine asli).
%   Glue lokal PAB0 (Step 0): sama dgn PIVlab_automasi_qpiv tetapi lebar strip =
%   IW pass-1 + 2*stripPad (bukan 2*IW) -> komputasi jauh lebih ringan & cepat.
%   dryRun=true -> hanya rakit metadata (utk muat cache lama tanpa re-PIV).
    [names, sfx] = i_listImgs(rawFolder, P.suffix);
    stride = round(P.skip) + 1;
    if stride > 1 && numel(names) >= 1; names = names(1:stride:end); end
    if numel(names) < 2
        error('PAB0:tooFew','Need >=2 images (after skip):\n%s', rawFolder);
    end
    first = imread(fullfile(rawFolder, names{1})); H=size(first,1); W=size(first,2);
    iaReq = round(P.iw(:)'/2)*2; npReq = round(P.npass);
    [iaUsed,npUsed,iwMax,iwStrip,clamped] = i_clampPasses(iaReq,npReq);
    % Strip TIPIS untuk hemat komputasi, TAPI tetap >= 2 baris vektor: PIVlab
    % wajib menghitung strain (gradient) yang butuh grid 2D. Minimum aman =
    % IW + ceil(IW/2) (baris ke-2) + 2*pad (kompensasi POT atas/bawah).
    Lwidth = iwStrip + ceil(iwStrip/2) + 2*round(P.stripPad);
    tiltDeg = 0; if isfield(P,'tilt'); tiltDeg = max(0,min(90,P.tilt)); end
    [roi,Lwidth] = i_stripRoi(lower(P.orient), P.pos, tiltDeg, H, W, Lwidth);
    [fn1,fn2] = i_pairs(names, P.seqv); nPairs = numel(fn1);

    out = struct();
    out.cache_file=cacheFile; out.nFrames=nPairs; out.roi=roi; out.orient=P.orient;
    out.tiltDeg=tiltDeg;
    out.posPct=P.pos; out.iw_passes=iaReq; out.num_passes=npReq; out.iw_used=iaUsed;
    out.num_passes_used=npUsed; out.iw_max_pass=iwMax; out.Lwidth=Lwidth; out.imageSize=[H W];
    out.raw_folder=rawFolder; out.suffix=sfx; out.skip=round(P.skip); out.sequencing=P.seqv;
    out.fn1=fn1; out.fn2=fn2; out.clamped=clamped;
    if dryRun; return; end

    [cdir,cname] = fileparts(cacheFile); if isempty(cdir); cdir=rawFolder; end
    if ~isfolder(cdir); mkdir(cdir); end
    res = PIVlab_automasi(rawFolder, 'Suffix', sfx, 'Sequencing', P.seqv, 'Skip', round(P.skip), ...
        'NumWorkers', round(P.nWork), 'PIVlabRoot', '', 'OutputFolder', cdir, 'OutputName', cname, ...
        'IntAreas', iaUsed, 'NumPasses', npUsed, 'ROI', roi, 'PreprocROI', roi, ...
        'ProgressFcn', progFcn);
    out.cache_file = res.output_file; out.nFrames = res.num_pairs;
    nf = max(0, out.nFrames);
    out.fn1 = fn1(1:min(nf,numel(fn1))); out.fn2 = fn2(1:min(nf,numel(fn2)));
end

function [names,suffix] = i_listImgs(folder, suffix)
exts={'*.tif','*.tiff','*.jpg','*.jpeg','*.png','*.bmp'};
if isempty(suffix)
    counts=zeros(numel(exts),1);
    for k=1:numel(exts); d=dir(fullfile(folder,exts{k})); counts(k)=sum(~[d.isdir]); end
    [mx,idx]=max(counts);
    if mx==0; error('PAB0:noImages','No images in:\n%s', folder); end
    suffix=exts{idx};
elseif ~startsWith(suffix,'*')
    if ~startsWith(suffix,'.'); suffix=['.' suffix]; end
    suffix=['*' suffix];
end
d=dir(fullfile(folder,suffix)); d=d(~[d.isdir]); names=sort({d.name}); names=names(:);
end

function [iaUsed,npUsed,iwMax,iwStrip,clamped] = i_clampPasses(iaReq,npReq)
active=iaReq(1:npReq); active=active(active>=8); if isempty(active); active=16; end
npUsed=numel(active); iwMax=active(end); iwStrip=max(active);
iaUsed=[active, repmat(active(end),1,4-npUsed)]; iaUsed=iaUsed(1:4); clamped=npUsed<npReq;
end

function [roi,Lwidth] = i_stripRoi(orient,pos,tilt,H,W,Lwidth)
%I_STRIPROI  Kotak ROI (axis-aligned) yang memuat garis scan, dimiringkan
%   `tilt` derajat (CW). tilt=0 -> strip tipis seperti semula. Untuk tilt>0
%   garis scan miring, jadi ROI = kotak pembatas garis + setengah lebar strip
%   di kedua sisi (strip otomatis melebar; komputasi lebih berat di sudut besar).
t = tand(max(0,min(89.5,tilt)));   % cap 89.5: tand(90)=Inf -> ROI/endpoint tak hingga
if strcmpi(orient,'vertical')
    cc = 1+(pos/100)*(W-1);
    if t==0
        if Lwidth>=W; x0=1; wSpan=W-1; Lwidth=W;
        else; x0=round(cc-Lwidth/2); x0=max(1,min(x0,W-(Lwidth-1))); wSpan=Lwidth-1; end
        roi=[x0,1,wSpan,H-1]; return;
    end
    yc=(1+H)/2; xTop=cc+(yc-1)*t; xBot=cc-(H-yc)*t;   % CW: atas ke +x, bawah ke -x
    x0=max(1,floor(min(xTop,xBot)-Lwidth/2));
    x1=min(W,ceil(max(xTop,xBot)+Lwidth/2));
    if (x1-x0)<1; x0=max(1,round(cc-1)); x1=min(W,x0+1); end
    roi=[x0,1,x1-x0,H-1]; Lwidth=x1-x0+1;
else
    rc=1+(pos/100)*(H-1);
    if t==0
        if Lwidth>=H; y0=1; hSpan=H-1; Lwidth=H;
        else; y0=round(rc-Lwidth/2); y0=max(1,min(y0,H-(Lwidth-1))); hSpan=Lwidth-1; end
        roi=[1,y0,W-1,hSpan]; return;
    end
    xc=(1+W)/2; yL=rc-(xc-1)*t; yR=rc+(W-xc)*t;       % CW: kiri ke atas, kanan ke bawah
    y0=max(1,floor(min(yL,yR)-Lwidth/2));
    y1=min(H,ceil(max(yL,yR)+Lwidth/2));
    if (y1-y0)<1; y0=max(1,round(rc-1)); y1=min(H,y0+1); end
    roi=[1,y0,W-1,y1-y0]; Lwidth=y1-y0+1;
end
end

function [fn1,fn2] = i_pairs(names,seq)
amount=numel(names);
if strcmpi(seq,'pairs')
    if mod(amount,2)==1; amount=amount-1; names(end)=[]; end
    fn1=names(1:2:amount-1); fn2=names(2:2:amount);
else
    fn1=names(1:end-1); fn2=names(2:end);
end
fn1=fn1(:); fn2=fn2(:);
end

function kept = i_cleanImageSet(fn1, fn2, seq, ig)
%I_CLEANIMAGESET  Daftar gambar TERSISA setelah membuang frame MATI. Delegasi ke
%   engine bersama batchpivprep2.io.qpivCleanImageSet (satu sumber kebenaran,
%   dipakai juga utk `dropped` di i_qpivNameLists). Pasangan mati -> KEDUA gambar
%   pembentuknya dibuang (perbaikan bug frame-1/zona-mati-awal LOLOS).
kept = batchpivprep2.io.qpivCleanImageSet(fn1, fn2, seq, ig);
end

function [kept, dropped] = i_qpivNameLists(out, ignore, seqFallback)
%I_QPIVNAMELISTS  Dari hasil QPIV (out.fn1/out.fn2 = nama gambar per-pasangan
%   pada urutan BENAR) + vektor ignore (indeks pasangan) -> dua cellstr basename:
%     kept    = gambar yang LOLOS (urutan QPIV), = i_cleanImageSet
%     dropped = gambar yang DIBUANG (pemetaan pasangan->gambar IDENTIK).
%   Guard: bila out kosong / tanpa fn1 -> keduanya {} (PAB1 fallback ke indeks).
kept = {}; dropped = {};
if isempty(out) || ~isstruct(out); return; end
fn1 = i_field(out,'fn1',{}); fn2 = i_field(out,'fn2',{});
if isempty(fn1) || isempty(fn2); return; end
seq = i_field(out,'sequencing',seqFallback);
% Engine bersama: kept & dropped SEKALI JALAN, pemetaan pasangan->gambar identik
% (consecutive buang KEDUA sisi pasangan mati). Keluaran sudah basename.
[kept, dropped] = batchpivprep2.io.qpivCleanImageSet(fn1, fn2, seq, ignore);
end

function c = i_basenames(x)
%I_BASENAMES  cellstr path/nama -> basename (nama+ekstensi) saja, baris.
c = {};
if isempty(x); return; end
if ischar(x); x = {x}; end
x = x(:)'; c = cell(1,numel(x));
for i = 1:numel(x)
    [~,nm,ext] = fileparts(char(x{i})); c{i} = [nm ext];
end
end

function i_forceLight(fig)
    try, theme(fig, 'light'); catch, end
    try, fig.Theme = 'light'; catch, end
    try, fig.Color = [1 1 1]; catch, end
end

function i_fitToScreen(fig)
%I_FITTOSCREEN  Skala SERAGAM seluruh GUI agar muat layar (mis. 1440x800), tanpa
%   mengubah tata letak relatif (proporsi tetap -> tak ada overlap baru). Posisi
%   & FontSize semua child dikali faktor s; figure ikut mengecil & ditempatkan di
%   kiri-atas. s=1 (tak berubah) bila layar sudah cukup besar. Font diclamp >=8.
    try, ss = get(0,'ScreenSize'); scrW = ss(3); scrH = ss(4); catch, scrW = 1440; scrH = 800; end
    if ~(scrW > 200 && scrH > 200); scrW = 1440; scrH = 800; end
    p = fig.Position; figW = p(3); figH = p(4);
    marginW = 40;  marginH = 96;          % border jendela + title-bar + taskbar
    s = min([1, (scrW-marginW)/figW, (scrH-marginH)/figH]);
    if s >= 0.999; return; end            % sudah muat, jangan utak-atik
    ws = warning('off','all');            % bbrp komponen (dropdown) tinggi tetap -> warning
    cleanupWs = onCleanup(@() warning(ws)); %#ok<NASGU>
    i_scaleChildren(fig, s);
    newW = round(figW*s); newH = round(figH*s);
    x0 = max(1, round((scrW-newW)/2));
    y0 = max(36, scrH - newH - 64);
    fig.Position = [x0 y0 newW newH];
end

function i_scaleChildren(parent, s)
%I_SCALECHILDREN  Kali Position (& FontSize) setiap turunan dengan s, rekursif.
%   Position panel & child-nya (relatif) dikali s yang sama -> konsisten.
    ch = allchild(parent);
    for k = 1:numel(ch)
        c = ch(k);
        if isprop(c,'Position')
            try
                pos = c.Position;
                if numel(pos) == 4; c.Position = pos * s; end
            catch
            end
        end
        if isprop(c,'FontSize')
            try, c.FontSize = max(8, c.FontSize * s); catch, end
        end
        try, i_scaleChildren(c, s); catch, end   % rekursi ke kontainer (panel dll.)
    end
end

function [p1,p2] = i_linePoints(out, x1, y1)
yMid=(max(y1(:))+min(y1(:)))/2; H=out.imageSize(1); W=out.imageSize(2);
t = 0; if isfield(out,'tiltDeg'); t = tand(max(0,min(89.5,out.tiltDeg))); end  % cap 89.5: tand(90)=Inf
if strcmpi(out.orient,'vertical')
    cc=1+(out.posPct/100)*(W-1);
    % data-y = 2*yMid - imageRow; x garis = cc - (imageRow - yc)*t  (CW).
    yc=(1+H)/2; ymin=min(y1(:)); ymax=max(y1(:));
    xa=cc-(ymax-yc)*t; xb=cc-(ymin-yc)*t;
    p1=[xa 2*yMid-ymax]; p2=[xb 2*yMid-ymin];
else
    rc=1+(out.posPct/100)*(H-1);
    % imageRow garis = rc + (imageX - xc)*t  (CW); data-y = 2*yMid - imageRow.
    xc=(1+W)/2; xmin=min(x1(:)); xmax=max(x1(:));
    rL=rc+(xmin-xc)*t; rR=rc+(xmax-xc)*t;
    p1=[xmin 2*yMid-rL]; p2=[xmax 2*yMid-rR];
end
end

function [M,posPx] = i_recsMatrix(recs, nF)
n=numel(recs);
if n==0; M=[]; posPx=[]; return; end
M=nan(n,nF); posPx=nan(1,n);
for r=1:n
    d=recs(r).data(:)'; L=min(numel(d),nF); M(r,1:L)=d(1:L);
    if isfield(recs(r),'posPx') && ~isempty(recs(r).posPx); posPx(r)=recs(r).posPx; end
end
bad=~isfinite(posPx); if any(bad); posPx(bad)=find(bad); end
end

function c = i_robustClim(M)
if isempty(M); c=[0 1]; return; end
v=M(isfinite(M)); if isempty(v); c=[0 1]; return; end
hi=i_pct(v,98); if ~(isfinite(hi)&&hi>0); hi=max(v); end
if ~(isfinite(hi)&&hi>0); hi=1; end
c=[0 hi];
end

function md = i_modeApprox(v)
%I_MODEAPPROX  Nilai dt yang PALING SERING muncul (dibulatkan ke 0.1 s) = dt
%   yang "seharusnya". Frame dengan dt jauh dari nilai ini = anomali interval.
v=v(:); v=v(isfinite(v));
if isempty(v); md=NaN; return; end
r=round(v*10)/10; u=unique(r); best=u(1); bc=0;
for k=1:numel(u); c=sum(r==u(k)); if c>bc; bc=c; best=u(k); end; end
md=best;
end

function q = i_pct(v,p)
v=sort(v(:)); n=numel(v);
if n==0; q=NaN; return; end
if n==1; q=v(1); return; end
r=(p/100)*(n-1)+1; lo=floor(r); hi=ceil(r); fr=r-lo;
q=v(lo)*(1-fr)+v(hi)*fr;
end

function [vec,bad] = i_parseFrameList(str,nMax)
vec=[]; bad=[]; str=strtrim(char(str));
if isempty(str); return; end
toks=regexp(str,'[,;\s]+','split'); all=[];
for k=1:numel(toks)
    t=strtrim(toks{k}); if isempty(t); continue; end
    m=regexp(t,'^(\d+)\s*-\s*(\d+)$','tokens','once');
    if ~isempty(m)
        a=str2double(m{1}); b=str2double(m{2}); if a>b; tmp=a;a=b;b=tmp; end
        all=[all a:b]; %#ok<AGROW>
    elseif ~isempty(regexp(t,'^\d+$','once'))
        all=[all str2double(t)]; %#ok<AGROW>
    end
end
all=unique(round(all)); bad=all(all<1|all>nMax); vec=all(all>=1&all<=nMax);
end

function v = i_field(s,f,d)
if isstruct(s)&&isfield(s,f)&&~isempty(s.(f)); v=s.(f); else; v=d; end
end
function s = i_capOrient(o); if strcmpi(o,'vertical'); s='Vertical'; else; s='Horizontal'; end; end
function s = i_onoff(tf); if tf; s='on'; else; s='off'; end; end
function p = i_orPwd(p); if isempty(p)||~isfolder(p); p=pwd; end; end
function i_closeDlg(d); try if isvalid(d); close(d); end; catch; end; end
function i_runAllTick(d,ii,n,f,nm)
%I_RUNALLTICK  Progress per-frame utk "Run QPIV semua": perbarui dialog &
%   HORMATI tombol Batal — bila ditekan, lempar PAB0:cancel agar loop run-all
%   berhenti di tengah exp (bukan hanya antar-exp).
if ~isempty(d) && isvalid(d) && d.CancelRequested
    error('PAB0:cancel','Cancelled by the user.');
end
try, if isvalid(d); d.Value=min(1,((ii-1)+f)/n); d.Message=sprintf('(%d/%d) %s — %.0f%%',ii,n,nm,100*f); end; catch, end
end
function s = i_failNote(nFail)
if nFail > 0; s = sprintf(' (%d failed/skipped)', nFail); else; s = ''; end
end
