function PAB_step_1(varargin)
%GRAIN_STEP_1  Forwarder transisi -> PAB1_old (GUI BatchPIVPrep2 = produksi .mat).
%   Dulu PAB_step_1 = GUI BatchPIVPrep2 (= GRAIN1 lama). Kini tool itu PAB1_old
%   (_compat); "true GRAIN1" jadi tool ROI jitter. Nama lama dipertahankan
%   sementara agar pemanggil belum-pindah tak patah. Hapus pada Fase 7.
PAB1_old(varargin{:});
end
