# Vehicle Firearms

Módulo próprio dentro do submod `LasciviousScripts`.

## Objetivo

Melhorar a gameplay de armas de fogo no banco do motorista em B42:

- permitir continuar controlando o carro ao mirar ou recarregar;
- permitir cancelamento emergencial de reload/manejo com attack/click, `CancelAction` ou `Rack Firearm`/desemperrar;
- manter freio, ré e direção como controles normais do veículo, sem cancelar reload;
- não liberar reload correndo a pé.

## Escopo

O módulo só atua quando o personagem local está sentado como motorista e está com arma de fogo/manejo relacionado ativo. Fora do banco do motorista, ele não muda TimedActions nem flags de movimento.

## Implementação

- `shared/LasciviousScripts/VehicleFirearms/Core.lua`
  - registra defaults e leitura das opções sandbox;
  - detecta ações de reload, rack, inserir/remover carregador e carregar/descarregar munição;
  - envolve `start` e `update` dessas TimedActions com call-through (ver nota sobre `new` abaixo);
  - relaxa `stopOnAim`, `stopOnWalk` e `stopOnRun` apenas para motorista;
  - limpa `setBlockMovement(false)`/`setIgnoreMovement(false)` apenas no cenário de motorista + arma;
  - tenta `BaseVehicle:updateControls()` e desativa silenciosamente esse fallback se a build não expuser a chamada.

- `client/LasciviousScripts/VehicleFirearms/Client.lua`
  - acompanha jogador local em `OnPlayerUpdate` e `OnTick`;
  - limpa estados de animação travados (`isLoading`, `isRacking`, `isUnloading`, `WeaponReloadType`, `RackAiming`);
  - cancela ação atual apenas por comandos de emergência definidos.

## Sandbox

- `LasciviousScriptsVehicleFirearms.Enabled`
- `LasciviousScriptsVehicleFirearms.RelaxDriverFirearmActions`
- `LasciviousScriptsVehicleFirearms.PreserveDriverControls`
- `LasciviousScriptsVehicleFirearms.EmergencyCancel`

Todas vêm ligadas por padrão. Não há opção de debug neste módulo em produção.

## BUG crítico corrigido em 1.0.7 (2026-09-01): nunca envolver `.new`

Uma versão anterior também envolvia o construtor (`.new`) das 7 TimedActions de arma de fogo, do
mesmo jeito que `start`/`update`. Isso quebrou reload/desemperrar (`ISReloadWeaponAction`/
`ISRackFirearm`/etc.) **mesmo fora de veículo, pra todo mundo** -- crashes vanilla em
`character:getPerkLevel(...)`/`weapon:getSpentRoundCount(...)` com "non-table: null".

Causa raiz (confirmada descompilando `zombie.core.NetTimedAction`): `NetTimedAction.set(player,
action)` lê `action:getMetatable():rawget("new")` -- o construtor DA CLASSE -- faz `checkcast
LuaClosure` e inspeciona o `Prototype` **compilado** dessa closure (`numParams` + os NOMES das
variáveis locais que o compilador Lua gravou pra cada parâmetro) pra decidir quais campos nomeados
da instância copiar pra dentro de `actionArgs`, usado na (re)construção da ação pela rede. Isso é o
Java refletindo sobre a ASSINATURA COMPILADA do construtor, não uma chamada normal -- ele não tem
como saber que nosso wrapper é "o mesmo construtor com uma casca a mais". Nosso wrapper
(`function(self, ...) ... end`) tem exatamente UM parâmetro compilado (`self`; `...` não conta como
variável nomeada), então esse laço não achava nome de parâmetro nenhum, `actionArgs` voltava vazio
(sem `character`, sem `weapon`), e a ação reconstruída no servidor tinha `self.character` nulo --
exatamente os crashes reportados.

Corrigido removendo o envolvimento de `.new` por completo. `Core.relaxActionForDriver` já roda a
partir do wrap de `start` (antes E depois do `start()` original), que dispara com a ação já
totalmente construída (`self.character`/`self.gun` reais) -- efeito equivalente, sem tocar no
construtor. `start`/`update` são seguros de envolver porque são sempre chamados diretamente pelo Lua
(`self:start()`), nunca inspecionados pelo Java por nome de parâmetro.

**Nunca reintroduzir um wrap de `.new` (ou de qualquer construtor de TimedAction de rede) neste
módulo ou em qualquer outro que toque `NetTimedAction`.**

## Teste funcional

Validado em jogo após a hotfix `1.0.6`:

- recarregar no banco do motorista não trava mais definitivamente o jogador;
- mirar/recarregar permite continuar controlando o carro;
- attack/click cancela reload/manejo;
- freio e ré não cancelam reload;
- não há acesso a `CarController:updateControls()`, que gerava erro Lua por frame.
