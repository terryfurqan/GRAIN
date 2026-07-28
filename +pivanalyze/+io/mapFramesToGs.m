function gsPerFrame = mapFramesToGs(gsSorted, nFrames, seq, dropFirst)
%MAPFRAMESTOGS  Petakan tiap pasangan frame PIV ke satu berkas GS.
%
%   gsPerFrame = pivanalyze.io.mapFramesToGs(gsSorted, nFrames, seq, dropFirst)
%
%   seq       : 'pairs' (GS = frame ke-2 tiap pasangan) atau 'consecutive'.
%   dropFirst : pada 'consecutive', buang GS pertama agar sejajar pasangan.
%   Kembalian : cell {nFrames x 1} path GS ('' bila kosong).
%
%   Salinan persis subfungsi map_frames_to_gs dari PIVlab_automasi_batch_V4.

    nG = numel(gsSorted);
    gsPerFrame = cell(nFrames, 1);
    [gsPerFrame{:}] = deal('');
    if nG == 0; return; end
    if strcmpi(seq, 'pairs')
        for k = 1:nFrames
            gsPerFrame{k} = gsSorted{min(2*k, nG)};
        end
    else
        if dropFirst && nG >= 2
            used = gsSorted(2:end);
            nU = numel(used);
            for k = 1:nFrames
                gsPerFrame{k} = used{min(k, nU)};
            end
        else
            for k = 1:nFrames
                gsPerFrame{k} = gsSorted{min(k, nG)};
            end
        end
    end
end
