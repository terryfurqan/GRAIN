function names = PIVlab_automasi_uniquenames(destdirs, basenames)
%PIVLAB_AUTOMASI_UNIQUENAMES  Pastikan nama file output tidak bentrok.
%
%   names = PIVlab_automasi_uniquenames(destdirs, basenames)
%
%   destdirs  : cell-array folder tujuan tiap output (tempat .mat disimpan)
%   basenames : cell-array nama dasar yang diinginkan (tanpa ekstensi)
%
%   Mengembalikan 'names' (cell-array) berisi nama dasar unik, sehingga
%   fullfile(destdir, [name '.mat']) untuk seluruh entri berbeda satu sama
%   lain. Nama yang bentrok diberi akhiran _2, _3, dst.
%
%   Contoh: dua folder berbeda dengan nama 'run' yang disimpan ke folder
%   output yang sama akan menghasilkan 'run' dan 'run_2'.

n = numel(basenames);
names = cell(1, n);
taken = strings(0, 1);   % daftar path (lowercase) yang sudah dipakai

for i = 1:n
	base = char(basenames{i});
	base = strtrim(base);
	if isempty(base); base = 'output'; end

	cand = base;
	k = 1;
	key = lower(fullfile(destdirs{i}, [cand '.mat']));
	while any(taken == string(key))
		k = k + 1;
		cand = sprintf('%s_%d', base, k);
		key  = lower(fullfile(destdirs{i}, [cand '.mat']));
	end
	taken(end+1, 1) = string(key); %#ok<AGROW>
	names{i} = cand;
end
end
