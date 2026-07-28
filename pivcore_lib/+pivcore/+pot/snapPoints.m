classdef snapPoints
%SNAPPOINTS  Titik observasi POT Start/NUC/FSR/END per Hanging Wall — snap ke
%   kurva + normalisasi struct. RE-IMPLEMENTASI CLEAN-ROOM dari pola PIVTerry
%   tabStep4 (dibaca read-only; TIDAK dipanggil lintas-folder). Murni/headless.
%
%   Tiap titik = INDEKS FRAME (1..nF), bukan nilai kurva. Skema record per-HW
%   SAMA dgn pivcore.io.step1Session.saveStep4Points/loadStep4Points (kompat):
%       struct('hw', startF, nclF, fsrF, endF)   % NaN = belum ditandai
%
%   SNAP-TO-CURVE (klik dekat kurva): frame = round(x-klik), clip [1,nF]; bila
%   nilai kurva di frame itu NaN -> cari frame BERHINGGA terdekat (pencarian
%   linier argmin|gi-f|). TANPA interpolasi (snap ke frame diskret).
%
%   API:
%     f   = pivcore.pot.snapPoints.snapFrame(yv, fClick)
%     p   = pivcore.pot.snapPoints.emptyPts()
%     p   = pivcore.pot.snapPoints.normalize(p)
%     p   = pivcore.pot.snapPoints.setPoint(p, hwNum, which, frame)  % which: start/nuc/fsr/end
%     row = pivcore.pot.snapPoints.getHW(p, hwNum)                   % [] bila tak ada
%     tf  = pivcore.pot.snapPoints.hasAny(p)
%     F   = pivcore.pot.snapPoints.fields()      % {'startF','nclF','fsrF','endF'}
%     col = pivcore.pot.snapPoints.color(which)  % warna marker titik
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivcore/+pot/snapPoints.m

    methods (Static)

        % ================================================================
        function f = snapFrame(yv, fClick)
        %SNAPFRAME  Frame ter-snap di kurva yv (1xN) dari klik fClick. NaN bila
        %   kurva kosong/seluruhnya non-finite.
            f = NaN;
            yv = yv(:).';
            n = numel(yv);
            if n == 0, return; end
            fc = round(fClick);
            if ~isfinite(fc), fc = 1; end
            fc = max(1, min(n, fc));
            if isfinite(yv(fc)), f = fc; return; end
            gi = find(isfinite(yv));
            if isempty(gi), return; end
            [~, jj] = min(abs(gi - fc));
            f = gi(jj);
        end


        % ================================================================
        function p = emptyPts()
        %EMPTYPTS  Array titik kosong (0x0) berskema lengkap.
            p = struct('hw',{}, 'startF',{}, 'nclF',{}, 'fsrF',{}, 'endF',{});
        end


        % ================================================================
        function p = normalize(p)
        %NORMALIZE  Pastikan field hw/startF/nclF/fsrF/endF ADA & skalar (NaN
        %   bila kosong). Robust thd struct minimal/lama.
            if isempty(p) || ~isstruct(p), p = pivcore.pot.snapPoints.emptyPts(); return; end
            defs = {'hw',NaN, 'startF',NaN, 'nclF',NaN, 'fsrF',NaN, 'endF',NaN};
            for k = 1:2:numel(defs)
                if ~isfield(p, defs{k}), [p.(defs{k})] = deal(defs{k+1}); end
            end
            for i = 1:numel(p)
                for k = 1:2:numel(defs)
                    v = p(i).(defs{k});
                    if ~isscalar(v) || ~isnumeric(v), p(i).(defs{k}) = defs{k+1}; end
                end
            end
        end


        % ================================================================
        function p = setPoint(p, hwNum, which, frame)
        %SETPOINT  Tetapkan frame untuk titik `which` pada HW hwNum (buat baris
        %   HW bila belum ada). which ∈ {start,nuc,fsr,end}. frame NaN = hapus.
            p = pivcore.pot.snapPoints.normalize(p);
            fld = pivcore.pot.snapPoints.whichField(which);
            if isempty(fld)
                error('pivcore:snapPoints:which', ...
                    'which harus start/nuc/fsr/end (diberi: %s).', char(which));
            end
            idx = pivcore.pot.snapPoints.hwIndex(p, hwNum);
            if idx == 0
                row = struct('hw',hwNum, 'startF',NaN, 'nclF',NaN, 'fsrF',NaN, 'endF',NaN);
                if isempty(p), p = row; else, p(end+1) = orderfields(row, p(1)); end
                idx = numel(p);
            end
            if nargin < 4, frame = NaN; end
            p(idx).(fld) = frame;
        end


        % ================================================================
        function row = getHW(p, hwNum)
        %GETHW  Baris titik untuk HW hwNum ([] bila tak ada).
            row = [];
            idx = pivcore.pot.snapPoints.hwIndex(p, hwNum);
            if idx > 0, row = p(idx); end
        end


        function tf = hasAny(p)
        %HASANY  TRUE bila ada >=1 titik (Start/NUC/FSR/END) terisi di salah satu HW.
            tf = false;
            p = pivcore.pot.snapPoints.normalize(p);
            F = pivcore.pot.snapPoints.fields();
            for i = 1:numel(p)
                for k = 1:numel(F)
                    v = p(i).(F{k});
                    if isscalar(v) && isfinite(v), tf = true; return; end
                end
            end
        end


        function F = fields()
            F = {'startF','nclF','fsrF','endF'};
        end


        function L = labels()
            L = {'Start','NUC','FSR','END'};
        end


        function fld = whichField(which)
        %WHICHFIELD  start->startF, nuc->nclF, fsr->fsrF, end->endF ('' bila asing).
            switch lower(char(which))
                case 'start', fld = 'startF';
                case 'nuc',   fld = 'nclF';
                case 'fsr',   fld = 'fsrF';
                case 'end',   fld = 'endF';
                otherwise,    fld = '';
            end
        end


        function col = color(which)
        %COLOR  Warna marker titik (sama pola tabStep4).
            switch lower(char(which))
                case {'start','startf'}, col = [0 0 0];
                case {'nuc','nclf'},     col = [0.10 0.35 0.90];   % NUC-D biru
                case {'nuct'},           col = [0.55 0.15 0.75];   % NUC-T ungu (teoritis)
                case {'fsr','fsrf'},     col = [0.10 0.60 0.20];   % FSR-D hijau
                case {'fsrt'},           col = [0.40 0.80 0.35];   % FSR-T hijau muda (teoritis)
                case {'end','endf'},     col = [0.95 0.75 0.00];
                otherwise,               col = [0.4 0.4 0.4];
            end
        end

    end


    methods (Static, Access = private)

        function idx = hwIndex(p, hwNum)
            idx = 0;
            for i = 1:numel(p)
                if isfield(p(i),'hw') && isscalar(p(i).hw) && p(i).hw == hwNum
                    idx = i; return;
                end
            end
        end

    end
end
