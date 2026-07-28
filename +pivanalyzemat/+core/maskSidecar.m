classdef maskSidecar
%MASKSIDECAR  I/O resep masking di berkas SIDECAR terpisah (JSON), di samping
%   MAT PREP — TANPA menyentuh blob RAW mentah.
%
%   PRINSIP (keputusan user): GRAINMASK hanya PENYEMAT RESEP. Menyimpan resep
%   masking (kotak/polygon) TAK BOLEH menulis ulang file MAT PREP yang bisa
%   1,4 GB. Karena itu resep hidup di berkas kecil `<nama>_mask.json` di folder
%   yang sama. MAT PREP dari GRAIN1 dibiarkan APA ADANYA (nol tulis besar).
%
%   Satu sidecar per-eksperimen dipakai BERSAMA:
%     - GRAINMASK1 (kotak persegi, sekarang)   -> field `v1_rect`
%     - GRAINMASK2 (polygon + keyframe, nanti) -> field `v2_poly`
%
%   SKEMA `pab_masking_v1`:
%     { "schema":"pab_masking_v1", "matfile":"<nama>.mat",
%       "v1_rect": <struct maskRect: enabled/fill/boxes> | null,
%       "v2_poly": null }
%
%   GRAIN2 (produksi) & decoder (readMatFrame/unpackMat) membaca resep lewat
%   pivanalyzemat.core.prepBlobStore.readMasking yang MENDAHULUKAN sidecar ini.
%
%   Lihat juga: pivanalyzemat.core.maskRect (normalisasi/validasi),
%               pivanalyzemat.core.prepBlobStore, GRAINMASK

	methods (Static)

		function p = path(matPath)
		%PATH  Path sidecar '<mat-tanpa-ext>_mask.json' utk sebuah MAT PREP.
			matPath = char(matPath);
			[d, base, ~] = fileparts(matPath);
			p = fullfile(d, [base '_mask.json']);
		end

		function tf = has(matPath)
		%HAS  true bila sidecar resep ada.
			tf = isfile(pivanalyzemat.core.maskSidecar.path(matPath));
		end

		function m = read(matPath)
		%READ  Baca resep GRAINMASK1 (v1_rect) dari sidecar -> struct maskRect
		%   ter-normalisasi. [] bila sidecar tak ada / kosong / rusak.
			m = [];
			sp = pivanalyzemat.core.maskSidecar.path(matPath);
			if ~isfile(sp); return; end
			try
				txt = fileread(sp);
				S = jsondecode(txt);
			catch
				return;
			end
			if ~isstruct(S); return; end
			raw = [];
			if isfield(S, 'v1_rect') && ~isempty(S.v1_rect) && isstruct(S.v1_rect)
				raw = S.v1_rect;
			end
			if isempty(raw); return; end
			% jsondecode bikin boxes jadi struct-array bila seragam, atau cell.
			raw = pivanalyzemat.core.maskSidecar.i_coerceBoxes(raw);
			try
				m = pivanalyzemat.core.maskRect.normalize(raw);
			catch
				m = [];
			end
		end

		function ok = write(matPath, masking)
		%WRITE  Tulis resep GRAINMASK1 (v1_rect) ke sidecar JSON. Instan (berkas
		%   kecil), MAT PREP tak disentuh. Pertahankan v2_poly bila sidecar sudah
		%   ada (jangan hapus resep GRAINMASK2). true bila sukses.
			ok = false;
			matPath = char(matPath);
			sp = pivanalyzemat.core.maskSidecar.path(matPath);
			try
				% muat sidecar lama (pertahankan v2_poly), else struct baru.
				doc = struct('schema','pab_masking_v1', ...
					'matfile', i_leaf(matPath), 'v1_rect', [], 'v2_poly', []);
				if isfile(sp)
					try
						old = jsondecode(fileread(sp));
						if isstruct(old) && isfield(old,'v2_poly'); doc.v2_poly = old.v2_poly; end
					catch
					end
				end
				% normalisasi resep sebelum tulis (buang kotak invalid).
				if ~isempty(masking)
					doc.v1_rect = pivanalyzemat.core.maskRect.normalize(masking);
				end
				txt = jsonencode(doc, 'PrettyPrint', true);
				fid = fopen(sp, 'w');
				if fid < 0; return; end
				fwrite(fid, txt, 'char');
				fclose(fid);
				ok = true;
			catch
				ok = false;
			end
		end

		function ok = remove(matPath)
		%REMOVE  Hapus sidecar (mis. saat masking dinonaktifkan total). true bila
		%   terhapus atau memang tak ada.
			ok = true;
			sp = pivanalyzemat.core.maskSidecar.path(matPath);
			try
				if isfile(sp); delete(sp); end
			catch
				ok = false;
			end
		end

		function p = readPoly(matPath)
		%READPOLY  Baca resep GRAINMASK2 (v2_poly) dari sidecar -> struct maskPoly
		%   ter-normalisasi. [] bila tak ada / kosong / rusak.
			p = [];
			sp = pivanalyzemat.core.maskSidecar.path(matPath);
			if ~isfile(sp); return; end
			try
				S = jsondecode(fileread(sp));
			catch
				return;
			end
			if ~isstruct(S) || ~isfield(S,'v2_poly') || isempty(S.v2_poly); return; end
			try
				p = pivanalyzemat.core.maskPoly.normalize(S.v2_poly);
			catch
				p = [];
			end
		end

		function ok = writePoly(matPath, poly)
		%WRITEPOLY  Tulis resep GRAINMASK2 (v2_poly) ke sidecar. Pertahankan v1_rect
		%   bila sidecar sudah ada (jangan hapus resep kotak). true bila sukses.
			ok = false; matPath = char(matPath);
			sp = pivanalyzemat.core.maskSidecar.path(matPath);
			try
				doc = struct('schema','pab_masking_v1', ...
					'matfile', i_leaf(matPath), 'v1_rect', [], 'v2_poly', []);
				if isfile(sp)
					try
						old = jsondecode(fileread(sp));
						if isstruct(old) && isfield(old,'v1_rect'); doc.v1_rect = old.v1_rect; end
					catch
					end
				end
				if ~isempty(poly)
					doc.v2_poly = pivanalyzemat.core.maskPoly.normalize(poly);
				end
				txt = jsonencode(doc, 'PrettyPrint', true);
				fid = fopen(sp,'w'); if fid<0; return; end
				fwrite(fid, txt, 'char'); fclose(fid);
				ok = true;
			catch
				ok = false;
			end
		end

	end

	methods (Static, Access = private)

		function raw = i_coerceBoxes(raw)
		%I_COERCEBOXES  Samakan bentuk boxes hasil jsondecode -> struct-array 1xN
		%   dgn field yg diharapkan maskRect (rect_first/rect_last/frame_*/keyframes).
			empt = struct('rect_first',{},'rect_last',{}, ...
				'frame_first',{},'frame_last',{},'keyframes',{});
			if ~isfield(raw, 'boxes') || isempty(raw.boxes)
				raw.boxes = empt;
				return;
			end
			b = raw.boxes;
			if iscell(b)
				% cell of structs -> struct array
				bb = empt;
				for i = 1:numel(b)
					bi = b{i};
					bb(end+1) = pivanalyzemat.core.maskSidecar.i_oneBox(bi); %#ok<AGROW>
				end
				raw.boxes = bb;
			elseif isstruct(b)
				bb = empt;
				for i = 1:numel(b)
					bb(end+1) = pivanalyzemat.core.maskSidecar.i_oneBox(b(i)); %#ok<AGROW>
				end
				raw.boxes = bb;
			end
		end

		function s = i_oneBox(bi)
		%I_ONEBOX  Pastikan satu box punya field lengkap + vektor baris.
		%   `keyframes` = struct-array {frame_index, rect} (kosong bila tak ada).
			s = struct('rect_first', [], 'rect_last', [], ...
				'frame_first', 1, 'frame_last', 2, ...
				'keyframes', struct('frame_index',{},'rect',{}));
			if isfield(bi,'rect_first'); s.rect_first = double(bi.rect_first(:)).'; end
			if isfield(bi,'rect_last');  s.rect_last  = double(bi.rect_last(:)).';  end
			if isfield(bi,'frame_first') && ~isempty(bi.frame_first); s.frame_first = double(bi.frame_first); end
			if isfield(bi,'frame_last')  && ~isempty(bi.frame_last);  s.frame_last  = double(bi.frame_last);  end
			if isfield(bi,'keyframes')
				s.keyframes = pivanalyzemat.core.maskSidecar.i_coerceKf(bi.keyframes);
			end
		end

		function kf = i_coerceKf(src)
		%I_COERCEKF  Samakan bentuk keyframes hasil jsondecode -> struct-array
		%   {frame_index, rect [x y w h]}. Terima cell ATAU struct-array; buang
		%   yang tak punya frame_index/rect valid (maskRect re-validasi lagi).
			kf = struct('frame_index', {}, 'rect', {});
			if isempty(src); return; end
			for i = 1:numel(src)
				if iscell(src); one = src{i}; else; one = src(i); end
				if ~isstruct(one); continue; end
				fi = []; rc = [];
				if isfield(one,'frame_index') && ~isempty(one.frame_index); fi = double(one.frame_index(1)); end
				if isfield(one,'rect') && ~isempty(one.rect); rc = double(one.rect(:)).'; end
				if isempty(fi) || isempty(rc); continue; end
				kf(end+1) = struct('frame_index', fi, 'rect', rc); %#ok<AGROW>
			end
		end

	end
end

function s = i_leaf(p)
	[~, b, e] = fileparts(char(p));
	s = [b e];
end
