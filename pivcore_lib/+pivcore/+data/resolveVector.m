function [U, V] = resolveVector(data, sel, k)
%RESOLVEVECTOR  Ambil bidang vektor sesuai pilihan pada bingkai k.
%   Port dari i_resolveVector (PIV_Viewer.m baris 1957-1973).

    U = []; V = [];
    switch sel
        case 'u_component / v_component (aktif)'
            U = pivcore.data.safeFrame(data.u_component, k);
            V = pivcore.data.safeFrame(data.v_component, k);
        case 'u_smoothed / v_smoothed'
            U = pivcore.data.safeFrame(data.u_smoothed, k);
            V = pivcore.data.safeFrame(data.v_smoothed, k);
        case 'u_filtered / v_filtered'
            U = pivcore.data.safeFrame(data.u_filtered, k);
            V = pivcore.data.safeFrame(data.v_filtered, k);
        case 'u_original / v_original'
            U = pivcore.data.safeFrame(data.u_original, k);
            V = pivcore.data.safeFrame(data.v_original, k);
    end
end
