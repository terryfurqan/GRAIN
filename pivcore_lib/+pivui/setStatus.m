function setStatus(fig, msg)
%SETSTATUS  Tulis pesan ke strip status sebuah GUI (field guidata h.txtStatus).
%   No-op aman bila figure tak punya txtStatus / handle invalid / SUDAH DIHANCURKAN.
%   SATU sumber — sebelumnya disalin byte-identik sebagai i_setStatus di GRAINSA1a/1b/3/3a.
%   GUARD fig-valid: callback bisa terpicu saat figure sedang destroy (DestroyedObject
%   Callback) -> guidata(fig) lempar "Object must be a figure". Abaikan diam-diam.
    if isempty(fig) || ~ishghandle(fig), return; end
    try, h = guidata(fig); catch, return; end
    if isfield(h,'txtStatus') && ishghandle(h.txtStatus)
        try, set(h.txtStatus,'String',msg); drawnow limitrate; catch, end
    end
end
