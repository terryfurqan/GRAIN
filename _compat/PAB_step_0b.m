function PAB_step_0b(varargin)
%PAB_STEP_0B  Forwarder transisi -> PAB0 (lihat RENAME_PLAN.md, Fase 3).
%   Nama lama dipertahankan sementara agar pemanggil belum-pindah tak patah.
%   Tool Step 0 (QPIV exclusion) kini ada di PAB0 (true PAB0).
%   Hapus setelah semua pemanggil memakai PAB0 (Fase 7).
PAB0(varargin{:});
end
