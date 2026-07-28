function varargout = PABEXPORT(varargin)
%PABEXPORT  Legacy alias of GRAINEXPORT (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAINEXPORT(varargin{:});
end
