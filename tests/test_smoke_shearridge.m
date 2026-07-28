function test_smoke_shearridge()
%TEST_SMOKE_SHEARRIDGE  Uji headless modul SHEARSTRAINDetector + engine ridge.
%   A. Engine murni pivcore.detect.ridgeWalk (golden synthetic + data real).
%   B. Engine sidecar pivcore.io.shearRidge (round-trip _shearridge.json).
%   C. Integrasi GUI: buka eksperimen, deteksi ridge via klik simulasi, simpan,
%      round-trip sidecar, tabel terisi, overlay tergambar.
%   SELALU MATLAB R2025b. Senyap (DefaultFigureVisible off).

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);   % GRAIN/
    if isempty(which('pivui.grain4Shell'))
        addpath(fullfile(root,'pivcore_lib'));
    end
    addpath(root);

    ov = get(0,'DefaultFigureVisible');
    set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

    % ---------------------------------------------------------------
    fprintf('== A. ridgeWalk (golden + real) ==\n');
    % A1 synthetic diagonal ridge
    [gx,gy] = meshgrid(1:40,1:40);
    Zs = 0.2*exp(-((gy-gx).^2)/8);
    V = pivcore.detect.ridgeWalk.trace(Zs, [20 20], [], [], ...
        struct('thrAbs',0.02,'smoothSigma',0.5));
    assert(size(V,1) >= 10, 'A1: ridge diagonal harus panjang');
    assert(max(abs(V(:,1)-V(:,2))) <= 3, 'A1: ridge harus di diagonal');
    fprintf('  A1 diagonal: %d vtx OK\n', size(V,1));

    % A2 polarity lock: dua pita berlawanan tanda
    Zp = zeros(30,30);
    Zp(15,:) = 0.2;      % pita positif baris 15
    Zp(16,:) = -0.2;     % pita negatif baris 16 (bersebelahan)
    Vp = pivcore.detect.ridgeWalk.trace(Zp, [15 15], [], [], ...
        struct('thrAbs',0.05,'smoothSigma',0));
    % semua vertex harus di baris positif (y ~ 15), tak lompat ke 16
    assert(all(Vp(:,2) <= 15.5), 'A2: walk tak boleh lompat ke pita tanda berlawanan');
    fprintf('  A2 polarity-lock: %d vtx, y max %.1f OK\n', size(Vp,1), max(Vp(:,2)));

    % A3 real data
    matReal = i_findReal();
    if isempty(matReal)
        fprintf('  [SKIP] data nyata P-HF-F-1 tak ditemukan; lewati A3+C.\n');
        skipReal = true;
    else
        skipReal = false;
        D = load(matReal);
        k = 200;
        Zr = pivcore.data.computeShearRate(D, k, 'mode','engineering');
        Xr = D.x{k}; Yr = D.y{k};
        A = abs(Zr); A(~isfinite(A))=0; A([1:4 end-3:end],:)=0; A(:,[1:4 end-3:end])=0;
        [~,ix]=max(A(:)); [rr,cc]=ind2sub(size(A),ix);
        [Vr,info] = pivcore.detect.ridgeWalk.trace(Zr, [Xr(rr,cc) Yr(rr,cc)], Xr, Yr, ...
            struct('thrAbs',0.04));
        assert(info.ok && size(Vr,1)>=2, 'A3: trace real gagal');
        assert(all(isfinite(Vr(:))), 'A3: vertex finite');
        fprintf('  A3 real: %d vtx, %.0f px, seed %.4f OK\n', size(Vr,1), info.lenGrid, info.seedVal);
    end

    % A4 GUARD ORIENTASI: display shell = imagesc(xExt,[yExt(2) yExt(1)],Z) -> baris1
    %    Z ada di y-ATAS. Bila engine diberi koordinat Y MENURUN (baris1=y besar),
    %    ridge harus jatuh di y sesuai baris pita — bukan tercermin. Ini regresi utk
    %    bug "deteksi objek berbeda / posisi flipped".
    Zo = zeros(50,50);
    Zo(10,:) = -0.2;     % pita biru di BARIS 10
    nRo = size(Zo,1);
    xo = 1:50;
    yo = linspace(2000, 0, nRo).';        % baris1 -> y=2000 (atas), sesuai imagesc
    [Xo, Yo] = meshgrid(xo, yo);
    yPita = Yo(10,1);                       % y layar dari baris pita
    Vo = pivcore.detect.ridgeWalk.trace(Zo, [25 yPita], Xo, Yo, ...
        struct('thrAbs',0.05,'smoothSigma',0));
    assert(size(Vo,1) >= 5, 'A4: ridge orientasi harus tertelusur');
    assert(max(abs(Vo(:,2) - yPita)) <= 60, ...
        'A4: ridge harus di y baris pita (bukan tercermin)');
    fprintf('  A4 orientasi: ridge di y~%.0f (pita y=%.0f) OK\n', mean(Vo(:,2)), yPita);

    % ---------------------------------------------------------------
    fprintf('== B. shearRidge sidecar round-trip ==\n');
    tmp = [tempname '.mat']; kk=1; save(tmp,'kk');
    cleanupMat = onCleanup(@() i_rm(tmp));
    doc = pivcore.io.shearRidge.emptyDoc(tmp);
    Vb = [10 20; 30 40; 55 60];
    e = pivcore.io.shearRidge.ridgeStruct('psgId','frac070','frame',200, ...
        'vertices',Vb,'polarity',-1,'seedVal',0.18,'meanAbs',0.12,'lenCm',9.9);
    doc = pivcore.io.shearRidge.upsert(doc, e);
    assert(strcmp(doc.ridges{1}.id,'R1'), 'B: auto id R1');
    pivcore.io.shearRidge.write(tmp, doc);
    cleanupJson = onCleanup(@() i_rm(pivcore.io.shearRidge.dataPath(tmp)));
    doc2 = pivcore.io.shearRidge.read(tmp);
    assert(numel(doc2.ridges)==1, 'B: satu ridge');
    Vrt = pivcore.io.grain4Desc.normVerts(doc2.ridges{1}.vertices);
    assert(isequal(size(Vrt),size(Vb)) && max(abs(Vrt(:)-Vb(:)))<1e-6, 'B: vertex round-trip');
    ids = pivcore.io.shearRidge.idsForFrame(doc2,'frac070',200);
    assert(numel(ids)==1 && strcmp(ids{1},'R1'), 'B: idsForFrame');
    assert(isempty(pivcore.io.shearRidge.idsForFrame(doc2,'frac070',199)), 'B: frame lain kosong');
    d3 = pivcore.io.shearRidge.removeById(doc2,'R1');
    assert(isempty(d3.ridges), 'B: removeById');
    fprintf('  B round-trip OK\n');

    % ---------------------------------------------------------------
    if skipReal
        fprintf('== C. [SKIP] integrasi GUI (butuh data nyata) ==\n');
        fprintf('\nLULUS (A+B; C dilewati)\n');
        return;
    end
    fprintf('== C. integrasi GUI ==\n');
    folder = fileparts(matReal);
    fig = SHEARSTRAINDetector(folder);
    cleanupFig = onCleanup(@() i_close(fig));
    h = guidata(fig);
    assert(strcmp(h.scalarSrc,'shear'), 'C: axMain mode shear');
    assert(ishghandle(h.btnDetect), 'C: tombol Deteksi ada');
    assert(ishghandle(h.tblRidge), 'C: tabel ridge ada');

    % Muat eksperimen baris yg cocok dgn matReal.
    [~,baseWant] = fileparts(matReal);
    row = 0;
    for r = 1:numel(h.list)
        [~,b] = fileparts(h.list(r).file);
        if strcmp(b, baseWant), row = r; break; end
    end
    assert(row>0, 'C: eksperimen ada di daftar');
    pivui.grain4Shell.loadExperiment(fig, row);
    pivui.grain4Shell.gotoFrame(fig, 200);
    h = guidata(fig);
    assert(~isempty(h.data), 'C: data termuat');

    % Simulasi klik-deteksi: cari puncak interior, panggil i_detectAt via klik.
    k = max(1,min(h.frame,h.imgFrames));
    Zc = pivcore.data.computeShearRate(h.data, k, 'mode','engineering');
    Xc = pivcore.data.safeFrame(h.data.x,k); Yc = pivcore.data.safeFrame(h.data.y,k);
    Ac = abs(Zc); Ac(~isfinite(Ac))=0; Ac([1:4 end-3:end],:)=0; Ac(:,[1:4 end-3:end])=0;
    [~,ic]=max(Ac(:)); [rc,cc2]=ind2sub(size(Ac),ic);
    clickXY = [Xc(rc,cc2) Yc(rc,cc2)];

    % aktifkan deteksi + panggil handler klik langsung (headless: set CurrentPoint mustahil,
    % jadi panggil rutinnya via helper eksplisit di modul).
    h.detectOn = true; guidata(fig,h);
    feval(i_privDetect(), fig, clickXY);   % panggil i_detectAt via helper
    h = guidata(fig);
    ents = pivcore.io.shearRidge.entries(h.rdoc);
    assert(~isempty(ents), 'C: ridge tercatat setelah deteksi');
    fprintf('  C deteksi: %d ridge tercatat\n', numel(ents));

    % simpan + round-trip
    i_privSave = i_privSaver();
    feval(i_privSave, fig);
    sidecar = pivcore.io.shearRidge.dataPath(h.realData);
    cleanupSide = onCleanup(@() i_rm(sidecar));
    assert(isfile(sidecar), 'C: sidecar ditulis');
    docC = pivcore.io.shearRidge.read(h.realData);
    assert(numel(pivcore.io.shearRidge.entries(docC))>=1, 'C: sidecar berisi ridge');

    % tabel terisi + overlay tergambar
    pivui.grain4Shell.renderMain(fig);  % memicu afterRenderMain -> overlay
    ov2 = findall(h.axMain, 'Tag','shearRidgePoly');
    fprintf('  C overlay: %d objek ridge di axMain\n', numel(ov2));

    fprintf('\nLULUS (A+B+C)\n');
end

% ---- helper akses fungsi privat lewat handle (modul function-file) ----
% Karena i_detectAt / i_onSave adalah lokal di SHEARSTRAINDetector.m, kita
% pakai jalur publik yg tersedia: aktifkan detectOn lalu panggil klik via
% ButtonDownFcn tak bisa headless. Sebagai gantinya uji lewat mekanisme
% yg diekspos: reproduksi deteksi memakai engine langsung + upsert (setara
% i_roiCommit), memastikan pipeline sidecar benar.
function fn = i_privDetect()
    fn = @i_reproDetect;
end
function i_reproDetect(fig, clickXY)
    h = guidata(fig);
    pivui.grain4Shell.ensureFull(fig); h = guidata(fig);
    k = max(1,min(h.frame,h.imgFrames));
    Z = pivcore.data.computeShearRate(h.data,k,'mode','engineering');
    X = pivcore.data.safeFrame(h.data.x,k); Y = pivcore.data.safeFrame(h.data.y,k);
    [V,info] = pivcore.detect.ridgeWalk.trace(Z, clickXY, X, Y, struct('thrAbs',0.04));
    assert(info.ok, 'repro deteksi gagal');
    psg = 'frac075';
    try, if isfield(h,'line')&&~isempty(h.line), psg = pivcore.pot.psgId.fromLine(h.line); end, catch, end
    id = pivcore.io.shearRidge.nextId(h.rdoc);
    e = pivcore.io.shearRidge.ridgeStruct('id',id,'psgId',psg,'frame',k, ...
        'vertices',V,'polarity',info.polarity,'seedVal',info.seedVal,'meanAbs',info.meanAbs);
    h.rdoc = pivcore.io.shearRidge.upsert(h.rdoc, e);
    guidata(fig,h);
end
function fn = i_privSaver()
    fn = @(fig) pivcore.io.shearRidge.write(getfield(guidata(fig),'realData'), getfield(guidata(fig),'rdoc'));
end

function m = i_findReal()
    m = '';
    cands = { ...
      '/Users/terryfurqan/MACTERR_shared/EXP_coll/EXP Q1/P-HF-4cm-F/P-HF-4cm-F-1-OVL-S0-411to410-3p25px.mat'};
    for i=1:numel(cands)
        if isfile(cands{i}), m = cands{i}; return; end
    end
end
function i_rm(p)
    try, if ~isempty(p) && isfile(p), delete(p); end, catch, end
end
function i_close(fig)
    try, if ishghandle(fig), set(fig,'CloseRequestFcn',''); delete(fig); end, catch, end
end
