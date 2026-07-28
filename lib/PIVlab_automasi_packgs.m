function pack = PIVlab_automasi_packgs(gsFilesPerFrame, varargin)
%PIVLAB_AUTOMASI_PACKGS  Kemas citra GS per-frame menjadi bg_images (JPEG+dedup).
%
%   pack = PIVlab_automasi_packgs(gsFilesPerFrame)
%   pack = PIVlab_automasi_packgs(gsFilesPerFrame, 'Name', Value, ...)
%
%   Fungsi pekerja MANDIRI (tanpa GUI/dialog, tanpa ketergantungan PIVTerry)
%   yang mengubah daftar berkas citra GS per-frame menjadi paket latar
%   terkompresi yang 100% kompatibel dengan PIVTerry (lihat
%   +pivterry/+data/buildDataset.m, skema 'jpeg_dedup_v1').
%
%   Logikanya disuling dari tools/vgsBuildPackage.m milik PIVTerry, namun
%   beroperasi langsung dari daftar PATH berkas (bukan memuat ulang MAT) dan
%   tidak menulis berkas apa pun -- hanya MENGEMBALIKAN variabel paket,
%   sehingga pemanggil dapat menyimpannya/menyematkannya ke file .mat hasil
%   PIV (lihat PIVlab_automasi_batch_V2).
%
%   ARGUMEN
%     gsFilesPerFrame : cell {nF x 1} berisi PATH berkas citra GS untuk tiap
%                       frame (boleh ada path berulang; '' atau berkas tak ada
%                       -> frame tanpa latar, index 0).
%
%   OPSI (Name-Value)
%     'Quality'      : kualitas JPEG saat RE-ENCODE (1..100). Default 92.
%     'ReencodeJpeg' : true -> berkas .jpg/.jpeg pun di-encode ulang ke
%                      kualitas 'Quality'. Default false -> berkas JPEG
%                      disimpan APA ADANYA (lossless passthrough, lebih cepat
%                      & tanpa kompresi ganda; berkas non-JPEG tetap di-encode).
%     'ProgressFcn'  : handle @(frac,msg) untuk laporan progres (0..1).
%     'LogFcn'       : handle @(msg) untuk baris log.
%
%   KELUARAN  pack (struct):
%     .format    = 'jpeg_dedup_v1'        (-> bg_images_format)
%     .blobs     = {uint8(:); ...}        (-> bg_images_blobs)  blob unik
%     .index     = uint32 vektor [nF x 1] (-> bg_images_index)  0 = tak ada
%     .quality   = kualitas JPEG nominal  (-> bg_images_quality)
%     .nFrames   = jumlah frame
%     .nRead     = jumlah frame yang berhasil membaca citra
%     .nUnique   = jumlah blob unik
%     .nMissing  = jumlah frame tanpa citra (index 0)
%
%   Lihat juga: PIVlab_automasi_batch_V2, PIVlab_automasi_scanprep

ip = inputParser;
ip.addRequired('gsFilesPerFrame', @(x) iscell(x));
ip.addParameter('Quality',      92, @(x) isnumeric(x) && isscalar(x));
ip.addParameter('ReencodeJpeg', false, @(x) islogical(x) || isnumeric(x));
ip.addParameter('ProgressFcn',  [], @(x) isempty(x) || isa(x, 'function_handle'));
ip.addParameter('LogFcn',       [], @(x) isempty(x) || isa(x, 'function_handle'));
ip.parse(gsFilesPerFrame, varargin{:});
opt = ip.Results;

quality = round(double(opt.Quality));
if ~isfinite(quality) || quality < 1 || quality > 100; quality = 92; end
reencode = logical(opt.ReencodeJpeg);
progFcn  = opt.ProgressFcn;
logFcn   = opt.LogFcn;

nF = numel(gsFilesPerFrame);

blobs  = {};
index  = zeros(nF, 1, 'uint32');
pathMap = containers.Map('KeyType', 'char', 'ValueType', 'uint32');   % path  -> blob idx
hashMap = containers.Map('KeyType', 'char', 'ValueType', 'uint32');   % hash  -> blob idx

tmpFile = [tempname() '.jpg'];
cleanup = onCleanup(@() i_delQuiet(tmpFile)); %#ok<NASGU>

nRead = 0; nMissing = 0;
step  = max(1, round(nF/10));
report(0, sprintf('Mengemas %d citra GS (JPEG q=%d)...', nF, quality));

for k = 1:nF
	p = gsFilesPerFrame{k};
	if ~ischar(p) && ~isstring(p); p = ''; else; p = char(p); end

	if isempty(p) || ~isfile(p)
		index(k) = 0;            % frame tanpa latar
		nMissing = nMissing + 1;
		report(k/nF, sprintf('GS %d / %d (tak ada)', k, nF));
		continue;
	end

	% Path yang sama -> blob yang sama (dedup berbasis berkas).
	if isKey(pathMap, p)
		index(k) = pathMap(p);
		nRead = nRead + 1;
		report(k/nF, sprintf('GS %d / %d', k, nF));
		continue;
	end

	bytes = i_readGsBytes(p, reencode, quality, tmpFile);
	if isempty(bytes)
		index(k) = 0;
		nMissing = nMissing + 1;
		logmsg(sprintf('  [PERINGATAN] gagal baca/encode GS: %s', p));
		report(k/nF, sprintf('GS %d / %d (gagal)', k, nF));
		continue;
	end

	% Dedup berbasis isi (dua berkas berisi byte identik -> satu blob).
	key = i_hashBytes(bytes);
	if isKey(hashMap, key)
		idx = hashMap(key);
	else
		blobs{end+1, 1} = bytes; %#ok<AGROW>
		idx = uint32(numel(blobs));
		hashMap(key) = idx;
	end
	index(k)   = idx;
	pathMap(p) = idx;
	nRead = nRead + 1;

	if mod(k, step) == 0 || k == nF
		logmsg(sprintf('  ...kemas %d / %d citra GS (%d blob unik)', k, nF, numel(blobs)));
	end
	report(k/nF, sprintf('GS %d / %d', k, nF));
end

pack = struct();
pack.format   = 'jpeg_dedup_v1';
pack.blobs    = blobs;
pack.index    = uint32(index);
pack.quality  = quality;
pack.nFrames  = nF;
pack.nRead    = nRead;
pack.nUnique  = numel(blobs);
pack.nMissing = nMissing;

report(1, sprintf('GS selesai: %d frame, %d blob unik, %d kosong.', nF, numel(blobs), nMissing));

	%% --------------------------------------------------- nested reporters
	function report(frac, msg)
		if ~isempty(progFcn)
			try progFcn(max(0, min(1, frac)), msg); catch; end
		end
	end
	function logmsg(msg)
		if ~isempty(logFcn)
			try logFcn(msg); catch; end
		end
	end
end


%% ========================= SUBFUNGSI =====================
function bytes = i_readGsBytes(p, reencode, quality, tmpFile)
%I_READGSBYTES  Ambil byte JPEG untuk satu berkas GS.
%   Berkas .jpg/.jpeg dikembalikan apa adanya (kecuali reencode=true);
%   format lain di-encode ke JPEG kualitas 'quality'.
	bytes = [];
	[~, ~, ext] = fileparts(p);
	isJpeg = any(strcmpi(ext, {'.jpg', '.jpeg'}));

	if isJpeg && ~reencode
		fid = fopen(p, 'rb');
		if fid < 0, return; end
		bytes = fread(fid, Inf, '*uint8');
		fclose(fid);
		bytes = bytes(:);
		return;
	end

	try
		img = i_toU8RGB(imread(p));
	catch
		img = [];
	end
	if isempty(img), return; end
	try
		imwrite(img, tmpFile, 'jpg', 'Quality', quality);
		fid = fopen(tmpFile, 'rb');
		if fid < 0, return; end
		bytes = fread(fid, Inf, '*uint8');
		fclose(fid);
		bytes = bytes(:);
	catch
		bytes = [];
	end
end


function img = i_toU8RGB(img)
%I_TOU8RGB  Normalisasi citra ke uint8 (warna dipertahankan). [dari vgsBuildPackage]
	if isempty(img), img = []; return; end
	if islogical(img), img = uint8(img) * 255; end
	if isa(img, 'uint16')
		img = uint8(double(img) / 257);
	elseif isa(img, 'single') || isa(img, 'double')
		m = max(img(:));
		if isempty(m) || ~isfinite(m), img = []; return; end
		if m <= 1.0 + eps, img = uint8(img * 255);
		else,              img = uint8(min(max(img, 0), 255)); end
	elseif ~isa(img, 'uint8')
		try img = im2uint8(img); catch; img = []; return; end
	end
	if ndims(img) > 3, img = []; end %#ok<ISMAT>
end


function key = i_hashBytes(bytes)
%I_HASHBYTES  Hash MD5 (heksadesimal) dari vektor byte. [dari vgsBuildPackage]
	persistent md
	if isempty(md)
		md = java.security.MessageDigest.getInstance('MD5');
	end
	md.reset();
	md.update(bytes);
	digest = typecast(md.digest(), 'uint8');
	key = lower(reshape(dec2hex(digest, 2).', 1, []));
end


function i_delQuiet(p)
	try
		if exist(p, 'file'), delete(p); end
	catch
	end
end
