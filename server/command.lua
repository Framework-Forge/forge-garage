pr_lib.addCommand(locale("command.admin.garagelist"), {
    help = locale("command.admin.garagelistHelp"),
    restricted = 'group.admin'
}, function(source, args, raw)
    TriggerClientEvent("forge_garage:client:garagelist", source)
end)
