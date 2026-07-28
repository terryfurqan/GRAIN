classdef pab5Palette
%PAB5PALETTE  Palet warna zona/area sesar PAB5 (Tab ① Sesar) — fungsi MURNI
%   (tak menyentuh GUI/guidata; hanya membaca state `h.zonePalette`/`h.zoneAlpha`).
%   Diekstrak dari PAB5.m (Fase 3a) agar file entry ramping & palet dipakai-ulang.
%
%   API:
%     c = pivui.pab5Palette.pastelPalette()      % cell warna pastel (lembut)
%     c = pivui.pab5Palette.vividPalette()       % cell warna ngejreng (jenuh)
%     c = pivui.pab5Palette.zonePalette(h)        % pilih per h.zonePalette
%     a = pivui.pab5Palette.zoneAlpha(h)          % transparansi fill (0.02..0.95)
%     c = pivui.pab5Palette.pastelGreen(j)        % varian hijau SF ke-j (lembut)
%     c = pivui.pab5Palette.vividGreen(j)         % varian hijau SF ke-j (ngejreng)
%     c = pivui.pab5Palette.zoneGreen(h, j)       % pilih per h.zonePalette
%
%   Penempatan berkas: PAB/pivcore_lib/+pivui/pab5Palette.m

    methods (Static)

        function c = pastelPalette()
        %PASTELPALETTE  Warna pastel LEMBUT (default), estetik, kontras antar-sesar.
            c = { [0.62 0.76 0.90], ...   % biru langit
                  [0.95 0.78 0.55], ...   % oranye pastel
                  [0.78 0.68 0.88], ...   % ungu lavender
                  [0.98 0.72 0.72], ...   % merah muda salmon
                  [0.72 0.86 0.72], ...   % hijau mint
                  [0.95 0.88 0.60], ...   % kuning lembut
                  [0.68 0.85 0.88], ...   % teal muda
                  [0.88 0.75 0.70] };     % coklat pastel
        end

        function c = vividPalette()
        %VIVIDPALETTE  Warna NGEJRENG (jenuh) — kontras tinggi antar-sesar.
            c = { [0.10 0.45 0.95], ...   % biru terang
                  [1.00 0.55 0.00], ...   % oranye
                  [0.60 0.20 0.85], ...   % ungu
                  [0.95 0.15 0.35], ...   % merah-pink
                  [0.10 0.75 0.30], ...   % hijau
                  [1.00 0.82 0.00], ...   % kuning
                  [0.00 0.75 0.80], ...   % teal
                  [0.70 0.40 0.20] };     % coklat
        end

        function c = zonePalette(h)
        %ZONEPALETTE  Koleksi warna zona/area sesar menurut h.zonePalette.
            if isstruct(h) && isfield(h,'zonePalette') && strcmp(h.zonePalette,'ngejreng')
                c = pivui.pab5Palette.vividPalette();
            else
                c = pivui.pab5Palette.pastelPalette();
            end
        end

        function a = zoneAlpha(h)
        %ZONEALPHA  Transparansi fill zona sesar (state; default 0.28; clamp).
            a = 0.28;
            if isstruct(h) && isfield(h,'zoneAlpha') && isscalar(h.zoneAlpha) && isfinite(h.zoneAlpha)
                a = max(0.02, min(0.95, h.zoneAlpha));
            end
        end

        function c = pastelGreen(j)
        %PASTELGREEN  Varian hijau utk SF ke-j (lembut).
            base = { [0.70 0.88 0.70], [0.60 0.82 0.66], [0.78 0.90 0.62], [0.66 0.85 0.78] };
            c = base{mod(max(1,j)-1,numel(base))+1};
        end

        function c = vividGreen(j)
        %VIVIDGREEN  Varian hijau NGEJRENG utk SF ke-j.
            base = { [0.10 0.80 0.25], [0.20 0.70 0.40], [0.40 0.85 0.10], [0.00 0.75 0.55] };
            c = base{mod(max(1,j)-1,numel(base))+1};
        end

        function c = zoneGreen(h, j)
        %ZONEGREEN  Varian hijau SF ke-j menurut h.zonePalette.
            if isstruct(h) && isfield(h,'zonePalette') && strcmp(h.zonePalette,'ngejreng')
                c = pivui.pab5Palette.vividGreen(j);
            else
                c = pivui.pab5Palette.pastelGreen(j);
            end
        end

    end
end
