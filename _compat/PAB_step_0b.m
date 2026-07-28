function PAB_step_0b(varargin)
%GRAIN_STEP_0B  Forwarder transisi -> GRAIN0 (lihat RENAME_PLAN.md, Fase 3).
%   Nama lama dipertahankan sementara agar pemanggil belum-pindah tak patah.
%   Tool Step 0 (QPIV exclusion) kini ada di GRAIN0 (true GRAIN0).
%   Hapus setelah semua pemanggil memakai GRAIN0 (Fase 7).
GRAIN0(varargin{:});
end
