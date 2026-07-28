function info = PIVlab_automasi_dropframes(matFile, dropVec)
%PIVLAB_AUTOMASI_DROPFRAMES  Buang frame (pasangan) dari .mat hasil PIVlab(+GS/EXIF).
%
%   info = PIVlab_automasi_dropframes(matFile, dropVec)
%
%   Membuang frame berindeks `dropVec` (1-based, terhadap daftar frame PENUH)
%   dari SEMUA variabel per-frame di berkas .mat, lalu menyimpannya ulang
%   (-v7.3). Berkas gambar TIDAK disentuh — hanya output PIV yang dirapikan.
%
%   Yang dilakukan:
%     - cell PIV per-frame {nP x 1} (x,y,u_*,v_*,typevector_*,velocity_magnitude,
%       strain_rate,correlation_map, dll.) di-subset ke frame yang dipertahankan;
%     - bg_images_index (latar GS per-frame) di-subset, blob yatim DIPANGKAS &
%       di-renumber (bg_images_blobs);
%     - frame_dt_s & frame_time_abs di-subset; frame_time_s DIHITUNG ULANG
%       sebagai waktu kumulatif frame tersisa (gap dari frame dibuang dirapatkan);
%     - automasi_settings.num_pairs & exif_meta.nFrames/n_dt_* diperbarui;
%     - jejak qpiv_dropped_frames ditulis.
%   Variabel non-per-frame (calxy, units, information, bg_images_format/quality,
%   experiment_geometry, exif_table, dll.) DIBIARKAN apa adanya.
%
%   KELUARAN  info: struct .nKept .nDrop .nBefore .dropped
%
%   Lihat juga: PIVlab_automasi_batch_V4, PIVlab_automasi_qpiv

matFile = char(matFile);
if ~isfile(matFile)
	error('PIVlab_automasi_dropframes:noFile', 'Berkas .mat tidak ditemukan:\n%s', matFile);
end

S = load(matFile);
if ~isfield(S, 'x') || ~iscell(S.x)
	error('PIVlab_automasi_dropframes:noX', ...
		'Variabel per-frame ''x'' (cell) tidak ditemukan di %s', matFile);
end
nP = numel(S.x);

dropVec = unique(round(double(dropVec(:))));
dropVec = dropVec(dropVec >= 1 & dropVec <= nP);
keep = true(nP, 1); keep(dropVec) = false;
nKeep = nnz(keep);
if nKeep < 1
	error('PIVlab_automasi_dropframes:empty', ...
		'Semua %d frame akan terbuang — output dibatalkan.', nP);
end
if isempty(dropVec)
	info = struct('nKept', nP, 'nDrop', 0, 'nBefore', nP, 'dropped', []);
	return;   % tak ada yang dibuang -> tak menyentuh berkas
end

% --- variabel cell per-frame ---
cellVars = {'x','y','u_original','v_original','typevector_original', ...
	'u_filtered','v_filtered','typevector_filtered','u_smoothed','v_smoothed', ...
	'vorticity','velocity_magnitude','u_component','v_component','divergence', ...
	'q_criterion','shear_rate','strain_rate','LIC','vectorangle','correlation_map'};
for i = 1:numel(cellVars)
	vn = cellVars{i};
	if isfield(S, vn) && iscell(S.(vn)) && numel(S.(vn)) == nP
		S.(vn) = S.(vn)(keep);
	end
end

% --- GS index per-frame + remap/pangkas blob yatim ---
if isfield(S, 'bg_images_index') && numel(S.bg_images_index) == nP
	idxKept = S.bg_images_index(keep);
	if isfield(S, 'bg_images_blobs') && ~isempty(S.bg_images_blobs)
		[idxKept, S.bg_images_blobs] = i_remap_blobs(idxKept, S.bg_images_blobs);
	end
	S.bg_images_index = idxKept;
end

% --- waktu EXIF per-frame ---
if isfield(S, 'frame_dt_s') && numel(S.frame_dt_s) == nP
	S.frame_dt_s = S.frame_dt_s(keep);
	if isfield(S, 'frame_time_s')
		S.frame_time_s = i_recompute_time(S.frame_dt_s);   % rapatkan gap
	end
end
if isfield(S, 'frame_time_abs') && numel(S.frame_time_abs) == nP
	S.frame_time_abs = S.frame_time_abs(keep);
end

% --- bookkeeping skalar ---
if isfield(S, 'automasi_settings') && isstruct(S.automasi_settings)
	S.automasi_settings.num_pairs      = nKeep;
	S.automasi_settings.dropped_frames = dropVec(:)';
	S.automasi_settings.dropped_by     = 'PIVlab_automasi_dropframes';
end
if isfield(S, 'exif_meta') && isstruct(S.exif_meta)
	S.exif_meta.nFrames = nKeep;
	if isfield(S, 'frame_dt_s')
		S.exif_meta.n_dt_valid = sum(isfinite(S.frame_dt_s));
		S.exif_meta.n_dt_nan   = sum(~isfinite(S.frame_dt_s));
	end
	S.exif_meta.compacted = true;
end
S.qpiv_dropped_frames = dropVec(:)';     %#ok<STRNU>

save(matFile, '-struct', 'S', '-v7.3');
info = struct('nKept', nKeep, 'nDrop', nP - nKeep, 'nBefore', nP, 'dropped', dropVec(:)');
end

%% ========================= SUBFUNGSI =====================
function [idx2, blobs2] = i_remap_blobs(idx, blobs)
%I_REMAP_BLOBS  Subset blob ke yang masih dipakai + renumber index (0 = kosong).
idx = double(idx(:));
nz  = idx > 0;
used = unique(idx(nz));
used = used(used >= 1 & used <= numel(blobs));
if isempty(used)
	blobs2 = blobs([]);
	idx2 = zeros(size(idx), 'uint32');
	return;
end
blobs2 = blobs(used);
newOf = zeros(max(used), 1);
newOf(used) = 1:numel(used);
idx2 = zeros(size(idx), 'uint32');
keepable = nz & ismember(idx, used);
idx2(keepable) = uint32(newOf(idx(keepable)));
end

function ts = i_recompute_time(dtk)
%I_RECOMPUTE_TIME  Waktu kumulatif (detik) di awal tiap frame TERSISA, gap
%   dirapatkan: ts(1)=0; ts(m)=ts(m-1)+dt(m-1). dt NaN -> tak menambah.
dtk = double(dtk(:));
n = numel(dtk);
ts = zeros(n, 1);
for m = 2:n
	inc = dtk(m-1); if ~isfinite(inc); inc = 0; end
	ts(m) = ts(m-1) + inc;
end
end
