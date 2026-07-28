function [U, V] = pickAnyVel(data, k)
%PICKANYVEL  Pilih bidang kecepatan apa pun yang tersedia (fallback).
%   Port dari i_pickAnyVel (PIV_Viewer.m baris 1930-1939).

    U = pivcore.data.safeFrame(data.u_component, k);
    V = pivcore.data.safeFrame(data.v_component, k);
    if isempty(U), U = pivcore.data.safeFrame(data.u_smoothed, k); end
    if isempty(V), V = pivcore.data.safeFrame(data.v_smoothed, k); end
    if isempty(U), U = pivcore.data.safeFrame(data.u_filtered, k); end
    if isempty(V), V = pivcore.data.safeFrame(data.v_filtered, k); end
    if isempty(U), U = pivcore.data.safeFrame(data.u_original, k); end
    if isempty(V), V = pivcore.data.safeFrame(data.v_original, k); end
end
