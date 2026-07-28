function [suffix, count] = PIVlab_automasi_countimg(folder, forcedSuffix)
%PIVLAB_AUTOMASI_COUNTIMG  Hitung jumlah gambar di sebuah folder.
%
%   [suffix, count] = PIVlab_automasi_countimg(folder)
%   [suffix, count] = PIVlab_automasi_countimg(folder, forcedSuffix)
%
%   Tanpa forcedSuffix, fungsi memeriksa ekstensi gambar umum
%   (tif/tiff/jpg/jpeg/png/bmp) dan memilih yang jumlah filenya terbanyak.
%   Mengembalikan pola ekstensi terpilih (mis. '*.tif') dan jumlah filenya.

exts = {'*.tif', '*.tiff', '*.jpg', '*.jpeg', '*.png', '*.bmp'};

if nargin >= 2 && ~isempty(forcedSuffix)
	forcedSuffix = char(forcedSuffix);
	if ~startsWith(forcedSuffix, '*')
		if ~startsWith(forcedSuffix, '.'); forcedSuffix = ['.' forcedSuffix]; end
		forcedSuffix = ['*' forcedSuffix];
	end
	d = dir(fullfile(folder, forcedSuffix));
	count  = sum(~[d.isdir]);
	suffix = forcedSuffix;
	return;
end

counts = zeros(numel(exts), 1);
for k = 1:numel(exts)
	d = dir(fullfile(folder, exts{k}));
	if ~isempty(d)
		counts(k) = sum(~[d.isdir]);
	end
end
[count, idx] = max(counts);
suffix = exts{idx};
end
