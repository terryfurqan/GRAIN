function monitor = updateMonitor(monitor, frameIdx, dx, dy, jitMag, elapsed)
%UPDATEMONITOR  Perbarui data plot monitor untuk satu frame.
%
%   monitor = pivprep.ui.updateMonitor(monitor, frameIdx, dx, dy, jitMag, elapsed)
%
%   INPUT:
%       monitor   struct hasil pivprep.ui.buildMonitor (akan diperbarui)
%       frameIdx  indeks frame saat ini (1..nFrames)
%       dx        pergeseran horizontal SIGNED untuk frame ini (px)
%       dy        pergeseran vertikal SIGNED untuk frame ini (px)
%       jitMag    magnitude jitter (hypot(dx,dy)) untuk frame ini (px)
%       elapsed   waktu sejak batch dimulai (detik)
%
%   OUTPUT:
%       monitor   struct yang sama dengan vektor data diperbarui
%
%   Implementasi:
%   - Hanya 'set' XData/YData pada line yang sudah ada. Sumbu, label,
%     judul, dan legend TIDAK dibangun ulang tiap frame.
%   - Menggunakan 'drawnow limitrate' agar repaint tidak menghambat
%     loop processing.
%   - Aman terhadap user menutup jendela monitor (figure handle dicek).
%
%   ETA dihitung dari rate frame/detik dan ditampilkan dalam dua format:
%   detik eksplisit dan HH:MM:SS.

    if isempty(monitor) || ~isfield(monitor, 'fig') || ~ishandle(monitor.fig)
        return;
    end

    util = pivprep.util.utilities;

    % --- Update buffer data ---
    monitor.frames(end + 1) = frameIdx;

    if monitor.useStab
        monitor.instX(end + 1)   = dx;
        monitor.instY(end + 1)   = dy;
        monitor.magInst(end + 1) = jitMag;
        monitor.sumX             = monitor.sumX + dx;
        monitor.sumY             = monitor.sumY + dy;
        monitor.cumX(end + 1)    = monitor.sumX;
        monitor.cumY(end + 1)    = monitor.sumY;

        % --- Update line: hanya XData/YData ---
        if ishandle(monitor.lineInstX)
            set(monitor.lineInstX, ...
                'XData', monitor.frames, 'YData', monitor.instX);
        end
        if ishandle(monitor.lineInstY)
            set(monitor.lineInstY, ...
                'XData', monitor.frames, 'YData', monitor.instY);
        end
        if ishandle(monitor.lineMagInst)
            set(monitor.lineMagInst, ...
                'XData', monitor.frames, 'YData', monitor.magInst);
        end
        if ishandle(monitor.lineCumX)
            set(monitor.lineCumX, ...
                'XData', monitor.frames, 'YData', monitor.cumX);
        end
        if ishandle(monitor.lineCumY)
            set(monitor.lineCumY, ...
                'XData', monitor.frames, 'YData', monitor.cumY);
        end
    end

    % --- Update progress bar (vektor X poligon fill) ---
    if ishandle(monitor.barProgress)
        set(monitor.barProgress, ...
            'XData', [0, frameIdx, frameIdx, 0]);
    end

    % --- Hitung ETA ---
    nF        = monitor.nFrames;
    rate      = frameIdx / max(elapsed, 0.001);              % frame/detik
    remaining = max(0, (nF - frameIdx) / max(rate, 0.001));   % detik

    % --- Update judul progress dan teks status ---
    if ishandle(monitor.axProg)
        title(monitor.axProg, sprintf( ...
            'Progress  |  %d / %d frames  |  Elapsed: %.0f s  |  Rate: %.2f fps', ...
            frameIdx, nF, elapsed, rate), 'FontWeight', 'bold');
    end

    if ishandle(monitor.txtStatus)
        if frameIdx >= nF
            statusStr = sprintf('DONE  |  Total: %.0f s (%s)', ...
                elapsed, util.secsToHMS(elapsed));
        else
            statusStr = sprintf( ...
                'ETA: %.0f s tersisa  (%s)  -  estimasi selesai dalam %.1f menit', ...
                remaining, util.secsToHMS(remaining), remaining / 60);
        end
        set(monitor.txtStatus, 'String', statusStr);
        % Geser teks mengikuti center bar agar selalu terbaca
        set(monitor.txtStatus, 'Position', [nF / 2, 1, 0]);
    end

    drawnow limitrate;
end
