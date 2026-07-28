classdef potSession
%POTSESSION  Serialisasi / deserialisasi progres tab POT (Plot Over Time).
%
%   Kelas statik. Menyimpan dan memulihkan seluruh informasi yang melekat
%   pada keadaan POT saat ini: jumlah variabel, label, warna, mode, rentang
%   bingkai, lebar garis, asal kotak sampel, deret waktu hasil sampling,
%   sumber skalar per variabel, ukuran area persegi, gaya kotak indikator,
%   dan preview yang belum di-commit.
%
%   Format penyimpanan: berkas .mat berisi sebuah struct tunggal bernama
%   `potSession`. Struktur dirancang self-describing supaya dapat di-parse
%   tanpa GUI PIVTerry, mis. pada skrip post-processing eksternal:
%
%       S = load('namafile.mat');           % memuat struct
%       S.potSession                        % isi utama
%       S.potSession.vars(1).data           % deret waktu variabel ke-1
%       S.potSession.vars(1).origin         % [cx, cy] di sumbu data
%       S.potSession.areaW, areaH           % ukuran area sampel persegi
%
%   API:
%     pivcore.io.potSession.saveToFile(fig, fname)
%     pivcore.io.potSession.loadFromFile(fig, fname)
%     S = pivcore.io.potSession.toStruct(h)
%     h = pivcore.io.potSession.fromStruct(h, S)
%     pivcore.io.potSession.saveDialog(fig)
%     pivcore.io.potSession.loadDialog(fig)
%
%   Catatan:
%     - Modul ini TIDAK bergantung pada handle UI selain `fig`. Semua data
%       dibaca/ditulis melalui guidata.
%     - Saat memuat, jumlah bingkai pada berkas sesi DAPAT berbeda dengan
%       jumlah bingkai dataset yang sedang aktif. Bila berbeda, deret data
%       dipotong / di-pad dengan NaN supaya panjangnya konsisten dengan
%       `h.data.nFrames`.

    methods (Static)

        function S = toStruct(h)
        %TOSTRUCT  Bangun struct serialisasi dari state POT pada guidata h.
            pot = h.state.pot;

            S = struct();
            S.formatName    = 'PIVTerry POT Session';
            S.formatVersion = 1;
            S.savedAt       = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<DATST,TNOW1>
            S.matFile       = '';
            if isfield(h,'matFile') && ischar(h.matFile)
                S.matFile = h.matFile;
            end
            S.nFramesAtSave = h.data.nFrames;

            S.nVars     = pot.nVars;
            S.activeVar = pot.activeVar;
            S.areaW     = pot.areaW;
            S.areaH     = pot.areaH;
            S.srcName   = pot.srcName;

            % Salin gaya kotak indikator
            if isfield(pot,'box')
                S.box = pot.box;
            else
                S.box = struct( ...
                    'syncOutlineWithCurve', true, ...
                    'outlineColor', [0.20 0.40 0.85], ...
                    'fillColor',    [1 1 1], ...
                    'fontColor',    [0 0 0], ...
                    'lineWidth',    1.5, ...
                    'fillAlpha',    0.85);
            end

            % Salin daftar variabel beserta data sampling-nya
            varTpl = struct( ...
                'index',    0, ...
                'label',    '', ...
                'color',    [0 0 0], ...
                'mode',     'Raw', ...
                'maWindow', 5, ...
                'fromF',    1, ...
                'toF',      1, ...
                'lw',       1.5, ...
                'origin',   [NaN NaN], ...
                'srcName',  '', ...
                'data',     [], ...
                'nValid',   0);
            S.vars = repmat(varTpl, 1, pot.nVars);
            for k = 1:pot.nVars
                v = pot.vars(k);
                S.vars(k).index    = k;
                S.vars(k).label    = v.label;
                S.vars(k).color    = v.color;
                S.vars(k).mode     = v.mode;
                S.vars(k).maWindow = v.maWindow;
                S.vars(k).fromF    = v.fromF;
                S.vars(k).toF      = v.toF;
                S.vars(k).lw       = v.lw;
                S.vars(k).origin   = v.origin;
                S.vars(k).srcName  = v.srcName;
                if isempty(v.data)
                    S.vars(k).data   = [];
                    S.vars(k).nValid = 0;
                else
                    S.vars(k).data   = v.data(:).';   % vektor baris
                    S.vars(k).nValid = sum(isfinite(v.data));
                end
            end

            % Preview yang belum di-commit (dapat dipulihkan)
            if isfield(pot,'preview')
                S.preview = pot.preview;
            else
                S.preview = struct( ...
                    'active',  false, ...
                    'origin',  [NaN NaN], ...
                    'data',    [], ...
                    'srcName', '');
            end
        end


        function h = fromStruct(h, S)
        %FROMSTRUCT  Tulis kembali struct sesi ke guidata h.state.pot.
        %   Jumlah bingkai data yang sedang aktif dijadikan acuan; deret
        %   waktu setiap variabel dipotong / di-pad dengan NaN agar
        %   konsisten dengan h.data.nFrames.

            if ~isfield(S,'formatName') || ~contains(S.formatName,'POT Session')
                error('pivcore:potSession:badFormat', ...
                    'Berkas tidak dikenali sebagai sesi POT PIVTerry.');
            end

            nF = h.data.nFrames;

            pot = struct();
            pot.nVars     = max(1, double(S.nVars));
            pot.activeVar = max(1, min(pot.nVars, double(S.activeVar)));
            pot.areaW     = max(1, double(S.areaW));
            pot.areaH     = max(1, double(S.areaH));
            if isfield(S,'srcName') && ischar(S.srcName)
                pot.srcName = S.srcName;
            else
                pot.srcName = 'velocity_magnitude';
            end

            % Gaya kotak
            if isfield(S,'box') && isstruct(S.box)
                pot.box = S.box;
            else
                pot.box = struct( ...
                    'syncOutlineWithCurve', true, ...
                    'outlineColor', [0.20 0.40 0.85], ...
                    'fillColor',    [1 1 1], ...
                    'fontColor',    [0 0 0], ...
                    'lineWidth',    1.5, ...
                    'fillAlpha',    0.85);
            end

            % Bangun ulang struct vars
            tpl = struct('data',[],'label','','color',[0 0 0], ...
                'mode','Moving average','maWindow',2,'fromF',1,'toF',nF, ...
                'lw',1.5,'origin',[NaN NaN],'srcName','');
            pot.vars = repmat(tpl, 1, pot.nVars);

            for k = 1:pot.nVars
                if k <= numel(S.vars)
                    sv = S.vars(k);
                else
                    sv = struct();
                end

                pot.vars(k).label    = pivcore.io.potSession.getf( ...
                    sv,'label', sprintf('HW-%d', k));
                pot.vars(k).color    = pivcore.io.potSession.getf( ...
                    sv,'color', [0 0 0]);
                pot.vars(k).mode     = pivcore.io.potSession.getf( ...
                    sv,'mode',  'Moving average');
                pot.vars(k).maWindow = pivcore.io.potSession.getf( ...
                    sv,'maWindow', 2);
                pot.vars(k).fromF    = max(1, ...
                    pivcore.io.potSession.getf(sv,'fromF', 1));
                pot.vars(k).toF      = min(nF, ...
                    pivcore.io.potSession.getf(sv,'toF', nF));
                pot.vars(k).lw       = pivcore.io.potSession.getf( ...
                    sv,'lw', 1.5);
                pot.vars(k).origin   = pivcore.io.potSession.getf( ...
                    sv,'origin', [NaN NaN]);
                pot.vars(k).srcName  = pivcore.io.potSession.getf( ...
                    sv,'srcName', '');

                d = pivcore.io.potSession.getf(sv,'data', []);
                pot.vars(k).data = pivcore.io.potSession.fitSeries(d, nF);
            end

            % Preview
            if isfield(S,'preview') && isstruct(S.preview) ...
                    && pivcore.io.potSession.getf(S.preview,'active',false)
                pot.preview = struct( ...
                    'active',  true, ...
                    'origin',  pivcore.io.potSession.getf( ...
                                S.preview,'origin',[NaN NaN]), ...
                    'data',    pivcore.io.potSession.fitSeries( ...
                                pivcore.io.potSession.getf( ...
                                    S.preview,'data',[]), nF), ...
                    'srcName', pivcore.io.potSession.getf( ...
                                S.preview,'srcName',''));
            else
                pot.preview = struct( ...
                    'active',  false, ...
                    'origin',  [NaN NaN], ...
                    'data',    [], ...
                    'srcName', '');
            end

            h.state.pot = pot;
        end


        function saveToFile(fig, fname)
        %SAVETOFILE  Tulis sesi POT ke fname (.mat).
            h = guidata(fig);
            potSession = pivcore.io.potSession.toStruct(h); %#ok<NASGU>
            save(fname, 'potSession', '-v7');
        end


        function loadFromFile(fig, fname)
        %LOADFROMFILE  Baca sesi POT dari fname dan terapkan ke fig.
            S = load(fname);
            if ~isfield(S,'potSession')
                error('pivcore:potSession:noField', ...
                    ['Berkas %s tidak berisi variabel "potSession". ', ...
                     'Pastikan berkas ini hasil "Simpan progres" PIVTerry.'], ...
                     fname);
            end
            h = guidata(fig);
            h = pivcore.io.potSession.fromStruct(h, S.potSession);
            guidata(fig, h);
        end


        function saveDialog(fig)
        %SAVEDIALOG  Buka dialog "Save As" lalu tulis sesi POT.
            h = guidata(fig);
            defaultName = 'pot_session.mat';
            if isfield(h,'matFile') && ischar(h.matFile) && ~isempty(h.matFile)
                [~, base] = fileparts(h.matFile);
                defaultName = sprintf('%s_pot.mat', base);
            end
            [fn, fp] = uiputfile({'*.mat','PIVTerry POT Session (*.mat)'}, ...
                'Simpan progres POT', defaultName);
            if isequal(fn, 0), return; end
            outFile = fullfile(fp, fn);
            try
                pivcore.io.potSession.saveToFile(fig, outFile);
                msgbox(sprintf(['Progres POT tersimpan ke:\n%s\n\n', ...
                    'Berkas dapat dibuka kembali dengan "Muat progres" ', ...
                    'atau di-parse pada skrip eksternal melalui ', ...
                    'load(...).'], outFile), 'Simpan progres');
            catch ME
                errordlg(sprintf('Gagal menyimpan: %s', ME.message), ...
                    'Simpan progres');
            end
        end


        function loadDialog(fig)
        %LOADDIALOG  Buka dialog "Open" lalu pulihkan sesi POT.
            [fn, fp] = uigetfile({'*.mat','PIVTerry POT Session (*.mat)'}, ...
                'Muat progres POT');
            if isequal(fn, 0), return; end
            inFile = fullfile(fp, fn);
            try
                pivcore.io.potSession.loadFromFile(fig, inFile);
            catch ME
                errordlg(sprintf('Gagal memuat: %s', ME.message), ...
                    'Muat progres');
                return;
            end
            % CORE (pivcore): state.pot sudah dipulihkan oleh loadFromFile.
            %   Penyelarasan kontrol UI + redraw adalah TANGGUNG JAWAB GUI
            %   HOST (core tidak mengenal kontrol GUI mana pun). Pola pakai:
            %   panggil pivcore.io.potSession.loadFromFile(fig,...) lalu
            %   refresh kontrol & gambar sendiri di GUI standalone.
            %   (Lihat core/README.md - "load via core -> refresh UI sendiri".)
            h = guidata(fig);
            msgbox(sprintf(['Progres POT berhasil dimuat dari:\n%s\n\n', ...
                'Jumlah variabel: %d.\nJumlah bingkai dataset: %d.'], ...
                inFile, h.state.pot.nVars, h.data.nFrames), ...
                'Muat progres');
        end


        % ----------------------------------------------------------
        % Helper internal
        % ----------------------------------------------------------

        function v = getf(s, name, defaultVal)
        %GETF  Ambil bidang struct dengan default jika tidak ada / kosong.
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                v = s.(name);
            else
                v = defaultVal;
            end
        end


        function out = fitSeries(d, nF)
        %FITSERIES  Pastikan deret waktu d sepanjang nF (potong / pad NaN).
            if isempty(d)
                out = [];
                return;
            end
            d = d(:).';
            if numel(d) == nF
                out = d;
            elseif numel(d) > nF
                out = d(1:nF);
            else
                out = nan(1, nF);
                out(1:numel(d)) = d;
            end
        end

    end
end
