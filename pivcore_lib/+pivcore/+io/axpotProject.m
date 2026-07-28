classdef axpotProject
%AXPOTPROJECT  Berkas PROYEK AX POT (.mat) — jembatan PAB4 -> editor figur
%   standalone PABAXPOT. Sengaja GEMBUNG: SELURUH informasi kurva AX POT masuk
%   (kurva mentah + teridentifikasi + titik + net-slip + indenter + garis PSG +
%   strain + geom). Yang TIDAK ikut = tumpukan frame piksel (frame tetap di .mat
%   sumber, cukup DIREFERENSIKAN via `source.dataFile` + `frameRefs`).
%
%   Tujuan: bercerita eksperimen lewat kurva AX POT sebagai "bigger picture",
%   lalu memproduksi RASTER (PNG/JPEG) grade-paper + JSON sidecar (bahan komentar).
%   Berkas ini juga jadi alat MEMESAN frame mana yang tampil di montage
%   (lewat `frameRefs`, diisi belakangan).
%
%   Skema (struct disimpan sebagai variabel `axpot` di .mat):
%     .formatName / .formatVersion
%     .savedAt                      (tanggal string)
%     .source   : struct(dataFile, base, pivDir)
%     .nFrames  / .units
%     .strainTotalPct / .strainFormula   (frame->strain kumulatif %; bisa negatif)
%     .psg      : struct(id, p1[1x2], p2[1x2])
%     .clim     : struct(velmag[1x2], shearAbs)
%     .indenter : [1xnF] envelope maksimum
%     .curves   : struct-array SEMUA kurva (mentah+berlabel):
%                 index,label,color[1x3],posPx,cutFrame,excluded,values[1xnF]
%     .hw       : struct-array HW TERIDENTIFIKASI (utk label/titik/montase):
%                 num,label,color[1x3],repValues[1xnF],startF,nclF,fsrF,endF,
%                 startStrainPct,nucStrainPct,fsrStrainPct,endStrainPct
%     .netslip  : struct-array (hw,partner,values[1xnF],area,dNet,start..end,units,convention)
%     .geom     : meta geom .mat sumber (apa adanya; boleh besar)
%     .frameRefs: [1xK] urutan frame utk montage (diisi nanti; default [])
%     .infoPoints: struct-array anotasi (diisi di PABAXPOT; default kosong)
%     .display  : struct setelan tampilan terakhir (diisi PABAXPOT; default kosong)
%
%   Penempatan: PAB/pivcore_lib/+pivcore/+io/axpotProject.m

    methods (Static)

        % ================================================================
        function p = empty(dataFile)
        %EMPTY  Proyek default/kosong (skema lengkap, nilai aman).
            if nargin < 1, dataFile = ''; end
            [d, base, ext] = pivcore.io.axpotProject.parts(dataFile);
            p = struct();
            p.formatName    = 'PAB AXPOT Project';
            p.formatVersion = 1;
            p.savedAt       = '';
            p.source        = struct('dataFile',char(dataFile), 'base',base, ...
                                     'pivDir',d, 'ext',ext);
            p.nFrames       = 0;
            p.units         = 'px/frame';
            p.strainTotalPct = NaN;
            p.strainFormula  = '(k-1)/(nF-1)*strainTotalPct';
            p.psg           = struct('id','', 'p1',[NaN NaN], 'p2',[NaN NaN]);
            p.clim          = struct('velmag',[0 5], 'shearAbs',1);
            p.indenter      = [];
            p.curves        = pivcore.io.axpotProject.emptyCurves();
            p.hw            = pivcore.io.axpotProject.emptyHW();
            p.netslip       = {};
            p.geom          = struct();
            p.frameRefs     = [];
            p.infoPoints    = pivcore.io.axpotProject.emptyInfo();
            p.display       = struct();
            % --- KALIBRASI sumbu-Y dunia nyata (px/frame -> cm/s) — 3 OPSI ---
            %   (paritas PAB Exporter: 'manual' cm/px÷dt · 'calxy' · 'geom' X0/X1+dt)
            %   timing  = waktu antar-frame (dt). source 'exif' bila terbaca EXIF
            %             saat ekspor PAB4; 'manual' bila di-override pengguna.
            %   geomCal = geometri global dari .mat PIV (experiment_geometry/calxy):
            %             dxCm=|X0-X1| cm, cmPerPx (calxy terkalibrasi), strainPct.
            %   ycal    = pilihan kalibrasi aktif: source + velMult (cm/s per
            %             px/frame) + override manual (cmPerPx,dt) + enabled + unit.
            p.timing        = struct('dtSec',NaN, 'source','none', ...
                                     'medianExifSec',NaN, 'nValidExif',0);
            p.geomCal       = struct('dxCm',NaN, 'cmPerPx',NaN, 'strainPct',NaN);
            p.ycal          = struct('source','geom', 'velMult',0.005, ...
                                     'cmPerPx',NaN, 'unit','cm/s', 'enabled',false);
            % --- SUMBER EDITAN (gembung): record POT mentah + titik observasi.
            %     Bila ada, PABAXPOT bisa MENGEDIT (trim/assign HW/buang) sama
            %     seperti PAB4; curves/hw/indenter = TURUNAN (deriveFromRecs).
            p.recs          = [];
            p.pts           = pivcore.pot.snapPoints.emptyPts();
        end


        % ================================================================
        function c = curveStruct(index, label, color, posPx, cutFrame, excluded, values)
        %CURVESTRUCT  Satu rekaman kurva (mentah/berlabel). values = |V| per-frame
        %   (sudah trim-applied bila kurva ter-trim).
            c = struct('index',double(index), 'label',char(label), ...
                'color',pivcore.io.axpotProject.col(color), ...
                'posPx',pivcore.io.axpotProject.sc(posPx), ...
                'cutFrame',pivcore.io.axpotProject.sc(cutFrame), ...
                'excluded',logical(excluded), ...
                'values',pivcore.io.axpotProject.row(values));
        end


        % ================================================================
        function w = hwStruct(num, label, color, repValues, pts, strainPcts)
        %HWSTRUCT  Satu HW teridentifikasi + kurva representatif + titik observasi.
        %   pts = struct(startF,nclF,fsrF,endF); strainPcts = struct(start,nuc,fsr,end).
            if nargin < 5 || ~isstruct(pts), pts = struct('startF',NaN,'nclF',NaN,'fsrF',NaN,'endF',NaN); end
            if nargin < 6 || ~isstruct(strainPcts), strainPcts = struct('start',NaN,'nuc',NaN,'fsr',NaN,'end',NaN); end
            g = @(s,f) pivcore.io.axpotProject.fld(s,f,NaN);
            w = struct('num',double(num), 'label',char(label), ...
                'color',pivcore.io.axpotProject.col(color), ...
                'repValues',pivcore.io.axpotProject.row(repValues), ...
                'startF',g(pts,'startF'), 'nclF',g(pts,'nclF'), ...
                'fsrF',g(pts,'fsrF'), 'endF',g(pts,'endF'), ...
                'startStrainPct',g(strainPcts,'start'), 'nucStrainPct',g(strainPcts,'nuc'), ...
                'fsrStrainPct',g(strainPcts,'fsr'), 'endStrainPct',g(strainPcts,'end'));
        end


        % ================================================================
        function ip = infoPointStruct(p)
        %INFOPOINTSTRUCT  Titik informasi (anotasi) — bisa "ngobrol" dgn PAB:
        %   frame (sumbu-x asli), strainPct, value (y), label teks, kind, color.
            if nargin < 1 || ~isstruct(p), p = struct(); end
            g  = @(f,d) pivcore.io.axpotProject.fld(p,f,d);
            ip = struct('id',char(g('id','')), 'kind',char(g('kind','mark')), ...
                'frame',pivcore.io.axpotProject.sc(g('frame',NaN)), ...
                'strainPct',pivcore.io.axpotProject.sc(g('strainPct',NaN)), ...
                'value',pivcore.io.axpotProject.sc(g('value',NaN)), ...
                'label',char(g('label','')), ...
                'color',pivcore.io.axpotProject.col(g('color',[0.1 0.1 0.1])), ...
                'hw',pivcore.io.axpotProject.sc(g('hw',NaN)));
        end


        % ================================================================
        function pth = defaultPath(dataFile)
        %DEFAULTPATH  <dir>/<base>_axpot.mat (di samping .mat sumber).
            [d, base] = pivcore.io.axpotProject.parts(dataFile);
            if isempty(base), pth = ''; return; end
            pth = fullfile(d, [base '_axpot.mat']);
        end


        % ================================================================
        function save(pth, proj)
        %SAVE  Tulis proyek (variabel `axpot`) ATOMIC (tmp -> movefile).
            if isempty(pth), error('pivcore:axpotProject:path','Path kosong'); end
            proj = pivcore.io.axpotProject.migrate(proj);
            d = fileparts(pth); if ~isempty(d) && ~isfolder(d), mkdir(d); end
            tmp = [pth '.tmp.mat'];
            axpot = proj; %#ok<NASGU>
            save(tmp, 'axpot', '-v7');
            [ok, msg] = movefile(tmp, pth, 'f');
            if ~ok
                try, if isfile(tmp), delete(tmp); end, catch, end
                error('pivcore:axpotProject:move','Gagal tulis %s: %s', pth, msg);
            end
        end


        % ================================================================
        function proj = load(pth)
        %LOAD  Baca proyek -> struct (migrasi/validasi skema). Error bila absen.
            if isempty(pth) || ~isfile(pth)
                error('pivcore:axpotProject:notfound','Berkas tak ada: %s', pth);
            end
            S = load(pth);
            if isfield(S,'axpot')
                proj = S.axpot;
            elseif isfield(S,'formatName') || isfield(S,'curves')
                proj = S;   % tersimpan sebagai field tersebar
            else
                error('pivcore:axpotProject:badfmt','Bukan berkas proyek AX POT: %s', pth);
            end
            proj = pivcore.io.axpotProject.migrate(proj);
        end


        % ================================================================
        function v = strainVec(proj)
        %STRAINVEC  Vektor strain kumulatif % per-frame [1xnF] (bisa negatif).
            n = pivcore.io.axpotProject.sc(proj.nFrames);
            st = pivcore.io.axpotProject.sc(proj.strainTotalPct);
            if ~(isfinite(n) && n > 1 && isfinite(st)), v = []; return; end
            v = (0:n-1) / (n-1) * st;
        end


        % ================================================================
        function [mult, info, ok] = velMult(proj, source)
        %VELMULT  Pengali |V| px/frame -> cm/s utk SUMBER tertentu (3 opsi, paritas
        %   PAB Exporter i_onAutoMult). Murni/headless. ok=false bila bahan kurang.
        %     'manual' : cmPerPx(override ycal) / dtSec(timing)
        %     'calxy'  : geomCal.cmPerPx (calxy terkalibrasi) / dtSec
        %     'geom'   : (dxCm/((nF-1)*dt)) / max(indenter)   [kalibrasi via indenter]
            ax = pivcore.io.axpotProject;
            yc = ax.fld(proj,'ycal',struct());     gc = ax.fld(proj,'geomCal',struct());
            tm = ax.fld(proj,'timing',struct());
            dt = ax.sc(ax.fld(tm,'dtSec',NaN));
            mult = NaN; info = ''; ok = false;
            switch lower(char(source))
                case 'manual'
                    cmpx = ax.sc(ax.fld(yc,'cmPerPx',NaN));
                    if isfinite(cmpx) && cmpx>0 && isfinite(dt) && dt>0
                        mult = cmpx/dt; info = sprintf('manual: %.4g cm/px ÷ %.4g s', cmpx, dt); ok = true;
                    else, info = 'manual: isi cm/px & dt';
                    end
                case 'calxy'
                    cmpx = ax.sc(ax.fld(gc,'cmPerPx',NaN));
                    if isfinite(cmpx) && cmpx>0 && isfinite(dt) && dt>0
                        mult = cmpx/dt; info = sprintf('calxy: %.4g cm/px ÷ %.4g s', cmpx, dt); ok = true;
                    else, info = 'calxy tak tersedia (calxy=1 / belum dikalibrasi)';
                    end
                otherwise   % geom
                    dxCm = ax.sc(ax.fld(gc,'dxCm',NaN));
                    nF   = ax.sc(ax.fld(proj,'nFrames',NaN));
                    indMax = NaN; env = ax.fld(proj,'indenter',[]);
                    if ~isempty(env), e = env(isfinite(env)); if ~isempty(e), indMax = max(e); end, end
                    if isfinite(dxCm) && dxCm>0 && isfinite(dt) && dt>0 && nF>1 ...
                            && isfinite(indMax) && indMax>0
                        vIndCmS = dxCm/((nF-1)*dt);
                        mult = vIndCmS/indMax; ok = true;
                        info = sprintf('geom: %.4gcm/%.4gs ÷ %.4gpx/fr', dxCm, (nF-1)*dt, indMax);
                    else, info = 'geom butuh |X0-X1| + dt + nF + indenter';
                    end
            end
        end


        % ================================================================
        function [f, lab, ok] = yFactor(proj, baseLabel)
        %YFACTOR  Pengali konversi sumbu-Y px/frame -> cm/s + label, JUJUR.
        %   Pakai ycal.velMult bila ada; else hitung dari ycal.source via velMult().
        %   f=1, label asli (px), ok=false bila ycal.enabled=false / bahan kurang
        %   (tak memunculkan angka metrik palsu). baseLabel = label Y mentah.
            if nargin < 2 || isempty(baseLabel), baseLabel = '|V| (px/frame)'; end
            f = 1; lab = baseLabel; ok = false;
            ax = pivcore.io.axpotProject;
            yc = ax.fld(proj,'ycal',struct());
            en = isfield(yc,'enabled') && isscalar(yc.enabled) && logical(yc.enabled);
            if ~en, return; end
            m = ax.sc(ax.fld(yc,'velMult',NaN));
            if ~(isfinite(m) && m > 0)
                src = 'geom'; if isfield(yc,'source') && ischar(yc.source), src = yc.source; end
                [m, ~, okc] = ax.velMult(proj, src);
                if ~okc, return; end
            end
            if ~(isfinite(m) && m > 0), return; end
            unit = 'cm/s'; if isfield(yc,'unit') && ischar(yc.unit) && ~isempty(yc.unit), unit = yc.unit; end
            f = m; ok = true; lab = sprintf('|V| (%s)', unit);
        end


        % ================================================================
        function proj = migrate(proj)
        %MIGRATE  Lengkapi field hilang dgn default (kompat maju-mundur).
            d = pivcore.io.axpotProject.empty('');
            if ~isstruct(proj), proj = d; return; end
            fn = fieldnames(d);
            for i = 1:numel(fn)
                if ~isfield(proj, fn{i}) || isempty(proj.(fn{i})) && ~ismember(fn{i}, {'indenter','frameRefs','netslip'})
                    if ~isfield(proj, fn{i}), proj.(fn{i}) = d.(fn{i}); end
                end
            end
            proj.formatName = 'PAB AXPOT Project';
        end


        % ================================================================
        function proj = deriveFromRecs(proj)
        %DERIVEFROMRECS  Hitung ULANG curves/hw/indenter dari proj.recs (+proj.pts).
        %   SINGLE-SOURCE: bila proj.recs ada, ITULAH kebenaran editan (trim/assign
        %   HW/buang dilakukan di atas recs); curves/hw/indenter cuma TURUNAN yang
        %   dipakai renderer. No-op bila recs kosong (proyek lama = read-only).
        %   Murni/headless — pakai engine pivcore.pot.* + helper trim/excluded lokal
        %   (TANPA ketergantungan ke pivui, supaya tetap engine).
            if ~isfield(proj,'recs') || isempty(proj.recs), return; end
            recs = pivcore.pot.records.normalize(proj.recs);
            proj.recs = recs;
            ax = pivcore.io.axpotProject;
            nF = ax.sc(proj.nFrames);
            if ~(isfinite(nF) && nF >= 1)
                nF = 1;
                for r = 1:numel(recs)
                    [~, yv] = pivcore.pot.records.curveXY(recs(r), nF);
                    nF = max(nF, numel(yv));
                end
                proj.nFrames = nF;
            end
            % --- indenter = envelope MAX kurva non-buang (trim diterapkan) ---
            M = -inf(1, nF); any_ = false;
            for r = 1:numel(recs)
                if ax.recExcluded(recs(r)), continue; end
                [~, yv] = pivcore.pot.records.curveXY(recs(r), nF);
                yv = ax.trimYV(recs(r), yv);
                if isempty(yv), continue; end
                m = numel(yv); seg = M(1:m); g = isfinite(yv);
                seg(g) = max(seg(g), yv(g)); M(1:m) = seg; any_ = true;
            end
            if any_, M(~isfinite(M)) = NaN; proj.indenter = M; else, proj.indenter = []; end
            % --- curves: SEMUA record (mentah+berlabel), trim-applied ---
            C = ax.emptyCurves();
            for r = 1:numel(recs)
                rec = recs(r);
                [~, yv] = pivcore.pot.records.curveXY(rec, nF);
                yv = ax.trimYV(rec, yv);
                lab = pivcore.pot.records.label(rec);
                col = rec.color; if numel(col) ~= 3, col = [0.4 0.4 0.4]; end
                px = NaN; if isfield(rec,'posPx') && isscalar(rec.posPx), px = rec.posPx; end
                cf = NaN; if isfield(rec,'cutFrame') && isscalar(rec.cutFrame), cf = rec.cutFrame; end
                C(end+1) = ax.curveStruct(r, lab, col, px, cf, ax.recExcluded(rec), yv); %#ok<AGROW>
            end
            proj.curves = C;
            % --- hw teridentifikasi: rep curve + titik + strain% ---
            pts = proj.pts; if ~isstruct(pts), pts = pivcore.pot.snapPoints.emptyPts(); end
            recsHW = ax.recsForHW(recs);
            nums = pivcore.pot.hwLabel.hwNumbers(recsHW);
            st = ax.sc(proj.strainTotalPct);
            W = ax.emptyHW();
            for num = nums
                rows = pivcore.pot.hwLabel.rowsForHW(recsHW, num);
                if isempty(rows), continue; end
                rep = pivcore.pot.netslip.repVec( ...
                    pivcore.pot.hwLabel.groupCurves(recsHW, rows, nF), nF);
                row = pivcore.pot.snapPoints.getHW(pts, num);
                if isempty(row), row = struct('startF',NaN,'nclF',NaN,'fsrF',NaN,'endF',NaN); end
                col = pivcore.pot.labels.labelColor('HW', num);
                sp = struct('start',ax.strainAt(row.startF,nF,st), 'nuc',ax.strainAt(row.nclF,nF,st), ...
                    'fsr',ax.strainAt(row.fsrF,nF,st), 'end',ax.strainAt(row.endF,nF,st));
                W(end+1) = ax.hwStruct(num, sprintf('HW-%d',num), col, rep, row, sp); %#ok<AGROW>
            end
            proj.hw = W;
        end

    end


    % =================================================================
    methods (Static, Access = private)

        function [d, base, ext] = parts(dataFile)
            d = ''; base = ''; ext = '';
            if ~isempty(dataFile) && (ischar(dataFile) || isstring(dataFile))
                [d, base, ext] = fileparts(char(dataFile));
            end
        end

        function c = emptyCurves()
            c = struct('index',{}, 'label',{}, 'color',{}, 'posPx',{}, ...
                'cutFrame',{}, 'excluded',{}, 'values',{});
        end
        function w = emptyHW()
            w = struct('num',{}, 'label',{}, 'color',{}, 'repValues',{}, ...
                'startF',{}, 'nclF',{}, 'fsrF',{}, 'endF',{}, ...
                'startStrainPct',{}, 'nucStrainPct',{}, 'fsrStrainPct',{}, 'endStrainPct',{});
        end
        function ip = emptyInfo()
            ip = struct('id',{}, 'kind',{}, 'frame',{}, 'strainPct',{}, ...
                'value',{}, 'label',{}, 'color',{}, 'hw',{});
        end

        function v = sc(x)   % scalar numeric atau NaN
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end
        function v = row(x)  % vektor baris double
            if isnumeric(x) && ~isempty(x), v = double(x(:).'); else, v = []; end
        end
        function c = col(x)  % warna [1x3]
            if isnumeric(x) && numel(x)==3, c = double(x(:).'); else, c = [0.4 0.4 0.4]; end
        end
        function v = fld(s, f, dflt)
            v = dflt; if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); end
        end

    end


    % =================================================================
    %  Helper EDIT (dipakai deriveFromRecs) — clean-room kecil dari
    %  pivui.pab4Shell supaya engine TAK bergantung ke lapisan UI.
    methods (Static)
        function tf = recExcluded(rec)
        %RECEXCLUDED  True bila record kurva ditandai DIBUANG (non-destruktif).
            tf = isstruct(rec) && isfield(rec,'excluded') && isscalar(rec.excluded) ...
                && logical(rec.excluded);
        end
        function yv = trimYV(rec, yv)
        %TRIMYV  NaN-kan deret SETELAH frame potong bila record ditandai trim.
            if ~(isstruct(rec) && isfield(rec,'cutManual') && isscalar(rec.cutManual) ...
                    && logical(rec.cutManual)), return; end
            df = NaN;
            if isfield(rec,'cutFrame') && isscalar(rec.cutFrame) && isfinite(rec.cutFrame)
                df = rec.cutFrame;
            end
            if isfinite(df) && df >= 1 && df < numel(yv), yv(df+1:end) = NaN; end
        end
        function R = recsForHW(recs)
        %RECSFORHW  Salinan recs: kurva DIBUANG -> label dikosongkan (keluar dari
        %   perhitungan HW). Panjang/urutan DIPERTAHANKAN.
            R = recs;
            for r = 1:numel(R)
                if pivcore.io.axpotProject.recExcluded(R(r))
                    R(r).assignLabel = '';
                    if isfield(R(r),'point'), R(r).point = ''; end
                end
            end
        end
        function s = strainAt(f, nF, st)
        %STRAINAT  Strain kumulatif % di frame f: (f-1)/(nF-1)*st. NaN bila tak sah.
            s = NaN;
            if isscalar(f) && isfinite(f) && nF > 1 && isfinite(st)
                s = (f-1)/(nF-1)*st;
            end
        end
    end
end
