function figOut = GRAIN4TEMP(varargin)
%GRAIN4TEMP  Pintu masuk UJI untuk GRAIN4 versi TEROPTIMASI (percepatan ekspor:
%   Commit + Report). Forwarder tipis ke GRAIN4 — SEMUA logika + optimasi ada di
%   GRAIN4.m + shell bersama (pivui.grain4Shell), jadi tak ada duplikasi.
%
%   Kenapa ada file ini: supaya Anda bisa MEMBUKA GRAIN4TEMP untuk menguji
%   percepatan ekspor sambil tetap memakai GRAIN4 seperti biasa. Karena optimasi
%   berada di shell BERSAMA, GRAIN4 & GRAIN4TEMP berperilaku sama (byte-identik,
%   sudah lolos regresi GRAIN4/5/6). File ini murni penanda + judul window.
%
%   TIDAK PUAS / MAU BALIK KE VERSI LAMA:
%     zsh GRAIN/_bak_optim/RESTORE_LAMA.sh   (kembalikan 5 file pra-optimasi)
%     lalu hapus GRAIN4TEMP.m bila mau.
%
%   Selalu MATLAB R2025b.
    fig = GRAIN4(varargin{:});
    try
        set(fig, 'Name', [get(fig,'Name') '  ⚡[TEMP: ekspor cepat]']);
    catch
    end
    if nargout > 0, figOut = fig; end
end
