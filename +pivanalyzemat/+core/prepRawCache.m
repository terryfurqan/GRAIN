function raw = prepRawCache(matPath, op)
%PREPRAWCACHE  Cache RAM per-sesi utk `prep.raw` (blobs+index+names+ext) MAT PREP.
%
%   raw = pivanalyzemat.core.prepRawCache(matPath)        % ambil (load bila perlu)
%   pivanalyzemat.core.prepRawCache('', 'clear')          % kosongkan cache
%
%   TUJUAN. Setelah keputusan "jangan tulis ulang MAT PREP" (resep masking di
%   sidecar, blob RAW dibiarkan `-v7`), decode 1 frame butuh load `prep` (~4 s
%   utk file 1,4 GB). Supaya pembacaan frame BERIKUTNYA (slider, awal/akhir,
%   pindah exp lalu balik) INSTAN tanpa menyentuh disk lagi, `prep.raw` di-cache
%   di RAM. Load pertama per file lambat; sisanya diambil dari RAM.
%
%   LRU kecil (kapasitas 2 file) — hindari RAM meledak bila banyak file besar.
%   File yang diakses terbaru dipertahankan; yang terlama dibuang saat penuh.
%
%   raw: struct dgn field .blobs (cell), .index (double vec), .names (cell,
%        SUDAH terurut leksikografis), .ext. [] bila gagal.
%
%   Lihat juga: pivanalyzemat.core.readMatFrame, pivanalyzemat.core.readMatFramePair

	persistent KEYS VALS
	if isempty(KEYS); KEYS = {}; VALS = {}; end
	CAP = 2;

	if nargin >= 2 && strcmpi(char(op), 'clear')
		KEYS = {}; VALS = {}; raw = [];
		return;
	end

	raw = [];
	matPath = char(matPath);
	if isempty(matPath) || ~isfile(matPath); return; end
	key = i_canon(matPath);

	% cache hit -> pindahkan ke posisi TERBARU (akhir) & kembalikan.
	hit = find(strcmp(KEYS, key), 1);
	if ~isempty(hit)
		raw = VALS{hit};
		KEYS(hit) = []; VALS(hit) = [];      % cabut
		KEYS{end+1} = key; VALS{end+1} = raw; % pasang sbg terbaru
		return;
	end

	% miss -> load 'prep', ambil raw ter-normalisasi (nama terurut leksikografis).
	try
		S = load(matPath, 'prep');
	catch
		return;
	end
	if ~isfield(S, 'prep') || ~isfield(S.prep, 'raw'); return; end
	r = S.prep.raw;
	if ~isfield(r, 'names') || isempty(r.names); return; end

	names = r.names(:);
	[names, ord] = sort(names);            % SAMA urutan unpackMat/PIVlab
	idx = double(r.index(:));
	idx = idx(ord);
	ext = '.jpg';
	if isfield(r, 'ext') && ~isempty(r.ext); ext = char(r.ext); end
	raw = struct('blobs', {r.blobs}, 'index', idx, 'names', {names}, 'ext', ext);

	% sisipkan sbg terbaru + jaga kapasitas (buang terlama = indeks 1).
	KEYS{end+1} = key; VALS{end+1} = raw;
	while numel(KEYS) > CAP
		KEYS(1) = []; VALS(1) = [];
	end
end

%% ===================================================================
function s = i_canon(p)
s = char(p);
try, s = char(java.io.File(s).getCanonicalPath()); catch; end %#ok<CTCH>
end
