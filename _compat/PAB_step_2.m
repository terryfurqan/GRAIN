function PAB_step_2(varargin)
%GRAIN_STEP_2  Forwarder transisi -> GRAIN2 (lihat RENAME_PLAN.md, Fase 4).
%   Nama lama dipertahankan sementara agar pemanggil belum-pindah tak patah.
%   Hapus setelah semua pemanggil memakai GRAIN2 (Fase 7).
GRAIN2(varargin{:});
end
