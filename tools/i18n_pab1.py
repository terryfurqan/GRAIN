#!/usr/bin/env python3
"""Stage 2 of the ID -> EN UI-text migration: PAB1.m (+ its test stub).

Same rules as tools/i18n_pab0.py — user-visible text only.
"""
import sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

PAB1 = [
    # ---- entry dialog / window ---------------------------------------
    ("            'Pilih folder ROOT — semua subfolder akan dipindai sbg eksperimen');",
     "            'Pick a ROOT folder — every subfolder is scanned as an experiment');", 1),
    ("pivui.titleWithVersion('PAB1 (Step 1) — Penentuan ROI jitter/anchor multi-eksperimen')",
     "pivui.titleWithVersion('PAB1 (Step 1) — Multi-experiment jitter/anchor ROI setup')", 1),

    # ---- left column --------------------------------------------------
    ("'Title','Eksperimen (subfolder ROOT)'", "'Title','Experiments (ROOT subfolders)'", 1),
    ("'String','Pilih ROOT…', ...\n        'TooltipString','Pilih folder ROOT; subfolder dipindai sbg eksperimen.'",
     "'String','Pick ROOT…', ...\n        'TooltipString','Pick a ROOT folder; its subfolders are scanned as experiments.'", 1),
    ("'String','Pindai ulang', ...\n        'TooltipString','Pindai ulang subfolder (rekursif).'",
     "'String','Rescan', ...\n        'TooltipString','Rescan the subfolders (recursive).'", 1),
    ("'ColumnName',{'Eksperimen','Frame','ROI','Jitter','✓'}",
     "'ColumnName',{'Experiment','Frame','ROI','Jitter','✓'}", 1),
    ("'String','Hapus terpilih', ...\n        'TooltipString',['Buang eksperimen terpilih dari daftar (boleh banyak). ', ...\n                         'Folder di disk TIDAK dihapus — hanya keluar dari input Step 1.']",
     "'String','Remove selected', ...\n        'TooltipString',['Drop the selected experiments from the list (multi-select ok). ', ...\n                         'Folders on disk are NOT deleted — they just leave the Step 1 input.']", 1),
    ("'String','Kosongkan', ...\n        'TooltipString','Kosongkan seluruh daftar eksperimen (folder di disk tak disentuh).'",
     "'String','Clear all', ...\n        'TooltipString','Clear the whole experiment list (folders on disk are untouched).'", 1),
    ("'FontSize',8,'BackgroundColor',WHITE,'String','0 eksperimen.');",
     "'FontSize',8,'BackgroundColor',WHITE,'String','0 experiments.');", 1),

    # ---- middle column ------------------------------------------------
    ("'Title','Frame-1 + ROI  /  kurva jitter'", "'Title','Frame-1 + ROI  /  jitter curves'", 1),
    ("'String','ROI Persegi ▭', ...", "'String','ROI Rectangle ▭', ...", 1),
    ("'TooltipString','Tarik SEKALI -> ROI tersimpan. Lalu tekan \"Hitung Jitter\".'",
     "'TooltipString','Drag ONCE -> the ROI is saved. Then press \"Compute Jitter\".'", 1),
    ("'TooltipString','Klik titik-titik; tersimpan saat polygon ditutup. Tanpa double-click.'",
     "'TooltipString','Click the vertices; saved once the polygon closes. No double-click needed.'", 1),
    ("'String','Hapus ROI', ...", "'String','Clear ROI', ...", 1),
    ("'TooltipString','Hapus ROI exp ini.'", "'TooltipString','Clear this exp''s ROI.'", 1),
    ("'String','ROI: (belum)');", "'String','ROI: (none)');", 2),
    ("'String','⇇ ROI exp sebelumnya', ...", "'String','⇇ ROI from previous exp', ...", 1),
    ("'TooltipString',['Salin ROI dari eksperimen nomor urut SEBELUMNYA ke posisi ', ...\n                         'piksel yang sama. Bisa langsung diubah; lalu \"Hitung Jitter\".']",
     "'TooltipString',['Copy the ROI from the PREVIOUS experiment in the list to the ', ...\n                         'same pixel position. Editable right away; then \"Compute Jitter\".']", 1),
    ("'String','ROI ⇉ exp lain (kosong)', ...", "'String','ROI ⇉ other exps (empty)', ...", 1),
    ("'TooltipString',['Terapkan ROI exp ini ke SEMUA eksperimen yang BELUM punya ROI ', ...\n                         '(posisi piksel sama). Yang sudah ber-ROI tidak ditimpa.']",
     "'TooltipString',['Apply this exp''s ROI to EVERY experiment that has NO ROI yet ', ...\n                         '(same pixel position). Exps that already have one are not overwritten.']", 1),
    ("'String','Hitung jitter SEMUA ⏩', ...", "'String','Compute jitter for ALL ⏩', ...", 1),
    ("'TooltipString',['Hitung jitter untuk SEMUA eksperimen yang sudah ber-ROI ', ...\n                         '(lewati yang belum ber-ROI / sudah ada hasil).']",
     "'TooltipString',['Compute jitter for EVERY experiment that already has an ROI ', ...\n                         '(skips those without an ROI / that already have a result).']", 1),
    ("'String','Hitung Jitter ▶', ...", "'String','Compute Jitter ▶', ...", 1),
    ("'TooltipString','Ukur jitter ROI exp ini di seluruh frame & render 4 kurva.'",
     "'TooltipString','Measure this exp''s ROI jitter across all frames & render the 4 curves.'", 1),
    ("'String','✓ Simpan + Next Exp ▶', ...", "'String','✓ Save + Next Exp ▶', ...", 1),
    ("'TooltipString',['Tandai eksperimen ini SELESAI (saveNextSweep: sapu ke exp ', ...\n                         'belum-selesai berikutnya; pop-up bila semua tuntas).']",
     "'TooltipString',['Mark this experiment DONE (saveNextSweep: sweep to the next ', ...\n                         'unfinished exp; pop-up once everything is complete).']", 1),
    ("'String','✓ Simpan + Next + JIT! ▶', ...", "'String','✓ Save + Next + JIT! ▶', ...", 1),
    ("'TooltipString',['Simpan+Next, lalu OTOMATIS hitung jitter exp berikutnya ', ...\n                         'bila sudah ber-ROI (mis. ROI sama disebar ke semua exp).']",
     "'TooltipString',['Save+Next, then AUTOMATICALLY compute the next exp''s jitter ', ...\n                         'if it already has an ROI (e.g. one ROI spread to every exp).']", 1),
    ("title(h.ax,'Pilih eksperimen di kiri');", "title(h.ax,'Pick an experiment on the left');", 4),
    ("title(h.axJit,'Jitter per-bingkai (dx, dy)');", "title(h.axJit,'Per-frame jitter (dx, dy)');", 2),
    ("title(h.axCum,'Drift kumulatif (cumDx, cumDy)');", "title(h.axCum,'Cumulative drift (cumDx, cumDy)');", 2),

    # ---- right column -------------------------------------------------
    ("'Position',[0.734 0.01 0.260 0.985],'Title','Kontrol', ...",
     "'Position',[0.734 0.01 0.260 0.985],'Title','Controls', ...", 1),
    ("'FontWeight','bold','BackgroundColor',WHITE,'String','Parameter uji jitter');",
     "'FontWeight','bold','BackgroundColor',WHITE,'String','Jitter test parameters');", 1),
    ("'BackgroundColor',WHITE,'String','Metode:');", "'BackgroundColor',WHITE,'String','Method:');", 1),
    ("'String',{'SURF (fitur)','Phase-corr (patch)'}", "'String',{'SURF (features)','Phase-corr (patch)'}", 1),
    ("'TooltipString',['SURF: area kaya tekstur. Phase-corr: patch kecil/halus ', ...\n                         '(lebih andal utk area SANGAT kecil).']",
     "'TooltipString',['SURF: texture-rich areas. Phase-corr: small/smooth patches ', ...\n                         '(more reliable for VERY small areas).']", 1),
    ("'BackgroundColor',WHITE,'String','Pita acuan ±(px):');",
     "'BackgroundColor',WHITE,'String','Reference band ±(px):');", 1),
    ("'TooltipString','Pita ±N px sbg ACUAN VISUAL pd plot. Tidak menghakimi ROI.'",
     "'TooltipString','A ±N px band as a VISUAL REFERENCE on the plot. It does not judge the ROI.'", 1),
    ("'BackgroundColor',WHITE,'String','Maks frame (0=semua):');",
     "'BackgroundColor',WHITE,'String','Max frames (0=all):');", 1),
    ("'TooltipString','Batasi jumlah frame uji (cepat). 0 = pakai semua frame.'",
     "'TooltipString','Limit how many frames are tested (faster). 0 = use every frame.'", 1),
    ("'String','Hitung ulang (param di atas)', ...", "'String','Recompute (params above)', ...", 1),
    ("'TooltipString',['Hitung ULANG jitter exp terpilih dgn metode/maks-frame di atas. ', ...\n                         'Sama dgn \"Hitung Jitter\" di kolom tengah.']",
     "'TooltipString',['RECOMPUTE the selected exp''s jitter with the method/max-frames above. ', ...\n                         'Same as \"Compute Jitter\" in the middle column.']", 1),
    ("'String','Kumulatif ABSOLUT (panjang lintasan)', 'Value',0, ...",
     "'String','ABSOLUTE cumulative (path length)', 'Value',0, ...", 1),
    ("'TooltipString',['MATI = SIGNED: perpindahan bersih, +/- bisa saling ', ...\n                         'meniadakan. NYALA = ABSOLUT: jumlah |d| (selalu naik) ', ...\n                         '= total getaran. Hanya mengubah kurva & \"drift\", ', ...\n                         'bukan pengukuran frame.']",
     "'TooltipString',['OFF = SIGNED: net displacement, +/- can cancel each ', ...\n                         'other out. ON = ABSOLUTE: sum of |d| (always rising) ', ...\n                         '= total vibration. Changes only the curves & \"drift\", ', ...\n                         'not the per-frame measurement.']", 1),
    ("'FontWeight','bold','BackgroundColor',WHITE,'String','Navigasi');",
     "'FontWeight','bold','BackgroundColor',WHITE,'String','Navigation');", 1),
    ("'String','◀ Sebelumnya', ...", "'String','◀ Previous', ...", 1),
    ("'TooltipString','Ke eksperimen berikutnya (yang belum punya ROI bila ada).'",
     "'TooltipString','Go to the next experiment (preferring one without an ROI).'", 1),
    ("'FontSize',9,'BackgroundColor',WHITE,'String','Selesai: 0/0   ROI: 0/0');",
     "'FontSize',9,'BackgroundColor',WHITE,'String','Done: 0/0   ROI: 0/0');", 1),
    ("'String','💾 Simpan Progress', ...", "'String','💾 Save Progress', ...", 1),
    ("'TooltipString','Timpa <ROOT>/PAB1_progress.mat (ROI + hasil jitter semua exp). Tanpa dialog.'",
     "'TooltipString','Overwrite <ROOT>/PAB1_progress.mat (ROI + jitter results of every exp). No dialog.'", 1),
    ("'String','📂 Muat Progress', ...", "'String','📂 Load Progress', ...", 1),
    ("'TooltipString','Muat <ROOT>/PAB1_progress.mat (atau pilih berkas) — lanjut kerja ROI.'",
     "'TooltipString','Load <ROOT>/PAB1_progress.mat (or pick a file) — carry on with the ROI work.'", 1),
    ("'FontWeight','bold','BackgroundColor',WHITE,'String','Keluaran (input Step 2)');",
     "'FontWeight','bold','BackgroundColor',WHITE,'String','Output (Step 2 input)');", 1),
    ("'String','Ekspor → Step 2 (pilih lokasi)…', ...", "'String','Export → Step 2 (pick location)…', ...", 1),
    ("'TooltipString',['Tulis berkas progress BatchPIVPrep2 berisi semua exp + ', ...\n                         'anchor ke lokasi pilihan. Buka Step 2 -> Load Progress -> Run.']",
     "'TooltipString',['Write a BatchPIVPrep2 progress file holding every exp + ', ...\n                         'anchor to the chosen location. Open Step 2 -> Load Progress -> Run.']", 1),
    ("'String','Produksi MAT PREP → PAB2 ▶', ...", "'String','Produce MAT PREP → PAB2 ▶', ...", 1),
    ("'TooltipString',['Pilih LOKASI + NAMA folder keluaran, produksi MAT PREP ke sana ', ...\n                         '(+tempel resep masking dari PABMASK sbg sidecar), lalu buka PAB2. ', ...\n                         'Alur: PAB0 -> PABMASK -> PAB1 -> PAB2.']",
     "'TooltipString',['Pick the LOCATION + NAME of the output folder, produce MAT PREP there ', ...\n                         '(+attach the PABMASK masking recipe as a sidecar), then open PAB2. ', ...\n                         'Flow: PAB0 -> PABMASK -> PAB1 -> PAB2.']", 1),
    ("'String','…atau buka PABMASK di MAT PREP (lama)', ...",
     "'String','…or open PABMASK on MAT PREP (legacy)', ...", 1),
    ("'TooltipString',['Produksi MAT PREP lalu buka PABMASK MENUNJUK folder .mat ', ...\n                         '(alur lama PAB1->PABMASK). Pakai bila belum masking di foto mentah.']",
     "'TooltipString',['Produce MAT PREP then open PABMASK POINTED at the .mat folder ', ...\n                         '(legacy PAB1->PABMASK flow). Use it if the raw photos were not masked yet.']", 1),
    ("'String','Simpan anchor exp ini…', ...", "'String','Save this exp''s anchor…', ...", 1),
    ("'TooltipString','Simpan preset anchor exp terpilih (.mat) — utk Load manual di Step 1.'",
     "'TooltipString','Save the selected exp''s anchor preset (.mat) — for a manual Load in Step 1.'", 1),
    ("'String','Ekspor PNG kurva exp ini…', ...", "'String','Export this exp''s curves as PNG…', ...", 1),
    ("'TooltipString','Simpan plot jitter (2 panel) exp terpilih sbg PNG.'",
     "'TooltipString','Save the selected exp''s jitter plot (2 panels) as a PNG.'", 1),

    # ---- help text block ----------------------------------------------
    ("""        'String',{ ...
            'Alur:', ...
            ' 1. Pilih exp di kiri.', ...
            ' 2. Gambar ROI KECIL di bagian', ...
            '    yang SEHARUSNYA DIAM (rangka', ...
            '    tetap — BUKAN pasir/dinding', ...
            '    pendorong). ▭ tarik sekali.', ...
            ' 3. Tekan \"Hitung Jitter ▶\"; cek 4', ...
            '    kurva. Drift = getaran eksternal', ...
            '    yg akan di-nol-kan Step 1.', ...
            ' 4. \"Simpan + Next\" -> sapu ke exp', ...
            '    belum-selesai berikutnya.', ...
            ' 5. \"Ekspor/Buka Step 1\".', ...
            '', ...
            'Pintasan ROI:', ...
            ' • \"⇇ ROI exp sebelumnya\": pinjam', ...
            '   ROI (posisi sama), ubah bila perlu.', ...
            ' • \"ROI ⇉ exp lain\": sebar ke semua', ...
            '   exp yang belum ber-ROI.', ...
            'Drift: toggle SIGNED (bersih) vs', ...
            'ABSOLUT (panjang lintasan/total).', ...
            '', ...
            'Crop tiap exp = full-frame;', ...
            'atur crop sebenarnya di Step 1.'});""",
     """        'String',{ ...
            'Flow:', ...
            ' 1. Pick an exp on the left.', ...
            ' 2. Draw a SMALL ROI on a part', ...
            '    that SHOULD BE STILL (fixed', ...
            '    frame — NOT the sand/pushing', ...
            '    wall). ▭ drag once.', ...
            ' 3. Press \"Compute Jitter ▶\"; check', ...
            '    the 4 curves. Drift = external', ...
            '    vibration, zeroed out in Step 1.', ...
            ' 4. \"Save + Next\" -> sweep to the', ...
            '    next unfinished exp.', ...
            ' 5. \"Export/Open Step 1\".', ...
            '', ...
            'ROI shortcuts:', ...
            ' • \"⇇ ROI from previous exp\": borrow', ...
            '   the ROI (same spot), edit if needed.', ...
            ' • \"ROI ⇉ other exps\": spread it to', ...
            '   every exp without an ROI.', ...
            'Drift: toggle SIGNED (net) vs', ...
            'ABSOLUTE (path length/total).', ...
            '', ...
            'Crop of each exp = full-frame;', ...
            'set the real crop in Step 1.'});""", 1),
    ("'String','Pilih ROOT lalu pindai subfolder.');",
     "'String','Pick a ROOT, then scan its subfolders.');", 1),

    # ---- scan ----------------------------------------------------------
    ("d = uigetdir(h.root, 'Pilih folder ROOT (subfolder dipindai sbg eksperimen)');",
     "d = uigetdir(h.root, 'Pick a ROOT folder (subfolders are scanned as experiments)');", 1),
    ("i_setStatus(fig,'Memindai subfolder…');", "i_setStatus(fig,'Scanning subfolders…');", 1),
    ("sprintf('Gagal memindai: %s', ME.message)", "sprintf('Scan failed: %s', ME.message)", 1),
    ("set(h.txtCount,'String','0 eksperimen (tak ada subfolder berisi gambar).');",
     "set(h.txtCount,'String','0 experiments (no subfolder holds images).');", 1),
    ("i_setStatus(fig,'Tak ada subfolder berisi urutan gambar di ROOT ini.');",
     "i_setStatus(fig,'No subfolder in this ROOT holds an image sequence.');", 1),
    ("set(h.txtCount,'String',sprintf('%d eksperimen ditemukan.', numel(exps)));",
     "set(h.txtCount,'String',sprintf('%d experiments found.', numel(exps)));", 1),
    ("i_setStatus(fig, sprintf('⚠ PEMETAAN QPIV: %s', strjoin(warnExps, '  |  ')));",
     "i_setStatus(fig, sprintf('⚠ QPIV MAPPING: %s', strjoin(warnExps, '  |  ')));", 1),
    ("""            i_setStatus(fig,sprintf(['%d eksperimen. %d exp tersaring QPIV (total %d gambar ' ...
                'di-drop) — hanya frame lolos QPIV yang dipakai.'], numel(exps), nFiltered, nDropTot));""",
     """            i_setStatus(fig,sprintf(['%d experiments. %d exps filtered by QPIV (%d images ' ...
                'dropped) — only frames that passed QPIV are used.'], numel(exps), nFiltered, nDropTot));""", 1),
    ("i_setStatus(fig,sprintf('%d eksperimen. Pilih satu, lalu gambar ROI.', numel(exps)));",
     "i_setStatus(fig,sprintf('%d experiments. Pick one, then draw an ROI.', numel(exps)));", 1),

    # ---- table labels --------------------------------------------------
    ("if isempty(e.roiBox), lbl = '—'; else, lbl = '(siap)'; end",
     "if isempty(e.roiBox), lbl = '—'; else, lbl = '(ready)'; end", 1),
    ("lbl = '! ukur'; return;", "lbl = '! meas'; return;", 1),

    # ---- delete / clear list -------------------------------------------
    ("if n == 0, i_setStatus(fig,'Daftar kosong.'); return; end",
     "if n == 0, i_setStatus(fig,'The list is empty.'); return; end", 2),
    ("        i_setStatus(fig,'Pilih dulu eksperimen di tabel yang mau dihapus.'); return;",
     "        i_setStatus(fig,'Select the experiments to remove in the table first.'); return;", 1),
    ("q = sprintf('Hapus eksperimen \"%s\" dari daftar?', nm);",
     "q = sprintf('Remove experiment \"%s\" from the list?', nm);", 1),
    ("q = sprintf('Hapus %d eksperimen terpilih dari daftar?', numel(rows));",
     "q = sprintf('Remove %d selected experiments from the list?', numel(rows));", 1),
    ("""    btn = questdlg([q char(10) char(10) ...
        'Folder di disk TIDAK dihapus — hanya keluar dari input Step 1.'], ...
        'PAB1 — Hapus dari daftar', 'Hapus', 'Batal', 'Batal');
    if ~strcmp(btn,'Hapus'), return; end""",
     """    btn = questdlg([q char(10) char(10) ...
        'Folders on disk are NOT deleted — they just leave the Step 1 input.'], ...
        'PAB1 — Remove from list', 'Remove', 'Cancel', 'Cancel');
    if ~strcmp(btn,'Remove'), return; end""", 1),
    ("    set(h.txtCount,'String',sprintf('%d eksperimen.', numel(h.exps)));",
     "    set(h.txtCount,'String',sprintf('%d experiments.', numel(h.exps)));", 1),
    ("    i_setStatus(fig, sprintf('%d eksperimen dihapus dari daftar (folder di disk utuh).', ...",
     "    i_setStatus(fig, sprintf('%d experiments removed from the list (folders on disk intact).', ...", 1),
    ("if isempty(h.exps), i_setStatus(fig,'Daftar sudah kosong.'); return; end",
     "if isempty(h.exps), i_setStatus(fig,'The list is already empty.'); return; end", 1),
    ("""    btn = questdlg(['Kosongkan SELURUH daftar eksperimen?' char(10) char(10) ...
        'Folder di disk TIDAK dihapus.'], ...
        'PAB1 — Kosongkan daftar', 'Kosongkan', 'Batal', 'Batal');
    if ~strcmp(btn,'Kosongkan'), return; end""",
     """    btn = questdlg(['Clear the WHOLE experiment list?' char(10) char(10) ...
        'Folders on disk are NOT deleted.'], ...
        'PAB1 — Clear list', 'Clear', 'Cancel', 'Cancel');
    if ~strcmp(btn,'Clear'), return; end""", 1),
    ("    set(h.txtCount,'String','0 eksperimen.');", "    set(h.txtCount,'String','0 experiments.');", 1),
    ("i_setStatus(fig,'Daftar dikosongkan. Pindai ulang ROOT bila perlu.');",
     "i_setStatus(fig,'List cleared. Rescan the ROOT if needed.');", 1),

    # ---- load exp ------------------------------------------------------
    ("        msg = sprintf('Exp %d/%d: %s — gambar ROI kecil di bagian diam.', ...",
     "        msg = sprintf('Exp %d/%d: %s — draw a small ROI on a still part.', ...", 1),
    ("        msg = sprintf('Exp %d/%d: %s — ROI ada; tekan \"Hitung Jitter ▶\".', ...",
     "        msg = sprintf('Exp %d/%d: %s — ROI set; press \"Compute Jitter ▶\".', ...", 1),
    ("        msg = sprintf('Exp %d/%d: %s — drift |%.2f| px.', ...",
     "        msg = sprintf('Exp %d/%d: %s — drift |%.2f| px.', ...", 1),
    ("        axis(h.ax,'off'); title(h.ax,'(gagal baca frame-1)'); return;",
     "        axis(h.ax,'off'); title(h.ax,'(failed to read frame-1)'); return;", 1),

    # ---- draw ROI ------------------------------------------------------
    ("if row < 1, i_setStatus(fig,'Pilih eksperimen dulu.'); return; end",
     "if row < 1, i_setStatus(fig,'Pick an experiment first.'); return; end", 1),
    ("i_setStatus(fig,'Gambar ROI sekarang (tarik/klik)…');",
     "i_setStatus(fig,'Draw the ROI now (drag/click)…');", 1),
    ("i_setStatus(fig, sprintf('Gagal menggambar ROI: %s', ME.message));",
     "i_setStatus(fig, sprintf('Failed to draw the ROI: %s', ME.message));", 1),
    ("i_setStatus(fig,'ROI dibatalkan.'); return;", "i_setStatus(fig,'ROI cancelled.'); return;", 1),
    ("i_setStatus(fig,'ROI batal (terlalu kecil).'); return;",
     "i_setStatus(fig,'ROI dropped (too small).'); return;", 1),
    ("i_setStatus(fig,'ROI batal (polygon < 3 titik).'); return;",
     "i_setStatus(fig,'ROI dropped (polygon has < 3 points).'); return;", 1),
    ("if isempty(img), i_setStatus(fig,'Gagal baca frame-1.'); return; end",
     "if isempty(img), i_setStatus(fig,'Failed to read frame-1.'); return; end", 1),
    ("if isempty(img1), i_setStatus(fig,'Gagal baca frame-1.'); return; end",
     "if isempty(img1), i_setStatus(fig,'Failed to read frame-1.'); return; end", 1),
    ("    i_setStatus(fig, sprintf('ROI[%.0f %.0f %.0f %.0f] tersimpan — tekan \"Hitung Jitter ▶\".', ...",
     "    i_setStatus(fig, sprintf('ROI[%.0f %.0f %.0f %.0f] saved — press \"Compute Jitter ▶\".', ...", 1),
    ("i_setStatus(fig,'ROI dihapus untuk exp ini.');", "i_setStatus(fig,'ROI cleared for this exp.');", 1),

    # ---- borrow / spread ROI -------------------------------------------
    ("        i_setStatus(fig,'Tak ada eksperimen sebelumnya.'); return;",
     "        i_setStatus(fig,'There is no previous experiment.'); return;", 1),
    ("        i_setStatus(fig, sprintf('Exp sebelumnya (\"%s\") belum punya ROI.', prev.name));",
     "        i_setStatus(fig, sprintf('The previous exp (\"%s\") has no ROI yet.', prev.name));", 1),
    ("if ~ok, i_setStatus(fig,'Gagal baca frame-1 exp ini.'); return; end",
     "if ~ok, i_setStatus(fig,'Failed to read this exp''s frame-1.'); return; end", 1),
    ("    i_setStatus(fig, sprintf(['ROI dari \"%s\" disalin. Ubah bila perlu, lalu ', ...\n        '\"Hitung Jitter ▶\".'], prev.name));",
     "    i_setStatus(fig, sprintf(['ROI copied from \"%s\". Edit if needed, then ', ...\n        '\"Compute Jitter ▶\".'], prev.name));", 1),
    ("        i_setStatus(fig,'Pilih exp ber-ROI dulu.'); return;",
     "        i_setStatus(fig,'Pick an exp that has an ROI first.'); return;", 3),
    ("        i_setStatus(fig,'Semua eksperimen lain sudah punya ROI (tak ada yg ditimpa).');",
     "        i_setStatus(fig,'Every other experiment already has an ROI (nothing overwritten).');", 1),
    ("    msg = sprintf('ROI \"%s\" diterapkan ke %d exp yang belum ber-ROI.', src.name, nApplied);",
     "    msg = sprintf('ROI \"%s\" applied to %d exps that had no ROI.', src.name, nApplied);", 1),
    ("    if nFail > 0, msg = sprintf('%s (%d gagal baca frame).', msg, nFail); end",
     "    if nFail > 0, msg = sprintf('%s (%d failed to read a frame).', msg, nFail); end", 1),
    ("        set(h.txtRoiInfo,'String','ROI: (belum)'); return;",
     "        set(h.txtRoiInfo,'String','ROI: (none)'); return;", 0),

    # ---- compute -------------------------------------------------------
    ("wb = i_makeWaitbar(sprintf('Hitung jitter \"%s\"…', e.name));",
     "wb = i_makeWaitbar(sprintf('Computing jitter for \"%s\"…', e.name));", 1),
    ("i_setStatus(fig, ['Gagal: ' R.failMsg]); return;",
     "i_setStatus(fig, ['Failed: ' R.failMsg]); return;", 1),
    ("R.failMsg = 'Tak ada fitur SURF di ROI (coba ROI bertekstur / Phase-corr).';",
     "R.failMsg = 'No SURF features inside the ROI (try a textured ROI / Phase-corr).';", 1),
    ("    msg = sprintf('Exp \"%s\": %d frame, drift |%.2f| px.', e.name, nUse, R.driftMag);",
     "    msg = sprintf('Exp \"%s\": %d frames, drift |%.2f| px.', e.name, nUse, R.driftMag);", 1),
    ("    if nFail>0, msg = sprintf('%s  (%d frame gagal diukur)', msg, nFail); end",
     "    if nFail>0, msg = sprintf('%s  (%d frames could not be measured)', msg, nFail); end", 1),
    ("    if n == 0, i_setStatus(fig,'Daftar kosong.'); return; end",
     "    if n == 0, i_setStatus(fig,'The list is empty.'); return; end", 0),
    ("            i_setStatus(fig,'Semua exp ber-ROI sudah punya hasil jitter.');",
     "            i_setStatus(fig,'Every exp with an ROI already has a jitter result.');", 1),
    ("            i_setStatus(fig,'Belum ada exp ber-ROI. Gambar/sebar ROI dulu.');",
     "            i_setStatus(fig,'No exp has an ROI yet. Draw/spread one first.');", 1),
    ("wb = i_makeWaitbar('Hitung jitter SEMUA eksperimen…');",
     "wb = i_makeWaitbar('Computing jitter for ALL experiments…');", 1),
    ("        i_setStatus(fig, sprintf('Hitung jitter SEMUA — exp %d/%d: \"%s\"…', ...",
     "        i_setStatus(fig, sprintf('Jitter for ALL — exp %d/%d: \"%s\"…', ...", 1),
    ("    i_setStatus(fig, sprintf('Selesai menghitung jitter %d eksperimen.', nDone));",
     "    i_setStatus(fig, sprintf('Finished computing jitter for %d experiments.', nDone));", 1),
    ("wb = waitbar(0, msg, 'Name','PAB1 — progres jitter');",
     "wb = waitbar(0, msg, 'Name','PAB1 — jitter progress');", 1),

    # ---- curves --------------------------------------------------------
    ("        axis(axT,'off'); title(axT,'Jitter per-bingkai (dx, dy)');",
     "        axis(axT,'off'); title(axT,'Per-frame jitter (dx, dy)');", 1),
    ("        axis(axB,'off'); title(axB,'Drift kumulatif (cumDx, cumDy)');",
     "        axis(axB,'off'); title(axB,'Cumulative drift (cumDx, cumDy)');", 1),
    ("        title(axT,'Jitter — tidak terukur');", "        title(axT,'Jitter — not measurable');", 1),
    ("    ylabel(axT,'piksel');", "    ylabel(axT,'pixels');", 1),
    ("    xlabel(axB,'Frame'); ylabel(axB,'piksel');", "    xlabel(axB,'Frame'); ylabel(axB,'pixels');", 1),
    ("    title(axT, sprintf('%s — jitter per-bingkai (dx, dy)', head),'Interpreter','none');",
     "    title(axT, sprintf('%s — per-frame jitter (dx, dy)', head),'Interpreter','none');", 1),
    ("    title(axB, sprintf('drift kumulatif [%s] — akhir |%.2f| px', modeStr, drift), ...",
     "    title(axB, sprintf('cumulative drift [%s] — final |%.2f| px', modeStr, drift), ...", 1),

    # ---- export / handoff ----------------------------------------------
    ("        i_setStatus(fig,'Belum ada exp ber-ROI untuk diekspor.'); return;",
     "        i_setStatus(fig,'No exp with an ROI to export yet.'); return;", 1),
    ("    [fn, fp] = uiputfile({'*.mat','BatchPIVPrep2 progress (*.mat)'}, ...\n        'Ekspor progress (Load di Step 1)', def);",
     "    [fn, fp] = uiputfile({'*.mat','BatchPIVPrep2 progress (*.mat)'}, ...\n        'Export progress (Load it in Step 1)', def);", 1),
    ("        i_setStatus(fig, sprintf('Diekspor: %s (%d exp). Buka Step 1 -> Load Progress.', ...",
     "        i_setStatus(fig, sprintf('Exported: %s (%d exps). Open Step 1 -> Load Progress.', ...", 1),
    ("        i_setStatus(fig, sprintf('Gagal ekspor: %s', ME.message));",
     "        i_setStatus(fig, sprintf('Export failed: %s', ME.message));", 1),
    ("        i_setStatus(fig,'Belum ada exp ber-ROI. Gambar ROI dulu.'); return;",
     "        i_setStatus(fig,'No exp has an ROI yet. Draw one first.'); return;", 1),
    ("""        btn = questdlg(sprintf([ ...
            '%d eksperimen ber-ROI BELUM lewat QPIV (Step 0).' char(10) char(10) ...
            'Frame diam/mati (mesin berhenti) belum tersaring, jadi SEMUA frame ' ...
            'akan ikut dikemas dan MEMBESARKAN MAT PREP.' char(10) char(10) ...
            'Sebaiknya jalankan Step 0 (PAB0) dulu. Tetap lanjut memproduksi?'], ...
            nNoQpiv), ...
            'PAB1 — Eksperimen belum di-QPIV', 'Tetap lanjut', 'Batal', 'Batal');
        if ~strcmp(btn,'Tetap lanjut')
            i_setStatus(fig, sprintf(['Dibatalkan — %d exp belum di-QPIV. ' ...
                'Jalankan Step 0 (PAB0) dulu agar frame mati tak membesarkan MAT PREP.'], ...
                nNoQpiv));""",
     """        btn = questdlg(sprintf([ ...
            '%d exps with an ROI have NOT been through QPIV (Step 0).' char(10) char(10) ...
            'Still/dead frames (machine stopped) are not filtered out yet, so EVERY frame ' ...
            'gets packed and BLOATS the MAT PREP.' char(10) char(10) ...
            'Better run Step 0 (PAB0) first. Produce anyway?'], ...
            nNoQpiv), ...
            'PAB1 — Experiments without QPIV', 'Produce anyway', 'Cancel', 'Cancel');
        if ~strcmp(btn,'Produce anyway')
            i_setStatus(fig, sprintf(['Cancelled — %d exps have no QPIV. ' ...
                'Run Step 0 (PAB0) first so dead frames do not bloat the MAT PREP.'], ...
                nNoQpiv));""", 1),
    ("        i_setStatus(fig,'Dibatalkan — lokasi keluaran MAT PREP belum dipilih.'); return;",
     "        i_setStatus(fig,'Cancelled — no MAT PREP output location was picked.'); return;", 1),
    ("    i_setStatus(fig, sprintf('Memproduksi MAT PREP %d exp ke %s …', prog.nAnchored, prepDir));",
     "    i_setStatus(fig, sprintf('Producing MAT PREP for %d exps into %s …', prog.nAnchored, prepDir));", 1),
    ("        i_setStatus(fig, sprintf('Produksi MAT PREP gagal: %s', ME.message)); return;",
     "        i_setStatus(fig, sprintf('MAT PREP production failed: %s', ME.message)); return;", 1),
    ("""        i_setStatus(fig, ['Tidak ada MAT PREP yang dihasilkan (cek log konsol). ', ...
            'Modul lanjutan tidak diluncurkan.']);""",
     """        i_setStatus(fig, ['No MAT PREP was produced (check the console log). ', ...
            'The next module was not launched.']);""", 1),
    ("        i_setStatus(fig, sprintf('%d MAT PREP + %d resep masking ditempel (sidecar).', nMat, nSide));",
     "        i_setStatus(fig, sprintf('%d MAT PREP + %d masking recipes attached (sidecar).', nMat, nSide));", 1),
    ("            i_setStatus(fig, sprintf('%d MAT PREP dibuat. Meluncurkan PABMASK (masking)…', nMat));",
     "            i_setStatus(fig, sprintf('%d MAT PREP created. Launching PABMASK (masking)…', nMat));", 1),
    ("                warning('PAB1:openMask', 'MAT PREP tersimpan di %s tapi PABMASK gagal dibuka: %s', ...",
     "                warning('PAB1:openMask', 'MAT PREP saved in %s but PABMASK failed to open: %s', ...", 1),
    ("            i_setStatus(fig, sprintf('%d MAT PREP dibuat. Meluncurkan Step 2 (PAB2)…', nMat));",
     "            i_setStatus(fig, sprintf('%d MAT PREP created. Launching Step 2 (PAB2)…', nMat));", 1),
    ("                warning('PAB1:openStep2', 'MAT PREP tersimpan di %s tapi PAB2 gagal dibuka: %s', ...",
     "                warning('PAB1:openStep2', 'MAT PREP saved in %s but PAB2 failed to open: %s', ...", 1),
    ("        parentDir = uigetdir(startDir, 'Pilih LOKASI folder keluaran MAT PREP (input Step 2)');",
     "        parentDir = uigetdir(startDir, 'Pick the LOCATION of the MAT PREP output folder (Step 2 input)');", 1),
    ("    answer = inputdlg('Nama folder keluaran MAT PREP:', 'Nama folder keluaran', ...",
     "    answer = inputdlg('Name of the MAT PREP output folder:', 'Output folder name', ...", 1),
    ("        i_setStatus(fig, sprintf('Gagal buat folder keluaran: %s', ME.message));",
     "        i_setStatus(fig, sprintf('Failed to create the output folder: %s', ME.message));", 1),

    # ---- PAB1 progress -------------------------------------------------
    ("if isempty(h.exps), i_setStatus(fig,'Belum ada eksperimen untuk disimpan.'); return; end",
     "if isempty(h.exps), i_setStatus(fig,'No experiment to save yet.'); return; end", 1),
    ("        i_setStatus(fig, sprintf('Progress PAB1 disimpan: %s (%d exp, %d ber-ROI).', ...",
     "        i_setStatus(fig, sprintf('PAB1 progress saved: %s (%d exps, %d with an ROI).', ...", 1),
    ("        i_setStatus(fig, sprintf('Gagal simpan progress PAB1: %s', ME.message));",
     "        i_setStatus(fig, sprintf('Failed to save the PAB1 progress: %s', ME.message));", 1),
    ("        [fn, fp] = uigetfile({'*.mat','Progress PAB1 (*.mat)'}, ...\n            'Muat progress PAB1', h.root);",
     "        [fn, fp] = uigetfile({'*.mat','PAB1 progress (*.mat)'}, ...\n            'Load the PAB1 progress', h.root);", 1),
    ("        i_setStatus(fig, sprintf('Gagal baca progress: %s', ME.message)); return;",
     "        i_setStatus(fig, sprintf('Failed to read the progress: %s', ME.message)); return;", 1),
    ("        i_setStatus(fig,'Berkas bukan progress PAB1 yang sah.'); return;",
     "        i_setStatus(fig,'That file is not a valid PAB1 progress.'); return;", 1),
    ("    i_setStatus(fig, sprintf('Progress PAB1 dimuat: %d/%d exp dipulihkan dari %s', ...",
     "    i_setStatus(fig, sprintf('PAB1 progress loaded: %d/%d exps restored from %s', ...", 1),
    ("        i_setStatus(fig,'Belum ada exp ber-ROI untuk disimpan.'); return;",
     "        i_setStatus(fig,'No exp with an ROI to save yet.'); return;", 1),
    ("        i_setStatus(fig, sprintf('Progress disimpan: %s (%d exp ber-ROI).', ...",
     "        i_setStatus(fig, sprintf('Progress saved: %s (%d exps with an ROI).', ...", 1),
    ("        i_setStatus(fig, sprintf('Gagal simpan progress: %s', ME.message));",
     "        i_setStatus(fig, sprintf('Failed to save the progress: %s', ME.message));", 1),

    # ---- done / next ---------------------------------------------------
    ("        i_setStatus(fig,'Pilih eksperimen dulu.'); return;",
     "        i_setStatus(fig,'Pick an experiment first.'); return;", 2),
    ("        i_setStatus(fig,'Belum ada ROI. Gambar ROI dulu.'); return;",
     "        i_setStatus(fig,'No ROI yet. Draw one first.'); return;", 2),
    ("        i_setStatus(fig,'Hitung jitter dulu (hasil belum ada / gagal terukur).'); return;",
     "        i_setStatus(fig,'Compute the jitter first (no result yet / measurement failed).'); return;", 2),
    ("""        i_setStatus(fig, sprintf(['Exp \"%s\" selesai. SELURUH %d eksperimen sudah ' ...
            'dianalisis — lanjut \"Simpan Progress\" / \"Buka di Step 2\".'], doneName, n));""",
     """        i_setStatus(fig, sprintf(['Exp \"%s\" done. ALL %d experiments have been ' ...
            'analysed — carry on with \"Save Progress\" / \"Open in Step 2\".'], doneName, n));""", 1),
    ("            i_setStatus(fig, sprintf('Exp \"%s\" SELESAI. Lanjut \"%s\" — menghitung jitter…', ...",
     "            i_setStatus(fig, sprintf('Exp \"%s\" DONE. Next \"%s\" — computing jitter…', ...", 1),
    ("    i_setStatus(fig, sprintf('Exp \"%s\" ditandai SELESAI. Lanjut ke exp \"%s\" (belum selesai)…', ...",
     "    i_setStatus(fig, sprintf('Exp \"%s\" marked DONE. Moving to exp \"%s\" (unfinished)…', ...", 1),

    # ---- anchor / PNG ---------------------------------------------------
    ("    [fn, fp] = uiputfile({'*.mat','Preset anchor (*.mat)'}, 'Simpan preset anchor', def);",
     "    [fn, fp] = uiputfile({'*.mat','Anchor preset (*.mat)'}, 'Save the anchor preset', def);", 1),
    ("        i_setStatus(fig, sprintf('Anchor tersimpan: %s', out));",
     "        i_setStatus(fig, sprintf('Anchor saved: %s', out));", 1),
    ("        i_setStatus(fig, sprintf('Gagal simpan anchor: %s', ME.message));",
     "        i_setStatus(fig, sprintf('Failed to save the anchor: %s', ME.message));", 1),
    ("        i_setStatus(fig,'Belum ada kurva exp ini untuk diekspor.'); return;",
     "        i_setStatus(fig,'This exp has no curve to export yet.'); return;", 1),
    ("    [fn, fp] = uiputfile({'*.png','PNG (*.png)'}, 'Simpan plot jitter (2 panel)', def);",
     "    [fn, fp] = uiputfile({'*.png','PNG (*.png)'}, 'Save the jitter plot (2 panels)', def);", 1),
    ("        i_setStatus(fig, sprintf('Tersimpan: %s', out));",
     "        i_setStatus(fig, sprintf('Saved: %s', out));", 1),
    ("        i_setStatus(fig, sprintf('Gagal ekspor PNG: %s', ME.message));",
     "        i_setStatus(fig, sprintf('PNG export failed: %s', ME.message));", 1),

    # ---- sidecar warnings / console ------------------------------------
    ("                warning('PAB1:maskSidecar', 'Gagal tulis resep kotak utk %s: %s', matPath, ME.message);",
     "                warning('PAB1:maskSidecar', 'Failed to write the rect recipe for %s: %s', matPath, ME.message);", 1),
    ("                warning('PAB1:polySidecar', 'Gagal tulis resep polygon utk %s: %s', matPath, ME.message);",
     "                warning('PAB1:polySidecar', 'Failed to write the polygon recipe for %s: %s', matPath, ME.message);", 1),
    ("""            ['%d resep masking aktif di progres, tapi hanya %d sidecar tertulis. ' ...
             'Sisanya kemungkinan tak cocok key folder (bentuk path PABMASK vs PAB1 ' ...
             'berbeda) -> MAT PREP itu TANPA masking. Periksa root yang sama.'], ...""",
     """            ['%d masking recipes are active in the progress, but only %d sidecars were written. ' ...
             'The rest probably failed the folder-key match (PABMASK vs PAB1 path shapes ' ...
             'differ) -> those MAT PREP have NO masking. Check that the root is the same.'], ...""", 1),
    ("    fprintf('[PAB1] sidecar masking: %d resep aktif, %d tertulis (dari %d MAT PREP).\\n', ...",
     "    fprintf('[PAB1] masking sidecars: %d recipes active, %d written (out of %d MAT PREP).\\n', ...", 1),
    ("""            info.mapWarn = sprintf(['QPIV simpan %d nama, TAK ADA yang cocok di ' ...
                'folder (rename/salah folder?). Semua %d frame dipakai.'], ...""",
     """            info.mapWarn = sprintf(['QPIV stored %d names, NONE of them match this ' ...
                'folder (renamed/wrong folder?). All %d frames are used.'], ...""", 1),
    ("            info.mapWarn = sprintf('QPIV %d nama, cocok %d, %d tak ditemukan di folder.', ...",
     "            info.mapWarn = sprintf('QPIV had %d names, %d matched, %d not found in the folder.', ...", 1),

    # ---- misc ----------------------------------------------------------
    ("    set(h.txtProg,'String',sprintf('Selesai: %d/%d   ROI: %d/%d', nDone, n, nRoi, n));",
     "    set(h.txtProg,'String',sprintf('Done: %d/%d   ROI: %d/%d', nDone, n, nRoi, n));", 1),
    ("        i_setStatus(fig,'Mode drift kumulatif: ABSOLUT (panjang lintasan, cumsum|d|).');",
     "        i_setStatus(fig,'Cumulative drift mode: ABSOLUTE (path length, cumsum|d|).');", 1),
    ("        i_setStatus(fig,'Mode drift kumulatif: SIGNED (perpindahan bersih, cumsum d).');",
     "        i_setStatus(fig,'Cumulative drift mode: SIGNED (net displacement, cumsum d).');", 1),
]

TESTS = {}   # tests/test_smoke_pab_step0.m questdlg stub 'Hapus'->'Remove' already applied


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


ok = apply('PAB1.m', PAB1)
for rel, pairs in TESTS.items():
    ok = apply(rel, pairs) and ok
sys.exit(0 if ok else 1)
