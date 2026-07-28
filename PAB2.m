function varargout = PAB2(varargin)
%PAB2  Legacy alias of GRAIN2 (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAIN2(varargin{:});
end
