function [img, name, nFrames] = readMatFrame(matEntry, which, applyMask)
%READMATFRAME  Decode SATU frame RAW langsung dari blob .mat (tanpa dump folder).
%
%   [img, name, nFrames] = pivanalyzemat.core.readMatFrame(matEntry, which)
%   [...] = pivanalyzemat.core.readMatFrame(matEntry, which, applyMask)
%
%   Membaca satu citra RAW dari berkas .mat PIVPrep single (skema
%   'pivprep_single_v1') TANPA membongkar seluruh eksperimen ke disk. Dipakai
%   Pratinjau Step 2 yang hanya menampilkan SATU frame pada satu waktu, sehingga
%   tak perlu menulis ratusan berkas RAW/GS hanya untuk melihat satu gambar.
%
%   matEntry  : satu elemen struct (punya .matfile) ATAU char path .mat.
%   which     : 'first' | 'last' | indeks numerik (1-based, sesudah urut nama).
%               Default 'first'.
%   applyMask : true (DEFAULT) = tempel masking persegi non-destruktif bila
%               prep.masking aktif (citra siap-tampil/siap-PIV). false = frame
%               BERSIH apa adanya (dipakai editor GRAINMASK saat menggambar kotak).
%
%   KELUARAN
%     img     : citra (uint8) hasil decode blob JPEG; [] bila gagal.
%     name    : nama berkas frame terpilih.
%     nFrames : jumlah total frame RAW di .mat.
%
%   Implementasi: load 'prep', pilih blob frame yang diminta (urut leksikografis
%   nama, sama dgn unpackMat), tulis SATU berkas sementara, imread, lalu hapus.
%   Hanya satu berkas kecil pernah menyentuh disk.
%
%   Lihat juga: pivanalyzemat.core.unpackMat, pivanalyzemat.core.readMatStripFrame,
%               pivanalyzemat.core.maskRect

	if nargin < 2 || isempty(which); which = 'first'; end
	if nargin < 3 || isempty(applyMask); applyMask = true; end
	img = []; name = ''; nFrames = 0;

	matPath = i_matPath(matEntry);
	if isempty(matPath) || ~isfile(matPath)
		error('pivanalyzemat:readMatFrame:noFile', 'Berkas .mat tidak ada:\n%s', matPath);
	end

	% --- JALUR STORE (warisan): file yg TERLANJUR punya blob-store per-frame
	%     (braw_idx) -> baca 1 blob (cepat, tak menulis). TIDAK meng-upgrade file
	%     yang belum punya store (prinsip: JANGAN tulis ulang MAT PREP besar). ---
	idx = pivanalyzemat.core.prepBlobStore.readIdx(matPath);
	if ~isempty(idx) && isfield(idx, 'index') && ~isempty(idx.index)
		nFrames = numel(idx.index);
		k = i_resolveWhich(which, nFrames);
		if k < 1 || k > nFrames; return; end
		[bytes, name] = pivanalyzemat.core.prepBlobStore.readFrameBytes(matPath, k, idx);
		img = i_decodeBytes(bytes, name);
		img = i_maybeMask(matPath, img, applyMask, k, nFrames);
		return;
	end

	% --- JALUR NORMAL: baca prep.raw dari CACHE RAM per-sesi (load pertama ~4 s
	%     utk file besar, berikutnya instan tanpa sentuh disk). MAT PREP TIDAK
	%     ditulis ulang; resep masking dibaca dari SIDECAR. ---
	raw = pivanalyzemat.core.prepRawCache(matPath);
	if isempty(raw) || ~isfield(raw, 'names') || isempty(raw.names)
		error('pivanalyzemat:readMatFrame:badFile', ...
			'Bukan pivprep_single_v1 (prep.raw tak ada):\n%s', matPath);
	end
	names = raw.names;                 % sudah terurut leksikografis (cache)
	idxAll = raw.index;
	nFrames = numel(names);
	if nFrames == 0; return; end

	k = i_resolveWhich(which, nFrames);
	if k < 1 || k > nFrames; return; end
	name = names{k};

	bi = idxAll(k);
	if bi < 1 || bi > numel(raw.blobs); return; end
	bytes = raw.blobs{bi};

	img = i_decodeBytes(bytes, name);
	img = i_maybeMask(matPath, img, applyMask, k, nFrames);
end

%% ===================================================================
function img = i_maybeMask(matPath, img, applyMask, k, nFrames)
%I_MAYBEMASK  Tempel masking bila aktif. Resep dibaca dari SIDECAR
%   '<nama>_mask.json' (pivanalyzemat.core.prepBlobStore.readMasking -> maskSidecar);
%   fallback warisan pmasking/prep.masking. Blob RAW tak disentuh (non-destruktif).
	if ~applyMask || isempty(img); return; end
	m = pivanalyzemat.core.prepBlobStore.readMasking(matPath);
	if ~isempty(m) && pivanalyzemat.core.maskRect.isActive(m)
		img = pivanalyzemat.core.maskRect.applyMask(img, m, k, nFrames);
	end
	% Layer-2 polygon (GRAINMASK2) — komposisi setelah kotak (idempoten).
	try
		p = pivanalyzemat.core.maskSidecar.readPoly(matPath);
		if ~isempty(p) && pivanalyzemat.core.maskPoly.isActive(p)
			img = pivanalyzemat.core.maskPoly.applyMask(img, p, k, nFrames);
		end
	catch
	end
end

%% ===================================================================
function k = i_resolveWhich(which, n)
if ischar(which) || isstring(which)
	switch lower(char(which))
		case 'first'; k = 1;
		case 'last';  k = n;
		otherwise;    k = 1;
	end
else
	k = round(double(which));
end
end

function img = i_decodeBytes(bytes, name)
%I_DECODEBYTES  Decode byte JPEG/PNG -> citra via SATU berkas sementara.
img = [];
[~, ~, ext] = fileparts(char(name));
if isempty(ext); ext = '.jpg'; end
tmp = [tempname ext];
cleaner = onCleanup(@() i_rm(tmp)); %#ok<NASGU>
try
	fid = fopen(tmp, 'wb');
	if fid < 0; return; end
	fwrite(fid, bytes, 'uint8');
	fclose(fid);
	img = imread(tmp);
catch
	img = [];
end
end

function i_rm(p)
try, if isfile(p); delete(p); end; catch; end
end

function p = i_matPath(matEntry)
if ischar(matEntry) || isstring(matEntry)
	p = char(matEntry);
elseif isstruct(matEntry) && isfield(matEntry, 'matfile')
	p = char(matEntry.matfile);
else
	p = '';
end
end
