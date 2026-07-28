function folders = PIVlab_automasi_scan(parent_folder, varargin)
%PIVLAB_AUTOMASI_SCAN  Pindai folder induk untuk mencari subfolder berisi
%   sequence gambar (untuk pemrosesan batch).
%
%   folders = PIVlab_automasi_scan(parent_folder)
%   folders = PIVlab_automasi_scan(parent_folder, 'Name', Value, ...)
%
%   Mengembalikan struct-array 'folders' (satu elemen per folder yang berisi
%   minimal MinImages gambar) dengan field:
%       .path     - path lengkap folder
%       .relpath  - path relatif terhadap folder induk (untuk tampilan)
%       .name     - nama folder (basis) -> dipakai sebagai nama file .mat
%       .count    - jumlah file gambar di dalam folder
%       .suffix   - pola ekstensi terdeteksi (mis. '*.tif')
%       .npairs   - perkiraan jumlah pasangan frame
%
%   OPSI
%     'Recursive'  : true (default) menelusuri seluruh subfolder bertingkat;
%                    false hanya subfolder langsung + folder induk.
%     'MinImages'  : jumlah gambar minimum agar folder dianggap valid (>=2).
%     'Suffix'     : paksa pola ekstensi (mis. '*.tif'); default deteksi auto.
%     'Sequencing' : 'consecutive' (default) atau 'pairs' (untuk hitung npairs).
%
%   Lihat juga: PIVlab_automasi_batch, PIVlab_automasi

ip = inputParser;
ip.addRequired('parent_folder', @(x) ischar(x) || isstring(x));
ip.addParameter('Recursive',  true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('MinImages',  2,    @(x) isnumeric(x) && isscalar(x) && x >= 2);
ip.addParameter('Suffix',     '',   @(x) ischar(x) || isstring(x));
ip.addParameter('Sequencing', 'consecutive', @(x) any(strcmpi(x, {'consecutive','pairs'})));
ip.parse(parent_folder, varargin{:});
opt = ip.Results;

parent_folder = char(parent_folder);
if ~isfolder(parent_folder)
	error('PIVlab_automasi_scan:noFolder', ...
		'Folder induk tidak ditemukan:\n%s', parent_folder);
end

forcedSuffix = char(opt.Suffix);
if ~isempty(forcedSuffix) && ~startsWith(forcedSuffix, '*')
	if ~startsWith(forcedSuffix, '.'); forcedSuffix = ['.' forcedSuffix]; end
	forcedSuffix = ['*' forcedSuffix];
end

% kumpulkan seluruh direktori kandidat (termasuk folder induk itu sendiri)
allDirs = list_dirs(parent_folder, logical(opt.Recursive));

folders = struct('path', {}, 'relpath', {}, 'name', {}, ...
	'count', {}, 'suffix', {}, 'npairs', {}, 'outname', {});
pfx = [parent_folder filesep];
for k = 1:numel(allDirs)
	[sfx, cnt] = PIVlab_automasi_countimg(allDirs{k}, forcedSuffix);
	if cnt >= opt.MinImages
		if strcmpi(opt.Sequencing, 'pairs')
			npairs = floor(cnt / 2);
		else
			npairs = cnt - 1;
		end
		[~, nm] = fileparts(allDirs{k});
		if strcmp(allDirs{k}, parent_folder)
			rel = [nm ' (folder induk)'];
		elseif startsWith(allDirs{k}, pfx)
			rel = extractAfter(allDirs{k}, pfx);
		else
			rel = allDirs{k};
		end
		folders(end+1) = struct('path', allDirs{k}, 'relpath', rel, ...
			'name', nm, 'count', cnt, 'suffix', sfx, 'npairs', npairs, ...
			'outname', nm); %#ok<AGROW>
	end
end

% urutkan berdasarkan path agar tampilan konsisten
if ~isempty(folders)
	[~, ord] = sort({folders.path});
	folders = folders(ord);
end
end

%% ----------------------------------------------------------- subfungsi
function dlist = list_dirs(root, recursive)
% daftar direktori (root + turunannya bila recursive), lewati folder tersembunyi
dlist = {root};
items = dir(root);
for k = 1:numel(items)
	nm = items(k).name;
	if items(k).isdir && ~strcmp(nm, '.') && ~strcmp(nm, '..') && ~startsWith(nm, '.')
		sub = fullfile(root, nm);
		if recursive
			dlist = [dlist; list_dirs(sub, true)]; %#ok<AGROW>
		else
			dlist = [dlist; {sub}];                %#ok<AGROW>
		end
	end
end
end
