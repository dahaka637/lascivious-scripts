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
  - envolve `new`, `start` e `update` dessas TimedActions com call-through;
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

## Teste funcional

Validado em jogo após a hotfix `1.0.6`:

- recarregar no banco do motorista não trava mais definitivamente o jogador;
- mirar/recarregar permite continuar controlando o carro;
- attack/click cancela reload/manejo;
- freio e ré não cancelam reload;
- não há acesso a `CarController:updateControls()`, que gerava erro Lua por frame.
