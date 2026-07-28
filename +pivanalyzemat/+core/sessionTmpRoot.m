function root = sessionTmpRoot()
%SESSIONTMPROOT  Folder induk sementara (per-sesi MATLAB) untuk bongkaran .mat.
%
%   root = pivanalyzemat.core.sessionTmpRoot()
%
%   Mengembalikan SATU folder stabil sepanjang sesi MATLAB di bawah tempdir,
%   tempat pivanalyzemat.core.unpackMat menaruh folder eksperimen hasil bongkar
%   blob .mat. Folder dibuat sekali (persistent) dan dipakai ulang; bersihkan
%   dengan pivanalyzemat.core.cleanupTmp saat GUI ditutup.

	persistent ROOT
	if ~isempty(ROOT) && isfolder(ROOT)
		root = ROOT; return;
	end
	base = tempdir;
	% nama unik per-sesi tanpa Math.random (terlarang di sebagian harness):
	% pakai feature('getpid') + tic untuk keunikan praktis.
	try, pid = feature('getpid'); catch, pid = 0; end
	tag = sprintf('%d_%d', pid, round(mod(now*8.64e7, 1e9))); %#ok<TNOW1>
	ROOT = fullfile(base, sprintf('grain_step2_unpack_%s', tag));
	if ~isfolder(ROOT); mkdir(ROOT); end
	root = ROOT;
end
