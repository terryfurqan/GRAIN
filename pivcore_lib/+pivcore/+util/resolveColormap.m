function cmap = resolveColormap(name, n)
%RESOLVECOLORMAP  Konversi nama colormap ke matriks n x 3.
%   Port dari i_resolveColormap (PIV_Viewer.m baris 1984-1999).

    switch lower(name)
        case 'parula',  cmap = parula(n);
        case 'jet',     cmap = jet(n);
        case 'hsv',     cmap = hsv(n);
        case 'turbo'
            try
                cmap = turbo(n);
            catch
                cmap = pivcore.util.turboFallback(n);
            end
        case 'hot',     cmap = hot(n);
        case 'cool',    cmap = cool(n);
        case 'gray',    cmap = gray(n);
        otherwise,      cmap = parula(n);
    end
end
