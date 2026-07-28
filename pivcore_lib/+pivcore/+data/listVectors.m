function lst = listVectors(data)
%LISTVECTORS  Daftar sumber vektor yang tersedia pada dataset.
%   Port dari i_listAvailableVectors (PIV_Viewer.m baris 2046-2061).

    lst = {};
    if ~isempty(data.u_component) && ~isempty(data.v_component)
        lst{end+1} = 'u_component / v_component (aktif)'; %#ok<AGROW>
    end
    if ~isempty(data.u_smoothed) && ~isempty(data.v_smoothed)
        lst{end+1} = 'u_smoothed / v_smoothed'; %#ok<AGROW>
    end
    if ~isempty(data.u_filtered) && ~isempty(data.v_filtered)
        lst{end+1} = 'u_filtered / v_filtered'; %#ok<AGROW>
    end
    if ~isempty(data.u_original) && ~isempty(data.v_original)
        lst{end+1} = 'u_original / v_original'; %#ok<AGROW>
    end
    if isempty(lst), lst = {'(tidak ada)'}; end
end
