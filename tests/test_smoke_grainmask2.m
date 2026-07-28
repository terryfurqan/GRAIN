function test_smoke_grainmask2()
%TEST_SMOKE_GRAINMASK2  Fase C GUI: GRAINMASK2 headless — scan JPG lolos QPIV, set
%   keyframe polygon, simpan ke progres terpadu (setpoly), muat ulang.
%
%   Jalankan: grain_setup; test_smoke_grainmask2   (SELALU R2025b)
    fprintf('\n=== TEST GRAINMASK2 GUI (Fase C) ===\n');
    grain_setup();
    assert(~isempty(which('GRAINMASK2')), 'GRAINMASK2 tak di-path');

    troot = fullfile(tempdir, sprintf('pabmask2_%d', feature('getpid')));
    if isfolder(troot), rmdir(troot,'s'); end; mkdir(troot);
    cleaner = onCleanup(@() i_rmdir(troot)); %#ok<NASGU>

    expA = fullfile(troot,'exp_A'); mkdir(expA);
    nImg = 10; base = i_texture(200,260);
    for k=1:nImg; imwrite(base, fullfile(expA, sprintf('f_%d.jpg',k))); end

    pf = fullfile(troot,'PAB0_progress.mat');
    PIVlab_automasi_progress('setfile', pf);
    restoreProg = onCleanup(@() PIVlab_automasi_progress('resetfile')); %#ok<NASGU>
    keptNames = arrayfun(@(k) sprintf('f_%d.jpg',k), 1:nImg, 'uni',0);
    eA = PIVlab_automasi_progress('empty');
    eA.expdir=expA; eA.key=PIVlab_automasi_progress('key',expA);
    eA.sequencing='consecutive'; eA.skip=0; eA.qpiv_done=true;
    eA.qpiv_nframes=nImg-1; eA.qpiv_kept_names=keptNames;
    PIVlab_automasi_progress('set', eA);

    set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible','on')); %#ok<NASGU>
    GRAINMASK2(troot);
    f = findall(0,'Type','figure','-regexp','Name','^GRAIN Masking 2');
    if numel(f)>1, f=f(1); end
    assert(~isempty(f), 'figure GRAINMASK2 tak terbentuk');
    closeFig = onCleanup(@() i_closeFig(f)); %#ok<NASGU>
    h = guidata(f);

    iA = find(strcmp({h.list.name},'exp_A'),1);
    assert(~isempty(iA), 'exp_A tak terpindai');
    assert(h.list(iA).nFrames==nImg, 'nFrames salah (lolos QPIV = 10)');

    % Simulasi: pilih exp -> set keyframe di frame akhir & frame awal (via engine
    % langsung, meniru i_onSetKeyframe tanpa drawpolygon interaktif).
    h.activeRow = iA;
    sq = @(cx,cy,r)[cx-r cy-r; cx+r cy-r; cx+r cy+r; cx-r cy+r];
    pg = [];
    pg = i_upsertKf(pg, 10, sq(200,100,30));   % frame akhir
    pg = i_upsertKf(pg, 1,  sq(120,100,30));   % frame awal
    h.list(iA).polygon = pg; h.list(iA).dirty = true;
    guidata(f,h);

    % Simpan -> progres terpadu
    poly = struct('enabled',true,'fill',255,'polygons',pg);
    PIVlab_automasi_progress('setpoly', expA, poly);
    got = PIVlab_automasi_progress('getpoly', expA);
    assert(~isempty(got), 'getpoly kosong setelah setpoly');
    gp = pivanalyzemat.core.maskPoly.normalize(got);
    assert(gp.enabled && numel(gp.polygons)==1, 'poly progres tak valid');
    assert(numel(gp.polygons(1).keyframes)==2, 'keyframe tak 2');
    % interpolasi frame tengah (5): cx antara 120 dan 200
    V5 = pivanalyzemat.core.maskPoly.interpVerts(gp.polygons(1), 5, 10);
    cx = mean(V5(:,1));
    assert(cx > 120 && cx < 200, sprintf('interp tengah cx=%.1f di luar rentang', cx));
    fprintf('  scan lolos-QPIV=10, 2 keyframe, interp tengah cx=%.1f OK.\n', cx);
    fprintf('=== LULUS ===\n');
end

function pg = i_upsertKf(pg, fr, V)
    kf1 = struct('frame_index',fr,'vertices',double(V));
    if isempty(pg); pg = struct('enabled',true,'fill',[],'keyframes',kf1); return; end
    kf = pg.keyframes; kf(end+1) = kf1;
    [~,o] = sort([kf.frame_index]); pg.keyframes = kf(o);
end
function img = i_texture(H,W)
    [xx,yy]=meshgrid(1:W,1:H); img=uint8(128+60*sin(xx/7).*cos(yy/9));
end
function i_closeFig(f); try, if all(ishghandle(f)), delete(f); end, catch, end; end
function i_rmdir(d); try, if isfolder(d), rmdir(d,'s'); end, catch, end; end
