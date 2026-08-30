# Auditoria das traduções de Sandbox — PT-BR

Data da auditoria: 2026-08-26.

## Resultado

Todos os 17 módulos que possuem `media/sandbox-options.txt` agora também possuem:

- catálogo legível e completo em `Translate/PTBR/Sandbox.json`;
- tabela carregável pelo jogo em `Translate/PTBR/Sandbox_PTBR.txt`;
- conjunto de chaves idêntico ao catálogo inglês correspondente.

| Módulo | Chaves PT-BR | Paridade EN/PTBR | Carga Lua 5.1 |
|---|---:|---|---|
| FixedLightOnBeltAF | 3 | OK | OK |
| LS_AegisPanel | 67 | OK | OK |
| LS_Antibodies | 149 | OK | OK |
| LS_BetterEngineRepair | 23 | OK | OK |
| LS_BetterPush | 17 | OK | OK |
| LS_BurrisQualityOfLife | 108 | OK | OK |
| LS_CyesPushDoors | 35 | OK | OK |
| LS_ImmersiveSuicide | 5 | OK | OK |
| LS_ImprovisedSilencers | 23 | OK | OK |
| LS_PlyskenSolarRevolution | 47 | OK | OK |
| LS_ProximityInventory | 3 | OK | OK |
| LS_PushVehicle | 3 | OK | OK |
| LS_ResponsivePivoting | 47 | OK | OK |
| LS_TacticalHold | 5 | OK | OK |
| LS_TotalWeightRebalance | 3 | OK | OK |
| LS_WanderingZombies | 160 | OK | OK |
| LasciviousScripts | 18 | OK | OK |
| **Total** | **716** | **OK** | **OK** |

## Solução para acentos

O carregador nativo já havia demonstrado corromper caracteres acentuados escritos diretamente em
literais Lua. Os arquivos `Sandbox_PTBR.txt` gerados contornam isso sem alterar o texto exibido:
cada byte UTF-8 não ASCII é escrito como escape decimal Lua de três dígitos. Assim, a fonte permanece
100% ASCII e o valor reconstruído em execução permanece UTF-8 correto.

O catálogo JSON é a fonte legível e editável. Após qualquer mudança nele, executar:

```bash
python3 tools/generate_ptbr_sandbox_native.py
```

## Validações realizadas

- 716/716 chaves correspondem aos catálogos EN;
- 716/716 valores carregados pelo Lua 5.1 correspondem byte a byte ao JSON PT-BR;
- todos os 17 arquivos nativos passam em `luac5.1 -p`;
- todos os 17 arquivos nativos contêm somente bytes ASCII;
- `tools/validate_structure.py` passou sem erros estruturais; permanecem apenas os três avisos de
  capitalização já conhecidos do projeto.

Esta auditoria trata exclusivamente das opções de sandbox. Outras famílias de interface continuam
com o estado específico registrado no documento de cada módulo.
