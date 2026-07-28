function capture_gui_docs(force)
%CAPTURE_GUI_DOCS  Luncurkan tiap modul GRAIN dgn data contoh, tangkap jendela GUI
%   ke docs/img/gui_<modul>.png + generate AXPOT/AXPSG dari MAT PIV contoh.
%   Dipakai untuk dokumentasi ALUR_KERJA_V2.html. SELALU R2025b.
%
%   ⚠️ BUKAN TES SENYAP. File ini SENGAJA menampilkan GUI TERLIHAT, me-RAISE
%      jendela ke depan, dan MEMAKSIMALKAN window — jadi MENCURI FOKUS layar.
%      Hanya untuk regenerasi screenshot dokumentasi secara MANUAL.
%      JANGAN masukkan ke suite tes otomatis.
%
%   Jalankan (opt-in wajib):  grain_setup; capture_gui_docs(true)

if nargin < 1 || ~isequal(force,true)
    error('capture_gui_docs:needsForce', ...
        ['GENERATOR SCREENSHOT — akan menampilkan GUI & mencuri fokus layar.\n' ...
         'Jalankan sengaja dengan: capture_gui_docs(true)']);
end

here   = fileparts(mfilename('fullpath'));
grainDir = fileparts(here);
proj   = fileparts(grainDir);
imgDir = fullfile(grainDir,'docs','img');
if ~exist(imgDir,'dir'), mkdir(imgDir); end

rawRoot  = fullfile(proj,'RAW');             % MAT mentah/PREP + PIV_<tgl>
pivDir   = fullfile(rawRoot,'PIV_2026-06-24');% MAT PIV
jpgRoot  = fullfile(proj,'5 cm-1');           % folder JPG mentah (Step 0/1)
matPiv   = fullfile(pivDir,'TKS-5_cm-1-NOVL-S1-111to27-4p20px.mat');

fprintf('imgDir = %s\n', imgDir);

% ---- modul GUI: {nama, fungsi pemanggil} ; arg root dipilih per modul ----
mods = {
  'grain0', @() GRAIN0(jpgRoot)
  'pab1', @() GRAIN1(jpgRoot)
  'pabmask', @() GRAINMASK(rawRoot)
  'grain2', @() GRAIN2(rawRoot)
  'matpivedit', @() MATPIVEDIT(pivDir)
  'grain3', @() GRAIN3(pivDir)
  'grain3a', @() GRAIN3a(pivDir)
  'grain4', @() GRAIN4(pivDir)
  'grainexport', @() GRAINEXPORT(pivDir)
};

for i = 1:size(mods,1)
    nm = mods{i,1}; fn = mods{i,2};
    try
        pre = findall(0,'Type','figure');
        fn();                       % buka GUI
        drawnow; pause(2.5);        % beri waktu auto-load + waitbar selesai
        drawnow; pause(1.5);
        post = findall(0,'Type','figure');
        newF = setdiff(post, pre);
        if isempty(newF), newF = post; end
        % pilih figure terbesar (jendela utama, bukan waitbar)
        f = pickMain(newF);
        if isempty(f) || ~isgraphics(f)
            fprintf('[SKIP] %s: tak ada figure\n', nm); continue;
        end
        try, set(f,'WindowState','maximized'); drawnow; pause(1.0); catch, end
        out = fullfile(imgDir, sprintf('gui_%s.png', nm));
        captureFig(f, out);
        fprintf('[OK]   gui_%s.png\n', nm);
        delete(setdiff(findall(0,'Type','figure'), pre));
        drawnow; pause(0.3);
    catch ME
        fprintf('[ERR]  %s: %s\n', nm, ME.message);
        try, delete(setdiff(findall(0,'Type','figure'), pre)); catch, end
    end
end

% ---- AXPOT & AXPSG: render bersih dari MAT PIV (tanpa GUI) ----
try
    genPotPsg(matPiv, imgDir);
    fprintf('[OK]   example_axpot.png / example_axpsg.png\n');
catch ME
    fprintf('[ERR]  axpot/psg: %s\n', ME.message);
end

fprintf('SELESAI. Cek %s\n', imgDir);
end

% ===================================================================
function f = pickMain(figs)
f = [];
best = -1;
for k = 1:numel(figs)
    g = figs(k);
    if ~isgraphics(g), continue; end
    nm = lower(string(get(g,'Name')));
    if contains(nm,'waitbar') || contains(nm,'tunggu'), continue; end
    p = get(g,'Position'); a = p(3)*p(4);
    if a > best, best = a; f = g; end
end
end

function captureFig(f, out)
figure(f); drawnow; pause(0.4);
% exportapp menangkap SELURUH jendela termasuk uicontrol/panel/tabel/tombol
try
    exportapp(f, out);
catch
    try
        fr = getframe(f);
        imwrite(fr.cdata, out);
    catch
        exportgraphics(f, out, 'Resolution', 110, 'BackgroundColor','white');
    end
end
end

% ===================================================================
function genPotPsg(matPiv, imgDir)
%GENPOTPSG  Bangun dataset dari MAT PIV, garis PSG 75% dari atas, sampel POT,
%   lalu render AXPSG (frame skalar + garis) & AXPOT (kurva |V| sepanjang garis).
S = load(matPiv);
% dataset standar
data = pivcore.data.buildDataset(S);
nF   = data.nFrames;
kMid = max(1, round(nF*0.85));

% citra skalar velmag frame kMid (AXPSG)
x = data.x{kMid}; y = data.y{kMid};
vmag = data.velocity_magnitude{kMid};
if isempty(vmag)
    vmag = sqrt(data.u_smoothed{kMid}.^2 + data.v_smoothed{kMid}.^2);
end
xv = x(1,:); yv = y(:,1);

% garis PSG horizontal 75% dari atas (YDir image)
yL = yv(1) + 0.25*(yv(end)-yv(1));
xA = xv(1); xB = xv(end);

% ---------- AXPSG ----------
f1 = figure('Color','w','Position',[100 100 760 420],'Visible','off');
ax = axes(f1);
pcolor(ax, x, y, vmag); shading(ax,'interp');
set(ax,'YDir','reverse'); axis(ax,'image'); colormap(ax,'turbo');
cb = colorbar(ax); cb.Label.String = '|V| (px/frame)';
hold(ax,'on');
plot(ax,[xA xB],[yL yL],'-','Color',[1 0 0],'LineWidth',2.2);
plot(ax,[xA xB],[yL yL],'o','Color',[1 0 0],'MarkerFaceColor','w','MarkerSize',7);
title(ax, sprintf('AX PSG — garis PSG di atas medan |V| (frame %d/%d)',kMid,nF));
xlabel(ax,'x (px)'); ylabel(ax,'y (px)');
exportgraphics(f1, fullfile(imgDir,'example_axpsg.png'),'Resolution',120,'BackgroundColor','white');
close(f1);

% ---------- AXPOT: |V| sepanjang garis utk beberapa frame ----------
spacing = 4;
np = max(20, round(abs(xB-xA)/spacing));
xs = linspace(xA, xB, np);
ys = yL*ones(1,np);
f2 = figure('Color','w','Position',[100 100 760 420],'Visible','off');
ax2 = axes(f2); hold(ax2,'on'); grid(ax2,'on');
frIdx = round(linspace(1, nF, min(8,nF)));
cmap = turbo(numel(frIdx));
for j = 1:numel(frIdx)
    kk = frIdx(j);
    vmj = data.velocity_magnitude{kk};
    if isempty(vmj)
        vmj = sqrt(data.u_smoothed{kk}.^2 + data.v_smoothed{kk}.^2);
    end
    vq = interp2(data.x{kk}, data.y{kk}, vmj, xs, ys, 'linear', NaN);
    plot(ax2, xs, vq, '-', 'Color', cmap(j,:), 'LineWidth', 1.6, ...
        'DisplayName', sprintf('f%d', frIdx(j)));
end
xlabel(ax2,'posisi sepanjang garis PSG (px)');
ylabel(ax2,'|V| (px/frame)');
title(ax2,'AX POT — profil |V| sepanjang garis PSG, beberapa frame');
legend(ax2,'Location','northeastoutside');
exportgraphics(f2, fullfile(imgDir,'example_axpot.png'),'Resolution',120,'BackgroundColor','white');
close(f2);
end
