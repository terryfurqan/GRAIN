function cmap = turboFallback(n)
%TURBOFALLBACK  Fallback turbo() untuk MATLAB lama yang tidak punya turbo.
%   Port dari i_turboFallback (PIV_Viewer.m baris 2002-2019).

    base = [ ...
        0.18995 0.07176 0.23217;
        0.27376 0.31299 0.83918;
        0.21363 0.62083 0.95957;
        0.13986 0.85822 0.74631;
        0.41709 0.97562 0.45381;
        0.85060 0.93434 0.20330;
        0.99393 0.71763 0.20060;
        0.97442 0.39474 0.13231;
        0.81608 0.13343 0.05080;
        0.47960 0.01583 0.01055];
    t = linspace(0,1,size(base,1));
    tq = linspace(0,1,n);
    cmap = [interp1(t,base(:,1),tq)', ...
            interp1(t,base(:,2),tq)', ...
            interp1(t,base(:,3),tq)'];
end
