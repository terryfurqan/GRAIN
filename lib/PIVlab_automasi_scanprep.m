function exps = PIVlab_automasi_scanprep(parent_folder, varargin)
%PIVLAB_AUTOMASI_SCANPREP  Pindai folder induk untuk eksperimen keluaran PIVPrep.
%
%   exps = PIVlab_automasi_scanprep(parent_folder)
%   exps = PIVlab_automasi_scanprep(parent_folder, 'Name', Value, ...)
%
%   Berbeda dengan PIVlab_automasi_scan (yang mencari sembarang folder berisi
%   gambar), fungsi ini mencari folder bergaya keluaran PIVPrep, yaitu folder
%   EKSPERIMEN yang berisi DUA subfolder sekaligus: 'RAW' dan 'GS'
%   (lihat +pivprep/+io/writeOutputs.m). Untuk tiap eksperimen:
%       - PIV dijalankan pada subfolder RAW (resolusi penuh).
%       - Subfolder GS dipakai sebagai latar yang disematkan ke .mat hasil.
%
%   Begitu sebuah folder dikenali sebagai eksperimen, isinya TIDAK ditelusuri
%   lebih dalam (RAW/GS/EXIF tidak dianggap eksperimen terpisah).
%
%   Mengembalikan struct-array 'exps' (satu elemen per eksperimen) dengan field
%   yang langsung dipakai PIVlab_automasi_batch_V2 / GUI:
%       .path     - path subfolder RAW  (INPUT analisis PIV)
%       .gsdir    - path subfolder GS   (latar yang disematkan)
%       .expdir   - path folder eksperimen (induk RAW & GS)
%       .relpath  - path relatif terhadap folder induk (untuk tampilan)
%       .name     - nama folder eksperimen -> nama dasar file .mat
%       .count    - jumlah gambar di RAW
%       .gscount  - jumlah gambar di GS
%       .suffix   - pola ekstensi RAW terdeteksi (mis. '*.jpg')
%       .npairs   - perkiraan jumlah pasangan frame
%       .outname  - nama keluaran (default = .name)
%
%   OPSI
%     'Recursive'  : true (default) telusuri subfolder bertingkat.
%     'MinImages'  : jumlah gambar RAW minimum agar dianggap valid (>=2).
%     'Suffix'     : paksa pola ekstensi RAW (mis. '*.tif'); default auto.
%     'Sequencing' : 'consecutive' (default) atau 'pairs' (untuk hitung npairs).
%     'RawName'    : nama subfolder RAW. Default 'RAW'.
%     'GsName'     : nama subfolder GS.  Default 'GS'.
%     'GsPattern'  : pola berkas GS untuk menghitung #gambar.
%                    Default '*.jpg;*.jpeg;*.tif;*.tiff;*.png;*.bmp'.
%
%   Lihat juga: PIVlab_automasi_batch_V2, PIVlab_automasi_batch_GUI_V2,
%               PIVlab_automasi_scan

ip = inputParser;
ip.addRequired('parent_folder', @(x) ischar(x) || isstring(x));
ip.addParameter('Recursive',  true, @(x) islogical(x) || isnumeric(x));
ip.addParameter('MinImages',  2,    @(x) isnumeric(x) && isscalar(x) && x >= 2);
ip.addParameter('Suffix',     '',   @(x) ischar(x) || isstring(x));
ip.addParameter('Sequencing', 'consecutive', @(x) any(strcmpi(x, {'consecutive','pairs'})));
ip.addParameter('RawName',    'RAW', @(x) ischar(x) || isstring(x));
ip.addParameter('GsName',     'GS',  @(x) ischar(x) || isstring(x));
ip.addParameter('GsPattern',  '*.jpg;*.jpeg;*.tif;*.tiff;*.png;*.bmp', @(x) ischar(x) || isstring(x));
ip.parse(parent_folder, varargin{:});
opt = ip.Results;

parent_folder = char(parent_folder);
if ~isfolder(parent_folder)
	error('PIVlab_automasi_scanprep:noFolder', ...
		'Folder induk tidak ditemukan:\n%s', parent_folder);
end

forcedSuffix = char(opt.Suffix);
if ~isempty(forcedSuffix) && ~startsWith(forcedSuffix, '*')
	if ~startsWith(forcedSuffix, '.'); forcedSuffix = ['.' forcedSuffix]; end
	forcedSuffix = ['*' forcedSuffix];
end
rawName   = char(opt.RawName);
gsName    = char(opt.GsName);
gsPattern = char(opt.GsPattern);

exps = empty_exps();

% Telusuri direktori. Folder induk sendiri ikut diperiksa sebagai kandidat
% (mis. bila pengguna langsung memilih satu folder eksperimen).
dirs = list_dirs(parent_folder, logical(opt.Recursive), rawName, gsName);
pfx  = [parent_folder filesep];

for k = 1:numel(dirs)
	D = dirs{k};
	rawdir = i_subfolder(D, rawName);
	gsdir  = i_subfolder(D, gsName);
	if isempty(rawdir) || isempty(gsdir); continue; end   % bukan eksperimen

	[sfx, cnt] = PIVlab_automasi_countimg(rawdir, forcedSuffix);
	if cnt < opt.MinImages; continue; end
	gscnt = i_countPattern(gsdir, gsPattern);

	if strcmpi(opt.Sequencing, 'pairs')
		npairs = floor(cnt / 2);
	else
		npairs = cnt - 1;
	end

	[~, nm] = fileparts(regexprep(D, '[\\/]+$', ''));
	if strcmp(D, parent_folder)
		rel = [nm ' (folder induk)'];
	elseif startsWith(D, pfx)
		rel = extractAfter(D, pfx);
	else
		rel = D;
	end

	exps(end+1) = struct('path', rawdir, 'gsdir', gsdir, 'expdir', D, ...
		'relpath', rel, 'name', nm, 'count', cnt, 'gscount', gscnt, ...
		'suffix', sfx, 'npairs', npairs, 'outname', nm); %#ok<AGROW>
end

if ~isempty(exps)
	[~, ord] = sort({exps.expdir});
	exps = exps(ord);
end
end

%% ----------------------------------------------------------- subfungsi
function s = empty_exps()
s = struct('path', {}, 'gsdir', {}, 'expdir', {}, 'relpath', {}, 'name', {}, ...
	'count', {}, 'gscount', {}, 'suffix', {}, 'npairs', {}, 'outname', {});
end

function dlist = list_dirs(root, recursive, rawName, gsName)
% Daftar direktori (root + turunan bila recursive). Bila sebuah direktori
% adalah eksperimen (punya RAW & GS), isinya TIDAK ditelusuri lebih dalam.
dlist = {root};
if ~isempty(i_subfolder(root, rawName)) && ~isempty(i_subfolder(root, gsName))
	return;   % root adalah eksperimen -> jangan turun ke RAW/GS/EXIF
end
items = dir(root);
for k = 1:numel(items)
	nm = items(k).name;
	if items(k).isdir && ~strcmp(nm, '.') && ~strcmp(nm, '..') && ~startsWith(nm, '.')
		sub = fullfile(root, nm);
		if recursive
			dlist = [dlist; list_dirs(sub, true, rawName, gsName)]; %#ok<AGROW>
		else
			dlist = [dlist; {sub}];                                 %#ok<AGROW>
		end
	end
end
end

function p = i_subfolder(parent, name)
% Cari subfolder bernama 'name' (cocok TANPA peduli huruf besar/kecil).
p = '';
exact = fullfile(parent, name);
if isfolder(exact); p = exact; return; end
items = dir(parent);
for k = 1:numel(items)
	if items(k).isdir && strcmpi(items(k).name, name) ...
			&& ~strcmp(items(k).name, '.') && ~strcmp(items(k).name, '..')
		p = fullfile(parent, items(k).name);
		return;
	end
end
end

function n = i_countPattern(folder, patternStr)
% Hitung berkas (unik) yang cocok daftar pola (';' / ',') di folder.
n = 0;
if isempty(folder) || ~isfolder(folder); return; end
if isempty(patternStr); patternStr = '*.jpg;*.jpeg;*.tif;*.tiff;*.png;*.bmp'; end
patternStr = strrep(patternStr, ',', ';');
parts = strsplit(patternStr, ';');
seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
for i = 1:numel(parts)
	pp = strtrim(parts{i});
	if isempty(pp); continue; end
	d = dir(fullfile(folder, pp));
	for j = 1:numel(d)
		if ~d(j).isdir && ~isKey(seen, d(j).name)
			seen(d(j).name) = true;
		end
	end
end
n = double(seen.Count);
end
