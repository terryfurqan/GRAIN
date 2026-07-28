classdef faultAngle
%FAULTANGLE  Sudut sesar dari 2 titik — fungsi MURNI (headless). Dipakai Tab ②
%   PAB5 (Sesar = tampilan/final) untuk mengukur kemiringan sesar relatif bidang
%   detachment referensi. Pola sibling: pivcore.pot.netslip (murni, ber-test
%   golden). TIDAK menyentuh GUI/IO.
%
%   KONVENSI SUMBU: titik = [x y] pada axPOT/axMain (koordinat layar MATLAB,
%   sumbu-Y menunjuk KE BAWAH pada gambar tapi di sini dipakai apa adanya —
%   pemanggil bertanggung jawab konsisten). Sudut = atan2d(dy, dx), lalu
%   dinormalkan ke rentang (-90, 90] karena garis sesar tak berarah (garis, bukan
%   vektor): kemiringan 170° ≡ -10°.
%
%   "MIRING KIRI" (enforceLeftDip): konvensi seed 2-titik agar konsisten — ujung
%   KANAN lebih TINGGI, ujung KIRI lebih RENDAH (dip menghadap kiri). Dipakai saat
%   men-seed ROI 2-titik supaya semua sesar diukur dengan orientasi sama.
%
%   API:
%     deg = pivcore.pot.faultAngle.fromPoints(p1, p2)
%     deg = pivcore.pot.faultAngle.relativeToDetachment(fP1, fP2, detP1, detP2)
%     [q1,q2] = pivcore.pot.faultAngle.enforceLeftDip(p1, p2)
%     d = pivcore.pot.faultAngle.emptyDetachment()   % struct('p1',[NaN NaN],'p2',[NaN NaN])
%     tf = pivcore.pot.faultAngle.isValidDetachment(d)
%
%   Penempatan berkas: PAB/pivcore_lib/+pivcore/+pot/faultAngle.m

    methods (Static)

        % ================================================================
        function deg = fromPoints(p1, p2)
        %FROMPOINTS  Sudut garis 2-titik vs horizontal, dinormalkan (-90,90].
        %   NaN bila titik tak valid / berimpit (dx=dy=0).
            deg = NaN;
            a = pivcore.pot.faultAngle.pt(p1);
            b = pivcore.pot.faultAngle.pt(p2);
            if any(~isfinite(a)) || any(~isfinite(b)), return; end
            dx = b(1) - a(1); dy = b(2) - a(2);
            if dx == 0 && dy == 0, return; end
            deg = pivcore.pot.faultAngle.normDeg(atan2d(dy, dx));
        end


        % ================================================================
        function deg = relativeToDetachment(fP1, fP2, detP1, detP2)
        %RELATIVETODETACHMENT  Sudut sesar (fP1->fP2) RELATIF bidang detachment
        %   (detP1->detP2). = sudut sesar − sudut detachment, dinormalkan
        %   (-90,90]. Bila detachment tak diberi/invalid -> jatuh ke sudut absolut
        %   sesar (relatif horizontal). NaN bila sesar tak valid.
            deg = pivcore.pot.faultAngle.fromPoints(fP1, fP2);
            if ~isfinite(deg), return; end
            if nargin < 4, return; end
            dref = pivcore.pot.faultAngle.fromPoints(detP1, detP2);
            if ~isfinite(dref), return; end   % detachment invalid -> pakai absolut
            deg = pivcore.pot.faultAngle.normDeg(deg - dref);
        end


        % ================================================================
        function [q1, q2] = enforceLeftDip(p1, p2)
        %ENFORCELEFTDIP  Susun ulang 2 titik agar q1 = ujung KIRI (x lebih kecil),
        %   q2 = ujung KANAN (x lebih besar). Bila x sama, urut per-y (bawah dulu).
        %   Titik tak valid diteruskan apa adanya (q1=p1,q2=p2).
            a = pivcore.pot.faultAngle.pt(p1);
            b = pivcore.pot.faultAngle.pt(p2);
            if any(~isfinite(a)) || any(~isfinite(b))
                q1 = a; q2 = b; return;
            end
            swap = (b(1) < a(1)) || (b(1) == a(1) && b(2) < a(2));
            if swap, q1 = b; q2 = a; else, q1 = a; q2 = b; end
        end


        % ================================================================
        function d = emptyDetachment()
        %EMPTYDETACHMENT  Struct bidang detachment kosong (2 titik NaN).
            d = struct('p1', [NaN NaN], 'p2', [NaN NaN]);
        end


        % ================================================================
        function tf = isValidDetachment(d)
        %ISVALIDDETACHMENT  true bila d punya p1/p2 masing-masing 2 elemen finite
        %   dan tak berimpit.
            tf = false;
            if ~isstruct(d) || ~isfield(d,'p1') || ~isfield(d,'p2'), return; end
            a = pivcore.pot.faultAngle.pt(d.p1);
            b = pivcore.pot.faultAngle.pt(d.p2);
            if any(~isfinite(a)) || any(~isfinite(b)), return; end
            tf = ~(a(1)==b(1) && a(2)==b(2));
        end

    end


    methods (Static, Access = private)

        function v = pt(p)
        %PT  Normalkan titik ke baris [x y] double. Invalid -> [NaN NaN].
            v = [NaN NaN];
            if isnumeric(p) && numel(p) >= 2
                p = double(p(:)).';
                v = p(1:2);
            end
        end

        function deg = normDeg(deg)
        %NORMDEG  Bawa sudut ke (-90, 90] (garis tak berarah). Mis. 170 -> -10,
        %   -90 -> 90.
            if ~isfinite(deg), return; end
            deg = mod(deg, 180);        % [0,180)
            if deg > 90, deg = deg - 180; end   % (-90, 90]
        end

    end
end
