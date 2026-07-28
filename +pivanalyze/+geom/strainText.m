function [txt, cat] = strainText(X0, X1, Lpos)
%STRAINTEXT  Label strain ringkas untuk GUI (isi cepat geometri).
%
%   [txt, cat] = pivanalyze.geom.strainText(X0, X1, Lpos)
%
%   txt : string strain persen bertanda (mis. '+3.21'), '' bila tak lengkap,
%         'L0≤0!' bila L0 tak valid.
%   cat : 'lengthening' | 'shortening' | 'none' | 'badL0' | ''.
%
%   Salinan persis subfungsi strainText dari PIVlab_automasi_batch_GUI_V4.

    txt = ''; cat = '';
    if isempty(X0) || isempty(X1) || isempty(Lpos) || isnan(X0) || isnan(X1) || isnan(Lpos)
        return;
    end
    L0 = Lpos - X0;
    dL = (Lpos - X1) - L0;
    if L0 <= 0; txt = 'L0≤0!'; cat = 'badL0'; return; end   % fidelitas V4 (Unicode ≤)
    strainPct = dL / L0 * 100;
    txt = sprintf('%+.2f', strainPct);
    if dL > 0; cat = 'lengthening'; elseif dL < 0; cat = 'shortening'; else; cat = 'none'; end
end
