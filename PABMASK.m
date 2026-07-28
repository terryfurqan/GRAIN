function varargout = PABMASK(varargin)
%PABMASK  Legacy alias of GRAINMASK (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAINMASK(varargin{:});
end
