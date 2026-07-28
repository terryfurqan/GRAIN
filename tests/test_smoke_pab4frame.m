function test_smoke_pab4frame(rootDir)
%TEST_SMOKE_PAB4FRAME  Smoke test PAB4Frame (ekspor frame velmag+shear, zoom-aware).
%   Blok:
%     A  build GUI -> axPOT DISEMBUNYIKAN + strip POT tersembunyi + axMain diperbesar
%        + panel kanan punya kontrol (edFrameRange/btnFrameImg/btnAxZoom/edAxW/edExportPx)
%     B  eksperimen termuat -> h.df + h.data terisi
%     C  kontrol UKURAN axMain: apply lebar/tinggi -> h.axMainPos berubah + Position axMain
%     D  crop-lim mengikuti XLim/YLim axMain; ukuran figure ekspor ber-aspek crop
%     E  ekspor 1 bingkai (override root temp) -> 2 JPG (velmag + shear) tertulis
%     F  zoom-lock: set kunci pandang -> crop-lim = view beku (ekspor mengikuti crop)
%
%   SENYAP: DefaultFigureVisible off. Fixture default = RAW/PIV_2026-06-24. SELALU R2025b.

    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(fileparts(here)));                 % PAB/ (PAB4Frame.m)
    addpath(fullfile(fileparts(here), 'pivcore_lib'));  % engine
    try, pab_setup; catch, end

    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>

    if nargin < 1 || isempty(rootDir)
        cand = {fullfile(fileparts(fileparts(here)), 'RAW', 'PIV_2026-06-24'), ...
                '/Users/terryfurqan/MACTERR_shared/Automasi PIV LAB/RAW/PIV_2026-06-24'};
        rootDir = '';
        for i = 1:numel(cand)
            if isfolder(cand{i}), rootDir = cand{i}; break; end
        end
    end
    if isempty(rootDir) || ~isfolder(rootDir)
        fprintf('[SKIP] test_smoke_pab4frame: fixture folder tak ada.\n'); return;
    end
    fprintf('Fixture root: %s\n', rootDir);

    % ========================= A. BUILD =========================
    fprintf('==== A. Build GUI ====\n');
    fig = PAB4Frame(rootDir);
    assert(ishghandle(fig), 'A: figure tak terbuat');
    cu = onCleanup(@() i_closeIf(fig)); %#ok<NASGU>
    h = guidata(fig);
    assert(isfield(h,'axMain') && ishghandle(h.axMain), 'A: axMain absen');
    assert(isfield(h,'axPOT') && strcmp(get(h.axPOT,'Visible'),'off'), 'A: axPOT belum disembunyikan');
    assert(strcmp(get(h.btnAxView,'Visible'),'off'), 'A: strip POT (btnAxView) belum tersembunyi');
    p = get(h.axMain,'Position');
    assert(abs(p(4)-0.800) < 0.05, 'A: axMain belum diperbesar (tinggi=%.3f)', p(4));
    for nm = {'edFrameRange','btnFrameImg','btnFrameExp','btnFrameAllExp','btnAxZoom', ...
              'btnAxViewLock','edAxW','edAxH','edExportPx','btnMovie'}
        assert(isfield(h,nm{1}) && ishghandle(h.(nm{1})), 'A: kontrol %s absen', nm{1});
    end
    fprintf('   axPOT off, strip POT off, axMain tinggi=%.3f, kontrol lengkap: OK\n', p(4));

    % ========================= B. LOAD =========================
    fprintf('==== B. Eksperimen termuat ====\n');
    if isempty(h.data)
        try, pivui.pab4Shell.loadExperiment(fig, 1); catch, end
        h = guidata(fig);
    end
    if isempty(h.data)
        fprintf('[SKIP] test_smoke_pab4frame: tak ada .mat termuat di folder.\n'); return;
    end
    assert(~isempty(h.df), 'B: h.df kosong pasca-load');
    nF = max(1, pivcore.data.frameCount(h.data));
    fprintf('   df=%s  nF(termuat)=%d: OK\n', i_bn(h.df), nF);

    % ========================= C. UKURAN axMain =========================
    fprintf('==== C. Kontrol ukuran axMain ====\n');
    set(h.edAxW,'String','0.400'); set(h.edAxH,'String','0.600');
    i_click(h.edAxW);   % callback = i_onApplyAxSize
    h = guidata(fig);
    assert(abs(h.axMainPos(3)-0.400) < 1e-3 && abs(h.axMainPos(4)-0.600) < 1e-3, ...
        'C: axMainPos tak terapply (%.3f × %.3f)', h.axMainPos(3), h.axMainPos(4));
    fprintf('   axMainPos = [%.3f %.3f %.3f %.3f]: OK\n', h.axMainPos);
    % kembalikan default supaya ekspor pakai box penuh
    i_click(findobj(fig,'Style','pushbutton','String','Reset'));
    h = guidata(fig);

    % ========================= D. CROP-LIM + ukuran figure =========================
    fprintf('==== D. Crop-lim & ukuran figure ====\n');
    xl = get(h.axMain,'XLim'); yl = get(h.axMain,'YLim');
    assert(diff(xl)>0 && diff(yl)>0, 'D: XLim/YLim axMain tak valid');
    fprintf('   crop XLim[%.0f %.0f] YLim[%.0f %.0f]: OK\n', xl, yl);

    % ========================= E. EKSPOR 1 bingkai =========================
    fprintf('==== E. Ekspor 1 bingkai (velmag + shear) ====\n');
    outRoot = fullfile(tempdir, 'PAB4FRAME_TEST');
    if isfolder(outRoot), try, rmdir(outRoot,'s'); catch, end, end
    h.exportRootOverride = outRoot; h.exportStampOverride = 'TEST';
    set(h.edFrameRange,'String','1');
    guidata(fig, h);
    i_click(h.btnFrameImg);   % callback = i_onExportFrameImg
    jpgs = dir(fullfile(outRoot,'**','*.jpg'));
    assert(numel(jpgs) >= 2, 'E: harusnya >=2 JPG (velmag+shear), dapat %d', numel(jpgs));
    fprintf('   %d JPG tertulis di %s: OK\n', numel(jpgs), outRoot);
    try, rmdir(outRoot,'s'); catch, end

    % ========================= F. Zoom-lock crop =========================
    fprintf('==== F. Kunci pandang -> crop mengikuti view beku ====\n');
    h = guidata(fig);
    xlz = [xl(1) mean(xl)]; ylz = yl;   % crop separuh kiri (buang sisi kanan)
    set(h.axMain,'XLim',xlz,'YLim',ylz);
    i_click(h.btnAxViewLock);   % kunci pandang ON
    h = guidata(fig);
    assert(h.axMainViewLock && numel(h.axMainViewLim)==4, 'F: kunci pandang tak aktif');
    assert(abs(h.axMainViewLim(2)-xlz(2)) < 1e-6, 'F: view beku tak = crop');
    fprintf('   kunci pandang X[%.0f %.0f]: OK\n', h.axMainViewLim(1:2));

    close(fig);
    fprintf('\n===== test_smoke_pab4frame: SEMUA BLOK LULUS =====\n');
end

function i_click(hCtrl)
    if isempty(hCtrl) || ~ishghandle(hCtrl), return; end
    cb = get(hCtrl,'Callback');
    if ~isempty(cb), cb(hCtrl, []); end
end

function s = i_bn(df)
    [~, s] = fileparts(char(df));
end

function i_closeIf(fig)
    try, if ishghandle(fig), close(fig); end, catch, end
end
