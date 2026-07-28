function varargout = PAB0(varargin)
%PAB0  Legacy alias of GRAIN0 (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAIN0(varargin{:});
end
