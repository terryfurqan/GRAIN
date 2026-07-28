function varargout = PABMASK2(varargin)
%PABMASK2  Legacy alias of GRAINMASK2 (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = GRAINMASK2(varargin{:});
end
