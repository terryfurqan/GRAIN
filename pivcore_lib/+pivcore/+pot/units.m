classdef units
%UNITS  Konversi laju perpindahan POT dari px/frame -> satuan metrik
%   (cm/s / cm/hr). SATU sumber kebenaran untuk kalibrasi ruang+waktu yang
%   dipakai GUI standalone (step1 = input di tabel, step2 = tampilan axPOT).
%   Stateless/headless (tak menyentuh handle figure), aman di-test. Gaya
%   sejajar pivcore.pot.vscale / pivcore.pot.labels.
%
%   Data POT mentah = velocity_magnitude PIVLAB TAK terkalibrasi (calxy=1) ->
%   satuannya px/frame (laju perpindahan tanpa satuan fisik). Agar tampil
%   sebagai laju metrik dibutuhkan dua kalibrasi:
%     - RUANG  cmPerPx = |lengthCm - startCm| / lineLenPx
%       (lineLenPx = panjang garis PSG dlm piksel). Mengikuti konvensi
%       tabPSG mode "real-unit": garis PSG membentang sepanjang (length-start)
%       cm, jadi cm/px = panjang_cm / panjang_px.
%     - WAKTU  secPerFrame = rata-rata interval antar foto (s/frame).
%   Maka:
%       cm/s     = px/frame * cmPerPx / secPerFrame
%       cm/hr    = cm/s * 3600
%       px/frame = mentah (faktor 1)
%   "Strain label" (anotasi tabStrain): strainMax% = |endCm-startCm|/lengthCm*100.
%
%   Struktur kalibrasi (disimpan di autopotSession.step1.scale):
%     startCm, endCm, lengthCm, secPerFrame (double|NaN), unit ('cm/s'|'cm/hr'),
%     savedAt (char).
%
%   API:
%     s        = pivcore.pot.units.emptyScale()
%     s        = pivcore.pot.units.normalize(s)
%     u        = pivcore.pot.units.unitList()            % {'cm/s','cm/hr','px/frame'}
%     px       = pivcore.pot.units.lineLenPx(line)       % hypot p1->p2
%     cmpp     = pivcore.pot.units.cmPerPx(scale, lineLenPx)
%     [f, lab] = pivcore.pot.units.factor(scale, lineLenPx [, unit])
%     yv       = pivcore.pot.units.convert(yv, f)
%     pct      = pivcore.pot.units.strainMax(scale)
%
%   Penempatan berkas: PIVTerry/core/+pivcore/+pot/units.m

    methods (Static)

        function s = emptyScale()
        %EMPTYSCALE  Struktur kalibrasi kosong (semua NaN, unit default 'cm/s').
            s = struct('startCm',NaN, 'endCm',NaN, 'lengthCm',NaN, ...
                       'secPerFrame',NaN, 'unit','cm/s', 'savedAt','');
        end


        function s = normalize(s)
        %NORMALIZE  Pastikan field kalibrasi ADA & bertipe sah. Field hilang
        %   diisi default emptyScale; nilai non-skalar/non-numerik -> NaN; unit
        %   asing -> 'cm/s'. CATATAN: 'px/frame' BUKAN unit simpan (hanya pilihan
        %   tampilan di step2) -> tak pernah disimpan sebagai scale.unit.
            d = pivcore.pot.units.emptyScale();
            if isempty(s) || ~isstruct(s), s = d; return; end
            for fn = {'startCm','endCm','lengthCm','secPerFrame'}
                k = fn{1};
                if ~isfield(s,k) || ~isscalar(s.(k)) || ~isnumeric(s.(k))
                    s.(k) = NaN;
                else
                    s.(k) = double(s.(k));
                end
            end
            if ~isfield(s,'unit') || ~ischar(s.unit) ...
                    || ~any(strcmpi(s.unit, {'cm/s','cm/hr'}))
                s.unit = 'cm/s';
            else
                s.unit = lower(s.unit);
            end
            if ~isfield(s,'savedAt') || ~ischar(s.savedAt), s.savedAt = ''; end
        end


        function u = unitList()
        %UNITLIST  Daftar satuan tampilan (urut: metrik dulu, mentah terakhir).
            u = {'cm/s','cm/hr','px/frame'};
        end


        function px = lineLenPx(line)
        %LINELENPX  Panjang garis PSG dlm piksel (hypot p1->p2). NaN bila garis
        %   tak valid. `line` = struct('p1',[x y],'p2',[x y]).
            px = NaN;
            if isempty(line) || ~isstruct(line) ...
                    || ~isfield(line,'p1') || ~isfield(line,'p2'), return; end
            p1 = line.p1; p2 = line.p2;
            if numel(p1) ~= 2 || numel(p2) ~= 2 ...
                    || any(~isfinite(p1)) || any(~isfinite(p2)), return; end
            dpx = hypot(p2(1)-p1(1), p2(2)-p1(2));
            if isfinite(dpx) && dpx > 0, px = dpx; end
        end


        function cmpp = cmPerPx(scale, lineLenPx)
        %CMPERPX  Kalibrasi ruang cm/piksel = |lengthCm - startCm| / lineLenPx.
        %   NaN bila input tak lengkap/valid (span <= 0 atau lineLenPx <= 0).
            cmpp = NaN;
            s = pivcore.pot.units.normalize(scale);
            span = abs(s.lengthCm - s.startCm);
            if ~(isfinite(span) && span > 0), return; end
            if ~(isscalar(lineLenPx) && isfinite(lineLenPx) && lineLenPx > 0), return; end
            cmpp = span / lineLenPx;
        end


        function [f, lab] = factor(scale, lineLenPx, unit)
        %FACTOR  Pengali utk mengubah deret px/frame -> satuan `unit`, beserta
        %   label sumbu. unit default = scale.unit. Untuk 'px/frame' ATAU bila
        %   kalibrasi tak lengkap -> f=1 & label '[px/frame]' (JUJUR: tak
        %   memunculkan angka metrik palsu, sumbu jelas masih mentah).
            s = pivcore.pot.units.normalize(scale);
            if nargin < 3 || isempty(unit), unit = s.unit; end
            unit = lower(char(unit));

            if strcmp(unit, 'px/frame')
                f = 1; lab = 'Displacement rate [px/frame]'; return;
            end

            cmpp = pivcore.pot.units.cmPerPx(s, lineLenPx);
            spf  = s.secPerFrame;
            if ~(isfinite(cmpp) && cmpp > 0) ...
                    || ~(isscalar(spf) && isfinite(spf) && spf > 0)
                f = 1; lab = 'Displacement rate [px/frame]'; return;   % fallback
            end

            switch unit
                case 'cm/s'
                    f = cmpp / spf;          lab = 'Displacement rate [cm/s]';
                case 'cm/hr'
                    f = cmpp / spf * 3600;   lab = 'Displacement rate [cm/hr]';
                otherwise
                    f = 1;                   lab = 'Displacement rate [px/frame]';
            end
        end


        function yv = convert(yv, f)
        %CONVERT  Terapkan pengali f ke deret (yv .* f). f tak valid -> apa adanya.
            if ~(isscalar(f) && isfinite(f)), return; end
            yv = yv .* f;
        end


        function pct = strainMax(scale)
        %STRAINMAX  Strain maksimum (%) anotasi = |endCm-startCm|/lengthCm*100.
        %   NaN bila input tak lengkap (lengthCm <= 0). Padanan tabStrain auto.
            pct = NaN;
            s = pivcore.pot.units.normalize(scale);
            if ~(isfinite(s.lengthCm) && s.lengthCm > 0), return; end
            d = abs(s.endCm - s.startCm);
            if ~isfinite(d), return; end
            pct = d / s.lengthCm * 100;
        end

    end
end
