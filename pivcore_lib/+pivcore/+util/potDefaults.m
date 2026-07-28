function d = potDefaults()
%POTDEFAULTS  Default POT/PSG untuk GUI pratinjau (GRAINSA3/3a).
%   d.psgFrac : fraksi tinggi garis PSG auto (0=atas, 1=bawah)   0.75
%   d.gsAlpha : alpha overlay GS di atas skalar                   0.30
%   SATU sumber konstanta — sebelumnya di-hardcode (psgFrac/gsAlpha) di init &
%   fallback GRAINSA3/3a + string edit-box.
    d = struct('psgFrac', 0.75, 'gsAlpha', 0.30);
end
