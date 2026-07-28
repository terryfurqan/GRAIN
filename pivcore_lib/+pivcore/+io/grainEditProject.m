classdef grainEditProject
%GRAINEDITPROJECT  Sidecar SETELAN TAMPILAN untuk GRAINEDIT (editor WYSIWYG produksi
%   gambar spesifik AXPOT/Net-slip/AX main). BUKAN gembung data seperti
%   axpotProject — data sesar hidup di `_faults.json` (grain5Faults) + `_potdata.json`
%   (grain4PotData) yang dibaca LIVE oleh GRAINEDIT. Berkas ini HANYA menyimpan pilihan
%   tampilan: elemen mana yang tampil, warna/ukurannya, judul/label, CLim min/max,
%   velMult cm/s, dsb — supaya konfigurasi bisa dipakai ulang antar sesi.
%
%   Skema (struct disimpan sebagai variabel `grainedit` di JSON):
%     .formatName / .formatVersion / .savedAt
%     .source     : struct(dataFile, base)
%     .opts       : struct SETELAN tampilan (lihat defaultOpts) — INTI berkas.
%
%   Dua lapis persistensi (pola GRAINAXPOT):
%     - GLOBAL  : setpref('GRAINEDIT','global', opts)  (lintas-sesi; dikelola GRAINEDIT)
%     - SIDECAR : <base>_pabedit.json  (per-eksperimen; berkas ini)
%   Prioritas muat di GRAINEDIT: sidecar exp -> global -> defaultOpts.
%
%   Penempatan: GRAIN/pivcore_lib/+pivcore/+io/grainEditProject.m

    methods (Static)

        % ================================================================
        function o = defaultOpts()
        %DEFAULTOPTS  Setelan tampilan bawaan pabrik (skema LENGKAP, nilai aman).
        %   KONVENSI TERKUNCI GRAINEDIT: X = strain kumulatif % ; Y = cm/s.
            io = pivcore.io.grainEditProject;
            o = struct();
            % --- mode kanvas & geometri gambar ---
            o.mode        = 'pot';        % 'pot' | 'netslip' | 'main'
            o.widthCm     = 20;
            o.heightCm    = 9;
            o.dpi         = 200;
            o.jpegQ       = 92;
            o.maxLongPx   = 2400;         % 0 = tak dibatasi
            % --- judul & label sumbu (X strain%, Y cm/s dikunci konvensi) ---
            o.title       = '';           % '' -> auto (nama exp)
            o.showTitle   = true;
            o.xlabel      = 'cumulative strain (%)';
            o.ylabel      = 'velocity (cm/s)';
            o.xReverse    = true;         % 0% di KIRI (strain negatif -> XDir reverse)
            o.showGrid    = true;
            % --- kalibrasi cm/s (Y) ---
            o.velMult     = 0.005;        % px/frame -> cm/s (pola GRAIN5 TAB9)
            % --- zoom window (frame) ; [] = full span ---
            o.zoomOn      = false;
            o.zoomSpan    = 200;
            % --- MASKING (patch putih borderless di atas gambar background,
            %     di bawah elemen). rects = Nx4 [x y w h] koord data; polys =
            %     cell of Kx2 verts. Untuk gambar "bersih" saat export. ---
            o.masks       = struct('rects',[], 'polys',{{}});
            % --- elemen POI per-jenis (START/NUC/FSR/END) ---
            o.poi         = io.defaultPoi();
            % --- garis vertikal POI ---
            o.vline       = struct('show',false, 'tiered',true, 'lineWidth',1.3, ...
                                   'labelFrame',true);
            % --- kurva & zona sesar ---
            o.faultsOn    = [];           % [] = semua enabled tampil; else daftar uiNum
            o.faultsOff   = [];           % daftar uiNum yang DISEMBUNYIKAN (override)
            o.curveWidth  = 2.4;
            o.hwColor     = [0.85 0.10 0.10];
            o.fwColor     = [0.10 0.30 0.85];
            o.slipColor   = [0.55 0.10 0.55];
            o.zoneAlpha   = 0.35;
            o.zonePalette = 'ngejreng';   % 'ngejreng' | 'lembut'
            o.areaShade   = true;         % arsir luas START..END (netslip)
            o.faultLabel  = true;         % label F# di kurva
            o.clampAB     = true;         % potong kurva ke [START,END]
            o.showBg      = true;         % kurva POT latar (spaghetti abu-abu, konteks)
            % --- AX main (mode 'main') ---
            o.scalar      = 'velmag';     % 'velmag' | 'shear'
            o.frame       = 1;
            o.climVel     = [0 3.5];      % min/max |V| (px/frame; label cm/s via velMult)
            o.shearAbs    = 0.05;         % |shear| CLim
            o.tickPx      = false;        % AX main POLOS (tanpa tick) — KUNCI
            o.showColorbar= true;
            o.gsOn        = true;
            o.glyphOn     = true;
            o.markerHWFW  = true;
            o.indMarkerSize = 6;
        end


        % ================================================================
        function p = defaultPoi()
        %DEFAULTPOI  Setelan default 4 jenis POI (warna dari snapPoints.color).
            which = {'start','nuc','fsr','end'};
            p = struct();
            for i = 1:numel(which)
                w = which{i};
                p.(w) = struct('show',true, ...
                    'color',pivcore.io.grainEditProject.poiColor(w), ...
                    'size',7, 'exclude',[]);   % exclude = daftar uiNum yang di-skip
            end
        end


        % ================================================================
        function c = poiColor(which)
        %POICOLOR  Warna kanonik POI (bungkus snapPoints.color; fallback aman).
            try
                c = pivcore.pot.snapPoints.color(char(which));
            catch
                c = [0.1 0.1 0.1];
            end
            if ~(isnumeric(c) && numel(c)==3), c = [0.1 0.1 0.1]; end
            c = double(c(:).');
        end


        % ================================================================
        function pth = defaultPath(dataFile)
        %DEFAULTPATH  <dir>/<base>_pabedit.json (di samping .mat sumber).
            [d, base] = pivcore.io.grainEditProject.parts(dataFile);
            if isempty(base), pth = ''; return; end
            pth = fullfile(d, [base '_pabedit.json']);
        end


        % ================================================================
        function p = empty(dataFile)
        %EMPTY  Proyek default/kosong (skema lengkap).
            if nargin < 1, dataFile = ''; end
            [~, base] = pivcore.io.grainEditProject.parts(dataFile);
            p = struct();
            p.formatName    = 'GRAIN Editor Display';
            p.formatVersion = 1;
            p.savedAt       = '';
            p.source        = struct('dataFile',char(dataFile), 'base',base);
            p.opts          = pivcore.io.grainEditProject.defaultOpts();
        end


        % ================================================================
        function save(pth, opts, dataFile)
        %SAVE  Tulis sidecar setelan (JSON) ATOMIC (tmp -> movefile).
        %   `opts` = struct setelan (di-merge ke default supaya lengkap).
            if isempty(pth), error('pivcore:grainEditProject:path','Path kosong'); end
            if nargin < 3, dataFile = ''; end
            p = pivcore.io.grainEditProject.empty(dataFile);
            p.opts    = pivcore.io.grainEditProject.mergeOpts(opts);
            p.savedAt = pivcore.io.grainEditProject.stampNow();
            d = fileparts(pth); if ~isempty(d) && ~isfolder(d), mkdir(d); end
            txt = jsonencode(p, 'PrettyPrint', true);
            tmp = [pth '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0, error('pivcore:grainEditProject:open','Gagal buka %s', tmp); end
            cu = onCleanup(@() pivcore.io.grainEditProject.cleanupTmp(tmp));
            fwrite(fid, txt, 'char'); fclose(fid);
            [ok, msg] = movefile(tmp, pth, 'f');
            if ~ok, error('pivcore:grainEditProject:move','Gagal tulis %s: %s', pth, msg); end
            clear cu;
        end


        % ================================================================
        function opts = load(pth)
        %LOAD  Baca sidecar -> struct opts (di-merge ke default). Error bila absen.
            if isempty(pth) || ~isfile(pth)
                error('pivcore:grainEditProject:notfound','Berkas tak ada: %s', pth);
            end
            txt = fileread(pth);
            p = jsondecode(txt);
            o = struct();
            if isstruct(p) && isfield(p,'opts') && isstruct(p.opts)
                o = p.opts;
            elseif isstruct(p)
                o = p;   % tersimpan sebagai opts tersebar
            end
            opts = pivcore.io.grainEditProject.mergeOpts(o);
        end


        % ================================================================
        function o = mergeOpts(o)
        %MERGEOPTS  Lengkapi field hilang dgn default (kompat maju-mundur). POI
        %   sub-struct di-merge per-jenis. Tahan-migrasi: field baru masuk otomatis.
            io = pivcore.io.grainEditProject;
            d = io.defaultOpts();
            if ~isstruct(o), o = d; return; end
            fn = fieldnames(d);
            for i = 1:numel(fn)
                f = fn{i};
                if ~isfield(o, f) || isempty(o.(f)) && ~io.emptyAllowed(f)
                    o.(f) = d.(f);
                end
            end
            % POI sub-struct: pastikan 4 jenis lengkap + field per-jenis.
            if ~isstruct(o.poi), o.poi = d.poi; end
            which = {'start','nuc','fsr','end'};
            for i = 1:numel(which)
                w = which{i};
                if ~isfield(o.poi, w) || ~isstruct(o.poi.(w))
                    o.poi.(w) = d.poi.(w);
                else
                    pf = fieldnames(d.poi.(w));
                    for j = 1:numel(pf)
                        if ~isfield(o.poi.(w), pf{j}) || (isempty(o.poi.(w).(pf{j})) && ~strcmp(pf{j},'exclude'))
                            o.poi.(w).(pf{j}) = d.poi.(w).(pf{j});
                        end
                    end
                end
            end
            % vline sub-struct
            if ~isstruct(o.vline), o.vline = d.vline; end
            % masks sub-struct (rects Nx4, polys cell of Kx2). Normalisasi bentuk
            % pasca JSON round-trip (jsondecode bisa ubah cell -> array/struct).
            o.masks = io.normMasks(o.masks);
        end


        % ================================================================
        function m = normMasks(m)
        %NORMMASKS  Pastikan masks = struct(rects Nx4, polys cell of Kx2).
            if ~isstruct(m), m = struct('rects',[],'polys',{{}}); end
            if ~isfield(m,'rects'), m.rects = []; end
            if ~isfield(m,'polys'), m.polys = {}; end
            r = m.rects;
            if isempty(r), m.rects = [];
            elseif isnumeric(r) && size(r,2)==4, m.rects = double(r);
            else, m.rects = [];
            end
            p = m.polys;
            if isempty(p), m.polys = {};
            elseif iscell(p)
                out = {};
                for i = 1:numel(p)
                    v = p{i};
                    if isnumeric(v) && size(v,2)==2 && size(v,1)>=3, out{end+1} = double(v); end %#ok<AGROW>
                end
                m.polys = out;
            elseif isnumeric(p) && size(p,2)==2 && size(p,1)>=3
                m.polys = {double(p)};   % 1 poligon tersimpan sbg matriks
            else
                m.polys = {};
            end
        end


        % ================================================================
        function s = strainVec(nF, strainTotalPct)
        %STRAINVEC  Vektor strain kumulatif % per-frame [1xnF] (bisa negatif).
            s = [];
            n = pivcore.io.grainEditProject.sc(nF);
            st = pivcore.io.grainEditProject.sc(strainTotalPct);
            if isfinite(n) && n > 1 && isfinite(st), s = (0:n-1)/(n-1)*st; end
        end


        % ================================================================
        function pct = strainAtFrame(frameK, nF, strainTotalPct)
        %STRAINATFRAME  Strain kumulatif % di frame k: (k-1)/(nF-1)*st. NaN invalid.
            pct = NaN;
            k = pivcore.io.grainEditProject.sc(frameK);
            n = pivcore.io.grainEditProject.sc(nF);
            st = pivcore.io.grainEditProject.sc(strainTotalPct);
            if isfinite(k) && isfinite(n) && n > 1 && isfinite(st)
                pct = (k-1)/(n-1)*st;
            end
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

        function tf = emptyAllowed(f)
        %EMPTYALLOWED  Field yang BOLEH kosong (tak ditimpa default saat merge).
            tf = ismember(f, {'title','faultsOn','faultsOff','masks'});
        end

        function s = stampNow()
        %STAMPNOW  Tanggal string; JANGAN pakai Date.now di skrip workflow, tapi di
        %   engine MATLAB `datestr(now)` aman (dijalankan di MATLAB, bukan JS).
            try, s = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')); catch, s = ''; end
        end

        function v = sc(x)
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end

        function cleanupTmp(tmp)
            try, if isfile(tmp), delete(tmp); end, catch, end
        end

    end
end
