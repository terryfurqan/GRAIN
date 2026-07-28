function cmap = velColormap(n)
%VELCOLORMAP  Colormap untuk Velocity magnitude = JET (default proyek PAB_SA).
%   cmap = pivcore.util.velColormap(n)
%
%   SATU sumber kebenaran colormap velocity dipakai GUI (PAB_step_3) & montase
%   (pivcore.montage.buildMontage) supaya konsisten. JET (BUKAN parula/turbo)
%   atas permintaan eksplisit. Fallback aman bila jet() tak ada.
    if nargin < 1 || ~isfinite(n) || n < 2, n = 256; end
    n = round(n);
    % Cache kasus paling umum (n==256): fungsi deterministik, hemat rebuild
    % tiap panel saat ekspor. Kasus n lain dihitung normal (tanpa cache).
    persistent C256
    if n == 256 && ~isempty(C256), cmap = C256; return; end
    if exist('jet','file') ~= 0
        cmap = jet(n);
    else
        % Fallback manual JET (biru->cyan->kuning->merah) bila jet() absen.
        base = [0 0 0.5; 0 0 1; 0 1 1; 1 1 0; 1 0 0; 0.5 0 0];
        t  = linspace(0,1,size(base,1));
        tq = linspace(0,1,n);
        cmap = [interp1(t,base(:,1),tq)', ...
                interp1(t,base(:,2),tq)', ...
                interp1(t,base(:,3),tq)'];
    end
    if n == 256, C256 = cmap; end
end
