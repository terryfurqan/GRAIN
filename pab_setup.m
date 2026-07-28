function varargout = pab_setup(varargin)
%PAB_SETUP  Legacy alias of grain_setup (the project was renamed PAB -> GRAIN).
%   Kept so older scripts, notes and habits keep working. All arguments and
%   outputs are forwarded unchanged; there is no logic here.
[varargout{1:nargout}] = grain_setup(varargin{:});
end
