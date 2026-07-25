pr_lib.addCommand(GarageBridge.locale("command.admin.garagelist"), {
    help = GarageBridge.locale("command.admin.garagelistHelp"),
    restricted = 'group.admin'
}, function(source, args, raw)
    TriggerClientEvent("forge_garage:client:garagelist", source)
end)
