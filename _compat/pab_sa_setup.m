function varargout = pab_sa_setup(varargin)
%PAB_SA_SETUP  Legacy alias -> grain_setup.
%   Nama lama dipertahankan agar pemanggil belum-pindah tak patah.
%   Meneruskan argumen & semua output.
[varargout{1:nargout}] = grain_setup(varargin{:});
end
