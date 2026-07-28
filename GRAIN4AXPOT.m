function figOut = GRAIN4AXPOT(varargin)
%GRAIN4AXPOT  Standalone: stacked axPOT overlays for a folder of experiments.
%
%   A small GUI. Input = a folder that CONTAINS the experiment .mat files
%   (Step-2 PIV output, one file per experiment). Two products:
%
%     [ AX-POT RAW ]   Raw-data spaghetti overlay per experiment (every POT
%                      curve + black max-indenter envelope). No cleaning, no
%                      POI. Mirrors pivui.grain4Shell.renderPOT exactly.
%
%     [ AX-POT CLEAN ] Same overlay, but CLEANED using each experiment's GRAIN4
%                      sidecars: <base>_potdata.json (excluded curves + trim
%                      to max indenter) and <base>_faults.json (each fault's
%                      HW = red, FW = blue, with the fault zone FILLED between
%                      them over [startF,endF]). No POI markers.
%
%     [ AX-SLIP ]      Net-slip (HW - FW) per fault over [startF,endF], one
%                      curve per fault FILLED to 0, each fault a different fill
%                      colour. No raw curves, no indenter, no DX/POI vertical
%                      lines. Y = cm/s (or px/frame if uncalibrated).
%
%   Output PDF is named <experiment-group>_<PLOTTYPE>.pdf (group = folder name),
%   e.g. P-HF-4cm-F_AXSLIP.pdf, into CLCC/<folder>/.
%
%   Both stack all experiments top-to-bottom with a SHARED X range (the widest
%   experiment), export ONE vector PDF into CLCC/, and save the numeric panel
%   data to CLCC/PAB4AXPOT.mat.
%
%   Axes use REAL-WORLD units:
%     X = cumulative strain (%)      from experiment_geometry.strain_cumm_pct
%     Y = velocity (cm/s)            |V| px/frame x geom velMult (indenter-
%                                    calibrated: dxCm/((nF-1)*dt) / indenterMax)
%   If an experiment lacks the calibration to convert Y, that panel falls back
%   to px/frame and its title says so (honest, no fabricated numbers).
%
%   Usage:
%       GRAIN4AXPOT                 % opens GUI, pick folder
%       GRAIN4AXPOT('expDir', DIR)  % preselect folder
%
%   Run grain_setup first so pivcore/pivui packages are on the path.

    p = inputParser;
    p.addParameter('expDir', '', @(s) ischar(s) || isstring(s));
    p.parse(varargin{:});
    startDir = char(p.Results.expDir);

    fig = figure('Name','GRAIN4AXPOT — stacked axPOT overlays', ...
        'NumberTitle','off', 'Color','w', 'MenuBar','none', 'ToolBar','none', ...
        'Units','pixels', 'Position',[120 120 620 300]);
    try, pivui.forceLightTheme(fig); catch, end
    try, fig.Name = pivui.titleWithVersion('GRAIN4AXPOT — stacked axPOT overlays'); catch, end

    h.fig = fig;
    h.expDir = startDir;

    uicontrol(fig,'Style','text','String','Experiment folder (.mat) — or a PARENT of experiment subfolders for BATCH:', ...
        'HorizontalAlignment','left','BackgroundColor','w', ...
        'Units','pixels','Position',[20 258 580 20],'FontWeight','bold');
    h.edDir = uicontrol(fig,'Style','edit','String',startDir, ...
        'HorizontalAlignment','left','BackgroundColor','w', ...
        'Units','pixels','Position',[20 230 470 26]);
    uicontrol(fig,'Style','pushbutton','String','Browse…', ...
        'Units','pixels','Position',[500 230 100 26], ...
        'Callback',@(s,e) i_onBrowse(fig));

    % --- Single folder: 3 modes ---
    uicontrol(fig,'Style','text','String','Single folder (output -> CLCC/<folder>/):', ...
        'HorizontalAlignment','left','BackgroundColor','w','ForegroundColor',[0.3 0.3 0.3], ...
        'Units','pixels','Position',[20 200 580 18]);
    uicontrol(fig,'Style','pushbutton','String','AX-POT RAW0', ...
        'FontWeight','bold','FontSize',10, ...
        'Units','pixels','Position',[20 150 138 48], ...
        'TooltipString','Full raw-data overlay per experiment (no cleaning, no faults, no POI).', ...
        'Callback',@(s,e) i_onProduce(fig,'raw0'));
    uicontrol(fig,'Style','pushbutton','String','AX-POT RAW1', ...
        'FontWeight','bold','FontSize',10, ...
        'Units','pixels','Position',[166 150 138 48], ...
        'TooltipString',['Cleaned overlay (excluded curves removed + trim-to-indenter), ' ...
            'still plain: NO HW/FW, NO fill, no POI.'], ...
        'Callback',@(s,e) i_onProduce(fig,'raw1'));
    uicontrol(fig,'Style','pushbutton','String','AX-POT CLEAN', ...
        'FontWeight','bold','FontSize',10, ...
        'Units','pixels','Position',[312 150 138 48], ...
        'TooltipString',['Cleaned overlay + HW(red)/FW(blue) faults filled (faults.json). No POI.'], ...
        'Callback',@(s,e) i_onProduce(fig,'clean'));
    uicontrol(fig,'Style','pushbutton','String','AX-SLIP', ...
        'FontWeight','bold','FontSize',10, 'BackgroundColor',[0.92 1.00 0.92], ...
        'Units','pixels','Position',[458 150 138 48], ...
        'TooltipString',['Net-slip per fault (HW - FW), one curve per fault, filled to 0. ' ...
            'Each fault a different fill colour. No DX/POI vertical lines.'], ...
        'Callback',@(s,e) i_onProduce(fig,'axslip'));

    % --- Batch: every experiment subfolder, all 3 modes ---
    uicontrol(fig,'Style','pushbutton', ...
        'String','BATCH: all subfolders × RAW0·RAW1·CLEAN·AXSLIP', ...
        'FontWeight','bold','FontSize',11, 'BackgroundColor',[0.90 0.94 1.00], ...
        'Units','pixels','Position',[20 92 581 46], ...
        'TooltipString',['Treat the box as a PARENT folder; process EVERY subfolder that ' ...
            'holds experiment .mat files, all 3 modes, into CLCC/<subfolder>/.'], ...
        'Callback',@(s,e) i_onProduceAll(fig));

    h.txtStatus = uicontrol(fig,'Style','text', ...
        'String','Pick a folder. Single: RAW0/RAW1/CLEAN. Or BATCH over subfolders (e.g. EXP Q1 -> P-CON, P-HF, P-LF).', ...
        'HorizontalAlignment','left','BackgroundColor','w','ForegroundColor',[0.2 0.2 0.2], ...
        'Units','pixels','Position',[20 14 580 68]);

    guidata(fig, h);
    if nargout > 0, figOut = fig; end
end

% =====================================================================
function i_onBrowse(fig)
    h = guidata(fig);
    d0 = h.expDir; if isempty(d0) || ~isfolder(d0), d0 = pwd; end
    d = uigetdir(d0, 'Pick folder containing experiment .mat files');
    if isequal(d,0), return; end
    h.expDir = d; set(h.edDir,'String',d); guidata(fig,h);
    i_status(fig, sprintf('Folder: %s', d));
end

function i_status(fig, msg)
    h = guidata(fig);
    if isfield(h,'txtStatus') && ishghandle(h.txtStatus)
        set(h.txtStatus,'String',msg); drawnow;
    end
    fprintf('%s\n', msg);
end

% =====================================================================
function i_onProduce(fig, mode)
%I_ONPRODUCE  1 folder eksperimen (dari kotak) -> 1 mode. Output ke
%   CLCC/<namaFolder>/.
    h = guidata(fig);
    expDir = strtrim(get(h.edDir,'String'));
    if isempty(expDir) || ~isfolder(expDir)
        i_status(fig,'Folder tidak valid. Klik Browse…'); return;
    end
    h.expDir = expDir; guidata(fig,h);

    outDir = i_outDirFor(expDir);
    ok = i_produce(fig, expDir, mode, outDir);
    if ~ok, return; end
    i_status(fig, sprintf('Selesai %s -> %s', upper(mode), outDir));
end

% =====================================================================
function i_onProduceAll(fig)
%I_ONPRODUCEALL  BATCH: folder di kotak dianggap PARENT berisi SUBFOLDER
%   eksperimen (mis. EXP Q1 -> P-CON/P-HF/P-LF). Tiap subfolder yg punya .mat
%   -> 3 mode (raw0/raw1/clean) ke CLCC/<namaSubfolder>/.
    h = guidata(fig);
    parent = strtrim(get(h.edDir,'String'));
    if isempty(parent) || ~isfolder(parent)
        i_status(fig,'Folder induk tidak valid. Klik Browse… (pilih folder yg berisi subfolder eksperimen).'); return;
    end
    h.expDir = parent; guidata(fig,h);

    subs = i_expSubfolders(parent);
    if isempty(subs)
        i_status(fig,'Tak ada subfolder berisi .mat eksperimen di folder induk itu.'); return;
    end
    modes = {'raw0','raw1','clean','axslip'};
    nOk = 0;
    for s = 1:numel(subs)
        [~, sname] = fileparts(subs{s});
        outDir = i_outDirFor(subs{s});
        for m = 1:numel(modes)
            i_status(fig, sprintf('[%d/%d %s] %s …', s, numel(subs), sname, upper(modes{m})));
            if i_produce(fig, subs{s}, modes{m}, outDir), nOk = nOk + 1; end
        end
    end
    i_status(fig, sprintf('Selesai BATCH: %d subfolder × 4 mode = %d PDF ke CLCC/<subfolder>/.', ...
        numel(subs), nOk));
end

% =====================================================================
function outDir = i_outDirFor(expDir)
%I_OUTDIRFOR  Folder output = CLCC/<namaFolderEksperimen>/.
    [~, name] = fileparts(strip_trailing_sep(expDir));
    if isempty(name), name = 'default'; end
    outDir = fullfile(fileparts(mfilename('fullpath')), 'CLCC', name);
    if ~isfolder(outDir), mkdir(outDir); end
end

function p = strip_trailing_sep(p)
    while ~isempty(p) && (p(end)=='/' || p(end)=='\'), p(end) = []; end
end

% =====================================================================
function subs = i_expSubfolders(parent)
%I_EXPSUBFOLDERS  Subfolder langsung di `parent` yg berisi ≥1 .mat eksperimen.
    subs = {};
    d = dir(parent); d = d([d.isdir]);
    for k = 1:numel(d)
        nm = d(k).name;
        if strcmp(nm,'.') || strcmp(nm,'..'), continue; end
        sp = fullfile(parent, nm);
        if ~isempty(i_findExpFiles(sp)), subs{end+1} = sp; end %#ok<AGROW>
    end
    subs = sort(subs);
end

% =====================================================================
function ok = i_produce(fig, expDir, mode, outDir)
%I_PRODUCE  Inti produksi 1 folder + 1 mode -> PDF (+ data .mat) di outDir.
    ok = false;
    files = i_findExpFiles(expDir);
    if isempty(files)
        i_status(fig, sprintf('Tak ada .mat eksperimen di %s', expDir)); return;
    end

    n = numel(files); panels = cell(1,n); xLo = inf; xHi = -inf;
    for i = 1:n
        [~,bn] = fileparts(files{i});
        i_status(fig, sprintf('%s [%d/%d] %s …', upper(mode), i, n, bn));
        try
            panels{i} = i_collectPanel(files{i}, mode);
        catch ME
            panels{i} = [];   % berkas tak bisa dimuat -> lewati (jangan batalkan batch)
            warning('GRAIN4AXPOT:skipFile','Lewati %s: %s', bn, ME.message);
            continue;
        end
        xLo = min(xLo, min(panels{i}.xr)); xHi = max(xHi, max(panels{i}.xr));
    end
    good = ~cellfun(@isempty, panels);
    panels = panels(good); files = files(good);
    if isempty(panels)
        i_status(fig, sprintf('Semua berkas gagal dimuat di %s', expDir)); return;
    end
    n = numel(panels);
    xLim = sort([xLo xHi]);                  % shared X (strain can be negative)

    % --- figure: n panels top->bottom ---
    ff = figure('Color','w','Units','pixels', ...
        'Position',[80 80 1000 220*n+60],'Visible','off');
    try, pivui.forceLightTheme(ff); catch, end
    for i = 1:n
        ax = subplot(n,1,i,'Parent',ff);
        i_renderPanel(ax, panels{i}, xLim, mode);
        if i < n, xlabel(ax,''); end
    end

    if ~isfolder(outDir), mkdir(outDir); end
    % Nama berkas = <nama kelompok EXP>_<jenis plot>.pdf (nama kelompok = folder).
    [~, grpName] = fileparts(strip_trailing_sep(outDir));
    if isempty(grpName), grpName = 'EXP'; end
    outPdf = fullfile(outDir, sprintf('%s_%s.pdf', grpName, upper(mode)));
    outMat = fullfile(outDir, 'PAB4AXPOT.mat');

    set(ff,'PaperPositionMode','auto');
    try
        exportgraphics(ff, outPdf, 'ContentType','vector','BackgroundColor','white');
    catch
        print(ff, outPdf, '-dpdf','-bestfit');
    end
    if isvalid(ff), close(ff); end

    i_saveMat(outMat, mode, files, panels, xLim);
    ok = true;
end

% =====================================================================
function files = i_findExpFiles(expDir)
%I_FINDEXPFILES  Semua .mat eksperimen di folder (abaikan _axpot & subfolder
%   BAK). Diurut natural (F-1,F-2,… bila ada nomor -OVL, else alfabet).
    d = dir(fullfile(expDir,'*.mat'));
    d = d(~[d.isdir]);
    names = {}; keys = {};
    for k = 1:numel(d)
        nm = d(k).name;
        % Buang SEMUA berkas sidecar "<base>_<kata>.mat" (autopot/axpot/axcal/
        % faults/potdata/desc/comments/taper/fault*/shear/link/hb/interp/…).
        % Berkas eksperimen tak pernah punya suffix "_<kata>" sebelum .mat.
        if ~isempty(regexpi(nm,'_[a-z0-9]+\.mat$','once')), continue; end
        % Buang berkas progres/util GRAIN (bukan .mat eksperimen PIV).
        if ~isempty(regexpi(nm,'^(GRAINSA|GRAIN\d|progress|.*_progress_)','once')), continue; end
        names{end+1} = fullfile(d(k).folder, nm); %#ok<AGROW>
        keys{end+1}  = i_sortKey(nm);             %#ok<AGROW>
    end
    if isempty(names), files = {}; return; end
    [~,ord] = sort(keys);
    files = names(ord);
end

function [p1, p2] = i_resolveLine(matFile, data)
%I_RESOLVELINE  Garis PSG (paritas frameCatalog.resolveRender): potdata garis-1
%   -> autopot loadLine -> autoPSG 75% dari ATAS.
    p1 = []; p2 = [];
    ln = pivcore.export.frameCatalog.lineFromPotData(matFile);
    if ~isempty(ln), p1 = ln.p1(:).'; p2 = ln.p2(:).'; return; end
    la = pivcore.io.step1Session.loadLine(matFile);
    if ~isempty(la) && isfield(la,'p1') && isfield(la,'p2')
        p1 = la.p1(:).'; p2 = la.p2(:).'; return;
    end
    x = pivcore.data.safeFrame(data.x, 1);
    y = pivcore.data.safeFrame(data.y, 1);
    xE = [min(x(:)) max(x(:))]; yE = [min(y(:)) max(y(:))];
    yL = yE(2) - 0.75*(yE(2)-yE(1));   % 75% dari ATAS (YDir normal)
    p1 = [xE(1) yL]; p2 = [xE(2) yL];
end

function key = i_sortKey(nm)
%I_SORTKEY  Kunci urut: bila ada pola "-<n>-OVL" pakai nomor (F-1..F-N), else nama.
    tok = regexpi(nm,'-(\d+)-OVL','tokens','once');
    if ~isempty(tok)
        key = sprintf('%06d', str2double(tok{1}));
    else
        key = lower(nm);
    end
end

% =====================================================================
function P = i_collectPanel(matFile, mode)
%I_COLLECTPANEL  Muat + sampel POT (reuse jalur GRAIN4 via frameCatalog), lalu
%   siapkan struct panel siap-render. Mode:
%     'raw0'  = overlay mentah penuh (tanpa clean, tanpa sesar).
%     'raw1'  = di-clean (excluded dibuang + trim ke indenter), POLOS (tanpa sesar).
%     'clean' = di-clean + sesar HW(merah)/FW(biru) + fill (faults.json). Tanpa POI.
    [~, base] = fileparts(matFile);
    applyClean = any(strcmpi(mode, {'raw1','clean','axslip'}));   % buang excluded + trim
    drawFaults = strcmpi(mode, 'clean');                 % HW/FW + fill
    drawSlip   = strcmpi(mode, 'axslip');                % net-slip (HW-FW) per sesar, fill ke 0

    % --- garis PSG (jalur kanonik GRAIN, TANPA re-sampling resolveRender) ---
    %   Prioritas: potdata garis-1 -> autopot loadLine -> autoPSG 75% dari atas.
    data = pivcore.io.step1Session.loadAllFrames(matFile);
    [p1, p2] = i_resolveLine(matFile, data);

    % --- spacing node ---
    sp = pivcore.io.step1Session.savedSpacing(matFile);
    if ~(isscalar(sp) && isfinite(sp) && sp > 0)
        dd = pivcore.data.nodeSpacing(data);
        if isfinite(dd) && dd > 0, sp = round(dd); else, sp = 10; end
    end

    recs = pivcore.pot.step1Collect.collectAlongLine(data, p1, p2, sp, 'velocity_magnitude');
    recs = pivcore.pot.records.normalize(recs);
    recs = pivcore.pot.records.applyColors(recs);

    nF = 0; for r=1:numel(recs), nF = max(nF, numel(recs(r).data)); end
    nF = max(1, nF);

    % --- kalibrasi (ringan: geom + dt EXIF; indenterMax dari POT ini) ---
    [strTotG, ~, dxCm] = pivcore.export.frameCatalog.readGeom(matFile);
    dtSec = pivcore.export.frameCatalog.readExifDt(matFile);
    R = struct('strainTotalPct', strTotG, 'dxCm', dxCm, 'dtSec', dtSec, ...
        'nFrames', nF, 'velMultGeom', NaN);

    faults = {};
    if applyClean
        % potdata: excluded + cutFrame (trim ke max indenter) — POSISIONAL.
        recs = i_applyPotData(matFile, recs);
    end
    if drawFaults || drawSlip
        % faults: HW/FW pasangan (+ fill / net-slip). POI TIDAK dipakai.
        faults = i_loadFaults(matFile, recs, nF);
    end

    % Envelope indenter (hormati excluded bila di-clean; raw0 = semua).
    env = i_indenterEnv(recs, nF, applyClean);

    % --- velMultGeom (indenter-calibrated cm/s per px/frame), paritas frameCatalog:
    %   kec.fisik indenter = dxCm/((nF-1)*dt) cm/s ; |V| indenter = indenterMax px/fr.
    %   indenterMax dihitung dari envelope MENTAH (tanpa excluded) agar kalibrasi
    %   stabil (identik jalur frameCatalog.resolveRender). ---
    envRaw = env;
    if applyClean, envRaw = i_indenterEnv(recs, nF, false); end
    indMax = NaN;
    if ~isempty(envRaw), e = envRaw(isfinite(envRaw)); if ~isempty(e), indMax = max(e); end, end
    if isfinite(R.dxCm) && R.dxCm > 0 && isfinite(R.dtSec) && R.dtSec > 0 ...
            && nF > 1 && isfinite(indMax) && indMax > 0
        R.velMultGeom = (R.dxCm / ((nF-1)*R.dtSec)) / indMax;   % cm/s per (px/frame)
    end

    % --- Real-world axes ---
    % X: strain kumulatif % per-frame (frame 1..nF -> 0..strainTot).
    strTot = R.strainTotalPct;
    haveStrain = isfinite(strTot) && strTot ~= 0 && nF > 1;
    if haveStrain, xr = (0:nF-1)/(nF-1)*strTot; else, xr = 1:nF; end
    % Y: |V| px/frame -> cm/s via geom velMult (indenter-terkalibrasi).
    vMult = R.velMultGeom; haveVel = isfinite(vMult) && vMult > 0;
    if ~haveVel, vMult = 1; end

    P = struct();
    P.base   = base;
    P.recs   = recs;
    P.nF     = nF;
    P.env    = env;
    P.faults = {faults};        % wrap: cell of fault-structs
    P.applyClean = applyClean;  % excluded dibuang + trim
    P.drawFaults = drawFaults;  % HW/FW + fill
    P.drawSlip   = drawSlip;    % net-slip (HW-FW) per sesar, fill ke 0
    P.mode   = lower(mode);
    P.xr     = xr;              % per-frame X (strain% atau frame)
    P.haveStrain = haveStrain;
    P.vMult  = vMult;
    P.haveVel= haveVel;
    P.strainTot = strTot;
end

% =====================================================================
function recs = i_applyPotData(matFile, recs)
%I_APPLYPOTDATA  Terapkan <base>_potdata.json garis PERTAMA (positional):
%   excluded + cutFrame. Identik GRAIN4 i_applyDocLabels (subset yg relevan
%   untuk membersihkan overlay — label tak diperlukan di sini).
    try
        doc = pivcore.io.grain4PotData.read(matFile);
    catch
        return;   % tak ada sidecar -> biarkan mentah
    end
    if ~isstruct(doc) || ~isfield(doc,'psgLines') || isempty(doc.psgLines), return; end
    ln = doc.psgLines{1};
    if ~isstruct(ln) || ~isfield(ln,'curves'), return; end
    m = min(numel(recs), numel(ln.curves));
    for k = 1:m
        c = ln.curves{k};
        if ~isstruct(c), continue; end
        if isfield(c,'cutFrame') && isscalar(c.cutFrame) && isfinite(c.cutFrame)
            recs(k).cutManual = true; recs(k).cutFrame = c.cutFrame;
        end
        if isfield(c,'excluded') && isscalar(c.excluded) && logical(c.excluded)
            recs(k).excluded = true;
        end
    end
end

% =====================================================================
function faults = i_loadFaults(matFile, recs, nF)
%I_LOADFAULTS  Baca <base>_faults.json, resolusi HW/FW row via posPx, hitung
%   kurva HW/FW TAMPIL (trim) + fill zona [startF,endF]. Reuse logika GRAIN5
%   (rowForPos + faultNetslip clamp). Return cell of struct.
    faults = {};
    try
        doc = pivcore.io.grain5Faults.read(matFile);
    catch
        return;
    end
    if ~isstruct(doc) || ~isfield(doc,'faults') || isempty(doc.faults), return; end

    hloc = struct('recs',recs, 'nF',nF, 'spacing',[], 'signConv','signed');

    F = doc.faults;
    if isstruct(F), F = num2cell(F); end
    for k = 1:numel(F)
        f = F{k};
        if ~isstruct(f), continue; end
        if isfield(f,'enabled') && isscalar(f.enabled) && ~logical(f.enabled), continue; end
        if ~isempty(i_parentId(f)), continue; end     % sub-fault: lewati (fill hanya F# utama)

        hwRow = i_rowForPos(recs, f.hwPosPx);
        fwRow = i_rowForPos(recs, f.fwPosPx);
        if isempty(hwRow), continue; end

        yHW = i_dispY(recs, hwRow, nF);
        yFW = []; if ~isempty(fwRow), yFW = i_dispY(recs, fwRow, nF); end

        a = f.startF; b = f.endF;
        if ~(isfinite(a) && isfinite(b))
            gg = isfinite(yHW); if ~isempty(yFW), gg = gg & isfinite(yFW); end
            idxg = find(gg);
            if isempty(idxg), a = 1; b = nF; else, a = idxg(1); b = idxg(end); end
        end
        a = max(1, round(min(a,b))); b = min(nF, round(max(a,b)));

        % Potong kurva HW/FW ke [a,b] (NaN di luar) — sama seperti GRAIN5.
        yHWc = i_clampRange(yHW, a, b);
        yFWc = []; if ~isempty(yFW), yFWc = i_clampRange(yFW, a, b); end

        fs = struct('uiNum', i_uiNum(f), 'a',a, 'b',b, ...
            'yHW',yHWc, 'yFW',yFWc, 'hasFW', ~isempty(yFWc));
        faults{end+1} = fs; %#ok<AGROW>
    end
end

function id = i_parentId(f)
    id = '';
    if isfield(f,'parentId') && (ischar(f.parentId) || isstring(f.parentId))
        id = char(f.parentId);
    end
end
function n = i_uiNum(f)
    n = NaN;
    if isfield(f,'uiNum') && isscalar(f.uiNum) && isfinite(f.uiNum), n = f.uiNum; end
end

function r = i_rowForPos(recs, posPx)
%I_ROWFORPOS  Petakan posPx -> baris record terdekat (≤ max(8,0.75*spacing)).
%   Salinan pivui.grain5Model.rowForPos (spacing diestimasi dari jarak posPx).
    r = [];
    if ~isscalar(posPx) || ~isfinite(posPx) || isempty(recs), return; end
    best = inf; bestR = [];
    ps = [];
    for k = 1:numel(recs)
        if isfield(recs(k),'excluded') && isscalar(recs(k).excluded) && logical(recs(k).excluded), continue; end
        p = NaN;
        if isfield(recs(k),'posPx') && isscalar(recs(k).posPx), p = recs(k).posPx; end
        if isfinite(p)
            ps(end+1) = p; %#ok<AGROW>
            d = abs(p - posPx);
            if d < best, best = d; bestR = k; end
        end
    end
    if isempty(bestR), return; end
    sp = 10; if numel(ps) >= 2, dsp = median(diff(sort(ps))); if isfinite(dsp)&&dsp>0, sp = dsp; end, end
    if best <= max(8, 0.75*sp), r = bestR; end
end

function y = i_dispY(recs, row, nF)
%I_DISPY  Deret-Y tampil (trim diterapkan). Tanpa moving-average (GRAIN4 no-op).
    y = [];
    if isempty(row) || row < 1 || row > numel(recs), return; end
    [~, y] = pivcore.pot.records.curveXY(recs(row), nF);
    y = pivui.grain4Shell.applyTrimYV(recs(row), y);
end

function y = i_clampRange(y, a, b)
%I_CLAMPRANGE  NaN-kan indeks di luar [a,b] (salinan pivui.grain5Fmt.clampRange).
    if isempty(y), return; end
    n = numel(y); idx = 1:n;
    y(idx < a | idx > b) = NaN;
end

% =====================================================================
function env = i_indenterEnv(recs, nF, honorExcluded)
%I_INDENTERENV  Max envelope per-frame (identik pivui.grain4Shell.indenterEnvelope).
    M = -inf(1,nF); any_ = false;
    for r = 1:numel(recs)
        if honorExcluded && isfield(recs(r),'excluded') && isscalar(recs(r).excluded) ...
                && logical(recs(r).excluded), continue; end
        [~, yv] = pivcore.pot.records.curveXY(recs(r), nF);
        yv = pivui.grain4Shell.applyTrimYV(recs(r), yv);   % trim ikut (clean)
        if isempty(yv), continue; end
        m = numel(yv); seg = M(1:m); g = isfinite(yv);
        seg(g) = max(seg(g), yv(g)); M(1:m) = seg; any_ = true;
    end
    if ~any_, env = []; return; end
    M(~isfinite(M)) = NaN; env = M;
end

% =====================================================================
function i_renderPanel(ax, P, xLim, mode) %#ok<INUSD>
%I_RENDERPANEL  Satu axPOT overlay. Real-world axes (X=strain%, Y=cm/s bila
%   tersedia; sumbu-X dibalik: 0 kiri, strain paling negatif kanan).
%   raw0 = semua kurva. raw1 = di-clean (excluded dibuang + trim), POLOS.
%   clean = di-clean + sesar HW(merah)/FW(biru) + fill zona. TANPA POI.
    cla(ax);
    set(ax,'Color','w','XColor',[0.15 0.15 0.15],'YColor',[0.15 0.15 0.15], ...
        'GridColor',[0.85 0.85 0.85],'GridAlpha',1,'Box','on','Layer','top');
    hold(ax,'on');
    applyClean = P.applyClean; drawFaults = P.drawFaults;
    drawSlip = isfield(P,'drawSlip') && P.drawSlip;
    vM = P.vMult;                         % px/frame -> cm/s (atau 1)
    X  = P.xr;                            % per-frame X (strain% atau frame)

    % --- AX-SLIP: net-slip (HW-FW) per sesar, fill ke 0, warna beda tiap sesar.
    %     Tanpa kurva mentah, tanpa indenter, tanpa garis vertikal DX/POI. ---
    if drawSlip
        i_renderSlipPanel(ax, P, xLim);
        return;
    end

    nShown = 0; nDel = 0; ymax = -inf;
    for r = 1:numel(P.recs)
        excl = isField(P.recs(r),'excluded') && logical(P.recs(r).excluded);
        if applyClean && excl, nDel = nDel + 1; continue; end
        [~, yv] = pivcore.pot.records.curveXY(P.recs(r), P.nF);
        if applyClean, yv = pivui.grain4Shell.applyTrimYV(P.recs(r), yv); end
        yv = yv(:).' * vM;
        m = min(numel(yv), numel(X));
        xv = X(1:m); yv = yv(1:m);
        g = isfinite(xv) & isfinite(yv); if ~any(g), continue; end
        nShown = nShown + 1;
        col = P.recs(r).color; if numel(col)~=3, col=[0.4 0.4 0.4]; end
        lw = 0.6;   % CLEAN & RAW: kurva mentah warna-warni asli
        plot(ax, xv(g), yv(g), '-', 'Color',col, 'LineWidth',lw);
        ymax = max(ymax, max(yv(g)));
    end

    % --- CLEAN: sesar (fill + HW merah + FW biru), TANPA POI ---
    if drawFaults && ~isempty(P.faults) && ~isempty(P.faults{1})
        F = P.faults{1};
        pastel = { [0.70 0.85 0.70], [0.72 0.80 0.95], [0.98 0.85 0.70], ...
                   [0.90 0.78 0.95], [0.75 0.92 0.92], [0.95 0.80 0.82] };
        for k = 1:numel(F)
            f = F{k};
            fillCol = pastel{mod(k-1,numel(pastel))+1};
            % Fill zona antara HW & FW pada [a,b].
            if f.hasFW
                ia = f.a:f.b;
                top = f.yHW(ia)*vM; bot = f.yFW(ia)*vM;
                gg = isfinite(top) & isfinite(bot);
                xa = X(ia(gg)); ta = top(gg); ba = bot(gg);
                if numel(xa) >= 2
                    fill(ax, [xa fliplr(xa)], [ta fliplr(ba)], fillCol, ...
                        'FaceAlpha',0.55,'EdgeColor','none');
                    ymax = max(ymax, max([ta ba]));
                end
            end
            % HW (merah) & FW (biru).
            yHW = f.yHW*vM; gH = isfinite(yHW);
            mH = min(numel(yHW),numel(X));
            if any(gH(1:mH))
                plot(ax, X(1:mH), yHW(1:mH), '-', 'Color',[0.85 0.10 0.10],'LineWidth',1.8);
                ymax = max(ymax, max(yHW(isfinite(yHW))));
            end
            if f.hasFW
                yFW = f.yFW*vM; mF = min(numel(yFW),numel(X));
                if any(isfinite(yFW(1:mF)))
                    plot(ax, X(1:mF), yFW(1:mF), '-', 'Color',[0.30 0.45 0.85],'LineWidth',1.8);
                    ymax = max(ymax, max(yFW(isfinite(yFW))));
                end
            end
        end
    end

    % --- Indenter envelope (garis hitam, paling atas) ---
    if ~isempty(P.env)
        e = P.env(:).' * vM; me = min(numel(e),numel(X));
        xe = X(1:me); ge = isfinite(e(1:me));
        if any(ge)
            plot(ax, xe(ge), e(ge), '-', 'Color',[0 0 0],'LineWidth',3);
            ymax = max(ymax, max(e(ge)));
        end
    end

    hold(ax,'off'); grid(ax,'on');

    % Labels (real-world).
    if P.haveStrain, xlabel(ax,'Cumulative strain (%)'); else, xlabel(ax,'Frame'); end
    if P.haveVel,    ylabel(ax,'Velocity (cm/s)');        else, ylabel(ax,'|V| (px/frame)'); end

    % Title.
    unitTag = '';
    if ~P.haveVel, unitTag = ' [Y=px/frame: Y-calib. missing]'; end
    switch P.mode
        case 'raw0'
            ttl = sprintf('%s  —  RAW0: %d curves (black = max indenter)%s', ...
                P.base, nShown, unitTag);
        case 'raw1'
            ttl = sprintf('%s  —  RAW1: %d curves (%d removed; black = max indenter)%s', ...
                P.base, nShown, nDel, unitTag);
        otherwise
            ttl = sprintf('%s  —  CLEAN: %d curves (%d removed; black = max indenter)%s', ...
                P.base, nShown, nDel, unitTag);
    end
    title(ax, ttl, 'Color',[0 0 0],'Interpreter','none','FontSize',9);

    xlim(ax, xLim);
    if isfinite(ymax) && ymax > 0, ylim(ax,[0 ymax*1.05]); end
    % Sumbu-X dibalik: 0 di KIRI, strain paling negatif di KANAN. (strain
    % kumulatif shortening bernilai negatif -> XDir 'reverse' menaruh 0 di kiri.)
    if P.haveStrain, set(ax,'XDir','reverse'); else, set(ax,'XDir','normal'); end
end

function tf = isField(s, f), tf = isfield(s,f) && isscalar(s.(f)); end

% =====================================================================
function i_renderSlipPanel(ax, P, xLim)
%I_RENDERSLIPPANEL  AX-SLIP: satu kurva net-slip (HW - FW) per sesar sepanjang
%   [startF,endF], di-FILL dari 0 ke kurva. Tiap sesar warna fill BEDA. Sumbu
%   real-world (X=strain%, Y=cm/s bila terkalibrasi). TANPA kurva mentah,
%   indenter, atau garis vertikal DX/POI.
    vM = P.vMult; X = P.xr;
    ymax = -inf; ymin = inf; nF_ = 0;

    % Palet garis (jenuh) — dipasangkan dgn fill pastel senada.
    lineCol = { [0.20 0.55 0.25], [0.20 0.35 0.80], [0.85 0.45 0.10], ...
                [0.55 0.25 0.70], [0.10 0.60 0.62], [0.80 0.20 0.35] };
    fillCol = { [0.72 0.88 0.72], [0.74 0.82 0.96], [0.98 0.86 0.72], ...
                [0.88 0.78 0.95], [0.76 0.92 0.92], [0.96 0.80 0.84] };

    F = {};
    if ~isempty(P.faults) && ~isempty(P.faults{1}), F = P.faults{1}; end
    for k = 1:numel(F)
        f = F{k};
        if ~f.hasFW, continue; end          % net-slip perlu HW & FW
        ns = f.yHW - f.yFW;                  % net-slip (px/frame)
        ia = f.a:f.b;
        m = min([numel(ns), numel(X), max(ia)]);
        ia = ia(ia <= m);
        y = ns(ia) * vM; x = X(ia);
        g = isfinite(x) & isfinite(y);
        xa = x(g); ya = y(g);
        if numel(xa) < 2, continue; end
        lc = lineCol{mod(k-1,numel(lineCol))+1};
        fc = fillCol{mod(k-1,numel(fillCol))+1};
        % Fill dari 0 ke kurva net-slip.
        fill(ax, [xa fliplr(xa)], [ya zeros(1,numel(ya))], fc, ...
            'FaceAlpha',0.55, 'EdgeColor','none', 'HandleVisibility','off');
        plot(ax, xa, ya, '-', 'Color',lc, 'LineWidth',1.8, ...
            'DisplayName',sprintf('F%d', i_slipNum(f,k)));
        ymax = max(ymax, max(ya)); ymin = min(ymin, min(ya)); nF_ = nF_ + 1;
    end
    % Garis nol referensi.
    plot(ax, xLim, [0 0], '-', 'Color',[0.6 0.6 0.6], 'LineWidth',0.5, ...
        'HandleVisibility','off');

    grid(ax,'on');
    if P.haveStrain, xlabel(ax,'Cumulative strain (%)'); else, xlabel(ax,'Frame'); end
    if P.haveVel,    ylabel(ax,'|v_{HW}| - |v_{FW}| (cm/s)'); else, ylabel(ax,'|v_{HW}| - |v_{FW}| (px/frame)'); end

    unitTag = ''; if ~P.haveVel, unitTag = ' [Y=px/frame: Y-calib. missing]'; end
    ttl = sprintf('%s  —  AX-SLIP: %d fault(s) net-slip (fill to 0)%s', ...
        P.base, nF_, unitTag);
    title(ax, ttl, 'Color',[0 0 0],'Interpreter','none','FontSize',9);

    xlim(ax, xLim);
    if isfinite(ymin) && isfinite(ymax)
        lo = min(0, ymin); hi = max(0, ymax);
        pad = 0.05*max([abs(lo) abs(hi) eps]);   % skalar
        if hi > lo, ylim(ax,[lo-pad hi+pad]); end
    end
    if P.haveStrain, set(ax,'XDir','reverse'); else, set(ax,'XDir','normal'); end
    if nF_ > 0, legend(ax,'show','Location','best','Box','off','FontSize',7); end
end

function n = i_slipNum(f, k)
%I_SLIPNUM  Nomor sesar utk legend (uiNum bila ada, else urutan).
    n = k;
    if isfield(f,'uiNum') && isscalar(f.uiNum) && isfinite(f.uiNum), n = f.uiNum; end
end

% =====================================================================
function i_saveMat(outMat, mode, files, panels, xLim)
%I_SAVEMAT  Simpan data numerik panel ke CLCC/PAB4AXPOT.mat (per-mode field).
%   Struktur additive: berkas menampung 'raw' dan/atau 'clean'.
    S = struct();
    if isfile(outMat)
        try, S = load(outMat); catch, S = struct(); end
    end
    rec = struct('files',{files}, 'xLim',xLim, 'panels',{cell(1,numel(panels))});
    for i = 1:numel(panels)
        P = panels{i};
        pp = struct('base',P.base, 'nF',P.nF, 'xr',P.xr, 'env',P.env, ...
            'haveStrain',P.haveStrain, 'strainTot',P.strainTot, ...
            'haveVel',P.haveVel, 'vMult',P.vMult, ...
            'yUnit', ternary(P.haveVel,'cm/s','px/frame'), ...
            'xUnit', ternary(P.haveStrain,'strain%','frame'));
        % Simpan deret |V| mentah (cm/s bila terkalibrasi) tiap kurva ditampilkan.
        rec.panels{i} = pp;
    end
    S.(lower(mode)) = rec; %#ok<STRNU>
    save(outMat, '-struct','S');
end

function v = ternary(c,a,b), if c, v=a; else, v=b; end, end
