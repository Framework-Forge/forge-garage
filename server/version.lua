-- bridge/version.lua  (carregado no shared_scripts)
local CURRENT_VERSION = "1.4.5"
local REPO_OWNER = "Framework-Forge"
local REPO_NAME = "forge-garage"

-- Só roda no server para não abrir requisição no client
if IsDuplicityVersion() and Config.VersionCheck then
	CreateThread(function()
		-- Aguarda o server subir completamente
		Wait(5000)

		if pr_lib and pr_lib.versionCheck then
			pr_lib.versionCheck(("%s/%s"):format(REPO_OWNER, REPO_NAME))
		end
	end)
end
