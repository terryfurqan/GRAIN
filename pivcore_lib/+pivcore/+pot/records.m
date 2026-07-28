classdef records
%RECORDS  Operasi tingkat-RECORD kurva POT-PSG4 (murni, headless): normalisasi
%   skema, deret tampil (curveXY: MA + potong nF), getter label, pewarnaan.
%   Stateless (tak menyentuh handle), aman di-test. Dipakai-ulang GUI standalone
%   (step2) — sebelumnya helper lokal i_normalizeRecs/i_curveXY/i_lbl/i_applyColors.
%
%   Skema record (POT-PSG4): data, point, posPx, origin, color, mode, maWindow,
%   assignLabel, cutManual, cutFrame, dataCut.
%
%   Trim ke max indenter menyimpan DUA versi kurva (non-destruktif):
%     data    = kurva ASLI utuh (versi-1; selalu dijaga -> bisa di-restore)
%     dataCut = kurva TERPOTONG di max indenter (versi-2; di-NaN-kan setelah
%               cutFrame). cutFrame = frame "kematian" yang DIBEKUKAN saat Trim
%               supaya reproducible (tak ikut berubah bila envelope berubah).
%
%   API:
%     recs    = pivcore.pot.records.normalize(recs)
%     [xv,yv] = pivcore.pot.records.curveXY(rec, nF)
%     lb      = pivcore.pot.records.label(rec)
%     recs    = pivcore.pot.records.applyColors(recs)

    methods (Static)

        function recs = normalize(recs)
        %NORMALIZE  Pastikan field minimal tiap record ADA & bernilai sah
        %   (data/point/posPx/origin/color/mode/maWindow/assignLabel/cutManual).
        %   Robust thd record minimal/lama: field HILANG ditambahkan ke SELURUH
        %   array dulu (hindari "dissimilar structures" saat recs(r)=rec), lalu
        %   nilai tiap record diperbaiki. Field EKSTRA (mis. POT-PSG4) dijaga.
            n = numel(recs);
            if n == 0, return; end
            defs = {'data',[], 'point','', 'posPx',NaN, 'origin',[NaN NaN], ...
                    'color',[0.4 0.4 0.4], 'mode','Moving average', ...
                    'maWindow',2, 'assignLabel','', 'cutManual',false, ...
                    'cutFrame',NaN, 'dataCut',[]};
            for k = 1:2:numel(defs)
                if ~isfield(recs, defs{k}), [recs.(defs{k})] = deal(defs{k+1}); end
            end
            for r = 1:n
                rec = recs(r);
                if ~ischar(rec.point) || isempty(rec.point), rec.point = sprintf('P-%d', r); end
                if ~isscalar(rec.posPx), rec.posPx = NaN; end
                if numel(rec.origin) ~= 2, rec.origin = [NaN NaN]; end
                if numel(rec.color) ~= 3, rec.color = [0.4 0.4 0.4]; end
                if ~ischar(rec.mode) || isempty(rec.mode), rec.mode = 'Moving average'; end
                if ~isscalar(rec.maWindow), rec.maWindow = 2; end
                if ~ischar(rec.assignLabel), rec.assignLabel = ''; end
                if ~isscalar(rec.cutManual), rec.cutManual = false; end   % trim ke max indenter
                if ~isscalar(rec.cutFrame), rec.cutFrame = NaN; end       % frame potong (dibekukan)
                if ~isnumeric(rec.dataCut), rec.dataCut = []; end         % kurva terpotong (versi-2)
                recs(r) = rec;
            end
        end


        function [xv, yv] = curveXY(rec, nF)
        %CURVEXY  Deret (x=frame, y=nilai) sebuah record, di-MA sesuai metadata
        %   (sama dgn step1Export.plotPot) + dipotong ke nF.
            xv = []; yv = [];
            if isempty(rec) || ~isfield(rec,'data') || isempty(rec.data), return; end
            y = rec.data(:).';
            if isfield(rec,'mode') && strcmpi(rec.mode,'Moving average') ...
                    && isfield(rec,'maWindow') && isscalar(rec.maWindow) && rec.maWindow >= 2
                y = pivcore.util.movavg(y, rec.maWindow);
            end
            if nargin >= 2 && isfinite(nF) && nF >= 1 && numel(y) > nF, y = y(1:nF); end
            xv = 1:numel(y); yv = y;
        end


        function lb = label(rec)
        %LABEL  Getter aman assignLabel (string; '' bila tak ada).
            lb = '';
            if isstruct(rec) && isfield(rec,'assignLabel') && ischar(rec.assignLabel)
                lb = rec.assignLabel;
            end
        end


        function recs = applyColors(recs)
        %APPLYCOLORS  Set recs.color: ter-assign = warna label (labels.labelColor);
        %   belum = pelangi (labels.unassignedColor).
            for r = 1:numel(recs)
                [ty, num] = pivcore.pot.labels.parseLabel(pivcore.pot.records.label(recs(r)));
                if isempty(ty)
                    recs(r).color = pivcore.pot.labels.unassignedColor(r);
                else
                    recs(r).color = pivcore.pot.labels.labelColor(ty, num);
                end
            end
        end

    end
end
