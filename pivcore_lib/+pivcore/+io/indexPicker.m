classdef indexPicker
%INDEXPICKER  Dialog modal startup "folder-first" untuk PIVTerry.
%
%   Dipakai PIVTerry() saat dijalankan TANPA argumen: meminta folder kerja,
%   memindainya (pivcore.io.indexScanner), menampilkan daftar eksperimen
%   beserta progres & klasifikasi, lalu mengembalikan PATH berkas data utama
%   yang dipilih pengguna untuk dimuat. Mengembalikan '' bila dibatalkan.
%
%   API:
%     dataFile = pivcore.io.indexPicker.choose()          % minta folder
%     dataFile = pivcore.io.indexPicker.choose(rootDir)   % folder diketahui
%     [dataFile, rootDir] = pivcore.io.indexPicker.choose(...)
%
%   Catatan: ini dialog ringan & berdiri sendiri (figure modal), terpisah
%   dari tab Index di dalam aplikasi utama. Keduanya berbagi indexScanner.
%
%   Penempatan berkas: PIVTerry/+pivterry/+io/indexPicker.m

    methods (Static)

        function [dataFile, rootDir] = choose(rootDir)
            dataFile = '';
            if nargin < 1 || isempty(rootDir)
                rootDir = uigetdir(pwd, 'Pilih folder kerja PIVTerry');
                if isequal(rootDir, 0), rootDir = ''; return; end
            end
            if ~isfolder(rootDir)
                error('pivcore:indexPicker:badRoot', ...
                    'Folder tidak valid: %s', rootDir);
            end

            % --- Pindai + merge index tersimpan ---
            list  = pivcore.io.indexScanner.scanFolder(rootDir);
            saved = pivcore.io.indexScanner.loadIndex(rootDir);
            if ~isempty(saved)
                list = pivcore.io.indexScanner.mergeClassification(list, saved);
            end

            if isempty(list)
                uiwait(msgbox(sprintf(['Tidak ada berkas data utama (.mat) ' ...
                    'ditemukan di:\n%s\n\nPilih file secara manual.'], rootDir), ...
                    'Folder kosong','warn'));
                [fn, fp] = uigetfile({'*.mat','Berkas PIVLAB (*.mat)'}, ...
                    'Pilih berkas hasil PIVLAB', rootDir);
                if ~isequal(fn, 0), dataFile = fullfile(fp, fn); end
                return;
            end

            % --- Bangun dialog modal ---
            res = pivcore.io.indexPicker.showDialog(rootDir, list);
            dataFile = res;
        end


        function dataFile = showDialog(rootDir, list)
            dataFile = '';
            defs   = pivcore.io.indexScanner.CHECKLIST_DEFS();
            chkLbl = {defs.label};
            nChk   = numel(chkLbl);

            % Susun data tabel: Nama | L1..L4 | checklist | MB
            n = numel(list);
            data = cell(n, 5 + nChk + 1);
            greenCells = zeros(0,2); redCells = zeros(0,2);
            for i = 1:n
                e = list(i);
                data(i,1:5) = {e.name, e.L1, e.L2, e.L3, e.L4};
                for k = 1:nChk
                    tf = isfield(e,'done') && isfield(e.done, defs(k).key) ...
                        && logical(e.done.(defs(k).key));
                    col = 5 + k;
                    if tf
                        data{i,col} = char(10003);
                        greenCells(end+1,:) = [i col]; %#ok<AGROW>
                    else
                        data{i,col} = char(10007);
                        redCells(end+1,:) = [i col];   %#ok<AGROW>
                    end
                end
                if e.sizeMB > 0
                    data{i,end} = sprintf('%.0f', e.sizeMB);
                else
                    data{i,end} = '-';
                end
            end
            colNames = [{'Nama','L1','L2','L3','L4'}, chkLbl, {'MB'}];
            colW = [{200,60,55,45,40}, repmat({62},1,nChk), {60}];

            dlg = figure('Name','PIVTerry - Pilih eksperimen', ...
                'NumberTitle','off','MenuBar','none','ToolBar','none', ...
                'Units','normalized','Position',[0.20 0.25 0.60 0.50], ...
                'Color',[0.96 0.96 0.96],'WindowStyle','modal');

            uicontrol(dlg,'Style','text','Units','normalized', ...
                'Position',[0.02 0.93 0.96 0.05], ...
                'String',sprintf('Folder kerja: %s', rootDir), ...
                'HorizontalAlignment','left','BackgroundColor',[0.96 0.96 0.96], ...
                'FontWeight','bold');

            tbl = uitable(dlg,'Units','normalized', ...
                'Position',[0.02 0.14 0.96 0.78], ...
                'ColumnName',colNames,'ColumnWidth',colW, ...
                'RowName',[],'Data',data, ...
                'ColumnEditable',false(1, size(data,2)));

            % Warnai sel checklist: hijau=sudah, merah=belum (uistyle/addStyle).
            try
                if ~isempty(greenCells)
                    addStyle(tbl, uistyle('BackgroundColor',[0.78 0.92 0.78]), ...
                        'cell', greenCells);
                end
                if ~isempty(redCells)
                    addStyle(tbl, uistyle('BackgroundColor',[0.96 0.80 0.80]), ...
                        'cell', redCells);
                end
            catch
            end

            % Simpan baris terpilih di appdata dialog.
            setappdata(dlg,'sel',0);
            setappdata(dlg,'list',list);
            set(tbl,'CellSelectionCallback',@(s,e) ...
                pivcore.io.indexPicker.onSelect(dlg, e));

            uicontrol(dlg,'Style','pushbutton','String','Buka', ...
                'Units','normalized','Position',[0.62 0.03 0.17 0.08], ...
                'FontWeight','bold', ...
                'Callback',@(s,e) pivcore.io.indexPicker.onOpen(dlg));
            uicontrol(dlg,'Style','pushbutton','String','Batal', ...
                'Units','normalized','Position',[0.81 0.03 0.17 0.08], ...
                'Callback',@(s,e) pivcore.io.indexPicker.onCancel(dlg));

            uiwait(dlg);

            if ishghandle(dlg)
                dataFile = getappdata(dlg, 'result');
                if isempty(dataFile), dataFile = ''; end
                delete(dlg);
            end
        end


        function onSelect(dlg, evt)
            if ~isempty(evt) && isprop(evt,'Indices') && ~isempty(evt.Indices)
                setappdata(dlg,'sel', evt.Indices(1,1));
            end
        end


        function onOpen(dlg)
            sel  = getappdata(dlg,'sel');
            list = getappdata(dlg,'list');
            if sel < 1 || sel > numel(list)
                uiwait(msgbox('Pilih satu baris eksperimen dulu.','Pilih', ...
                    'help'));
                return;
            end
            df = list(sel).dataFile;
            if isempty(df) || ~isfile(df)
                uiwait(msgbox(sprintf('Berkas tidak ditemukan:\n%s', df), ...
                    'Pilih','warn'));
                return;
            end
            setappdata(dlg,'result', df);
            uiresume(dlg);
        end


        function onCancel(dlg)
            setappdata(dlg,'result','');
            uiresume(dlg);
        end

    end
end
