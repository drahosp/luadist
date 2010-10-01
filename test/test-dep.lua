local dist = require "dist"

-- Get test dists
local dists = dist.getDists("./dists")

print (dist.install("alpha","=< 2","./_test-dep", dists))
local installed = dist.getDeployedDists("./_test_dep")

for k, v in pairs(installed) do
	print (k, v, v.name or "", v.version or "")
end
