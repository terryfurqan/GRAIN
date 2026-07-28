classdef pab4TaperInterp
%PAB4TAPERINTERP  Sidecar TRACK interpolasi TAPER lengkap per-frame (evolusi
%   kemiringan topografi) di `<base>_taperinterp.json`. TERPISAH dari tabel
%   DESKRIPSI (yg cuma keyframe) & dari `_faultinterp.json` (bidang sesar).
%
%   DUA KEBUTUHAN BERBEDA (keputusan user 2026-07-18):
%     - KERJA  : track taper LENGKAP tiap frame (buat plot evolusi) -> sidecar ini.
%     - LAPORAN: nilai taper per-POI/DX -> JSON commit (bukan file ini).
%
%   Struktur & matematika 100% mewarisi pivcore.io.pab4Interp (lerp/buildSamples/
%   setTrackFor/…); kelas ini HANYA mengganti path + label format supaya sidecar
%   taper terpisah dari sidecar bidang sesar. Samples: garis taper = 2 vertex.

    methods (Static)

        function p = dataPath(dataFile)
        %DATAPATH  <dir>/<base>_taperinterp.json untuk MAT PIV dataFile.
            p = '';
            if isempty(dataFile) || ~ischar(dataFile), return; end
            [d, base] = fileparts(dataFile);
            if isempty(d), d = pwd; end
            p = fullfile(d, sprintf('%s_taperinterp.json', base));
        end

        function doc = emptyDoc(dataFile)
        %EMPTYDOC  Kerangka dokumen kosong (label taper).
            if nargin < 1, dataFile = ''; end
            [~, base, ext] = fileparts(char(dataFile));
            doc = struct();
            doc.formatName    = 'PAB4 Taper Interpolation Track';
            doc.formatVersion = 1;
            doc.source        = [base ext];
            doc.tracks        = {};
        end

        function doc = read(dataFile)
        %READ  Baca & normalisasi sidecar taper. Absen/rusak -> emptyDoc.
            p = pivcore.io.pab4TaperInterp.dataPath(dataFile);
            if isempty(p) || ~isfile(p)
                doc = pivcore.io.pab4TaperInterp.emptyDoc(dataFile); return;
            end
            try
                raw = jsondecode(fileread(p));
            catch ME
                warning('pivcore:pab4TaperInterp:read', ...
                    'Gagal baca/parse %s (%s); dokumen kosong.', p, ME.message);
                doc = pivcore.io.pab4TaperInterp.emptyDoc(dataFile); return;
            end
            % reuse normalizer pab4Interp (struktur tracks identik), lalu benahi label.
            doc = pivcore.io.pab4Interp.normalizeDoc(raw, dataFile);
            e = pivcore.io.pab4TaperInterp.emptyDoc(dataFile);
            doc.formatName = e.formatName;
        end

        function write(dataFile, doc)
        %WRITE  Tulis ATOMIC ke `<base>_taperinterp.json`.
            p = pivcore.io.pab4TaperInterp.dataPath(dataFile);
            if isempty(p)
                error('pivcore:pab4TaperInterp:noPath', ...
                    'Tak bisa menentukan path _taperinterp untuk: %s', dataFile);
            end
            doc = pivcore.io.pab4Interp.prepForEncode(doc);
            txt = jsonencode(doc, 'PrettyPrint', true);
            tmp = [p '.tmp'];
            fid = fopen(tmp, 'w');
            if fid < 0, error('pivcore:pab4TaperInterp:open','Tak bisa buka %s.', tmp); end
            cleaner = onCleanup(@() pivcore.io.pab4TaperInterp.cleanupTmp(tmp)); %#ok<NASGU>
            fwrite(fid, txt, 'char'); fclose(fid);
            [ok, msg] = movefile(tmp, p, 'f');
            if ~ok, error('pivcore:pab4TaperInterp:move','Gagal pindah tmp->final (%s): %s', p, msg); end
        end

        function cleanupTmp(tmp)
            try, if isfile(tmp), delete(tmp); end, catch, end
        end

        % Accessor DIWARISI dari pab4Interp (struktur tracks sama):
        function doc = setTrackFor(doc, psgId, fNum, samples, keyFrames)
            doc = pivcore.io.pab4Interp.setTrackFor(doc, psgId, fNum, samples, keyFrames);
        end
        function doc = clearTrackFor(doc, psgId, fNum)
            doc = pivcore.io.pab4Interp.clearTrackFor(doc, psgId, fNum);
        end
        function entry = trackFor(doc, psgId, fNum)
            entry = pivcore.io.pab4Interp.trackFor(doc, psgId, fNum);
        end
    end
end
