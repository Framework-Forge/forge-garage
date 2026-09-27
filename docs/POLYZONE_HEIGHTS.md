# Limites verticais das PolyZones

O editor 3D do `pr_bridge` fornece `minZ`, `maxZ` e `thickness`. O
`forge-garage` preserva esses tres dados ao criar, editar, serializar e validar
uma garagem. O `pr_bridge` nao foi modificado.

Em terreno inclinado, abaixe o piso no editor ate cobrir o ponto mais baixo e
eleve o teto ate cobrir o ponto mais alto. Os pontos mantem seus valores Z e a
zona usa os limites absolutos escolhidos, em vez de recentrar uma parede fixa
de quatro metros pela media dos pontos.

Garagens antigas que possuem apenas `points` e `thickness` continuam sendo
interpretadas pelo comportamento compativel: menor/maior Z dos pontos mais
metade da espessura. Ao refazer a PolyZone pelo painel, `minZ` e `maxZ` passam a
ser gravados explicitamente.

Validacao local: `luac` nos consumidores alterados e `tests/zone_bounds.lua`.
Ainda e necessario validar em jogo uma garagem criada sobre declive, entrando
pelas extremidades baixa e alta e conferindo que o prompt nao oscila.
