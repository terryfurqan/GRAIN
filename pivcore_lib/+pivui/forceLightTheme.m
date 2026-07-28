function forceLightTheme(figH)
%FORCELIGHTTHEME  Paksa SEBUAH jendela (figure/waitbar/dialog) ke tema TERANG,
%   abaikan dark-mode OS — supaya axes/teks/tombol/popup/uitable selalu hitam-
%   di-putih. theme() = API R2025a+; set('Theme','light') fallback rilis lama.
%   Aman utk handle kosong/invalid (no-op).
%
%   SATU sumber kebenaran untuk seri GUI standalone PIVTerry (step1/step2/…) —
%   sebelumnya disalin sebagai i_forceLightTheme di tiap berkas.
    if isempty(figH) || ~ishghandle(figH), return; end
    try
        theme(figH,'light');
    catch
        try
            set(figH,'Theme','light');
        catch
        end
    end
end
