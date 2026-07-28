function varargout = PAB1(varargin)
%PAB1  Legacy alias of GRAIN1 (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAIN1(varargin{:});
end
