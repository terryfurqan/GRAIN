classdef assign
%ASSIGN  Agregat assignment kurva POT per label (murni, headless). Mengumpulkan
%   record per label -> struct agregat + fitur grup; KOMPATIBEL dgn
%   pivcore.io.step1Session.saveAssignments. Stateless, aman di-test. Dipakai-
%   ulang GUI standalone (step2) — sebelumnya i_assignFromRecords/i_emptyAssign/
%   i_emptyAssignOne/i_restoreAssign.
%
%   API:
%     a   = pivcore.pot.assign.fromRecords(recs)
%     a   = pivcore.pot.assign.empty()
%     e   = pivcore.pot.assign.emptyOne()
%     rc  = pivcore.pot.assign.applySaved(recs, savedAssign)

    methods (Static)

        function assign = fromRecords(recs)
        %FROMRECORDS  Kumpulkan record per label -> struct agregat + fitur grup
        %   (pivcore.pot.curveFeatures). KOMPATIBEL dgn step1Session.saveAssignments.
            assign = pivcore.pot.assign.empty();
            if isempty(recs), return; end
            labels = {};
            for r = 1:numel(recs)
                lb = pivcore.pot.records.label(recs(r));
                if ~isempty(lb), labels{end+1} = lb; end %#ok<AGROW>
            end
            uLbl = unique(labels, 'stable');
            for u = 1:numel(uLbl)
                lb = uLbl{u};
                idx = [];
                for r = 1:numel(recs)
                    if strcmp(pivcore.pot.records.label(recs(r)), lb), idx(end+1) = r; end %#ok<AGROW>
                end
                [ty, num] = pivcore.pot.labels.parseLabel(lb);
                e = pivcore.pot.assign.emptyOne();
                e.label    = lb;
                e.type     = ty;
                e.num      = num;
                e.curveIdx = idx;
                e.color    = pivcore.pot.labels.labelColor(ty, num);
                e.feat     = pivcore.pot.curveFeatures.featGroup(recs, idx);
                if isempty(assign), assign = e; else, assign(end+1) = e; end %#ok<AGROW>
            end
            assign = pivcore.pot.curveFeatures.fillGroupGaps(assign);
        end


        function a = empty()
        %EMPTY  Struct-array assignment kosong (skema kanonik).
            a = struct('label',{},'type',{},'num',{},'curveIdx',{},'color',{},'feat',{});
        end


        function e = emptyOne()
        %EMPTYONE  Satu entri assignment kosong (feat = grup kosong).
            e = struct('label','','type','','num',NaN,'curveIdx',[], ...
                'color',[0.6 0.6 0.6],'feat',pivcore.pot.curveFeatures.emptyGroupFeat());
        end


        function recs = applySaved(recs, saved)
        %APPLYSAVED  Petakan assignment tersimpan (ap.step3Assign: curveIdx ->
        %   label) ke records.assignLabel, HANYA bila records belum punya label.
        %   `saved` = struct-array hasil step1Session.loadAssignments.
            has = false;
            for r = 1:numel(recs)
                if ~isempty(pivcore.pot.records.label(recs(r))), has = true; break; end
            end
            if has, return; end
            if isempty(saved) || ~isstruct(saved), return; end
            for a = 1:numel(saved)
                if ~isfield(saved(a),'curveIdx') || ~isfield(saved(a),'label'), continue; end
                idx = saved(a).curveIdx(:).';
                for ri = idx
                    if ri >= 1 && ri <= numel(recs), recs(ri).assignLabel = saved(a).label; end
                end
            end
        end

    end
end
