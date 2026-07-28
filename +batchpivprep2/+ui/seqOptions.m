function varargout = seqOptions(varargin)
%SEQOPTIONS  Pilihan "Sequencing" (urutan file) untuk tabel folder Step 1.
%
%   choices = batchpivprep2.ui.seqOptions()
%       Kembalikan cell-of-char daftar label popup (untuk ColumnFormat uitable).
%
%   [mode, step] = batchpivprep2.ui.seqOptions('parse', label)
%       Ubah label tabel -> (mode, step). mode: 'consecutive'|'pairs'|'skip'.
%
%   label = batchpivprep2.ui.seqOptions('label', mode, step)
%       Ubah (mode, step) -> label tabel kanonis (untuk ditampilkan).
%
%   SATU sumber kebenaran untuk label urutan file, dipakai bersama oleh
%   buildGUI (ColumnFormat), refreshFolderTable (tampil), dan installCallbacks
%   (parse CellEditCallback). Metadata ini ditulis ke prep.sequencing di .mat
%   oleh pivprepPackFolder dan dibaca konsumer PIV (PIVlab_automasi_fromSingleMat).
%
%   Daftar Skip-N dibatasi N = 2..6 (cukup untuk kasus umum frame berdekatan
%   terlalu mirip). Tambah/ubah daftar di sini bila perlu lebih banyak.

    skipMax = 6;

    if nargin == 0
        varargout{1} = i_buildChoices(skipMax);
        return;
    end

    op = lower(char(varargin{1}));
    switch op
        case 'parse'
            [varargout{1}, varargout{2}] = i_parse(char(varargin{2}));
        case 'label'
            mode = char(varargin{2});
            step = 1;
            if nargin >= 3 && ~isempty(varargin{3}); step = double(varargin{3}); end
            varargout{1} = i_label(mode, step);
        case 'choices'
            varargout{1} = i_buildChoices(skipMax);
        otherwise
            error('batchpivprep2:seqOptions:badOp', 'Operasi tidak dikenal: %s', op);
    end
end


% =====================================================================
function c = i_buildChoices(skipMax)
    c = {i_label('consecutive', 1), i_label('pairs', 1)};
    for n = 2:skipMax
        c{end+1} = i_label('skip', n); %#ok<AGROW>
    end
end


function label = i_label(mode, step)
%I_LABEL  (mode, step) -> label tabel kanonis.
    switch lower(strtrim(mode))
        case 'pairs'
            label = 'Pairs (1-2, 3-4)';
        case 'skip'
            step = max(2, round(step));
            label = sprintf('Skip-%d (tiap %d)', step, step);
        otherwise
            label = 'Consecutive (1-2, 2-3)';
    end
end


function [mode, step] = i_parse(label)
%I_PARSE  Label tabel -> (mode, step). Toleran thd label lama/parsial.
    label = lower(strtrim(label));
    step = 1;
    if startsWith(label, 'pairs')
        mode = 'pairs';
    elseif startsWith(label, 'skip')
        mode = 'skip';
        tok = regexp(label, 'skip-?\s*(\d+)', 'tokens', 'once');
        if ~isempty(tok); step = max(2, str2double(tok{1})); else; step = 2; end
    else
        mode = 'consecutive';
    end
end
