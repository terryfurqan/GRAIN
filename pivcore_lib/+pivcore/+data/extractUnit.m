function txt = extractUnit(unitsStr, kind)
%EXTRACTUNIT  Parsing satuan dari string units PIVLAB.
%   Port dari i_extractUnit (PIV_Viewer.m baris 2064-2077).

    txt = '';
    if isempty(unitsStr), return; end
    tok = regexp(unitsStr, '\[([^\]]+)\]', 'tokens');
    if numel(tok) < 2, return; end
    spaceUnit = tok{1}{1};
    timeUnit  = tok{2}{1};
    switch kind
        case 'spatial',  txt = sprintf('[%s]', spaceUnit);
        case 'velocity', txt = sprintf('[%s/%s]', spaceUnit, timeUnit);
        case 'rate',     txt = sprintf('[1/%s]', timeUnit);
        otherwise,       txt = sprintf('[%s]', spaceUnit);
    end
end
