function cleaner = i_guardSidecars(df)
%I_GUARDSIDECARS  Lindungi data SIDECAR milik satu MAT fixture `df` selama test.
%   Test GRAIN4/5/6 memakai FIXTURE NYATA (data user, mis. EXP_coll/P-CON-4cm-F) &
%   menulis/menghapus sidecar (_desc.json, _faults.json, _faultinterp.json, dst) ->
%   BISA MERUSAK data user. Helper ini mem-BACKUP semua sidecar (file KECIL, BUKAN
%   .mat data mentah >100 MB) ke tempdir, lalu MENGEMBALIKANNYA saat `cleaner`
%   di-clear (onCleanup) — apa pun yang terjadi di test (lulus/gagal/crash).
%
%   PEMAKAIAN (di awal blok yang menyentuh fixture, SEBELUM load/tulis):
%       guard = i_guardSidecars(df);   %#ok<NASGU>   % restore otomatis saat keluar
%
%   ATURAN: HANYA sidecar (base + akhiran dikenal) yang dibackup. File .mat DATA
%   MENTAH (>100 MB / pola blob PIV) TAK PERNAH disentuh. Bila df tak valid -> no-op.

    cleaner = onCleanup(@() true);   % default no-op
    if nargin < 1 || isempty(df) || ~ischar(df), return; end
    [d, base] = fileparts(df);
    if isempty(d), d = pwd; end
    if ~isfolder(d), return; end

    % Kumpulkan SIDECAR milik `base`: semua file `<base>*` KECUALI .mat data mentah.
    listing = dir(fullfile(d, [base '*']));
    snap = struct('path',{},'existed',{},'bytes',{});
    for i = 1:numel(listing)
        if listing(i).isdir, continue; end
        nm = listing(i).name;
        p  = fullfile(d, nm);
        if ~i_isSidecar(p), continue; end   % lewati .mat data & non-sidecar
        s = struct('path', p, 'existed', true, 'bytes', []);
        try, s.bytes = i_readBytes(p); catch, s.existed = false; end
        snap(end+1) = s; %#ok<AGROW>
    end
    % Catat juga sidecar yang BELUM ada tapi mungkin DIBUAT test (supaya dihapus saat
    % restore). Akhiran kanonik yang lazim ditulis test.
    for suf = i_knownSuffixes()
        p = fullfile(d, [base suf{1}]);
        if any(strcmp({snap.path}, p)), continue; end
        snap(end+1) = struct('path', p, 'existed', false, 'bytes', []); %#ok<AGROW>
    end

    cleaner = onCleanup(@() i_restore(snap));
end

% ---------------------------------------------------------------------
function tf = i_isSidecar(p)
%I_ISSIDECAR  TRUE bila `p` file SIDECAR (aman dibackup), FALSE bila .mat DATA
%   mentah (>100 MB atau .mat non-sidecar) / file besar tak dikenal.
    tf = false;
    [~, ~, ext] = fileparts(p);
    ext = lower(ext);
    di = dir(p); if isempty(di), return; end
    bytes = di(1).bytes;
    % .mat: hanya sidecar .mat KECIL (mis. _axpot.mat/_autopot.mat) yang aman —
    % TAPI demi keamanan mutlak, .mat >100 MB PASTI data mentah -> JANGAN sentuh.
    if strcmp(ext, '.mat')
        if bytes > 100*1024*1024, tf = false; return; end   % data mentah -> lindungi
        % .mat kecil: tetap SKIP (bukan target test JSON; hindari risiko).
        tf = false; return;
    end
    % Sidecar JSON/teks kecil -> aman. Batasi ukuran wajar (<50 MB) sbg jaring.
    if any(strcmp(ext, {'.json', '.txt'})) && bytes < 50*1024*1024
        tf = true; return;
    end
end

function sufs = i_knownSuffixes()
%I_KNOWNSUFFIXES  Akhiran sidecar kanonik yang lazim DITULIS/DIHAPUS test GRAIN.
    sufs = {'_desc.json','_faults.json','_faultinterp.json','_faultgeom.json', ...
            '_potdata.json','_comments.json','_axcal.json','_hb.json','_link.json', ...
            '_autopot.json'};
end

function b = i_readBytes(p)
    fid = fopen(p, 'r');
    if fid < 0, error('i_guardSidecars:open', 'tak bisa baca %s', p); end
    c = onCleanup(@() fclose(fid));
    b = fread(fid, inf, '*uint8');
end

function i_writeBytes(p, b)
    fid = fopen(p, 'w');
    if fid < 0, return; end
    c = onCleanup(@() fclose(fid));
    fwrite(fid, b, 'uint8');
end

function i_restore(snap)
%I_RESTORE  Kembalikan tiap sidecar ke keadaan awal: ada -> tulis-ulang byte asli;
%   TAK ada semula -> hapus bila test membuatnya.
    for i = 1:numel(snap)
        s = snap(i);
        try
            if s.existed && ~isempty(s.bytes)
                i_writeBytes(s.path, s.bytes);
            elseif ~s.existed
                if isfile(s.path), delete(s.path); end
            end
        catch
        end
    end
end
