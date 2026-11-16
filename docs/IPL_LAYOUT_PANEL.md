# Painel de layout das garagens IPL

Implementado em 19/09/2026. Usa menus, diálogos, callbacks, zonas e editor 3D nativos do PR Bridge. Não acrescenta dependência de OX Lib, OX Target ou conexão SQL direta.

## Configurar como administrador

1. Execute `/garagelist` ou abra Garagens no painel ForgeCore.
2. Escolha uma garagem IPL e abra **IPL, Acessos e Elevadores → Painel de layout**.
3. Use **Ir ao interior para posicionar**. A garagem precisa de modelo e de um ponto interno/preview válidos.
4. Selecione **Criar NPC do painel**. Defina acesso público ou residencial. No residencial, selecione o imóvel da lista; não é necessário digitar coordenadas ou o ID do imóvel.
5. Escolha o modelo do NPC e a distância do target (1 a 3 metros). No DevTools, posicione e gire o NPC com preview, clique para fixar e pressione **Enter**. **Backspace** cancela. São salvos o modelo, XYZ e heading retornados pelo posicionador, sem subtrair altura nem buscar outro chão.
6. Depois de criado, use **Mover / trocar NPC do painel**, **Editar acesso do painel**, **Teleportar ao ponto do painel**, **Abrir e pré-visualizar aparência** ou **Remover ponto do painel**.
7. As setas de retorno preservam o menu pai do IPL e a navegação administrativa existente até o ForgeCore.

O acesso é pelo target nativo do PR Bridge no NPC, sem DrawMarker nem texto de tecla E. O NPC é local à garagem ativa: é removido ao sair, editar, excluir ou parar o recurso. O teleporte administrativo coloca o jogador ao lado do NPC.

Pontos antigos recebem um NPC padrão na coordenada já salva. Se aquela coordenada estava incorreta, use **Mover / trocar NPC do painel** para gravar a posição correta pelo DevTools.

## Personalização disponível

| Interiores | Opções |
|---|---|
| CEO Arcadius, Maze Bank, Lombank e Maze Bank West, modelos A/B/C | 4 acabamentos (concreto, liso, mármore, madeira), 9 iluminações e 9 estilos de numeração |
| Eclipse Boulevard | 3 acabamentos, 5 numerações e 12 cores |
| Outros modelos | O menu informa que ainda não há variações cadastradas; não aplica acabamentos incompatíveis |

O catálogo em `shared/ipl_visual.lua` usa entity sets conferidos nos arquivos locais do bob74_ipl, sem chamar seus exports. Acrescentar um interior exige cadastrar suas variações reais. Mudar acabamento não muda as coordenadas de entradas, vagas ou elevadores. Trocar o **modelo IPL** no criador remove o ponto de layout e as escolhas anteriores, exigindo posicionar o painel no novo interior.

## Acesso e persistência

- Público: qualquer usuário que satisfaça os requisitos de emprego/gangue da garagem pode usar o painel no interior.
- Residencial: exige acesso ao imóvel no ps-housing (proprietário ou morador autorizado, conforme o serviço de casas). Se o housing estiver parado, o acesso é negado. Administradores podem gerenciar o visual para configuração.
- O servidor valida ponto, distância, instância, permissões e opções do catálogo. O jogador não envia nomes arbitrários de entity sets.
- O visual fica em `ipl.visual` e o ponto em `ipl.manager` de `data/garages.json`, por garagem. Uma instância com o mesmo modelo mantém suas próprias escolhas.
- O preview é local. Cancelar, fechar o menu ou afastar-se restaura o último visual salvo. **Salvar aparência** publica a alteração para os jogadores daquela garagem e persiste em disco.
- Se outro jogador salvar enquanto o painel estiver aberto, o visual é atualizado e o painel deve ser reaberto. Revisões antigas não sobrescrevem o estado novo.
- Remover o ponto conserva a aparência salva. A troca do modelo reinicia a personalização.

## Roteiro de testes em jogo

Faça em uma garagem de teste, sem veículos/jogadores no interior durante o reinício do recurso. Carregue os arquivos com `restart forge-garage` no console.

1. Configure o painel em uma garagem CEO; confirme o preview do NPC e que cancelar não cria nem move o NPC. Teleporte até ele e confira a posição.
2. Entre a pé por uma entrada normal, use o target no NPC, escolha mármore e uma iluminação. Feche sem salvar: deve voltar ao visual anterior. Repita e salve: deve permanecer.
3. Saia e entre novamente. Depois repita após reiniciar o recurso fora do interior: o ponto e a aparência devem persistir.
4. Com dois jogadores na mesma garagem, salve uma mudança: ambos devem vê-la. Abra o painel em ambos; salve em um e confirme que o outro não consegue publicar a revisão antiga.
5. Crie outra garagem usando o mesmo modelo IPL em outro bucket. Personalize cada uma e alterne entre elas: os visuais não podem se misturar.
6. Em Eclipse Boulevard, teste as cores claras/escuras e a combinação com os três acabamentos; confirme que não aparecem dois acabamentos sobrepostos.
7. Configure acesso residencial, vincule o imóvel e teste proprietário, morador autorizado e estranho. O estranho não deve abrir nem salvar. Teste também acesso público e garagem com emprego restrito.
8. Mova o NPC, altere o modelo/rotação e a distância do target; confirme que só a posição nova responde. Remova o painel: a interação desaparece e o visual fica salvo.
9. Navegue de volta do preview para o painel de layout, depois para IPL e ForgeCore. Teste cancelar diálogos e editor, verificando que o personagem recupera o controle.
10. Troque o modelo no criador. Confirme o aviso e reposicione o painel no novo interior.

## Validação automatizada


Sintaxe Lua e as suítes existentes de migração, banco, parquímetro e zonas passaram. Renderização e interação real do FiveM dependem do roteiro acima; não foram executadas nesta entrega.

Validação adicional: posição XYZ, modelo e heading de NPC persistidos sem deslocamento; target nativo; cancelamento de carregamento, ausência de duplicação e limpeza durante edição/saída. Teste também NPC em piso elevado: depois de salvar, ele deve coincidir com o preview.

Correção de carregamento do NPC: teleportes de elevadores/vagas identificam a garagem ativa; o NPC local não depende de IsInteriorReady para existir e fica protegido como entidade de missão. O ciclo de sincronização recupera NPC removido e repete falhas de modelo/criação a cada 5 segundos, sem duplicar entidades. Falhas são registradas no console F8 com o nome da garagem. A posição já salva é preservada.

Correção da altura: o NPC salvo reaplica `pr_lib.fivem.streaming.setEntityTransform` com `noOffset=false`, exatamente como o preview de ped do DevTools. A coordenada do editor é uma posição de colocação e não deve ser reaplicada com `SetEntityCoordsNoOffset`. Nenhum metro fixo é acrescentado e nenhum novo chão é procurado; pontos já salvos não precisam ser refeitos. Validação Lua executa o helper real do PR Bridge e verifica o encaminhamento para `SetEntityCoords`.
