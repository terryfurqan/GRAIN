function [imgFirst, imgLast, nameFirst, nameLast, nFrames] = readMatFramePair(matEntry, applyMask)
%READMATFRAMEPAIR  Decode frame AWAL + AKHIR sekaligus dari blob .mat (1x load).
%
%   [imgFirst, imgLast, nameFirst, nameLast, nFrames] = ...
%       pivanalyzemat.core.readMatFramePair(matEntry)
%   [...] = pivanalyzemat.core.readMatFramePair(matEntry, applyMask)
%
%   Sama seperti readMatFrame, tetapi membaca DUA frame (pertama & terakhir)
%   dalam SATU pemanggilan load(). Pratinjau Step 2 hanya butuh awal+akhir;
%   memanggil readMatFrame dua kali akan memuat seluruh blob .mat ke RAM DUA
%   kali (sangat lambat untuk .mat besar). Fungsi ini cukup load sekali.
%
%   matEntry  : satu elemen struct (punya .matfile) ATAU char path .mat.
%   applyMask : true (DEFAULT) = tempel masking persegi non-destruktif bila
%               prep.masking aktif → pratinjau SAMA dengan citra yang dimakan
%               PIV (WYSIWYG). false = frame BERSIH apa adanya. Konsisten dgn
%               readMatFrame supaya PAB2 kompatibel PABMASK.
%
%   Lihat juga: pivanalyzemat.core.readMatFrame, pivanalyzemat.core.unpackMat

	if nargin < 2 || isempty(applyMask); applyMask = true; end
	imgFirst = []; imgLast = []; nameFirst = ''; nameLast = ''; nFrames = 0;

	matPath = i_matPath(matEntry);
	if isempty(matPath) || ~isfile(matPath)
		error('pivanalyzemat:readMatFramePair:noFile', 'Berkas .mat tidak ada:\n%s', matPath);
	end

	% --- JALUR STORE (warisan): file yg TERLANJUR punya blob-store (braw_idx)
	%     -> baca 2 blob (cepat, tak menulis). TIDAK meng-upgrade file yg belum
	%     punya store (prinsip: JANGAN tulis ulang MAT PREP besar). ---
	idx = pivanalyzemat.core.prepBlobStore.readIdx(matPath);
	if ~isempty(idx) && isfield(idx, 'index') && ~isempty(idx.index)
		nFrames = numel(idx.index);
		if nFrames == 0; return; end
		[bF, nameFirst] = pivanalyzemat.core.prepBlobStore.readFrameBytes(matPath, 1, idx);
		[bL, nameLast]  = pivanalyzemat.core.prepBlobStore.readFrameBytes(matPath, nFrames, idx);
		imgFirst = i_decodeBytes(bF, nameFirst);
		imgLast  = i_decodeBytes(bL, nameLast);
		[imgFirst, imgLast] = i_applyMask(matPath, imgFirst, imgLast, applyMask, nFrames);
		return;
	end

	% --- JALUR NORMAL: prep.raw dari CACHE RAM per-sesi (load pertama ~4 s utk
	%     file besar, berikutnya instan). MAT PREP TIDAK ditulis ulang; resep
	%     masking dari SIDECAR. ---
	raw = pivanalyzemat.core.prepRawCache(matPath);
	if isempty(raw) || ~isfield(raw, 'names') || isempty(raw.names)
		error('pivanalyzemat:readMatFramePair:badFile', ...
			'Bukan pivprep_single_v1 (prep.raw tak ada):\n%s', matPath);
	end
	names = raw.names; idxAll = raw.index;
	nFrames = numel(names);
	if nFrames == 0; return; end

	[imgFirst, nameFirst] = i_pick(names, idxAll, raw.blobs, 1);
	[imgLast,  nameLast ] = i_pick(names, idxAll, raw.blobs, nFrames);
	[imgFirst, imgLast] = i_applyMask(matPath, imgFirst, imgLast, applyMask, nFrames);
end

%% ===================================================================
function [imgFirst, imgLast] = i_applyMask(matPath, imgFirst, imgLast, applyMask, nFrames)
%I_APPLYMASK  Tempel masking (dari SIDECAR) ke frame awal(rank 1)+akhir(rank N).
	if ~applyMask; return; end
	m = pivanalyzemat.core.prepBlobStore.readMasking(matPath);
	if isempty(m) || ~pivanalyzemat.core.maskRect.isActive(m); return; end
	if ~isempty(imgFirst)
		imgFirst = pivanalyzemat.core.maskRect.applyMask(imgFirst, m, 1, nFrames);
	end
	if ~isempty(imgLast)
		imgLast = pivanalyzemat.core.maskRect.applyMask(imgLast, m, nFrames, nFrames);
	end
end

%% ===================================================================
function [img, name] = i_pick(names, idxAll, blobs, k)
img = []; name = '';
if k < 1 || k > numel(names); return; end
name = names{k};
bi = idxAll(k);
if bi < 1 || bi > numel(blobs); return; end
img = i_decodeBytes(blobs{bi}, name);
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
try if isfile(p); delete(p); end; catch; end
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
