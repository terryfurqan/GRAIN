function test_smoke_grain4faultgeom()
%TEST_SMOKE_GRAIN4FAULTGEOM  Smoke test engine pivcore.io.grain4FaultGeom (murni/
%   headless). Blok:
%     A  fungsi angka murni: polylineLenPx / lenCm / angleDeg (regresi) /
%        cmPerPxFromGeom / growthRate / dieOutRate / nearestFsMaxToNuc
%     B  round-trip write/read sidecar `_faultgeom.json` (Nx2 vertex + NaN<->null)
%        + geomFor/setGeomFor/clearGeomFor (per psgId,F#)
%
%   SENYAP; file sementara di tempdir. SELALU MATLAB R2025b.

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(fileparts(here)));
    addpath(fullfile(fileparts(here), 'pivcore_lib'));
    try, grain_setup; catch, end

    E = @pivcore.io.grain4FaultGeom;   % alias tak bisa utk static -> pakai nama penuh
    ng = 'pivcore.io.grain4FaultGeom';
    fprintf('== test_smoke_grain4faultgeom ==\n');

    % ================= BLOK A: angka murni =================
    % Polyline 3 vertex: (0,0)->(3,4)->(3,4+12=16)? gunakan segmen jelas.
    %   (0,0)->(3,4): len 5 ; (3,4)->(3,10): len 6 -> total 11.
    V = [0 0; 3 4; 3 10];
    L = pivcore.io.grain4FaultGeom.polylineLenPx(V);
    assert(abs(L - 11) < 1e-9, 'A1 polylineLenPx=%.6f (exp 11)', L);

    % < 2 vertex -> 0
    assert(pivcore.io.grain4FaultGeom.polylineLenPx([2 3]) == 0, 'A2 single vertex len');

    % lenCm: cmPerPx=0.5 -> 11*0.5 = 5.5
    Lcm = pivcore.io.grain4FaultGeom.lenCm(V, 0.5);
    assert(abs(Lcm - 5.5) < 1e-9, 'A3 lenCm=%.6f (exp 5.5)', Lcm);
    assert(isnan(pivcore.io.grain4FaultGeom.lenCm(V, NaN)), 'A4 lenCm NaN cmPerPx');
    assert(isnan(pivcore.io.grain4FaultGeom.lenCm(V, -1)),  'A5 lenCm cmPerPx<=0');

    % angleDeg: garis lurus slope 1 -> 45 deg (regresi sempurna)
    Vl = [0 0; 1 1; 2 2; 3 3];
    d45 = pivcore.io.grain4FaultGeom.angleDeg(Vl);
    assert(abs(d45 - 45) < 1e-9, 'A6 angleDeg=%.6f (exp 45)', d45);
    % slope -1 -> -45
    Vm = [0 0; 1 -1; 2 -2];
    dm = pivcore.io.grain4FaultGeom.angleDeg(Vm);
    assert(abs(dm + 45) < 1e-9, 'A7 angleDeg=%.6f (exp -45)', dm);
    % horizontal -> 0
    Vh = [0 5; 2 5; 4 5];
    assert(abs(pivcore.io.grain4FaultGeom.angleDeg(Vh)) < 1e-9, 'A8 angleDeg horizontal');
    % vertical -> +-90 (normDeg -> 90)
    Vv = [3 0; 3 5; 3 9];
    dv = pivcore.io.grain4FaultGeom.angleDeg(Vv);
    assert(abs(abs(dv) - 90) < 1e-9, 'A9 angleDeg vertical=%.6f (exp 90)', dv);
    % <2 vertex valid -> NaN
    assert(isnan(pivcore.io.grain4FaultGeom.angleDeg([1 2])), 'A10 angleDeg single NaN');

    % cmPerPxFromGeom: dxCm=17.55, width=3000 -> 0.00585
    cpp = pivcore.io.grain4FaultGeom.cmPerPxFromGeom(17.55, 3000);
    assert(abs(cpp - 17.55/3000) < 1e-12, 'A11 cmPerPx=%.8f', cpp);
    assert(isnan(pivcore.io.grain4FaultGeom.cmPerPxFromGeom(0, 3000)), 'A12 dxCm<=0 NaN');
    assert(isnan(pivcore.io.grain4FaultGeom.cmPerPxFromGeom(10, 0)),   'A13 width<=0 NaN');

    % growthRate: len=5.5 cm, dFrame=10, dt=2 -> 5.5/20 = 0.275
    g = pivcore.io.grain4FaultGeom.growthRate(5.5, 10, 2);
    assert(abs(g - 0.275) < 1e-9, 'A14 growthRate=%.6f (exp 0.275)', g);
    % dieOutRate sama rumus
    do = pivcore.io.grain4FaultGeom.dieOutRate(5.5, 10, 2);
    assert(abs(do - 0.275) < 1e-9, 'A15 dieOutRate=%.6f', do);
    % dFrame<=0 -> NaN
    assert(isnan(pivcore.io.grain4FaultGeom.growthRate(5.5, 0, 2)), 'A16 growth dFrame0 NaN');
    % dt fallback 10 bila tak diberi
    g2 = pivcore.io.grain4FaultGeom.growthRate(10, 5);   % 10/(5*10)=0.2
    assert(abs(g2 - 0.2) < 1e-9, 'A17 growth dt-fallback=%.6f (exp 0.2)', g2);

    % nearestFsMaxToNuc: fs=[20 90 120], nuc=100 -> nearest 90 (dd=10)
    [fr, dd] = pivcore.io.grain4FaultGeom.nearestFsMaxToNuc([20 90 120], 100);
    assert(fr == 90 && dd == 10, 'A18 nearestFsMax fr=%g dd=%g (exp 90,10)', fr, dd);
    [fr2, dd2] = pivcore.io.grain4FaultGeom.nearestFsMaxToNuc([], 100);
    assert(isnan(fr2) && isnan(dd2), 'A19 nearestFsMax empty NaN');

    % angleDegRel: garis 45° dgn ref 10° -> 35°. ref NaN -> = angleDeg (45).
    assert(abs(pivcore.io.grain4FaultGeom.angleDegRel(Vl, 10) - 35) < 1e-9, 'A20 angleDegRel 45-10=35');
    assert(abs(pivcore.io.grain4FaultGeom.angleDegRel(Vl, NaN) - 45) < 1e-9, 'A21 angleDegRel ref NaN -> 45');
    % normalisasi (-90,90]: 45° dgn ref -50° -> 95° -> -85°.
    assert(abs(pivcore.io.grain4FaultGeom.angleDegRel(Vl, -50) - (-85)) < 1e-9, 'A22 angleDegRel wrap');
    fprintf('  [A] angka murni OK\n');

    % ================= BLOK B: round-trip sidecar =================
    td = tempname; mkdir(td);
    cleaner = onCleanup(@() rmdir(td,'s')); %#ok<NASGU>
    df = fullfile(td, 'P-TEST-4cm-F.mat');

    doc = pivcore.io.grain4FaultGeom.emptyDoc(df);
    assert(isempty(pivcore.io.grain4FaultGeom.geomFor(doc,'psgA','F1')), 'B1 empty geomFor');

    % 2-FASE: F1 punya NUC (fase default) + DIE (fase 'die'). F2 hanya NUC (N=1).
    Vn = [10 20; 33.5 44.5; 60 70];   % nukleasi 3 vertex
    Vd = [70 80; 100 130];            % die-out 2 vertex (BENTUK beda)
    V2 = [5 5];                        % 1 vertex (N=1 -> uji round-trip Nx2 stabil)
    doc = pivcore.io.grain4FaultGeom.setGeomFor(doc, 'psgA', 'F1', Vn, 120);           % nuc
    doc = pivcore.io.grain4FaultGeom.setGeomFor(doc, 'psgA', 'F1', Vd, 240, 'die');     % die (F1 sama)
    doc = pivcore.io.grain4FaultGeom.setGeomFor(doc, 'psgA', 'F2', V2, NaN);

    pivcore.io.grain4FaultGeom.write(df, doc);
    p = pivcore.io.grain4FaultGeom.dataPath(df);
    assert(isfile(p), 'B2 file _faultgeom.json ditulis');

    d2 = pivcore.io.grain4FaultGeom.read(df);
    e1 = pivcore.io.grain4FaultGeom.geomFor(d2, 'psgA', 'F1');
    assert(~isempty(e1), 'B3 geomFor F1 ada');
    % Fase NUC
    assert(isequal(size(e1.verticesNuc),[3 2]), 'B4 verticesNuc F1 3x2 (got %s)', mat2str(size(e1.verticesNuc)));
    assert(max(abs(e1.verticesNuc(:) - Vn(:))) < 1e-9, 'B5 verticesNuc nilai roundtrip');
    assert(e1.frameRefNuc == 120, 'B6 frameRefNuc F1=120');
    % Fase DIE (bentuk beda, tak menimpa NUC)
    assert(isequal(size(e1.verticesDie),[2 2]), 'B7 verticesDie F1 2x2 (got %s)', mat2str(size(e1.verticesDie)));
    assert(max(abs(e1.verticesDie(:) - Vd(:))) < 1e-9, 'B8 verticesDie nilai roundtrip');
    assert(e1.frameRefDie == 240, 'B9 frameRefDie F1=240');
    % phaseVerts helper
    assert(isequal(pivcore.io.grain4FaultGeom.phaseVerts(e1,'nuc'), Vn), 'B10 phaseVerts nuc');
    assert(isequal(pivcore.io.grain4FaultGeom.phaseVerts(e1,'die'), Vd), 'B11 phaseVerts die');

    e2 = pivcore.io.grain4FaultGeom.geomFor(d2, 'psgA', 'F2');
    assert(~isempty(e2), 'B12 geomFor F2 ada');
    assert(isequal(size(e2.verticesNuc),[1 2]), 'B13 verticesNuc F2 1x2 (N=1 stabil)');
    assert(isempty(e2.verticesDie), 'B14 verticesDie F2 kosong (tak diukur)');

    % clearGeomFor F1 -> tinggal F2
    d3 = pivcore.io.grain4FaultGeom.clearGeomFor(d2, 'psgA', 'F1');
    assert(isempty(pivcore.io.grain4FaultGeom.geomFor(d3,'psgA','F1')), 'B15 F1 dihapus');
    assert(~isempty(pivcore.io.grain4FaultGeom.geomFor(d3,'psgA','F2')), 'B16 F2 tetap');

    % KOMPAT LAMA: entri 1-fase (field 'vertices'/'frameRef') -> migrasi ke Nuc.
    legacyRaw = struct('formatName','x','formatVersion',1,'source','y','meta',struct(), ...
        'faults',{{struct('psgId','pL','fNum','F3','vertices',{{[1 2],[3 4]}},'frameRef',55)}});
    eL = pivcore.io.grain4FaultGeom.normEntry(legacyRaw.faults{1});
    assert(isequal(size(eL.verticesNuc),[2 2]), 'B17 legacy vertices -> verticesNuc');
    assert(eL.frameRefNuc == 55, 'B18 legacy frameRef -> frameRefNuc');
    assert(isempty(eL.verticesDie), 'B19 legacy verticesDie kosong');

    % read file tak-ada -> emptyDoc (tanpa error)
    d4 = pivcore.io.grain4FaultGeom.read(fullfile(td,'nope.mat'));
    assert(isstruct(d4) && isempty(pivcore.io.grain4FaultGeom.tocell(d4.faults)), 'B20 read absent -> empty');

    % REFERENSI HORIZONTAL round-trip: set dari 2 titik (miring 5°) -> simpan -> baca.
    assert(isnan(pivcore.io.grain4FaultGeom.refHorizonDeg(doc)), 'B21 ref default NaN');
    docR = pivcore.io.grain4FaultGeom.setRefHorizonFromPts(doc, [0 0], [10 10*tand(5)]);
    assert(abs(pivcore.io.grain4FaultGeom.refHorizonDeg(docR) - 5) < 1e-6, 'B22 ref set 5°');
    pivcore.io.grain4FaultGeom.write(df, docR);
    dR2 = pivcore.io.grain4FaultGeom.read(df);
    assert(abs(pivcore.io.grain4FaultGeom.refHorizonDeg(dR2) - 5) < 1e-6, 'B23 ref round-trip 5°');
    % ref bertahan bersama entri 2-fase (F1 nuc+die masih ada).
    assert(~isempty(pivcore.io.grain4FaultGeom.geomFor(dR2,'psgA','F1')), 'B24 entri tetap ada dgn ref');
    fprintf('  [B] round-trip sidecar OK\n');

    fprintf('== test_smoke_grain4faultgeom LULUS ==\n');
end
