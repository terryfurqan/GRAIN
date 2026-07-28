function PAB_step_0(varargin)
%GRAIN_STEP_0  Forwarder transisi -> GRAIN1 (ROI jitter, kini "Step 1").
%   Dulu PAB_step_0 = tool ROI jitter (= GRAIN0 lama). Tool itu kini GRAIN1
%   ("true Step 1"); "true GRAIN0" kini Step 0 QPIV exclusion. Nama lama
%   dipertahankan sementara agar pemanggil belum-pindah tak patah. Hapus Fase 7.
GRAIN1(varargin{:});
end
