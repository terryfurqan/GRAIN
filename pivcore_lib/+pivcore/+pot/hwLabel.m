classdef hwLabel
%HWLABEL  Labeling Hanging-Wall RINGAN di-tempat (HW-#/F-#/F0/FFW) atas array
%   record POT — fungsi murni/headless di atas pivcore.pot.labels + records +
%   netslip. Dipakai GRAIN4B (tanpa lewat GRAIN3a). SATU sumber pengelompokan HW.
%
%   API:
%     recs   = pivcore.pot.hwLabel.assign(recs, rowIdx, ty, num)  % set label+warna
%     recs   = pivcore.pot.hwLabel.unassign(recs, rowIdx)
%     nums   = pivcore.pot.hwLabel.hwNumbers(recs)        % HW-# unik, terurut naik
%     rows   = pivcore.pot.hwLabel.rowsForHW(recs, num)
%     rows   = pivcore.pot.hwLabel.ffwRows(recs)
%     Y      = pivcore.pot.hwLabel.groupCurves(recs, rows, nF)     % cell vektor-baris
%     [A,B,partner,okB] = pivcore.pot.hwLabel.pair(recs, num, nF)  % rep HWₙ vs HWₙ₊₁/FFW
%     st     = pivcore.pot.hwLabel.completeness(recs)     % nHW/hasFFW/canNetslip/...
%     tyList = pivcore.pot.hwLabel.typeList()             % {'HW','F','F0','FFW'}
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivcore/+pot/hwLabel.m

    methods (Static)

        % ================================================================
        function recs = assign(recs, rowIdx, ty, num)
        %ASSIGN  Beri label kurva rowIdx -> HW-#/F-#/F0/FFW lalu warnai ulang
        %   SELURUH array (warna = warna label).
            if isempty(recs) || rowIdx < 1 || rowIdx > numel(recs), return; end
            lbl = pivcore.pot.labels.makeLabel(ty, num);
            recs(rowIdx).assignLabel = lbl;
            recs = pivcore.pot.records.applyColors(recs);
        end


        function recs = unassign(recs, rowIdx)
        %UNASSIGN  Hapus label kurva rowIdx + warnai ulang.
            if isempty(recs) || rowIdx < 1 || rowIdx > numel(recs), return; end
            recs(rowIdx).assignLabel = '';
            recs = pivcore.pot.records.applyColors(recs);
        end


        % ================================================================
        function nums = hwNumbers(recs)
        %HWNUMBERS  Nomor HW unik yang HADIR (HW-0..HW-n), terurut naik.
            nums = [];
            for r = 1:numel(recs)
                [ty, num] = pivcore.pot.labels.parseLabel(pivcore.pot.records.label(recs(r)));
                if strcmp(ty,'HW') && isfinite(num), nums(end+1) = num; end %#ok<AGROW>
            end
            nums = unique(nums(:).');
        end


        function rows = rowsForHW(recs, num)
        %ROWSFORHW  Indeks record berlabel HW-<num>.
            rows = [];
            for r = 1:numel(recs)
                [ty, n] = pivcore.pot.labels.parseLabel(pivcore.pot.records.label(recs(r)));
                if strcmp(ty,'HW') && isfinite(n) && n == num, rows(end+1) = r; end %#ok<AGROW>
            end
        end


        function rows = ffwRows(recs)
        %FFWROWS  Indeks record berlabel FFW (Final Footwall, blok stabil).
            rows = [];
            for r = 1:numel(recs)
                ty = pivcore.pot.labels.parseLabel(pivcore.pot.records.label(recs(r)));
                if strcmp(ty,'FFW'), rows(end+1) = r; end %#ok<AGROW>
            end
        end


        % ================================================================
        function Y = groupCurves(recs, rows, nF)
        %GROUPCURVES  Kumpulan deret (cell vektor-baris) untuk record `rows`,
        %   dipotong/di-MA via records.curveXY (konsisten tampilan axPOT).
            Y = {};
            for j = 1:numel(rows)
                r = rows(j);
                if r < 1 || r > numel(recs), continue; end
                [~, yv] = pivcore.pot.records.curveXY(recs(r), nF);
                if ~isempty(yv), Y{end+1} = yv(:).'; end %#ok<AGROW>
            end
        end


        % ================================================================
        function [A, B, partner, okB] = pair(recs, num, nF)
        %PAIR  Kurva representatif HWₙ (A) & pasangannya (B): HWₙ₊₁ bila ada,
        %   selain itu FFW. `partner` = label pasangan ('HW-2'/'FFW'/''). okB =
        %   true bila B punya data (pasangan ter-label).
            A = pivcore.pot.netslip.repVec( ...
                pivcore.pot.hwLabel.groupCurves(recs, ...
                    pivcore.pot.hwLabel.rowsForHW(recs, num), nF), nF);
            nums = pivcore.pot.hwLabel.hwNumbers(recs);
            partner = ''; okB = false; B = nan(1, nF);
            % HW berikutnya = nomor HW terkecil yang > num.
            nxt = nums(nums > num);
            if ~isempty(nxt)
                pn = min(nxt);
                rowsB = pivcore.pot.hwLabel.rowsForHW(recs, pn);
                if ~isempty(rowsB)
                    B = pivcore.pot.netslip.repVec( ...
                        pivcore.pot.hwLabel.groupCurves(recs, rowsB, nF), nF);
                    partner = sprintf('HW-%d', pn); okB = true;
                end
            else
                rowsF = pivcore.pot.hwLabel.ffwRows(recs);
                if ~isempty(rowsF)
                    B = pivcore.pot.netslip.repVec( ...
                        pivcore.pot.hwLabel.groupCurves(recs, rowsF, nF), nF);
                    partner = 'FFW'; okB = true;
                end
            end
        end


        % ================================================================
        function st = completeness(recs)
        %COMPLETENESS  Status kelengkapan label untuk net-slip (warga kelas-satu:
        %   modul tetap berguna walau belum lengkap).
        %     .nHW         jumlah HW unik
        %     .hwNums      daftar HW
        %     .hasFFW      ada FFW?
        %     .canNetslip  >=2 HW, ATAU (>=1 HW + FFW) -> net-slip bisa dihitung
        %     .message     ringkas untuk status bar
            nums = pivcore.pot.hwLabel.hwNumbers(recs);
            hasFFW = ~isempty(pivcore.pot.hwLabel.ffwRows(recs));
            nHW = numel(nums);
            canNetslip = (nHW >= 2) || (nHW >= 1 && hasFFW);
            if canNetslip
                msg = sprintf('Net-slip: siap (%d HW, FFW=%s).', nHW, pivcore.pot.hwLabel.yn(hasFFW));
            else
                msg = sprintf('Net-slip: butuh >=2 HW + FFW (sekarang: %d HW, FFW=%s).', ...
                    nHW, pivcore.pot.hwLabel.yn(hasFFW));
            end
            st = struct('nHW',nHW, 'hwNums',nums, 'hasFFW',hasFFW, ...
                        'canNetslip',canNetslip, 'message',msg);
        end


        function tyList = typeList()
            tyList = {'HW','F','F0','FFW'};
        end

    end


    methods (Static, Access = private)
        function s = yn(tf)
            if tf, s = 'ada'; else, s = 'tidak'; end
        end
    end
end
