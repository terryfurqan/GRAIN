function varargout = PAB6_temp(varargin)
%PAB6_TEMP  Legacy alias of GRAIN6_temp (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAIN6_temp(varargin{:});
end
