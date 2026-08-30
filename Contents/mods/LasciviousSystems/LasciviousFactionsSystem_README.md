# Lascivious Factions System

Mod de facções para Project Zomboid Build 42, mantido por Dahaka e baseado no
Faction Framework original de Burri. Construído sobre o motor de zonas do
PhunZones 2 (originalmente de UburGeek), que desde a fusão em
[Lascivious Systems](README.md) vem embutido neste mesmo mod — não é mais
uma dependência externa separada.

A interface e os avisos do mod são apresentados em português brasileiro mesmo com
o idioma do jogo configurado em inglês. A pontuação atual de uma facção é a soma dos
contadores nativos de zumbis mortos e horas sobrevividas dos personagens atuais de
seus membros. Personagens antigos importam o histórico que já possuem, jogadores
offline mantêm a última leitura e, por padrão, a morte zera somente o personagem
que morreu. A opção Sandbox `PreserveMemberPowerOnDeath` pode preservar os pontos
já contribuídos pelo membro e fazer a nova vida continuar somando sobre esse total.
Uma queda de pontuação nunca apaga território já reivindicado, mas impede novas
expansões enquanto a facção estiver acima do limite. Toda facção começa com uma área
separada e, por padrão, libera outra a cada 2.500 pontos (valor configurável).

O mod inclui território protegido, áreas públicas configuráveis, renascimento da
facção, cargos e permissões, convites manuais por lista de jogadores conectados,
diplomacia, guerras, ataques, fogo amigo, chat, mapa, etiquetas, classificação,
temporadas e ferramentas administrativas. Convites recusados recebem espera
progressiva contra spam. Uma opção de sandbox ativada por padrão concede recuperação
gradual de saúde e humor aos membros dentro do próprio território, além de ajudar
contra doenças comuns e intoxicação alimentar. Em personagens infectados, ela também
retarda sutilmente a progressão e a febre zumbi, mas não remove a mordida nem garante
uma cura. A potência geral desses benefícios é configurável no sandbox (1,0 por padrão).

O ícone da facção na barra lateral pode ser ocultado por uma opção própria do sandbox.
Mesmo oculto, o painel continua acessível pelo menu nativo Cliente > Facção e pelo
atalho configurável (J por padrão).

Para integrar bot, Discord ou outro mod do servidor, consulte
[LasciviousFactionsSystem_API.md](LasciviousFactionsSystem_API.md).
