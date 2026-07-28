function PAB_step_3(varargin)
%GRAIN_STEP_3  Forwarder transisi -> GRAIN3 (lihat RENAME_PLAN.md, Fase 5).
%   Nama lama dipertahankan sementara agar pemanggil belum-pindah tak patah.
%   Hapus setelah semua pemanggil memakai GRAIN3 (Fase 7).
GRAIN3(varargin{:});
end
