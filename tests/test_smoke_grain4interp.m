function test_smoke_grain4interp()
%TEST_SMOKE_GRAIN4INTERP  Engine pivcore.io.grain4Interp (murni/headless):
%   A  math: lerpVerts golden · validateKeyframes (ok/mismatch/dup/<2) · buildSamples
%      (linear midpoint + jumlah sample + piecewise 3 keyframe)
%   B  sidecar round-trip: setTrackFor + write + read + trackFor + vertsAtFrame +
%      clearTrackFor
%   SELALU MATLAB R2025b.

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(fileparts(here)));
    addpath(fullfile(fileparts(here), 'pivcore_lib'));
    try, grain_setup; catch, end
    P = @pivcore.io.grain4Interp;

    fprintf('==== A. Math interpolasi ====\n');
    % lerpVerts golden: midpoint dua polyline sejajar.
    V0 = [0 0; 0 10]; V1 = [10 0; 10 10];
    Vm = pivcore.io.grain4Interp.lerpVerts(V0, V1, 0.5);
    assert(isequal(Vm,[5 0; 5 10]), 'A: lerpVerts midpoint = [5 0;5 10]');
    assert(isequal(pivcore.io.grain4Interp.lerpVerts(V0,V1,0), V0), 'A: t=0 -> V0');
    assert(isequal(pivcore.io.grain4Interp.lerpVerts(V0,V1,1), V1), 'A: t=1 -> V1');
    % clamp t di luar [0,1]
    assert(isequal(pivcore.io.grain4Interp.lerpVerts(V0,V1,-3), V0), 'A: t<0 -> clamp V0');
    % mismatch jumlah vertex -> error
    err = false;
    try, pivcore.io.grain4Interp.lerpVerts([0 0;0 1], [0 0;0 1;0 2], 0.5); catch, err = true; end
    assert(err, 'A: lerpVerts beda jumlah vertex -> error');

    mk = @(f,V) struct('frame',f,'vertices',V);
    % validateKeyframes OK (2 keyframe, jumlah vertex sama)
    kf = {mk(10,V0), mk(20,V1)};
    [ok,msg,N] = pivcore.io.grain4Interp.validateKeyframes(kf);
    assert(ok && N==2, 'A: validate OK N=2 (msg=%s)', msg);
    % mismatch counts
    [ok2,msg2] = pivcore.io.grain4Interp.validateKeyframes({mk(10,[0 0;0 1]), mk(20,[0 0;0 1;0 2])});
    assert(~ok2 && contains(msg2,'BEDA'), 'A: validate beda vertex -> gagal');
    % <2 keyframe
    [ok3] = pivcore.io.grain4Interp.validateKeyframes({mk(10,V0)});
    assert(~ok3, 'A: validate <2 keyframe -> gagal');
    % frame kembar
    [ok4,msg4] = pivcore.io.grain4Interp.validateKeyframes({mk(10,V0), mk(10,V1)});
    assert(~ok4 && contains(msg4,'kembar'), 'A: validate frame kembar -> gagal');

    % buildSamples: 2 keyframe frame 10..20 -> 11 sample; frame 15 = midpoint.
    S = pivcore.io.grain4Interp.buildSamples(kf, 0.01, 0);
    assert(numel(S)==11, 'A: buildSamples 11 sample (10..20), dapat %d', numel(S));
    s1 = S{1}; assert(s1.frame==10 && isequal(pivcore.io.grain4Desc.normVerts(s1.vertices),V0), 'A: sample1 = keyframe awal');
    s6 = S{6}; assert(s6.frame==15 && isequal(pivcore.io.grain4Desc.normVerts(s6.vertices),[5 0;5 10]), ...
        'A: sample frame15 = midpoint');
    assert(isfinite(s6.lenCm) && abs(s6.lenCm-0.1)<1e-9, 'A: lenCm frame15 = 0.1 (dapat %.4f)', s6.lenCm);
    sEnd = S{end}; assert(sEnd.frame==20 && isequal(pivcore.io.grain4Desc.normVerts(sEnd.vertices),V1), 'A: sampleEnd = keyframe akhir');
    % piecewise 3 keyframe: kf tengah menekuk -> sample tengah ikut keyframe tengah.
    Vk = [5 0; 5 5];   % keyframe tengah frame 15 (BEDA dari lerp lurus)
    S3 = pivcore.io.grain4Interp.buildSamples({mk(10,V0), mk(15,Vk), mk(20,V1)}, 0.01, 0);
    assert(numel(S3)==11, 'A: piecewise 11 sample');
    got15 = pivcore.io.grain4Desc.normVerts(S3{6}.vertices);
    assert(isequal(got15,Vk), 'A: frame15 = keyframe tengah (piecewise), dapat %s', mat2str(got15));
    fprintf('[OK] A math (lerp/validate/buildSamples/piecewise)\n');

    fprintf('==== B. Sidecar round-trip ====\n');
    tf = fullfile(tempdir, 'GRAIN4INTERP_exp.mat');
    doc = pivcore.io.grain4Interp.emptyDoc(tf);
    doc = pivcore.io.grain4Interp.setTrackFor(doc, 'psgA', 'F3', S, [10 20]);
    doc = pivcore.io.grain4Interp.setTrackFor(doc, 'psgA', 'F5', S3, [10 15 20]);
    pivcore.io.grain4Interp.write(tf, doc);
    d2 = pivcore.io.grain4Interp.read(tf);
    e3 = pivcore.io.grain4Interp.trackFor(d2, 'psgA', 'F3');
    assert(~isempty(e3), 'B: trackFor F3 ada');
    assert(isequal(sort(e3.keyFrames),[10 20]), 'B: keyFrames F3 = [10 20]');
    Vf15 = pivcore.io.grain4Interp.vertsAtFrame(e3, 15);
    assert(isequal(Vf15,[5 0;5 10]), 'B: vertsAtFrame F3 @15 = midpoint (round-trip)');
    e5 = pivcore.io.grain4Interp.trackFor(d2, 'psgA', 'F5');
    assert(isequal(pivcore.io.grain4Interp.vertsAtFrame(e5,15),[5 0;5 5]), 'B: F5 @15 = keyframe tengah');
    % normFtag ekuivalen 'F3'/'3'/3
    assert(~isempty(pivcore.io.grain4Interp.trackFor(d2,'psgA',3)), 'B: trackFor terima 3 (numerik)');
    % clearTrackFor
    d3 = pivcore.io.grain4Interp.clearTrackFor(d2, 'psgA', 'F3');
    assert(isempty(pivcore.io.grain4Interp.trackFor(d3,'psgA','F3')), 'B: clearTrackFor F3');
    assert(~isempty(pivcore.io.grain4Interp.trackFor(d3,'psgA','F5')), 'B: F5 tetap ada setelah clear F3');
    try, delete(pivcore.io.grain4Interp.dataPath(tf)); catch, end
    fprintf('[OK] B sidecar round-trip\n');

    % ================= C. INTEGRASI GUI (toggle Evolusi end-to-end) =================
    fprintf('==== C. Integrasi GUI (interpolasi ALWAYS-ON -> overlay + _faultinterp.json) ====\n');
    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>
    rootDir = ''; cand = {fullfile(grain_fixture_root(),'EXP_coll','EXP Q1','P-CON-4cm-F'), ...
                          fullfile(grain_fixture_root(),'EXP_coll','P-CON-4cm-F')};
    for i=1:numel(cand)
        if isfolder(cand{i}) && ~isempty(local_findMat(cand{i})), rootDir=cand{i}; break; end
    end
    if isempty(rootDir)
        fprintf('[SKIP] C: fixture tak ada.\n');
        fprintf('==== GRAIN4INTERP ENGINE SEMUA LULUS ✓ (C dilewati) ====\n'); return;
    end
    df = local_findMat(rootDir);
    sidecarGuard = i_guardSidecars(df); %#ok<NASGU>   % lindungi data user (restore auto)
    fig = GRAIN4(rootDir); cu = onCleanup(@() local_close(fig)); %#ok<NASGU>
    ipath = pivcore.io.grain4Interp.dataPath(df);
    if isfile(ipath), delete(ipath); end
    dpath = strrep(df,'.mat','_desc.json'); if isfile(dpath), delete(dpath); end
    idx = local_expIdx(fig, df); assert(idx>=1, 'C: exp fixture ada');
    pivui.grain4Shell.loadExperiment(fig, idx);
    h = guidata(fig);
    Fs = pivui.grain5Model.faultsForPsg(h.fdoc, h.activePsgId);
    assert(~isempty(Fs), 'C: perlu >=1 sesar');
    fA = Fs{1}; h.activeFaultId = fA.id;
    uN = pivui.grain5Model.faultUiNum(fA); psg = h.activePsgId; fTag = sprintf('F%d', round(uN));
    % 2 keyframe: PRP-FSR@30 (bidang) + ACT-FSR@50 (bidang, jumlah vertex SAMA, digeser).
    V0 = [400 300; 470 360]; V1 = [430 300; 500 360];   % 2 vertex masing2, bergeser +30 x
    mk = @(fr,poi,V) local_row(psg,fTag,fr,poi,V);
    rows = {mk(30,'PRP-FSR',V0), mk(50,'ACT-FSR',V1)};
    h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, psg, rows);
    % Overlay evolusi kini ALWAYS-ON (tak ada tombol/toggle): interpOn default true,
    % track dibangun otomatis saat keyframe bidang di-commit (via i_faultPolyCommit ->
    % i_rebuildInterpTrack). Di sini keyframe di-inject langsung, jadi bangun track via
    % engine publik (setara i_rebuildInterpTrack) lalu verifikasi overlay tampil sendiri.
    assert(isfield(h,'interpOn') && h.interpOn, 'C: interpOn=true ALWAYS-ON (default)');
    kf = { struct('frame',30,'vertices',V0), struct('frame',50,'vertices',V1) };
    [vok,~] = pivcore.io.grain4Interp.validateKeyframes(kf); assert(vok, 'C: keyframe valid');
    samples = pivcore.io.grain4Interp.buildSamples(kf, 1, 0);
    h.interpDoc = pivcore.io.grain4Interp.setTrackFor(h.interpDoc, psg, fTag, samples, [30 50]);
    guidata(fig, h);
    pivcore.io.grain4Interp.write(df, h.interpDoc);
    assert(isfile(ipath), 'C: _faultinterp.json ditulis');
    dChk = pivcore.io.grain4Interp.read(df);
    e = pivcore.io.grain4Interp.trackFor(dChk, psg, fTag);
    assert(~isempty(e), 'C: track F# tersimpan');
    % 30..50 -> 21 sample; frame 40 = midpoint [415 300;485 360].
    Vf40 = pivcore.io.grain4Interp.vertsAtFrame(e, 40);
    assert(isequal(Vf40,[415 300;485 360]), 'C: interp @40 = midpoint (dapat %s)', mat2str(Vf40));
    % Scrub ke frame 40 -> overlay cyan muncul OTOMATIS (Tag interpFaultPoly; always-on).
    pivui.grain4Shell.gotoFrame(fig, 40); h = guidata(fig);
    ov40 = findall(h.axMain,'Tag','interpFaultPoly');
    assert(~isempty(ov40), 'C: overlay cyan tampil @ frame antar-keyframe (always-on)');
    % Scrub ke keyframe 30 -> interp DILEWATI (keyframe manual hitam yg tampil).
    pivui.grain4Shell.gotoFrame(fig, 30); h = guidata(fig);
    ov30 = findall(h.axMain,'Tag','interpFaultPoly');
    assert(isempty(ov30), 'C: overlay cyan DILEWATI di frame keyframe');
    if isfile(ipath), delete(ipath); end
    if isfile(dpath), delete(dpath); end
    fprintf('[OK] C integrasi GUI (toggle/track/overlay/OFF)\n');

    % ============ D. BAYANGAN MERAH sesar-lain (visual aid hitung sesar) ============
    fprintf('==== D. Bayangan merah sesar-lain (otherFaultShadow) ====\n');
    h = guidata(fig);
    Fs = pivui.grain5Model.faultsForPsg(h.fdoc, h.activePsgId);
    uis = [];
    for i=1:numel(Fs), u = pivui.grain5Model.faultUiNum(Fs{i}); if isscalar(u)&&isfinite(u), uis(end+1)=round(u); end, end %#ok<AGROW>
    uis = unique(uis);
    if numel(uis) < 2
        fprintf('[SKIP] D: fixture <2 sesar di PSG (dapat %d) — butuh F-aktif + F-lain.\n', numel(uis));
    else
        uAct = uis(1); uOther = uis(2);          % amati uAct; bayangan utk uOther
        tOther = sprintf('F%d', uOther);
        % Rentang HIDUP F-lain: PRP-FSR@60 -> ACT-FSR@75 (bidang) -> X-FS@90.
        Vlast = [520 280; 590 350];              % bentuk ACT-FSR terakhir F-lain
        rowsO = {mk(60,'PRP-FSR',[500 280; 560 340]), ...
                 local_row(psg,tOther,75,'ACT-FSR',Vlast), ...
                 local_row(psg,tOther,90,'X-FS',zeros(0,2))};
        % Gabung dgn rows F-aktif (C) supaya keduanya ada; set utk PSG.
        allRows = [rows, rowsO];
        h.descDoc = pivcore.io.grain4Desc.setRowsForPsg(h.descDoc, psg, allRows);
        % Aktifkan F-AKTIF (uAct) + nyalakan interpolasi (bayangan ikut interpOn).
        fAct = []; for i=1:numel(Fs), if round(pivui.grain5Model.faultUiNum(Fs{i}))==uAct, fAct=Fs{i}; break; end, end
        h.activeFaultId = fAct.id; h.interpOn = true; guidata(fig, h);
        % Scrub ke frame 80 (di dalam hidup F-lain 60..90) -> bayangan MERAH tampil.
        pivui.grain4Shell.gotoFrame(fig, 80); h = guidata(fig);
        sh = findall(h.axMain,'Tag','otherFaultShadow','Type','line');
        assert(~isempty(sh), 'D: bayangan merah F-lain tampil @frame dalam hidupnya');
        Vsh = [get(sh(1),'XData').' get(sh(1),'YData').'];
        assert(isequal(round(Vsh),round(Vlast)), 'D: bayangan = copy vertex ACT-FSR terakhir F-lain');
        % Scrub ke frame 120 (di LUAR hidup F-lain) -> bayangan HILANG.
        if h.nF >= 120
            pivui.grain4Shell.gotoFrame(fig, 120); h = guidata(fig);
            assert(isempty(findall(h.axMain,'Tag','otherFaultShadow','Type','line')), ...
                'D: bayangan hilang di LUAR rentang hidup F-lain');
        end
        % Interp OFF -> bayangan tak muncul walau frame di dalam hidup.
        pivui.grain4Shell.gotoFrame(fig, 80);
        h = guidata(fig); h.interpOn = false; guidata(fig, h);
        pivui.grain4Shell.renderMain(fig); h = guidata(fig);
        assert(isempty(findall(h.axMain,'Tag','otherFaultShadow','Type','line')), ...
            'D: bayangan tak tampil saat interpolasi OFF');
        % Sesar AKTIF sendiri TAK dibayangi (skip uAct).
        h.interpOn = true; guidata(fig, h);
        pivui.grain4Shell.gotoFrame(fig, 80); h = guidata(fig);
        shAll = findall(h.axMain,'Tag','otherFaultShadow','Type','text');
        labs = arrayfun(@(t) strtrim(get(t,'String')), shAll, 'UniformOutput', false);
        assert(~any(strcmp(labs, sprintf('F%d',uAct))), 'D: sesar AKTIF tak ikut dibayangi');
        fprintf('[OK] D bayangan merah (tampil dalam-hidup, hilang luar/OFF, skip F-aktif)\n');
    end
    if isfile(ipath), delete(ipath); end
    if isfile(dpath), delete(dpath); end

    fprintf('==== GRAIN4INTERP SEMUA LULUS ✓ ====\n');
end

function df = local_findMat(dirPath)
    df = '';
    d = dir(fullfile(dirPath, '**', '*.mat'));
    for i = 1:numel(d)
        p = fullfile(d(i).folder, d(i).name);
        if isfile(strrep(p,'.mat','_faults.json')), df = p; return; end
    end
end
function idx = local_expIdx(fig, df)
    idx = -1; h = guidata(fig);
    if ~isfield(h,'list'), return; end
    for i=1:numel(h.list), if strcmp(h.list(i).file, df), idx=i; return; end, end
end
function r = local_row(psg,fTag,fr,poi,V)
    r = pivcore.io.grain4Desc.rowStruct(psg,fTag,fr,poi,NaN,'1','',' ','',NaN);
    r.vertices = V; r.lenCm = pivcore.io.grain4Desc.lenCmOf(V,0.01);
    r.angleDeg = pivcore.io.grain4Desc.angleDegOf(V);
end
function local_close(fig), try, if ishghandle(fig), delete(fig); end, catch, end, end
