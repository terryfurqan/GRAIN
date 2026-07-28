function refreshFolderTable(fig)
%REFRESHFOLDERTABLE  Bangun ulang isi tabel folder pada jendela utama.
%
%   batchpivprep2.ui.refreshFolderTable(fig)
%
%   Membaca h.folders dari guidata(fig) lalu mengisi h.tblFolders dan
%   h.txtFolderCount. Kolom: #, Folder, Images, Output Name, Sequencing,
%   Anchor, Crop. Dipakai bersama oleh installCallbacks, viewFirstFrames,
%   viewCropFrames agar perubahan anchor/crop/urutan langsung terlihat.

    h = guidata(fig);
    if ~isfield(h, 'tblFolders') || ~ishandle(h.tblFolders)
        return;
    end

    n = numel(h.folders);
    data = cell(n, 7);
    for i = 1:n
        f  = h.folders(i);

        an = f.anchorName;
        if isempty(an); an = '(none)'; end

        cr = '(none)';
        if isfield(f, 'cropName') && ~isempty(f.cropName)
            cr = char(f.cropName);
        end
        if isfield(f, 'crop') && ~isempty(f.crop) && isfield(f.crop, 'cropMode')
            cr = sprintf('%s [%s]', cr, upper(f.crop.cropMode));
        end

        on = '';
        if isfield(f, 'outName'); on = char(f.outName); end
        if isempty(on); on = local_defaultOutName(f.path); end

        sq = local_seqLabel(f);

        data{i, 1} = i;
        data{i, 2} = local_shortPath(f.path);
        data{i, 3} = f.nImg;
        data{i, 4} = on;
        data{i, 5} = sq;
        data{i, 6} = an;
        data{i, 7} = cr;
    end
    set(h.tblFolders, 'Data', data);

    nAnchor = 0; nCrop = 0;
    if n > 0
        nAnchor = sum(arrayfun(@(f) ~isempty(f.anchor), h.folders));
        nCrop   = sum(arrayfun(@(f) isfield(f, 'crop') && ~isempty(f.crop), h.folders));
    end
    if isfield(h, 'txtFolderCount') && ishandle(h.txtFolderCount)
        set(h.txtFolderCount, 'String', ...
            sprintf('%d folder  |  %d anchor  |  %d crop', n, nAnchor, nCrop));
    end
end


% =====================================================================
function s = local_seqLabel(f)
%LOCAL_SEQLABEL  Label kolom Sequencing dari field folder (default consecutive).
    mode = 'consecutive';
    step = 1;
    if isfield(f, 'seqMode') && ~isempty(f.seqMode); mode = char(f.seqMode); end
    if isfield(f, 'seqStep') && ~isempty(f.seqStep) && isnumeric(f.seqStep)
        step = double(f.seqStep);
    end
    s = batchpivprep2.ui.seqOptions('label', mode, step);
end


% =====================================================================
function nm = local_defaultOutName(p)
%LOCAL_DEFAULTOUTNAME  Nama folder keluaran default = basename folder input.
    p = char(p);
    if ~isempty(p) && (p(end) == filesep || p(end) == '/'); p(end) = []; end
    [~, nm] = fileparts(p);
    if isempty(nm); nm = 'Folder'; end
end


% =====================================================================
function s = local_shortPath(p)
%LOCAL_SHORTPATH  Tampilkan 2 komponen terakhir path (mudah dibaca).
    p = char(p);
    parts = regexp(p, '[\\/]', 'split');
    parts = parts(~cellfun(@isempty, parts));
    if numel(parts) <= 2
        s = p;
    else
        s = ['...' filesep parts{end-1} filesep parts{end}];
    end
end
