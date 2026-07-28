classdef linkView
%LINKVIEW  Panel penampil SATU MAT PIV (velmag + GS + garis PSG) dengan slider
%   frame + label frame/strain — dipakai BERSAMA oleh GRAINLINK (pengikat) &
%   GRAINSYNC (penafsir). Renderer IDENTIK dengan GRAINEXPORT/GRAIN3/GRAIN4
%   (`pivcore.export.frameCatalog.drawScalarPanel`) → "what you see = what you get".
%
%   Pola pakai (host yang menyimpan struct panel di guidata + memasang callback):
%     pn = pivui.linkView.build(parent, posNorm, titleStr);
%     pn = pivui.linkView.loadMat(pn, matFile);          % frame-1 + resolveRender
%     pn = pivui.linkView.gotoFrame(pn, k, strainOverride);  % set slider + render
%     pn = pivui.linkView.render(pn, strainOverride);     % gambar pn.frame
%
%   `strainOverride` (%): isi caption strain. NaN → auto via geometri (R.geom);
%   untuk view TARGET (tampak peta) tanpa geometri, host mengoper strain hasil
%   KALIBRASI (pivcore.io.grainLink) ke sini.
%
%   Penempatan: GRAIN/pivcore_lib/+pivui/linkView.m

    methods (Static)

        % ================================================================
        function pn = build(parent, pos, titleStr)
        %BUILD  Bangun panel (judul + kanvas + slider + label) di `parent` pada
        %   kotak normalized `pos` = [x y w h]. Kembalikan struct panel.
            if nargin < 3, titleStr = ''; end
            WHITE = [1 1 1];
            pn = struct();
            pn.scalar     = 'velocity_magnitude';
            pn.realData   = '';
            pn.base       = '';
            pn.data       = [];
            pn.resolve    = [];
            pn.fullLoaded = false;
            pn.imgFrames  = 1;
            pn.nF         = 1;
            pn.frame      = 1;
            pn.hasGeom    = false;
            pn.up         = pivui.linkView.defaultPrefs();

            host = uipanel('Parent',parent,'Units','normalized','Position',pos, ...
                'BackgroundColor',WHITE,'BorderType','line', ...
                'HighlightColor',[0.8 0.8 0.8]);
            pn.host = host;

            pn.txtTitle = uicontrol('Parent',host,'Style','text','Units','normalized', ...
                'Position',[0.01 0.945 0.98 0.05],'HorizontalAlignment','left', ...
                'FontWeight','bold','FontSize',12,'BackgroundColor',WHITE, ...
                'ForegroundColor',[0 0 0],'String',titleStr);

            pnlAx = uipanel('Parent',host,'Units','normalized', ...
                'Position',[0.01 0.135 0.98 0.805],'BackgroundColor',WHITE, ...
                'BorderType','none');
            pn.ax = axes('Parent',pnlAx,'Units','normalized','Position',[0.08 0.08 0.84 0.86]);
            set(pn.ax,'XTick',[],'YTick',[],'Box','on','Color',[0.96 0.96 0.96]);

            pn.slider = uicontrol('Parent',host,'Style','slider','Units','normalized', ...
                'Position',[0.01 0.075 0.98 0.045],'Min',1,'Max',2,'Value',1, ...
                'SliderStep',[1 1],'Enable','off');
            pn.txtFrame = uicontrol('Parent',host,'Style','text','Units','normalized', ...
                'Position',[0.01 0.035 0.49 0.035],'HorizontalAlignment','left', ...
                'BackgroundColor',WHITE,'ForegroundColor',[0.2 0.2 0.2],'String','frame —/—');
            pn.txtStrain = uicontrol('Parent',host,'Style','text','Units','normalized', ...
                'Position',[0.50 0.035 0.49 0.035],'HorizontalAlignment','right', ...
                'BackgroundColor',WHITE,'ForegroundColor',[0 0 0],'FontWeight','bold', ...
                'String','strain —');
        end


        % ================================================================
        function pn = loadMat(pn, matFile)
        %LOADMAT  Muat MAT PIV (bingkai-1 + setelan render). nF + slider disetel.
            pn.realData   = char(matFile);
            [~, pn.base]  = fileparts(pn.realData);
            pn.data       = [];
            pn.resolve    = [];
            pn.fullLoaded = false;
            pn.imgFrames  = 1;
            pn.nF         = 1;
            pn.frame      = 1;
            pn.hasGeom    = false;

            data1 = pivcore.io.step1Session.loadFrame1(pn.realData);
            R     = pivcore.export.frameCatalog.resolveRender(pn.realData);
            pn.data      = data1;
            pn.resolve   = R;
            pn.imgFrames = pivcore.data.frameCount(data1);
            pn.nF        = max([1, pn.imgFrames, R.nFrames]);
            pn.hasGeom   = isfield(R,'strainTotalPct') && isscalar(R.strainTotalPct) ...
                && isfinite(R.strainTotalPct);

            % slider range
            mx = max(2, pn.nF);
            stepN = max(1, pn.nF-1);
            set(pn.slider, 'Min',1, 'Max',mx, 'Value',1, ...
                'SliderStep',[1/stepN, max(1/stepN, 0.1)], ...
                'Enable', pivui.linkView.enOf(pn.nF > 1));
            pn = pivui.linkView.render(pn, NaN);
        end


        % ================================================================
        function pn = gotoFrame(pn, k, strainOverride)
        %GOTOFRAME  Set frame (clamp 1..nF) + slider + render. strainOverride
        %   diteruskan ke caption (NaN → auto geometri).
            if nargin < 3, strainOverride = NaN; end
            k = round(pivui.linkView.scal(k));
            if ~isfinite(k), k = 1; end
            k = min(max(k,1), max(1,pn.nF));
            pn.frame = k;
            if ishghandle(pn.slider)
                v = min(max(k, get(pn.slider,'Min')), get(pn.slider,'Max'));
                set(pn.slider, 'Value', v);
            end
            pn = pivui.linkView.render(pn, strainOverride);
        end


        % ================================================================
        function pn = render(pn, strainOverride)
        %RENDER  Gambar pn.frame ke kanvas (drawScalarPanel) + label frame/strain.
            if nargin < 2, strainOverride = NaN; end
            if ~ishghandle(pn.ax), return; end
            if isempty(pn.data) || isempty(pn.resolve)
                cla(pn.ax,'reset'); axis(pn.ax,'off');
                text(pn.ax,0.5,0.5,'(pilih MAT PIV)','Units','normalized', ...
                    'HorizontalAlignment','center','Color',[0.5 0.5 0.5]);
                return;
            end
            k = min(max(round(pn.frame),1), max(1,pn.imgFrames));
            if k > 1 && ~pn.fullLoaded
                pn = pivui.linkView.ensureFull(pn);
            end
            k = min(max(round(pn.frame),1), max(1,pn.imgFrames));

            spec = pivcore.export.frameCatalog.specFromResolve(pn.resolve, pn.up);
            cfg  = pivcore.export.frameCatalog.renderCfg(spec);
            dec  = pivcore.export.frameCatalog.decOptsFromSpec(spec, pn.up);
            so   = pivui.linkView.scal(strainOverride);
            if isfinite(so)
                dec.strainPct  = so;
                dec.strainShow = true;
            elseif ~pn.hasGeom
                dec.strainShow = false;     % target tanpa geometri & belum kalibrasi
            end
            cla(pn.ax,'reset');
            pivcore.export.frameCatalog.drawScalarPanel(pn.ax, pn.data, k, pn.scalar, ...
                cfg, pn.resolve, pn.base, dec);

            set(pn.txtFrame, 'String', sprintf('frame %d / %d', k, pn.nF));
            if isfinite(so)
                set(pn.txtStrain, 'String', sprintf('strain %+.3g %%', so));
            elseif pn.hasGeom
                set(pn.txtStrain, 'String', sprintf('strain %+.3g %%', ...
                    (k-1)/max(1,pn.nF-1)*pn.resolve.strainTotalPct));
            else
                set(pn.txtStrain, 'String', 'strain —');
            end
        end


        % ================================================================
        function pn = ensureFull(pn)
        %ENSUREFULL  Muat semua bingkai (sekali) untuk scrub frame k>1.
            if pn.fullLoaded || isempty(pn.realData), return; end
            try
                dataAll = pivcore.io.step1Session.loadAllFrames(pn.realData);
            catch
                return;
            end
            pn.data       = dataAll;
            pn.fullLoaded = true;
            pn.imgFrames  = pivcore.data.frameCount(dataAll);
        end


        % ================================================================
        function up = defaultPrefs()
        %DEFAULTPREFS  Preferensi render default (velmag + GS + glyph, tema terang).
            up = struct('scalars',{{'velmag'}}, 'gsOn',true, 'claheOn',true, ...
                'adjOn',true, 'gsAlpha',0.5, 'glyphOn',true, 'glyphLW',1, ...
                'glyphSp',3, 'glyphColor',[0 0 0], 'glyphColorShear',[NaN NaN NaN], ...
                'tickPx',true, 'velUnit','pxframe', 'velMult',1, 'strainShow',true, ...
                'strainPos',[0.02 0.04], 'strainColor',[0 0 0], 'strainBg',[1 1 1], ...
                'showPSG',true, 'showColorbar',true, 'showTitle',true);
        end

    end


    methods (Static, Access = private)
        function s = enOf(tf)
            if tf, s = 'on'; else, s = 'off'; end
        end
        function v = scal(x)
            if isscalar(x) && isnumeric(x), v = double(x); else, v = NaN; end
        end
    end
end
