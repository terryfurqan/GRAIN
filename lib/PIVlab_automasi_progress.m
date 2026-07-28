function varargout = PIVlab_automasi_progress(action, varargin)
%PIVLAB_AUTOMASI_PROGRESS  Penyimpan progres Quick PIV (QPIV) lintas-sesi.
%
%   SATU berkas global menyimpan status QPIV + daftar frame yang ditandai
%   "abaikan" untuk SEMUA eksperimen, sehingga pekerjaan dapat dilanjutkan di
%   sesi berikutnya. Berkas diletakkan di samping berkas kode tool ini:
%       <folder_kode>/PIVlab_automasi_progress.mat   (variabel: progress)
%
%   Setiap eksperimen dikunci oleh PATH foldernya (expdir) yang dinormalisasi
%   (huruf kecil, separator '/', tanpa slash akhir) supaya tahan terhadap
%   perbedaan separator/huruf besar antar-sesi/OS.
%
%   API (dispatch lewat argumen pertama 'action'):
%     S    = PIVlab_automasi_progress('load')            % muat/empat struct progres
%     p    = PIVlab_automasi_progress('file')            % path berkas progres
%     key  = PIVlab_automasi_progress('key', expdir)     % normalisasi expdir -> key
%     e    = PIVlab_automasi_progress('get', expdirOrKey)% entry atau []
%     all  = PIVlab_automasi_progress('all')             % struct-array semua entry
%            PIVlab_automasi_progress('set', entry)      % upsert by entry.expdir/key
%            PIVlab_automasi_progress('setIgnore', expdirOrKey, ignoreVec)
%            PIVlab_automasi_progress('clearIgnore', expdirOrKey)
%            PIVlab_automasi_progress('remove', expdirOrKey)
%     tf   = PIVlab_automasi_progress('isDone', expdirOrKey)
%     e0   = PIVlab_automasi_progress('empty')           % template entry kosong
%     sig  = PIVlab_automasi_progress('sig', orient, pos, iw, suffix, nframes)
%
%   Lihat juga: PIVlab_automasi_qpiv, PIVlab_automasi_qpiv_GUI,
%               PIVlab_automasi_batch_GUI_V4

	if nargin < 1; action = 'load'; end
	action = lower(char(action));

	switch action
		case 'file'
			varargout{1} = i_progressFile();

		case 'setfile'
			% Setel lokasi berkas progres aktif (per-root). '' -> default global.
			if isempty(varargin); p = ''; else; p = varargin{1}; end
			varargout{1} = i_progressFile(p);

		case 'resetfile'
			varargout{1} = i_progressFile('');

		case 'empty'
			varargout{1} = i_emptyEntry();

		case 'key'
			varargout{1} = i_key(varargin{1});

		case 'sig'
			varargout{1} = i_signature(varargin{:});

		case 'load'
			varargout{1} = i_load();

		case 'all'
			S = i_load();
			varargout{1} = S.entries;

		case 'get'
			% get(expdirOrKey) ATAU get(expdirOrKey, fallbackKey).
			%   Jembatan QPIV: Step 2 mengunci dgn path .mat; bila tak ketemu,
			%   coba folder RAW asli (pab_src) yang dipakai Step 0. fallbackKey
			%   kosong -> perilaku lama (mundur anggun untuk .mat lama).
			S = i_load();
			e = i_find(S, i_key(varargin{1}));
			if isempty(e) && numel(varargin) >= 2 && ~isempty(varargin{2})
				e = i_find(S, i_key(varargin{2}));
			end
			varargout{1} = e;

		case 'isdone'
			S = i_load();
			e = i_find(S, i_key(varargin{1}));
			varargout{1} = ~isempty(e) && isfield(e, 'qpiv_done') && logical(e.qpiv_done);

		case 'set'
			S = i_load();
			e = i_normEntry(varargin{1});
			if isempty(e.key); e.key = i_key(e.expdir); end
			S = i_upsert(S, e);
			i_save(S);
			if nargout > 0; varargout{1} = e; end

		case 'setignore'
			key = i_key(varargin{1});
			vec = i_normVec(varargin{2});
			S = i_load();
			e = i_find(S, key);
			if isempty(e)
				e = i_emptyEntry(); e.key = key;
				if ischar(varargin{1}) || isstring(varargin{1}); e.expdir = char(varargin{1}); end
			end
			e.ignore_frames = vec;
			e.n_drop = numel(vec);
			S = i_upsert(S, e);
			i_save(S);
			if nargout > 0; varargout{1} = e; end

		case 'clearignore'
			key = i_key(varargin{1});
			S = i_load();
			e = i_find(S, key);
			if ~isempty(e)
				e.ignore_frames = []; e.n_drop = 0;
				S = i_upsert(S, e); i_save(S);
			end

		case 'remove'
			key = i_key(varargin{1});
			S = i_load();
			if ~isempty(S.entries)
				keep = ~strcmp({S.entries.key}, key);
				S.entries = S.entries(keep);
				i_save(S);
			end

		case 'setmask'
			% setmask(expdirOrKey, recipe) — simpan resep masking PABMASK ke entry.
			%   recipe = struct maskRect (enabled/fill/boxes) atau [] utk hapus.
			key = i_key(varargin{1});
			recipe = []; if numel(varargin) >= 2; recipe = varargin{2}; end
			S = i_load();
			e = i_find(S, key);
			if isempty(e)
				e = i_emptyEntry(); e.key = key;
				if ischar(varargin{1}) || isstring(varargin{1}); e.expdir = char(varargin{1}); end
			end
			e.mask_recipe = recipe;
			S = i_upsert(S, e);
			i_save(S);
			if nargout > 0; varargout{1} = e; end

		case 'getmask'
			% getmask(expdirOrKey) -> resep masking (struct) atau [] bila tak ada.
			S = i_load();
			e = i_find(S, i_key(varargin{1}));
			if isempty(e) || ~isfield(e,'mask_recipe'); varargout{1} = []; else; varargout{1} = e.mask_recipe; end

		case 'setpoly'
			% setpoly(expdirOrKey, polyRecipe) — resep polygon PABMASK2.
			key = i_key(varargin{1});
			recipe = []; if numel(varargin) >= 2; recipe = varargin{2}; end
			S = i_load();
			e = i_find(S, key);
			if isempty(e)
				e = i_emptyEntry(); e.key = key;
				if ischar(varargin{1}) || isstring(varargin{1}); e.expdir = char(varargin{1}); end
			end
			e.poly_recipe = recipe;
			S = i_upsert(S, e);
			i_save(S);
			if nargout > 0; varargout{1} = e; end

		case 'getpoly'
			S = i_load();
			e = i_find(S, i_key(varargin{1}));
			if isempty(e) || ~isfield(e,'poly_recipe'); varargout{1} = []; else; varargout{1} = e.poly_recipe; end

		otherwise
			error('PIVlab_automasi_progress:badAction', ...
				'Aksi tidak dikenal: %s', action);
	end
end

%% ========================= SUBFUNGSI =====================
function p = i_progressFile(setTo)
%I_PROGRESSFILE  Path berkas progres.
%   Default: di samping kode tool (global, kompat lama).
%   Override (per-root): i_progressFile(path) menyetel lokasi aktif untuk
%   sesi ini (disimpan di persistent). i_progressFile('') -> kembali default.
	persistent OVERRIDE
	if nargin >= 1
		if isempty(setTo)
			OVERRIDE = '';
		else
			OVERRIDE = char(setTo);
		end
	end
	if ~isempty(OVERRIDE)
		p = OVERRIDE; return;
	end
	p = fullfile(fileparts(mfilename('fullpath')), 'PIVlab_automasi_progress.mat');
end

function e = i_emptyEntry()
%I_EMPTYENTRY  Template satu entry (urutan field kanonik).
	e = struct( ...
		'key',           '', ...
		'expdir',        '', ...
		'name',          '', ...
		'raw_suffix',    '', ...
		'sequencing',    'consecutive', ...
		'scan_orient',   'Horizontal', ...
		'scan_pos_pct',  50, ...
		'iw_passes',     [64 32 25 16], ...
		'num_passes',    3, ...
		'skip',          0, ...
		'qpiv_done',     false, ...
		'qpiv_cache',    '', ...
		'qpiv_nframes',  0, ...
		'qpiv_run_time', '', ...
		'ignore_frames', [], ...
		'ignore_names',  {{}}, ...    % nama gambar (basename) yang DIBUANG QPIV
		'qpiv_kept_names', {{}}, ...  % nama gambar LENGKAP yang LOLOS QPIV (urutan benar)
		'n_drop',        0, ...
		'pos_hash',      '', ...
		'pab_src',       '', ...      % PAB_step_1: folder foto mentah
		'pab_cropmode',  '', ...      % 'full' | 'crop' | 'square'
		'pab_out',       '', ...      % path .mat keluaran
		'pab_nimg',      0, ...       % jumlah foto
		'pab_anchor',    [], ...      % preset anchor stabilisasi (struct) atau []
		'pab_crop',      [], ...      % preset ROI crop (struct) atau []
		'pab_listed',    false, ...   % true = baris ini bagian daftar PAB_step_1
		'mask_recipe',   [], ...      % PABMASK: resep kotak (struct maskRect) atau []
		'poly_recipe',   [], ...      % PABMASK2: resep polygon (struct maskPoly) atau []
		'updated',       '');
end

function e = i_normEntry(src)
%I_NORMENTRY  Gabungkan field src ke template -> entry berfield kanonik penuh.
	e = i_emptyEntry();
	if ~isstruct(src); return; end
	fn = fieldnames(e);
	for i = 1:numel(fn)
		if isfield(src, fn{i}) && ~isempty(src.(fn{i}))
			e.(fn{i}) = src.(fn{i});
		end
	end
	% normalisasi tipe
	e.ignore_frames    = i_normVec(e.ignore_frames);
	e.ignore_names     = i_normNames(e.ignore_names);
	e.qpiv_kept_names  = i_normNames(e.qpiv_kept_names);
	e.n_drop           = numel(e.ignore_frames);
	if isempty(e.key); e.key = i_key(e.expdir); end
end

function c = i_normNames(x)
%I_NORMNAMES  Normalisasi daftar nama berkas -> cellstr baris (char, tak kosong).
%   Menerima cellstr, string-array, atau char tunggal. Hasil: 1xN cellstr.
	c = {};
	if isempty(x); return; end
	if ischar(x); c = {x}; return; end
	if isstring(x); x = cellstr(x); end
	if ~iscell(x); return; end
	x = x(:)';
	keep = false(1, numel(x));
	for i = 1:numel(x)
		if ischar(x{i}) && ~isempty(x{i})
			keep(i) = true;
		elseif isstring(x{i}) && strlength(x{i}) > 0
			x{i} = char(x{i}); keep(i) = true;
		end
	end
	c = x(keep);
end

function v = i_normVec(x)
%I_NORMVEC  Vektor indeks frame -> baris double unik & terurut (>=1, integer).
	if isempty(x); v = []; return; end
	v = double(x(:)');
	v = v(isfinite(v) & v >= 1);
	v = unique(round(v));
end

function key = i_key(expdir)
%I_KEY  Normalisasi path eksperimen menjadi kunci stabil.
	if isempty(expdir); key = ''; return; end
	key = char(string(expdir));
	key = strrep(key, '\', '/');
	key = regexprep(key, '/+$', '');     % buang slash akhir
	key = lower(key);
end

function sig = i_signature(orient, pos, iw, suffix, nframes, skip, seq)
%I_SIGNATURE  Tanda-tangan konfigurasi QPIV (deteksi cache basi).
	if nargin < 7 || isempty(seq); seq = ''; end
	if nargin < 6 || isempty(skip); skip = 0; end
	if nargin < 5; nframes = 0; end
	if nargin < 4 || isempty(suffix); suffix = ''; end
	if nargin < 3 || isempty(iw); iw = [0 0 0 0]; end
	iw = double(iw(:)'); if numel(iw) < 4; iw(end+1:4) = 0; end
	sig = sprintf('%s|%.3f|%d-%d-%d-%d|skip%d|%s|%d|%s', char(orient), double(pos), ...
		round(iw(1)), round(iw(2)), round(iw(3)), round(iw(4)), ...
		round(skip), char(seq), round(nframes), char(suffix));
end

function S = i_emptyStore()
	S = struct('version', 1, 'updated', '', 'entries', i_emptyEntry());
	S.entries(:) = [];   % struct-array kosong berfield kanonik
end

function S = i_load()
%I_LOAD  Muat berkas progres; berkas korup/absen -> store kosong (backup yg rusak).
	S = i_emptyStore();
	p = i_progressFile();
	if ~isfile(p); return; end
	try
		L = load(p, 'progress');
		if isfield(L, 'progress') && isstruct(L.progress) ...
				&& isfield(L.progress, 'entries')
			S.version = i_getf(L.progress, 'version', 1);
			S.updated = i_getf(L.progress, 'updated', '');
			ent = L.progress.entries;
			% Normalisasi tiap entry ke field kanonik (toleran skema lama).
			out = i_emptyEntry(); out(:) = [];
			for i = 1:numel(ent)
				out(end+1) = i_normEntry(ent(i)); %#ok<AGROW>
			end
			S.entries = out;
		end
	catch ME
		% Berkas tidak dapat dibaca: cadangkan lalu mulai bersih.
		try
			bak = [p '.corrupt-' datestr(now, 'yyyymmdd-HHMMSS') '.bak']; %#ok<TNOW1>
			copyfile(p, bak);
			warning('PIVlab_automasi_progress:corrupt', ...
				'Berkas progres rusak (%s). Dicadangkan ke %s; mulai baru.', ...
				ME.message, bak);
		catch
		end
		S = i_emptyStore();
	end
end

function i_save(S)
%I_SAVE  Simpan store secara atomik (tulis temp lalu movefile).
	p = i_progressFile();
	S.updated = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1>
	progress = S; %#ok<NASGU>
	tmp = [p '.tmp'];
	try
		save(tmp, 'progress', '-v7');
		if isfile(p); delete(p); end
		movefile(tmp, p, 'f');
	catch ME
		try if isfile(tmp); delete(tmp); end; catch; end
		% fallback: langsung simpan (non-atomik) agar progres tak hilang
		try
			save(p, 'progress', '-v7');
		catch
			warning('PIVlab_automasi_progress:save', ...
				'Gagal menyimpan progres: %s', ME.message);
		end
	end
end

function e = i_find(S, key)
%I_FIND  Cari entry berdasar key; [] bila tidak ada.
	e = [];
	if isempty(key) || isempty(S.entries); return; end
	idx = find(strcmp({S.entries.key}, key), 1);
	if ~isempty(idx); e = S.entries(idx); end
end

function S = i_upsert(S, e)
%I_UPSERT  Sisipkan/timpa entry berdasar key, jaga field kanonik konsisten.
	e = i_normEntry(e);
	e.updated = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1>
	if isempty(S.entries)
		S.entries = e; return;
	end
	idx = find(strcmp({S.entries.key}, e.key), 1);
	if isempty(idx)
		S.entries(end+1) = orderfields(e, S.entries(1));
	else
		S.entries(idx) = orderfields(e, S.entries(1));
	end
end

function v = i_getf(s, f, dflt)
	if isfield(s, f) && ~isempty(s.(f)); v = s.(f); else; v = dflt; end
end
