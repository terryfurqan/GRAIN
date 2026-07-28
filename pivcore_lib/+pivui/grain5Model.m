classdef grain5Model
%GRAIN5MODEL  Helper MODEL SESAR GRAIN5 (Tab ① Sesar) — logika murni atas state `h`
%   (baca h.fdoc/h.recs/h.pts/dll; TIDAK memanggil guidata / menyentuh widget).
%   Diekstrak dari GRAIN5.m (Fase 3c) sebagai satu cluster yang saling-panggil.
%   Bergantung hanya pada paket: pivcore.io.grain5Faults, pivcore.pot.netslip,
%   pivcore.pot.records, pivui.grain4Shell, pivcore.util.
%
%   CATATAN: captureFaults dipakai jalur SAVE (i_onSave/i_beforeLoad/i_onCloseFlush)
%   untuk cache derivatif (area/dNet/values) tiap sesar sebelum tulis _faults.json.
%
%   API (semua static; argumen h = struct state GRAIN5):
%     [f,idx] = pivui.grain5Model.activeFault(h)
%     [ns,hwRow,fwRow,okHW,okFW] = pivui.grain5Model.faultNetslip(h, f)
%     pid  = pivui.grain5Model.parentId(f)
%     fm   = pivui.grain5Model.mainFaultOf(h, f)
%     subs = pivui.grain5Model.subFaultsOf(h, parentId)
%     row  = pivui.grain5Model.subPartnerRow(h, f)
%     r    = pivui.grain5Model.rowForPos(h, posPx)
%     fdoc = pivui.grain5Model.captureFaults(h)
%     id   = pivui.grain5Model.nextFaultId(fdoc)
%     sid  = pivui.grain5Model.nextSubId(fdoc, parentId)
%     ord  = pivui.grain5Model.faultRowOrder(h)
%     [id,parentId] = pivui.grain5Model.deriveId(fNum, sNum)   % angka -> id kanonik
%     [fNum,sNum]   = pivui.grain5Model.idToNumbers(id)        % id kanonik -> angka
%     n    = pivui.grain5Model.faultUiNum(f)     % NOMOR TAMPIL sesar (boleh duplikat)
%     num  = pivui.grain5Model.nextUniqueIdNum(fdoc)  % angka id INTERNAL unik berikut
%
%   MODEL "SLOT SPREADSHEET" (GRAIN5): tabel sesar = slot per-baris; kolom F# = ANGKA
%   NOMOR sesar (f.uiNum, BOLEH duplikat). id record = kunci UNIK internal
%   'F<n>' (nextUniqueIdNum). SUB-FAULT (SF) DINONAKTIFKAN sementara -> deriveId/
%   idToNumbers/parentId/subFaultsOf jadi jalur tidur (siap bila SF diaktifkan lagi).
%   GRAIN6 mewarisi model ini.
%
%   Penempatan berkas: GRAIN/pivcore_lib/+pivui/grain5Model.m

    methods (Static)

        function [f, idx] = activeFault(h)
            f = []; idx = 0;
            if ~isstruct(h.fdoc) || ~isfield(h,'activeFaultId') || isempty(h.activeFaultId), return; end
            [f, idx] = pivcore.io.grain5Faults.findFault(h.fdoc, h.activeFaultId);
        end


        function [ns, hwRow, fwRow, okHW, okFW] = faultNetslip(h, f)
        %FAULTNETSLIP  ns = repHW − rep(pasangan bawah) (deret tampil + trim), pakai
        %   konvensi tanda. Sesar UTAMA: pasangan = FW-nya. SUB-FAULT: pasangan = HW
        %   SF berikutnya, atau FW F utama bila SF terakhir (luas berjenjang).
            ns = []; hwRow = []; fwRow = []; okHW = false; okFW = false;
            if ~isstruct(f), return; end
            hwRow = pivui.grain5Model.rowForPos(h, f.hwPosPx);
            if ~isempty(pivui.grain5Model.parentId(f))
                fwRow = pivui.grain5Model.subPartnerRow(h, f);   % pasangan bawah SF
            else
                fwRow = pivui.grain5Model.rowForPos(h, f.fwPosPx);
            end
            okHW = ~isempty(hwRow); okFW = ~isempty(fwRow);
            if okHW && okFW
                nF = h.nF;
                [~, A] = pivcore.pot.records.curveXY(h.recs(hwRow), nF);
                [~, B] = pivcore.pot.records.curveXY(h.recs(fwRow), nF);
                A = pivui.grain4Shell.applyTrimYV(h.recs(hwRow), A);
                B = pivui.grain4Shell.applyTrimYV(h.recs(fwRow), B);
                ns = pivcore.pot.netslip.netslipVec(A, B);
                ns = pivcore.pot.netslip.applySign(ns, h.signConv);
            end
        end


        % --- Sub-fault (SF) helper -----------------------------------
        function pid = parentId(f)
        %PARENTID  parentId sesar ('' = sesar utama; id F = sub-fault). Aman utk
        %   record lama tanpa field (kompat).
            pid = '';
            if isstruct(f) && isfield(f,'parentId') && ~isempty(f.parentId), pid = char(f.parentId); end
        end


        function fm = mainFaultOf(h, f)
        %MAINFAULTOF  Ambil struct sesar UTAMA (induk) dari SF; bila f sudah utama,
        %   kembalikan f apa adanya.
            fm = f;
            pid = pivui.grain5Model.parentId(f);
            if isempty(pid), return; end
            [fp, ip] = pivcore.io.grain5Faults.findFault(h.fdoc, pid);
            if ip >= 1, fm = fp; end
        end


        function subs = subFaultsOf(h, parentId)
        %SUBFAULTSOF  Daftar struct SF (anak) dari sesar utama parentId, TERURUT
        %   menurun berdasarkan hwPosPx (dekat ke FW = paling bawah). Cell array.
            subs = {};
            if ~(isstruct(h.fdoc) && isfield(h.fdoc,'faults')), return; end
            pos = [];
            for k = 1:numel(h.fdoc.faults)
                fk = h.fdoc.faults{k};
                if strcmp(pivui.grain5Model.parentId(fk), parentId)
                    subs{end+1} = fk; %#ok<AGROW>
                    pp = NaN; if isfield(fk,'hwPosPx') && isscalar(fk.hwPosPx), pp = fk.hwPosPx; end
                    pos(end+1) = pp; %#ok<AGROW>
                end
            end
            if numel(subs) <= 1, return; end
            % Urut menurun posPx (HW SF paling "atas"/jauh dari FW = indeks pertama).
            [~, ord] = sort(pos, 'descend', 'MissingPlacement','last');
            subs = subs(ord);
        end


        function row = subPartnerRow(h, f)
        %SUBPARTNERROW  Baris record PASANGAN BAWAH untuk net-slip SF f: HW SF
        %   berikutnya (menurun posPx), atau FW induk bila SF terakhir.
            row = [];
            pid = pivui.grain5Model.parentId(f); if isempty(pid), return; end
            subs = pivui.grain5Model.subFaultsOf(h, pid);
            ids = cellfun(@(x) x.id, subs, 'UniformOutput', false);
            ix = find(strcmp(ids, f.id), 1);
            if isempty(ix), return; end
            if ix < numel(subs)
                row = pivui.grain5Model.rowForPos(h, subs{ix+1}.hwPosPx);   % HW SF berikutnya
            else
                [fp, ip] = pivcore.io.grain5Faults.findFault(h.fdoc, pid);
                if ip >= 1, row = pivui.grain5Model.rowForPos(h, fp.fwPosPx); end   % FW induk
            end
        end


        function r = rowForPos(h, posPx)
        %ROWFORPOS  Petakan posPx (identitas kurva stabil) -> baris record terdekat
        %   dalam toleransi (≤ 0.75·spacing). [] bila tak ada (kurva hilang/dibuang).
            r = [];
            if ~isscalar(posPx) || ~isfinite(posPx) || isempty(h.recs), return; end
            best = inf; bestR = [];
            for k = 1:numel(h.recs)
                if pivui.grain4Shell.isExcluded(h.recs(k)), continue; end
                p = NaN;
                if isfield(h.recs(k),'posPx') && isscalar(h.recs(k).posPx), p = h.recs(k).posPx; end
                if isfinite(p)
                    d = abs(p - posPx);
                    if d < best, best = d; bestR = k; end
                end
            end
            if isempty(bestR), return; end
            sp = pivcore.util.scalarOr(h.spacing, 10); if ~(isfinite(sp) && sp > 0), sp = 10; end
            if best <= max(8, 0.75*sp), r = bestR; end
        end


        function fdoc = captureFaults(h)
        %CAPTUREFAULTS  Segarkan meta + cache derivatif (area/dNet/values) tiap sesar
        %   sebelum simpan (kanal Claude). Model murni (posisi/titik) tak diubah.
            fdoc = h.fdoc;
            if ~isstruct(fdoc), fdoc = pivcore.io.grain5Faults.emptyDoc(h.df); end
            fdoc.meta.frames = max([h.nF, h.imgFrames, 1]);
            [~, base, ext] = fileparts(h.df);
            fdoc.source = [base ext]; fdoc.meta.basename = base;
            fdoc.signConvention = h.signConv;
            if ~isfield(fdoc,'units') || isempty(fdoc.units), fdoc.units = 'px/frame'; end
            if isfield(fdoc,'faults')
                for k = 1:numel(fdoc.faults)
                    f = fdoc.faults{k};
                    [ns, ~, ~, okHW, okFW] = pivui.grain5Model.faultNetslip(h, f);
                    if okHW && okFW && ~isempty(ns)
                        f.area   = pivcore.pot.netslip.area(ns, f.startF, f.endF);
                        f.dNet   = pivcore.pot.netslip.dNet(ns, f.startF, f.endF);
                        f.values = ns;
                    else
                        f.area = NaN; f.dNet = NaN; f.values = [];
                    end
                    fdoc.faults{k} = f;
                end
            end
        end


        function id = nextFaultId(fdoc)
        %NEXTFAULTID  ID sesar UTAMA berikut: "F<n>" (SF ber-id "F..S.." dilewati).
            mx = 0;
            if isstruct(fdoc) && isfield(fdoc,'faults')
                for k = 1:numel(fdoc.faults)
                    fk = fdoc.faults{k};
                    if isstruct(fk) && isfield(fk,'id') && isempty(pivui.grain5Model.parentId(fk))
                        t = regexp(char(fk.id),'^F(\d+)$','tokens','once');
                        if ~isempty(t), mx = max(mx, str2double(t{1})); end
                    end
                end
            end
            id = sprintf('F%d', mx+1);
        end


        function sid = nextSubId(fdoc, parentId)
        %NEXTSUBID  ID sub-fault berikut untuk induk parentId: "<parentId>S<n>".
            mx = 0; pat = sprintf('^%sS(\\d+)$', regexptranslate('escape', parentId));
            if isstruct(fdoc) && isfield(fdoc,'faults')
                for k = 1:numel(fdoc.faults)
                    fk = fdoc.faults{k};
                    if isstruct(fk) && isfield(fk,'id')
                        t = regexp(char(fk.id), pat, 'tokens','once');
                        if ~isempty(t), mx = max(mx, str2double(t{1})); end
                    end
                end
            end
            sid = sprintf('%sS%d', parentId, mx+1);
        end


        function [id, parentId] = deriveId(fNum, sNum)
        %DERIVEID  Turunkan id-string kanonik dari angka kolom F#/SF.
        %   fNum = bilangan bulat >=1 (WAJIB). sNum = [] (utama) atau bulat >=1 (SF).
        %   SF kosong -> id 'F<fNum>', parentId ''.
        %   SF terisi -> id 'F<fNum>S<sNum>', parentId 'F<fNum>'.
            id = ''; parentId = '';
            if isempty(fNum) || ~isfinite(fNum), return; end
            fN = round(fNum);
            if isempty(sNum) || ~isfinite(sNum)
                id = sprintf('F%d', fN); parentId = '';
            else
                parentId = sprintf('F%d', fN);
                id = sprintf('F%dS%d', fN, round(sNum));
            end
        end


        function [fNum, sNum] = idToNumbers(id)
        %IDTONUMBERS  Reverse deriveId: id-string kanonik -> angka F#/SF (utk tampil).
        %   'F3'   -> fNum=3, sNum=[] ;  'F3S2' -> fNum=3, sNum=2 ;  lain -> [],[].
        %   DUA regexp terpisah: grup opsional (?:S(\d+))? MEMANGKAS token kedua di
        %   MATLAB (baik dgn/ tanpa 'once'), jadi F# & SF dibaca sendiri-sendiri.
            fNum = []; sNum = [];
            if isempty(id), return; end
            s = char(id);
            if isempty(regexp(s, '^F\d+(S\d+)?$', 'once')), return; end   % bukan id kanonik
            tf = regexp(s, '^F(\d+)', 'tokens', 'once');
            if ~isempty(tf), fNum = str2double(tf{1}); end
            ts = regexp(s, 'S(\d+)$', 'tokens', 'once');
            if ~isempty(ts), sNum = str2double(ts{1}); end
        end


        function tf = faultEnabled(f)
        %FAULTENABLED  true bila sesar AKTIF (dirender/diekspor). Field absen ->
        %   default true (kompat record lama). false -> sesar dinonaktifkan (input
        %   dipertahankan tapi tak tampil/tak diekspor).
            tf = true;
            if isstruct(f) && isfield(f,'enabled') && isscalar(f.enabled)
                tf = logical(f.enabled);
            end
        end


        function tf = faultChecklistDone(f)
        %FAULTCHECKLISTDONE  true bila sesar SUDAH ter-CHECKLIST (✓) = definisi baru:
        %   punya HW + FW (kurva atas-bawah) DAN START + END (pembatas kiri-kanan).
        %   NUC/FSR TIDAK lagi syarat (observasi POI dilakukan di GRAIN4). Dipakai
        %   konsisten oleh tabel sesar (✓ biru), hitung #F, dan info ekspor.
            tf = false;
            if ~isstruct(f), return; end
            hasHW = isfield(f,'hwPosPx') && isscalar(f.hwPosPx) && isfinite(f.hwPosPx);
            hasFW = isfield(f,'fwPosPx') && isscalar(f.fwPosPx) && isfinite(f.fwPosPx);
            hasST = isfield(f,'startF')  && isscalar(f.startF)  && isfinite(f.startF);
            hasEN = isfield(f,'endF')    && isscalar(f.endF)    && isfinite(f.endF);
            tf = hasHW && hasFW && hasST && hasEN;
        end


        function n = faultUiNum(f)
        %FAULTUINUM  Nomor TAMPIL sesar (kolom F#). BOLEH duplikat antar-sesar.
        %   Dari f.uiNum bila finite; else turunkan dari id (kompat record lama).
        %   [] bila tak terbaca.
            n = [];
            if ~isstruct(f), return; end
            if isfield(f,'uiNum') && isscalar(f.uiNum) && isfinite(f.uiNum)
                n = round(f.uiNum); return;
            end
            if isfield(f,'id'), [fN,~] = pivui.grain5Model.idToNumbers(f.id); if ~isempty(fN), n = round(fN); end, end
        end


        function num = nextUniqueIdNum(fdoc)
        %NEXTUNIQUEIDNUM  Angka id INTERNAL unik berikut (utk 'F<num>' kunci record).
        %   Berbeda dari uiNum (nomor tampil boleh duplikat), TAPI tetap unik dalam
        %   satu file. Strategi = ISI LUBANG TERKECIL: angka >=1 terkecil yang BELUM
        %   dipakai id mana pun. Jadi setelah hapus sesar, nomor terisi ulang rapi
        %   (padat 1..N, tanpa lompatan/offset global acak spt F16..). Aman untuk
        %   findFault/activeFaultId/parentId krn tetap unik per-dokumen.
            used = pivui.grain5Model.usedIdNums(fdoc);
            num = 1;
            while any(used == num), num = num + 1; end
        end


        function used = usedIdNums(fdoc)
        %USEDIDNUMS  Vektor angka F# dari SEMUA id record (utama & SF induknya).
        %   Dipakai nextUniqueIdNum utk cari lubang terkecil. Angka dari 'F<n>' dan
        %   dari induk 'F<n>S<m>' (supaya id utama tak bentrok dgn angka induk SF).
            used = [];
            if ~(isstruct(fdoc) && isfield(fdoc,'faults')), return; end
            for k = 1:numel(fdoc.faults)
                fk = fdoc.faults{k};
                if isstruct(fk) && isfield(fk,'id')
                    [fN,~] = pivui.grain5Model.idToNumbers(fk.id);
                    if ~isempty(fN), used(end+1) = fN; end %#ok<AGROW>
                end
            end
        end


        function ord = faultRowOrder(h)
        %FAULTROWORDER  Urutkan baris tabel: tiap sesar UTAMA (urut kemunculan)
        %   diikuti SF anaknya (urut posPx menurun). Cell struct paralel baris tabel.
            ord = {};
            if ~(isstruct(h.fdoc) && isfield(h.fdoc,'faults')), return; end
            F = h.fdoc.faults;
            for k = 1:numel(F)
                f = F{k};
                if ~isempty(pivui.grain5Model.parentId(f)), continue; end   % SF via induk
                ord{end+1} = f; %#ok<AGROW>
                subs = pivui.grain5Model.subFaultsOf(h, f.id);
                for j = 1:numel(subs), ord{end+1} = subs{j}; end %#ok<AGROW>
            end
            % SF yatim (induk terhapus) — tetap tampilkan di akhir agar bisa dihapus.
            for k = 1:numel(F)
                f = F{k}; pid = pivui.grain5Model.parentId(f);
                if isempty(pid), continue; end
                [~, ip] = pivcore.io.grain5Faults.findFault(h.fdoc, pid);
                if ip < 1, ord{end+1} = f; end %#ok<AGROW>
            end
        end


        % ================================================================
        % SCOPING FAULT per-GARIS PSG (GRAIN5_temp_2 / multi-PSG per-F).
        % Tiap fault.psgId = id garis pemilik. Helper murni (tak sentuh guidata).
        % ================================================================
        function pid = psgIdOf(f)
        %PSGIDOF  id garis PSG pemilik sesar ('' bila absen/belum ter-scope).
            pid = '';
            if isstruct(f) && isfield(f,'psgId') && (ischar(f.psgId) || isstring(f.psgId))
                pid = char(f.psgId);
            end
        end


        function F = faultsForPsg(fdoc, psgId)
        %FAULTSFORPSG  Cell fault milik garis PSG `psgId` (f.psgId==psgId).
        %   Fault ber-psgId '' (belum ter-scope) DIANGGAP milik garis mana pun
        %   yang sedang ditanya HANYA jika psgId juga '' — jadi setelah migrasi
        %   (assignOrphanFaultsTo) tak ada lagi orphan. Urutan kemunculan asli.
            F = {};
            if ~(isstruct(fdoc) && isfield(fdoc,'faults')), return; end
            want = char(psgId);
            src = fdoc.faults;
            for k = 1:numel(src)
                fk = src{k};
                if isstruct(fk) && strcmp(pivui.grain5Model.psgIdOf(fk), want)
                    F{end+1} = fk; %#ok<AGROW>
                end
            end
        end


        function fdoc = assignOrphanFaultsTo(fdoc, psgId)
        %ASSIGNORPHANFAULTSTO  Migrasi lazy: tiap fault ber-psgId '' -> psgId
        %   (garis pertama). Dipakai saat membuka file lama (GRAIN4/GRAIN5/GRAIN6)
        %   yang belum punya scoping. No-op bila tak ada orphan / psgId kosong.
            if ~(isstruct(fdoc) && isfield(fdoc,'faults')), return; end
            want = char(psgId);
            if isempty(want), return; end
            for k = 1:numel(fdoc.faults)
                fk = fdoc.faults{k};
                if isstruct(fk) && isempty(pivui.grain5Model.psgIdOf(fk))
                    fk.psgId = want; fdoc.faults{k} = fk;
                end
            end
        end


        function [fdoc, nRemoved] = pruneGhostFaults(fdoc, realPsgIds)
        %PRUNEGHOSTFAULTS  Buang sesar "hantu" = ber-psgId yang TIDAK ADA di
        %   `realPsgIds` (daftar id garis PSG NYATA dari _potdata.json psgLines).
        %   Muncul karena garis PSG lama dihapus/diregenerasi tapi sesarnya
        %   tertinggal (psgId asing) -> menggelembungkan hitungan & bisa duplikat.
        %   Sesar ber-psgId '' (orphan) DIPERTAHANKAN (biar assignOrphanFaultsTo
        %   yang migrasi). Panggil SESUDAH assignOrphanFaultsTo saat load.
        %   nRemoved = jumlah record dibuang (0 -> dokumen tak berubah).
            nRemoved = 0;
            if ~(isstruct(fdoc) && isfield(fdoc,'faults')), return; end
            if isempty(realPsgIds), return; end   % tak tahu garis nyata -> jangan buang apa pun
            realSet = containers.Map('KeyType','char','ValueType','logical');
            for k = 1:numel(realPsgIds), realSet(char(realPsgIds{k})) = true; end
            keep = {};
            for k = 1:numel(fdoc.faults)
                fk = fdoc.faults{k};
                pid = pivui.grain5Model.psgIdOf(fk);   % '' bila absen
                if ~isempty(pid) && ~isKey(realSet, pid)
                    nRemoved = nRemoved + 1;   % psgId asing -> hantu, buang
                else
                    keep{end+1} = fk; %#ok<AGROW>
                end
            end
            fdoc.faults = keep;
        end


        function fdoc = normalizeUiNumsPerPsg(fdoc)
        %NORMALIZEUINUMSPERPSG  Perbaiki NOMOR TAMPIL sesar supaya LOKAL per garis PSG.
        %   Masalah multi-PSG: id record ('F<n>') = kunci UNIK GLOBAL (nextUniqueIdNum
        %   = max+1 lintas semua garis PSG). Kalau f.uiNum HILANG (file lama/pra-
        %   multi-PSG), faultUiNum jatuh ke idToNumbers(id) -> bocor angka global
        %   (mis. sesar #1 di garis-2 ber-id F11 tampil "F11" alih-alih "F1").
        %
        %   Fix: untuk TIAP garis PSG, tetapkan f.uiNum = 1,2,3,... menurut urutan
        %   kemunculan. uiNum eksplisit DIHORMATI HANYA bila MASUK AKAL utk grup itu
        %   (bilangan bulat 1..nGrup dan belum dipakai record lain di grup). uiNum
        %   liar (mis. 33 padahal grup cuma 12 sesar; sisa kebocoran id global lama)
        %   DIABAIKAN -> diperlakukan sbg belum-ternomori -> diisi lubang 1..N rapi.
        %   Idempoten: dijalankan ulang tak mengubah dokumen yang sudah normal.
            if ~(isstruct(fdoc) && isfield(fdoc,'faults')), return; end
            F = fdoc.faults;
            % Kumpulkan psgId unik menurut urutan kemunculan.
            groups = {};
            for k = 1:numel(F)
                pid = pivui.grain5Model.psgIdOf(F{k});
                if ~any(strcmp(groups, pid)), groups{end+1} = pid; end %#ok<AGROW>
            end
            for gi = 1:numel(groups)
                pid = groups{gi};
                idx = [];
                for k = 1:numel(F)
                    if strcmp(pivui.grain5Model.psgIdOf(F{k}), pid), idx(end+1) = k; end %#ok<AGROW>
                end
                nGrp = numel(idx);
                % Fase 1: tandai record mana yang MEMPERTAHANKAN uiNum-nya = uiNum
                % valid (bulat, 1..nGrp) & merupakan record PERTAMA yang mengklaim
                % angka itu (duplikat berikutnya di-renumber). `taken` = nomor final.
                taken = [];
                keepMask = false(1, numel(idx));
                for j = 1:numel(idx)
                    fk = F{idx(j)};
                    if pivui.grain5Model.uiNumIsSane(fk, nGrp) && ~any(taken == round(fk.uiNum))
                        taken(end+1) = round(fk.uiNum); %#ok<AGROW>
                        keepMask(j) = true;
                    end
                end
                % Fase 2: record tak-di-keep (kosong/liar/duplikat) -> lubang 1..nGrp
                % terkecil yang belum terpakai. Record di-keep dibiarkan apa adanya.
                next = 1;
                for j = 1:numel(idx)
                    if keepMask(j), continue; end
                    while any(taken == next), next = next + 1; end
                    fk = F{idx(j)}; fk.uiNum = next; F{idx(j)} = fk;
                    taken(end+1) = next; next = next + 1; %#ok<AGROW>
                end
            end
            fdoc.faults = F;
        end


        function tf = uiNumIsSane(f, nGrp)
        %UINUMISSANE  true bila f.uiNum = bilangan bulat 1..nGrp (nomor tampil masuk
        %   akal utk grup PSG ber-nGrp sesar). Menolak uiNum liar (mis. 33 di grup 12)
        %   sisa kebocoran id global lama, supaya normalizeUiNumsPerPsg mengoreksinya.
            tf = false;
            if ~(isstruct(f) && isfield(f,'uiNum') && isscalar(f.uiNum) && isfinite(f.uiNum)), return; end
            n = f.uiNum;
            tf = (n == round(n)) && n >= 1 && n <= max(nGrp,1);
        end

    end
end
