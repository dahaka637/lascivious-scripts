-- Deteccao de "zumbi por perto" do jogador local, usada por dois recursos
-- independentes: HardcoreKits_AutoOpen.lua (adia a abertura automatica) e
-- HardcoreKits_Window.lua (reduz o alpha da interface). Arquivo separado
-- pra nao duplicar a varredura nos dois lugares -- so muda o raio pedido.
--
-- Cliente-only e local por design: cada jogador ve so o proprio perigo, sem
-- nada pra sincronizar com o servidor (a decisao de abrir/escurecer a
-- interface e puramente visual, nao afeta o resgate em si).
--
-- Mesma tecnica ja usada (e comprovada) por LFS_Server.lua (SafeZone):
-- cell:getZombieList() + distancia ao quadrado (evita sqrt) + z:isDead()
-- pra ignorar corpos. So que aqui e do lado do cliente, olhando so pro
-- jogador local, sem faccao/anchor nenhum envolvido.
require "HardcoreKits_Config"

HardcoreKitsDanger = HardcoreKitsDanger or {}

-- true se existir pelo menos um zumbi vivo dentro de radiusTiles do jogador.
-- Tudo em pcall -- isto roda a cada poucos frames enquanto a janela esta
-- aberta (ver Window.lua), entao um erro aqui nunca pode travar a interface.
function HardcoreKitsDanger.zombiesNear(player, radiusTiles)
    if not player or not radiusTiles or radiusTiles <= 0 then return false end
    local ok, found = pcall(function()
        local cell = getCell()
        if not cell or not cell.getZombieList then return false end
        local zlist = cell:getZombieList()
        if not zlist then return false end
        local px, py = player:getX(), player:getY()
        local radiusSq = radiusTiles * radiusTiles
        for i = 0, zlist:size() - 1 do
            local z = zlist:get(i)
            if z and not z:isDead() then
                local dx, dy = z:getX() - px, z:getY() - py
                if (dx * dx + dy * dy) <= radiusSq then return true end
            end
        end
        return false
    end)
    return ok and found or false
end
