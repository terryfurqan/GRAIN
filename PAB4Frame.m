function varargout = PAB4Frame(varargin)
%PAB4FRAME  Legacy alias of GRAIN4Frame (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAIN4Frame(varargin{:});
end
