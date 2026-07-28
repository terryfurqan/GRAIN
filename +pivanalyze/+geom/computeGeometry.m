function g = computeGeometry(X0, X1, Lpos, provenance)
%COMPUTEGEOMETRY  Hitung geometri & strain kumulatif bertanda dari X0/X1/Lpos.
%
%   g = pivanalyze.geom.computeGeometry(X0, X1, Lpos)
%   g = pivanalyze.geom.computeGeometry(X0, X1, Lpos, provenance)
%
%   Konvensi (sama persis dengan PIVlab_automasi_batch_V4):
%       L0 = Lpos - X0;  L1 = Lpos - X1;  dL = L1 - L0 = X0 - X1
%       strain_cumm = dL / L0   (bertanda: dL>0 lengthening, dL<0 shortening)
%
%   X0/X1/Lpos dalam cm; NaN/kosong -> geometri 'incomplete' (valid=false).

    if nargin < 4 || isempty(provenance); provenance = 'pivanalyze_core'; end
    u = pivanalyze.util.utilities;
    X0 = u.scalar(X0); X1 = u.scalar(X1); Lpos = u.scalar(Lpos);

    g = struct('X0_cm', X0, 'X1_cm', X1, 'Lpos_cm', Lpos, ...
        'L0_cm', NaN, 'L1_cm', NaN, 'dL_cm', NaN, ...
        'strain_cumm', NaN, 'strain_cumm_pct', NaN, ...
        'mode', 'none', 'valid', false, ...
        'embedded_by', provenance, ...
        'note', ['L0=Lpos-X0; L1=Lpos-X1; dL=L1-L0=X0-X1; strain_cumm=dL/L0 ' ...
        '(bertanda: dL>0 lengthening, dL<0 shortening).']);

    complete = isfinite(X0) && isfinite(X1) && isfinite(Lpos);
    if ~complete; g.mode = 'incomplete'; return; end

    g.L0_cm = Lpos - X0;
    g.L1_cm = Lpos - X1;
    g.dL_cm = g.L1_cm - g.L0_cm;
    if g.dL_cm > 0
        g.mode = 'lengthening';
    elseif g.dL_cm < 0
        g.mode = 'shortening';
    else
        g.mode = 'none';
    end
    if g.L0_cm ~= 0
        g.strain_cumm     = g.dL_cm / g.L0_cm;
        g.strain_cumm_pct = g.strain_cumm * 100;
    end
    g.valid = isfinite(g.strain_cumm) && g.L0_cm > 0;
end
