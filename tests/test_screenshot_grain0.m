function test_screenshot_grain0()
%TEST_SCREENSHOT_GRAIN0  Uji tata-letak GRAIN0 (QPIV): tangkap screenshot + deteksi
%   overlap/ spacing kacau antar-widget secara terprogram (headless).
%
%   Memvalidasi:
%     1. GRAIN0() membentuk uifigure tanpa dialog (root kosong).
%     2. Semua widget BARU/PINDAH ada: tiltField, cancelBtn, runBtn & saveNextBtn
%        (di fig/tengah), autoBtn + min/max + skip (di panel kanan), Save/Load
%        Progress (kiri), frTable.ColumnSortable kolom Abaikan = true.
%     3. Tak ada widget kontrol yang SALING TUMPANG-TINDIH dalam satu induk.
%     4. Screenshot diekspor ke PNG (exportapp) bila display tersedia.
%
%   Jalankan: grain_setup; test_screenshot_grain0
%   SELALU MATLAB R2025b.

    fprintf('\n=== SCREENSHOT/LAYOUT GRAIN0 ===\n');
    grain_setup();
    assert(~isempty(which('GRAIN0')), 'GRAIN0 tak di-path');

    ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP
    restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>  % pulihkan sesi
    GRAIN0();
    drawnow;
    fig = findall(0,'Type','figure','-regexp','Name','^GRAIN0');
    assert(~isempty(fig), 'figure GRAIN0 tak terbentuk');
    fig = fig(1);
    cl = onCleanup(@() i_closeFig(fig));
    assert(isa(fig,'matlab.ui.Figure'), 'GRAIN0 bukan uifigure');
    fprintf('  [1] uifigure GRAIN0 terbentuk tanpa dialog\n');

    % --- 2. Widget kunci ada ----------------------------------------------
    need = {'Angle','Position','✖ Cancel QPIV','▶ Run QPIV', ...
            '✓ Save ▸ Next ▸ QPIV','✓ Save ▸ Next (no QPIV)','▶▶ QPIV all exps', ...
            'Auto-detect dead frames', ...
            'Manual frame skip (e.g. 1,2,5-9):','💾 Save Progress','📂 Load Progress', ...
            '🔒 IW','🔒 Pos','🔒 etc'};   % 3 ceklis kunci config (anti reset antar-exp)
    allTxt = i_allText(fig);
    for k = 1:numel(need)
        assert(any(contains(allTxt, need{k})), ...
            sprintf('widget/teks hilang: "%s"', need{k}));
    end
    % Tombol/field yang DIPENSIUN tak boleh ada lagi.
    gone = {'Simpan exclusion','Run SEMUA','Interval ±','detektor mati','detektor interval','Terapkan saran'};
    for k = 1:numel(gone)
        assert(~any(contains(allTxt, gone{k})), ...
            sprintf('widget yang dipensiunkan masih ada: "%s"', gone{k}));
    end
    fprintf('  [2] widget baru/pindah ada; widget pensiun hilang\n');

    % --- 2b. frTable sortable di kolom paling kanan (Abaikan) -------------
    tbls = findall(fig,'Type','uitable');
    frT = [];
    for k = 1:numel(tbls)
        cn = tbls(k).ColumnName;
        if iscell(cn) && any(strcmp(cn,'Ignore')); frT = tbls(k); break; end
    end
    assert(~isempty(frT), 'tabel frame (Ignore) tak ditemukan');
    cs = frT.ColumnSortable;
    assert(numel(cs)>=4 && cs(end)==true, 'kolom Ignore harus ColumnSortable=true');
    assert(~any(cs(1:3)), 'hanya kolom paling kanan yang boleh sortable');
    fprintf('  [2b] frTable.ColumnSortable kolom Ignore = true (asc/desc)\n');

    % --- 3. Deteksi overlap antar-kontrol satu induk ---------------------
    bad = {};
    i_walk(fig);
    if ~isempty(bad)
        fprintf(2,'  OVERLAP terdeteksi:\n');
        for k = 1:numel(bad); fprintf(2,'    - %s\n', bad{k}); end
    end
    assert(isempty(bad), sprintf('%d pasang widget tumpang-tindih', numel(bad)));
    fprintf('  [3] tak ada overlap antar-kontrol (semua induk)\n');

    % --- 4. Screenshot (best-effort) -------------------------------------
    outdir = fullfile(tempdir,'grain0_shot'); if ~isfolder(outdir); mkdir(outdir); end
    png = fullfile(outdir,'grain0_layout.png');
    ok = false;
    try, exportapp(fig, png); ok = isfile(png); catch ME
        fprintf('  [4] exportapp dilewati (%s)\n', ME.message);
    end
    if ok; fprintf('  [4] screenshot: %s\n', png); end

    fprintf('=== SCREENSHOT/LAYOUT GRAIN0: LULUS ===\n\n');

    % ============== nested: walk + overlap ===========================
    function i_walk(parent)
        ch = allchild(parent);
        ctrl = {};
        for ii = 1:numel(ch)
            c = ch(ii);
            if i_isCtrl(c); ctrl{end+1} = c; end %#ok<AGROW>
        end
        for a = 1:numel(ctrl)
            for b = a+1:numel(ctrl)
                [ov,wd,ht] = i_overlap(ctrl{a}.Position, ctrl{b}.Position);
                if ov
                    bad{end+1} = sprintf('%s "%s" ∩ %s "%s" (%.0fx%.0f px)', ...
                        i_short(ctrl{a}), i_lbl(ctrl{a}), i_short(ctrl{b}), i_lbl(ctrl{b}), wd, ht); %#ok<AGROW>
                end
            end
        end
        for ii = 1:numel(ch)   % rekursi ke kontainer
            if isa(ch(ii),'matlab.ui.container.Panel') || isa(ch(ii),'matlab.ui.container.Tab')
                i_walk(ch(ii));
            end
        end
    end
end

% ---- kontrol yang dicek overlap (kontainer/axes dikecualikan) ----------
function tf = i_isCtrl(c)
    tf = isa(c,'matlab.ui.control.Button') || isa(c,'matlab.ui.control.NumericEditField') || ...
         isa(c,'matlab.ui.control.EditField') || isa(c,'matlab.ui.control.DropDown') || ...
         isa(c,'matlab.ui.control.CheckBox') || isa(c,'matlab.ui.control.Label') || ...
         isa(c,'matlab.ui.control.Table') || isa(c,'matlab.ui.control.Slider');
end

function [tf,w,h] = i_overlap(p1,p2)
    % toleransi 2px: sentuhan tepi tak dihitung overlap.
    tol = 2;
    x1=p1(1); y1=p1(2); x2=x1+p1(3); y2=y1+p1(4);
    a1=p2(1); b1=p2(2); a2=a1+p2(3); b2=b1+p2(4);
    w = min(x2,a2) - max(x1,a1);
    h = min(y2,b2) - max(y1,b1);
    tf = (w > tol) && (h > tol);
end

function s = i_short(c)
    t = class(c); p = strsplit(t,'.'); s = p{end};
end

function s = i_lbl(c)
    s = '';
    try
        if isprop(c,'Text') && ~isempty(c.Text)
            s = char(string(c.Text));
        elseif isprop(c,'Value') && (ischar(c.Value)||isstring(c.Value))
            s = char(string(c.Value));
        elseif isa(c,'matlab.ui.control.Table')
            s = 'table';
        end
    catch
    end
    if numel(s) > 22; s = [s(1:20) '..']; end
end

function txt = i_allText(fig)
    txt = strings(0,1);
    w = findall(fig);
    for k = 1:numel(w)
        c = w(k);
        try
            if isprop(c,'Text') && ~isempty(c.Text)
                txt(end+1) = string(char(string(c.Text))); %#ok<AGROW>
            end
        catch
        end
        try
            if isprop(c,'Title') && ~isempty(c.Title) && ~isgraphics(c.Title)
                txt(end+1) = string(char(string(c.Title))); %#ok<AGROW>
            end
        catch
        end
    end
end

function i_closeFig(fig)
    try, if isgraphics(fig); close(fig); end; catch, end
end
