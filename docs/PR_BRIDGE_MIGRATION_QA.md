# Forge Garage — migração PR Bridge e testes

## Estado da entrega

Implementado em 2026-09-18. O manifesto depende de `pr_bridge`. Banco usa `pr_lib.database`; target usa `pr_lib.target`; combustível usa `pr_lib.fuel`; catálogo/persistência usam `pr_lib.framework`; consultas de itens de chave usam `pr_lib.inventory`.
Menus, diálogos, notificações, callbacks e comandos continuam no PR Bridge. As integrações específicas de chaves, polícia, banco/faturas, casas e telefone foram preservadas; a migração não torna esses fluxos de negócio independentes dos respectivos serviços.

Os state bags de identidade/placa original e falsa, trancas e persistência continuam replicados.
O schema continua sendo o da base Forge/QBX (`player_vehicles`, `players` e tabelas da garagem); trocar o driver SQL não converte esse schema para outra framework.

## Carregar a mudança

1. Mantenha o driver de banco escolhido e o `pr_bridge` iniciados antes do Garage. O OXMySQL pode continuar como driver indireto.
2. Para testar apenas esta migração, no console do servidor execute `restart forge-garage`. A inicialização do consumidor recarrega os módulos atualizados do PR Bridge.
3. Confirme que o console não registra erro de import, módulo, callback ou SQL. Para carregar as mudanças compartilhadas em todos os consumidores, use a próxima reinicialização programada da base.
4. Não remova o OXLib globalmente só por esta entrega: os demais consumidores ainda constam na fila de migração.

## Roteiro no jogo

| Etapa | Ação | Resultado esperado |
|---|---|---|
| Administração | Como admin, execute `/garagelist` ou entre pelo `/forgecore` > garagens. | Listagem abre; ao usar ForgeCore, voltar leva ao menu pai. |
| Criação | Crie uma garagem de teste, desenhe a zona e posicione NPC/vagas; edite e salve. | Preview, target, menus e dados persistem; cancelar o editor devolve o controle. |
| Acesso | Tente abrir com e sem emprego/permissão exigidos. | Somente usuários autorizados acessam os pontos restritos. |
| Guardar/retirar | Guarde e retire um veículo próprio com chave. | Mesmo veículo/placa, combustível, tuning e danos; sem duplicação. |
| Placa falsa | Repita com um veículo que já tenha placa falsa configurada. | Placa falsa continua visível e o registro original continua sendo usado para ownership/chaves/persistência. |
| Vários veículos | Abra uma garagem com chaves de dois ou mais veículos. | A lista contém os registros corretos, sem erro SQL no filtro por placas. |
| Chaves | Execute `/keymanager`; veja chaves originais/cópias e teste uma cópia ou reposição. | Itens/metadados são reconhecidos e cobrança/devolução continuam corretas. |
| Transferência | Com dois jogadores, transfira um veículo, incluindo um com placa falsa. | Ownership, acesso e pagamento seguem as regras anteriores; cancelamento não transfere. |
| Persistência | Guarde em garagem persistente, afaste-se e volte; saia da vaga e retorne. | Um único veículo é exibido e seu estado guardado/fora é coerente. |
| Parquímetro | Use um terminal, pague e teste permanência, saída, multa e quitação. | Cobrança e débito persistem corretamente; não duplica sessão/multa. |
| Apreensão | Como policial, use o target do veículo e apreenda; depois pague/libere. | Registro da apreensão, cobrança e estado do veículo permanecem coerentes. |
| IPL | Selecione um interior, use preview, entradas, elevadores e vagas. | Acesso e retorno funcionam; veículos e jogadores não ficam em bucket incorreto. |
| Telefone | Consulte a lista de veículos no aplicativo de garagem. | Catálogo, nomes e estados aparecem sem chamada direta ao QB Core. |
| Reinício | Após guardar, desconecte/reconecte e repita após `restart forge-garage`. | Dados, vagas e placas permanecem corretos; sem targets duplicados. |

## Validação já executada

- Sintaxe Lua 5.4: 44 arquivos do Garage e dos módulos/testes PR Bridge envolvidos.
- `tests/bridge_migration.lua`: parâmetros SQL, placas originais/falsas, erros de escrita, target, combustível e catálogo.
- `pr_bridge/tests/database_garage.lua`: contratos dos três drivers com exports simulados, callbacks, affectedRows, transações e framework QBX/QB.
- `tests/parking_billing.lua`, `tests/parking_config.lua`, `tests/zone_bounds.lua`: cobrança, pausa, restauração, limites e configuração.
- Nenhum teste acima valida a física, rede ou interface real do FiveM; esses itens dependem do roteiro em jogo.
- Nenhuma consulta ou alteração foi feita no banco real durante os testes.

## Certificação dos drivers alternativos

Em uma cópia da base e do banco, inicie somente o driver escolhido (MySQL Async ou GHMattiMySQL), ajuste a seleção no PR Bridge e repita o roteiro.
Verifique leitura de linhas, ID de inserção, zero/uma linha afetada, retorno de callbacks e disponibilidade no boot.
Em uma tabela descartável do banco de teste, execute uma transação com duas escritas, forçando a segunda a falhar: a primeira não deve permanecer gravada.
Os testes isolados comprovam o encaminhamento da transação inteira ao driver; commit/rollback real precisa dessa homologação.

Contratos consultados: [MySQL Async](https://github.com/brouznouf/fivem-mysql-async/blob/master/lib/MySQL.lua), [implementação MySQL Async](https://github.com/brouznouf/fivem-mysql-async/blob/master/src/entry/server.ts) e [GHMattiMySQL](https://github.com/FrazzIe/ghmattimysql/blob/master/src/index.js).

## Contratos públicos acrescentados ao PR Bridge

| API | Retorno |
|---|---|
| pr_lib.database.update(query, params, callback?) | Número de linhas afetadas; nil se o adaptador não obteve resultado. Com callback, entrega esse valor ao callback. |
| pr_lib.database.execute(query, params, callback?) | Mantém o retorno bruto do driver; não foi convertido em número globalmente. |
| pr_lib.database.transaction(statements, params?, callback?) | Encaminha uma transação ao driver; aceita strings com parâmetros compartilhados ou instruções com values/parameters individuais. |
| pr_lib.framework.GetVehiclesByHash(model?) | Catálogo indexado pelo hash ou registro de um modelo; consulta QBX/QB dentro do bridge. |
| pr_lib.framework.GetVehicleData(model) | Registro do modelo (nome/hash), ou nil quando desconhecido. |
| pr_lib.framework.SetVehiclePersistence(vehicle, enabled) | Servidor: delega ao QBX quando ativo; demais provedores usam a política de entidade órfã. |

No adaptador de combustível sem provedor, GetFuel/SetFuel usam o nível nativo do veículo.
