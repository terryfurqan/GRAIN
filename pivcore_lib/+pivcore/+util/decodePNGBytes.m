function png = decodePNGBytes(bytes)
%DECODEPNGBYTES  Decode blob PNG (uint8) -> citra. Pembungkus tipis
%   pivcore.util.decodeBlob(bytes,'png'). Sebelumnya i_decodePNG di GRAINSA1a/1b.
    png = pivcore.util.decodeBlob(bytes, 'png');
end
