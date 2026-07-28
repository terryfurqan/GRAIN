classdef pivGeomIO
%PIVGEOMIO  Baca/tulis geometri (X0/X1/Lpos + strain) pada MAT PIV Step 2.
%
%   Geometri eksperimen tersimpan di MAT PIV sebagai variabel
%   `experiment_geometry` (struct dari pivanalyze.geom.computeGeometry):
%       .X0_cm .X1_cm .Lpos_cm .L0_cm .L1_cm .dL_cm
%       .strain_cumm .strain_cumm_pct .mode .valid .embedded_by .note
%   (lihat pivanalyze.io.embedTimeGeom). Editor MAT PIV mengubah TIGA nilai
%   mentah X0/X1/Lpos; saat menyimpan, strain DIHITUNG-ULANG otomatis lewat
%   pivanalyze.geom.computeGeometry agar konsisten (keputusan user).
%
%   API:
%     g  = pivanalyzemat.core.pivGeomIO.read(matFile)   % struct geom (default bila tak ada)
%     pivanalyzemat.core.pivGeomIO.write(matFile, X0, X1, Lpos [, prov])
%
%   write() me-RECOMPUTE geometri lalu save('-append') HANYA variabel geom
%   (tak menyentuh blob PIV/GS) -> aman & cepat untuk file besar.

    methods (Static)

        % ================================================================
        function g = read(matFile)
        %READ  Baca experiment_geometry dari MAT PIV (default kosong bila tak ada).
            g = pivanalyzemat.core.pivGeomIO.emptyGeom();
            if isempty(matFile) || ~ischar(matFile) || ~isfile(matFile), return; end
            try
                info = whos('-file', matFile);
            catch
                return;
            end
            if ~any(strcmp({info.name}, 'experiment_geometry')), return; end
            try
                S = load(matFile, 'experiment_geometry');
            catch
                return;
            end
            if isfield(S, 'experiment_geometry') && isstruct(S.experiment_geometry)
                g = pivanalyzemat.core.pivGeomIO.fillGeom(S.experiment_geometry);
            end
        end

        % ================================================================
        function g = write(matFile, X0, X1, Lpos, prov)
        %WRITE  Recompute geom dari X0/X1/Lpos -> save('-append') ke MAT PIV.
        %   Mengembalikan struct geom yang ditulis. Melempar bila gagal save.
            if nargin < 5 || isempty(prov), prov = 'matpiv_editor'; end
            if isempty(matFile) || ~isfile(matFile)
                error('pivanalyzemat:pivGeomIO:noFile', ...
                    'Berkas MAT PIV tidak ada:\n%s', char(matFile));
            end
            g = pivanalyze.geom.computeGeometry(X0, X1, Lpos, prov);

            % save('-append') variabel TUNGGAL -> tak memuat/menulis blob besar.
            experiment_geometry   = g;
            pivterry_geom_pack    = 'geom_strain_v1';
            time_geom_embedded_by = prov;
            save(matFile, 'experiment_geometry', 'pivterry_geom_pack', ...
                'time_geom_embedded_by', '-append');
        end

        % ================================================================
        function g = emptyGeom()
        %EMPTYGEOM  Struct geom kosong (X0/X1/Lpos = NaN).
            g = pivanalyze.geom.computeGeometry(NaN, NaN, NaN, 'matpiv_editor');
        end

        % ================================================================
        function g = fillGeom(in)
        %FILLGEOM  Normalisasi struct geom apa-pun -> bentuk lengkap & konsisten.
        %   Bila file lama hanya simpan X0/X1/Lpos, strain di-recompute.
            X0 = i_pick(in, {'X0_cm','X0','x0'}, NaN);
            X1 = i_pick(in, {'X1_cm','X1','x1'}, NaN);
            Lpos = i_pick(in, {'Lpos_cm','Lpos','L_pos','lpos'}, NaN);
            prov = 'matpiv_editor';
            if isfield(in,'embedded_by') && ~isempty(in.embedded_by)
                prov = char(in.embedded_by);
            end
            g = pivanalyze.geom.computeGeometry(X0, X1, Lpos, prov);
        end

    end
end

%% --------------------------------------------------------------------
function v = i_pick(s, fields, default)
%I_PICK  Ambil field pertama yang ada (skalar) dari struct s.
    v = default;
    if ~isstruct(s), return; end
    for k = 1:numel(fields)
        if isfield(s, fields{k})
            x = s.(fields{k});
            if ~isempty(x) && isnumeric(x)
                v = double(x(1)); return;
            end
        end
    end
end
