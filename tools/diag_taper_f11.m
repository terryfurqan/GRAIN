function diag_taper_f11()
%DIAG_TAPER_F11  Diagnostik kenapa garis taper F11 / interpolasi tak tampil.
%   JALANKAN saat GRAIN4 TERBUKA (F11 aktif, frame di sekitar 292). Cetak: keyframe
%   taper F11, isi cache taperSamples, objek storedTaper/taperInterp/taperInterpRef
%   yg tergambar di axMain, dan alasan bila kosong.
    figs = findall(0,'Type','figure');
    fig = [];
    for k = 1:numel(figs)
        h = guidata(figs(k));
        if isstruct(h) && isfield(h,'tblDesc') && isfield(h,'taperSamples')
            fig = figs(k); break;
        end
    end
    if isempty(fig), fprintf(2,'GRAIN4 tak ditemukan (buka dulu).\n'); return; end
    h = guidata(fig);
    fprintf('=== DIAG TAPER (GRAIN4) ===\n');
    fprintf('activePsgId = %s\n', h.activePsgId);
    fprintf('frame live  = %d\n', round(pivcore.util.scalarOr(h.frame,1)));
    fprintf('taperInterpOn = %d\n', isfield(h,'taperInterpOn') && h.taperInterpOn);

    % sesar aktif
    [fa, ia] = pivui.grain5Model.activeFault(h);
    uA = NaN; if ia>=1, uA = round(pivui.grain5Model.faultUiNum(fa)); end
    fprintf('F# aktif = %g\n', uA);

    % keyframe taper F# aktif (baca descDoc langsung)
    rows = pivcore.io.grain4Desc.rowsForPsg(h.descDoc, h.activePsgId);
    tgt = sprintf('F%d', uA);
    fprintf('\n-- Baris DX F%d ber-taper (descDoc) --\n', uA);
    nkf = 0; vnums = [];
    for k=1:numel(rows)
        r = rows{k};
        if ~strcmp(strtrim(char(r.fNum)), tgt), continue; end
        V = pivcore.io.grain4Desc.normVerts(r.taperVerts);
        if size(V,1) >= 2
            nkf = nkf+1; vnums(end+1) = size(V,1); %#ok<AGROW>
            fprintf('  frame %d : %d vertex, taperDeg=%.2f\n', round(r.frame), size(V,1), r.taperDeg);
        end
    end
    fprintf('TOTAL keyframe taper F%d = %d (jumlah vertex: %s)\n', uA, nkf, mat2str(vnums));
    if nkf < 2, fprintf(2, '>> <2 keyframe -> interpolasi TAK jalan (butuh >=2).\n'); end
    if numel(unique(vnums))>1, fprintf(2, '>> jumlah vertex BEDA antar-keyframe -> lerp gagal -> sample kosong.\n'); end

    % cache
    fprintf('\n-- Cache taperSamples --\n');
    if isa(h.taperSamples,'containers.Map')
        ks = h.taperSamples.keys;
        if isempty(ks), fprintf(2,'  CACHE KOSONG (belum rebuild).\n'); end
        for k=1:numel(ks)
            S = h.taperSamples(ks{k});
            ns = 0; if isfield(S,'samples'), ns = numel(pivcore.io.grain4Interp.tocell(S.samples)); end
            fprintf('  %s : %d sample, keyFrames=%s\n', ks{k}, ns, mat2str(round(S.keyFrames)));
        end
    end

    % objek tergambar
    fprintf('\n-- Objek di axMain --\n');
    for tag = {'storedTaper','taperInterp','taperInterpRef'}
        n = numel(findall(h.axMain,'Tag',tag{1}));
        fprintf('  %-16s : %d objek\n', tag{1}, n);
    end
    fprintf('=== selesai ===\n');
end
