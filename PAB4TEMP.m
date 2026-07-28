function varargout = PAB4TEMP(varargin)
%PAB4TEMP  Legacy alias of GRAIN4TEMP (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAIN4TEMP(varargin{:});
end
