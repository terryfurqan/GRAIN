classdef grainLink
%GRAINLINK  "Georeferensi" strain↔frame yang MENGIKAT dua MAT PIV — view acuan
%   (penampang, geometri X0/X1/Lpos diketahui = strain Truth) dengan view target
%   (tampak peta, tanpa geometri). Sidecar `<tgt_base>_link.json` di folder yang
%   sama dengan MAT TARGET. INI kebenaran milik GRAINLINK/GRAINSYNC. MAT PIV biner &
%   sidecar GRAIN4/GRAIN5 TIDAK disentuh.
%
%   KONSEP. Peristiwa sesar yang sama (FSR pertama & FSR terakhir) terlihat di
%   kedua view pada momen fisik yang sama → strain yang sama. Strain acuan per
%   frame bersifat LINEAR (rumus kanonik GRAIN4/GRAIN5):
%       sRef(f) = (f-1)/(nFref-1) * strainTotalPct       (bertanda; bisa negatif)
%   Tiap titik ikat menyimpan refFrame (frame FSR di penampang) + tgtFrame (frame
%   FSR di peta); strain titik ikat = sRef(refFrame) (dihitung otomatis). Dengan 2
%   titik ikat, kalibrasi target = linear 2-titik melalui (tgtFrame_k, refStrain_k):
%       b        = (s2 - s1) / (fT2 - fT1)               (% strain per frame, peta)
%       sTgt(f)  = s1 + b*(f - fT1)                      (interp + ekstrapolasi)
%       fTgt(s)  = fT1 + (s - s1)/b                      (inverse)
%
%   Semua perbandingan tanda-aman (`~=0`, bukan `>0`) karena strain bisa negatif
%   (shortening — normal sandbox anjak). `calibration` DITURUNKAN ULANG dari
%   tiePoints saat read → tak pernah basi; di-cache untuk inspeksi/kanal Claude.
%
%   Penulisan WAJIB ATOMIC (tmp -> movefile). NaN <-> JSON null.
%
%   API:
%     p    = pivcore.io.grainLink.dataPath(tgtFile)
%     doc  = pivcore.io.grainLink.emptyDoc(refFile, tgtFile)
%     doc  = pivcore.io.grainLink.read(tgtFile)            % [] -> emptyDoc + calibrate
%     pivcore.io.grainLink.write(tgtFile, doc)             % ATOMIC
%     tie  = pivcore.io.grainLink.tieStruct(name, refFrame, refStrainPct, tgtFrame)
%     doc  = pivcore.io.grainLink.setTie(doc, tie)         % kunci = name
%     doc  = pivcore.io.grainLink.calibrate(doc)           % isi doc.calibration
%     s    = pivcore.io.grainLink.strainAtRef(doc, f)      % strain% di frame ref
%     f    = pivcore.io.grainLink.frameAtRef(doc, s)       % frame ref di strain%
%     s    = pivcore.io.grainLink.strainAtTgt(doc, f)      % strain% di frame tgt
%     f    = pivcore.io.grainLink.frameAtTgt(doc, s)       % frame tgt di strain%
%     T    = pivcore.io.grainLink.syncTable(doc, strainVec)% struct[].strainPct/frameRef/frameTgt
%     v    = pivcore.io.grainLink.defaultStrainVec(doc, step)
%     info = pivcore.io.grainLink.geomInfo(matFile)        % baca experiment_geometry
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivcore/+io/grainLink.m

    methods (Static)

        % ================================================================
        function p = dataPath(tgtFile)
        %DATAPATH  <dir>/<tgt_base>_link.json untuk MAT PIV TARGET (peta).
            p = '';
            if isempty(tgtFile) || ~ischar(tgtFile), return; end
            [d, base] = fileparts(tgtFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_link.json', base));
        end


        % ================================================================
        function doc = emptyDoc(refFile, tgtFile)
        %EMPTYDOC  Kerangka dokumen kosong (satuan pct/frame, signed).
            if nargin < 1, refFile = ''; end
            if nargin < 2, tgtFile = ''; end
            [~, rb] = fileparts(char(refFile));
            [~, tb] = fileparts(char(tgtFile));
            doc = struct();
            doc.formatName     = 'GRAIN Link (georef strain<->frame)';
            doc.formatVersion  = 1;
            doc.reference = struct('path',char(refFile), 'basename',rb, ...
                'nFrames',NaN, 'strainTotalPct',NaN, 'geomValid',false, ...
                'X0_cm',NaN, 'X1_cm',NaN, 'Lpos_cm',NaN);
            doc.target = struct('path',char(tgtFile), 'basename',tb, ...
                'nFrames',NaN, 'geomValid',false);
            doc.tiePoints   = {};   % cell of tieStruct (kunci = name)
            doc.calibration = pivcore.io.grainLink.emptyCalib();
            doc.units          = 'pct/frame';
            doc.signConvention = 'signed';
        end


        % ================================================================
        function doc = read(tgtFile)
        %READ  Baca + NORMALISASI + KALIBRASI ULANG sidecar. Tak ada berkas ->
        %   emptyDoc. Rusak -> emptyDoc + warning (tak melempar agar GUI jalan).
            p = pivcore.io.grainLink.dataPath(tgtFile);
            if isempty(p) || ~isfile(p)
                doc = pivcore.io.grainLink.emptyDoc('', tgtFile); return;
            end
            try
                txt = fileread(p);
                raw = jsondecode(txt);
            catch ME
                warning('pivcore:grainLink:read', ...
                    'Gagal membaca/parse %s (%s); pakai dokumen kosong.', p, ME.message);
                doc = pivcore.io.grainLink.emptyDoc('', tgtFile); return;
            end
            doc = pivcore.io.grainLink.normalizeDoc(raw, tgtFile);
            doc = pivcore.io.grainLink.calibrate(doc);   % derive (tak pernah basi)
        end


        % ================================================================
        function write(tgtFile, doc)
        %WRITE  Tulis dokumen ke `<tgt_base>_link.json` secara ATOMIC.
            p = pivcore.io.grainLink.dataPath(tgtFile);
            if isempty(p)
                error('pivcore:grainLink:noPath', ...
                    'Tak bisa menentukan path _link untuk: %s', tgtFile);
            end
            doc = pivcore.io.grainLink.calibrate(doc);     % cache derivatif
            doc = pivcore.io.grainLink.prepForEncode(doc);
            txt = jsonencode(doc, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0
                error('pivcore:grainLink:open', 'Tak bisa membuka %s utk tulis.', tmp);
            end
            cleaner = onCleanup(@() pivcore.io.grainLink.cleanupTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
            fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok
                error('pivcore:grainLink:move', ...
                    'Gagal memindah tmp->final (%s): %s', p, msg);
            end
        end


        % ================================================================
        function tie = tieStruct(name, refFrame, refStrainPct, tgtFrame)
        %TIESTRUCT  Skeleton satu titik ikat.
            if nargin < 2, refFrame     = NaN; end
            if nargin < 3, refStrainPct = NaN; end
            if nargin < 4, tgtFrame     = NaN; end
            tie = struct('name', char(name), ...
                'refFrame',     pivcore.io.grainLink.scal(refFrame), ...
                'refStrainPct', pivcore.io.grainLink.scal(refStrainPct), ...
                'tgtFrame',     pivcore.io.grainLink.scal(tgtFrame));
        end


        % ================================================================
        function doc = setTie(doc, tie)
        %SETTIE  Sisipkan/ganti titik ikat ber-name sama (name = kunci stabil).
            if ~isstruct(doc), doc = pivcore.io.grainLink.emptyDoc('',''); end
            if ~isfield(doc,'tiePoints') || ~iscell(doc.tiePoints), doc.tiePoints = {}; end
            idx = 0;
            for k = 1:numel(doc.tiePoints)
                tk = doc.tiePoints{k};
                if isstruct(tk) && isfield(tk,'name') && strcmp(tk.name, tie.name)
                    idx = k; break;
                end
            end
            if idx > 0, doc.tiePoints{idx} = tie; else, doc.tiePoints{end+1} = tie; end
        end


        % ================================================================
        function doc = calibrate(doc)
        %CALIBRATE  Turunkan doc.calibration dari geometri acuan + 2 titik ikat.
        %   refStrainPct tiap tie DIHITUNG ULANG dari refFrame (anti-basi).
            cal = pivcore.io.grainLink.emptyCalib();
            nFref = pivcore.io.grainLink.scal(doc.reference.nFrames);
            stp   = pivcore.io.grainLink.scal(doc.reference.strainTotalPct);
            if isfinite(nFref) && nFref > 1 && isfinite(stp)
                cal.refStrainPerFrame = stp / (nFref - 1);
            end

            % Hitung ulang strain acuan tiap titik ikat dari refFrame.
            for k = 1:numel(doc.tiePoints)
                t = doc.tiePoints{k};
                t.refStrainPct = pivcore.io.grainLink.strainAtRef(doc, t.refFrame);
                doc.tiePoints{k} = t;
            end

            if numel(doc.tiePoints) >= 2
                t1 = doc.tiePoints{1}; t2 = doc.tiePoints{2};
                s1 = pivcore.io.grainLink.scal(t1.refStrainPct);
                s2 = pivcore.io.grainLink.scal(t2.refStrainPct);
                f1 = pivcore.io.grainLink.scal(t1.tgtFrame);
                f2 = pivcore.io.grainLink.scal(t2.tgtFrame);
                if all(isfinite([s1 s2 f1 f2])) && (f2 ~= f1)
                    b = (s2 - s1) / (f2 - f1);
                    if isfinite(b) && b ~= 0
                        cal.slopePctPerFrame = b;
                        cal.frame0  = f1;
                        cal.strain0 = s1;
                        cal.valid   = true;
                    end
                end
            end
            doc.calibration = cal;
        end


        % ================================================================
        function s = strainAtRef(doc, f)
        %STRAINATREF  Strain kumulatif (%) di frame f view ACUAN (linear geometri).
            s = NaN;
            nF  = pivcore.io.grainLink.scal(doc.reference.nFrames);
            stp = pivcore.io.grainLink.scal(doc.reference.strainTotalPct);
            f   = pivcore.io.grainLink.scal(f);
            if ~isfinite(f) || ~isfinite(stp), return; end
            if ~isfinite(nF) || nF <= 1, s = stp; else, s = (f-1)/(nF-1) * stp; end
        end


        % ================================================================
        function f = frameAtRef(doc, s)
        %FRAMEATREF  Frame view ACUAN pada strain% s (inverse strainAtRef).
            f = NaN;
            nF  = pivcore.io.grainLink.scal(doc.reference.nFrames);
            stp = pivcore.io.grainLink.scal(doc.reference.strainTotalPct);
            s   = pivcore.io.grainLink.scal(s);
            if ~isfinite(s), return; end
            if isfinite(nF) && nF <= 1, f = 1; return; end
            if isfinite(nF) && nF > 1 && isfinite(stp) && stp ~= 0
                f = 1 + s/stp * (nF-1);
            end
        end


        % ================================================================
        function s = strainAtTgt(doc, f)
        %STRAINATTGT  Strain kumulatif (%) di frame f view TARGET (kalibrasi linear).
            s = NaN;
            cal = doc.calibration; f = pivcore.io.grainLink.scal(f);
            if isstruct(cal) && isfield(cal,'valid') && cal.valid && isfinite(f)
                s = cal.strain0 + cal.slopePctPerFrame * (f - cal.frame0);
            end
        end


        % ================================================================
        function f = frameAtTgt(doc, s)
        %FRAMEATTGT  Frame view TARGET pada strain% s (inverse strainAtTgt).
            f = NaN;
            cal = doc.calibration; s = pivcore.io.grainLink.scal(s);
            if isstruct(cal) && isfield(cal,'valid') && cal.valid && isfinite(s) ...
                    && cal.slopePctPerFrame ~= 0
                f = cal.frame0 + (s - cal.strain0) / cal.slopePctPerFrame;
            end
        end


        % ================================================================
        function T = syncTable(doc, strainVec)
        %SYNCTABLE  Untuk tiap strain% -> frame acuan & frame target (bulat, clamp).
            T = struct('strainPct',{},'frameRef',{},'frameTgt',{});
            if nargin < 2 || isempty(strainVec), return; end
            strainVec = double(strainVec(:)).';
            for i = 1:numel(strainVec)
                s  = strainVec(i);
                fR = pivcore.io.grainLink.clampFrame( ...
                        pivcore.io.grainLink.frameAtRef(doc, s), doc.reference.nFrames);
                fT = pivcore.io.grainLink.clampFrame( ...
                        pivcore.io.grainLink.frameAtTgt(doc, s), doc.target.nFrames);
                T(end+1) = struct('strainPct',s, 'frameRef',fR, 'frameTgt',fT); %#ok<AGROW>
            end
        end


        % ================================================================
        function v = defaultStrainVec(doc, step)
        %DEFAULTSTRAINVEC  Rentang strain% (bulat ke `step`) yang mencakup ujung
        %   kedua view. Tanda-aman (shortening: rentang negatif).
            if nargin < 2 || ~isfinite(step) || step <= 0, step = 1; end
            s = [pivcore.io.grainLink.strainAtRef(doc, 1), ...
                 pivcore.io.grainLink.strainAtRef(doc, doc.reference.nFrames), ...
                 pivcore.io.grainLink.strainAtTgt(doc, 1), ...
                 pivcore.io.grainLink.strainAtTgt(doc, doc.target.nFrames)];
            s = s(isfinite(s));
            if isempty(s), v = []; return; end
            lo = floor(min(s)/step)*step;
            hi = ceil(max(s)/step)*step;
            if hi < lo, t = lo; lo = hi; hi = t; end
            v = lo:step:hi;
            if isempty(v), v = lo; end
        end


        % ================================================================
        function info = geomInfo(matFile)
        %GEOMINFO  Baca experiment_geometry dari MAT PIV (tanpa muat blob besar).
            info = struct('strainTotalPct',NaN, 'X0_cm',NaN, 'X1_cm',NaN, ...
                'Lpos_cm',NaN, 'valid',false);
            if isempty(matFile) || ~ischar(matFile) || ~isfile(matFile), return; end
            try
                w = whos('-file', matFile);
                if ~ismember('experiment_geometry', {w.name}), return; end
                S = load(matFile, 'experiment_geometry');
                g = S.experiment_geometry;
                if ~isstruct(g), return; end
                if isfield(g,'strain_cumm_pct'), info.strainTotalPct = pivcore.io.grainLink.scal(g.strain_cumm_pct); end
                if isfield(g,'X0_cm'),   info.X0_cm   = pivcore.io.grainLink.scal(g.X0_cm); end
                if isfield(g,'X1_cm'),   info.X1_cm   = pivcore.io.grainLink.scal(g.X1_cm); end
                if isfield(g,'Lpos_cm'), info.Lpos_cm = pivcore.io.grainLink.scal(g.Lpos_cm); end
                if isfield(g,'valid'),   info.valid   = logical(g.valid); end
            catch
            end
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function cal = emptyCalib()
            cal = struct('model','linear-2pt', 'slopePctPerFrame',NaN, ...
                'frame0',NaN, 'strain0',NaN, 'refStrainPerFrame',NaN, 'valid',false);
        end


        function fr = clampFrame(f, nF)
            fr = NaN;
            f = pivcore.io.grainLink.scal(f);
            if ~isfinite(f), return; end
            fr = round(f);
            nF = pivcore.io.grainLink.scal(nF);
            if isfinite(nF) && nF >= 1, fr = min(max(fr, 1), nF); else, fr = max(fr, 1); end
        end


        function doc = normalizeDoc(raw, tgtFile)
            d = pivcore.io.grainLink.emptyDoc('', tgtFile);
            if ~isstruct(raw), doc = d; return; end
            doc = d;
            for fn = {'formatName','formatVersion','units','signConvention'}
                k = fn{1};
                if isfield(raw, k), doc.(k) = raw.(k); end
            end
            if isfield(raw,'reference') && isstruct(raw.reference)
                doc.reference = pivcore.io.grainLink.normRef(raw.reference, doc.reference);
            end
            if isfield(raw,'target') && isstruct(raw.target)
                doc.target = pivcore.io.grainLink.normTgt(raw.target, doc.target);
            end
            ties = {};
            if isfield(raw,'tiePoints')
                src = pivcore.io.grainLink.tocell(raw.tiePoints);
                for k = 1:numel(src)
                    ties{end+1} = pivcore.io.grainLink.normTie(src{k}); %#ok<AGROW>
                end
            end
            doc.tiePoints = ties;
            % calibration di-derive ulang oleh read(); biarkan default di sini.
        end


        function r = normRef(s, r)
            if isfield(s,'path')           && ischar(s.path),     r.path     = s.path; end
            if isfield(s,'basename')       && ischar(s.basename), r.basename = s.basename; end
            if isfield(s,'nFrames'),        r.nFrames        = pivcore.io.grainLink.scal(s.nFrames); end
            if isfield(s,'strainTotalPct'), r.strainTotalPct = pivcore.io.grainLink.scal(s.strainTotalPct); end
            if isfield(s,'geomValid'),      r.geomValid      = logical(s.geomValid); end
            if isfield(s,'X0_cm'),          r.X0_cm          = pivcore.io.grainLink.scal(s.X0_cm); end
            if isfield(s,'X1_cm'),          r.X1_cm          = pivcore.io.grainLink.scal(s.X1_cm); end
            if isfield(s,'Lpos_cm'),        r.Lpos_cm        = pivcore.io.grainLink.scal(s.Lpos_cm); end
        end


        function t = normTgt(s, t)
            if isfield(s,'path')     && ischar(s.path),     t.path     = s.path; end
            if isfield(s,'basename') && ischar(s.basename), t.basename = s.basename; end
            if isfield(s,'nFrames'),   t.nFrames   = pivcore.io.grainLink.scal(s.nFrames); end
            if isfield(s,'geomValid'), t.geomValid = logical(s.geomValid); end
        end


        function t = normTie(s)
            t = pivcore.io.grainLink.tieStruct('', NaN, NaN, NaN);
            if ~isstruct(s), return; end
            if isfield(s,'name') && ischar(s.name), t.name = s.name; end
            if isfield(s,'refFrame'),     t.refFrame     = pivcore.io.grainLink.scal(s.refFrame); end
            if isfield(s,'refStrainPct'), t.refStrainPct = pivcore.io.grainLink.scal(s.refStrainPct); end
            if isfield(s,'tgtFrame'),     t.tgtFrame     = pivcore.io.grainLink.scal(s.tgtFrame); end
        end


        function doc = prepForEncode(doc)
            d = pivcore.io.grainLink.emptyDoc('','');
            fn = fieldnames(d);
            for i = 1:numel(fn)
                if ~isfield(doc, fn{i}), doc.(fn{i}) = d.(fn{i}); end
            end
            if ~iscell(doc.tiePoints)
                doc.tiePoints = pivcore.io.grainLink.tocell(doc.tiePoints);
            end
        end


        % --- helper tipe ---------------------------------------------
        function c = tocell(x)
            if isempty(x), c = {}; return; end
            if iscell(x), c = reshape(x, 1, []); return; end
            if isstruct(x)
                c = cell(1, numel(x));
                for k = 1:numel(x), c{k} = x(k); end
                return;
            end
            c = {x};
        end


        function v = scal(x)
            if (isnumeric(x) || islogical(x)) && isscalar(x)
                v = double(x);
            else
                v = NaN;
            end
        end


        function cleanupTmp(tmp)
            try, if isfile(tmp), delete(tmp); end, catch, end
        end

    end
end
