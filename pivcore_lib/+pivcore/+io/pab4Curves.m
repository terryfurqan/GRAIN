classdef pab4Curves
%PAB4CURVES  Ekspor DATA NUMERIK kurva HW TERIDENTIFIKASI ke bundel Claude:
%   `PAB4_claude/<base>/curves.json`. Memberi Cowork (CLCW) konteks angka di
%   balik tiap `@curve:HW-N` di komentar — nilai |V| per-frame, puncak, titik
%   observasi, dan net-slip — supaya komentar tertaut ke data kuantitatif.
%
%   SKEMA:
%     formatName='PAB4 Curves'; formatVersion=1; source=<base.ext>;
%     psgId; nFrames; units; strainTotalPct; strainFormula;
%     curves[]  : { label, posPx, peakFrame, peakVal, cutFrame, values[] }
%     netslip[] : { hw, partner, start, nuc, fsr, end, area, dNet, values[] }
%
%   HANYA kurva ber-LABEL (HW/F/F0/FFW) yang non-excluded yang diekspor.
%   NaN -> JSON null. Penulisan ATOMIC. Penempatan: +pivcore/+io/pab4Curves.m

    methods (Static)

        function p = dataPath(dataFile)
            p = '';
            d = pivcore.io.pab4Comments.assetDir(dataFile);   % PAB4_claude/<base>/
            if isempty(d), return; end
            p = fullfile(d, 'curves.json');
        end


        function doc = emptyDoc(dataFile)
            [~, base, ext] = fileparts(char(dataFile));
            doc = struct();
            doc.formatName     = 'PAB4 Curves';
            doc.formatVersion  = 1;
            doc.source         = [base ext];
            doc.psgId          = '';
            doc.nFrames        = 0;
            doc.units          = 'px/frame';
            doc.strainTotalPct = NaN;
            doc.strainFormula  = 'strainPct(frame k) = (k-1)/(nFrames-1) * strainTotalPct';
            doc.curves         = {};
            doc.netslip        = {};
        end


        function c = curveStruct(label, posPx, peakFrame, peakVal, cutFrame, values)
        %CURVESTRUCT  Satu kurva teridentifikasi + deret nilai |V| per-frame.
            c = struct( ...
                'label',     char(label), ...
                'posPx',     pivcore.io.pab4Curves.num(posPx), ...
                'peakFrame', pivcore.io.pab4Curves.num(peakFrame), ...
                'peakVal',   pivcore.io.pab4Curves.num(peakVal), ...
                'cutFrame',  pivcore.io.pab4Curves.num(cutFrame), ...
                'values',    pivcore.io.pab4Curves.vec(values));
        end


        function write(dataFile, doc)
            p = pivcore.io.pab4Curves.dataPath(dataFile);
            if isempty(p)
                error('pivcore:pab4Curves:noPath','Tak bisa tentukan path curves: %s', dataFile);
            end
            d = fileparts(p); if ~isfolder(d), mkdir(d); end
            if ~iscell(doc.curves),  doc.curves  = pivcore.io.pab4Curves.tocell(doc.curves);  end
            if ~iscell(doc.netslip), doc.netslip = pivcore.io.pab4Curves.tocell(doc.netslip); end
            txt = jsonencode(doc, 'PrettyPrint', true);
            pivcore.io.pab4Curves.atomicWrite(p, txt);
        end


        function p = storyPath(dataFile)
            p = '';
            d = pivcore.io.pab4Comments.assetDir(dataFile);
            if isempty(d), return; end
            p = fullfile(d, 'hw_story.json');
        end


        function writeStory(dataFile, doc)
        %WRITESTORY  Tulis hw_story.json — paket cerita ber-anchor HW (kurva +
        %   titik + net-slip + gambar + komentar tertaut per HW).
            p = pivcore.io.pab4Curves.storyPath(dataFile);
            if isempty(p)
                error('pivcore:pab4Curves:noPath','Tak bisa tentukan path hw_story: %s', dataFile);
            end
            d = fileparts(p); if ~isfolder(d), mkdir(d); end
            if isfield(doc,'hangingWalls') && ~iscell(doc.hangingWalls)
                doc.hangingWalls = pivcore.io.pab4Curves.tocell(doc.hangingWalls);
            end
            txt = jsonencode(doc, 'PrettyPrint', true);
            pivcore.io.pab4Curves.atomicWrite(p, txt);
        end

    end


    methods (Static, Access = private)

        function v = num(x)
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end
        function v = vec(x)
            if isnumeric(x) && ~isempty(x), v = double(x(:).'); else, v = []; end
        end
        function c = tocell(x)
            if isempty(x), c = {}; return; end
            if iscell(x), c = reshape(x,1,[]); return; end
            if isstruct(x), c = cell(1,numel(x)); for k=1:numel(x), c{k}=x(k); end; return; end
            c = {x};
        end
        function atomicWrite(p, txt)
            tmp = [p '.tmp'];
            fid = fopen(tmp,'w');
            if fid < 0, error('pivcore:pab4Curves:open','Tak bisa tulis %s', tmp); end
            cleaner = onCleanup(@() pivcore.io.pab4Curves.rmTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char'); fclose(fid);
            [ok,msg] = movefile(tmp, p, 'f');
            if ~ok, error('pivcore:pab4Curves:move','Gagal tulis %s: %s', p, msg); end
        end
        function rmTmp(tmp), try, if isfile(tmp), delete(tmp); end, catch, end, end

    end
end
