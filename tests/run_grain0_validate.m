function run_grain0_validate()
%RUN_GRAIN0_VALIDATE  Suite validasi GRAIN0 pasca-perbaikan: checkcode, screenshot/
%   overlap, smoke logika, dan cek finit pada tilt=90 (regresi tand(90)=Inf).
%   SELALU MATLAB R2025b.
here = fileparts(mfilename('fullpath'));
addpath(here); addpath(fileparts(here)); grain_setup;
ov = get(0,'DefaultFigureVisible'); set(0,'DefaultFigureVisible','off');   % SENYAP: seluruh suite tak rebut fokus
restoreVis = onCleanup(@() set(0,'DefaultFigureVisible',ov)); %#ok<NASGU>  % pulihkan sesi di akhir
NAME = '^GRAIN0';

fprintf('\n##### 1. CHECKCODE (syntax) #####\n');
m = checkcode(which('GRAIN0'),'-id'); err=0;
for k=1:numel(m)
    if any(strcmp(m(k).id,{'MERR','SYNER','PARSE'}))
        fprintf(2,'  SYNTAX L%d %s\n',m(k).line,m(k).message); err=err+1;
    end
end
if err==0; fprintf('  PASS: tak ada error syntax\n'); end

fprintf('\n##### 2. test_screenshot_grain0 (overlap/layout/widget) #####\n');
ok2=true; try, test_screenshot_grain0; catch e; ok2=false; fprintf(2,'  FAIL: %s\n',e.message); end

fprintf('\n##### 3. test_smoke_grain_step0b (logika exclusion) #####\n');
ok3=true; try, test_smoke_grain_step0b; catch e; ok3=false; fprintf(2,'  FAIL: %s\n',e.message); end

fprintf('\n##### 4. Regresi tilt=90 (no Inf, garis finit) #####\n');
ok4=true;
try
    set(0,'DefaultFigureVisible','off');
    repoRoot = fileparts(fileparts(here));
    GRAIN0(repoRoot);
    f = findall(0,'Type','figure','-regexp','Name',NAME); f=f(end);
    % pilih exp pertama -> pratinjau GS
    tbls=findall(f,'Type','uitable'); expTbl=[];
    for k=1:numel(tbls); cn=tbls(k).ColumnName; if iscell(cn)&&any(strcmp(cn,'Experiment')); expTbl=tbls(k); break; end; end
    if ~isempty(expTbl) && ~isempty(expTbl.Data)
        cb=expTbl.CellSelectionCallback; cb(expTbl,struct('Indices',[1 1])); drawnow;
    end
    % dorong sudut ke 90
    sl=findall(f,'Type','uislider'); as=[];
    for k=1:numel(sl); if isequal(sl(k).Limits,[0 90]); as=sl(k); break; end; end
    assert(~isempty(as),'angSlider tak ketemu');
    cba=as.ValueChangedFcn; cba(as,struct('Value',90)); drawnow;
    % verifikasi garis kuning finit
    ln=findall(f,'Type','line'); nline=0;
    for k=1:numel(ln)
        if any(~isfinite(ln(k).XData))||any(~isfinite(ln(k).YData))
            ok4=false; fprintf(2,'  FAIL: garis ada Inf/NaN pada tilt=90\n');
        end
        nline=nline+1;
    end
    if ok4; fprintf('  PASS: tilt=90 -> %d garis, semua koordinat FINIT\n', nline); end
    close(f);
catch e
    ok4=false; fprintf(2,'  FAIL: %s\n',e.message);
end

fprintf('\n##### 5. test_lock_grain0 (kunci config lintas-exp) #####\n');
ok5=true; try, test_lock_grain0; catch e; ok5=false; fprintf(2,'  FAIL: %s\n',e.message); end

fprintf('\n##### RINGKASAN: checkcode=%d screenshot=%d smoke=%d tilt90=%d lock=%d #####\n', ...
    err==0, ok2, ok3, ok4, ok5);
if (err==0)&&ok2&&ok3&&ok4&&ok5; fprintf('===== SEMUA LULUS =====\n'); else; fprintf(2,'===== ADA YANG GAGAL =====\n'); end
end
