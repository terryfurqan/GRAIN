classdef psgId
%PSGID  ID GARIS PSG STABIL dari geometri garis — supaya catatan & data POT
%   "nyambung" saat eksperimen yang sama dibuka ulang (poin-6 GRAIN4_PLAN).
%
%   Observasi POT selalu dilakukan pada SATU garis PSG. Geser garis = observasi
%   lain. Maka tiap garis butuh ID yang STABIL: garis yang sama (dibuka ulang)
%   harus menghasilkan id yang SAMA, garis berbeda harus berbeda. ID inilah yang
%   menjadi kunci penyimpanan di `_potdata.json` (psgLines[].id) dan judul seksi
%   `_notes.md` (## Garis POT: <id>).
%
%   DUA JENIS ID (sesuai field psgLines[].frac):
%     - "fracNNN"  — garis OTOMATIS pada fraksi tinggi tertentu (frac=0.70 ->
%                    "frac070"). Stabil lintas-buka karena frac deterministik.
%                    Lebar-x boleh beda antar-eksperimen; id tetap sama (id
%                    bersifat per-eksperimen, scope di dalam 1 .mat).
%     - "geom_..." — garis KUSTOM (ditarik/digeser pengguna). ID dibangun dari
%                    KOORDINAT garis yang dibulatkan ke kelipatan TOLPX (=50 px)
%                    supaya geseran kecil-menengah TAK memutus identitas. Ujung
%                    garis di-URUT (flip p1<->p2 -> id sama).
%
%   Bentuk "geom_" sengaja TERBACA (koordinat bulat), bukan hash buram: nol
%   tabrakan, mudah di-debug, dan valid sebagai kunci JSON / judul markdown.
%
%   API:
%     id = pivcore.pot.psgId.fromLine(line)         % line.p1/p2 (+ line.frac opsional)
%     id = pivcore.pot.psgId.fromLine(line, frac)   % frac eksplisit (NaN/[]=geom)
%     id = pivcore.pot.psgId.fromFrac(frac)         % "frac070" dari 0.70
%     id = pivcore.pot.psgId.fromGeom(p1, p2)       % "geom_x1_y1_x2_y2"
%     tf = pivcore.pot.psgId.isFrac(id)
%     [p1,p2] = pivcore.pot.psgId.geomCoords(id)    % balik koordinat dari geom id ([] bila bukan geom)
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivcore/+pot/psgId.m

    properties (Constant)
        % TOLPX = toleransi pembulatan koordinat garis kustom (piksel). Koordinat
        % ujung dibulatkan ke kelipatan TOLPX SEBELUM jadi token id, jadi geseran
        % < TOLPX/2 TAK mengubah id. Dulu 1 px -> praktis tak melindungi apa pun:
        % geseran ROI beberapa piksel (interaksi tak sengaja / re-snap render)
        % langsung bikin id baru -> semua baris DESC ber-psgId lama JADI YATIM ->
        % tabel kosong -> Save menimpa kosong -> DATA HILANG (insiden P-CON-F1
        % 2026-07-17). Dinaikkan ke 50 px: geseran wajar (belasan px) tetap id
        % sama; garis PSG berbeda (umumnya terpisah ratusan px per-sisi) tetap
        % dibedakan. Lihat memori [[multi-psg-per-side-scoping]].
        TOLPX = 50;
    end

    methods (Static)

        % ================================================================
        function id = fromLine(line, frac)
        %FROMLINE  ID stabil dari struct garis. Bila `frac` valid (0..1) ATAU
        %   line.frac valid -> id "fracNNN". Selain itu -> id "geom_" dari p1/p2.
            if nargin < 2
                frac = NaN;
                if isstruct(line) && isfield(line,'frac'), frac = line.frac; end
            end
            if pivcore.pot.psgId.validFrac(frac)
                id = pivcore.pot.psgId.fromFrac(frac); return;
            end
            if ~isstruct(line) || ~isfield(line,'p1') || ~isfield(line,'p2')
                id = 'geom_NA'; return;
            end
            id = pivcore.pot.psgId.fromGeom(line.p1, line.p2);
        end


        % ================================================================
        function id = fromFrac(frac)
        %FROMFRAC  0.70 -> "frac070" (frac*100 dibulatkan, 3 digit). frac tak
        %   valid -> "frac_NA".
            if ~pivcore.pot.psgId.validFrac(frac)
                id = 'frac_NA'; return;
            end
            id = sprintf('frac%03d', round(frac*100));
        end


        % ================================================================
        function id = fromGeom(p1, p2)
        %FROMGEOM  "geom_x1_y1_x2_y2" dari KOORDINAT bulat (toleransi TOLPX),
        %   ujung di-URUT secara kanonik supaya p1<->p2 menghasilkan id sama.
            p1 = p1(:).'; p2 = p2(:).';
            if numel(p1) ~= 2 || numel(p2) ~= 2 ...
                    || any(~isfinite(p1)) || any(~isfinite(p2))
                id = 'geom_NA'; return;
            end
            tol = pivcore.pot.psgId.TOLPX; if ~(isfinite(tol) && tol > 0), tol = 1; end
            q1 = round(p1 / tol) * tol;
            q2 = round(p2 / tol) * tol;
            % Urut kanonik LEKSIKOGRAFIS (x dulu, lalu y): titik lebih kecil jadi
            % a. CATATAN: `[q1(1) q1(2)] <= [q2(1) q2(2)]` SALAH — itu vektor
            % logical 1x2 yang `if` perlakukan true hanya bila SEMUA elemen true
            % (implicit all()), jadi garis miring (x1<x2 tapi y1>y2) ditarik bolak-
            % balik menghasilkan id BERBEDA. Bandingkan x dulu, baru y.
            if q1(1) < q2(1) || (q1(1) == q2(1) && q1(2) <= q2(2))
                a = q1; b = q2;
            else
                a = q2; b = q1;
            end
            id = sprintf('geom_%s_%s_%s_%s', ...
                pivcore.pot.psgId.numTok(a(1)), pivcore.pot.psgId.numTok(a(2)), ...
                pivcore.pot.psgId.numTok(b(1)), pivcore.pot.psgId.numTok(b(2)));
        end


        % ================================================================
        function tf = isFrac(id)
        %ISFRAC  TRUE bila id bergaya "fracNNN" (bukan geom).
            tf = ischar(id) && ~isempty(regexp(id, '^frac\d{3}$', 'once'));
        end


        % ================================================================
        function [p1, p2] = geomCoords(id)
        %GEOMCOORDS  Balik [x1 y1],[x2 y2] dari id "geom_..."; [] bila bukan geom.
            p1 = []; p2 = [];
            if ~ischar(id), return; end
            tok = regexp(id, '^geom_(m?\d+)_(m?\d+)_(m?\d+)_(m?\d+)$', 'tokens', 'once');
            if isempty(tok), return; end
            v = cellfun(@pivcore.pot.psgId.tokNum, tok);   % tok = 1x4 cell of char
            p1 = [v(1) v(2)]; p2 = [v(3) v(4)];
        end


        % ================================================================
        function tf = validFrac(frac)
        %VALIDFRAC  TRUE bila frac skalar berhingga di [0,1].
            tf = isscalar(frac) && isnumeric(frac) && isfinite(frac) ...
                 && frac >= 0 && frac <= 1;
        end

    end


    methods (Static, Access = private)

        function s = numTok(v)
        %NUMTOK  Koordinat bulat -> token (negatif diawali 'm' agar id tetap
        %   token tanpa tanda minus: -12 -> "m12").
            v = round(v);
            if v < 0, s = sprintf('m%d', -v); else, s = sprintf('%d', v); end
        end

        function v = tokNum(t)
        %TOKNUM  Kebalikan numTok: "m12" -> -12, "12" -> 12. `t` = char token.
            if iscell(t), t = t{1}; end
            if ~isempty(t) && t(1) == 'm', v = -str2double(t(2:end));
            else, v = str2double(t); end
        end

    end
end
