function c = robustCLim(Z)
%ROBUSTCLIM  Batas warna kokoh [lo, ~p98] dari bidang skalar, tanpa Statistics
%   TBX. lo = min(0, nilai-min); hi = persentil-98 nilai BERHINGGA. SATU sumber
%   ambang p98 yang sebelumnya disalin di 4 tempat (step1 i_robustCLim,
%   step2 i_autoClimFromFrame ×2 cabang, step1Preview.scalarToRGB).
%
%   Hasil: c = [lo hi]. Bila tak ada nilai berhingga -> [0 1] (pemanggil yang
%   ingin "jangan ubah apa pun" harus jaga sendiri via any(isfinite(Z(:)))).
%
%   Shear SIMETRIS: panggil robustCLim(abs(Z)) lalu pakai c(2) sbg X (CLim
%   [-X X]); karena min(0,·)=0, c=[0 X].
    c = [0 1];
    if isempty(Z) || ~isnumeric(Z), return; end
    zf = Z(isfinite(Z));
    if isempty(zf), return; end
    s  = sort(zf(:));
    lo = min(0, s(1));
    hi = s(max(1, ceil(0.98 * numel(s))));
    if hi <= lo, hi = lo + 1; end
    c = [lo hi];
end
