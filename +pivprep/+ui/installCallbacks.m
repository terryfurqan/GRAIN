function installCallbacks(fig)
%INSTALLCALLBACKS  Pasang semua callback untuk jendela PIVPrep.
%
%   pivprep.ui.installCallbacks(fig)

    h = guidata(fig);

    set(h.btnPickFiles,  'Callback', @(s, e) local_onPickFiles(fig));
    set(h.btnPickOutput, 'Callback', @(s, e) local_onPickOutput(fig));
    set(h.btnRun,        'Callback', @(s, e) local_onRun(fig));
end


% =====================================================================
function local_onPickFiles(fig)
    h = guidata(fig);
    [files, folder] = pivprep.io.pickInputs();
    if isempty(files); return; end
    h.files       = files;
    h.inputFolder = folder;
    [~, folderName] = fileparts(folder);
    set(h.txtFiles, 'String', ...
        sprintf('%d image(s) in "%s"', numel(files), folderName));
    guidata(fig, h);
end


% =====================================================================
function local_onPickOutput(fig)
    h = guidata(fig);
    startDir = h.inputFolder;
    if isempty(startDir); startDir = pwd; end
    folder = uigetdir(startDir, 'Pilih Folder Output');
    if isequal(folder, 0); return; end
    h.outputFolder = folder;
    disp_str = folder;
    if numel(disp_str) > 40
        disp_str = ['...' disp_str(end-37:end)];
    end
    set(h.txtOutput, 'String', disp_str);
    guidata(fig, h);
end


% =====================================================================
function local_onRun(fig)
    h = guidata(fig);

    if isempty(h.files)
        errordlg('Pilih berkas input terlebih dahulu.', 'PIVPrep: No Input');
        return;
    end

    % --- Validasi numerik ---
    rawQual = str2double(get(h.edRawQual, 'String'));
    gsScale = str2double(get(h.edGsScale, 'String'));
    gsQual  = str2double(get(h.edGsQual,  'String'));
    jit     = str2double(get(h.edJitter,  'String'));

    if any(isnan([rawQual, gsScale, gsQual, jit]))
        errordlg('Nilai numerik tidak valid. Periksa quality, scale, dan jitter.', ...
                 'PIVPrep: Input Error');
        return;
    end

    cfg = h.cfg;

    % Mode framing
    if get(h.rbSquare, 'Value')
        cfg.mode = 'square';
    else
        cfg.mode = 'crop';
    end

    % Stabilisasi
    cfg.useStab = logical(get(h.chkStab, 'Value'));
    methodList     = {'surf', 'phasecorr'};
    cfg.stabMethod = methodList{get(h.popStabMethod, 'Value')};
    cfg.jitterTol  = jit;

    % Format RAW
    rawFmtList    = {'jpg', 'png', 'tif'};
    cfg.rawFormat = rawFmtList{get(h.popRawFmt, 'Value')};
    cfg.rawQuality = rawQual;

    % GS
    cfg.gsScale   = gsScale / 100;
    cfg.gsQuality = gsQual;

    if cfg.gsScale <= 0 || cfg.gsScale > 1
        errordlg('GS scale harus antara 1 dan 100 persen.', 'PIVPrep: Input Error');
        return;
    end

    % EXIF: preservasi selalu aktif (embed lengkap + backup EXIF/EXIF.mat).
    % Tidak ada opsi; ditangani penuh di writeOutputs & writeExifTable.

    % Monitor real-time
    if isfield(h, 'chkMonitor') && ishandle(h.chkMonitor)
        cfg.showMonitor = logical(get(h.chkMonitor, 'Value'));
    else
        cfg.showMonitor = true;
    end

    % Folder output
    if isempty(h.outputFolder)
        [~, folderName] = fileparts(strtrim(h.inputFolder));
        if isempty(folderName); folderName = 'Output'; end
        outDir = fullfile(h.inputFolder, ['PIVPrep-' folderName]);
    else
        outDir = h.outputFolder;
    end
    pivprep.util.utilities.ensureDir(outDir);

    % --- Jalankan batch ---
    pivprep.core.processBatch(h.files, h.inputFolder, outDir, cfg);
end
