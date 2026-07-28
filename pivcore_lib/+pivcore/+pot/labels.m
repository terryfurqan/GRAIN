classdef labels
%LABELS  Tata-bahasa label assignment POT (HW-#/F-#/F0/FFW) + warna
%   deterministik per label. SATU sumber kebenaran untuk GUI standalone
%   (step2) — sebelumnya disalin IDENTIK di step2 dan pivterry.modules.tabStep3.
%   Stateless/headless (tak menyentuh handle), aman di-test.
%
%   API:
%     lbl      = pivcore.pot.labels.makeLabel(ty, num)
%     [ty,num] = pivcore.pot.labels.parseLabel(lbl)
%     col      = pivcore.pot.labels.labelColor(ty, num)
%     col      = pivcore.pot.labels.hwPalette(k)
%
%   Konvensi domain (imbrikasi sesar naik): HW = hanging wall (kurva naik);
%   F = bidang sesar transisi; F0 = sesar pertama (num=0); FFW = Final Footwall
%   (blok stabil, satu per eksperimen, num=0).

    methods (Static)

        function lbl = makeLabel(ty, num)
        %MAKELABEL  'HW'+1 -> 'HW-1'; 'F'+2 -> 'F-2'; 'F0' -> 'F0'; 'FFW' -> 'FFW'.
            switch ty
                case 'F0',  lbl = 'F0';
                case 'FFW', lbl = 'FFW';
                case 'HW',  lbl = sprintf('HW-%d', num);
                case 'F',   lbl = sprintf('F-%d', num);
                otherwise,  lbl = '';
            end
        end


        function [ty, num] = parseLabel(lbl)
        %PARSELABEL  'HW-3' -> ('HW',3); 'F-2' -> ('F',2); 'F0' -> ('F0',0);
        %   'FFW' -> ('FFW',0).
            ty = ''; num = NaN;
            if isempty(lbl) || ~ischar(lbl), return; end
            if strcmpi(lbl,'F0'),  ty = 'F0';  num = 0; return; end
            if strcmpi(lbl,'FFW'), ty = 'FFW'; num = 0; return; end
            tok = regexp(lbl, '^(HW|F)-(\d+)$', 'tokens', 'once');
            if ~isempty(tok), ty = tok{1}; num = str2double(tok{2}); end
        end


        function col = labelColor(ty, num)
        %LABELCOLOR  Warna deterministik per label.
        %   HW-0 = biru-tua khas; HW (>=1) = palet TETAP & kontras (HW-1 selalu
        %   hijau, dst.); F / F0 = abu netral (kurva transisi, sengaja tak
        %   menonjol); FFW = hampir hitam (basis stabil).
            switch ty
                case 'HW'
                    if isfinite(num) && num == 0
                        col = [0.10 0.20 0.45];
                    else
                        col = pivcore.pot.labels.hwPalette(max(1,num));
                    end
                case {'F','F0'}
                    col = [0.55 0.55 0.55];
                case 'FFW'
                    col = [0.12 0.12 0.12];
                otherwise
                    col = [0.6 0.6 0.6];
            end
        end


        function col = hwPalette(k)
        %HWPALETTE  Palet TETAP utk HW-# (1-based; Tableau-like; berulang siklik
        %   bila k > jumlah warna).
            P = [ ...
                0.17 0.63 0.17;   ... % 1  hijau
                0.89 0.47 0.76;   ... % 2  pink
                1.00 0.50 0.05;   ... % 3  oranye
                0.58 0.40 0.74;   ... % 4  ungu
                0.09 0.75 0.81;   ... % 5  cyan
                0.74 0.74 0.13;   ... % 6  zaitun
                0.55 0.34 0.29;   ... % 7  coklat
                0.12 0.47 0.71;   ... % 8  biru
                0.84 0.15 0.16;   ... % 9  merah
                0.50 0.50 0.50];      % 10 abu
            if ~isfinite(k) || k < 1, k = 1; end
            idx = mod(round(k)-1, size(P,1)) + 1;
            col = P(idx,:);
        end


        function col = unassignedColor(idx)
        %UNASSIGNEDCOLOR  Warna pelangi deterministik utk kurva BELUM-assign
        %   (golden-ratio hue). Sama gaya dgn Step 3 main suite.
            if ~isfinite(idx) || idx < 1, idx = 1; end
            hue = mod((idx-1) * 0.61803398875, 1);
            try
                col = hsv2rgb([hue 0.55 0.85]);
            catch
                col = [0.78 0.78 0.78];
            end
            col = col(:).';
        end

    end
end
