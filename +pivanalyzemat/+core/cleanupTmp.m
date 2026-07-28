function cleanupTmp()
%CLEANUPTMP  Hapus seluruh folder bongkaran sementara sesi ini.
%
%   pivanalyzemat.core.cleanupTmp()
%
%   Dipanggil saat GUI Step 2 ditutup. Menghapus folder induk sementara
%   (pivanalyzemat.core.sessionTmpRoot) berikut semua bongkaran .mat di dalamnya.
%   Aman dipanggil berkali-kali (no-op bila folder sudah hilang).

	try
		root = pivanalyzemat.core.sessionTmpRoot();
		if isfolder(root)
			rmdir(root, 's');
		end
	catch
	end
end
