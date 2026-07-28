function varargout = PAB3(varargin)
%PAB3  Legacy alias of GRAIN3 (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAIN3(varargin{:});
end
