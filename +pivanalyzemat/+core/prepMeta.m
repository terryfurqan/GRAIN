function pmeta = prepMeta(prep)
%PREPMETA  Bangun struct metadata RINGAN 'pmeta' dari struct 'prep' MAT PREP.
%
%   pmeta = pivanalyzemat.core.prepMeta(prep)
%
%   TUJUAN. MAT PREP disimpan '-v7' (terkompresi). Format '-v7' TIDAK mendukung
%   partial-load DI DALAM satu variabel: membaca `prep.nFrames` memaksa MATLAB
%   mendekompresi SELURUH variabel `prep` (termasuk ratusan MB blob RAW) ke RAM.
%   Untuk 4 file @500 MB, pindai folder jadi puluhan detik hanya untuk mengisi
%   tabel — padahal yang dibutuhkan cuma nFrames/format/ext.
%
%   SOLUSI. Simpan metadata ringan ini sebagai VARIABEL TOP-LEVEL TERPISAH
%   ('pmeta') berdampingan dengan 'prep' di berkas .mat yang sama. `load('-v7')`
%   BISA memuat satu variabel tanpa yang lain, jadi `load(file,'pmeta')` hanya
%   membaca beberapa ratus byte — blob 'prep' tak pernah disentuh (≈0 detik,
%   ratusan kali lebih cepat). scanMats memakai 'pmeta' bila ada; berkas lama
%   tanpa 'pmeta' di-upgrade in-place sekali (append var, blob 'prep' utuh).
%
%   Field 'pmeta' = superset metadata yang dibaca pivanalyzemat.core.scanMats:
%       .schema     - 'pivprep_pmeta_v1' (penanda skema)
%       .format     - prep.format ('pivprep_single_v1')
%       .nFrames    - jumlah frame RAW
%       .nGs        - jumlah GS (di-normalkan: = nFrames bila GS tak disemat)
%       .ext        - ekstensi RAW umum (mis '.jpg')
%       .suffix     - pola ekstensi ('*.jpg')
%       .seqmode    - mode sequencing ('consecutive'|'pairs'|'skip')
%       .seqstep    - langkah skip (>=1)
%       .has_exif   - logical, memuat tabel EXIF
%       .pab_src    - folder RAW asli (jembatan progres QPIV Step 0), '' bila -
%
%   Lihat juga: pivanalyzemat.core.scanMats, pivprepPackFolder

	pmeta = struct('schema','pivprep_pmeta_v1', 'format','', 'nFrames',0, ...
		'nGs',0, 'ext','.jpg', 'suffix','*.jpg', ...
		'seqmode','consecutive', 'seqstep',1, 'has_exif',false, 'pab_src','');
	if ~isstruct(prep); return; end

	if isfield(prep,'format') && ~isempty(prep.format)
		pmeta.format = char(prep.format);
	end

	% --- nFrames ---
	nF = 0;
	if isfield(prep,'nFrames') && ~isempty(prep.nFrames)
		nF = double(prep.nFrames);
	elseif isfield(prep,'raw') && isfield(prep.raw,'names')
		nF = numel(prep.raw.names);
	end
	pmeta.nFrames = nF;

	% --- ext / suffix ---
	ext = '.jpg';
	if isfield(prep,'raw') && isfield(prep.raw,'ext') && ~isempty(prep.raw.ext)
		ext = char(prep.raw.ext);
	elseif isfield(prep,'raw') && isfield(prep.raw,'names') && ~isempty(prep.raw.names)
		[~,~,e2] = fileparts(prep.raw.names{1}); if ~isempty(e2); ext = e2; end
	end
	if ~startsWith(ext,'.'); ext = ['.' ext]; end
	pmeta.ext    = ext;
	pmeta.suffix = ['*' ext];

	% --- nGs (normalisasi sama scanMats: 0 -> nFrames karena GS diregen) ---
	nGs = 0;
	if isfield(prep,'gs') && isfield(prep.gs,'names') && ~isempty(prep.gs.names)
		nGs = numel(prep.gs.names);
	elseif isfield(prep,'gs') && isfield(prep.gs,'index') && ~isempty(prep.gs.index)
		nGs = numel(prep.gs.index);
	end
	if nGs == 0 && nF > 0; nGs = nF; end
	pmeta.nGs = nGs;

	% --- sequencing ---
	if isfield(prep,'sequencing') && isstruct(prep.sequencing)
		s = prep.sequencing;
		if isfield(s,'mode') && ~isempty(s.mode)
			pmeta.seqmode = lower(char(s.mode));
		end
		if isfield(s,'step') && ~isempty(s.step)
			pmeta.seqstep = max(1, round(double(s.step)));
		end
	end

	pmeta.has_exif = isfield(prep,'exif') && ~isempty(prep.exif);

	if isfield(prep,'pab_src') && ~isempty(prep.pab_src)
		pmeta.pab_src = char(prep.pab_src);
	end
end
