classdef pab5Fmt
%PAB5FMT  Formatter & helper skalar/string PAB5 — fungsi MURNI (tak menyentuh
%   guidata; hanya argumen/field). Diekstrak dari PAB5.m (Fase 3b) agar file
%   entry ramping. Dipakai untuk isi tabel sesar, ringkasan, tag kurva, dll.
%
%   API (semua static):
%     s = pivui.pab5Fmt.tern(tf,a,b)         % ternary
%     s = pivui.pab5Fmt.num(x)               % '%.3g' | '—'
%     s = pivui.pab5Fmt.num2(x)              % '%.2f' | '—'
%     s = pivui.pab5Fmt.numDash(x)           % '%d' (round) | '—'
%     s = pivui.pab5Fmt.pctStr(x)            % '%.1f' | '—'
%     s = pivui.pab5Fmt.orDash(x)            % char(x) | '—' bila kosong
%     v = pivui.pab5Fmt.gf(s,f)              % ambil field skalar numerik | NaN
%     y = pivui.pab5Fmt.clampRange(y,ab)     % NaN-kan y di luar [a,b]
%     c = pivui.pab5Fmt.dol(c)               % clamp warna ke [0 1]
%     s = pivui.pab5Fmt.subTag(sid)          % 'F1S2' -> 'S2'
%     v = pivui.pab5Fmt.nsAtFrame(ns,f)      % |net-slip| pada frame f
%     s = pivui.pab5Fmt.curveNumTag(h,row,posPx)
%     s = pivui.pab5Fmt.posTag(posPx,ok)
%     s = pivui.pab5Fmt.unitsStr(h)          % h.fdoc.units | 'px/frame'
%
%   Penempatan berkas: PAB/pivcore_lib/+pivui/pab5Fmt.m

    methods (Static)

        function s = tern(tf, a, b), if tf, s = a; else, s = b; end, end

        function s = num(x)
            if isscalar(x) && isfinite(x), s = sprintf('%.3g', x); else, s = '—'; end
        end

        function s = num2(x)
            if isscalar(x) && isfinite(x), s = sprintf('%.2f', x); else, s = '—'; end
        end

        function s = numDash(x)
            if isscalar(x) && isnumeric(x) && isfinite(x), s = sprintf('%d', round(x)); else, s = '—'; end
        end

        function s = pctStr(x)
            if isscalar(x) && isfinite(x), s = sprintf('%.1f', x); else, s = '—'; end
        end

        function s = orDash(x)
            if isempty(x), s = '—'; else, s = char(x); end
        end

        function v = gf(s, f)
            if isstruct(s) && isfield(s,f) && isscalar(s.(f)) && isnumeric(s.(f))
                v = double(s.(f));
            else
                v = NaN;
            end
        end

        function y = clampRange(y, ab)
        %CLAMPRANGE  NaN-kan y di luar [a,b] (frame). ab kosong -> y utuh.
            if isempty(ab) || numel(ab)~=2, return; end
            a = round(min(ab)); b = round(max(ab)); n = numel(y);
            a = max(1,a); b = min(n,b);
            if a > 1,   y(1:a-1) = NaN; end
            if b < n,   y(b+1:end) = NaN; end
        end

        function c = dol(c)  % clamp warna ke [0 1] (guard)
            c = min(1, max(0, c));
        end

        function s = subTag(sid)
        %SUBTAG  "F1S2" -> "S2".
            t = regexp(char(sid), 'S(\d+)$', 'tokens','once');
            if ~isempty(t), s = ['S' t{1}]; else, s = 'S'; end
        end

        function v = nsAtFrame(ns, f)
        %NSATFRAME  |net-slip| (selisih |HW−FW|) pada frame f. NaN bila di luar/kosong.
            v = NaN;
            if isempty(ns) || ~(isscalar(f) && isfinite(f)), return; end
            k = round(f); if k < 1 || k > numel(ns), return; end
            v = abs(ns(k));
        end

        function s = curveNumTag(h, row, posPx)
        %CURVENUMTAG  Nomor kurva (string) dari baris record; 'N?' bila posPx ada
        %   tapi kurva tak ketemu; '—' bila belum di-assign.
            if isempty(row)
                if isscalar(posPx) && isfinite(posPx), s = sprintf('%d?', round(posPx)); else, s = '—'; end
                return;
            end
            s = pivui.pab4Shell.curveNum(h.recs(row), row);
        end

        function s = posTag(posPx, ok)
            if ~isscalar(posPx) || ~isfinite(posPx), s = '—'; return; end
            if ok, s = sprintf('%d', round(posPx)); else, s = sprintf('%d?', round(posPx)); end
        end

        function s = unitsStr(h)
            s = 'px/frame';
            if isstruct(h.fdoc) && isfield(h.fdoc,'units') && ~isempty(h.fdoc.units), s = h.fdoc.units; end
        end

    end
end
