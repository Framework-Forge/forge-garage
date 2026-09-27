# Parquimetros como pontos de pagamento

## Retorno automatico em todas as garagens persistentes

O retorno independe de cobranca, parquimetro ou lista de vagas: vale para todo
veiculo registrado na persistencia, incluindo garagens gratuitas e IPL.
Em Regras da Garagem > Retorno automatico ao estacionamento, configure o prazo
(padrao 120s). O campo persistenceCooldownSeconds tem prioridade sobre o prazo
legado do parquimetro. Os dois editores atualizam a mesma configuracao.
Garagens sem persistencia nao participam. Sessoes gratuitas nunca geram multas
ou pagamentos. A referencia e a posicao registrada ao estacionar; o retorno
so ocorre parado e a ate 6m dela. O cadastro e atualizado no servidor e no cache.
Veiculos persistentes ja existentes sao recuperados pelo monitor, com verificacao
a cada 30s; novos registros entram diretamente pelo fluxo de persistencia.
Testar em garagem gratuita com prazo de 15s: destrancar, permanecer, conferir
tranca/registro, destrancar de novo e sair antes do prazo; nenhuma divida nova.

## Configuracao de pagamento

No criador: ative persistencia e cobranca por parquimetro.
Em garagem existente: Regras da Garagem > Parquimetros.
O painel permite definir tarifa, unidade, conta e prazo apos destrancar
(padrao 120 segundos; configuravel entre 10 e 86400 segundos reais).

Nao existe vinculo obrigatorio entre parquimetro e vaga. Um terminal atende
todos os veiculos autorizados do estacionamento; havendo varios, o jogador
seleciona a placa para pagar. A ocupacao continua sendo controlada por vaga.

- **Usar os existentes no mapa**: nao exige encontrar ou cadastrar objetos.
  O admin recebe aviso: sem prop_parknmeter_01 ou prop_parknmeter_02 a ate
  30m de alguma vaga, o jogador nao conseguira pagar. O target dos modelos
  consulta a garagem mais proxima dinamicamente, inclusive apos streaming.
- **Posicionar parquimetros**: quantidade independente das vagas (inclusive zero,
  com aviso), modelo por terminal e posicionamento pelo editor 3D.
  Ao editar tarifas/prazo, e possivel manter as posicoes cadastradas.
- As configuracoes anteriores com terminais por vaga continuam legiveis,
  mas cada terminal passa a aceitar pagamentos de todo o estacionamento.

## Cobranca
- Estacionar em vaga livre inicia sessao pela placa e notifica a tarifa.
- Hora/dia e fracao: arredondamento para cima, minimo uma unidade.
- A cobranca acompanha diretamente `GlobalState.currentTime`, publicado pelo
  relogio sincronizado da base. Se o tempo acelerar, desacelerar ou congelar,
  a cobranca acompanha esse comportamento. O painel nao pede conversao manual.
- Alteracoes administrativas grandes no horario apenas reposicionam a referencia;
  elas nao geram varias horas de cobranca instantanea.
- Destrancar pausa o total pelo prazo configurado. Alterar o prazo no painel
  afeta os proximos desbloqueios; nao altera janelas ja iniciadas.
- Pagamento quita o total acumulado daquela sessao.
- Saida fisica e detectada pelo servidor quando o veiculo se afasta mais de 6m
  do centro da vaga. Acelerar sem deslocar nao encerra a sessao.
- Sair sem pagamento gera divida ativa; sair pago encerra sem divida.
- Permanecer apos o prazo retoma cobranca (inclusive depois de pagar).
  Ao confirmar o veiculo parado (<0.4 m/s), ainda a ate 6m da vaga, o servidor
  restaura estado 1 no banco, garagem/coordenadas, registro persistente e tranca.
  Os clientes recebem a limpeza do estado liberado e a atualizacao do cache.
  Nao congela um carro em movimento: a restauracao aguarda ele parar na vaga.
- Somente um novo ciclo de trancar/destrancar pode iniciar nova pausa.
- Reinicio preserva sessoes, valores e prazo; a passagem de tempo offline conta
  conforme a duracao configurada.
- Debitos antigos nao sao cobrados junto com o estacionamento atual.
- Apenas veiculos estacionados apos configurar esta versao iniciam novas sessoes.
  Debitos legados continuam consultaveis. Sessoes antecipadas legadas nao sao convertidas.

## Integracao servidor com MDT

O garage registra a divida mesmo sem MDT. Nao altera o ps-mdt automaticamente.

No servidor do ps-mdt / forge-police:
```lua
exports('ReceiveParkingDebt', function(debt)
    -- Grave no MDT usando debt.id como chave UNICA/idempotente.
    -- debt: id, plate, garage, meter_id, amount, created_at.
    -- Retorne true SOMENTE depois de confirmar a gravacao.
    return false -- substituir pela integracao real
end)

-- Executar quando ambos recursos estiverem iniciados; repetir quando garage reiniciar.
exports['forge-garage']:RegisterParkingDebtHandler('ReceiveParkingDebt')
```

O garage envia pendencias a cada 10 segundos, com retry ate receber true.
Use id unico no MDT para evitar duplicidade se houver falha apos gravar e antes
de confirmar. So ha um destinatario configurado por vez.

```lua
local debt = exports['forge-garage']:GetParkingDebt(plate)
-- {active, plate, amount, records}; sem prontidao: {active=false, ready=false}
local report = exports['forge-garage']:ReportParkingDebt(plate, reference)
-- Consulta dividas emitidas; nao converte tempo ainda estacionado em multa.
local ok = exports['forge-garage']:ResolveParkingDebt(plate, reference)
-- Baixa todos os debitos ativos da placa; chamar somente apos liquidacao autorizada.
```

## Testes em FiveM
1. Criar varias vagas e apenas um terminal: pagar veiculos de vagas diferentes.
   Repetir usando existentes do mapa, inclusive _02; salvar tambem onde nao ha
   nenhum prop e conferir o aviso, sem bloqueio no editor.
2. Guardar veiculo e conferir notificacao e tarifa.
3. Destrancar, esperar menos de 120s e pagar: total deve ficar congelado.
4. Retirar apos pagar dentro do prazo: nenhuma nova divida.
5. Configurar prazo curto (ex. 15s), destrancar e nao sair: conferir tranca,
   estado estacionado e cobranca retomada. Repetir apos acelerar sem sair,
   apos pagamento e apos reinicio. Destrancar novamente e conferir novo prazo.
6. Sair sem pagar: consultar GetParkingDebt e conferir uma unica divida.
7. Reiniciar e consultar novamente; reconectar target ao retornar a area.
8. Dois jogadores: vaga ocupada bloqueada e somente dono/chaves pode pagar.
9. Testar export destinatario com falha/retry e gravacao idempotente.
10. Confirmar duracao de hora configurada corresponde ao relogio da base.

Validacao local: luac para sintaxe e tests/parking_billing.lua para calculo.
Os testes locais nao simulam rede, banco, props ou o servidor FiveM.
