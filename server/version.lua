local REPO_OWNER = "Framework-Forge"
local REPO_NAME = "forge-garage"

if IsDuplicityVersion() then
    CreateThread(function()
        Wait(5000)
        if Config.VersionCheck then
            if pr_lib and pr_lib.versionCheck then
                pr_lib.versionCheck(("%s/%s"):format(REPO_OWNER, REPO_NAME))
            end
        end
    end)
end
