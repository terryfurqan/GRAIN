function selectTableRow(tbl, row)
%SELECTTABLEROW  Pilih SATU baris di uitable + GULIR (scroll) ke baris itu agar
%   TERLIHAT di viewport (bukan sekadar tersorot di luar layar). Padanan
%   standalone dari pivterry.ui.selectTableRow. row < 1 / kosong -> no-op.
%   Semua best-effort (try/catch) agar tak menggagalkan handler lintas versi
%   MATLAB: SelectionType='row' & scroll() = uitable berbasis komponen (R2023b+).
    if nargin < 2 || isempty(row) || ~ishghandle(tbl), return; end
    row = round(row(1));
    if ~isfinite(row) || row < 1, return; end
    try
        if ~strcmp(tbl.SelectionType,'row'), tbl.SelectionType = 'row'; end
    catch
    end
    try
        tbl.Selection = row;
    catch
    end
    try
        scroll(tbl, 'row', row);
    catch
    end
end
