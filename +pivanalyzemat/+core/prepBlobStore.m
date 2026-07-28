classdef prepBlobStore
%PREPBLOBSTORE  Blob-store per-frame untuk MAT PREP (pivprep_single_v1).
%
%   Sumber kebenaran TUNGGAL untuk skema penyimpanan blob RAW yang bisa dibaca
%   PARSIAL. MAT PREP disimpan '-v7' (terkompresi); '-v7' tak mendukung partial-
%   load DI DALAM satu variabel, jadi menaruh semua blob JPEG di `prep.raw.blobs`
%   memaksa dekompresi ratusan MB untuk membaca 1 frame. Solusi (mirror idiom
%   readPivBgPair utk MAT PIV): simpan tiap BLOB UNIK sbg VARIABEL TOP-LEVEL
%   `braw_00001..braw_000M` + indeks kecil `braw_idx`. `load(file,'braw_00042')`
%   hanya membaca 1 blob — blob lain tak disentuh.
%
%   SKEMA (variabel top-level di .mat, di samping `prep` & `pmeta`):
%     braw_idx   struct: .index (N×1 uint32 frame->blob unik, 0=kosong),
%                        .names (N×1 cell, urutan LEKSIKOGRAFIS = urutan frame),
%                        .ext (char, mis '.jpg'), .nUnique (double)
%     braw_NNNNN uint8 vektor byte JPEG tiap blob unik (NNNNN = 1..nUnique, %05d)
%
%   DEDUP DIPERTAHANKAN: `braw_idx.index(k)` menunjuk blob unik (identik dgn
%   semantik `prep.raw.index`). File yang punya store MENGOSONGKAN
%   `prep.raw.blobs={}` (hindari duplikasi ukuran) tapi MEMPERTAHANKAN
%   `prep.raw.index/names/ext` (kompat pembaca lama & metadata).
%
%   Backward-compatible: file lama tanpa `braw_*` tetap dibaca via jalur lama
%   (`prep.raw.blobs`). `upgradeFile` memigrasi file lama in-place sekali.
%
%   Lihat juga: pivanalyzemat.core.readMatFrame, pivanalyzemat.core.unpackMat,
%               pivanalyzemat.core.readPivBgPair, pivprepPackFolder

	methods (Static)

		function nm = varName(u)
		%VARNAME  Nama variabel blob unik ke-u (1-based).
			nm = sprintf('braw_%05d', u);
		end

		function tf = hasStore(matPath)
		%HASSTORE  true bila .mat punya blob-store (variabel 'braw_idx').
			tf = false;
			try
				w = who('-file', char(matPath));
				tf = ismember('braw_idx', w);
			catch
			end
		end

		function idx = readIdx(matPath)
		%READIDX  Muat 'braw_idx' (kecil) — [] bila tak ada. Cek keberadaan var
		%   dulu (who) supaya load tak memunculkan warning "Variable not found"
		%   utk file NORMAL (tanpa store) yg dibaca tiap frame.
			idx = [];
			matPath = char(matPath);
			try
				w = who('-file', matPath);
				if ~ismember('braw_idx', w); return; end
				S = load(matPath, 'braw_idx');
				if isfield(S, 'braw_idx'); idx = S.braw_idx; end
			catch
			end
		end

		function [bytes, name] = readFrameBytes(matPath, k, idx)
		%READFRAMEBYTES  Byte blob frame ke-k (urutan leksikografis) via store.
		%   idx opsional (hasil readIdx) supaya bisa reuse antar-panggilan.
		%   [] bila di luar rentang / tak ada store.
			bytes = uint8([]); name = '';
			matPath = char(matPath);
			if nargin < 3 || isempty(idx); idx = pivanalyzemat.core.prepBlobStore.readIdx(matPath); end
			if isempty(idx) || ~isfield(idx, 'index'); return; end
			N = numel(idx.index);
			if k < 1 || k > N; return; end
			if isfield(idx, 'names') && numel(idx.names) >= k; name = idx.names{k}; end
			u = double(idx.index(k));
			if u < 1; return; end
			vn = pivanalyzemat.core.prepBlobStore.varName(u);
			try
				S = load(matPath, vn);
				if isfield(S, vn); bytes = S.(vn); end
			catch
				bytes = uint8([]);
			end
		end

		function n = numFrames(idx)
		%NUMFRAMES  Jumlah frame dari struct idx (0 bila kosong).
			n = 0;
			if isstruct(idx) && isfield(idx, 'index'); n = numel(idx.index); end
		end

		function vars = packVars(prep)
		%PACKVARS  Bentuk struct variabel store {braw_*, braw_idx} dari prep.raw.
		%   Reuse blob unik + index yang SUDAH dedup di prep.raw (jpeg_dedup_v1).
		%   Urutan frame = sort(names) leksikografis (konsisten unpackMat/PIVlab):
		%   index dipetakan-ulang ke urutan itu supaya braw_idx.index(k) selaras
		%   dgn frame ke-k yang dibaca pembaca.
			vars = struct();
			if ~isstruct(prep) || ~isfield(prep, 'raw'); return; end
			raw = prep.raw;
			if ~isfield(raw, 'names') || isempty(raw.names); return; end
			if ~isfield(raw, 'blobs') || isempty(raw.blobs); return; end

			names0 = raw.names(:);
			idx0   = double(raw.index(:));
			blobs  = raw.blobs;
			[namesS, ord] = sort(names0);
			idxS = idx0(ord);                 % index blob unik dalam urutan frame

			nU = numel(blobs);
			for u = 1:nU
				vars.(pivanalyzemat.core.prepBlobStore.varName(u)) = blobs{u};
			end
			ext = '.jpg';
			if isfield(raw, 'ext') && ~isempty(raw.ext); ext = char(raw.ext); end
			if ~startsWith(ext, '.'); ext = ['.' ext]; end
			vars.braw_idx = struct('index', uint32(idxS), 'names', {namesS(:)}, ...
				'ext', ext, 'nUnique', nU);
		end

		function ok = writeStore(matPath, prep)
		%WRITESTORE  Tulis store {braw_*, braw_idx} ke .mat via -append (blob lain
		%   tak disentuh). true bila sukses. Pemanggil bertanggung jawab
		%   mengosongkan prep.raw.blobs di variabel `prep` terpisah bila mau.
			ok = false;
			try
				vars = pivanalyzemat.core.prepBlobStore.packVars(prep); %#ok<NASGU>
				if ~isfield(vars, 'braw_idx'); return; end
				save(char(matPath), '-struct', 'vars', '-append');
				ok = true;
			catch
				ok = false;
			end
		end

		function m = readMasking(matPath, allowSlow)
		%READMASKING  Baca resep masking (kotak). Urutan sumber:
		%   (1) SIDECAR '<nama>_mask.json' (pivanalyzemat.core.maskSidecar) —
		%       jalur UTAMA sekarang; berkas kecil, MAT PREP tak disentuh.
		%   (2) 'pmasking' in-file — warisan iterasi lalu (file yg terlanjur).
		%   (3) 'prep.masking' warisan — HANYA bila allowSlow (load prep penuh).
		%
		%   allowSlow (default false): bila false, JANGAN PERNAH load 'prep' penuh
		%   (dekompresi ratusan MB). Sidecar & pmasking selalu murah. prep.masking
		%   hanya disentuh saat user MEMBUKA eksperimen (sekali).
			if nargin < 2 || isempty(allowSlow); allowSlow = false; end
			m = [];
			matPath = char(matPath);

			% (1) SIDECAR — sumber kebenaran baru.
			try
				m = pivanalyzemat.core.maskSidecar.read(matPath);
			catch
				m = [];
			end
			if ~isempty(m); return; end

			% (2) pmasking in-file (warisan).
			try
				w = who('-file', matPath);
			catch
				w = {};
			end
			if ismember('pmasking', w)
				try
					S = load(matPath, 'pmasking');
					if isfield(S, 'pmasking') && ~isempty(S.pmasking); m = S.pmasking; return; end
				catch
				end
			end

			% (3) prep.masking warisan — mahal, hanya bila diizinkan.
			if ~allowSlow; return; end
			try
				S = load(matPath, 'prep');
				if isfield(S, 'prep') && isfield(S.prep, 'masking')
					m = S.prep.masking;
				end
			catch
			end
		end

		function ok = writeMasking(matPath, masking)
		%WRITEMASKING  Tulis resep masking ke SIDECAR '<nama>_mask.json'
		%   (pivanalyzemat.core.maskSidecar) — berkas kecil, MAT PREP (blob RAW)
		%   TAK DISENTUH. Instan & non-destruktif. true bila sukses.
			ok = false;
			try
				ok = pivanalyzemat.core.maskSidecar.write(matPath, masking);
			catch
				ok = false;
			end
		end

		function ok = upgradeFile(matPath)
		%UPGRADEFILE  Migrasi file LAMA (blob di prep.raw.blobs) -> blob-store,
		%   in-place, SEKALI. Kosongkan prep.raw.blobs (pindah ke braw_*),
		%   pertahankan prep.raw.index/names/ext. Non-destruktif thd isi frame
		%   (byte blob identik). true bila store terbentuk (atau sudah ada).
		%   false bila gagal tulis (mis. read-only) -> pemanggil pakai jalur lama.
		%
		%   PERF: tulis ulang FILE PENUH dgn '-v6' (TANPA kompresi). Blob JPEG
		%   SUDAH terkompresi -> gzip '-v7' di atasnya hampir tak menghemat ukuran
		%   (±7%) tapi makan 15-20 detik CPU utk file 500 MB. '-v6' menulis dalam
		%   ~0,2 detik (80x lebih cepat). save '-append' JUSTRU lambat karena
		%   mempertahankan kompresi '-v7' file asli. Kita sudah load semua yg perlu,
		%   jadi rewrite penuh -v6 = jalur tercepat.
			ok = false;
			matPath = char(matPath);
			try
				if pivanalyzemat.core.prepBlobStore.hasStore(matPath); ok = true; return; end
				% Muat SEMUA variabel (mis. pmeta/pmasking warisan) supaya tak hilang
				% saat file ditulis-ulang. 'prep' pasti ada (berkas PREP).
				S = load(matPath);
				if ~isfield(S, 'prep') || ~isfield(S.prep, 'raw'); return; end
				raw = S.prep.raw;
				if ~isfield(raw, 'blobs') || isempty(raw.blobs); return; end  % tak ada blob utk dipindah

				vars = pivanalyzemat.core.prepBlobStore.packVars(S.prep);
				if ~isfield(vars, 'braw_idx'); return; end

				% Gabung: semua var lama (prep tipis + pmeta/pmasking dsb) + store.
				S.prep.raw.blobs = {};                 % prep tipis (blob pindah ke store)
				if ~isfield(S, 'pmeta') || isempty(S.pmeta)
					S.pmeta = pivanalyzemat.core.prepMeta(S.prep);
				end
				fn = fieldnames(vars);
				for i = 1:numel(fn); S.(fn{i}) = vars.(fn{i}); end  % braw_* + braw_idx

				save(matPath, '-struct', 'S', '-v6');  % rewrite penuh, cepat
				ok = true;
			catch
				ok = false;
			end
		end

	end
end
