function PAB_step_0(varargin)
%PAB_STEP_0  Forwarder transisi -> PAB1 (ROI jitter, kini "Step 1").
%   Dulu PAB_step_0 = tool ROI jitter (= PAB0 lama). Tool itu kini PAB1
%   ("true Step 1"); "true PAB0" kini Step 0 QPIV exclusion. Nama lama
%   dipertahankan sementara agar pemanggil belum-pindah tak patah. Hapus Fase 7.
PAB1(varargin{:});
end
