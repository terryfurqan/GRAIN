function d = climDefaults()
%CLIMDEFAULTS  Default rentang/colormap warna untuk axMain GUI PIV.
%   d.velCLim   : [min max] awal Vel mag                 [0 5]
%   d.shearAbs  : batas |shear| awal (±)                 0.05
%   d.snapStep  : kelipatan pembulatan KE ATAS batas vel 0.5  (lihat snapClim)
%   d.cmapN     : jumlah level colormap                  256
%   d.shearMode : mode regangan shear                    'engineering'
%   SATU sumber konstanta render — sebelumnya di-hardcode di GRAINSA3/3a init.
    d = struct('velCLim', [0 5], 'shearAbs', 0.05, 'snapStep', 0.5, ...
               'cmapN', 256, 'shearMode', 'engineering');
end
