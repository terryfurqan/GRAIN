function [Z, label] = resolveScalar(data, sel, k)
%RESOLVESCALAR  Ambil bidang skalar 'sel' pada bingkai k.
%   Port dari i_resolveScalar (PIV_Viewer.m baris 1890-1928).
%
%   PERUBAHAN versi ini:
%     Menambahkan case 'shear_rate_magnitude' (= sqrt(2 S_ij S_ij), invariant
%     rotasi) yang diproduksi oleh tabMain.computeShearAllFrames pada mode
%     'magnitude'. Tidak ada fallback komputasi otomatis: bila field
%     belum ada, Z dikembalikan kosong (user harus klik tombol "Hitung
%     shear rate" di tab Utama untuk membuatnya).
%
%     Case 'shear_rate' lama tetap memiliki fallback ke
%     pivcore.data.computeShearRate (mode default 'engineering' agar
%     kompatibel mundur).

    Z = []; label = sel;
    switch sel
        case 'velocity_magnitude'
            Z = pivcore.data.safeFrame(data.velocity_magnitude, k);
            if isempty(Z)
                [U,V] = pivcore.data.pickAnyVel(data, k);
                if ~isempty(U) && ~isempty(V), Z = hypot(U,V); end
            end
            label = sprintf('|V| %s', pivcore.data.extractUnit(data.units,'velocity'));
        case 'vorticity'
            Z = pivcore.data.safeFrame(data.vorticity, k);
            label = sprintf('vortisitas %s', pivcore.data.extractUnit(data.units,'rate'));
        case 'divergence'
            Z = pivcore.data.safeFrame(data.divergence, k);
            label = sprintf('divergensi %s', pivcore.data.extractUnit(data.units,'rate'));
        case 'shear_rate'
            Z = pivcore.data.safeFrame(data.shear_rate, k);
            if isempty(Z), Z = pivcore.data.computeShearRate(data, k); end
            label = sprintf('shear strain rate %s', pivcore.data.extractUnit(data.units,'rate'));
        case 'shear_rate_magnitude'
            if isfield(data, 'shear_rate_magnitude')
                Z = pivcore.data.safeFrame(data.shear_rate_magnitude, k);
            end
            label = sprintf('|shear rate| %s', pivcore.data.extractUnit(data.units,'rate'));
        case 'strain_rate'
            Z = pivcore.data.safeFrame(data.strain_rate, k);
            label = sprintf('laju regangan %s', pivcore.data.extractUnit(data.units,'rate'));
        case 'q_criterion'
            Z = pivcore.data.safeFrame(data.q_criterion, k);  label = 'kriteria-Q';
        case 'LIC'
            Z = pivcore.data.safeFrame(data.LIC, k);          label = 'LIC';
        case 'vectorangle'
            Z = pivcore.data.safeFrame(data.vectorangle, k);  label = 'sudut vektor (rad)';
        case 'u_component'
            Z = pivcore.data.safeFrame(data.u_component, k);
            label = sprintf('u %s', pivcore.data.extractUnit(data.units,'velocity'));
        case 'v_component'
            Z = pivcore.data.safeFrame(data.v_component, k);
            label = sprintf('v %s', pivcore.data.extractUnit(data.units,'velocity'));
        case 'u_smoothed'
            % Vx komponen ter-smooth. velocity_magnitude PIVlab = hypot(u_smoothed,
            % v_smoothed) PERSIS (u_component sering kosong), jadi u_smoothed/v_smoothed
            % adalah komponen yg KONSISTEN dgn |V| utk dekomposisi Vx/Vy.
            Z = pivcore.data.safeFrame(data.u_smoothed, k);
            label = sprintf('u %s', pivcore.data.extractUnit(data.units,'velocity'));
        case 'v_smoothed'
            Z = pivcore.data.safeFrame(data.v_smoothed, k);
            label = sprintf('v %s', pivcore.data.extractUnit(data.units,'velocity'));
        case 'u_filtered'
            Z = pivcore.data.safeFrame(data.u_filtered, k);
            label = sprintf('u %s', pivcore.data.extractUnit(data.units,'velocity'));
        case 'v_filtered'
            Z = pivcore.data.safeFrame(data.v_filtered, k);
            label = sprintf('v %s', pivcore.data.extractUnit(data.units,'velocity'));
        case '(tidak ada)'
            Z = []; label = '';
    end
end
