function root = rootUnpackRoot(rootFolder)
%ROOTUNPACKROOT  Folder induk bongkaran .mat DI DALAM folder root (bukan tempdir).
%
%   root = pivanalyzemat.core.rootUnpackRoot(rootFolder)
%
%   PAB_step_2 membongkar tiap .mat ke folder sementara. Berbeda dengan
%   pivanalyzemat.core.sessionTmpRoot (yang memakai tempdir per-sesi), fungsi ini
%   menempatkan folder induk bongkaran LANGSUNG di bawah folder root tempat .mat
%   dipindai, dengan NAMA YANG DI-HASH dari path root tsb supaya:
%     - stabil lintas-sesi (root sama -> folder unpack sama, bisa dipakai ulang),
%     - tidak bentrok bila beberapa root berbeda kebetulan sebaris,
%     - mudah dikenali sbg artefak tool (prefiks '.pabsa2_unpack_').
%
%       <rootFolder>/.pabsa2_unpack_<hash8>/<name>_<hash8>/RAW|GS|EXIF
%
%   Folder ini bersifat TEMPORER: bongkaran dibuat on-demand (menjelang QPIV /
%   batch satu eksperimen) lalu DIHAPUS segera setelah pekerjaan selesai, dan
%   sisa folder kerja dibersihkan saat GUI Step 2 ditutup. Tidak ada pembengkakan
%   di muka; hanya .mat hasil PIV (PIV_<tgl>/) yang merupakan keluaran final.
%
%   Lihat juga: pivanalyzemat.core.unpackMat, pivanalyzemat.core.sessionTmpRoot

	if nargin < 1 || isempty(rootFolder) || ~isfolder(rootFolder)
		% root belum valid -> jatuh ke tempdir per-sesi (perilaku lama).
		root = pivanalyzemat.core.sessionTmpRoot();
		return;
	end
	canon = i_canon(rootFolder);
	tag   = i_hash8(canon);
	root  = fullfile(rootFolder, sprintf('.pabsa2_unpack_%s', tag));
	if ~isfolder(root); mkdir(root); end
end

%% ===================================================================
function s = i_canon(p)
s = char(p);
try, s = char(java.io.File(s).getCanonicalPath()); catch; end
end

function h = i_hash8(str)
persistent md
if isempty(md); md = java.security.MessageDigest.getInstance('MD5'); end
md.reset(); md.update(uint8(char(str)));
digest = typecast(md.digest(), 'uint8');
hx = lower(reshape(dec2hex(digest, 2).', 1, []));
h = hx(1:8);
end
