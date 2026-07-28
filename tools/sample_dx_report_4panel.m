function sample_dx_report_4panel(matPath, faultNums, outPdf)
%SAMPLE_DX_REPORT_4PANEL  SAMPEL laporan DX 1-halaman-4-panel per (sesar, FSR-max).
%
%   TIDAK me-reinvent tampilan: panel kiri-atas = axPOT GRAIN4 ASLI (snapshot
%   copyobj dari h.axPOT hidup) -> spaghetti curve MENTAH semua data + HW/FW
%   merah/biru + fill warna assign + garis vertikal DX (ground-truth POI GRAIN4),
%   dengan HIGHLIGHT hanya sesar aktif (persis GRAIN4: showAllFaults=true +
%   setActiveFault). Hanya di-ZOOM ke jendela 150-frame (aturan FSR-max).
%
%   Layout 2x2 rapat (tight), langsung ke PDF landscape (TANPA JPG antara):
%     kiri-atas   = AX POT  (snapshot GRAIN4 hidup, X=Frame, di-zoom)
%     kiri-bawah  = AX SLIP (snapshot GRAIN4 hidup view='slip', di-zoom)
%     kanan-atas  = AX main velmag  (frame = tengah jendela; setting LIVE GRAIN4)
%     kanan-bawah = AX main shear   (idem)
%
%   Jendela X = 150 frame DIPUSATKAN di tengah dua FSR-max sesar itu, di-clamp
%   ke [1..nF] bila mepet tepi (tak digeser keluar).
%
%   Contoh (PHF-1, FSR-max pertama F1 & F5):
%     sample_dx_report_4panel(...
%       fullfile(grain_fixture_root(),'EXP_coll','EXP Q1','P-HF-4cm-F','P-HF-4cm-F-1-OVL-S0-411to410-3p25px.mat'), ...
%       [1 5]);

    if nargin < 2 || isempty(faultNums), faultNums = [1 5]; end
    [dir0, base, ~] = fileparts(matPath);
    if nargin < 3 || isempty(outPdf)
        outPdf = fullfile(dir0, sprintf('%s_SAMPLE_DXreport.pdf', base));
    end
    grain = fileparts(fileparts(mfilename('fullpath')));   % .../GRAIN
    addpath(fullfile(grain,'pivcore_lib'));

    % ---- FS-max frame per sesar dari _desc.json rows[] (ground truth GRAIN4) ----
    descDoc = pivcore.io.grain4Desc.read(matPath);
    rows = descDoc.rows; if ~iscell(rows), rows = num2cell(rows); end
    fsmax = containers.Map('KeyType','char','ValueType','any');
    for i = 1:numel(rows)
        r = rows{i};
        if strcmpi(strtrim(char(i_g(r,'poi',''))),'FS-max')
            fk = upper(strtrim(char(i_g(r,'fNum',''))));
            v  = i_g(r,'frame',NaN);
            if isscalar(v) && isfinite(v)
                if isKey(fsmax,fk), fsmax(fk) = [fsmax(fk) v]; else, fsmax(fk) = v; end
            end
        end
    end

    % ---- luncurkan GRAIN4 headless pada folder exp, muat exp ini ----
    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>
    fprintf('Membuka GRAIN4 di %s …\n', dir0);
    fig = GRAIN4(dir0);
    cuFig = onCleanup(@() i_closeIf(fig)); %#ok<NASGU>
    h = guidata(fig);
    row = i_expRowByBase(h, base);
    assert(row>=1, 'Eksperimen %s tak ada di daftar folder.', base);
    pivui.grain4Shell.loadExperiment(fig, row);
    pivui.grain4Shell.ensureFull(fig);     % muat semua bingkai (velmag/shear)
    h = guidata(fig);
    nF = h.nF;
    fprintf('  exp dimuat: %s (nF=%d, psg=%s)\n', base, nF, h.activePsgId);

    % ---- rakit PDF ----
    if isfile(outPdf), delete(outPdf); end
    firstPage = true;
    for fnum = faultNums(:).'
        ftag = sprintf('F%d', fnum);
        f = i_faultByUiNum(h, fnum);
        if isempty(f), warning('Sesar %s tak ada; dilewati.', ftag); continue; end

        if isKey(fsmax, ftag), fsv = sort(fsmax(ftag)); else, fsv = []; end
        if numel(fsv) >= 2, fsPair = fsv(1:2);
        elseif numel(fsv) == 1, fsPair = [fsv fsv];
        else, fsPair = [round(nF/2) round(nF/2)]; warning('%s: tak ada FS-max.', ftag);
        end

        % jendela 150 frame dipusatkan di tengah pasangan, clamp ke [1 nF].
        ctr = round(mean(fsPair)); win = 150;
        lo = ctr - floor(win/2); hi = lo + win - 1;
        if lo < 1, lo = 1; hi = min(nF, lo+win-1); end
        if hi > nF, hi = nF; lo = max(1, hi-win+1); end
        % FRAME yg DIOBSERVE = FS-max PERTAMA (bukan tengah jendela). FS-max ada 2
        % tapi hanya 1 yg diobserve per halaman -> velmag/shear + highlight di sini.
        obsFrame = max(1, min(nF, fsPair(1)));
        fprintf('  %s: FS-max=[%s] pusat=%d jendela=[%d %d] frame diobserve=%d\n', ...
            ftag, num2str(fsPair), ctr, lo, hi, obsFrame);

        i_makePage(fig, base, f, ftag, lo, hi, obsFrame, fsPair, outPdf, firstPage);
        firstPage = false;
    end
    fprintf('SELESAI -> %s\n', outPdf);
end

% =====================================================================
function i_makePage(fig, base, f, ftag, lo, hi, frameMid, fsPair, outPdf, firstPage)
    h = guidata(fig);

    % HIGHLIGHT HANYA SESAR AKTIF (showAllFaults=false): spaghetti mentah tetap
    % tampil (warna per-kurva), hanya sesar aktif dapat HW/FW merah-biru + fill +
    % POI. Persis resep Group C GRAIN4 (i_reportFaultAxpot).
    h.activeFaultId = f.id; h.showAllFaults = false; h.showAllSlip = false;
    % Spaghetti mentah: warna-warni + TIPIS (permintaan user).
    h.lwRaw = 0.5;
    % MATIKAN semua sesar KECUALI aktif (seperti uncheck ⏻ di tabel F) supaya
    % i_drawPersistentZones hanya fill/HW-FW sesar aktif. Simpan state utk restore.
    fdoc0 = h.fdoc;
    h.fdoc = i_enableOnly(h.fdoc, f.id);
    guidata(fig, h);
    cuRestore = onCleanup(@() i_restoreFdoc(fig, fdoc0)); %#ok<NASGU>

    pg = figure('Visible','off','Color','w','Units','pixels','Position',[50 50 1500 900]);
    try, pivui.forceLightTheme(pg); catch, end
    set(pg,'Color','w');
    cu = onCleanup(@() i_closeIf(pg)); %#ok<NASGU>
    annotation(pg,'textbox',[0.02 0.955 0.96 0.04], 'String', ...
        sprintf('%s  —  %s  (DX @ FSR-max: frames %s)', base, ftag, num2str(fsPair)), ...
        'Interpreter','none','FontWeight','bold','Color',[0 0 0], ...
        'HorizontalAlignment','center','VerticalAlignment','middle', ...
        'EdgeColor','none','FontSize',11);

    velMult = i_velMult(h);
    strainTot = i_strainTot(h);
    % Y-MAX axPOT = 1.2 * max_indenter (cm/s). AX SLIP pakai skalanya sendiri
    % (1.2 * max net-slip yg diplot) -> dihitung di dalam i_snapPot (yTop=NaN).
    indMaxCms = i_indenterMaxCms(h, velMult);
    yTopPot = 1.2 * indMaxCms;

    % Baris DX (POI) sesar ini utk label garis vertikal.
    dxPoi = i_dxPoiForFault(h, ftag);
    % FOKUS = FRAME yg diobserve (frameMid), BUKAN jenis POI. FS-max ada 2 tapi
    % yg di-highlight hanya frame ini. POI utk judul AX main = POI baris DX di
    % frame ini (fallback 'FS-max').
    focusFrame = frameMid;
    poiAtFrame = i_poiAtFrame(dxPoi, focusFrame);
    if isempty(poiAtFrame), poiAtFrame = 'FS-max'; end

    % ---- LAYOUT MANUAL: kolom kanan (AX main) lebih LEBAR & TINGGI, kiri lebih
    %      sempit. Optimalkan white-space; AX main isi citra memanjang. ----
    xL = 0.050;  wL = 0.30;                 % kolom kiri (POT/SLIP) — dipersempit
    xR = 0.405;  wR = 0.585;                % kolom kanan (AX main) — DIPERLEBAR
    yTopRow = 0.535; hRow = 0.375;          % baris atas
    yBotRow = 0.075;                        % baris bawah

    % (1) kiri-atas: AX POT
    axP = axes('Parent',pg,'Position',[xL yTopRow wL hRow]);
    i_snapPot(fig, axP, 'pot', lo, hi, velMult, strainTot, yTopPot, dxPoi, focusFrame);
    title(axP, sprintf('AX POT — %s', ftag), 'Interpreter','none','Color',[0 0 0]);

    % (2) kiri-bawah: AX SLIP (y-max sendiri)
    axS = axes('Parent',pg,'Position',[xL yBotRow wL hRow]);
    i_snapPot(fig, axS, 'slip', lo, hi, velMult, strainTot, NaN, dxPoi, focusFrame);
    title(axS, sprintf('AX SLIP — %s', ftag), 'Interpreter','none','Color',[0 0 0]);

    % (3)(4) kanan: AX main velmag & shear — lebih besar, tick disembunyikan.
    axV = axes('Parent',pg,'Position',[xR yTopRow wR hRow]);
    i_snapMain(fig, axV, 'velmag', frameMid, ...
        sprintf('%s - %s - Velocity Magnitude', ftag, poiAtFrame));
    axH = axes('Parent',pg,'Position',[xR yBotRow wR hRow]);
    i_snapMain(fig, axH, 'shear', frameMid, ...
        sprintf('%s - %s - Shear Strain', ftag, poiAtFrame));

    if firstPage
        exportgraphics(pg, outPdf, 'ContentType','image','Resolution',150);
    else
        exportgraphics(pg, outPdf, 'ContentType','image','Resolution',150,'Append',true);
    end
end

% =====================================================================
function i_snapPot(fig, axDst, view, lo, hi, velMult, strainTot, yTop, dxPoi, focusFrame)
%I_SNAPPOT  Render axPOT/AXSLIP GRAIN4 HIDUP (view='pot'|'slip') lalu SALIN child
%   ke axDst DENGAN KALIBRASI: X = cumulative strain % (dibalik), Y = cm/s.
%   Y-max = yTop; jika yTop=NaN (AX SLIP) -> 1.2*max(|HW-FW|) di jendela.
%   Modifikasi tampilan:
%     - titik POI GRAIN5 (Tag nsPoint / poiVline) + garis cut-off AXSLIP DIBUANG,
%     - garis vertikal DX: HANYA yg di FRAME fokus (focusFrame, = frame diobserve)
%       MERAH TEBAL; DX lain warna asli GRAIN4 (per-jenis) + TIPIS,
%     - label POI di-ROTATE 90 deg CW dari horizontal.
    if nargin < 10, focusFrame = NaN; end
    pivui.grain4Shell.setPotView(fig, view);
    pivui.grain4Shell.renderPOT(fig);   % decorate hook -> HW/FW/fill/DX vlines
    drawnow;
    h = guidata(fig); src = h.axPOT; nF = h.nF;
    xstrain = isfinite(strainTot);
    xmap = @(xf) i_xmapStrain(xf, nF, strainTot, xstrain);

    % BUANG titik/garis POI GRAIN5 + garis horizontal cut-off AXSLIP di SUMBER.
    try, delete(findall(src,'Tag','nsPoint'));      catch, end   % titik POI GRAIN5
    try, delete(findall(src,'Tag','poiVline'));     catch, end   % garis POI GRAIN5
    try, delete(findall(src,'Tag','axslipCutLine')); catch, end  % garis ambang cut-off

    set(axDst,'Color','w','XColor',[0 0 0],'YColor',[0 0 0],'Box','on','Layer','top');
    grid(axDst,'on'); hold(axDst,'on');
    kids = copyobj(allchild(src), axDst);
    try, delete(findall(axDst,'Tag','frameLine')); catch, end
    try, delete(findall(axDst,'Tag','frameTxt'));  catch, end

    % remap tiap child: X->strain%, Y->cm/s. Kumpulkan Y di JENDELA (utk lantai).
    yWin = [];
    for c = kids(:).'
        try
            tg = ''; if isprop(c,'Tag'), tg = get(c,'Tag'); end
            isVline = strcmp(tg,'descVline');
            if isprop(c,'XData') && ~isempty(get(c,'XData'))
                xf = get(c,'XData');
                inWin = xf >= lo & xf <= hi;
                set(c,'XData', xmap(xf));
                if isprop(c,'YData')
                    yv = get(c,'YData') * velMult; set(c,'YData', yv);
                    if any(inWin) && ~isVline
                        yWin = [yWin, yv(inWin & isfinite(yv))]; %#ok<AGROW>
                    end
                end
            elseif isprop(c,'YData') && ~isempty(get(c,'YData'))
                set(c,'YData', get(c,'YData') * velMult);
            end
            if strcmp(get(c,'Type'),'text')
                p = get(c,'Position');
                if numel(p) >= 2, p(1) = xmap(p(1)); p(2) = p(2)*velMult; set(c,'Position',p); end
            end
        catch
        end
    end
    axDst.YDir = src.YDir;
    if xstrain, xlabel(axDst,'Cumulative strain (%)','Color',[0 0 0]);
    else,       xlabel(axDst,'Frame','Color',[0 0 0]); end
    if strcmp(view,'slip'), ylabel(axDst,'|HW - FW| (cm/s)','Color',[0 0 0]);
    else,                   ylabel(axDst,'|V| (cm/s)','Color',[0 0 0]); end

    % ZOOM X = jendela dipetakan ke strain (dibalik).
    xl = sort([xmap(lo) xmap(hi)]);
    xlim(axDst, xl);
    if xstrain, set(axDst,'XDir','reverse'); end
    ylo = 0; if ~isempty(yWin), ylo = min(0, min(yWin)); end
    % AX SLIP (yTop=NaN): y-max = 1.2 * max(|HW-FW|) yg diplot di jendela.
    if ~(isscalar(yTop) && isfinite(yTop))
        if ~isempty(yWin), yTop = 1.2 * max(yWin(isfinite(yWin))); else, yTop = ylo + 1; end
    end
    if ~(yTop > ylo), yTop = ylo + 1; end
    ylim(axDst, [ylo yTop]);

    % Garis vertikal DX: buang salinan GRAIN4 -> gambar ulang. HIGHLIGHT MERAH TEBAL
    % HANYA garis pada FRAME yg diobserve (focusFrame). DX lain warna asli + tipis.
    try, delete(findall(axDst,'Tag','descVline')); catch, end
    ff = round(focusFrame);
    if ~isempty(dxPoi)
        for i = 1:size(dxPoi,1)
            xf = dxPoi{i,1}; nm = dxPoi{i,2};
            if ~(isscalar(xf) && isfinite(xf)) || xf<lo || xf>hi, continue; end
            isFocus = isscalar(ff) && isfinite(ff) && round(xf)==ff;
            if isFocus, col = [0.85 0 0]; lw = 2.6;    % FRAME yg SEDANG diobserve
            else,       col = i_poiColorLocal(nm); lw = 1.0; end   % DX lain: warna asli, tipis
            xs = xmap(xf);
            plot(axDst, [xs xs], [ylo yTop], '-', 'Color',col, 'LineWidth',lw, ...
                'Tag','descVline','HitTest','off','PickableParts','none');
            % Label POI ROTATE 90 deg CW; fokus tebal, lain normal.
            text(axDst, xs, yTop, [' ' nm], 'Rotation',90, 'Color',col, ...
                'FontSize',7.5, 'FontWeight', i_tern(isFocus,'bold','normal'), ...
                'HorizontalAlignment','right', 'VerticalAlignment','middle', ...
                'BackgroundColor',[1 1 1 0.6], 'Margin',1, 'Clipping','on', ...
                'Tag','descVline');
        end
    end

    % Bersihkan ruler kanan/atas sisa copyobj (YAxisLocation ganda).
    axDst.YAxisLocation = 'left'; axDst.XAxisLocation = 'bottom';

    hold(axDst,'off');
    pivui.grain4Shell.setPotView(fig, 'pot');
end

function xs = i_xmapStrain(xf, nF, strainTot, xstrain)
%I_XMAPSTRAIN  Frame -> cumulative strain % (linear (k-1)/(nF-1)*strainTot).
    if ~xstrain || nF <= 1, xs = xf; return; end
    xs = (xf - 1) / (nF - 1) * strainTot;
end

% =====================================================================
function i_snapMain(fig, axDst, scalar, k, ttl)
%I_SNAPMAIN  AX main STANDAR GRAIN4: render via pivui.grain4Shell.renderMain (label
%   cumulative strain kiri-atas + glyph sp10 + GS + sumbu-cm GRAINAXCAL), lalu
%   SNAPSHOT h.axMain -> axDst + colorbar SOUTHOUTSIDE (tick cm/s utk velmag).
%   ttl = judul kustom (mis '<F#> - <POI> - Velocity Magnitude').
    if nargin < 5, ttl = ''; end
    scKey = 'velocity_magnitude'; isShear = false;
    if strcmp(scalar,'shear'), scKey='shear'; isShear=true; end
    h = guidata(fig);
    kk = max(1, min(round(k), pivcore.data.frameCount(h.data)));
    velMult = i_velMult(h);
    % Set state GRAIN4 lalu render axMain standar.
    h.frame = kk; h.scalarSrc = scKey; h.glyphOn = true; h.glyphSp = 10;
    guidata(fig, h);
    pivui.grain4Shell.renderMain(fig);
    drawnow;
    h = guidata(fig); src = h.axMain;

    % Salin isi axMain (citra+glyph+segitiga+label strain) apa adanya.
    set(axDst,'Color','w','XColor',[0 0 0],'YColor',[0 0 0]);
    copyobj(allchild(src), axDst);
    axDst.YDir = src.YDir;
    axDst.XLim = src.XLim; axDst.YLim = src.YLim;
    % SEMBUNYIKAN tick mark (X & Y) — citra self-descriptive (label strain + cbar).
    set(axDst,'XTick',[],'YTick',[]);
    xlabel(axDst,''); ylabel(axDst,'');
    % daspect [1 1 1] menjaga proporsi; PlotBoxAspectRatio ikut citra supaya axes
    % memenuhi lebar/tinggi Position tanpa distorsi (isi AX main dimaksimalkan).
    daspect(axDst,[1 1 1]); box(axDst,'on'); set(axDst,'Layer','top');
    colormap(axDst, colormap(src)); clim(axDst, clim(src));
    try, delete(findall(axDst,'Type','ColorBar')); catch, end

    % Colorbar SOUTHOUTSIDE.
    cb = colorbar(axDst,'southoutside');
    if isShear
        cb.Label.String = 'shear strain (du/dy+dv/dx)';
    else
        cb.Label.String = '|V| (cm/s)';
        cl = clim(axDst); t = get(cb,'Ticks');
        if isempty(t), t = linspace(cl(1),cl(2),6); set(cb,'Ticks',t); end
        set(cb,'TickLabels', arrayfun(@(v) sprintf('%.3g',v*velMult), t, 'UniformOutput',false));
    end
    set(cb,'Color',[0 0 0]); cb.Label.Color = [0 0 0];
    if isempty(ttl), ttl = sprintf('AX main %s — frame %d', scalar, kk); end
    title(axDst, ttl, 'Interpreter','none','Color',[0 0 0]);
end

% =====================================================================
function rgb = i_poiColorLocal(poi)
%I_POICOLORLOCAL  Salinan i_poiColor GRAIN4 (warna garis vertikal DX per-jenis POI).
    p = upper(strtrim(char(poi)));
    if strcmp(p,'START')||strcmp(p,'END')||strcmp(p,'FS-X'), rgb=[0 0 0];
    elseif strcmp(p,'FS-MAX'), rgb=[0.50 0.10 0.75];
    elseif strcmp(p,'NUC-FSR'),rgb=[0.55 0.35 0.15];
    elseif endsWith(p,'BDF0'), rgb=[0.10 0.35 0.90];
    elseif endsWith(p,'BDF1'), rgb=[0.10 0.65 0.20];
    elseif endsWith(p,'FSR'),  rgb=[0.90 0.10 0.10];
    elseif endsWith(p,'TF'),   rgb=[0.55 0.35 0.15];
    else,                      rgb=[0.10 0.55 0.45];
    end
end

function s = i_tern(c, a, b)
    if c, s = a; else, s = b; end
end

function nm = i_poiAtFrame(dxPoi, frame)
%I_POIATFRAME  Nama POI baris DX pada frame (persis / terdekat). '' bila kosong.
    nm = '';
    if isempty(dxPoi) || ~(isscalar(frame) && isfinite(frame)), return; end
    fr = round(frame); best = inf;
    for i = 1:size(dxPoi,1)
        xf = dxPoi{i,1};
        if ~(isscalar(xf) && isfinite(xf)), continue; end
        d = abs(round(xf) - fr);
        if d < best, best = d; nm = dxPoi{i,2}; end
    end
    if best > 2, nm = ''; end   % tak ada DX dekat frame ini
end

function dx = i_dxPoiForFault(h, ftag)
%I_DXPOIFORFAULT  {frame, poiName} baris DESC GRAIN4 utk F# (garis PSG aktif),
%   POI non-blank saja. Sumber label garis vertikal DX.
    dx = {};
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    want = upper(strtrim(ftag));
    for k = 1:numel(rows)
        r = rows{k};
        fn = upper(strtrim(char(i_g(r,'fNum',''))));
        if ~strcmp(fn, want), continue; end
        poi = strtrim(char(i_g(r,'poi','')));
        if isempty(poi) || strcmpi(poi,'</blank>'), continue; end
        fr = i_g(r,'frame',NaN);
        if isscalar(fr) && isfinite(fr), dx(end+1,:) = {round(fr), poi}; end %#ok<AGROW>
    end
end

function fdoc = i_enableOnly(fdoc, keepId)
%I_ENABLEONLY  Set enabled=false pada SEMUA fault kecuali id==keepId (aktif).
    if ~(isstruct(fdoc) && isfield(fdoc,'faults')), return; end
    for k = 1:numel(fdoc.faults)
        fk = fdoc.faults{k};
        if isstruct(fk) && isfield(fk,'id')
            fk.enabled = strcmp(char(fk.id), char(keepId));
            fdoc.faults{k} = fk;
        end
    end
end

function i_restoreFdoc(fig, fdoc0)
    try, h = guidata(fig); h.fdoc = fdoc0; guidata(fig, h); catch, end
end

function f = i_faultByUiNum(h, num)
    f = [];
    F = pivui.grain5Model.faultsForPsg(h.fdoc, h.activePsgId);
    for k = 1:numel(F)
        fk = F(k); if iscell(F), fk = F{k}; end
        if abs(pivui.grain5Model.faultUiNum(fk) - num) < 0.5, f = fk; return; end
    end
end

function row = i_expRowByBase(h, base)
    row = -1;
    for i = 1:numel(h.list)
        [~, b] = fileparts(h.list(i).file);
        if strcmp(b, base), row = i; return; end
    end
end

function mc = i_indenterMaxCms(h, velMult)
%I_INDENTERMAXCMS  Puncak envelope indenter (px/frame) * velMult -> cm/s.
    mc = NaN;
    try
        env = pivcore.export.frameCatalog.indenterEnvelope(h.recs, h.nF);
        if ~isempty(env), mc = max(env(isfinite(env))) * velMult; end
    catch
    end
    if ~(isscalar(mc) && isfinite(mc) && mc>0), mc = 0.05; end
end

function vm = i_velMult(h)
%I_VELMULT  velMult (cm/s per px/frame) live GRAIN4; fallback 0.005.
    vm = 0.005;
    if isfield(h,'velMult') && isscalar(h.velMult) && h.velMult>0, vm = h.velMult; end
end

function st = i_strainTot(h)
    st = NaN;
    if isfield(h,'axCalR') && isstruct(h.axCalR) && isfield(h.axCalR,'strainTotalPct')
        st = h.axCalR.strainTotalPct;
    end
    if ~(isscalar(st) && isfinite(st))
        try, st = pivcore.export.frameCatalog.readGeom(h.df); catch, st = NaN; end
    end
end

function v = i_g(s, name, def)
    v = def;
    if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), v = s.(name); end
end

function i_closeIf(hh)
    try, if ishghandle(hh), close(hh); end, catch, end
end
