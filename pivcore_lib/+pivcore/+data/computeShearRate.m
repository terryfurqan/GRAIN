function Z = computeShearRate(data, k, varargin)
%COMPUTESHEARRATE  Hitung shear strain rate dari medan kecepatan u, v.
%
%   Z = pivcore.data.computeShearRate(data, k)
%   Z = pivcore.data.computeShearRate(data, k, 'mode','engineering')
%   Z = pivcore.data.computeShearRate(data, k, 'mode','magnitude')
%   Z = pivcore.data.computeShearRate(data, k, 'mode',M, ...
%           'vectorSource', vsel)
%
%   Bingkai k pada dataset 'data' diambil melalui pivcore.data.safeFrame
%   (untuk x, y) dan pivcore.data.resolveVector / pickAnyVel (untuk u, v).
%
%   Argumen Name-Value:
%     'mode'         'engineering' (default, bertanda) atau 'magnitude'
%                    (selalu >= 0).
%     'vectorSource' string sumber vektor sesuai pivcore.data.listVectors,
%                    contoh 'u_smoothed / v_smoothed'. Jika kosong / tidak
%                    diberikan: fallback ke pivcore.data.pickAnyVel
%                    (perilaku lama).
%
%   Konvensi Matematika
%   -------------------
%   Tensor laju regangan simetris untuk aliran 2D:
%
%       S_xx = du/dx,
%       S_yy = dv/dy,
%       S_xy = 0.5 * ( du/dy + dv/dx ).
%
%   Definisi yang dipakai:
%
%     'engineering' (kompatibel dengan PIVLAB / PIV_Viewer asli):
%         Z = du/dy + dv/dx          ( = 2 * S_xy, bertanda )
%
%     'magnitude'   (true total shear intensity, invariant rotasi):
%         Z = sqrt( 2*S_ij*S_ij )
%           = sqrt( 2*(du/dx)^2 + 2*(dv/dy)^2 + (du/dy + dv/dx)^2 ).
%
%   Mode 'magnitude' adalah ukuran skalar invariant terhadap rotasi sumbu,
%   identik dengan equivalent shear rate yang umum di literatur rheologi /
%   CFD (mis. Bird-Stewart-Lightfoot). Mode 'engineering' dipertahankan
%   sebagai default untuk backward compatibility dengan modul lama yang
%   memanggil computeShearRate(data, k) tanpa argumen tambahan.

    Z = [];

    p = inputParser;
    p.FunctionName = 'pivcore.data.computeShearRate';
    addParameter(p, 'mode',         'engineering', @(s) ischar(s) || isstring(s));
    addParameter(p, 'vectorSource', '',            @(s) ischar(s) || isstring(s));
    parse(p, varargin{:});
    mode = lower(char(p.Results.mode));
    vsel = char(p.Results.vectorSource);

    % --- Ambil U, V sesuai sumber vektor yang diminta (bila ada) ---
    U = []; V = [];
    if ~isempty(vsel)
        try
            [U, V] = pivcore.data.resolveVector(data, vsel, k);
        catch
            U = []; V = [];
        end
    end
    if isempty(U) || isempty(V)
        [U, V] = pivcore.data.pickAnyVel(data, k);
    end

    x = pivcore.data.safeFrame(data.x, k);
    y = pivcore.data.safeFrame(data.y, k);

    if isempty(U) || isempty(V) || isempty(x) || isempty(y), return; end
    if ~isequal(size(U), size(x)) || ~isequal(size(V), size(x)), return; end

    % Spasi grid (PIV grid uniform): pakai mean(diff(...)) baris/kolom
    dx = mean(diff(x(1, :)), 'omitnan');
    dy = mean(diff(y(:, 1)), 'omitnan');
    if ~isfinite(dx) || dx == 0, dx = 1; end
    if ~isfinite(dy) || dy == 0, dy = 1; end

    % gradient(F, hx, hy) -> [dF/dx, dF/dy] dengan hx spasi kolom, hy spasi baris
    [dudx, dudy] = gradient(U, dx, dy);
    [dvdx, dvdy] = gradient(V, dx, dy);

    switch mode
        case 'engineering'
            % du/dy + dv/dx (kompatibel PIVLAB)
            Z = dudy + dvdx;

        case 'magnitude'
            % sqrt( 2 * S_ij S_ij )
            %   = sqrt( 2*(du/dx)^2 + 2*(dv/dy)^2 + (du/dy + dv/dx)^2 )
            Z = sqrt( 2*dudx.^2 + 2*dvdy.^2 + (dudy + dvdx).^2 );

        otherwise
            error('pivcore:computeShearRate:badMode', ...
                  'mode harus ''engineering'' atau ''magnitude'' (diberikan: ''%s'').', mode);
    end
end
