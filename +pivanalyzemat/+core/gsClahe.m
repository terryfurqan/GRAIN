function g = gsClahe(img, varargin)
%GSCLAHE  Latar GS "optimum" on-the-fly: grayscale + CLAHE + auto kontras.
%
%   g = pivanalyzemat.core.gsClahe(img)
%   g = pivanalyzemat.core.gsClahe(img, 'Name', Value, ...)
%
%   Mengubah satu citra (RGB/grayscale) menjadi latar tampilan yang jernih untuk
%   axMain Quick PIV: kontras lokal diratakan (CLAHE / adapthisteq) lalu rentang
%   intensitas diregang (imadjust + stretchlim) agar terang/kontras optimum.
%   MURNI KOSMETIK — hanya untuk DITAMPILKAN, tidak pernah dipakai komputasi PIV
%   (PIV memakai RAW + CLAHE internal PIVlab sendiri).
%
%   Keluaran g: uint8 RGB (3 kanal) siap dipakai sebagai CData latar. Direplikasi
%   ke 3 kanal supaya TIDAK ikut diwarnai colormap turbo milik bidang |V|.
%
%   OPSI
%     'ClipLimit' : batas klip CLAHE (0..1). Default 0.01 (lembut, tak over).
%     'NumTiles'  : [r c] jumlah ubin adapthisteq. Default auto dari ukuran citra
%                   (~ satu ubin per ~64 px, mirip 'CLAHE size' 64 px PIVlab).
%     'StretchTol': toleransi stretchlim [lo hi]. Default [0.01 0.99].
%
%   Lihat juga: adapthisteq, imadjust, stretchlim, PIVlab_automasi (CLAHE 64 px)

	ip = inputParser;
	ip.addRequired('img');
	ip.addParameter('ClipLimit', 0.01, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
	ip.addParameter('NumTiles', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
	ip.addParameter('StretchTol', [0.01 0.99], @(x) isnumeric(x) && numel(x) == 2);
	ip.parse(img, varargin{:});
	opt = ip.Results;

	if isempty(img); g = []; return; end

	% --- grayscale uint8 ---
	gy = img;
	if size(gy, 3) == 3
		try, gy = rgb2gray(gy); catch, gy = gy(:,:,1); end
	end
	if ~isa(gy, 'uint8')
		gy = im2uint8(i_normDouble(gy));
	end

	% --- CLAHE (adapthisteq) ---
	tiles = opt.NumTiles;
	if isempty(tiles)
		% ~ satu ubin per 64 px (mirip 'CLAHE size' 64 PIVlab); minimal 2x2.
		tiles = max(2, round(size(gy) / 64));
		tiles = tiles([1 2]);
	end
	try
		gy = adapthisteq(gy, 'NumTiles', tiles, 'ClipLimit', opt.ClipLimit, ...
			'Distribution', 'uniform');
	catch
		% adapthisteq absen/gagal -> lanjut tanpa CLAHE (tetap diregang).
	end

	% --- auto brightness/contrast (regang rentang robust) ---
	try
		lohi = stretchlim(gy, opt.StretchTol);
		gy = imadjust(gy, lohi, [0 1]);
	catch
		try, gy = imadjust(gy); catch; end
	end

	% --- paksa 3 kanal (kebal colormap |V|) ---
	g = repmat(gy, 1, 1, 3);
end

%% ===================================================================
function d = i_normDouble(x)
%I_NORMDOUBLE  Normalisasi ke [0 1] double utk im2uint8 (tahan tipe non-uint8).
d = double(x);
mn = min(d(:)); mx = max(d(:));
if mx > mn; d = (d - mn) / (mx - mn); else; d = zeros(size(d)); end
end
