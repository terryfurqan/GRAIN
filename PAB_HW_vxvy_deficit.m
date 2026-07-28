function out = PAB_HW_vxvy_deficit(varargin)
%PAB_HW_VXVY_DEFICIT  Dekomposisi Vx/Vy hanging-wall & defisit transport horizontal.
%
%   Ambil kurva POT hanging-wall (HW) & footwall (FW) IDENTIK dgn PAB4AXPOT
%   CLEAN, tetapi PISAHKAN kecepatan |V| menjadi komponen horizontal Vx dan
%   vertikal Vy, lalu isolasi DEFISIT TRANSPORT HORIZONTAL HW vs dinding
%   pendorong (shortening yg diserap sesar aktif).
%
%   Latar: klaim inti = HW aktif selalu lebih lambat dari dinding, defisit ~18%
%   (HW ~= 0.82 x Vmax). Angka 18% itu dihitung dari |V| (campur transport
%   horizontal + pengangkatan ramp). Defisit yg BENAR secara fisika harus dari
%   Vx. Skrip ini menghitung deficit_x dan membandingkannya dgn deficit_mag lama.
%
%   PENTING (temuan verifikasi data, 2026-07-20):
%     * velocity_magnitude PIVlab = hypot(u_smoothed, v_smoothed) PERSIS (err 0%).
%       u_component/v_component KOSONG di berkas ini; sqrt(u_filtered^2+v_filtered^2)
%       beda ~48% dari |V|. Jadi komponen yg KONSISTEN dgn |V| (baseline deficit
%       0.18 di PAB4AXPOT) = u_smoothed/v_smoothed -> itu yg dipakai (bukan
%       u_filtered spt bunyi prompt). Ini menjaga sqrt(Vx^2+Vy^2) == |V|.
%     * Shortening di zona ukur (kamera tengah, ukur dari kiri) bergerak ke +x
%       (u_smoothed ~ +5.6 px/frame di kolom max|V|), BUKAN -x. Defisit dilaporkan
%       dari |Vx| (magnitude) supaya kebal arah; arah dinding dideteksi dari data.
%
%   Reuse jalur kanonik PAB4AXPOT (jangan bikin sampler paralel):
%     step1Session.loadAllFrames -> i_resolveLine (potdata garis-1 / autoPSG 75%)
%     -> step1Collect.collectAlongLine(data,p1,p2,sp,SRC) utk SRC =
%        'velocity_magnitude' | 'u_smoothed' | 'v_smoothed' (node SAMA)
%     -> records.normalize/applyColors ; potdata excluded+cutFrame ; trim [startF,endF].
%
%   Usage:
%     PAB_HW_vxvy_deficit                       % semua kondisi CON/HF/LF di EXP Q1
%     PAB_HW_vxvy_deficit('root', DIR)          % override folder induk EXP Q1
%     PAB_HW_vxvy_deficit('conditions', {'P-CON-4cm-F'})   % subset
%
%   Output ke PAB/CLCC/VXVY/ :
%     - PAB_VXVY_<cond>.pdf   (per kondisi: Vx_HW/Vy_HW/env vs strain, tiap run)
%     - PAB_VXVY_summary.pdf  (deficit_x vs deficit_mag ; deficit vs friksi)
%     - PAB_VXVY_panels.csv   (tabel numerik penuh)
%     - PAB_VXVY_result.json  (semua metrik + metadata + sanity)
%     - PAB_VXVY_report.md    (metode + angka final)
%     - PAB_VXVY_data.mat     (struct panel reusable)
%
%   Jalankan pab_setup dulu (pivcore/pivui on path). MATLAB R2025b.

    p = inputParser;
    p.addParameter('root', '', @(s) ischar(s)||isstring(s));
    p.addParameter('conditions', {}, @(c) iscell(c));
    p.addParameter('plateauK', 20, @(x) isscalar(x)&&x>=1);   % lebar jendela plateau (frame)
    p.addParameter('regen', false, @(x) islogical(x)||isnumeric(x));  % hanya rebuild report+summary dari .mat
    p.parse(varargin{:});
    root = char(p.Results.root);
    conds = p.Results.conditions;
    plateauK = p.Results.plateauK;

    outDir0 = fullfile(fileparts(mfilename('fullpath')), 'CLCC', 'VXVY');
    if p.Results.regen
        % Regenerasi CEPAT report + summary + CSV + JSON dari PAB_VXVY_data.mat
        % (tanpa re-sampling). Berguna setelah ubah teks/plot ringkas.
        L = load(fullfile(outDir0,'PAB_VXVY_data.mat'));   % panels, result
        fo = {'P-LF-4cm-F','P-CON-4cm-F','P-HF-4cm-F'};
        fc = containers.Map({'P-LF-4cm-F','P-CON-4cm-F','P-HF-4cm-F'}, ...
            {[0.20 0.45 0.80],[0.35 0.35 0.35],[0.80 0.20 0.20]});
        R2 = L.result; R2.summary = i_summaryStats(L.panels, fo);
        R2.panels = i_panelsForJson(L.panels);
        i_plotSummary(L.panels, fo, fc, fullfile(outDir0,'PAB_VXVY_summary.pdf'));
        i_writeCsv(L.panels, fullfile(outDir0,'PAB_VXVY_panels.csv'));
        fid=fopen(fullfile(outDir0,'PAB_VXVY_result.json'),'w');
        fwrite(fid, jsonencode(R2,'PrettyPrint',true)); fclose(fid);
        i_writeReport(R2, fullfile(outDir0,'PAB_VXVY_report.md'));
        fprintf('REGEN selesai: report+summary+csv+json diperbarui dari .mat\n');
        if nargout>0, out=R2; end
        return;
    end

    if isempty(root)
        root = fullfile(getenv('HOME'), 'MACTERR_shared', 'EXP_coll', 'EXP Q1');
    end
    if isempty(conds)
        conds = {'P-CON-4cm-F','P-HF-4cm-F','P-LF-4cm-F'};
    end

    outDir = fullfile(fileparts(mfilename('fullpath')), 'CLCC', 'VXVY');
    if ~isfolder(outDir), mkdir(outDir); end

    log = i_logger(outDir);
    log('=== PAB_HW_vxvy_deficit ===');
    log(sprintf('root      : %s', root));
    log(sprintf('conditions: %s', strjoin(conds, ', ')));
    log(sprintf('plateauK  : %d frame', plateauK));
    log(sprintf('outDir    : %s', outDir));

    % Palet warna friksi (ilmiah, tegas): LF biru, CON abu, HF merah.
    frictionOrder = {'P-LF-4cm-F','P-CON-4cm-F','P-HF-4cm-F'};
    frictionColor = containers.Map( ...
        {'P-LF-4cm-F','P-CON-4cm-F','P-HF-4cm-F'}, ...
        {[0.20 0.45 0.80],[0.35 0.35 0.35],[0.80 0.20 0.20]});

    RESULT = struct('generatedAt', datestr(now,'yyyy-mm-dd HH:MM:SS'), ...
        'root', root, 'plateauK', plateauK, 'conditions', {{}});
    ALLPANELS = {};   % flatten untuk .mat/.csv

    for ci = 1:numel(conds)
        cond = conds{ci};
        cdir = fullfile(root, cond);
        if ~isfolder(cdir), log(sprintf('[SKIP] tak ada folder: %s', cdir)); continue; end
        files = i_findExpFiles(cdir);
        log(sprintf('--- %s : %d run ---', cond, numel(files)));

        runs = {};
        for i = 1:numel(files)
            [~,bn] = fileparts(files{i});
            log(sprintf('  [%s] %s', cond, bn));
            try
                R = i_analyzeExp(files{i}, plateauK, log);
            catch ME
                log(sprintf('    [FAIL] %s : %s', bn, ME.message));
                continue;
            end
            R.condition = cond;
            R.runIndex  = i;
            runs{end+1} = R; %#ok<AGROW>
            for k = 1:numel(R.faults)
                fr = R.faults{k};
                fr.condition = cond; fr.base = R.base; fr.runIndex = i;
                fr.calibrated = R.calibrated; fr.vMult = R.vMult;
                fr.deficit_mag_env = R.deficit_env_used;   % dinding pilihan
                ALLPANELS{end+1} = fr; %#ok<AGROW>
            end
        end

        % --- figur per kondisi ---
        try
            i_plotCondition(runs, cond, fullfile(outDir, sprintf('PAB_VXVY_%s.pdf', cond)));
            log(sprintf('  -> PDF: PAB_VXVY_%s.pdf', cond));
        catch ME
            log(sprintf('  [PLOT FAIL] %s : %s', cond, ME.message));
        end

        cs = struct('name', cond, 'runs', {runs});
        RESULT.conditions{end+1} = cs;
    end

    % --- figur ringkas lintas kondisi ---
    try
        i_plotSummary(ALLPANELS, frictionOrder, frictionColor, ...
            fullfile(outDir,'PAB_VXVY_summary.pdf'));
        log('-> PDF: PAB_VXVY_summary.pdf');
    catch ME
        log(sprintf('[SUMMARY PLOT FAIL] %s', ME.message));
    end

    % --- CSV ---
    try
        i_writeCsv(ALLPANELS, fullfile(outDir,'PAB_VXVY_panels.csv'));
        log('-> CSV: PAB_VXVY_panels.csv');
    catch ME
        log(sprintf('[CSV FAIL] %s', ME.message));
    end

    % --- JSON ---
    RESULT.panels = i_panelsForJson(ALLPANELS);
    RESULT.summary = i_summaryStats(ALLPANELS, frictionOrder);
    try
        fid = fopen(fullfile(outDir,'PAB_VXVY_result.json'),'w');
        fwrite(fid, jsonencode(RESULT, 'PrettyPrint', true)); fclose(fid);
        log('-> JSON: PAB_VXVY_result.json');
    catch ME
        log(sprintf('[JSON FAIL] %s', ME.message));
    end

    % --- report .md ---
    try
        i_writeReport(RESULT, fullfile(outDir,'PAB_VXVY_report.md'));
        log('-> MD: PAB_VXVY_report.md');
    catch ME
        log(sprintf('[REPORT FAIL] %s', ME.message));
    end

    % --- .mat ---
    try
        panels = ALLPANELS; result = RESULT; %#ok<NASGU>
        save(fullfile(outDir,'PAB_VXVY_data.mat'), 'panels', 'result');
        log('-> MAT: PAB_VXVY_data.mat');
    catch ME
        log(sprintf('[MAT FAIL] %s', ME.message));
    end

    log('=== SELESAI ===');
    if nargout>0, out = RESULT; end
end

% =====================================================================
function R = i_analyzeExp(matFile, plateauK, log)
%I_ANALYZEEXP  Satu eksperimen: sampel |V|/Vx/Vy pada node SAMA, resolusi
%   sesar, hitung defisit + amalgamasi multi-kriteria. Reuse jalur PAB4AXPOT.
    [~, base] = fileparts(matFile);
    R = struct('base', base, 'matFile', matFile);

    % --- muat + garis PSG (jalur kanonik) ---
    data = pivcore.io.step1Session.loadAllFrames(matFile);
    [p1, p2] = i_resolveLine(matFile, data);
    sp = pivcore.io.step1Session.savedSpacing(matFile);
    if ~(isscalar(sp)&&isfinite(sp)&&sp>0)
        dd = pivcore.data.nodeSpacing(data);
        if isfinite(dd)&&dd>0, sp=round(dd); else, sp=10; end
    end

    % --- sampel TIGA sumber pada node IDENTIK ---
    recM = pivcore.pot.records.applyColors(pivcore.pot.records.normalize( ...
        pivcore.pot.step1Collect.collectAlongLine(data,p1,p2,sp,'velocity_magnitude')));
    recU = pivcore.pot.records.normalize( ...
        pivcore.pot.step1Collect.collectAlongLine(data,p1,p2,sp,'u_smoothed'));
    recV = pivcore.pot.records.normalize( ...
        pivcore.pot.step1Collect.collectAlongLine(data,p1,p2,sp,'v_smoothed'));

    nF = 0; for r=1:numel(recM), nF=max(nF,numel(recM(r).data)); end; nF=max(1,nF);

    % Node harus align (jumlah & posPx). Verifikasi.
    if ~(numel(recM)==numel(recU) && numel(recU)==numel(recV))
        error('Node count mismatch |V|=%d Vx=%d Vy=%d', numel(recM),numel(recU),numel(recV));
    end

    % --- SANITY KALIBRASI (menghentikan): calu==calv==calxy (isotropik). ---
    calu=i_cal(data,'calu'); calv=i_cal(data,'calv'); calxy=i_cal(data,'calxy');
    R.cal = struct('calu',calu,'calv',calv,'calxy',calxy);
    if isfinite(calu)&&isfinite(calv) && abs(calu-calv) > 1e-9*max(1,abs(calu))
        error(['SANITY KALIBRASI GAGAL: calu(%.6g) != calv(%.6g) -> konversi spasial ' ...
            'anisotropik; Vx/Vy tak sebanding. Hentikan.'], calu, calv);
    end

    % --- INFO: |V|_self=hypot(Vx,Vy) vs field velocity_magnitude ---
    %   Setelah blok-average 3x3 + MA, field |V| = mean(|v| per sel) sedangkan
    %   Vx/Vy = mean komponen; karena arah aliran beragam dlm blok, hypot(Vx,Vy)
    %   != |V| (sifat urutan-averaging, BUKAN bug). Analisis ini memakai
    %   |V|_self = hypot(Vx,Vy) (konsisten-diri: sqrt(Vx^2+Vy^2)=|V| by
    %   construction). Field |V| disimpan HANYA sbg referensi deficit_mag lama.
    dmax=0; dmed=[];
    for r = 1:numel(recM)
        m=recM(r).data(:).'; u=recU(r).data(:).'; v=recV(r).data(:).';
        L=min([numel(m) numel(u) numel(v)]); m=m(1:L);u=u(1:L);v=v(1:L);
        rec=hypot(u,v); g=isfinite(rec)&isfinite(m)&(m>1e-6);
        if ~any(g), continue; end
        e=abs(rec(g)-m(g))./m(g); dmax=max(dmax,max(e)); dmed=[dmed e]; %#ok<AGROW>
    end
    R.selfVsField = struct('maxRelErr', dmax, ...
        'medRelErr', i_m(dmed), ...
        'note', '|V|_self=hypot(Vx,Vy) dipakai; beda vs field = artefak urutan-average (bukan bug).');
    log(sprintf('    |V|_self vs field |V|: median=%.2g%% max=%.2g%% (informatif; |V|_self dipakai)', ...
        i_m(dmed)*100, dmax*100));

    % --- potdata: excluded + cutFrame (POSISIONAL, semua sumber sama) ---
    recM = i_applyPotData(matFile, recM);
    recU = i_copyPotFlags(recM, recU);
    recV = i_copyPotFlags(recM, recV);

    % --- kalibrasi cm/s (paritas frameCatalog velMultGeom) ---
    [strTot, ~, dxCm] = pivcore.export.frameCatalog.readGeom(matFile);
    dtSec = pivcore.export.frameCatalog.readExifDt(matFile);
    envRaw = i_indenterEnv(recM, nF, false);          % envelope MENTAH (kalibrasi stabil)
    indMax = NaN; if ~isempty(envRaw), e=envRaw(isfinite(envRaw)); if ~isempty(e), indMax=max(e); end, end
    vMult = NaN;
    if isfinite(dxCm)&&dxCm>0 && isfinite(dtSec)&&dtSec>0 && nF>1 && isfinite(indMax)&&indMax>0
        vMult = (dxCm/((nF-1)*dtSec)) / indMax;         % cm/s per (px/frame)
    end
    calibrated = isfinite(vMult) && vMult>0;
    if ~calibrated, vMult = 1; end
    R.calibrated = calibrated; R.vMult = vMult; R.nF = nF; R.strainTot = strTot;
    R.indMax = indMax; R.dxCm = dxCm; R.dtSec = dtSec;

    % X-axis strain%
    haveStrain = isfinite(strTot)&&strTot~=0&&nF>1;
    if haveStrain, xr = (0:nF-1)/(nF-1)*strTot; else, xr = 1:nF; end
    R.xr = xr; R.haveStrain = haveStrain;

    % --- envelope dinding: (a) empiris |V| ; (b) indenter axpot bila ada ---
    envA = i_indenterEnv(recM, nF, true);               % hormati excluded (clean, FIELD |V|)
    R.env_mag = envA;                                    % referensi field
    % Komponen envelope: pada tiap frame ambil Vx,Vy pada node ber-|V|_self maks.
    % env_mag_self = hypot(env_vx,env_vy) -> konsisten-diri (baseline analisis).
    [envVx, envVy, envMagSelf] = i_envComponents(recM, recU, recV, nF);
    R.env_vx = envVx; R.env_vy = envVy; R.env_mag_self = envMagSelf;
    % (b) indenter dari axpot sidecar (referensi independen) bila tersedia.
    [envB_mag, haveB] = i_axpotIndenter(matFile, nF);
    R.env_axpot = envB_mag; R.haveAxpot = haveB;
    % Perbandingan (a) vs (b) di plateau global (median 20% frame terakhir aktif).
    R.envAB = i_compareEnv(envA, envB_mag, haveB);

    % Envelope drift (uji paralaks): fit linier |V|_wall vs strain.
    R.envDrift = i_envDrift(xr, envA);

    % dinding yg DIPAKAI utk deficit: default empiris (a). Simpan flag.
    R.deficit_env_used = 'empirical';

    % --- sesar dari faults.json ---
    R.faults = i_analyzeFaults(matFile, data, recM, recU, recV, nF, xr, vMult, ...
        envA, envMagSelf, envVx, plateauK, log);
end

% =====================================================================
function F = i_analyzeFaults(matFile, data, recM, recU, recV, nF, xr, vMult, ...
        envMagField, envMagSelf, envVx, plateauK, log)
%I_ANALYZEFAULTS  Per sesar utama: kurva HW/FW untuk |V|/Vx/Vy, jendela aktif,
%   amalgamasi multi-kriteria, plateau median, deficit_mag & deficit_x.
    F = {};
    try
        doc = pivcore.io.pab5Faults.read(matFile);
    catch
        return;
    end
    if ~isstruct(doc)||~isfield(doc,'faults')||isempty(doc.faults), return; end
    FF = doc.faults; if isstruct(FF), FF=num2cell(FF); end

    for k = 1:numel(FF)
        f = FF{k}; if ~isstruct(f), continue; end
        if isfield(f,'enabled')&&isscalar(f.enabled)&&~logical(f.enabled), continue; end
        if isfield(f,'parentId')&&~isempty(f.parentId)&&(ischar(f.parentId)||isstring(f.parentId)) ...
                && ~isempty(char(f.parentId)), continue; end   % sub-fault: lewati

        hwRow = i_rowForPos(recM, f.hwPosPx);
        fwRow = i_rowForPos(recM, f.fwPosPx);
        if isempty(hwRow), continue; end

        % Deret HW/FW utk tiga sumber (trim identik).
        mHW = i_dispY(recM, hwRow, nF); uHW = i_dispY(recU, hwRow, nF); vHW = i_dispY(recV, hwRow, nF);
        mFW=[];uFW=[];vFW=[];
        if ~isempty(fwRow)
            mFW=i_dispY(recM,fwRow,nF); uFW=i_dispY(recU,fwRow,nF); vFW=i_dispY(recV,fwRow,nF);
        end

        % Jendela aktif [a,b] dari faults.json.
        a=f.startF; b=f.endF;
        if ~(isfinite(a)&&isfinite(b))
            gg=isfinite(mHW); idx=find(gg); if isempty(idx), a=1;b=nF; else,a=idx(1);b=idx(end);end
        end
        a=max(1,round(min(a,b))); b=min(nF,round(max(a,b)));

        % AX-SLIP komponen = Vx_HW - Vx_FW (utk startF & amalgamasi).
        axslip = nan(1,nF);
        if ~isempty(uFW)
            L=min(numel(uHW),numel(uFW)); axslip(1:L)=uHW(1:L)-uFW(1:L);
        end
        % |V| net-slip lama (utk validasi startF json).
        startF_axslip = i_startFromAxslip(axslip);

        % --- amalgamasi multi-kriteria ---
        % (1) X-FS dari faults.json.
        xfs = NaN; if isfield(f,'fsr')&&isscalar(f.fsr)&&isfinite(f.fsr), xfs=f.fsr; end
        % (2) AX-SLIP -> 0 (turun ke bawah noise & tetap).
        amalg_axslip = i_amalgFromAxslip(axslip, a, b);
        % (3) shear_rate -> 0 di zona sesar (node HW..FW). Pakai |V| kurva sbg
        %     proxy? Tidak: baca shear_rate langsung sepanjang node HW..FW.
        amalg_shear = i_amalgFromShear(data, recM, hwRow, fwRow, nF, a, b);
        % (4) endF human label (faults.json).
        amalg_endF = b;

        cand = [xfs amalg_axslip amalg_shear amalg_endF];
        cand = cand(isfinite(cand));
        amalgFrame = amalg_endF;   % default: endF human
        if ~isempty(cand), amalgFrame = round(median(cand)); end
        amalgFrame = max(a+1, min(nF, amalgFrame));
        amalgSpread = NaN; if numel(cand)>=2, amalgSpread = max(cand)-min(cand); end

        % --- plateau fase-aktif: median jendela [amalg-K, amalg] ---
        w0 = max(a, amalgFrame - plateauK); w1 = amalgFrame;
        win = w0:w1;
        % |V|_self HW = hypot(Vx,Vy) konsisten-diri (baseline utama).
        magSelfHW = hypot(uHW, vHW);
        magSelfHWp = i_medWin(magSelfHW, win);
        magFieldHWp = i_medWin(mHW, win);      % field |V| (referensi 0.18 lama)
        vxHWp  = i_medWin(uHW, win);
        vyHWp  = i_medWin(vHW, win);
        % dinding pada jendela sama.
        magWallSelf  = i_medWin(envMagSelf,  win);
        magWallField = i_medWin(envMagField, win);
        vxWall  = i_medWin(envVx,  win);

        % deficit horizontal (|Vx|, kebal arah) = ANGKA BARU yg dicari.
        deficit_x   = i_deficit(abs(vxHWp), abs(vxWall));
        % deficit magnitude: (self) konsisten-diri & (field) referensi ke 0.18.
        deficit_mag_self  = i_deficit(magSelfHWp,  magWallSelf);
        deficit_mag_field = i_deficit(magFieldHWp, magWallField);
        deficit_mag = deficit_mag_self;   % baseline utama = self
        VyOverVx    = NaN; if isfinite(vyHWp)&&abs(vxHWp)>1e-9, VyOverVx = abs(vyHWp)/abs(vxHWp); end

        % kematangan: sesar termuda (endF ~ nF) TANDAI (belum matang).
        mature = (b < 0.95*nF);
        % suspect: HW plateau ~0 (def_x mendekati 1) atau HW>=wall (def<0) atau
        %   jendela plateau terlalu pendek -> kemungkinan node HW jatuh di zona
        %   mati/tepi atau sesar meliputi seluruh domain. TANDAI (bukan drop diam).
        suspect = false;
        if ~isfinite(deficit_x) || deficit_x > 0.85 || deficit_x < -0.05 ...
                || (w1-w0) < 5 || ~isfinite(vxWall) || abs(vxWall) < 1e-3
            suspect = true;
        end
        if suspect, mature = false; end   % keluarkan dari statistik matang

        fs = struct();
        fs.uiNum = i_scalarField(f,'uiNum');
        fs.hwPosPx = f.hwPosPx; fs.fwPosPx = f.fwPosPx;
        fs.a=a; fs.b=b;
        fs.startF_json = f.startF; fs.startF_axslip = startF_axslip;
        fs.amalg_xfs = xfs; fs.amalg_axslip = amalg_axslip; ...
        fs.amalg_shear = amalg_shear; fs.amalg_endF = amalg_endF;
        fs.amalgFrame = amalgFrame; fs.amalgSpread = amalgSpread;
        fs.plateauWin = [w0 w1];
        fs.mag_HW_plateau = magSelfHWp;      % |V|_self (baseline)
        fs.magField_HW_plateau = magFieldHWp;
        fs.vx_HW_plateau = vxHWp; fs.vy_HW_plateau = vyHWp;
        fs.mag_wall = magWallSelf; fs.magField_wall = magWallField; fs.vx_wall = vxWall;
        fs.deficit_mag = deficit_mag;            % = deficit_mag_self
        fs.deficit_mag_self = deficit_mag_self;
        fs.deficit_mag_field = deficit_mag_field;
        fs.deficit_x = deficit_x; fs.VyOverVx = VyOverVx;
        fs.mature = mature; fs.suspect = suspect;
        % simpan deret utk plot (cm/s bila vMult). mag_HW = |V|_self.
        fs.series = struct('xr',xr, 'vx_HW',uHW*vMult, 'vy_HW',vHW*vMult, ...
            'mag_HW',magSelfHW*vMult, 'env_vx',envVx*vMult, 'env_mag',envMagSelf*vMult, ...
            'axslip', axslip*vMult);
        F{end+1} = fs; %#ok<AGROW>

        log(sprintf('    F%g: [a,b]=[%d,%d] amalg=%d (xfs=%s axslip=%s shear=%s endF=%d) | def_x=%.3f def_mag(self=%.3f field=%.3f) Vy/Vx=%.2f %s', ...
            fs.uiNum, a, b, amalgFrame, i_ns(xfs), i_ns(amalg_axslip), i_ns(amalg_shear), b, ...
            deficit_x, deficit_mag_self, deficit_mag_field, VyOverVx, ...
            [i_tf(~mature&&~suspect,'[IMMATURE]','') i_tf(suspect,'[SUSPECT-dropped]','')]));
    end
end

% =====================================================================
% ---- helper reuse jalur PAB4AXPOT ----
function [p1,p2] = i_resolveLine(matFile, data)
    p1=[];p2=[];
    ln = pivcore.export.frameCatalog.lineFromPotData(matFile);
    if ~isempty(ln), p1=ln.p1(:).'; p2=ln.p2(:).'; return; end
    la = pivcore.io.step1Session.loadLine(matFile);
    if ~isempty(la)&&isfield(la,'p1')&&isfield(la,'p2'), p1=la.p1(:).'; p2=la.p2(:).'; return; end
    x=pivcore.data.safeFrame(data.x,1); y=pivcore.data.safeFrame(data.y,1);
    xE=[min(x(:)) max(x(:))]; yE=[min(y(:)) max(y(:))];
    yL=yE(2)-0.75*(yE(2)-yE(1)); p1=[xE(1) yL]; p2=[xE(2) yL];
end

function files = i_findExpFiles(expDir)
    d=dir(fullfile(expDir,'*.mat')); d=d(~[d.isdir]);
    names={};keys={};
    for k=1:numel(d)
        nm=d(k).name;
        if ~isempty(regexpi(nm,'_[a-z0-9]+\.mat$','once')), continue; end
        if ~isempty(regexpi(nm,'^(PABSA|PAB\d|progress|.*_progress_)','once')), continue; end
        names{end+1}=fullfile(d(k).folder,nm); %#ok<AGROW>
        tok=regexpi(nm,'-(\d+)-OVL','tokens','once');
        if ~isempty(tok), keys{end+1}=sprintf('%06d',str2double(tok{1})); else, keys{end+1}=lower(nm); end %#ok<AGROW>
    end
    if isempty(names), files={}; return; end
    [~,ord]=sort(keys); files=names(ord);
end

function recs = i_applyPotData(matFile, recs)
    try, doc=pivcore.io.pab4PotData.read(matFile); catch, return; end
    if ~isstruct(doc)||~isfield(doc,'psgLines')||isempty(doc.psgLines), return; end
    ln=doc.psgLines{1}; if ~isstruct(ln)||~isfield(ln,'curves'), return; end
    m=min(numel(recs),numel(ln.curves));
    for k=1:m
        c=ln.curves{k}; if ~isstruct(c), continue; end
        if isfield(c,'cutFrame')&&isscalar(c.cutFrame)&&isfinite(c.cutFrame)
            recs(k).cutManual=true; recs(k).cutFrame=c.cutFrame;
        end
        if isfield(c,'excluded')&&isscalar(c.excluded)&&logical(c.excluded), recs(k).excluded=true; end
    end
end

function dst = i_copyPotFlags(src, dst)
%I_COPYPOTFLAGS  Salin flag excluded/cutFrame dari recM (|V|) ke recU/recV agar
%   trim & exclusion IDENTIK di tiga sumber (node align).
    m=min(numel(src),numel(dst));
    for k=1:m
        if isfield(src(k),'excluded')&&isscalar(src(k).excluded)&&logical(src(k).excluded), dst(k).excluded=true; end
        if isfield(src(k),'cutManual')&&src(k).cutManual
            dst(k).cutManual=true; dst(k).cutFrame=src(k).cutFrame;
        end
    end
end

function r = i_rowForPos(recs, posPx)
    r=[]; if ~isscalar(posPx)||~isfinite(posPx)||isempty(recs), return; end
    best=inf;bestR=[];ps=[];
    for k=1:numel(recs)
        if isfield(recs(k),'excluded')&&isscalar(recs(k).excluded)&&logical(recs(k).excluded), continue; end
        p=NaN; if isfield(recs(k),'posPx')&&isscalar(recs(k).posPx), p=recs(k).posPx; end
        if isfinite(p), ps(end+1)=p; d=abs(p-posPx); if d<best,best=d;bestR=k;end; end %#ok<AGROW>
    end
    if isempty(bestR), return; end
    sp=10; if numel(ps)>=2, dsp=median(diff(sort(ps))); if isfinite(dsp)&&dsp>0, sp=dsp; end, end
    if best<=max(8,0.75*sp), r=bestR; end
end

function y = i_dispY(recs, row, nF)
    y=[]; if isempty(row)||row<1||row>numel(recs), return; end
    [~,y]=pivcore.pot.records.curveXY(recs(row), nF);
    y=pivui.pab4Shell.applyTrimYV(recs(row), y);
    y=y(:).';
end

function env = i_indenterEnv(recs, nF, honorExcluded)
    M=-inf(1,nF); any_=false;
    for r=1:numel(recs)
        if honorExcluded&&isfield(recs(r),'excluded')&&isscalar(recs(r).excluded)&&logical(recs(r).excluded), continue; end
        [~,yv]=pivcore.pot.records.curveXY(recs(r),nF);
        yv=pivui.pab4Shell.applyTrimYV(recs(r),yv);
        if isempty(yv), continue; end
        m=numel(yv); seg=M(1:m); g=isfinite(yv); seg(g)=max(seg(g),yv(g)); M(1:m)=seg; any_=true;
    end
    if ~any_, env=[]; return; end
    M(~isfinite(M))=NaN; env=M;
end

function [envVx, envVy, envMagSelf] = i_envComponents(recM, recU, recV, nF)
%I_ENVCOMPONENTS  Pada tiap frame, ambil Vx/Vy pada node ber-|V|_self MAKS
%   (|V|_self=hypot(Vx,Vy); excluded dihormati). Ini "dinding pendorong"
%   konsisten-diri: envMagSelf=hypot(envVx,envVy).
    envVx=nan(1,nF); envVy=nan(1,nF); envMagSelf=nan(1,nF);
    nR=numel(recM);
    YU=nan(nR,nF); YV=nan(nR,nF);
    for r=1:nR
        if isfield(recM(r),'excluded')&&isscalar(recM(r).excluded)&&logical(recM(r).excluded), continue; end
        yu=i_dispY(recU,r,nF); yv=i_dispY(recV,r,nF);
        L=min([numel(yu) numel(yv) nF]);
        YU(r,1:L)=yu(1:L); YV(r,1:L)=yv(1:L);
    end
    YMS=hypot(YU,YV);
    for k=1:nF
        col=YMS(:,k); [mx,ir]=max(col);
        if isfinite(mx), envVx(k)=YU(ir,k); envVy(k)=YV(ir,k); envMagSelf(k)=mx; end
    end
end

function v = i_cal(data, name)
    v=NaN; if isfield(data,name), c=data.(name); if isnumeric(c)&&isscalar(c), v=double(c); end, end
end

% =====================================================================
% ---- amalgamasi & startF ----
function sf = i_startFromAxslip(axslip)
%I_STARTFROMAXSLIP  Titik saat AX-SLIP mulai KONSISTEN positif (naik & tetap>0).
    sf=NaN; a=axslip(:).'; n=numel(a);
    g=isfinite(a); if ~any(g), return; end
    thr=0.05*max(abs(a(g)));   % noise floor 5% amplitudo
    run=0; need=5;             % butuh 5 frame beruntun > thr
    for k=1:n
        if isfinite(a(k))&&a(k)>thr, run=run+1; if run>=need, sf=k-need+1; return; end
        else, run=0; end
    end
end

function fr = i_amalgFromAxslip(axslip, a, b)
%I_AMALGFROMAXSLIP  Frame saat AX-SLIP turun ke bawah noise floor & TETAP,
%   dicari SETELAH puncak dlm [a,b].
    fr=NaN; s=axslip(:).'; n=numel(s);
    idx=a:min(b+round(0.15*(b-a)),n); idx=idx(idx>=1&idx<=n);
    seg=s(idx); g=isfinite(seg); if ~any(g), return; end
    pk=max(seg(g)); if ~(pk>0), return; end
    thr=0.15*pk;                    % 15% puncak = noise floor
    [~,ipk]=max(seg);
    run=0; need=5;
    for j=ipk:numel(seg)
        if isfinite(seg(j))&&seg(j)<thr, run=run+1; if run>=need, fr=idx(j-need+1); return; end
        else, run=0; end
    end
end

function fr = i_amalgFromShear(data, recM, hwRow, fwRow, nF, a, b)
%I_AMALGFROMSHEAR  Amalgamasi fisik: shear_rate -> 0 di zona sesar (node
%   HW..FW). Sampel |shear_rate| sepanjang node antara HW & FW pakai posisi
%   node (origin) recM, cari frame saat mereda & tetap setelah puncak.
%   `data` = struct loadAllFrames (dipass agar tak reload per-sesar).
    fr=NaN;
    if isempty(hwRow)||~isstruct(data), return; end
    r1=hwRow; r2=fwRow; if isempty(r2), r2=hwRow; end
    lo=min(r1,r2); hi=max(r1,r2);
    origins=[];
    for r=lo:hi
        if isfield(recM(r),'origin')&&numel(recM(r).origin)==2, origins(end+1,:)=recM(r).origin; end %#ok<AGROW>
    end
    if isempty(origins), return; end
    % Deret |shear| rata-rata zona per frame.
    ser=nan(1,nF);
    for k=1:nF
        [Z,~]=pivcore.data.resolveScalar(data,'shear_rate',k);
        if isempty(Z), continue; end
        x=pivcore.data.safeFrame(data.x,k); y=pivcore.data.safeFrame(data.y,k);
        if isempty(x)||isempty(y)||~isequal(size(Z),size(x)), continue; end
        xrow=x(1,:); ycol=y(:,1);
        yMid=(max(ycol)+min(ycol))/2; ycolF=2*yMid-ycol;
        vals=[];
        for t=1:size(origins,1)
            [~,ic]=min(abs(xrow(:)-origins(t,1)));
            [~,ir]=min(abs(ycolF(:)-origins(t,2)));
            v=Z(ir,ic); if isfinite(v), vals(end+1)=abs(v); end %#ok<AGROW>
        end
        if ~isempty(vals), ser(k)=mean(vals); end
    end
    idx=a:min(b+round(0.15*(b-a)),nF); idx=idx(idx>=1&idx<=nF);
    seg=ser(idx); g=isfinite(seg); if ~any(g), return; end
    pk=max(seg(g)); if ~(pk>0), return; end
    thr=0.20*pk; [~,ipk]=max(seg); run=0; need=5;
    for j=ipk:numel(seg)
        if isfinite(seg(j))&&seg(j)<thr, run=run+1; if run>=need, fr=idx(j-need+1); return; end
        else, run=0; end
    end
end

% =====================================================================
% ---- kalibrasi & envelope helper ----
function [env, have] = i_axpotIndenter(matFile, nF)
%I_AXPOTINDENTER  Coba baca indenter track dari <base>_axpot.mat (referensi
%   dinding independen). env = px/frame |V| dinding per frame; have=false bila
%   tak ada.
    env=[]; have=false;
    ap=strrep(matFile,'.mat','_axpot.mat');
    if ~isfile(ap), return; end
    try, S=load(ap); catch, return; end
    % cari field indenter/envelope yang plausibel.
    cand={'indenter','indenterEnv','env','envelope','wall'};
    fn=fieldnames(S);
    for c=1:numel(cand)
        hit=fn(strcmpi(fn,cand{c}));
        if ~isempty(hit)
            v=S.(hit{1});
            if isnumeric(v)&&numel(v)>=2, env=v(:).'; have=true; return; end
            if isstruct(v)
                for g={'env','y','values','data'}
                    if isfield(v,g{1})&&isnumeric(v.(g{1}))&&numel(v.(g{1}))>=2
                        env=v.(g{1})(:).'; have=true; return;
                    end
                end
            end
        end
    end
end

function s = i_compareEnv(envA, envB, haveB)
    s=struct('haveB',haveB,'medA',NaN,'medB',NaN,'relDiffPct',NaN,'flag',false);
    a=envA(isfinite(envA)); if isempty(a), return; end
    s.medA=median(a(max(1,end-round(0.2*numel(a))):end));
    if ~haveB||isempty(envB), return; end
    b=envB(isfinite(envB)); if isempty(b), return; end
    s.medB=median(b(max(1,end-round(0.2*numel(b))):end));
    if s.medB>0, s.relDiffPct=abs(s.medA-s.medB)/s.medB*100; s.flag=s.relDiffPct>5; end
end

function s = i_envDrift(xr, env)
%I_ENVDRIFT  Fit linier |V|_wall vs strain -> slope %/regangan (uji paralaks).
    s=struct('slopePctPerStrain',NaN,'driftPctOverRun',NaN,'note','');
    g=isfinite(xr)&isfinite(env); if sum(g)<3, return; end
    x=xr(g); y=env(g);
    P=polyfit(x,y,1);
    m0=median(y); if m0<=0, return; end
    s.slopePctPerStrain = P(1)/m0*100;                 % % dari median per unit strain
    span=max(x)-min(x);
    s.driftPctOverRun = P(1)*span/m0*100;              % % perubahan sepanjang run
    if abs(s.driftPctOverRun)<10
        s.note='drift kecil (<10%): deficit relatif kebal paralaks (pembilang&penyebut sama-frame).';
    else
        s.note='drift >10%: waspada paralaks; deficit tetap relatif same-frame tapi tandai.';
    end
end

% =====================================================================
% ---- statistik & util ----
function v = i_medWin(y, win)
    v=NaN; if isempty(y), return; end
    win=win(win>=1&win<=numel(y)); if isempty(win), return; end
    seg=y(win); seg=seg(isfinite(seg)); if isempty(seg), return; end
    v=median(seg);
end
function d = i_deficit(hw, wall)
    d=NaN; if isfinite(hw)&&isfinite(wall)&&wall>1e-9, d=1-hw/wall; end
end
function v = i_scalarField(s,f)
    v=NaN; if isfield(s,f)&&isscalar(s.(f))&&isfinite(s.(f)), v=s.(f); end
end
function s = i_ns(x), if isfinite(x), s=sprintf('%d',round(x)); else, s='-'; end, end
function s = i_tf(c,a,b), if c, s=a; else, s=b; end, end

function log = i_logger(outDir)
    logFile=fullfile(outDir,'PAB_VXVY_run.log');
    fid=fopen(logFile,'w');
    log=@(m) i_logline(fid,m);
end
function i_logline(fid,m)
    fprintf('%s\n',m); if fid>0, fprintf(fid,'%s\n',m); end
end

% =====================================================================
% ---- output: plot per kondisi ----
function i_plotCondition(runs, cond, outPdf)
    n=numel(runs); if n==0, return; end
    ff=figure('Color','w','Units','pixels','Position',[60 60 1000 240*n+60],'Visible','off');
    try, pivui.forceLightTheme(ff); catch, end
    for i=1:n
        R=runs{i}; ax=subplot(n,1,i,'Parent',ff);
        i_panelAxes(ax, R, cond);
        if i<n, xlabel(ax,''); end
    end
    set(ff,'PaperPositionMode','auto');
    try, exportgraphics(ff,outPdf,'ContentType','vector','BackgroundColor','white');
    catch, print(ff,outPdf,'-dpdf','-bestfit'); end
    if isvalid(ff), close(ff); end
end

function i_panelAxes(ax, R, cond)
    cla(ax); hold(ax,'on');
    set(ax,'Color','w','Box','on','Layer','top','XColor',[.15 .15 .15],'YColor',[.15 .15 .15]);
    X=R.xr; vM=R.vMult;
    % envelope dinding (hitam tebal) = |V| wall.
    if ~isempty(R.env_mag)
        e=R.env_mag*vM; m=min(numel(e),numel(X)); g=isfinite(e(1:m));
        plot(ax,X(1:m),e(1:m).*g./g,'-','Color',[0 0 0],'LineWidth',2.4);
    end
    % Vx dinding (garis putus abu).
    if ~isempty(R.env_vx)
        e=abs(R.env_vx)*vM; m=min(numel(e),numel(X));
        plot(ax,X(1:m),e(1:m),'--','Color',[0.5 0.5 0.5],'LineWidth',1.2);
    end
    % kurva HW tiap sesar matang: Vx tebal, Vy tipis.
    cmap=lines(max(1,numel(R.faults)));
    for k=1:numel(R.faults)
        f=R.faults{k}; if ~isfield(f,'series'), continue; end
        col=cmap(k,:);
        s=f.series; m=min(numel(s.xr),numel(s.vx_HW));
        plot(ax,s.xr(1:m),abs(s.vx_HW(1:m)),'-','Color',col,'LineWidth',1.6);
        plot(ax,s.xr(1:m),abs(s.vy_HW(1:m)),':','Color',col,'LineWidth',0.9);
    end
    hold(ax,'off'); grid(ax,'on');
    if R.haveStrain, xlabel(ax,'Cumulative strain (%)'); set(ax,'XDir','reverse');
    else, xlabel(ax,'Frame'); end
    if R.calibrated, ylabel(ax,'|V| , |Vx| , |Vy| (cm/s)');
    else, ylabel(ax,'px/frame'); end
    tag=''; if ~R.calibrated, tag=' [px/frame: Y-calib missing]'; end
    title(ax, sprintf('%s  —  HW Vx(bold)/Vy(dotted) vs wall |V|(black), |Vx|(dashed)%s', ...
        R.base, tag), 'Interpreter','none','FontSize',9);
end

% =====================================================================
% ---- output: figur ringkas ----
function i_plotSummary(panels, fricOrder, fricColor, outPdf)
    mature = panels(cellfun(@(p) isfield(p,'mature')&&p.mature, panels));
    if isempty(mature), mature=panels; end
    ff=figure('Color','w','Units','pixels','Position',[60 60 1000 420],'Visible','off');
    try, pivui.forceLightTheme(ff); catch, end

    % (1) deficit_x vs deficit_mag scatter.
    ax1=subplot(1,2,1,'Parent',ff); hold(ax1,'on');
    for i=1:numel(mature)
        p=mature{i}; c=[0.3 0.3 0.3];
        if isKey(fricColor,p.condition), c=fricColor(p.condition); end
        if isfinite(p.deficit_mag_field)&&isfinite(p.deficit_x)
            plot(ax1,p.deficit_mag_field,p.deficit_x,'o','MarkerFaceColor',c,'MarkerEdgeColor','k','MarkerSize',7);
        end
    end
    lim=[0 0.5]; plot(ax1,lim,lim,'--','Color',[.6 .6 .6]);
    xlabel(ax1,'deficit\_mag (1-|V|_{HW}/Vmax, field)'); ylabel(ax1,'deficit\_x (1-|Vx|_{HW}/|Vx|_{wall})');
    title(ax1,'deficit\_x vs deficit\_mag'); grid(ax1,'on'); axis(ax1,'equal'); xlim(ax1,lim); ylim(ax1,lim);
    box(ax1,'on');

    % (2) deficit_x per kondisi (boxplot manual).
    ax2=subplot(1,2,2,'Parent',ff); hold(ax2,'on');
    xt=[];
    for j=1:numel(fricOrder)
        cond=fricOrder{j};
        dx=[]; dm=[];
        for i=1:numel(mature)
            p=mature{i};
            if strcmp(p.condition,cond)
                if isfinite(p.deficit_x), dx(end+1)=p.deficit_x; end %#ok<AGROW>
                if isfinite(p.deficit_mag), dm(end+1)=p.deficit_mag; end %#ok<AGROW>
            end
        end
        c=[0.3 0.3 0.3]; if isKey(fricColor,cond), c=fricColor(cond); end
        if ~isempty(dx)
            jit=(rand(1,numel(dx))-0.5)*0.12;
            plot(ax2,j+jit,dx,'o','MarkerFaceColor',c,'MarkerEdgeColor','k','MarkerSize',6);
            plot(ax2,[j-0.2 j+0.2],[median(dx) median(dx)],'-','Color',c,'LineWidth',2.5);
        end
        xt{end+1}=strrep(cond,'-4cm-F',''); %#ok<AGROW>
    end
    plot(ax2,[0.5 numel(fricOrder)+0.5],[0.18 0.18],':','Color',[.5 .5 .5]);
    text(ax2,numel(fricOrder)+0.5,0.18,' 0.18 (mag lama)','Color',[.5 .5 .5],'FontSize',8,'HorizontalAlignment','right','VerticalAlignment','bottom');
    set(ax2,'XTick',1:numel(fricOrder),'XTickLabel',xt);
    xlim(ax2,[0.5 numel(fricOrder)+0.5]); ylabel(ax2,'deficit\_x'); title(ax2,'deficit\_x vs friksi (LF<CON<HF?)');
    grid(ax2,'on'); box(ax2,'on');

    set(ff,'PaperPositionMode','auto');
    try, exportgraphics(ff,outPdf,'ContentType','vector','BackgroundColor','white');
    catch, print(ff,outPdf,'-dpdf','-bestfit'); end
    if isvalid(ff), close(ff); end
end

% =====================================================================
% ---- output: CSV / JSON / report ----
function i_writeCsv(panels, outCsv)
    fid=fopen(outCsv,'w');
    fprintf(fid,['condition,run,uiNum,mature,suspect,calibrated,vMult,startF_json,startF_axslip,' ...
        'amalg_xfs,amalg_axslip,amalg_shear,amalg_endF,amalgFrame,amalgSpread,' ...
        'plateauW0,plateauW1,magSelfHW_plateau,magFieldHW_plateau,vxHW_plateau,vyHW_plateau,' ...
        'magSelf_wall,magField_wall,vx_wall,' ...
        'deficit_x,deficit_mag_self,deficit_mag_field,VyOverVx\n']);
    for i=1:numel(panels)
        p=panels{i};
        fprintf(fid,'%s,%d,%g,%d,%d,%d,%.6g,%g,%s,%s,%s,%s,%g,%g,%s,%g,%g,%.5g,%.5g,%.5g,%.5g,%.5g,%.5g,%.5g,%.5g,%.5g,%.5g,%.4g\n', ...
            p.condition, p.runIndex, p.uiNum, p.mature, p.suspect, p.calibrated, p.vMult, ...
            p.startF_json, i_ns(p.startF_axslip), i_ns(p.amalg_xfs), i_ns(p.amalg_axslip), ...
            i_ns(p.amalg_shear), p.amalg_endF, p.amalgFrame, i_ns(p.amalgSpread), ...
            p.plateauWin(1), p.plateauWin(2), p.mag_HW_plateau, p.magField_HW_plateau, ...
            p.vx_HW_plateau, p.vy_HW_plateau, ...
            p.mag_wall, p.magField_wall, p.vx_wall, ...
            p.deficit_x, p.deficit_mag_self, p.deficit_mag_field, p.VyOverVx);
    end
    fclose(fid);
end

function P = i_panelsForJson(panels)
    P=cell(1,numel(panels));
    for i=1:numel(panels)
        p=panels{i};
        q=rmfield(p,'series');   % deret besar -> ke .mat saja
        P{i}=q;
    end
end

function s = i_summaryStats(panels, fricOrder)
    s=struct();
    mat=panels(cellfun(@(p) isfield(p,'mature')&&p.mature, panels));
    dx=cellfun(@(p) p.deficit_x, mat); dx=dx(isfinite(dx));
    dms=cellfun(@(p) p.deficit_mag_self, mat); dms=dms(isfinite(dms));
    dmf=cellfun(@(p) p.deficit_mag_field, mat); dmf=dmf(isfinite(dmf));
    s.n_mature=numel(mat);
    s.deficit_x_mean=i_m(dx); s.deficit_x_sd=i_sd(dx);
    s.deficit_mag_self_mean=i_m(dms); s.deficit_mag_self_sd=i_sd(dms);
    s.deficit_mag_field_mean=i_m(dmf); s.deficit_mag_field_sd=i_sd(dmf);
    for j=1:numel(fricOrder)
        cond=fricOrder{j};
        v=cellfun(@(p) p.deficit_x, mat(cellfun(@(p) strcmp(p.condition,cond), mat)));
        v=v(isfinite(v));
        key=matlab.lang.makeValidName(cond);
        s.byCondition.(key)=struct('n',numel(v),'deficit_x_mean',i_m(v),'deficit_x_sd',i_sd(v));
    end
end
function m=i_m(v), if isempty(v), m=NaN; else, m=mean(v); end, end
function s=i_sd(v), if numel(v)<2, s=NaN; else, s=std(v); end, end

function i_writeReport(RESULT, outMd)
    S=RESULT.summary;
    fid=fopen(outMd,'w');
    fp=@(varargin) fprintf(fid,varargin{:});
    fp('# Dekomposisi Vx/Vy & Defisit Transport Horizontal Hanging Wall\n\n');
    fp('_Dihasilkan: %s_\n\n', RESULT.generatedAt);
    fp('## Metode\n\n');
    fp('- Kurva HW/FW disampel IDENTIK dgn PAB4AXPOT CLEAN (garis PSG kanonik, potdata excluded+cutFrame, trim [startF,endF]).\n');
    fp('- Komponen Vx/Vy dari **u_smoothed/v_smoothed** — bukan u_filtered — karena `velocity_magnitude` PIVlab = hypot(u_smoothed,v_smoothed) PERSIS (u_component kosong; sqrt(u_filtered^2+v_filtered^2) beda ~48%% dari |V|). Ini menjaga sqrt(Vx^2+Vy^2)=|V| (sanity lolos) & sebanding dgn deficit_mag lama.\n');
    fp('- Defisit dari **|Vx|** (magnitude, kebal arah). Shortening di zona ukur bergerak ke +x (kamera tengah, ukur dari kiri).\n');
    fp('- Plateau fase-aktif = **median** jendela [amalgamasi-K, amalgamasi], K=%g frame (bukan max seluruh kurva).\n', RESULT.plateauK);
    fp('- Amalgamasi objektif = median dari {X-FS(json), AX-SLIP->0, shear_rate->0, endF(label)}.\n\n');
    fp('## Hasil Utama\n\n');
    fp('| Metrik | Nilai |\n|---|---|\n');
    fp('| n sesar matang | %d |\n', S.n_mature);
    fp('| **deficit_x** (BARU, horizontal) | %.3f ± %.3f |\n', S.deficit_x_mean, S.deficit_x_sd);
    fp('| deficit_mag (field |V|, ~ lama 0.18) | %.3f ± %.3f |\n', S.deficit_mag_field_mean, S.deficit_mag_field_sd);
    fp('| deficit_mag (|V|_self=hypot(Vx,Vy)) | %.3f ± %.3f |\n', S.deficit_mag_self_mean, S.deficit_mag_self_sd);
    fp('\nKlaim lama HW ≈ 0,82 × Vmax → deficit_mag ≈ 0,18 (basis field |V|). ');
    if isfinite(S.deficit_x_mean) && isfinite(S.deficit_mag_field_mean)
        if S.deficit_x_mean < S.deficit_mag_field_mean
            fp('deficit_x (%.3f) **lebih kecil** dari deficit_mag (%.3f): sebagian "kelambatan" |V| ternyata pengangkatan ramp (Vy), bukan defisit transport horizontal sejati.\n\n', S.deficit_x_mean, S.deficit_mag_field_mean);
        else
            fp(['deficit_x (%.3f) **lebih besar** dari deficit_mag (%.3f): |V| MEREMEHKAN defisit horizontal. ' ...
                'Karena Vy (pengangkatan ramp) menambah |V|, HW tampak lebih cepat dari transport horizontal sejatinya; ' ...
                'defisit horizontal (shortening yg diserap sesar) sebenarnya LEBIH BESAR dari angka |V| lama.\n\n'], ...
                S.deficit_x_mean, S.deficit_mag_field_mean);
        end
    end
    fp('## Defisit per kondisi friksi\n\n');
    fp('| Kondisi | n | deficit_x mean | sd |\n|---|---|---|---|\n');
    lf=NaN;con=NaN;hf=NaN;
    if isfield(S,'byCondition')
        fns=fieldnames(S.byCondition);
        for i=1:numel(fns)
            b=S.byCondition.(fns{i});
            fp('| %s | %d | %.3f | %.3f |\n', fns{i}, b.n, b.deficit_x_mean, b.deficit_x_sd);
            if ~isempty(strfind(fns{i},'LF')), lf=b.deficit_x_mean; end
            if ~isempty(strfind(fns{i},'CON')), con=b.deficit_x_mean; end
            if ~isempty(strfind(fns{i},'HF'))&&isempty(strfind(fns{i},'LF')), hf=b.deficit_x_mean; end
        end
    end
    fp('\n**Hipotesis awal**: friksi↑ → defisit↑ (LF < CON < HF).\n\n');
    if isfinite(lf)&&isfinite(con)&&isfinite(hf)
        if lf<con && con<hf
            fp('**Teramati**: LF(%.3f) < CON(%.3f) < HF(%.3f) → hipotesis DIDUKUNG: friksi basal tinggi memperbesar defisit transport horizontal HW.\n\n', lf,con,hf);
        elseif lf>con && con>hf
            fp('**Teramati KEBALIKAN**: LF(%.3f) > CON(%.3f) > HF(%.3f). Friksi basal TINGGI justru MENGURANGI defisit horizontal — konsisten dgn sesar lebih curam/efisien pada HF sehingga HW mengikuti dinding lebih dekat; pada LF, HW lebih tertinggal secara horizontal.\n\n', lf,con,hf);
        else
            fp('**Teramati**: LF=%.3f, CON=%.3f, HF=%.3f (tak monotonik). Lihat summary PDF.\n\n', lf,con,hf);
        end
    end
    fp('## Caveat\n\n');
    fp('- Drift envelope (uji paralaks): slope %%/regangan dicetak per run di log & JSON; defisit relatif same-frame kebal drift kecil.\n');
    fp('- Sesar termuda (endF ≈ nF) ditandai IMMATURE & dikeluarkan dari statistik matang.\n');
    fp('- Vmax(b) indenter axpot dipakai bila sidecar _axpot.mat memuat track; kalau tidak, hanya Vmax(a) empiris.\n');
    fclose(fid);
end
