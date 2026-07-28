function lst = listScalars(data)
%LISTSCALARS  Daftar bidang skalar yang tersedia pada dataset.
%   Port dari i_listAvailableScalars (PIV_Viewer.m baris 2022-2044).
%
%   PERUBAHAN versi ini:
%     Menambahkan kandidat 'shear_rate_magnitude' yang dihasilkan oleh
%     tabMain.computeShearAllFrames pada mode 'magnitude'. Jika field
%     tersebut ada dan tidak kosong, ia muncul di daftar; tetapi TIDAK
%     ditambahkan otomatis (berbeda dengan 'shear_rate' lama yang
%     ditambahkan otomatis sebagai virtual scalar). Ini agar magnitude
%     hanya muncul setelah benar-benar dihitung oleh user.

    candidates = { 'velocity_magnitude','vorticity','divergence', ...
        'shear_rate','shear_rate_magnitude','strain_rate','q_criterion','LIC','vectorangle', ...
        'u_component','v_component'};
    lst = {};
    for k = 1:numel(candidates)
        name = candidates{k};
        if isfield(data, name) && ~isempty(data.(name))
            v = data.(name);
            % Untuk cell array, anggap "ada" bila setidaknya satu sel non-empty.
            isOk = false;
            if iscell(v)
                isOk = any(~cellfun(@isempty, v));
            else
                isOk = ~isempty(v);
            end
            if isOk
                lst{end+1} = name; %#ok<AGROW>
            end
        end
    end

    % --- Virtual scalars yang selalu bisa dihitung dari u, v ---
    if ~ismember('velocity_magnitude', lst) && ...
            (i_anyNonEmpty(data, 'u_component') || i_anyNonEmpty(data, 'u_smoothed') || ...
             i_anyNonEmpty(data, 'u_filtered') || i_anyNonEmpty(data, 'u_original'))
        lst = [{'velocity_magnitude'}, lst];
    end
    if ~ismember('shear_rate', lst) && ...
            (i_anyNonEmpty(data, 'u_component') || i_anyNonEmpty(data, 'u_smoothed') || ...
             i_anyNonEmpty(data, 'u_filtered') || i_anyNonEmpty(data, 'u_original'))
        lst{end+1} = 'shear_rate'; %#ok<AGROW>
    end

    if isempty(lst), lst = {'(tidak ada)'}; end
end


function tf = i_anyNonEmpty(data, fieldName)
    tf = false;
    if ~isfield(data, fieldName), return; end
    v = data.(fieldName);
    if iscell(v)
        tf = any(~cellfun(@isempty, v));
    else
        tf = ~isempty(v);
    end
end
