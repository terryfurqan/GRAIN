function v = pabVersion()
%PABVERSION  Versi build PAB (commit git pendek + tanggal) untuk title bar.
%
%   v = pivui.pabVersion()
%
%   Mengembalikan struct ringkas identitas build supaya user TAHU salinan mana
%   yang sedang jalan (mis. di PC-2 setelah UPDATE_BERSIH.bat = git reset --hard
%   origin/main). Sumber = git commit HEAD folder repo tempat berkas ini berada:
%       .hash   commit pendek (mis 'a1b2c3d') | '' bila git tak ada
%       .date   tanggal commit 'yyyy-MM-dd HH:mm' | ''
%       .branch nama branch | ''
%       .dirty  true bila working tree ada perubahan belum di-commit
%       .label  string siap-pakai, mis 'v a1b2c3d · 2026-07-03 10:20' atau
%               'v a1b2c3d* (dirty)'; 'v (tanpa-git)' bila git tak terbaca.
%
%   Di-CACHE (persistent) — git dipanggil sekali per sesi MATLAB. Untuk title
%   bar dipakai lewat pivui.titleWithVersion(judul).
%
%   Catatan: PC-2 read-only (reset --hard) -> selalu bersih, hash = origin/main.
%   Kalau .dirty true di mesin dev, artinya ada edit belum di-commit/push.

    persistent CACHE
    if ~isempty(CACHE)
        v = CACHE; return;
    end

    v = struct('hash','', 'date','', 'branch','', 'dirty',false, 'label','v (tanpa-versi)');

    repoDir = i_repoDir();

    % (1) SUMBER UTAMA: berkas VERSION.txt ('<hash> | <yyyy-MM-dd HH:mm>') yang
    %     di-commit ke repo & di-update git hook pre-commit. Baca file = INSTAN,
    %     NOL system(git) di jalur GUI -> tak ada risiko hang saat window buka.
    %     PC-2 (reset --hard origin/main) selalu dapat VERSION.txt commit terkini.
    if ~isempty(repoDir)
        vt = i_readVersionFile(fullfile(repoDir, 'VERSION.txt'));
        if ~isempty(vt.hash)
            v.hash = vt.hash; v.date = vt.date;
            v.label = i_mkLabel(v);
            CACHE = v; return;
        end
    end

    % (2) FALLBACK: git live (bila VERSION.txt tak ada — mis. repo lama). Dibatasi
    %     sekali & di-cache; system(git) ~0.3s. Tetap aman krn cuma fallback.
    if ~isempty(repoDir)
        hash = i_git(repoDir, 'rev-parse --short HEAD');
        if ~isempty(hash)
            v.hash  = hash;
            v.date  = i_isoToShort(i_git(repoDir, 'log -1 --format=%ci'));
            v.dirty = ~isempty(i_git(repoDir, 'status --porcelain'));
            v.label = i_mkLabel(v);
        end
    end

    CACHE = v;
end

%% ===================================================================
function d = i_repoDir()
%I_REPODIR  Folder repo (root PAB) = 2 tingkat di atas berkas ini
%   (pivcore_lib/+pivui/pabVersion.m -> pivcore_lib -> PAB).
    d = '';
    try
        here = fileparts(mfilename('fullpath'));         % .../pivcore_lib/+pivui
        d = fileparts(fileparts(here));                  % .../PAB
        if ~isfolder(d); d = ''; end
    catch
        d = '';
    end
end

function out = i_git(repoDir, argstr)
%I_GIT  Jalankan 'git -C <repo> <argstr>' -> keluaran terpangkas ('' bila gagal).
    out = '';
    try
        cmd = sprintf('git -C "%s" %s', repoDir, argstr);
        [st, res] = system(cmd);
        if st == 0
            out = strtrim(res);
            % ambil baris pertama utk perintah non-multiline.
            nl = find(out == newline, 1);
            if ~isempty(nl) && ~contains(argstr, 'status')
                out = strtrim(out(1:nl-1));
            end
        end
    catch
        out = '';
    end
end

function s = i_isoToShort(iso)
%I_ISOTOSHORT  '2026-07-03 10:20:15 +0700' -> '2026-07-03 10:20'. '' bila kosong.
    s = '';
    iso = strtrim(char(iso));
    if numel(iso) >= 16; s = iso(1:16); end
end

function lbl = i_mkLabel(v)
%I_MKLABEL  Rakit label versi dari struct v (hash/date/dirty).
    star = ''; if v.dirty; star = '*'; end
    if ~isempty(v.date)
        lbl = sprintf('v %s%s · %s', v.hash, star, v.date);
    else
        lbl = sprintf('v %s%s', v.hash, star);
    end
end

function vt = i_readVersionFile(path)
%I_READVERSIONFILE  Baca VERSION.txt '<hash> | <yyyy-MM-dd HH:mm>'.
    vt = struct('hash','', 'date','');
    try
        if ~isfile(path); return; end
        txt = strtrim(fileread(path));
        nl = find(txt == newline, 1); if ~isempty(nl); txt = strtrim(txt(1:nl-1)); end
        parts = strsplit(txt, '|');
        vt.hash = strtrim(parts{1});
        if numel(parts) >= 2; vt.date = strtrim(parts{2}); end
    catch
    end
end
