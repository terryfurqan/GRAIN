function out = pivprepFrameExclusion(peak, dt, opts)
%PIVPREPFRAMEEXCLUSION  Saran frame yang diabaikan: MATI (tak gerak) + interval.
%
%   out = pivprepFrameExclusion(peak, dt, opts)
%
%   = logika inti GRAINSA0b. Menggabungkan DUA detektor independen ke satu
%   daftar frame "abaikan", masing-masing dengan alasannya:
%
%     1. FRAME MATI (mesin berhenti gerak): |V| puncak QPIV < motionMin
%        (atau > motionMax bila diisi). Frame nyaris tak bergeser = tak ada
%        deformasi nyata -> abaikan.
%     2. INTERVAL TAK TERATUR (counter shutter balik ke 1): dt EXIF menyimpang
%        dari median lebih dari toleransi. Saat counter kamera roll-over,
%        foto itu diambil di luar irama interval -> dt jadi outlier -> abaikan.
%
%   Keduanya OPSIONAL (bisa dimatikan). Hasil OR digabung; alasan per-frame
%   dilaporkan agar pengguna paham kenapa sebuah frame disarankan dibuang.
%
%   INPUT:
%       peak  [1 x nF] atau [nF x 1] |V| puncak per frame (px/frame). [] = nonaktif.
%       dt    [nF x 1] interval detik per frame (NaN = tak diketahui). [] = nonaktif.
%       opts  struct:
%           .motionMin   ambang bawah |V| (default = auto 0.2*persentil90(peak)).
%           .motionMax   ambang atas |V| (default Inf = tak memotong).
%           .useMotion   logical (default true bila peak ada).
%           .useTime     logical (default true bila dt ada).
%           .dtTolFrac   toleransi relatif terhadap median dt (default 0.5 = ±50%).
%           .dtTolAbs    toleransi absolut detik (default 0 = abaikan).
%                        Frame ditandai bila |dt-median| > max(dtTolAbs, dtTolFrac*median).
%
%   OUTPUT out (struct):
%       .ignore     [1 x nF] logical gabungan (mati OR interval).
%       .deadMask   [1 x nF] logical detektor mati.
%       .timeMask   [1 x nF] logical detektor interval.
%       .reason     {1 x nF} cellstr ''|'mati'|'interval'|'mati+interval'.
%       .motionMin,.motionMax,.medianDt,.dtTol   ambang efektif yang dipakai.
%       .nFrames
%
%   Lihat juga: pivprepRawExifDt, PIVlab_automasi_qpiv, PAB_step_0b.

    if nargin < 3 || isempty(opts); opts = struct(); end
    peak = peak(:)'; dt = dt(:)';
    nF = max(numel(peak), numel(dt));
    out = struct();

    useMotion = i_getf(opts, 'useMotion', ~isempty(peak));
    useTime   = i_getf(opts, 'useTime',   ~isempty(dt));

    % --- Detektor MATI (|V| puncak) ---
    motionMin = i_getf(opts, 'motionMin', []);
    motionMax = i_getf(opts, 'motionMax', Inf);
    if isempty(motionMin); motionMin = i_autoThresh(peak); end
    if isempty(motionMax) || ~isfinite(motionMax); motionMax = Inf; end
    deadMask = false(1, nF);
    if useMotion && ~isempty(peak)
        pk = [peak, nan(1, nF - numel(peak))];
        deadMask = (pk < motionMin) | (pk > motionMax);
        deadMask(~isfinite(pk)) = false;   % |V| tak terhitung -> jangan auto-buang
    end

    % --- Detektor INTERVAL (dt EXIF) ---
    dtTolFrac = i_getf(opts, 'dtTolFrac', 0.5);
    dtTolAbs  = i_getf(opts, 'dtTolAbs',  0);
    medDt = NaN; dtTol = NaN;
    timeMask = false(1, nF);
    if useTime && ~isempty(dt)
        dd = [dt, nan(1, nF - numel(dt))];
        v  = dd(isfinite(dd));
        if ~isempty(v)
            medDt = median(v);
            dtTol = max(dtTolAbs, dtTolFrac * abs(medDt));
            if dtTol > 0
                timeMask = abs(dd - medDt) > dtTol;
            end
            timeMask(~isfinite(dd)) = false;   % dt tak diketahui -> jangan auto-buang
        end
    end

    ignore = deadMask | timeMask;

    reason = repmat({''}, 1, nF);
    for k = 1:nF
        if deadMask(k) && timeMask(k); reason{k} = 'mati+interval';
        elseif deadMask(k);           reason{k} = 'mati';
        elseif timeMask(k);           reason{k} = 'interval';
        end
    end

    out.ignore = ignore; out.deadMask = deadMask; out.timeMask = timeMask;
    out.reason = reason; out.motionMin = motionMin; out.motionMax = motionMax;
    out.medianDt = medDt; out.dtTol = dtTol; out.nFrames = nF;
end


% =====================================================================
function t = i_autoThresh(peak)
%I_AUTOTHRESH  Ambang mati = 20% persentil-90 |V| puncak (tahan thd frame mati).
%   Identik dgn i_autoThresh PIVlab_automasi_qpiv_GUI_V2 (konsistensi).
    v = peak(isfinite(peak));
    if isempty(v); t = 0; return; end
    p90 = i_pct(v, 90);
    t = 0.2 * p90;
    if ~(isfinite(t) && t > 0); t = 0.2 * max(v); end
    if ~(isfinite(t) && t > 0); t = 0; end
    t = round(t * 1000) / 1000;
end

function q = i_pct(v, p)
    v = sort(v(:)); n = numel(v);
    if n == 0; q = NaN; return; end
    if n == 1; q = v(1); return; end
    r = (p/100) * (n - 1) + 1;
    lo = floor(r); hi = ceil(r); fr = r - lo;
    q = v(lo) * (1 - fr) + v(hi) * fr;
end

function v = i_getf(s, f, d)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f)); v = s.(f); else; v = d; end
end
