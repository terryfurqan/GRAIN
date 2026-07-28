function varargout = PAB4(varargin)
%PAB4  Legacy alias of GRAIN4 (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAIN4(varargin{:});
end
