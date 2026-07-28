classdef potexpModel
%POTEXPMODEL  Logika murni untuk modul POT-EXP (eksplorasi POT).
%
%   Modul POT-EXP membiarkan pengguna MENGUKUR jarak X & Y pada grafik POT
%   dengan menaruh 4 titik pengamatan per kurva HW:
%       slot 1 = Start, 2 = Nucleation, 3 = FSR (propagasi), 4 = END.
%   Titik diklik pada grafik POT lalu di-SNAP ke kurva HW yang sedang aktif
%   (X = bingkai/strain pada kurva, Y = nilai kurva pada titik itu).
%
%   Kelas ini TIDAK menyentuh GUI: ia hanya menyediakan struktur data +
%   perhitungan (snap, delta/gradient, integral antar pasangan kurva) agar
%   dipakai bersama oleh tab embedded (tabPOTEXP) maupun GUI mandiri
%   (POTExpExplorer). Lihat memory potexp-module-spec.
%
%   Skema state (disimpan di h.state.pot.exp):
%       exp.armed       : logical  -> mode sampling aktif?
%       exp.activeHW    : indeks kurva (var POT) yang aktif
%       exp.targetSlot  : 1..4     -> cell yang akan diisi berikutnya
%       exp.points(k).xy: 4x2 (NaN) -> baris=slot, kolom=[X Y]
%       exp.integral    : 1xN (NaN) -> integral pasangan (HW_n, HW_{n+1})
%                                       disimpan di baris kiri (n)
%
%   API utama:
%       exp = potexpModel.ensure(exp, nVars)
%       names = potexpModel.slotNames()
%       [x,y,ok] = potexpModel.snapToCurve(xVec, yVec, xClick)
%       D = potexpModel.deltas(exp)                 % delta antar SEMUA titik
%       [val,ok,msg] = potexpModel.integralPair(...)
%       tf = potexpModel.allComplete(exp, nVars)

    methods (Static)

        % ================================================================
        function names = slotNames()
            names = {'Start','Nucleation','FSR','END'};
        end


        % ================================================================
        function C = slotColors()
        %SLOTCOLORS  Warna penanda per slot pengamatan (4x3 RGB):
        %   Start = hijau, Nucleation = biru, FSR = kuning, END = merah.
            C = [0.00 0.70 0.00;    % Start      -> hijau
                 0.00 0.30 1.00;    % Nucleation -> biru
                 0.95 0.85 0.00;    % FSR        -> kuning
                 0.90 0.10 0.10];   % END        -> merah
        end


        % ================================================================
        function exp = ensure(exp, nVars)
        %ENSURE  Pastikan struct exp ada & punya 1 entri points per kurva.
            if nargin < 1 || ~isstruct(exp), exp = struct(); end
            if ~isfield(exp,'armed'),      exp.armed = false;      end
            if ~isfield(exp,'activeHW'),   exp.activeHW = 1;       end
            if ~isfield(exp,'targetSlot'), exp.targetSlot = 1;     end
            if ~isfield(exp,'points') || ~isstruct(exp.points)
                exp.points = struct('xy',{});
            end
            if nargin < 2 || isempty(nVars), nVars = numel(exp.points); end
            nVars = max(0, round(nVars));

            % Tumbuhkan / pangkas daftar points agar = nVars.
            cur = numel(exp.points);
            if cur < nVars
                for k = cur+1:nVars
                    exp.points(k).xy = nan(4,2);
                end
            elseif cur > nVars
                exp.points = exp.points(1:nVars);
            end
            % Pastikan setiap xy berbentuk 4x2.
            for k = 1:numel(exp.points)
                xy = exp.points(k).xy;
                if ~isequal(size(xy),[4 2]) || ~isnumeric(xy)
                    fixed = nan(4,2);
                    if isnumeric(xy) && ~isempty(xy)
                        r = min(size(xy,1),4); c = min(size(xy,2),2);
                        fixed(1:r,1:c) = xy(1:r,1:c);
                    end
                    exp.points(k).xy = fixed;
                end
            end

            % Integral: 1xnVars, baris kiri menampung pasangan (n,n+1).
            if ~isfield(exp,'integral') || numel(exp.integral) ~= nVars
                ivOld = [];
                if isfield(exp,'integral'), ivOld = exp.integral(:).'; end
                iv = nan(1, nVars);
                m = min(numel(ivOld), nVars);
                if m > 0, iv(1:m) = ivOld(1:m); end
                exp.integral = iv;
            end

            exp.activeHW   = min(max(1, round(exp.activeHW)),   max(1,nVars));
            exp.targetSlot = min(max(1, round(exp.targetSlot)), 4);
        end


        % ================================================================
        function [xVec, yVec] = curveXY(v, nF, opt)
        %CURVEXY  Bangun (xVec,yVec) TERPLOT untuk satu variabel POT v,
        %   meniru transform redrawPOT: yMult, moving-average, masking
        %   rentang [fromF,toF], dan sumbu X (bingkai atau strain).
        %
        %   opt fields (semua opsional):
        %     opt.yMult   (default 1)
        %     opt.xMode   'frame' (default) | 'strain'
        %     opt.sMin, opt.sMax  (rentang strain bila xMode='strain')
            if nargin < 3 || ~isstruct(opt), opt = struct(); end
            yMult = 1;
            if isfield(opt,'yMult') && isfinite(opt.yMult) && opt.yMult ~= 0
                yMult = opt.yMult;
            end
            xMode = 'frame';
            if isfield(opt,'xMode') && ischar(opt.xMode), xMode = lower(opt.xMode); end

            if strcmp(xMode,'strain')
                sMin = 0; sMax = 0.05;
                if isfield(opt,'sMin') && isfinite(opt.sMin), sMin = opt.sMin; end
                if isfield(opt,'sMax') && isfinite(opt.sMax), sMax = opt.sMax; end
                if nF <= 1, xVec = sMin; else, xVec = linspace(sMin, sMax, nF); end
            else
                xVec = 1:nF;
            end

            ydata = [];
            if isfield(v,'data'), ydata = v.data; end
            if isempty(ydata) || all(isnan(ydata))
                yVec = nan(1, nF); return;
            end
            ydata = ydata(:).' * yMult;
            mode = ''; if isfield(v,'mode'), mode = v.mode; end
            maW = 2; if isfield(v,'maWindow') && isfinite(v.maWindow), maW = v.maWindow; end
            if strcmpi(mode,'Moving average') && maW >= 2
                ydata = pivcore.util.movavg(ydata, maW);
            end
            yVec = nan(1, nF);
            fromF = 1; toF = nF;
            if isfield(v,'fromF') && isfinite(v.fromF), fromF = v.fromF; end
            if isfield(v,'toF')   && isfinite(v.toF),   toF   = v.toF;   end
            idx = max(1,round(fromF)) : min(nF, round(toF));
            idx = idx(idx >= 1 & idx <= numel(ydata));
            yVec(idx) = ydata(idx);
        end


        % ================================================================
        function [xs, ys, ok] = snapToCurve(xVec, yVec, xClick)
        %SNAPTOCURVE  Snap absis klik ke kurva (xVec,yVec): ambil titik kurva
        %   dengan X terdekat ke xClick yang nilainya berhingga. Mengembalikan
        %   (xs,ys) koordinat titik kurva tsb. ok=false bila kurva kosong.
            xs = NaN; ys = NaN; ok = false;
            if isempty(xVec) || isempty(yVec), return; end
            xVec = xVec(:).'; yVec = yVec(:).';
            n = min(numel(xVec), numel(yVec));
            xVec = xVec(1:n); yVec = yVec(1:n);
            valid = isfinite(xVec) & isfinite(yVec);
            if ~any(valid), return; end
            xV = xVec(valid); yV = yVec(valid);
            [~, idx] = min(abs(xV - xClick));
            xs = xV(idx); ys = yV(idx); ok = true;
        end


        % ================================================================
        function D = deltas(exp)
        %DELTAS  Delta X, Delta Y, dan Gradient antar SEMUA titik berurutan
        %   (Start->Nucleation->FSR->END) untuk tiap kurva. Hanya DISIMPAN
        %   (tidak ditampilkan). Mengembalikan struct array per kurva:
        %       D(k).dX, D(k).dY, D(k).grad  (masing-masing 1x3)
        %   pasangan: (1->2),(2->3),(3->4).
            nV = numel(exp.points);
            D = struct('dX',{},'dY',{},'grad',{});
            for k = 1:nV
                xy = exp.points(k).xy;
                dX = nan(1,3); dY = nan(1,3); g = nan(1,3);
                for s = 1:3
                    a = xy(s,:); b = xy(s+1,:);
                    if all(isfinite([a b]))
                        dX(s) = b(1) - a(1);
                        dY(s) = b(2) - a(2);
                        if dX(s) ~= 0, g(s) = dY(s) / dX(s); end
                    end
                end
                D(k) = struct('dX',dX,'dY',dY,'grad',g); %#ok<AGROW>
            end
        end


        % ================================================================
        function tf = curveComplete(exp, k)
        %CURVECOMPLETE  Apakah kurva k punya keempat titik (semua finite)?
            tf = false;
            if k < 1 || k > numel(exp.points), return; end
            xy = exp.points(k).xy;
            tf = isequal(size(xy),[4 2]) && all(isfinite(xy(:)));
        end


        function tf = allComplete(exp, nVars)
        %ALLCOMPLETE  Apakah SEMUA kurva (1..nVars) lengkap 4 titik?
            if nargin < 2 || isempty(nVars), nVars = numel(exp.points); end
            tf = nVars >= 1;
            for k = 1:nVars
                if ~pivcore.pot.potexpModel.curveComplete(exp, k)
                    tf = false; return;
                end
            end
        end


        % ================================================================
        function [val, ok, msg] = integralBetween(xL, yL, xR, yR)
        %INTEGRALBETWEEN  Luas area (integral lipat-1) di antara dua kurva
        %   kiri (xL,yL) dan kanan (xR,yR). Kurva di-resample ke union absis
        %   yang beririsan, lalu |yL - yR| diintegralkan via trapz terhadap X.
        %
        %   Mengembalikan val=luas (>=0), ok, msg.
            val = NaN; ok = false; msg = '';
            xL = xL(:).'; yL = yL(:).'; xR = xR(:).'; yR = yR(:).';
            vL = isfinite(xL) & isfinite(yL);
            vR = isfinite(xR) & isfinite(yR);
            xL = xL(vL); yL = yL(vL); xR = xR(vR); yR = yR(vR);
            if numel(xL) < 2 || numel(xR) < 2
                msg = 'Kurva tidak cukup titik untuk integral.'; return;
            end
            % Rentang absis yang beririsan (di mana kedua kurva terdefinisi).
            xlo = max(min(xL), min(xR));
            xhi = min(max(xL), max(xR));
            if ~(xhi > xlo)
                msg = 'Rentang X kedua kurva tidak beririsan.'; return;
            end
            % Grid bersama dari semua absis unik dalam [xlo,xhi].
            xs = unique([xL, xR]);
            xs = xs(xs >= xlo & xs <= xhi);
            if numel(xs) < 2, xs = linspace(xlo, xhi, 50); end
            % Interpolasi linear kedua kurva ke grid bersama.
            yLi = interp1(xL, yL, xs, 'linear');
            yRi = interp1(xR, yR, xs, 'linear');
            d = abs(yLi - yRi);
            good = isfinite(d);
            if nnz(good) < 2
                msg = 'Data tumpang tindih tidak cukup untuk integral.'; return;
            end
            val = trapz(xs(good), d(good));
            ok = true;
        end


        % ================================================================
        function hex = rgbHex(c)
        %RGBHEX  Ubah RGB (0..1, 1x3) -> string hex '#RRGGBB'. Nilai
        %   non-finite/di luar rentang di-clamp. (Utilitas umum.)
            if numel(c) < 3 || ~isnumeric(c)
                c = [0 0 0];
            end
            c = c(1:3);
            c(~isfinite(c)) = 0;
            c = min(1, max(0, c));
            rgb255 = round(c * 255);
            hex = sprintf('#%02X%02X%02X', rgb255(1), rgb255(2), rgb255(3));
        end


        function tf = isDark(c)
        %ISDARK  Apakah warna c gelap (butuh teks terang)? Pakai luminance
        %   sederhana; ambang sama dgn konvensi tab POT (mean > 0.6 = terang).
            if numel(c) < 3 || ~isnumeric(c), tf = true; return; end
            c = c(1:3); c(~isfinite(c)) = 0; c = min(1,max(0,c));
            tf = mean(c) <= 0.6;
        end


        % ================================================================
        function txt = coordStr(xy)
        %COORDSTR  Format pasangan [x y] -> '(x, y)' untuk sel tabel.
            if numel(xy) < 2 || any(~isfinite(xy(1:2)))
                txt = ''; return;
            end
            txt = sprintf('(%.4g, %.4g)', xy(1), xy(2));
        end

    end
end
