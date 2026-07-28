function gen_output_examples()
%GEN_OUTPUT_EXAMPLES  Render AX PSG dari MAT PIV P-CON-4cm-F-1.
%   velmag/shear pakai keluaran PABEXPORT asli; AX POT pakai _axpot.jpg asli.
%   pab_setup; gen_output_examples

here   = fileparts(mfilename('fullpath'));
pabDir = fileparts(here);
imgDir = fullfile(pabDir,'docs','img');

matPiv = '/Users/terryfurqan/MACTERR_shared/EXP_coll/P-CON-4cm-F/P-CON-4cm-F-1-OVL-S0-349to348-3p25px.mat';
fprintf('Memuat %s ...\n', matPiv);
S = load(matPiv);
data = pivcore.data.buildDataset(S);
nF   = data.nFrames;
k    = max(1, round(nF*0.85));
fprintf('nF=%d, frame contoh=%d\n', nF, k);

x = data.x{k}; y = data.y{k};
vmag = data.velocity_magnitude{k};
if isempty(vmag), vmag = sqrt(data.u_smoothed{k}.^2 + data.v_smoothed{k}.^2); end
xv = x(1,:); yv = y(:,1);
yL = yv(1) + 0.25*(yv(end)-yv(1));

f1 = figure('Color','w','Position',[80 80 1200 380],'Visible','off');
ax = axes(f1);
pcolor(ax,x,y,vmag); shading(ax,'interp'); set(ax,'YDir','reverse');
axis(ax,'image'); colormap(ax,'turbo');
cb=colorbar(ax); cb.Label.String='|V| (px/frame)';
hold(ax,'on');
plot(ax,[xv(1) xv(end)],[yL yL],'-','Color',[1 0 0],'LineWidth',2.6);
plot(ax,[xv(1) xv(end)],[yL yL],'o','Color',[1 0 0],'MarkerFaceColor','w','MarkerSize',8);
title(ax,sprintf('AX PSG — garis PSG di atas medan |V| (P-CON-4cm-F-1, frame %d/%d)',k,nF),'Color','k');
xlabel(ax,'x (px)','Color','k'); ylabel(ax,'y (px)','Color','k');
set(ax,'XColor','k','YColor','k','FontSize',12);
exportgraphics(f1,fullfile(imgDir,'example_axpsg.png'),'Resolution',140,'BackgroundColor','white');
close(f1);
fprintf('SELESAI: example_axpsg.png\n');
end
