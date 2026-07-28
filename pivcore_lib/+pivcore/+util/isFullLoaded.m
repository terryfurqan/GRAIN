function tf = isFullLoaded(h)
%ISFULLLOADED  TRUE bila SEMUA bingkai sudah dimuat (field h.fullLoaded),
%   dikembalikan sebagai skalar logical yang AMAN untuk operator && (cegah error
%   operand non-skalar bila field kosong/array).
%   Sebelumnya disalin sebagai i_isFull di PABSA3/3a.
    tf = false;
    if isfield(h,'fullLoaded') && ~isempty(h.fullLoaded)
        tf = logical(h.fullLoaded(1));
    end
end
