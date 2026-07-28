function GRAINfigure(dataDir, outDir)
%GRAINFIGURE  Figur berkualitas publikasi (JGR-style) dari 12 _desc.json sandbox sesar anjak.
%   GRAINfigure                     -> auto-detect DATA JSON FIXED + output ke CLCC/GRAINFIG
%   GRAINfigure(dataDir)            -> tentukan folder data
%   GRAINfigure(dataDir, outDir)    -> tentukan folder data + output
%
%   Engine: MATLAB R2025b (vektor .pdf via exportgraphics + PNG 600 dpi cadangan).
%   Metrik dihitung dari data mentah; netslip/area TIDAK dipakai.
%   Dua skenario: LENGKAP (horizon=nFrames) & BERSIH (horizon=batas_dasar+round(0.07*nFrames)).
%
%   isma@upi.edu — PIV lab @ UPI.

if nargin < 1 || isempty(dataDir)
    here = fileparts(mfilename('fullpath'));
    dataDir = fullfile(here, 'JSON FIX', 'DATA JSON FIXED');
end
if nargin < 2 || isempty(outDir)
    here = fileparts(mfilename('fullpath'));
    outDir = fullfile(here, 'CLCC', 'GRAINFIG');
end
assert(isfolder(dataDir), 'Folder data tidak ada: %s', dataDir);
if ~isfolder(outDir), mkdir(outDir); end

fprintf('=== GRAINfigure ===\n');
fprintf('Engine   : MATLAB %s\n', version('-release'));
fprintf('Data     : %s\n', dataDir);
fprintf('Output   : %s\n\n', outDir);

% ---- Konstanta desain eksperimen ----
GROUPS = {'LF','CON','HF'};                 % urutan wajib LF->CON->HF
% Palet friksi profesional (colorblind-safe): LF teal, CON amber, HF merah-bata.
% NB: parse hex per-komponen (hex2dec), JANGAN 0xAA 0xBB (jadi 1 integer!).
COL = containers.Map( ...
    {'LF','CON','HF'}, ...
    {i_hex('2A9D8F'), i_hex('E9B44C'), i_hex('E15554')});

% frame_batas_dasar per (grup, F#) dari observasi kurva
% baris = F1..F4 ; kolom = CON HF LF
BASE = struct();
BASE.CON = [222 219 187 231];
BASE.HF  = [237 234 242 245];
BASE.LF  = [228 227 225 209];

% ---- 1) Baca semua eksperimen ----
E = i_readAllExperiments(dataDir, GROUPS, BASE);
fprintf('Terbaca %d eksperimen.\n', numel(E));

% ---- 2) Hitung metrik per sesar, dua skenario ----
% M(scenario).faults = tabel gabungan semua sesar (satu baris per sesar per exp)
Mfull  = i_computeMetrics(E, 'full');
Mclean = i_computeMetrics(E, 'clean');

% ---- Gaya MATLAB global ----
i_setStyle();

% ---- 3) Figur ----
i_fig1_dip(outDir, GROUPS, COL, Mfull, Mclean);
i_fig2_slip(outDir, GROUPS, COL, Mfull, Mclean);
i_fig3_life(outDir, GROUPS, COL, Mfull, Mclean);
i_fig4_conc(outDir, GROUPS, COL, E, BASE);
i_fig5_partition(outDir, GROUPS, COL, E);
i_fig6_walldiag(outDir, GROUPS, COL, E);
i_fig7_strip(outDir, GROUPS, COL, Mclean);

% ---- 4) Verifikasi (cetak tabel) ----
i_printVerification(GROUPS, Mfull, Mclean, E);

fprintf('\nSelesai. File di: %s\n', outDir);
end

% ======================================================================
% READER
% ======================================================================
function E = i_readAllExperiments(dataDir, GROUPS, BASE)
E = struct('group',{},'fnum',{},'name',{},'nFrames',{},'strain',{}, ...
           'dxCm',{},'faults',{},'rows',{},'base',{},'horizonClean',{});
for gi = 1:numel(GROUPS)
    g = GROUPS{gi};
    gdir = fullfile(dataDir, g);
    for fexp = 1:4
        % cari file *_desc.json yang mengandung -F-<fexp>-
        pat = fullfile(gdir, sprintf('P-%s-4cm-F-%d-*', g, fexp));
        d = dir(pat);
        d = d([d.isdir]);
        assert(~isempty(d), 'Eksperimen tak ditemukan: %s', pat);
        js = dir(fullfile(gdir, d(1).name, '**', '*_desc.json'));
        assert(~isempty(js), 'JSON tak ada di %s', d(1).name);
        raw = fileread(fullfile(js(1).folder, js(1).name));
        J = jsondecode(raw);

        cal = J.calibration;
        nF = double(cal.nFrames);
        strain = abs(double(J.strainPct(:)'));    % strain kumulatif %, len=nF
        base = BASE.(g)(fexp);
        horizonClean = base + round(0.07 * nF);

        E(end+1) = struct( ...       %#ok<AGROW>
            'group', g, 'fnum', fexp, 'name', d(1).name, ...
            'nFrames', nF, 'strain', strain, 'dxCm', double(cal.dxCm), ...
            'faults', {i_faultsToStruct(J.faults)}, ...
            'rows',   {i_rowsToStruct(J.rows)}, ...
            'base', base, 'horizonClean', horizonClean);
    end
end
end

function F = i_faultsToStruct(faults)
% Normalkan array faults -> struct array {faultNumber, hwVals, fwVals, hwPos, fwPos}
if isstruct(faults), fa = num2cell(faults); else, fa = faults; end
F = struct('faultNumber',{},'hwVals',{},'fwVals',{},'hwPos',{},'fwPos',{});
for i = 1:numel(fa)
    f = fa{i};
    hw = f.hw; fw = f.fw;
    F(end+1) = struct( ...        %#ok<AGROW>
        'faultNumber', double(f.faultNumber), ...
        'hwVals', double(hw.values(:)'), ...
        'fwVals', double(fw.values(:)'), ...
        'hwPos', double(hw.posPx), ...
        'fwPos', double(fw.posPx));
end
end

function R = i_rowsToStruct(rows)
if isstruct(rows), rc = num2cell(rows); else, rc = rows; end
R = struct('fNum',{},'faultNumber',{},'frame',{},'poi',{},'actF',{}, ...
           'angleDeg',{},'nucPos',{},'fsrDir',{},'lenCm',{});
for i = 1:numel(rc)
    r = rc{i};
    fn = r.fNum;                       % "F<n>"
    num = str2double(regexprep(fn,'^F',''));
    ang = NaN; if isfield(r,'angleDeg') && ~isempty(r.angleDeg) && isnumeric(r.angleDeg), ang = double(r.angleDeg); end
    lc  = NaN; if isfield(r,'lenCm')  && ~isempty(r.lenCm)  && isnumeric(r.lenCm),  lc  = double(r.lenCm); end
    af  = 0;   if isfield(r,'actF')   && ~isempty(r.actF)   && isnumeric(r.actF),   af  = double(r.actF); end
    np = ''; if isfield(r,'nucPos') && ischar(r.nucPos), np = r.nucPos; end
    fd = ''; if isfield(r,'fsrDir') && ischar(r.fsrDir), fd = r.fsrDir; end
    R(end+1) = struct( ...             %#ok<AGROW>
        'fNum', fn, 'faultNumber', num, 'frame', double(r.frame), ...
        'poi', r.poi, 'actF', af, 'angleDeg', ang, ...
        'nucPos', np, 'fsrDir', fd, 'lenCm', lc);
end
end

% ======================================================================
% ENGINE METRIK
% ======================================================================
function M = i_computeMetrics(E, scenario)
% Kembalikan struct dg field per-grup berisi array metrik per sesar.
% scenario: 'full' | 'clean'
M = struct();
for gi = 1:numel(E), end %#ok<*NBRAK>
groups = unique({E.group});
for gi = 1:numel(groups)
    g = groups{gi};
    dip=[]; slip=[]; life=[]; nuc=[]; expid={}; fnumArr=[];
    Egr = E(strcmp({E.group}, g));
    for k = 1:numel(Egr)
        ex = Egr(k);
        if strcmp(scenario,'full'), horizon = ex.nFrames; else, horizon = min(ex.horizonClean, ex.nFrames); end
        % kumpulkan faultNumber yg punya baris
        fns = unique([ex.rows.faultNumber]);
        for fn = fns
            rws = ex.rows([ex.rows.faultNumber]==fn);
            % first ACT-FSR frame
            actFrames = [rws(strcmp({rws.poi},'ACT-FSR')).frame];
            nucFrames = [rws(ismember({rws.poi},{'NUC-TF','NUC-FSR','ACT-FSR'})).frame];
            if isempty(nucFrames), continue; end
            firstAct = min([actFrames, nucFrames]);   % awal aktif
            % BERSIH: buang sesar yg first-ACT-FSR >= horizon
            if strcmp(scenario,'clean')
                if isempty(actFrames)
                    firstActFSR = min(nucFrames);
                else
                    firstActFSR = min(actFrames);
                end
                if firstActFSR >= horizon, continue; end
            end
            % dip = median angleDeg ACT-FSR dg frame < horizon
            actRows = rws(strcmp({rws.poi},'ACT-FSR') & [rws.frame] < horizon);
            angs = [actRows.angleDeg]; angs = angs(~isnan(angs));
            if isempty(angs), dipVal = NaN; else, dipVal = median(angs); end

            % slip HW = max abs hw.values[1..horizon]
            fobj = ex.faults([ex.faults.faultNumber]==fn);
            slipVal = NaN;
            if ~isempty(fobj)
                v = fobj(1).hwVals;
                hlim = min(horizon, numel(v));
                slipVal = max(abs(v(1:hlim)));
            end

            % umur-aktif (hanya complete: ada X-FS < horizon)
            xfsFrames = [rws(strcmp({rws.poi},'X-FS') & [rws.frame] < horizon).frame];
            actFSRframes = [rws(strcmp({rws.poi},'ACT-FSR')).frame];
            lifeVal = NaN;
            if ~isempty(xfsFrames) && ~isempty(actFSRframes)
                f0 = min(actFSRframes); f1 = max(xfsFrames);
                if f1 > f0
                    lifeVal = i_strainAt(ex,f1) - i_strainAt(ex,f0);
                end
            end

            % strain nukleasi
            nucVal = i_strainAt(ex, firstAct);

            dip(end+1)=dipVal; slip(end+1)=slipVal; life(end+1)=lifeVal; %#ok<AGROW>
            nuc(end+1)=nucVal; %#ok<AGROW>
            expid{end+1}=sprintf('%s-F%d',g,ex.fnum); %#ok<AGROW>
            fnumArr(end+1)=fn; %#ok<AGROW>
        end
    end
    M.(g) = struct('dip',dip,'slip',slip,'life',life,'nuc',nuc,'exp',{expid},'fnum',fnumArr);
end
end

function s = i_strainAt(ex, frame)
frame = max(1, min(frame, ex.nFrames));
s = ex.strain(frame);
end

% ======================================================================
% GAYA
% ======================================================================
function c = i_hex(h)
% '2A9D8F' -> [r g b] ternormalisasi 0..1 (parse per-komponen, benar).
c = [hex2dec(h(1:2)) hex2dec(h(3:4)) hex2dec(h(5:6))] / 255;
end

function i_setStyle()
% PAKSA TEMA TERANG: latar putih, teks & sumbu hitam.
set(0,'defaultFigureColor','w');
set(0,'defaultAxesColor','w');              % latar dalam axes putih
set(0,'defaultAxesXColor','k');             % sumbu + tick + label X hitam
set(0,'defaultAxesYColor','k');
set(0,'defaultAxesGridColor',[0.80 0.80 0.80]);
set(0,'defaultAxesGridAlpha',0.6);
set(0,'defaultTextColor','k');
set(0,'defaultAxesFontName','Helvetica');
set(0,'defaultTextFontName','Helvetica');
set(0,'defaultAxesFontSize',10);
set(0,'defaultAxesBox','on');
set(0,'defaultAxesLineWidth',1);
set(0,'defaultAxesTickDir','in');
set(0,'defaultAxesXGrid','on');
set(0,'defaultAxesYGrid','on');
set(0,'defaultLegendTextColor','k');
set(0,'defaultLegendColor','w');
end

function i_lightenAxes(fig)
% Pastikan setiap axes/teks di fig bertema terang (jaga2 dari default OS gelap).
set(findall(fig,'Type','axes'), 'Color','w','XColor','k','YColor','k', ...
    'GridColor',[0.80 0.80 0.80]);
set(findall(fig,'Type','text'), 'Color','k');
set(findall(fig,'Type','legend'), 'TextColor','k','Color','w','EdgeColor','k');
end

function i_export(fig, outDir, name)
% PDF vektor (utama) + PNG 600 dpi (cadangan) + .fig
i_lightenAxes(fig);                          % jaga tema terang tepat sebelum render
set(fig,'Color','w','InvertHardcopy','off'); % jangan biarkan MATLAB timpa warna latar
pdf = fullfile(outDir, [name '.pdf']);
png = fullfile(outDir, [name '.png']);
exportgraphics(fig, pdf, 'ContentType','vector','BackgroundColor','white');
exportgraphics(fig, png, 'Resolution',600,'BackgroundColor','white');
try, savefig(fig, fullfile(outDir,[name '.fig'])); catch, end
fprintf('  -> %s (.pdf/.png)\n', name);
close(fig);
end

function i_jitterPts(ax, xc, y, c)
% titik per-sesar dg jitter horizontal + mean +/- SD
y = y(~isnan(y));
if isempty(y), return; end
n = numel(y);
jit = (linspace(-1,1,n)) * 0.11;         % deterministik (bukan rand -> reproducible)
scatter(ax, xc+jit, y, 26, 'MarkerFaceColor', c*0.75, ...
    'MarkerEdgeColor','w','MarkerFaceAlpha',0.9,'LineWidth',0.5);
m = mean(y); sd = std(y);
errorbar(ax, xc, m, sd, 'k', 'LineWidth',1.4,'CapSize',9,'Marker','none');
plot(ax, [xc-0.2 xc+0.2],[m m],'k-','LineWidth',1.8);
end

% ======================================================================
% FIGUR 1 — Dip vs friksi (2 skenario)
% ======================================================================
function i_fig1_dip(outDir, G, COL, Mf, Mc)
fig = figure('Units','centimeters','Position',[2 2 12 8.5]);
ax = axes(fig); hold(ax,'on');
w = 0.34; xg = 1:numel(G);
for i = 1:numel(G)
    g = G{i}; c = COL(g);
    yf = Mf.(g).dip; yc = Mc.(g).dip;
    mf = mean(yf(~isnan(yf))); mc = mean(yc(~isnan(yc)));
    % Lengkap = solid ; Bersih = hatch/transparan
    b1 = bar(ax, i-w/2-0.02, mf, w, 'FaceColor', c, 'EdgeColor','k','LineWidth',1); %#ok<NASGU>
    b2 = bar(ax, i+w/2+0.02, mc, w, 'FaceColor', c, 'FaceAlpha',0.30, ...
             'EdgeColor','k','LineWidth',1);
    try, b2.LineStyle='--'; catch, end
    i_jitterPts(ax, i-w/2-0.02, yf, c);
    i_jitterPts(ax, i+w/2+0.02, yc, c);
end
set(ax,'XTick',xg,'XTickLabel',G);
xlim(ax,[0.4 numel(G)+0.6]);
ylabel(ax,'Fault dip (\circ)'); xlabel(ax,'Basal friction');
title(ax,'Fig 1 \cdot Fault dip vs basal friction');
i_scenLegend(ax);
text(ax,0.02,0.03,'Full: apparent monotonic rise. Clean: LF steep vs CON\approxHF (scenario-sensitive).', ...
    'Units','normalized','FontSize',7.5,'Color',[0.3 0.3 0.3],'VerticalAlignment','bottom');
i_export(fig,outDir,'Fig1_dip_vs_friction');
end

% ======================================================================
% FIGUR 2 — Slip HW vs friksi
% ======================================================================
function i_fig2_slip(outDir, G, COL, Mf, Mc)
fig = figure('Units','centimeters','Position',[2 2 12 8.5]);
ax = axes(fig); hold(ax,'on'); w=0.34;
for i=1:numel(G)
    g=G{i}; c=COL(g);
    yf=Mf.(g).slip; yc=Mc.(g).slip;
    bar(ax,i-w/2-0.02,mean(yf(~isnan(yf))),w,'FaceColor',c,'EdgeColor','k','LineWidth',1);
    b2=bar(ax,i+w/2+0.02,mean(yc(~isnan(yc))),w,'FaceColor',c,'FaceAlpha',0.30,'EdgeColor','k','LineWidth',1);
    try, b2.LineStyle='--'; catch, end
    i_jitterPts(ax,i-w/2-0.02,yf,c);
    i_jitterPts(ax,i+w/2+0.02,yc,c);
end
set(ax,'XTick',1:numel(G),'XTickLabel',G); xlim(ax,[0.4 numel(G)+0.6]);
ylabel(ax,'Integrated HW slip (cm)'); xlabel(ax,'Basal friction');
title(ax,'Fig 2 \cdot HW slip vs basal friction');
i_scenLegend(ax);
text(ax,0.02,0.03,'Increases with friction in BOTH scenarios (robust).', ...
    'Units','normalized','FontSize',7.5,'Color',[0.3 0.3 0.3],'VerticalAlignment','bottom');
i_export(fig,outDir,'Fig2_HWslip_vs_friction');
end

% ======================================================================
% FIGUR 3 — Umur-aktif vs friksi
% ======================================================================
function i_fig3_life(outDir, G, COL, Mf, Mc)
fig = figure('Units','centimeters','Position',[2 2 12 8.5]);
ax = axes(fig); hold(ax,'on'); w=0.34;
for i=1:numel(G)
    g=G{i}; c=COL(g);
    yf=Mf.(g).life; yc=Mc.(g).life;
    bar(ax,i-w/2-0.02,mean(yf(~isnan(yf))),w,'FaceColor',c,'EdgeColor','k','LineWidth',1);
    b2=bar(ax,i+w/2+0.02,mean(yc(~isnan(yc))),w,'FaceColor',c,'FaceAlpha',0.30,'EdgeColor','k','LineWidth',1);
    try, b2.LineStyle='--'; catch, end
    i_jitterPts(ax,i-w/2-0.02,yf,c);
    i_jitterPts(ax,i+w/2+0.02,yc,c);
end
set(ax,'XTick',1:numel(G),'XTickLabel',G); xlim(ax,[0.4 numel(G)+0.6]);
ylabel(ax,'Active lifespan (\Delta strain %)'); xlabel(ax,'Basal friction');
title(ax,'Fig 3 \cdot Fault active lifespan vs basal friction');
i_scenLegend(ax);
text(ax,0.02,0.03,'Scenario-sensitive (cleaning changes the pattern).', ...
    'Units','normalized','FontSize',7.5,'Color',[0.3 0.3 0.3],'VerticalAlignment','bottom');
i_export(fig,outDir,'Fig3_lifespan_vs_friction');
end

% ======================================================================
% FIGUR 4 — Konkurensi actF>=3 (laju/100 event)
% ======================================================================
function i_fig4_conc(outDir, G, COL, E, BASE)
fig = figure('Units','centimeters','Position',[2 2 12 8.5]);
ax = axes(fig); hold(ax,'on'); w=0.34;
rateF = struct(); rateC = struct();
for i=1:numel(G)
    g=G{i}; c=COL(g);
    Egr = E(strcmp({E.group},g));
    rf=[]; rc=[];
    for k=1:numel(Egr)
        ex=Egr(k);
        % FULL
        rf(end+1)=i_concRate(ex, ex.nFrames); %#ok<AGROW>
        % CLEAN
        rc(end+1)=i_concRate(ex, min(ex.horizonClean,ex.nFrames)); %#ok<AGROW>
    end
    rateF.(g)=rf; rateC.(g)=rc;
    bar(ax,i-w/2-0.02,mean(rf),w,'FaceColor',c,'EdgeColor','k','LineWidth',1);
    b2=bar(ax,i+w/2+0.02,mean(rc),w,'FaceColor',c,'FaceAlpha',0.30,'EdgeColor','k','LineWidth',1);
    try, b2.LineStyle='--'; catch, end
    i_jitterPts(ax,i-w/2-0.02,rf,c);
    i_jitterPts(ax,i+w/2+0.02,rc,c);
end
set(ax,'XTick',1:numel(G),'XTickLabel',G); xlim(ax,[0.4 numel(G)+0.6]);
ylabel(ax,'Concurrency actF\geq3 (per 100 POI events)'); xlabel(ax,'Basal friction');
title(ax,'Fig 4 \cdot Fault concurrency vs basal friction');
i_scenLegend(ax);
text(ax,0.02,0.97,'HF \sim3\times CON, LF\approx0 (robust).', ...
    'Units','normalized','FontSize',7.5,'Color',[0.3 0.3 0.3],'VerticalAlignment','top');
% keep for verification
assignin('base','GRAINFIG_conc_full',rateF);
assignin('base','GRAINFIG_conc_clean',rateC);
i_export(fig,outDir,'Fig4_concurrency_vs_friction');
end

function r = i_concRate(ex, horizon)
fr = [ex.rows.frame];
sel = fr < horizon;
rws = ex.rows(sel);
if isempty(rws), r=0; return; end
n3 = sum([rws.actF] >= 3);
r = 100 * n3 / numel(rws);
end

% ======================================================================
% FIGUR 5 — Partisi kecepatan HW/FW sepanjang umur ternormalisasi
% ======================================================================
function i_fig5_partition(outDir, G, COL, E)
fig = figure('Units','centimeters','Position',[2 2 18 6.8]);
tl = tiledlayout(fig,1,numel(G),'TileSpacing','compact','Padding','compact');
title(tl,'Fig 5 \cdot HW/FW velocity partitioning along fault lifespan', ...
    'FontWeight','bold','FontSize',11,'Color','k');
xn = linspace(0,1,20);
for i=1:numel(G)
    g=G{i}; c=COL(g);
    Egr = E(strcmp({E.group},g));
    VH=[]; VF=[];
    for k=1:numel(Egr)
        ex=Egr(k);
        horizon = ex.nFrames;   % partisi pakai jendela aktif tiap sesar (bukan cleaning)
        fns=unique([ex.rows.faultNumber]);
        for fn=fns
            rws=ex.rows([ex.rows.faultNumber]==fn);
            a=[rws(strcmp({rws.poi},'ACT-FSR')).frame];
            x=[rws(strcmp({rws.poi},'X-FS')).frame];
            if isempty(a)||isempty(x), continue; end
            f0=min(a); f1=max(x);
            if f1-f0 < 6, continue; end
            fobj=ex.faults([ex.faults.faultNumber]==fn);
            if isempty(fobj), continue; end
            hv=fobj(1).hwVals; fv=fobj(1).fwVals;
            f1=min(f1,min(numel(hv),numel(fv)));
            if f1-f0<6, continue; end
            seg=f0:f1;
            vh=abs(i_ma(diff(hv(seg)),7));
            vf=abs(i_ma(diff(fv(seg)),7));
            tt=linspace(0,1,numel(vh));
            VH(end+1,:)=interp1(tt,vh,xn,'linear','extrap'); %#ok<AGROW>
            VF(end+1,:)=interp1(linspace(0,1,numel(vf)),vf,xn,'linear','extrap'); %#ok<AGROW>
        end
    end
    ax=nexttile(tl); hold(ax,'on');
    if ~isempty(VH)
        mh=mean(VH,1,'omitnan'); mf=mean(VF,1,'omitnan');
        ph=plot(ax,xn,mh,'-','Color',c,'LineWidth',2);
        pf=plot(ax,xn,mf,'--','Color',c*0.55,'LineWidth',2);
        % crossover
        dsig=sign(mh-mf); idx=find(dsig(1:end-1)>0 & dsig(2:end)<=0,1);
        if ~isempty(idx)
            xc=xn(idx); xline(ax,xc,':','Color',[0.35 0.35 0.35],'LineWidth',1.2);
        end
        if i==1, legend(ax,[ph pf],{'|v_{HW}|','|v_{FW}|'},'Location','northeast','Box','on'); end
    end
    title(ax,g); xlabel(ax,'Normalized lifespan'); if i==1, ylabel(ax,'|v| (cm/frame)'); end
    xlim(ax,[0 1]);
end
i_export(fig,outDir,'Fig5_HWFW_partitioning');
end

function y = i_ma(x,w)
if numel(x)<2, y=x; return; end
y = movmean(x, w);
end

% ======================================================================
% FIGUR 6 — Diagnostik dinding: dip vs posisi foreland
% ======================================================================
function i_fig6_walldiag(outDir, G, COL, E)
fig = figure('Units','centimeters','Position',[2 2 18 7]);
tl = tiledlayout(fig,1,numel(G),'TileSpacing','compact','Padding','compact');
title(tl,'Fig 6 \cdot Wall-effect diagnostic: fault dip vs foreland position', ...
    'FontWeight','bold','FontSize',11,'Color','k');
for i=1:numel(G)
    g=G{i}; c=COL(g);
    Egr=E(strcmp({E.group},g));
    ax=nexttile(tl); hold(ax,'on');
    for k=1:numel(Egr)
        ex=Egr(k); px=[]; dp=[];
        fns=unique([ex.rows.faultNumber]);
        for fn=fns
            rws=ex.rows([ex.rows.faultNumber]==fn);
            ar=rws(strcmp({rws.poi},'ACT-FSR'));
            angs=[ar.angleDeg]; angs=angs(~isnan(angs));
            fobj=ex.faults([ex.faults.faultNumber]==fn);
            if isempty(angs)||isempty(fobj), continue; end
            px(end+1)=fobj(1).fwPos; dp(end+1)=median(angs); %#ok<AGROW>
        end
        [px,ord]=sort(px); dp=dp(ord);
        plot(ax,px,dp,'-o','Color',c,'MarkerFaceColor',c,'MarkerEdgeColor','w', ...
            'LineWidth',1.2,'MarkerSize',5);
    end
    title(ax,g); xlabel(ax,'Foreland position fw.posPx (px)');
    if i==1, ylabel(ax,'Fault dip (\circ)'); end
end
text(tl.Children(end),0.5,-0.28,'Dip cliff at the leading (near-wall) faults \rightarrow justifies cleaning.', ...
    'Units','normalized','FontSize',7.5,'Color',[0.3 0.3 0.3],'HorizontalAlignment','left');
i_export(fig,outDir,'Fig6_wall_diagnostic');
end

% ======================================================================
% FIGUR 7 — Strip plot per-eksperimen (kejujuran n=4)
% ======================================================================
function i_fig7_strip(outDir, G, COL, Mc)
fig = figure('Units','centimeters','Position',[2 2 18 6.8]);
tl = tiledlayout(fig,1,3,'TileSpacing','compact','Padding','compact');
title(tl,'Fig 7 \cdot Between-replicate scatter (CLEAN scenario)', ...
    'FontWeight','bold','FontSize',11,'Color','k');
metrics = {'dip','Dip (\circ)'; 'slip','HW slip (cm)'; 'life','Active lifespan (\Delta%)'};
for mi=1:3
    ax=nexttile(tl); hold(ax,'on');
    key=metrics{mi,1};
    for i=1:numel(G)
        g=G{i}; c=COL(g);
        y=Mc.(g).(key); y=y(~isnan(y));
        jit=(linspace(-1,1,max(numel(y),1)))*0.12;
        scatter(ax,i+jit,y,24,'MarkerFaceColor',c*0.8,'MarkerEdgeColor','w', ...
            'MarkerFaceAlpha',0.85,'LineWidth',0.4);
        if ~isempty(y)
            plot(ax,[i-0.22 i+0.22],[mean(y) mean(y)],'k-','LineWidth',1.6);
        end
    end
    set(ax,'XTick',1:numel(G),'XTickLabel',G); xlim(ax,[0.4 3.6]);
    title(ax,metrics{mi,2}); xlabel(ax,'Friction');
end
i_export(fig,outDir,'Fig7_replicate_scatter');
end

% ======================================================================
% HELPER GAYA
% ======================================================================
function i_scenLegend(ax)
% small Full vs Clean legend (neutral grey) at top-right
h1 = patch(ax,'XData',NaN,'YData',NaN,'FaceColor',[0.55 0.55 0.55],'EdgeColor','k');
h2 = patch(ax,'XData',NaN,'YData',NaN,'FaceColor',[0.55 0.55 0.55],'FaceAlpha',0.30, ...
    'EdgeColor','k','LineStyle','--');
legend(ax,[h1 h2],{'Full','Clean'},'Location','northeast','Box','on','FontSize',8);
end

% ======================================================================
% VERIFIKASI
% ======================================================================
function i_printVerification(G, Mf, Mc, E)
fprintf('\n================= TABEL VERIFIKASI (angka yang diplot) =================\n');
fprintf('Engine: MATLAB %s | netslip/area TIDAK dipakai | slip=max|hw.values|\n\n', version('-release'));
mets = {'dip','Dip (deg)'; 'slip','Slip HW (cm)'; 'life','Umur-aktif (dStrain %)'; 'nuc','Strain nukleasi (%)'};
for mi=1:size(mets,1)
    key=mets{mi,1};
    fprintf('--- %s ---\n', mets{mi,2});
    fprintf('%5s | %-28s | %-28s\n','grup','LENGKAP (mean+/-SD, n)','BERSIH (mean+/-SD, n)');
    for i=1:numel(G)
        g=G{i};
        yf=Mf.(g).(key); yf=yf(~isnan(yf));
        yc=Mc.(g).(key); yc=yc(~isnan(yc));
        fprintf('%5s | %7.2f +/- %5.2f (n=%2d)     | %7.2f +/- %5.2f (n=%2d)\n', ...
            g, mean0(yf),std0(yf),numel(yf), mean0(yc),std0(yc),numel(yc));
    end
    fprintf('\n');
end
% jumlah sesar per grup/skenario
fprintf('--- Jumlah sesar (dip valid) per grup/skenario ---\n');
for i=1:numel(G)
    g=G{i};
    nf=sum(~isnan(Mf.(g).dip)); nc=sum(~isnan(Mc.(g).dip));
    fprintf('%5s : LENGKAP n=%2d | BERSIH n=%2d\n', g, nf, nc);
end
fprintf('\nCatatan: n=3 tingkat friksi -> disajikan sebagai perbandingan grup, TANPA garis regresi/tren.\n');
fprintf('=======================================================================\n');
end

function m=mean0(x), if isempty(x), m=NaN; else, m=mean(x); end, end
function s=std0(x), if numel(x)<2, s=0; else, s=std(x); end, end
