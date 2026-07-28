classdef pab4Annot
%PAB4ANNOT  Alat anotasi PAB4A di axMain: GARIS, TITIK, UKUR (ROI) + serialisasi
%   ke struct (untuk _potdata.json: psgLines[].annotations) + render-balik saat
%   eksperimen/garis dibuka ulang. Namespace `pivui.*`. Rilis-1 = tiga alat ini.
%
%   Anotasi MELEKAT pada GARIS PSG aktif (psgLines[].annotations) — bila garis
%   berbeda dipilih, anotasi yang ditampilkan berganti.
%
%   Bentuk serial (cocok jsonencode):
%     garis : struct('type','line',    'pos',[x1 y1; x2 y2], 'note',char)
%     titik : struct('type','point',   'pos',[x y],          'note',char)
%     ukur  : struct('type','measure', 'pos',[x1 y1; x2 y2], 'lengthPx',d, 'note',char)
%
%   API:
%     [ann, roi] = pivui.pab4Annot.create(ax, kind [, onDone])   % interaktif (drawline/point)
%     ann = pivui.pab4Annot.serialize(kind, pos [, note])
%     pivui.pab4Annot.draw(ax, ann)         % render STATIS (non-interaktif) satu anotasi
%     pivui.pab4Annot.drawAll(ax, annList)  % bersihkan + render daftar (cell/struct array)
%     pivui.pab4Annot.clear(ax)             % hapus semua anotasi tergambar
%     d   = pivui.pab4Annot.measureLen(pos)
%     s   = pivui.pab4Annot.summary(annList)
%
%   Penempatan berkas: PAB/pivcore_lib/+pivui/pab4Annot.m

    properties (Constant)
        TAG = 'pab4annot';
    end

    methods (Static)

        % =============================================================
        function [ann, roi] = create(ax, kind, onDone)
        %CREATE  Buat anotasi INTERAKTIF di axMain (klik). kind ∈ {line,point,
        %   measure}. Mengembalikan struct serial + handle ROI. onDone (opsional)
        %   dipanggil setelah selesai/digeser.
            ann = []; roi = [];
            if ~ishghandle(ax), return; end
            kind = lower(char(kind));
            col = pivui.pab4Annot.kindColor(kind);
            switch kind
                case 'point'
                    roi = drawpoint(ax, 'Color',col, 'Label','pt', 'LabelVisible','hover');
                    if isempty(roi) || ~isvalid(roi) || isempty(roi.Position), roi=[]; return; end
                    ann = pivui.pab4Annot.serialize('point', roi.Position);
                case {'line','measure'}
                    roi = drawline(ax, 'Color',col, 'LineWidth',1.6, ...
                        'Label',kind, 'LabelVisible','hover');
                    if isempty(roi) || ~isvalid(roi) || isempty(roi.Position), roi=[]; return; end
                    ann = pivui.pab4Annot.serialize(kind, roi.Position);
                otherwise
                    return;
            end
            if nargin >= 3 && ~isempty(onDone) && isa(onDone,'function_handle')
                addlistener(roi, 'ROIMoved', @(s,e) onDone());
            end
        end


        % =============================================================
        function ann = serialize(kind, pos, note)
        %SERIALIZE  Bentuk struct serial dari kind+pos (+catatan opsional).
            if nargin < 3, note = ''; end
            kind = lower(char(kind));
            ann = struct('type',kind, 'pos',double(pos), 'note',char(note));
            if strcmp(kind,'measure')
                ann.lengthPx = pivui.pab4Annot.measureLen(pos);
            end
        end


        % =============================================================
        function draw(ax, ann)
        %DRAW  Render STATIS satu anotasi (Tag pab4Annot.TAG) — non-interaktif,
        %   untuk pratinjau anotasi tersimpan. Tak mengganggu klik garis PSG.
            if ~ishghandle(ax) || ~isstruct(ann) || ~isfield(ann,'type'), return; end
            T = pivui.pab4Annot.TAG;
            hs = ishold(ax); hold(ax,'on');
            kind = lower(char(ann.type));
            col = pivui.pab4Annot.kindColor(kind);
            P = ann.pos;
            switch kind
                case 'point'
                    if numel(P) >= 2
                        plot(ax, P(1), P(2), 'o', 'MarkerSize',8, 'LineWidth',1.6, ...
                            'MarkerEdgeColor',col, 'MarkerFaceColor','none', ...
                            'Tag',T, 'HitTest','off','PickableParts','none');
                    end
                case {'line','measure'}
                    if size(P,1) >= 2
                        plot(ax, P(:,1), P(:,2), '-', 'Color',col, 'LineWidth',1.6, ...
                            'Tag',T, 'HitTest','off','PickableParts','none');
                        if strcmp(kind,'measure')
                            d = pivui.pab4Annot.measureLen(P);
                            text(ax, mean(P(:,1)), mean(P(:,2)), sprintf(' %.0f px', d), ...
                                'Color',col, 'FontSize',8, 'FontWeight','bold', ...
                                'Tag',T, 'HitTest','off','PickableParts','none');
                        end
                    end
            end
            if ~hs, hold(ax,'off'); end
        end


        function drawAll(ax, annList)
        %DRAWALL  Bersihkan anotasi lama lalu render semua di annList (cell atau
        %   struct-array).
            pivui.pab4Annot.clear(ax);
            L = pivui.pab4Annot.tolist(annList);
            for k = 1:numel(L), pivui.pab4Annot.draw(ax, L{k}); end
        end


        function clear(ax)
            if ~ishghandle(ax), return; end
            try, delete(findall(ax,'Tag',pivui.pab4Annot.TAG)); catch, end
        end


        function d = measureLen(pos)
            d = NaN;
            if size(pos,1) >= 2
                d = hypot(pos(2,1)-pos(1,1), pos(2,2)-pos(1,2));
            end
        end


        function s = summary(annList)
        %SUMMARY  Ringkas jumlah per jenis -> 'garis 2 · titik 1 · ukur 0'.
            L = pivui.pab4Annot.tolist(annList);
            nL=0; nP=0; nM=0;
            for k = 1:numel(L)
                a = L{k}; if ~isstruct(a) || ~isfield(a,'type'), continue; end
                switch lower(char(a.type))
                    case 'line', nL=nL+1;
                    case 'point', nP=nP+1;
                    case 'measure', nM=nM+1;
                end
            end
            s = sprintf('garis %d · titik %d · ukur %d', nL, nP, nM);
        end

    end


    methods (Static, Access = private)

        function col = kindColor(kind)
            switch lower(char(kind))
                case 'point',   col = [0.85 0.10 0.10];
                case 'measure', col = [0.55 0.15 0.75];
                otherwise,      col = [0.10 0.55 0.85];   % line
            end
        end

        function L = tolist(x)
            if isempty(x), L = {}; return; end
            if iscell(x), L = reshape(x,1,[]); return; end
            if isstruct(x)
                L = cell(1,numel(x)); for k=1:numel(x), L{k}=x(k); end
                return;
            end
            L = {x};
        end

    end
end
