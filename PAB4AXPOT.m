function varargout = PAB4AXPOT(varargin)
%PAB4AXPOT  Legacy alias of GRAIN4AXPOT (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAIN4AXPOT(varargin{:});
end
