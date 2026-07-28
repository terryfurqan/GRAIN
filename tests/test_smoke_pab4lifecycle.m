function test_smoke_pab4lifecycle()
%TEST_SMOKE_PAB4LIFECYCLE  Smoke test engine pivcore.io.pab4Lifecycle (murni/
%   headless). Blok:
%     A  strainAtFrameLinear (frame 1 -> 0%, frame nF -> total; linear)
%     B  lifecyclePhases lengkap: fase kanonik terurut + stempel strain%/durasi
%        + rates growth/die-out ditempel ke fase yg benar
%     C  robust POI hilang: fsx=NaN -> tak ada 'inactive', active-slip sampai nF;
%        nucFsr=NaN -> tak ada 'pre-fault'/'nucleation'; 1 FS-max -> fsMaxLast=first
%
%   SENYAP; tanpa GUI. SELALU MATLAB R2025b.

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(fileparts(here)));
    addpath(fullfile(fileparts(here), 'pivcore_lib'));
    try, pab_setup; catch, end

    fprintf('== test_smoke_pab4lifecycle ==\n');

    % ================= BLOK A: strainAtFrameLinear =================
    saf = @pivcore.io.pab4Lifecycle.strainAtFrameLinear;
    assert(abs(saf(1, 100, -40) - 0) < 1e-12,  'A1 frame1 -> 0%%');
    assert(abs(saf(100, 100, -40) + 40) < 1e-12, 'A2 frameN -> total');
    % frame 50, nF=100, total -40 -> (49/99)*-40
    assert(abs(saf(50, 100, -40) - (49/99*-40)) < 1e-9, 'A3 linear tengah');
    assert(isnan(saf(NaN, 100, -40)), 'A4 frame NaN -> NaN');
    assert(isnan(saf(50, 100, NaN)), 'A5 total NaN -> NaN');
    assert(abs(saf(3, 1, -40) + 40) < 1e-12, 'A6 nF<=1 -> total');

    % ================= BLOK B: lifecyclePhases lengkap =================
    % POI: nucFsr=20, fsMaxFirst=50, fsMaxLast=70, fsx=95; nF=100; total -40%;
    % dt=2 s; rates growth=0.3, die-out=0.1.
    poi = pivcore.io.pab4Lifecycle.poiStruct(20, 50, 70, 95);
    rates = struct('growth', 0.3, 'dieOut', 0.1);
    ph = pivcore.io.pab4Lifecycle.lifecyclePhases(poi, 100, -40, 2, rates);
    assert(iscell(ph), 'B0 return cell');
    names = cellfun(@(p) p.phase, ph, 'uni', 0);
    expNames = {'pre-fault','nucleation','FSR-formation','active-slip','waning','inactive'};
    assert(isequal(names, expNames), 'B1 urutan fase: %s', strjoin(names, ','));

    P = @(nm) ph{find(strcmp(names, nm), 1)};
    prf = P('pre-fault');     assert(prf.frameStart==1  && prf.frameEnd==20, 'B2 pre-fault 1..20');
    nuc = P('nucleation');    assert(nuc.frameStart==20 && nuc.frameEnd==50, 'B3 nucleation 20..50');
    fsr = P('FSR-formation'); assert(fsr.frameStart==50 && fsr.frameEnd==70, 'B4 FSR-formation 50..70');
    act = P('active-slip');   assert(act.frameStart==70 && act.frameEnd==95, 'B5 active-slip 70..95');
    wan = P('waning');        assert(wan.frameStart==70 && wan.frameEnd==95, 'B6 waning 70..95');
    ina = P('inactive');      assert(ina.frameStart==95 && ina.frameEnd==100,'B7 inactive 95..100');

    % strain stamp: nucleation start = saf(20) , end = saf(50)
    assert(abs(nuc.strainStartPct - saf(20,100,-40)) < 1e-9, 'B8 strainStart nuc');
    assert(abs(nuc.strainEndPct   - saf(50,100,-40)) < 1e-9, 'B9 strainEnd nuc');
    % durationSec = (end-start)*dt ; nucleation (50-20)*2 = 60
    assert(abs(nuc.durationSec - 60) < 1e-9, 'B10 durationSec nuc=60');
    assert(abs(prf.durationSec - (20-1)*2) < 1e-9, 'B11 durationSec pre-fault');
    % rates ditempel: growth -> nucleation, die-out -> waning
    assert(isfield(nuc,'rate') && abs(nuc.rate-0.3)<1e-12 && strcmp(nuc.rateType,'growth'), 'B12 growth di nucleation');
    assert(isfield(wan,'rate') && abs(wan.rate-0.1)<1e-12 && strcmp(wan.rateType,'die-out'), 'B13 die-out di waning');
    % fase tanpa rate -> tak ada field rate
    assert(~isfield(fsr,'rate'), 'B14 FSR-formation tanpa rate');

    % durationSec null bila dtSec absen
    ph2 = pivcore.io.pab4Lifecycle.lifecyclePhases(poi, 100, -40, NaN, rates);
    assert(isnan(ph2{2}.durationSec), 'B15 dtSec NaN -> durationSec NaN');

    % ================= BLOK C: robust POI hilang =================
    % fsx=NaN -> tak ada 'inactive'; active-slip sampai nF(=100); waning skip (fsx NaN).
    poiNoFsx = pivcore.io.pab4Lifecycle.poiStruct(20, 50, 70, NaN);
    phC = pivcore.io.pab4Lifecycle.lifecyclePhases(poiNoFsx, 100, -40, 2, rates);
    nmC = cellfun(@(p) p.phase, phC, 'uni', 0);
    assert(~any(strcmp(nmC,'inactive')), 'C1 tanpa fsx -> tak ada inactive');
    assert(~any(strcmp(nmC,'waning')),   'C2 tanpa fsx -> tak ada waning');
    actC = phC{find(strcmp(nmC,'active-slip'),1)};
    assert(actC.frameStart==70 && actC.frameEnd==100, 'C3 active-slip 70..nF');

    % nucFsr=NaN -> tak ada pre-fault & nucleation
    poiNoNuc = pivcore.io.pab4Lifecycle.poiStruct(NaN, 50, 70, 95);
    phN = pivcore.io.pab4Lifecycle.lifecyclePhases(poiNoNuc, 100, -40, 2, rates);
    nmN = cellfun(@(p) p.phase, phN, 'uni', 0);
    assert(~any(strcmp(nmN,'pre-fault')),  'C4 tanpa nucFsr -> tak ada pre-fault');
    assert(~any(strcmp(nmN,'nucleation')), 'C5 tanpa nucFsr -> tak ada nucleation');
    assert(any(strcmp(nmN,'FSR-formation')), 'C6 FSR-formation tetap ada');

    % hanya 1 FS-max (fsMaxLast NaN) -> fsMaxLast = fsMaxFirst -> FSR-formation 50..50 (durasi 0)
    poi1fs = pivcore.io.pab4Lifecycle.poiStruct(20, 50, NaN, 95);
    ph1 = pivcore.io.pab4Lifecycle.lifecyclePhases(poi1fs, 100, -40, 2, rates);
    nm1 = cellfun(@(p) p.phase, ph1, 'uni', 0);
    fsr1 = ph1{find(strcmp(nm1,'FSR-formation'),1)};
    assert(fsr1.frameStart==50 && fsr1.frameEnd==50, 'C7 1 FS-max -> FSR-formation 50..50');
    act1 = ph1{find(strcmp(nm1,'active-slip'),1)};
    assert(act1.frameStart==50 && act1.frameEnd==95, 'C8 active-slip dari fsMaxFirst');

    % POI kosong sepenuhnya -> hanya pre-fault(1..nF)? nucFsr NaN -> pre-fault skip;
    % semua boundary NaN kecuali endActive=nF -> active-slip butuh fsMaxLast (NaN) -> skip.
    phEmpty = pivcore.io.pab4Lifecycle.lifecyclePhases( ...
        pivcore.io.pab4Lifecycle.poiStruct(), 100, -40, 2, rates);
    assert(iscell(phEmpty), 'C9 POI kosong -> cell (boleh kosong)');

    % jsonencode tak error (cell of struct -> array)
    txt = jsonencode(ph); %#ok<NASGU>
    assert(ischar(txt) || isstring(txt), 'C10 jsonencode phases OK');

    fprintf('OK test_smoke_pab4lifecycle (A strain, B fase lengkap, C robust POI hilang)\n');
end
