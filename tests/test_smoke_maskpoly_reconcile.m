function test_smoke_maskpoly_reconcile()
%TEST_SMOKE_MASKPOLY_RECONCILE  Uji engine sinkronisasi jumlah vertex antar-keyframe
%   (maskPoly.reconcileVertexCount / insertVertexAll / removeVertexAll / match*).
%   Fitur: edit polygon TUNGGAL berkeyframe — tambah/hapus titik di 1 frame otomatis
%   merambat ke SEMUA keyframe agar K tetap seragam & interpVerts tetap sah.
%
%   Jalankan: grain_setup; test_smoke_maskpoly_reconcile   (SELALU R2025b)
    fprintf('\n=== TEST maskPoly reconcile vertex ===\n');
    grain_setup();
    mp = @pivanalyzemat.core.maskPoly;
    MP = pivanalyzemat.core.maskPoly; %#ok<NASGU>

    sq = @(cx,cy,r)[cx-r cy-r; cx+r cy-r; cx+r cy+r; cx-r cy+r];  % 4 titik CCW-ish

    % --- Polygon 2 keyframe, K=4 seragam ---
    pg = struct('enabled',true,'fill',[],'keyframes', struct( ...
        'frame_index',{1,10}, ...
        'vertices',{sq(100,100,30), sq(200,100,30)}));
    assert(size(pg.keyframes(1).vertices,1)==4 && size(pg.keyframes(2).vertices,1)==4);

    % === A. TAMBAH 1 titik di frame 10 (di antara titik 2 & 3 = sisi kanan) ===
    Vold = pg.keyframes(2).vertices;                 % 4 titik
    Vnew = [Vold(1:2,:); 232 100; Vold(3:4,:)];      % sisip titik baru di indeks 3
    [pg2, msgA] = pivanalyzemat.core.maskPoly.reconcileVertexCount(pg, 10, Vold, Vnew);
    pg2 = i_upsert(pg2, 10, Vnew);                    % pemanggil upsert keyframe curFrame
    K = arrayfun(@(k) size(k.vertices,1), pg2.keyframes);
    assert(all(K==5), sprintf('A: K tak seragam 5 -> [%s]', num2str(K)));
    assert(contains(msgA,'+1'), 'A: pesan tambah salah');
    % keyframe frame 1 (yg lain) harus dapat titik sisipan di indeks 3 = titik tengah
    % segmen antara vertex 2 & 3 polygon lama frame 1.
    V1 = pg2.keyframes(1).vertices;
    Vo1 = sq(100,100,30);
    expMid = (Vo1(2,:)+Vo1(3,:))/2;
    assert(norm(V1(3,:)-expMid) < 1e-9, 'A: titik sisipan frame-1 bukan titik tengah segmen');
    fprintf('  A tambah titik: K semua=5, sisipan frame-1 = titik tengah OK.\n');

    % interpVerts tetap sah (K=5, tak melompat): frame 5 cx antara 100 & 200
    V5 = pivanalyzemat.core.maskPoly.interpVerts(pg2, 5, 10);
    assert(size(V5,1)==5, 'A: interp K!=5');
    cx = mean(V5(:,1)); assert(cx>100 && cx<232, sprintf('A: interp cx=%.1f',cx));
    fprintf('  A interpVerts frame-5 K=5 cx=%.1f OK.\n', cx);

    % === B. HAPUS titik (indeks 3, yg barusan disisip) di frame 10 -> kembali K=4 ===
    Vold2 = pg2.keyframes(2).vertices;               % 5 titik
    Vnew2 = Vold2([1 2 4 5],:);                       % buang indeks 3
    [pg3, msgB] = pivanalyzemat.core.maskPoly.reconcileVertexCount(pg2, 10, Vold2, Vnew2);
    pg3 = i_upsert(pg3, 10, Vnew2);
    K3 = arrayfun(@(k) size(k.vertices,1), pg3.keyframes);
    assert(all(K3==4), sprintf('B: K tak kembali 4 -> [%s]', num2str(K3)));
    assert(contains(msgB,'-1'), 'B: pesan hapus salah');
    fprintf('  B hapus titik: K semua kembali 4 OK.\n');

    % === C. Guard K>=3 (tak boleh turun di bawah segitiga) ===
    tri = struct('enabled',true,'fill',[],'keyframes', struct( ...
        'frame_index',{1,5}, 'vertices',{[0 0;10 0;5 10],[2 2;12 2;7 12]}));
    pgC = pivanalyzemat.core.maskPoly.removeVertexAll(tri, 2);
    KC = arrayfun(@(k) size(k.vertices,1), pgC.keyframes);
    assert(all(KC==3), 'C: segitiga turun di bawah 3 titik');
    fprintf('  C guard K>=3 OK.\n');

    % === D. No-op saat K sama ===
    [pgD, msgD] = pivanalyzemat.core.maskPoly.reconcileVertexCount(pg, 10, sq(200,100,30), sq(210,100,30));
    assert(isempty(msgD), 'D: mestinya no-op');
    KD = arrayfun(@(k) size(k.vertices,1), pgD.keyframes);
    assert(all(KD==4), 'D: K berubah padahal K sama');
    fprintf('  D no-op K-sama OK.\n');

    % === E. Normalize masih menerima hasil (K seragam) ===
    poly = struct('enabled',true,'fill',255,'polygons',pg3);
    np = pivanalyzemat.core.maskPoly.normalize(poly);
    assert(np.enabled && numel(np.polygons)==1, 'E: normalize buang polygon valid');
    assert(numel(np.polygons(1).keyframes)==2, 'E: keyframe hilang');
    fprintf('  E normalize hasil reconcile OK.\n');

    fprintf('=== LULUS ===\n');
end

function pg = i_upsert(pg, fr, V)
    kf1 = struct('frame_index',round(fr),'vertices',double(V));
    kf = pg.keyframes;
    idx = find([kf.frame_index]==round(fr),1);
    if isempty(idx); kf(end+1)=kf1; else; kf(idx)=kf1; end
    [~,o]=sort([kf.frame_index]); pg.keyframes = kf(o);
end
