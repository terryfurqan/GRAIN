#!/usr/bin/env python3
"""Stage 1 of the ID -> EN UI-text migration: PAB0.m (+ its tests).

Only USER-VISIBLE text is touched: widget Text/Title/Tooltip/Placeholder,
ColumnName, dropdown Items (display only, ItemsData untouched), axes
titles/labels, status/alert/dialog messages and error message texts.
Code identifiers, comments, error identifiers, struct fields, file names
and progress-file keys are left exactly as they were.

Each pair asserts an exact occurrence count so a silent miss is impossible.
"""
import sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

# (old, new, expected_count)
PAB0 = [
    # ---- engine guard -------------------------------------------------
    ("'Engine PIVlab_automasi tak di-path. Jalankan pab_setup.'",
     "'Engine PIVlab_automasi is not on the path. Run pab_setup.'", 1),

    # ---- window title -------------------------------------------------
    ("'PAB0 (Step 0 · QPIV) — exclusion frame (mati + interval)'",
     "'PAB0 (Step 0 · QPIV) — frame exclusion (dead + interval)'", 1),

    # ---- left column --------------------------------------------------
    ("'Title','Eksperimen & kontrol exclusion'",
     "'Title','Experiments & exclusion controls'", 1),
    ("'Text','Pilih Root…'", "'Text','Pick Root…'", 1),
    ("'Text','Scan ulang'", "'Text','Rescan'", 1),
    ("'Tooltip','Pindai ulang root secara rekursif.'",
     "'Tooltip','Rescan the root folder recursively.'", 1),
    ("'Text','(root: belum dipilih)'", "'Text','(root: none selected)'", 1),
    ("'ColumnName',{'Eksperimen','#img','drop','output','status'}",
     "'ColumnName',{'Experiment','#img','drop','output','status'}", 1),
    ("'Text','Bersihkan ceklis'", "'Text','Clear checkmarks'", 1),
    ("'Text','0 frame ditandai abaikan.'", "'Text','0 frames marked ignore.'", 1),
    ("'Text','Hapus dari daftar'", "'Text','Remove from list'", 1),
    ("'Tooltip','Simpan status QPIV semua exp ke <root>/PAB0_progress.mat.'",
     "'Tooltip','Save the QPIV status of every exp to <root>/PAB0_progress.mat.'", 1),
    ("'Tooltip','Muat berkas progres (default <root>/PAB0_progress.mat) bila auto-load gagal.'",
     "'Tooltip','Load a progress file (default <root>/PAB0_progress.mat) if auto-load fails.'", 1),

    # ---- config panel -------------------------------------------------
    ("'Title','Konfigurasi QPIV — geser slider Posisi/Sudut, garis kuning di axMain update realtime'",
     "'Title','QPIV configuration — drag the Position/Angle sliders; the yellow line in axMain updates live'", 1),
    ("'Text','Orientasi:'", "'Text','Orientation:'", 1),
    ("'Text','Pasangan:'", "'Text','Pairing:'", 1),
    ("'Items',{'Berurutan: 1-2,2-3,…','Berpasangan: 1-2,3-4,…'}",
     "'Items',{'Consecutive: 1-2,2-3,…','Paired: 1-2,3-4,…'}", 1),
    ("'Tooltip','Kunci IW (pass 1-4) + #pass: tak berubah saat pindah exp.'",
     "'Tooltip','Lock IW (pass 1-4) + #pass: unchanged when switching exp.'", 1),
    ("'Tooltip','Kunci Posisi% + Sudut°: tak berubah saat pindah exp.'",
     "'Tooltip','Lock Position% + Angle°: unchanged when switching exp.'", 1),
    ("'Text','🔒 dll'", "'Text','🔒 etc'", 1),
    ("'Tooltip','Kunci Orientasi + Pasangan + Skip: tak berubah saat pindah exp.'",
     "'Tooltip','Lock Orientation + Pairing + Skip: unchanged when switching exp.'", 1),
    ("'Text','Posisi %:'", "'Text','Position %:'", 1),
    ("'Text','Overlay citra strip'", "'Text','Strip image overlay'", 1),
    ("'Text','Sudut °:'", "'Text','Angle °:'", 1),
    ("'Text','Warna|V|:'", "'Text','Color|V|:'", 1),

    # ---- axes ---------------------------------------------------------
    ("title(axMain,'axMain — full frame (GS) + garis POT/PSG')",
     "title(axMain,'axMain — full frame (GS) + POT/PSG line')", 1),
    ("title(axPSG,'axPSG — kymograph (posisi × frame)')",
     "title(axPSG,'axPSG — kymograph (position × frame)')", 1),
    ("'Tooltip','Geser frame. Lebarnya = lebar plot axPOT; posisi = garis biru.'",
     "'Tooltip','Drag to change frame. Width = axPOT plot width; position = blue line.'", 1),

    # ---- main action buttons -----------------------------------------
    ("'Text','Proses PIV tanpa excluded ▶'",
     "'Text','Process PIV without excluded ▶'", 1),
    ("'Tooltip','Jalankan ulang PIV pada foto BERSIH (frame diabaikan dibuang) -> lihat efek POT/PSG.'",
     "'Tooltip','Re-run PIV on the CLEAN photos (ignored frames dropped) -> see the POT/PSG effect.'", 1),
    ("'Text','◀ Kembalikan semua'", "'Text','◀ Restore all'", 1),
    ("'Tooltip','Kembali ke tampilan semua frame (mode edit ceklis).'",
     "'Tooltip','Back to the all-frames view (checkmark edit mode).'", 1),
    ("'Text','Lanjut → PABMASK (masking area)'",
     "'Text','Next → PABMASK (area masking)'", 1),
    ("'Tooltip','Buka langkah berikutnya: penentuan ROI stabilisasi jitter (PAB0 lama).'",
     "'Tooltip','Open the next step: jitter-stabilisation ROI (the old PAB0).'", 1),
    ("'Text','▶▶ QPIV semua exp'", "'Text','▶▶ QPIV all exps'", 1),
    ("'Tooltip',['Jalankan QPIV pada SEMUA eksperimen memakai parameter (config) yang SAMA ' ...\n               'dengan yang di layar saat ini. Bisa pilih: semua, atau hanya yang belum selesai.'], ...",
     "'Tooltip',['Run QPIV on ALL experiments using the SAME parameters (config) as the ' ...\n               'ones on screen right now. You can pick: all exps, or only the unfinished ones.'], ...", 1),
    ("'Text','▶ Jalankan QPIV'", "'Text','▶ Run QPIV'", 1),
    ("'Tooltip','Jalankan QPIV pada eksperimen terpilih (config di layar).'",
     "'Tooltip','Run QPIV on the selected experiment (config on screen).'", 1),
    ("'Text','✖ Batal QPIV'", "'Text','✖ Cancel QPIV'", 1),
    ("'Tooltip','Batalkan proses QPIV yang sedang berjalan (mis. salah setting).'",
     "'Tooltip','Cancel the QPIV run in progress (e.g. wrong settings).'", 1),
    ("'Tooltip','Simpan exclusion exp ini, pindah ke exp berikutnya yang belum selesai, lalu JALANKAN QPIV otomatis.'",
     "'Tooltip','Save this exp''s exclusion, move to the next unfinished exp, then RUN QPIV automatically.'", 1),
    ("'Text','✓ Save ▸ Next (tanpa QPIV)'",
     "'Text','✓ Save ▸ Next (no QPIV)'", 1),
    ("'Tooltip','Simpan exclusion exp ini lalu pindah ke exp berikutnya TANPA menjalankan QPIV.'",
     "'Tooltip','Save this exp''s exclusion then move to the next exp WITHOUT running QPIV.'", 1),
    ("'Text','Siap.'", "'Text','Ready.'", 1),

    # ---- right column -------------------------------------------------
    ("'Title','Deteksi mati & tabel frame'", "'Title','Dead detection & frame table'", 1),
    ("'Text','Auto-deteksi frame mati'", "'Text','Auto-detect dead frames'", 1),
    ("'Tooltip','Tandai frame dengan |V| puncak di bawah ambang sebagai \"mati\".'",
     "'Tooltip','Mark frames whose peak |V| is below the threshold as \"dead\".'", 1),
    ("'Text','Mati |V|<'", "'Text','Dead |V|<'", 1),
    ("'Tooltip','Ambang BAWAH |V| puncak: frame di bawahnya = mati (mesin berhenti).'",
     "'Tooltip','LOWER threshold on peak |V|: frames below it = dead (machine stopped).'", 1),
    ("'Tooltip','Ambang ATAS |V| (Inf = tak memotong).'",
     "'Tooltip','UPPER threshold on |V| (Inf = no cut).'", 1),
    ("'Text','(dt: belum dihitung)'", "'Text','(dt: not computed yet)'", 1),
    ("'Text','Skip frame manual (mis 1,2,5-9):'",
     "'Text','Manual frame skip (e.g. 1,2,5-9):'", 1),
    ("'Text','Tambah'", "'Text','Add'", 1),
    ("'ColumnName',{'Frame','|V|max','dt (s)','Abaikan'}",
     "'ColumnName',{'Frame','|V|max','dt (s)','Ignore'}", 1),
    ("""    'Text',['Kolom dt = interval EXIF antar-foto pasangan. dt = nilai TERBANYAK ' ...
            'dianggap interval yang seharusnya; baris yang menyimpang ditandai ' ...
            'MERAH (anomali interval/counter-wrap) — putuskan sendiri lewat ceklis ' ...
            '\"Abaikan\". |V|max kecil = frame mati. Klik kurva axPOT atau baris ' ...
            'tabel untuk loncat frame.']);""",
     """    'Text',['Column dt = EXIF interval between the photos of a pair. The MOST COMMON ' ...
            'dt is taken as the interval it should be; deviating rows are marked ' ...
            'RED (interval anomaly / counter wrap-around) — you decide via the ' ...
            '\"Ignore\" checkmark. Small |V|max = dead frame. Click the axPOT curve or a ' ...
            'table row to jump to that frame.']);""", 1),

    # ---- status / dialog messages -------------------------------------
    ("setStatus('Klik \"Pilih Root…\" untuk mendeteksi eksperimen (folder berisi JPEG).')",
     "setStatus('Click \"Pick Root…\" to detect experiments (folders containing JPEGs).')", 1),
    ("'Pilih ROOT (berisi subfolder eksperimen JPEG)'",
     "'Pick a ROOT (containing JPEG experiment subfolders)'", 1),
    ("setStatus('Memindai folder (rekursif, agresif)…');",
     "setStatus('Scanning folders (recursive, aggressive)…');", 1),
    ("sprintf('Gagal scan: %s', ME.message)", "sprintf('Scan failed: %s', ME.message)", 1),
    ("setStatus('Tak ada folder berisi urutan gambar di root ini.');",
     "setStatus('No folder with an image sequence found in this root.');", 1),
    ("""                setStatus(sprintf(['%d eksperimen terdeteksi. Progres tersimpan DIMUAT dari ' ...
                    '%s — lanjutkan dari status terakhir.'], numel(exps), progFileName));""",
     """                setStatus(sprintf(['%d experiments detected. Saved progress LOADED from ' ...
                    '%s — continue from the last status.'], numel(exps), progFileName));""", 1),
    ("""                setStatus(sprintf(['%d eksperimen terdeteksi (belum ada %s). Pilih satu lalu ' ...
                    '\"Jalankan QPIV\"; \"Save Progress\" utk simpan.'], numel(exps), progFileName));""",
     """                setStatus(sprintf(['%d experiments detected (no %s yet). Pick one then ' ...
                    '\"Run QPIV\"; \"Save Progress\" to store it.'], numel(exps), progFileName));""", 1),
    ("setStatus('Pilih root dulu sebelum menyimpan progres.');",
     "setStatus('Pick a root before saving progress.');", 1),
    ("sprintf('Progres tersimpan: %d entri → %s', n, pf)",
     "sprintf('Progress saved: %d entries → %s', n, pf)", 1),
    ("sprintf('%d entri progres tersimpan ke:\\n%s', n, pf), ...\n                'Progres tersimpan','Icon','success'",
     "sprintf('%d progress entries saved to:\\n%s', n, pf), ...\n                'Progress saved','Icon','success'", 1),
    ("setStatus('Belum ada entri untuk disimpan (jalankan/QPIV simpan dulu sebuah exp).');",
     "setStatus('No entry to save yet (run QPIV / save an exp first).');", 1),
    ("{'*.mat','Berkas progres (*.mat)'}", "{'*.mat','Progress file (*.mat)'}", 1),
    ("'Pilih berkas progres (PAB0_progress.mat)'",
     "'Pick a progress file (PAB0_progress.mat)'", 1),
    ("sprintf('Gagal memuat progres: %s', ME.message)",
     "sprintf('Failed to load progress: %s', ME.message)", 1),
    ("setStatus(sprintf('Progres dimuat (%d entri) dari %s', n, pf));",
     "setStatus(sprintf('Progress loaded (%d entries) from %s', n, pf));", 1),

    # ---- exp table status cells ---------------------------------------
    ("nd = 0; st = 'baru'; nout = [];", "nd = 0; st = 'new'; nout = [];", 1),
    ("if i_field(e,'qpiv_done',false); st = '✓ qpiv'; else; st = 'tersimpan'; end",
     "if i_field(e,'qpiv_done',false); st = '✓ qpiv'; else; st = 'saved'; end", 1),

    # ---- lock messages -------------------------------------------------
    ("""            setMid(sprintf(['%d kelompok config DIKUNCI — nilai sekarang dipertahankan ' ...
                'saat pindah exp (tak kembali ke default/tersimpan).'], nL));""",
     """            setMid(sprintf(['%d config group(s) LOCKED — current values are kept ' ...
                'when switching exp (no reset to default/saved).'], nL));""", 1),
    ("setMid('Kunci config nonaktif — config ikut nilai tersimpan tiap exp.');",
     "setMid('Config lock off — config follows each exp''s saved values.');", 1),

    # ---- load / run ----------------------------------------------------
    ("setBusy(true,'Memuat hasil QPIV tersimpan…');",
     "setBusy(true,'Loading saved QPIV result…');", 1),
    ("sprintf('Dimuat dari cache: %d frame. Ubah config lalu \"Jalankan QPIV\" bila perlu.', nF)",
     "sprintf('Loaded from cache: %d frames. Change the config then \"Run QPIV\" if needed.', nF)", 1),
    ("sprintf('Cache tak terbaca (%s). Klik \"Jalankan QPIV\".', ME.message)",
     "sprintf('Cache unreadable (%s). Click \"Run QPIV\".', ME.message)", 1),
    ("sprintf('Exp \"%s\": belum ada QPIV. Klik \"Jalankan QPIV (exp terpilih)\".', expname)",
     "sprintf('Exp \"%s\": no QPIV yet. Click \"Run QPIV (selected exp)\".', expname)", 1),
    ("setStatus('Pilih sebuah eksperimen di tabel dulu.'); return; end",
     "setStatus('Pick an experiment in the table first.'); return; end", 1),
    ("setBusy(true,'Menjalankan QPIV pada strip tipis…');",
     "setBusy(true,'Running QPIV on the thin strip…');", 1),
    ("""            setBusy(false,sprintf('QPIV selesai: %d frame (strip %dpx). %d disarankan abaikan.', ...""",
     """            setBusy(false,sprintf('QPIV done: %d frames (strip %dpx). %d suggested for ignore.', ...""", 1),
    ("setBusy(false,'QPIV DIBATALKAN oleh pengguna — tak ada hasil disimpan.');",
     "setBusy(false,'QPIV CANCELLED by the user — nothing saved.');", 1),
    ("setBusy(false,sprintf('GAGAL QPIV: %s', ME.message));\n                uialert(fig, ME.message, 'QPIV gagal');",
     "setBusy(false,sprintf('QPIV FAILED: %s', ME.message));\n                uialert(fig, ME.message, 'QPIV failed');", 1),
    ("error('PAB0:cancel','Dibatalkan pengguna.'); end",
     "error('PAB0:cancel','Cancelled by the user.'); end", 1),
    ("setMid('Membatalkan QPIV… (menunggu langkah berjalan selesai).');",
     "setMid('Cancelling QPIV… (waiting for the current step to finish).');", 1),

    # ---- dt info -------------------------------------------------------
    ("sprintf('dt terbanyak (seharusnya) = %.3g s — baris merah = anomali', md)",
     "sprintf('most common dt (expected) = %.3g s — red rows = anomaly', md)", 1),
    ("dtInfoLbl.Text = '(dt EXIF tak terbaca)';", "dtInfoLbl.Text = '(dt EXIF unreadable)';", 1),
    ("dtInfoLbl.Text = '(dt EXIF gagal)';", "dtInfoLbl.Text = '(dt EXIF failed)';", 1),

    # ---- detect / clear / skip ----------------------------------------
    ("setStatus('Belum ada hasil QPIV — jalankan dulu.');",
     "setStatus('No QPIV result yet — run it first.');", 1),
    ("setStatus(sprintf('Auto-deteksi mati: %d frame ditandai (|V| < ambang). Anomali dt = baris merah (putuskan via ceklis).', nd));",
     "setStatus(sprintf('Dead auto-detect: %d frames marked (|V| < threshold). dt anomalies = red rows (decide via the checkmarks).', nd));", 1),
    ("setStatus('Semua ceklis dibersihkan.');", "setStatus('All checkmarks cleared.');", 1),
    ("setStatus('Jalankan QPIV dulu.'); return; end", "setStatus('Run QPIV first.'); return; end", 2),
    ("sprintf('Di luar 1..%d: %s', nF, mat2str(bad)),'Sebagian tak valid'",
     "sprintf('Outside 1..%d: %s', nF, mat2str(bad)),'Partly invalid'", 2),
    ("setStatus(sprintf('Ditambah %d frame (total %d/%d).', numel(vec), nnz(ignore), nF));",
     "setStatus(sprintf('Added %d frames (total %d/%d).', numel(vec), nnz(ignore), nF));", 1),
    ("setStatus(sprintf('Skip di-set ke %d frame (%d/%d).', numel(vec), nnz(ignore), nF));",
     "setStatus(sprintf('Skip set to %d frames (%d/%d).', numel(vec), nnz(ignore), nF));", 1),

    # ---- save / next ---------------------------------------------------
    ("uialert(fig,'Belum ada hasil QPIV untuk disimpan.','Kosong')",
     "uialert(fig,'No QPIV result to save yet.','Empty')", 1),
    ("setStatus('Kembalikan dulu ke tampilan semua sebelum simpan.');",
     "setStatus('Restore the all-frames view before saving.');", 1),
    ("if nF == 0; setStatus('Belum ada hasil untuk disimpan.'); return; end",
     "if nF == 0; setStatus('No result to save yet.'); return; end", 1),
    ("setStatus(sprintf('Tersimpan %d abaikan utk %s. Cari exp berikutnya…', nnz(ignore), expname));",
     "setStatus(sprintf('Saved %d ignores for %s. Looking for the next exp…', nnz(ignore), expname));", 1),
    ("setStatus('Seluruh eksperimen sudah selesai (QPIV + exclusion tersimpan).');",
     "setStatus('All experiments are finished (QPIV + exclusion saved).');", 1),
    ("if expSel < 1; setStatus('Pilih eksperimen dulu.'); return; end",
     "if expSel < 1; setStatus('Pick an experiment first.'); return; end", 1),
    ("saveMsg = sprintf('Tersimpan %d abaikan utk %s. ', nnz(ignore), expname);",
     "saveMsg = sprintf('Saved %d ignores for %s. ', nnz(ignore), expname);", 1),
    ("saveMsg = sprintf('%s belum di-QPIV — dilewati. ', expname);",
     "saveMsg = sprintf('%s has no QPIV yet — skipped. ', expname);", 1),
    ("setStatus([saveMsg 'Hanya 1 eksperimen.']);", "setStatus([saveMsg 'Only 1 experiment.']);", 1),
    ("setStatus([saveMsg 'Pindah ke exp berikutnya (tanpa QPIV)…']);",
     "setStatus([saveMsg 'Moving to the next exp (no QPIV)…']);", 1),
    ("setStatus(sprintf('Tersimpan: %d frame diabaikan untuk %s.', numel(vec), expname));",
     "setStatus(sprintf('Saved: %d frames ignored for %s.', numel(vec), expname));", 1),
    ("uialert(fig, sprintf('%d frame ditandai untuk diabaikan saat PIV penuh.', numel(vec)), ...\n                'Tersimpan','Icon','success');",
     "uialert(fig, sprintf('%d frames marked to be ignored during the full PIV.', numel(vec)), ...\n                'Saved','Icon','success');", 1),

    # ---- run all -------------------------------------------------------
    ("setStatus('Belum ada eksperimen — pilih root & scan dulu.');",
     "setStatus('No experiments yet — pick a root & scan first.');", 1),
    ("""        cfgStr = sprintf(['IW=[%s], #pass=%d, %s, posisi=%g%%, sudut=%g°, ' ...
            'pasangan=%s, skip=%d'], strtrim(sprintf('%d ',iw)), npass, lower(orient), ...""",
     """        cfgStr = sprintf(['IW=[%s], #pass=%d, %s, position=%g%%, angle=%g°, ' ...
            'pairing=%s, skip=%d'], strtrim(sprintf('%d ',iw)), npass, lower(orient), ...""", 1),
    ("""        msg = sprintf(['Jalankan QPIV pada eksperimen dengan parameter yang SAMA:\\n\\n%s\\n\\n' ...
            'Total %d exp — %d sudah selesai, %d belum.'], cfgStr, numel(exps), nDone, nLeft);""",
     """        msg = sprintf(['Run QPIV on the experiments with the SAME parameters:\\n\\n%s\\n\\n' ...
            'Total %d exps — %d finished, %d not yet.'], cfgStr, numel(exps), nDone, nLeft);""", 1),
    ("opts = {'Jalankan semua','Hanya yang belum','Batal'}; canOpt = 3;",
     "opts = {'Run all','Only unfinished','Cancel'}; canOpt = 3;", 1),
    ("opts = {'Jalankan semua','Batal'}; canOpt = 2;",
     "opts = {'Run all','Cancel'}; canOpt = 2;", 1),
    ("choice = uiconfirm(fig, msg, 'Run QPIV — semua eksperimen', ...",
     "choice = uiconfirm(fig, msg, 'Run QPIV — all experiments', ...", 1),
    ("if strcmp(choice,'Batal'); setStatus('Run semua dibatalkan.'); return; end",
     "if strcmp(choice,'Cancel'); setStatus('Run all cancelled.'); return; end", 1),
    ("onlyUnfinished = strcmp(choice,'Hanya yang belum');",
     "onlyUnfinished = strcmp(choice,'Only unfinished');", 1),
    ("if isempty(targets); setStatus('Tak ada exp yang perlu dijalankan.'); return; end",
     "if isempty(targets); setStatus('No exp needs running.'); return; end", 1),
    ("setBusy(true, sprintf('Run QPIV %d exp dengan parameter sama…', numel(targets)));",
     "setBusy(true, sprintf('Running QPIV on %d exps with identical parameters…', numel(targets)));", 1),
    ("dlg = uiprogressdlg(fig,'Title','QPIV semua eksperimen','Message','Mulai…','Cancelable','on');",
     "dlg = uiprogressdlg(fig,'Title','QPIV — all experiments','Message','Starting…','Cancelable','on');", 1),
    ("setMid(sprintf('Lewati %s: %s', exps(k).name, ME.message));",
     "setMid(sprintf('Skipped %s: %s', exps(k).name, ME.message));", 1),
    ("setStatus(sprintf('Run semua DIBATALKAN: %d selesai, %d gagal sebelum berhenti.', nOk, nFail));",
     "setStatus(sprintf('Run all CANCELLED: %d done, %d failed before stopping.', nOk, nFail));", 1),
    ("""            setStatus(sprintf(['Run semua selesai: %d/%d exp diproses & disimpan dengan ' ...
                'parameter sama%s.'], nOk, numel(targets), i_failNote(nFail)));""",
     """            setStatus(sprintf(['Run all finished: %d/%d exps processed & saved with ' ...
                'identical parameters%s.'], nOk, numel(targets), i_failNote(nFail)));""", 1),
    ("setStatus('Pilih exp yang akan dihapus dari daftar.'); return; end",
     "setStatus('Pick the exp to remove from the list.'); return; end", 1),
    ("setStatus(sprintf('\"%s\" dihapus dari daftar (berkas TIDAK dihapus dari disk).', nm));",
     "setStatus(sprintf('\"%s\" removed from the list (files were NOT deleted from disk).', nm));", 1),

    # ---- clean re-PIV --------------------------------------------------
    ("setStatus('Belum ada frame diabaikan. Tandai dulu lalu proses.');",
     "setStatus('No frame is ignored yet. Mark some first, then process.');", 1),
    ("uialert(fig,'Frame tersisa < 2 — tak bisa diproses.','Kosong');",
     "uialert(fig,'Fewer than 2 frames left — cannot process.','Empty');", 1),
    ("setBusy(true,sprintf('Memproses PIV BERSIH: %d gambar dipakai (%d dibuang)…', nKept, max(0,nDropImg)));",
     "setBusy(true,sprintf('Processing CLEAN PIV: %d images used (%d dropped)…', nKept, max(0,nDropImg)));", 1),
    ("setMid(sprintf('[bersih %3.0f%%] %s',100*f,m))",
     "setMid(sprintf('[clean %3.0f%%] %s',100*f,m))", 1),
    ("""            setBusy(false, sprintf(['Pratinjau PIV BERSIH: %d pasangan dari %d gambar bersih ' ...
                '(asli %d pasangan, dibuang %d frame). \"Kembalikan\" utk semula.'], ...""",
     """            setBusy(false, sprintf(['CLEAN PIV preview: %d pairs from %d clean images ' ...
                '(originally %d pairs, %d frames dropped). \"Restore\" to go back.'], ...""", 1),
    ("setBusy(false, sprintf('Gagal proses bersih: %s', ME.message));\n            uialert(fig, ME.message, 'Proses bersih gagal');",
     "setBusy(false, sprintf('Clean processing failed: %s', ME.message));\n            uialert(fig, ME.message, 'Clean processing failed');", 1),
    ("setStatus('Kembali ke tampilan semua frame (mode edit).');",
     "setStatus('Back to the all-frames view (edit mode).');", 1),

    # ---- render labels -------------------------------------------------
    ("ttl=[ttl '  [ABAIKAN]']; end", "ttl=[ttl '  [IGNORE]']; end", 1),
    ("if viewClean; ttl=['[BERSIH] ' ttl]; end", "if viewClean; ttl=['[CLEAN] ' ttl]; end", 1),
    ("ylabel(ax,'posisi (px)');", "ylabel(ax,'position (px)');", 1),
    ("tg=''; if viewClean; tg=' [BERSIH]'; end", "tg=''; if viewClean; tg=' [CLEAN]'; end", 2),
    ("title(ax,['axPSG — kymograph (kolom gelap = frame ~mati)' tg]);",
     "title(ax,['axPSG — kymograph (dark column = ~dead frame)' tg]);", 1),
    ("title(ax, sprintf('axPOT — f %d/%d · %d kurva%s', frame, nF, size(M,1), tg));",
     "title(ax, sprintf('axPOT — f %d/%d · %d curves%s', frame, nF, size(M,1), tg));", 1),

    # ---- frame table ---------------------------------------------------
    ("selLbl.Text='0 frame ditandai abaikan.'; return; end",
     "selLbl.Text='0 frames marked ignore.'; return; end", 1),
    ("selLbl.Text = sprintf('PRATINJAU BERSIH: %d frame.', nF);",
     "selLbl.Text = sprintf('CLEAN PREVIEW: %d frames.', nF);", 1),
    ("selLbl.Text = sprintf('%d / %d frame ditandai abaikan.', nnz(ignore), nF);",
     "selLbl.Text = sprintf('%d / %d frames marked ignore.', nnz(ignore), nF);", 1),
    ("selLbl.Text=sprintf('%d / %d frame ditandai abaikan.', nnz(ignore), nF);",
     "selLbl.Text=sprintf('%d / %d frames marked ignore.', nnz(ignore), nF);", 1),

    # ---- config change / preview --------------------------------------
    ("setMid('Konfigurasi berubah — klik \"Jalankan QPIV\".');",
     "setMid('Configuration changed — click \"Run QPIV\".');", 1),
    ("setMid('Posisi garis diubah — klik \"Jalankan QPIV\".');",
     "setMid('Line position changed — click \"Run QPIV\".');", 1),
    ("setMid('Sudut garis diubah — klik \"Jalankan QPIV\".');",
     "setMid('Line angle changed — click \"Run QPIV\".');", 1),
    ("""        title(axMain, sprintf('axMain — %s · garis %s, posisi %g%%, sudut %g°', ...""",
     """        title(axMain, sprintf('axMain — %s · %s line, position %g%%, angle %g°', ...""", 1),
    ("setMid(sprintf('Pratinjau GS gagal: %s', ME.message));",
     "setMid(sprintf('GS preview failed: %s', ME.message));", 1),

    # ---- step nav ------------------------------------------------------
    ("if busy; setStatus('Sedang sibuk — tunggu proses selesai.'); return; end",
     "if busy; setStatus('Busy — wait for the current process to finish.'); return; end", 1),
    ("setStatus('Menyimpan progres & menutup Step 0…');",
     "setStatus('Saving progress & closing Step 0…');", 1),
    ("uialert(fig, ME.message, 'Gagal membuka PABMASK');",
     "uialert(fig, ME.message, 'Failed to open PABMASK');", 1),

    # ---- local subfunction errors --------------------------------------
    ("error('PAB0:tooFew','Butuh >=2 gambar (setelah skip):\\n%s', rawFolder);",
     "error('PAB0:tooFew','Need >=2 images (after skip):\\n%s', rawFolder);", 1),
    ("error('PAB0:noImages','Tak ada gambar di:\\n%s', folder); end",
     "error('PAB0:noImages','No images in:\\n%s', folder); end", 1),
    ("    error('PAB0:cancel','Dibatalkan pengguna.');\nend",
     "    error('PAB0:cancel','Cancelled by the user.');\nend", 1),
    ("s = sprintf(' (%d gagal/dilewati)', nFail)", "s = sprintf(' (%d failed/skipped)', nFail)", 1),
]

TESTS = {
    'tests/test_screenshot_pab0.m': [
        ("    need = {'Sudut','Posisi','✖ Batal QPIV','▶ Jalankan QPIV', ...\n            '✓ Save ▸ Next ▸ QPIV','✓ Save ▸ Next (tanpa QPIV)','▶▶ QPIV semua exp', ...\n            'Auto-deteksi frame mati', ...\n            'Skip frame manual (mis 1,2,5-9):','💾 Save Progress','📂 Load Progress', ...\n            '🔒 IW','🔒 Pos','🔒 dll'};",
         "    need = {'Angle','Position','✖ Cancel QPIV','▶ Run QPIV', ...\n            '✓ Save ▸ Next ▸ QPIV','✓ Save ▸ Next (no QPIV)','▶▶ QPIV all exps', ...\n            'Auto-detect dead frames', ...\n            'Manual frame skip (e.g. 1,2,5-9):','💾 Save Progress','📂 Load Progress', ...\n            '🔒 IW','🔒 Pos','🔒 etc'};", 1),
        ("if iscell(cn) && any(strcmp(cn,'Abaikan')); frT = tbls(k); break; end",
         "if iscell(cn) && any(strcmp(cn,'Ignore')); frT = tbls(k); break; end", 1),
        ("assert(~isempty(frT), 'tabel frame (Abaikan) tak ditemukan');",
         "assert(~isempty(frT), 'tabel frame (Ignore) tak ditemukan');", 1),
        ("assert(numel(cs)>=4 && cs(end)==true, 'kolom Abaikan harus ColumnSortable=true');",
         "assert(numel(cs)>=4 && cs(end)==true, 'kolom Ignore harus ColumnSortable=true');", 1),
        ("fprintf('  [2b] frTable.ColumnSortable kolom Abaikan = true (asc/desc)\\n');",
         "fprintf('  [2b] frTable.ColumnSortable kolom Ignore = true (asc/desc)\\n');", 1),
    ],
    'tests/test_lock_pab0.m': [
        ("any(strcmp(cn,'Eksperimen'))", "any(strcmp(cn,'Experiment'))", 1),
    ],
    'tests/test_savenext_noqpiv_pab0.m': [
        ("i_findByText(btns, 'Save ▸ Next (tanpa QPIV)')",
         "i_findByText(btns, 'Save ▸ Next (no QPIV)')", 1),
        ("any(strcmp(cn,'Eksperimen'))", "any(strcmp(cn,'Experiment'))", 1),
    ],
    'tests/run_pab0_validate.m': [
        ("any(strcmp(cn,'Eksperimen'))", "any(strcmp(cn,'Experiment'))", 1),
    ],
}


def apply(relpath, pairs):
    p = ROOT / relpath
    txt = p.read_text(encoding='utf-8')
    errs = []
    for old, new, cnt in pairs:
        got = txt.count(old)
        if got != cnt:
            errs.append('  count %d (want %d): %r' % (got, cnt, old[:90]))
            continue
        txt = txt.replace(old, new)
    if errs:
        print('MISMATCH in %s:' % relpath)
        print('\n'.join(errs))
        return False
    p.write_text(txt, encoding='utf-8')
    print('OK  %-38s %d replacements' % (relpath, len(pairs)))
    return True


ok = apply('PAB0.m', PAB0)
for rel, pairs in TESTS.items():
    ok = apply(rel, pairs) and ok
sys.exit(0 if ok else 1)
