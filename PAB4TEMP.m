function figOut = PAB4TEMP(varargin)
%PAB4TEMP  Pintu masuk UJI untuk PAB4 versi TEROPTIMASI (percepatan ekspor:
%   Commit + Report). Forwarder tipis ke PAB4 — SEMUA logika + optimasi ada di
%   PAB4.m + shell bersama (pivui.pab4Shell), jadi tak ada duplikasi.
%
%   Kenapa ada file ini: supaya Anda bisa MEMBUKA PAB4TEMP untuk menguji
%   percepatan ekspor sambil tetap memakai PAB4 seperti biasa. Karena optimasi
%   berada di shell BERSAMA, PAB4 & PAB4TEMP berperilaku sama (byte-identik,
%   sudah lolos regresi PAB4/5/6). File ini murni penanda + judul window.
%
%   TIDAK PUAS / MAU BALIK KE VERSI LAMA:
%     zsh PAB/_bak_optim/RESTORE_LAMA.sh   (kembalikan 5 file pra-optimasi)
%     lalu hapus PAB4TEMP.m bila mau.
%
%   Selalu MATLAB R2025b.
    fig = PAB4(varargin{:});
    try
        set(fig, 'Name', [get(fig,'Name') '  ⚡[TEMP: ekspor cepat]']);
    catch
    end
    if nargout > 0, figOut = fig; end
end
