classdef FakeKeyData < handle
%FAKEKEYDATA  Objek tiruan event WindowKeyPressFcn (meniru matlab.ui.eventdata.
%   KeyData) untuk uji hotkey. PENTING: karena ini OBJEK (bukan struct),
%   isfield(obj,'Modifier') SELALU false — persis seperti KeyData sungguhan di
%   GUI. Ini menangkap regresi "hotkey pakai isfield(evt,...)" yang tak kelihatan
%   bila test mengirim struct. Akses properti .Key/.Character/.Modifier langsung.
    properties
        Key = '';
        Character = '';
        Modifier = {};
    end
    methods
        function obj = FakeKeyData(key, ch, mods)
            if nargin >= 1, obj.Key = key; end
            if nargin >= 2, obj.Character = ch; end
            if nargin >= 3, obj.Modifier = mods; end
        end
    end
end
