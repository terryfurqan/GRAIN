function test_smoke_pab4b(rootDir)
%TEST_SMOKE_PAB4B  [WRAPPER] PAB4B kini forwarder ke PAB4 terpadu. Uji nyata ada
%   di test_smoke_pab4 (Komentar + Label HW + Net-slip dalam 1 app, 1 truth).
    if nargin < 1, test_smoke_pab4(); else, test_smoke_pab4(rootDir); end
end
