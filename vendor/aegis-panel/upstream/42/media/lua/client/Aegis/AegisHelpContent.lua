-- Help and changelog texts for the in game help window (AegisHelp.lua).
-- Long prose lives here instead of the translation JSONs: full articles
-- in 13 languages are not maintainable, so DE and EN carry the content
-- and every other game language falls back to EN. Each help section is
-- { title, lines = { ... } }, each changelog entry { version, date,
-- sections = { { title, points = { ... } } } }. Newest changelog first.
-- pagehelp maps a page id to { title, lines = { ... } }.
-- NOTE: the engine reads Lua sources as ASCII, run the escape script
-- over this file after editing German text (umlauts become \ddd).

AegisHelpContent = {}

AegisHelpContent.DE = {
    help = {
        { title = "Erste Schritte", lines = {
            "Das goldene Panel sehen nur echte Admins des Servers; welche Seiten ein Admin nutzen darf, regelst du auf der Rollen-Seite.",
            "\195\150ffnen: goldener Wappen-Knopf in der schwebenden Leiste oben, etwas links der Mitte, oder F7; die Taste belegst du unter Optionen im Reiter Mods um.",
            "Leiste versetzen: am Griff an jede Stelle ziehen; ein Klick auf den Griff klappt die Leiste ein und wieder aus.",
            "Fenster einrichten: am Kopf verschieben, unten rechts am Punkte-Dreieck die Gr\195\182\195\159e ziehen; Minus macht eine Mini-Leiste, das Plus darauf holt das Panel zur\195\188ck.",
            "Seitenleiste ordnen: Schloss unten \195\182ffnen, Eintr\195\164ge mit gedr\195\188ckter Maustaste ziehen, die goldene Linie zeigt die Einf\195\188gestelle, danach das Schloss schlie\195\159en.",
            "Hinweis: F7 klappt das Fenster nur zusammen und erh\195\164lt alle Listen und Eingaben; erst das X oben rechts schlie\195\159t das Panel wirklich.",
        } },
        { title = "Kr\195\164fte", lines = {
            "Jede Karte ist ein Schalter f\195\188r eine Adminkraft und wirkt sofort.",
            "Kraft schalten: Karte anklicken, etwa Gottmodus, Unsichtbar, Durch W\195\164nde gehen, Schnelle Bewegung, Unbegrenzt tragen oder Nachtsicht.",
            "Unbemerkt beobachten: der Spectator-Schalter oben rechts setzt Gottmodus, Unsichtbar, Durch W\195\164nde und Schnelle Bewegung in einem Zug.",
            "Alles beenden: Alle Kr\195\164fte aus schaltet s\195\164mtliche Schalter zur\195\188ck, auch den Spectator.",
            "Admin-Tag zeigen: der Schalter blendet die rote Kennzeichnung \195\188ber deinem Kopf ein oder aus, die Wahl \195\188bersteht Neustarts.",
        } },
        { title = "\195\156bersicht", lines = {
            "Die Startseite ist ein Baukasten aus Karten; dein Layout gilt nur f\195\188r dich und bleibt gespeichert.",
            "Umbauen: der Knopf oben rechts startet den Umbaumodus, Karten mit der Maus ziehen, das Kreuz entfernt eine Karte, die Plus-Kachel \195\182ffnet den Katalog.",
            "Karten hinzuf\195\188gen: der Katalog bietet alles Sichtbare, von Kr\195\164fte-Schnellschaltern \195\188ber Server-Puls und Wetter bis zur Sprung-Kachel f\195\188r jede Panel-Seite.",
            "Zeit und Wetter nutzen: die Karte setzt die Tageszeit auf Morgen, Mittag, Abend oder Mitternacht und beendet laufendes Unwetter direkt von der Startseite.",
            "Schnell heilen: Heilen entfernt hier auch Bisse, Kratzer und die Zombie-Infektion.",
            "Zur\195\188cksetzen: Standard wiederherstellen im Umbaumodus baut die Startseite wieder wie beim ersten \195\150ffnen auf.",
        } },
        { title = "Spieler", lines = {
            "Links die Spielerliste, rechts die Aktionen f\195\188r den gew\195\164hlten Spieler; der Schalter oben blendet auch alle jemals gesehenen Offline-Spieler ein.",
            "Helfen: Hinteleportieren, Zu mir holen, Heilen, Grundbed\195\188rfnisse stillen, Gegenstand geben, Gottmodus und Unsichtbar schalten, alles \195\188ber jede Entfernung.",
            "Beobachten: Folgen heftet deine Kamera unsichtbar an den Spieler, erneuter Klick beendet es; das Beziehungs-Radar zeigt seine h\195\164ufigsten Kontakte.",
            "Werte \195\182ffnen: geht \195\188ber jede Entfernung, der Spieler muss nur online sein; allein die 3D-Vorschau braucht ihn in deiner N\195\164he, sonst zeigt sie Au\195\159er Reichweite.",
            "Moderieren: Verwarnen verlangt einen Grund, Stummschalten fragt Dauer und optional Grund, Kicken wirft nach Dialog und Best\195\164tigung sofort raus.",
            "Bannen: Bann und Zeitbann verlangen einen Grund, der im Protokoll landet; Entbannen ist immer sichtbar, aber nur bei tats\195\164chlich Gebannten anklickbar.",
        } },
        { title = "Gegenst\195\164nde", lines = {
            "Die Seite vergibt jeden Gegenstand des Spiels an dich oder einen gew\195\164hlten Spieler.",
            "Suchen: oben einen Teil des Namens tippen, die Liste filtert sofort; die Kategorie-Auswahl daneben grenzt weiter ein.",
            "Vergeben: unten die Menge \195\188ber die Mengen-Kn\195\182pfe w\195\164hlen (1, 5, 10 und mehr), dann per Geben-Knopf an dein Inventar oder den gew\195\164hlten Spieler.",
            "Wiederholen: die Zeile Zuletzt oben unter der Suchleiste merkt sich die zuletzt vergebenen Gegenst\195\164nde f\195\188r schnellen Zugriff.",
        } },
        { title = "Fahrzeuge", lines = {
            "Fahrzeuge spawnen, gezielt platzieren und bis ins letzte Teil bearbeiten.",
            "Spawnen: Fahrzeug w\195\164hlen, Zu mir spawnen setzt es mit fester Ausrichtung auf deine Position; die Dreh-Kn\195\182pfe drehen nur die Vorschau-Ansicht.",
            "Ausgerichtet setzen: In der Welt platzieren w\195\164hlen, den Cursor in der Welt bewegen, das Mausrad dreht gradweise, R in 30-Grad-Schritten.",
            "Bearbeiten: Rechtsklick aufs Fahrzeug und Fahrzeug bearbeiten, oder der Panel-Knopf f\195\188rs n\195\164chstgelegene; dann Tank, Batterie, jedes Teil, Farbe und Zustand.",
            "Schl\195\188ssel: der Schl\195\188ssel-Knopf erzeugt einen neuen und legt ihn ins Handschuhfach, ersatzweise in dein Inventar.",
            "Mitnehmen: sitzt du selbst im Fahrzeug, nimmt jeder Panel-Teleport es samt Anh\195\164nger und Ladung mit; niemand sonst darf an Bord sein, Fernholen gibt es nicht.",
        } },
        { title = "Welt", lines = {
            "Hier steuerst du Tageszeit, Wetter und Ger\195\164usch-Ereignisse; auf L\195\164rm reagieren Zombies in der Umgebung.",
            "Tageszeit setzen: die vier Presets oder der Regler stellen die Uhrzeit sofort f\195\188r alle; IG-Datum und IG-Uhrzeit stellen den kompletten Kalender um.",
            "Sturm starten: Gewitter, Tropensturm und Schneesturm setzen sofort sichtbar ein, die Dauer bestimmt der Regler; Sofort-Regen und Wetter stoppen wirken direkt.",
            "Eigenes Wetter: der Wetter-Designer mischt Wolken, Regen, Nebel und Wind, auf Wunsch mit Donner-Takt; Als Vorlage speichern merkt sich die Mischung.",
            "L\195\164rm erzeugen: L\195\164rm machen nutzt den Radius-Regler (10 bis 500); Donnerschlag hier, Schuss und Feuerwerk ert\195\182nen mit festen Reichweiten an deiner Position.",
        } },
        { title = "Zonen", lines = {
            "Safehouses anlegen und \195\188ber die Vanilla-Grenzen hinaus formen; eine Zone z\195\164hlt immer als ein Ganzes, egal aus wie vielen Teilen.",
            "Zone anlegen: Neue Zone w\195\164hlen, Besitzer bestimmen, dann Rechtecke ziehen oder die Fl\195\164che malen; jedes weitere Rechteck muss an die Form anschlie\195\159en.",
            "Zone erweitern: Grenzen bearbeiten \195\182ffnen, Linksklick-Ziehen f\195\188gt Rechtecke an, Rechtsklick-Ziehen entfernt Angef\195\188gtes; Enter \195\188bernimmt alles, ESC verwirft.",
            "Zone verkleinern: Fl\195\164che malen nutzen, Linksklick malt, Rechtsklick radiert einzelne Kacheln; dazu musst du innerhalb der Zone stehen.",
            "Sichern und zeigen: Zonen einblenden zeichnet alle Zonen in die Welt; Sicherung legt eine Kopie an, die sich nach einem Griefer-Angriff wiederherstellen l\195\164sst.",
            "Ber\195\188hren sich Fl\195\164chen desselben Besitzers, verschmelzen sie zu einer Zone.",
        } },
        { title = "Horde und Tiere", lines = {
            "Zombies und Tiere auf Knopfdruck, alles rund um deine eigene Position.",
            "Horde spawnen: Anzahl und Radius einstellen, An meiner Position spawnen setzt die Zombies um dich herum.",
            "Zombies loswerden: Zombies entfernen wirkt im eingestellten Radius; dazu kommen Alle geladenen entfernen und Leichen entfernen.",
            "Belagerung starten: die Horde marschiert mit Vorwarnschuss aus der Ferne heran; Wellen, Anzahl und Distanz regelst du in der Sandbox unter Aegis Ereignisse.",
            "Tiere setzen: Art und Rasse w\195\164hlen, in der Vorschau drehen, dann in der Welt platzieren, genau wie bei Fahrzeugen.",
        } },
        { title = "Server", lines = {
            "Neustarts, Weltsicherung, Versorgungsnetze, Event-Regie und die serverweiten Schalter an einem Ort.",
            "Neustart planen: die Minuten-Kn\195\182pfe starten einen Countdown mit Banner f\195\188r alle; Uhrzeit, Datum und Automatik setzen feste Zeitpunkte im gew\195\164hlten Takt.",
            "Wichtig: der Server kann sich nicht selbst beenden, zum Stichtag muss jemand mit Herunterfahren-Recht online sein; das Hochfahren regelt dein Hoster-Panel.",
            "Event abfeuern: Event-Regie startet an deiner Position Unwetter-Show, Belagerung, Heli-Alarm, Luftlandung, Feuersturm oder Kriechender Hinterhalt.",
            "Sichern und Netze: Welt sichern speichert den Spielstand sofort; Stromnetz und Wassernetz schalten die Versorgung der ganzen Karte.",
            "Schalter und Ansage: Spielerbereich, Spieler-Claims und Spieler-Kits regeln, was Spieler d\195\188rfen; Ansage zeigt allen ein goldenes Banner samt Chat-Zeile.",
        } },
        { title = "Serveroptionen", lines = {
            "Alle Einstellungen der Server-INI als eigene Seite, nach Themen gruppiert; unter jedem Namen steht der Standardwert.",
            "Option \195\164ndern: \195\188ber das Suchfeld finden, Werte setzen, gesammelt mit \195\156bernehmen abschicken; sie wirken sofort und landen zugleich in der INI.",
            "Neustart-Werte erkennen: ein Uhr-Symbol markiert Optionen, die erst nach einem Neustart greifen.",
            "Sichtbarkeit: andere Admins sehen deine \195\132nderung erst nach Reconnect oder /reloadoptions, eine Eigenart des Spiels.",
            "Gesch\195\188tzt: Passw\195\182rter, RCON und Discord bleiben verborgen, Ports, Karte und Spieler-ID gesperrt; in den Rollen ist Serveroptionen ein eigener Bereich.",
            "Vorsicht: Mods und Workshop-Objekte \195\182ffnen sich erst nach zwei Warnungen, ein Tippfehler dort kann den Server lautlos unbrauchbar machen.",
        } },
        { title = "Bau-Werkzeuge", lines = {
            "Bauen, nachforschen und zur\195\188ckbauen direkt in der Welt.",
            "Bauen: im Bau-Pinsel ein Bauteil w\195\164hlen und mit gedr\195\188ckter Maustaste \195\188ber die Kacheln ziehen, R dreht; B\195\182den f\195\188llen Fl\195\164chen, W\195\164nde folgen der Linie.",
            "Bauteile aufnehmen: der Sprite-Inspektor zeigt beim Anvisieren alle Objektnamen der Kachel; ein Klick kopiert den obersten und legt ihn unter Eigene ab.",
            "Nachforschen: das Baustellen-Radar zeigt beim \195\156berfahren gebauter Objekte, wer sie wann gebaut hat.",
            "Abriss zur\195\188ckholen: im Bau-Protokoll auf der Welt-Seite die Zeile w\195\164hlen; Wiederherstellen zeigt eine Vorschau, erst deine Best\195\164tigung baut nach.",
            "Roden: Durchgang eins entfernt Pflanzen, Durchgang zwei alles bis auf den Boden; R\195\188ckg\195\164ngig gilt nur der letzten Rodung, B\195\164ume und Generatoren bleiben weg.",
        } },
        { title = "Protokoll und Todesf\195\164lle", lines = {
            "Jede Admin-Aktion und jeder Spielertod landet hier.",
            "Nachschlagen: oben links Bereich und Tag w\195\164hlen, darunter den Eintrag anklicken, rechts steht der volle Inhalt.",
            "Bereiche: Aktionen, Bans, Kicks, Warnungen, Chat-Moderation, Admin-Sitzungen, Spieler-Sitzungen und Todesf\195\164lle; das Bau-Protokoll steht auf der Welt-Seite.",
            "Aufbewahrung: Moderations- und Todesfall-Logs bleiben dauerhaft; Aktionen und Sitzungen wandern nach 14 Tagen ins Archiv und werden nach weiteren 30 geleert.",
            "Todesfall lesen: der Bericht nennt Ursache samt Waffe, Verletzungen, Infektion, Ort samt Raum und wer in der N\195\164he war; Admins sehen sofort eine Kurzmeldung.",
        } },
        { title = "Rollen", lines = {
            "Rollen legen fest, welche Panel-Seiten ein Admin benutzen darf.",
            "Rolle einrichten: anlegen, erlaubte Bereiche anhaken, speichern, unten dem Spieler zuweisen; die Maus \195\188ber einem Bereich zeigt die enthaltenen Seiten.",
            "Eingeschr\195\164nkten Admin anlegen: Rolle mit den erlaubten Bereichen anlegen und sofort zuweisen, erst danach /setaccesslevel \"Name\" observer setzen.",
            "Wichtig: ohne zugewiesene Rolle hat jede Stufe mit Admin-Werkzeug, auch observer, vollen Zugriff auf alles; darum die Rolle vor der Stufe vergeben.",
            "Rollenverwaltung entziehen: den Bereich Rollen unangehakt lassen; nur die Vanilla-Stufe admin beh\195\164lt die Rollenverwaltung in jedem Fall.",
            "Namens-Tag: die Rollenfarbe f\195\164rbt den Kopf-Tag; wer kein Admin ist, bekommt durch eine Rolle nur den farbigen Namen und keinerlei Admin-Rechte.",
        } },
        { title = "Spieler-Panel (blau)", lines = {
            "Das blaue Panel ist das Gegenst\195\188ck f\195\188r normale Spieler; jeder bekommt es beim Betreten automatisch, Admins eingeschlossen.",
            "Extras vergeben: pro Rolle auf der Rollen-Seite Claim-Kacheln (0 hei\195\159t kein Claim) und Kit-Zugang einstellen; Donatoren bekommen eigene Rollen mit mehr Budget.",
            "Abschalten: pro Rolle nicht m\195\182glich, serverweit schon; der Schalter Spielerbereich auf der Server-Seite oder in der Sandbox nimmt allen das blaue Panel.",
            "Wissen, was Spieler sehen: 3D-Charakter, Statistiken samt Bestenliste, Gesundheit mit Verbinden, eigene Fahrzeuge, Safehouse, Kits, Zonen-Claim und Notruf.",
            "Notruf verstehen: erreicht alle Admins online mit Name, Position und Nachricht; danach zwei Minuten Sperre gegen Spam.",
            "Hinweis: nutzt du die Panel-Claims, sollte die Serveroption PlayerSafehouse aus sein, sonst konkurrieren zwei Wege ums Safehouse.",
        } },
        { title = "Kits", lines = {
            "Kits sind Pakete, die Spieler im blauen Panel abholen.",
            "Kit bauen: Namen vergeben, \195\188ber die Suche Gegenst\195\164nde samt Menge hinzuf\195\188gen, dann den Modus Einmalig, Cooldown oder Monatlich w\195\164hlen.",
            "Cooldown einstellen: die Stundenzahl frei eingeben, Standard 24; t\195\164glich entspricht 24 Stunden, w\195\182chentlich 168.",
            "Zugang steuern: ohne angehakte Rolle ist das Kit offen f\195\188r alle, der Normalfall f\195\188rs Startpaket; angehakte Rollen beschr\195\164nken es auf deren Tr\195\164ger.",
            "Anspr\195\188che aufheben: Anspr\195\188che zur\195\188cksetzen wirkt je Kit, Anspr\195\188che verwalten je Spieler, Alle Anspr\195\188che l\195\182schen f\195\188r alles, letzteres mit getipptem Grund.",
            "Der Anspruch \195\188bersteht Tod und Wiedereinstieg; ob Spieler \195\188berhaupt an Kits kommen, regelt der Schalter Spieler-Kits auf der Server-Seite.",
        } },
        { title = "Praktische Hinweise", lines = {
            "Kleine Griffe f\195\188r den Alltag.",
            "Schnell reisen: Rechtsklick auf die Weltkarte (Taste M) bietet Hierher teleportieren.",
            "R\195\188ckmeldung finden: Meldungen erscheinen als goldene Kurzmeldung oben im Panel, bei verborgenem Panel als schwebender Text am Charakter.",
            "Liste auffrischen: wirkt eine Liste leer, l\195\164dt der runde Pfeil-Knopf sie neu.",
            "Fehler suchen: fast jede Aktion steht im Protokoll, dort lohnt der erste Blick.",
        } },
    },
    tour = {
        { page = "dashboard", title = "\195\156bersicht", text = "Deine Startseite. Die Kacheln lassen sich umsortieren und ausblenden, die Anordnung merkt sich das Panel f\195\188r jeden Admin einzeln." },
        { page = "powers", title = "Kr\195\164fte", text = "Alle Adminkr\195\164fte an einem Ort, der Zustand kommt vom Server zur\195\188ck. Gottmodus heilt dich sofort." },
        { page = "roles", title = "Rollen", text = "Rollen schr\195\164nken Admins ein. Adminrechte selbst kommen nur \195\188ber die Zugangsstufe." },
        { page = "options", title = "Serveroptionen", text = "Alle Servereinstellungen im Panel statt in der INI. Manche Werte greifen erst nach einem Neustart." },
        { page = "sandbox", title = "Sandbox", text = "Die Spielregeln deiner Welt, jederzeit im Betrieb \195\164nderbar. Die Aegis-eigenen Schalter stehen hier ebenfalls." },
        { page = "tools", title = "Werkzeuge", text = "Bau-Pinsel, Bereinigung, Foto-Modus und Baustellen-Radar. Zuletzt und mit Bedacht, die Bereinigung r\195\164umt wirklich alles weg." },
        { page = "dock", title = "Die zwei Symbole", text = "Das goldene Wappen \195\182ffnet das Panel, das blaue dein eigenes Spielerfenster. Am Griff ziehst du die Leiste, ein Klick darauf klappt sie zusammen, F7 und F6 gehen immer." },
        { page = "help", title = "Das Fragezeichen", text = "Das Fragezeichen erkl\195\164rt die Seite, auf der du gerade stehst. Der Knopf daneben \195\182ffnet Handbuch und \195\132nderungsliste, dort startest du auch diesen Rundgang neu." },
    },
    pagehelp = {
        dashboard = { title = "\195\156bersicht", lines = {
            "Deine Startseite, ein Baukasten aus Karten. Der Knopf oben rechts schaltet den Umbaumodus ein, die Plus-Kachel unten \195\182ffnet den Katalog.",
            "F\195\188r jede Panel-Seite liegt eine Kachel bereit, ein Klick springt direkt dorthin.",
            "Dein Layout gilt nur f\195\188r dich und bleibt gespeichert, andere Admins haben ihr eigenes.",
            "Heilen entfernt hier auch Bisse, Kratzer und die Zombie-Infektion.",
        } },
        powers = { title = "Kr\195\164fte", lines = {
            "Alle Adminkr\195\164fte als Schalter, jede Karte wirkt sofort. Den Zustand meldet der Server zur\195\188ck.",
            "Gottmodus heilt dich sofort.",
            "Der Spectator-Schalter b\195\188ndelt Gottmodus, Unsichtbar, Durch W\195\164nde und Schnelle Bewegung. Alle Kr\195\164fte aus setzt alles auf einmal zur\195\188ck.",
            "Admin-Tag blendet die rote Kennzeichnung \195\188ber deinem Kopf ein oder aus, die Wahl \195\188bersteht Neustarts.",
        } },
        players = { title = "Spieler", lines = {
            "Alle verbundenen Spieler samt Aktionen f\195\188r den ausgew\195\164hlten: Teleport, Heilen, Gegenstand geben, Gottmodus und mehr.",
            "Der Schalter oben blendet zus\195\164tzlich alle jemals gesehenen Offline-Spieler ein.",
            "Die Aktionen wirken \195\188ber jede Entfernung. Nur Werte \195\182ffnen und die 3D-Vorschau brauchen den Spieler in deiner N\195\164he.",
            "Folgen heftet deine Kamera dauerhaft an den Spieler, erneuter Klick beendet es.",
            "Kicken wirkt sofort. Bannen und Zeitbann verlangen einen Grund, der im Protokoll landet.",
        } },
        items = { title = "Gegenst\195\164nde", lines = {
            "Gegenst\195\164nde suchen und vergeben. Das Suchfeld filtert sofort, die Kategorie-Auswahl grenzt weiter ein.",
            "Die Mengen-Kn\195\182pfe bestimmen die St\195\188ckzahl, Ziel ist dein eigenes Inventar oder ein ausgew\195\164hlter Spieler.",
            "Unten merkt sich das Panel deine zuletzt vergebenen Gegenst\195\164nde als Verlaufs-Kn\195\182pfe.",
        } },
        vehicles = { title = "Fahrzeuge", lines = {
            "Fahrzeuge spawnen: in der Vorschau ausrichten, der Wagen erscheint vor dir in genau dieser Blickrichtung.",
            "Doppelklick auf ein Fahrzeug in der Welt \195\182ffnet das Detail-Fenster: Tank, Batterie, Schl\195\188ssel, jedes Teil einzeln reparieren, Farbe und Zustand.",
            "Fahrzeug-Teleport nimmt Anh\195\164nger und komplette Ladung mit.",
        } },
        animals = { title = "Tiere", lines = {
            "Tiere spawnen: Art und Rasse w\195\164hlen, in der Vorschau drehen, dann in der Welt platzieren oder direkt zu dir spawnen.",
            "Beim Platzieren dreht das Mausrad in feinen Schritten, R in groben, Rechtsklick bricht ab.",
            "Tier in der N\195\164he entfernen nimmt das n\195\164chstgelegene Tier nach R\195\188ckfrage aus der Welt.",
        } },
        world = { title = "Welt", lines = {
            "Tageszeit, Datum, Wetter und Ereignis-Ger\195\164usche f\195\188r die ganze Welt. Presets und Regler wirken sofort f\195\188r alle Spieler.",
            "Gewitter, Tropensturm und Schneesturm bauen sich \195\188ber etwa eine Spielstunde auf. Sofort-Regen wirkt ohne Aufbauzeit, Wetter stoppen beendet alles.",
            "Der Wetter-Designer mischt eigenes Wetter und speichert es dauerhaft als Vorlage.",
            "Ereignisse wie Donnerschlag oder Schuss ert\195\182nen an deiner Position, Zombies in der Umgebung reagieren darauf.",
        } },
        zones = { title = "Zonen", lines = {
            "Safehouses anlegen und \195\188ber die Vanilla-Grenzen hinaus erweitern. Eine Zone aus mehreren Teilen z\195\164hlt immer als ein Ganzes.",
            "Grenzen bearbeiten f\195\188gt Rechtecke an. Fl\195\164che malen ist das Feinwerkzeug f\195\188r einzelne Kacheln und der Weg zum Verkleinern.",
            "Ber\195\188hren sich Fl\195\164chen desselben Besitzers, verschmelzen sie zu einer Zone.",
            "Sicherung legt eine Kopie der Zone an, die sich sp\195\164ter wiederherstellen l\195\164sst, etwa nach einem Griefer-Angriff.",
        } },
        horde = { title = "Horde", lines = {
            "Zombies auf Kommando: Anzahl und Radius einstellen, dann spawnen sie um die gew\195\164hlte Position.",
            "Aufr\195\164umen entfernt Zombies im Radius wieder.",
            "Belagerung l\195\164sst die Horde aus der Ferne anmarschieren, mit Vorwarnung durch einen Schuss.",
            "Die Feinheiten der Belagerung, also Wellen, Anzahl und Distanz, stehen in der Sandbox unter Aegis Ereignisse.",
        } },
        server = { title = "Server", lines = {
            "Neustarts planen, Welt sichern, Strom- und Wassernetz schalten, Ansagen senden, Event-Regie starten.",
            "Der Server kann sich nicht selbst beenden: zum Stichtag muss ein berechtigter Spieler online sein, das Wiederhochfahren \195\188bernimmt dein Hoster-Panel.",
            "Die Funktions-Schalter bestimmen, was Spieler d\195\188rfen. Der Server setzt das durch, es ist nicht nur eine Anzeige.",
            "Server-Branding setzt den Namen im Kopf beider Panels, leer lassen bringt AEGIS zur\195\188ck.",
        } },
        options = { title = "Serveroptionen", lines = {
            "Alle Einstellungen der Server-INI, nach Themen gruppiert und durchsuchbar. \195\156bernehmen wirkt sofort und schreibt zugleich in die INI.",
            "Ein Uhr-Symbol markiert Optionen, die erst nach einem Neustart greifen.",
            "Andere Admins sehen deine \195\132nderung erst nach einem Reconnect oder nach /reloadoptions.",
            "Mods und Workshop-Objekte \195\182ffnen sich erst nach zwei Warnungen. Ein Tippfehler dort kann den Server lautlos unbrauchbar machen.",
        } },
        factions = { title = "Fraktionen", lines = {
            "Alle Fraktionen und Safehouses des Servers mit Besitzern und Mitgliedern, der Punkt zeigt, wer gerade online ist.",
            "Hinspringen teleportiert dich zum Safehouse. Freigeben entfernt es nach R\195\188ckfrage samt aller Anbauten.",
            "Hinspringen braucht das Welt-Recht deiner Rolle, Freigeben das Zonen-Recht.",
            "L\195\164uft Knox Claim auf dem Server, h\195\164lt der das Grundst\195\188ck weiter und die Zone kommt zur\195\188ck. Dort freigeben.",
            "Im Einzelspieler gibt es in der Regel keine Fraktionen.",
        } },
        tools = { title = "Werkzeuge", lines = {
            "Bau-Pinsel, Sprite-Inspektor, Baustellen-Radar, Foto-Modus, Bereich roden und das Bau-Protokoll mit Wiederherstellen.",
            "Bereich roden: der erste Durchgang entfernt nur Pflanzen, ein zweiter auf derselben Fl\195\164che r\195\164umt wirklich alles bis auf den Boden weg.",
            "R\195\188ckg\195\164ngig stellt die letzte Rodung wieder her.",
            "Wiederherstellen aus dem Bau-Protokoll zeigt erst eine durchscheinende Vorschau, gebaut wird erst nach deiner Best\195\164tigung.",
        } },
        kits = { title = "Kits", lines = {
            "Pakete schn\195\188ren, die Spieler im blauen Panel abholen: Gegenst\195\164nde \195\188ber die Suche hinzuf\195\188gen, Menge setzen, Modus w\195\164hlen.",
            "Ohne angehakte Rolle ist ein Kit offen f\195\188r jeden Spieler auf dem Server. Erst angehakte Rollen schr\195\164nken es auf deren Tr\195\164ger ein.",
            "Der Anspruch wird pro Spieler gespeichert und \195\188bersteht Tod und Wiedereinstieg. Nur Anspr\195\188che zur\195\188cksetzen hebt ihn auf.",
            "Ob Spieler \195\188berhaupt an Kits kommen, entscheidet der Schalter Spieler-Kits auf der Server-Seite.",
        } },
        sandbox = { title = "Sandbox", lines = {
            "Die Spielregeln deiner Welt, jederzeit im laufenden Betrieb \195\164nderbar, gruppiert in die Vanilla-Kategorien und durchsuchbar.",
            "\195\156bernehmen schickt die gesammelten \195\132nderungen ab. Die Aegis-eigenen Schalter stehen hier ebenfalls.",
            "Der Voll-Editor \195\182ffnet zus\195\164tzlich den kompletten Vanilla-Editor.",
        } },
        logs = { title = "Protokoll", lines = {
            "Jede Admin-Aktion dauerhaft gesammelt, geordnet nach Bereichen von Aktionen \195\188ber Bans bis Bau und Todesf\195\164lle.",
            "Links den Bereich w\195\164hlen, in der Mitte den Eintrag, rechts steht der volle Inhalt.",
            "Todesf\195\164lle erzeugen automatisch einen ausf\195\188hrlichen Bericht samt Waffe, Verletzungen, Ort und Umfeld. Alle Admins bekommen sofort eine Kurzmeldung.",
        } },
        roles = { title = "Rollen", lines = {
            "Rollen schr\195\164nken Admins ein, Adminrechte kommen nur \195\188ber die Zugangsstufe.",
            "Rolle anlegen, erlaubte Bereiche anhaken, unten einem Spieler zuweisen. Ohne Admin-Stufe bringt eine Rolle nur den farbigen Namen \195\188ber dem Kopf.",
            "Bleibt der Bereich Rollen unangehakt, kann der Admin keine Rechte mehr \195\164ndern, auch nicht seine eigenen. Die Vanilla-Stufe admin beh\195\164lt die Rollenverwaltung immer.",
            "Serveroptionen und Sandbox sind eigene Bereiche, die Server-Seite allein gibt sie nicht her.",
        } },
    },
    changelog = {
        { version = "2.5.1", date = "August 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Ausgebrannte Fahrzeuge lassen sich jetzt spawnen. Sie stehen mit der Markierung \"Ausgebrannt\" in derselben Liste.",
                "Der Todesbericht h\195\164lt jetzt fest, welche Fertigkeiten und Rezepte mit der Figur verloren gingen, mit Stufe und Fortschritt in Prozent.",
                "Aus \"Kills zur\195\188cksetzen\" wurde \"Statistiken zur\195\188cksetzen\": ein Auswahlfenster bestimmt, welche Werte gel\195\182scht werden, f\195\188r einen Spieler oder alle, samt Rundumschlag f\195\188r die ganze Liste.",
            } },
            { title = "Behoben", points = {
                "Die Zeitstempel in den Aufzeichnungen liefen in Weltzeit statt in der Uhrzeit des Servers und gingen je nach Zeitzone um Stunden daneben.",
            } },
        } },
        { version = "2.5", date = "August 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Ein gef\195\188hrter Rundgang beim ersten \195\150ffnen: acht Halte durch die wichtigsten Seiten. \195\156berspringen z\195\164hlt als gesehen, neu starten geht jederzeit \195\188ber die Hilfe.",
                "Das Fragezeichen im Fensterkopf erkl\195\164rt die Seite, auf der du gerade stehst, samt ihren Fallstricken.",
                "Das Handbuch ist neu geschrieben: Aufgaben mit Schritten statt Abs\195\164tze, dazu ein Suchfeld. Veraltete Stellen wurden am Code gepr\195\188ft und berichtigt.",
                "Fahrzeuge spawnen wahlweise als Neuwagen, Gebraucht oder Schrott, bei den beiden letzten w\195\188rfelt jedes Teil seinen Zustand einzeln.",
                "Der automatische Neustart beendet den Server nach M\195\182glichkeit selbst, dann muss niemand online sein.",
                "Dieses Fenster. Es erscheint nach einem Update, das H\195\164kchen unten h\195\164lt es bis zur n\195\164chsten Version still.",
                "Die Symbolleiste klappt per Klick auf die drei Punkte zusammen, noch ein Klick holt die Symbole zur\195\188ck.",
            } },
            { title = "Behoben", points = {
                "Tragkraft: 0 im Dialog stellt den Spielstandard wieder her. Kleine Werte nagelten vorher ein neues Limit fest, statt zur\195\188ckzusetzen.",
                "Gottmodus, Unsichtbar und Durch W\195\164nde bleiben aus, wenn die Sandbox sie aus haben will. Das Aus kam bisher nie beim Server an.",
                "Im Spielervergleich stehen Menge und Gewicht nicht mehr unter der Bildlaufleiste.",
                "Die Bereinigung l\195\164sst Steinchen und Bodendetails nicht mehr stehen.",
                "Eine Fehlerspur beim Einloggen auf manchen Servern ist weg.",
                "Die Symbolleiste sprang nach einem Neustart an ihren Ausgangsort statt dorthin, wo du sie zuletzt hattest.",
            } },
            { title = "Ge\195\164ndert", points = {
                "Der Admin-Tag-Schalter wirkt jetzt f\195\188r alle, nicht nur auf dem eigenen Bildschirm.",
                "Die Bereinigung r\195\164umt spielergebaute B\195\182den ab und legt Boden aus der Nachbarschaft nach, statt L\195\182cher zu lassen.",
                "Der Spielervergleich l\195\164sst sich am Kopf verschieben.",
                "Die Symbolleiste macht Platz, solange Weltkarte oder Pausenmen\195\188 offen sind.",
            } },
        } },
        { version = "2.4.2", date = "August 2026", sections = {
            { title = "Behoben", points = {
                "Einzelspieler: das goldene Symbol erscheint und F7 \195\182ffnet das Panel wie gewohnt. Beide warteten auf eine Rechte-Antwort des Servers, und im Einzelspieler gibt es keinen Server, der sie schicken k\195\182nnte. Wo niemand antworten kann, wird jetzt nicht mehr gewartet.",
                "Die neue Symbol-Leiste blieb bedienbar unter jedem sp\195\164ter ge\195\182ffneten Fenster begraben: lag zum Beispiel das Fraktions-Fenster von FactionsFramework dar\195\188ber, kamen Klicks und der Zieh-Griff nicht mehr durch. Die Leiste liegt jetzt immer obenauf, genau wie die Minimieren-Leiste des Panels es schon immer tut.",
                "Die Themenliste der Hilfe schnitt beim Verkleinern des Fensters unten Eintr\195\164ge ab, ohne Hinweis und ohne Weg dorthin. Sie hat jetzt eine eigene ziehbare Bildlaufleiste, dazu bl\195\164ttert ein Klick auf die Bahn seitenweise und das Mausrad rollt wie \195\188berall.",
                "Im Hilfe-Fenster konnte der Text unter die rechte Bildlaufleiste laufen, und die Leiste selbst klebte in der abgerundeten Fensterecke. Sie sitzt jetzt ein St\195\188ck weiter innen, und der Text endet hart davor, er kann sie nicht mehr erreichen.",
            } },
        } },
        { version = "2.4.1", date = "August 2026", sections = {
            { title = "Ge\195\164ndert", points = {
                "Die beiden Aegis-Symbole sind aus der Ausr\195\188stungsleiste ausgezogen und sitzen jetzt in einer eigenen kleinen Leiste, zu Beginn etwas links der Bildschirmmitte. Am Griff mit den drei Punkten dar\195\188ber ziehst du sie an jede Stelle, die Position wird gemerkt. In der Vanilla-Leiste haben sie sich st\195\164ndig mit anderen Symbolen um den Platz gedr\195\164ngt, sprangen beim \195\156berfahren umher oder landeten mitten zwischen fremden Kn\195\182pfen, je nach Mod-Zusammenstellung. Damit ist Schluss, die Leiste geh\195\182rt wieder ganz dem Spiel.",
            } },
        } },
        { version = "2.4", date = "August 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Die Factions-Seite hat jetzt einen echten Freigabe-Knopf f\195\188r ein Safehouse (Hauptteil und alle weiteren Zusatzteile auf einmal, mit R\195\188ckfrage). Vorher gab es im goldenen Panel keinen einzigen Weg, ein Safehouse aufzul\195\182sen. L\195\164uft Knox Claim auf dem Server und geh\195\182rt das Grundst\195\188ck dort hin, wird es gleich mit freigegeben. Ohne das kam die Zone nach kurzer Zeit von selbst zur\195\188ck, weil Knox sie aus seinem eigenen Eintrag neu aufgebaut hat. Bleibt der Knox-Eintrag doch stehen, sagt die R\195\188ckmeldung das ausdr\195\188cklich, statt Erfolg zu melden.",
                "Die Zonen-Liste ist jetzt nach Eigent\195\188mer zusammengeklappt, genau wie die Safehouse-Liste auf der Factions-Seite. Ein Klick auf den Namen f\195\164ltet dessen Grundst\195\188cke auf. Wer ein Dutzend Grundst\195\188cke besa\195\159, hat vorher alle anderen aus der Liste gedr\195\164ngt.",
                "Der Bau-Pinsel hat jetzt \"Alle Kacheln\": ein Fenster mit Kachelbl\195\164ttern, links durchsuchbar, rechts als Vorschau-Raster. Beide Fenster haben eine ziehbare Bildlaufleiste, ein Klick auf die Bahn bl\195\164ttert eine Seite weiter. F\195\164hrst du mit der Maus \195\188ber eine Kachel, erscheint sie gro\195\159 daneben, samt ihrem Namen: im Raster ist eine Kachel nur 58 Pixel gro\195\159, und viele unterscheiden sich nur in einer Kleinigkeit. Bringt eine Kachel ein echtes 3D-Modell mit, siehst du in der Vorschau dieses Modell statt des flachen Bildes. Das betrifft nur wenige: in Vanilla sind es 45 Kacheln aus f\195\188nf Bl\195\164ttern, gr\195\182\195\159tenteils T\195\188ren und Tore. Mods k\195\182nnen eigene mitbringen, gepr\195\188ft wird die Kachel selbst und keine feste Liste. Ein Klick legt die Kachel zu deinen eigenen St\195\188cken und w\195\164hlt sie sofort aus. Die bisherige Palette bleibt als schneller Weg daneben stehen. Wichtig zur Erwartung: die vollst\195\164ndige Kachelliste des Spiels gibt die Engine nur im Debug-Modus heraus, im normalen Spiel ist sie leer. Das Fenster zeigt deshalb die Bl\195\164tter der Palette plus alles, was rund um dich wirklich in der Welt steht, und wird beim \195\150ffnen jedes Mal neu eingelesen. An einem anderen Ort stehen also andere Bl\195\164tter darin.",
                "Die Protokoll-Seite hat eine Tagesauswahl bekommen. Bei einem viel genutzten Bereich musste man vorher hunderte Eintr\195\164ge durchscrollen, um einen bestimmten Tag zu finden.",
                "Neue Sandbox-Option: automatische Admin-Kr\195\164fte. Vanilla schaltet Gottmodus, Unsichtbarkeit und Geistmodus von selbst ein, sobald jemand Admin wird. Ausschalten l\195\164sst sie aus, bis du sie selbst aktivierst. Die volle Heilung bei derselben Bef\195\182rderung l\195\164sst sich nicht verhindern, die steckt in der Engine.",
                "Neue Sandbox-Option: Statistik f\195\188r Admins mitz\195\164hlen. Ausschalten sorgt daf\195\188r, dass Kills, Tode, Strecke und bestes Leben f\195\188r Charaktere auf einer Admin-Stufe nicht mehr aufgezeichnet werden, damit Admin-Tests die Zahlen nicht verf\195\164lschen.",
                "Auf der Spieler-Seite gibt es jetzt einen Knopf, der die Kill-Statistik eines Spielers oder aller Spieler auf null setzt, mit R\195\188ckfrage und Protokolleintrag. Er war f\195\164llig, weil sich verf\195\164lschte Best\195\164nde nicht nachtr\195\164glich zur\195\188ckrechnen lassen.",
                "Fensterscheiben einschlagen und Fahrzeuge kurzschlie\195\159en landen jetzt in der Sitzungsdatei des jeweiligen Spielers, mit Uhrzeit und Ort, beim eingeschlagenen Fenster zus\195\164tzlich mit dem \195\188bersetzten Namen des Fahrzeugs. Absichtlich kein neuer Log-Bereich: das sind Spieler-Aktivit\195\164ten und geh\195\182ren zum Spieler.",
            } },
            { title = "Behoben", points = {
                "Der geplante Neustart hing an der Anwesenheit des planenden Admins: solange dieser online war, reagierte ausschlie\195\159lich sein eigener Client auf den Neustart-Befehl, jeder andere Admin mit vollem Neustart-Recht ging leer aus. Der Server sendet den Befehl jetzt an jeden berechtigten Admin gleichzeitig, unabh\195\164ngig davon wer ihn geplant hat.",
                "Ein Spieler mit einer eigenen Rangrolle wie \"Priority\" konnte das goldene Symbol sehen und das Panel \195\182ffnen, blieb darin aber leer, weil der Server jeden Bereich korrekt verweigerte. Ursache war ein Namensfehler (die Vanilla-Stufe hei\195\159t \"priority\", nicht \"priorityuser\") zusammen mit einem Absicherungsweg, der bei unlesbarer Rollen-Liste im Zweifel Personal annahm. Das Symbol wartet jetzt auf die best\195\164tigte Antwort des Servers, bevor es erscheint, das schlie\195\159t jeden falsch beurteilten Rangnamen ein, nicht nur diesen einen.",
                "GRO\195\159ER FUND, betrifft jeden Server: das Einr\195\164umen in Fahrzeug-Beh\195\164lter lief bei ALLEN Spielern \195\188ber einen Sonderweg, den nur Aegis-Beh\195\164lter mit zugewiesenem Stauraum h\195\164tten nehmen d\195\188rfen. Die Pr\195\188fung dahinter hielt jeden f\195\188r einen Admin, dessen Zugriffsstufe nicht leer war, und in Build 42 hat jeder normale Spieler die Stufe \"user\". Folgen: Kofferr\195\164ume mancher Fahrzeug-Mods lie\195\159en sich von normalen Spielern nicht mehr bef\195\188llen, und jeder Transfer in ein Fahrzeug nahm den langsamen Weg. Der Sonderweg greift jetzt nur noch dort, wo wirklich ein Aegis-Stauraum vergeben wurde.",
                "Auf demselben Sonderweg war die Transferdauer neu erfunden statt von Vanilla \195\188bernommen: kleine Sachen wie T\195\188ten oder Geld brauchten rund eine Sekunde pro St\195\188ck statt so gut wie keine Zeit, und der Vorteil aus \"Geschickt\" fiel unter den Tisch. Die Dauer wird jetzt genau nach der Vanilla-Formel berechnet, Geschickt und Zwei linke H\195\164nde eingerechnet.",
                "Der Sonderweg fasst Bewegungen in das eigene Inventar eines Charakters nicht mehr an. Das Nachladen einer Waffe schiebt jede einzelne Patrone als ganz normalen Inventar-Transfer, und wer eine zugewiesene Tragkraft hatte, dessen Inventar galt als Aegis-Beh\195\164lter, womit auch die Patronen auf dem Sonderweg landen konnten. Eine Patrone, die dabei nicht ankam, lie\195\159 die Waffe halb geladen zur\195\188ck, sodass man f\195\188r sechs Schuss mehr als sechs Nachlade-Bewegungen brauchte.",
                "Bei manchen Fahrzeugen lie\195\159 sich trotz zugewiesenem Stauraum nichts einr\195\164umen, obwohl man direkt vor dem offenen Kofferraum stand. Der Server ma\195\159 die Entfernung zum Mittelpunkt des Fahrzeugs statt zum Kofferraum selbst, und bei einem langen Fahrzeug wie einem Milit\195\164r-Lkw liegt der Kofferraum mehrere Kacheln hinter dem Mittelpunkt. Die Pr\195\188fung nutzt jetzt denselben Bereich, den auch Vanilla selbst verwendet, um zu entscheiden ob ein Charakter ein Fahrzeugteil erreicht.",
                "Auf demselben Sonderweg wurde jede Ablehnung \195\188berstimmt, auch die eines anderen Mods. L\195\132uft zum Beispiel Knox Claim mit auf dem Server und verweigert einem Spieler das Pl\195\188ndern eines beanspruchten Fahrzeugs, h\195\164tte ein zugewiesener Aegis-Stauraum diese Ablehnung ausgehebelt. Der Sonderweg greift jetzt nur noch ein, wenn wirklich Vanilla selbst abgelehnt hat.",
                "Das Aegis-Symbol in der Werkzeugleiste rutschte bei manchen Mod-Zusammenstellungen an den unteren Bildschirmrand. Es hat sich an das unterste fremde Symbol geh\195\164ngt, das es in der Leiste finden konnte, auch wenn dieses in einer ganz anderen Gruppe weit darunter sa\195\159. Es sucht sich seinen Platz jetzt nur noch innerhalb der zusammenh\195\164ngenden Gruppe direkt \195\188ber sich, ein gro\195\159er Abstand gilt als Gruppenende. Wird dabei etwas \195\188bersprungen, steht das einmalig im Log.",
                "Gottmodus, Unsichtbarkeit und Geistmodus gingen von selbst wieder an, obwohl die neue Sandbox-Option sie ausschalten sollte. Sie wirkte nur genau in dem Moment, in dem ein Stufenwechsel bemerkt wurde, und die Engine vergibt die drei nicht immer punktgenau dazu. Die Pr\195\188fung l\195\164uft jetzt bei jedem gezeichneten Bild statt nur alle paar Sekunden, ein sichtbares Aufblitzen bleibt aus. Was du selbst \195\188ber das Panel einschaltest, bleibt an: Aegis merkt sich deine Absicht und redet dir nicht hinein. Die Vollheilung bei der Bef\195\182rderung l\195\164sst sich davon unabh\195\164ngig nicht verhindern, sie h\195\164ngt am Gottmodus selbst und ist schon vorbei, bevor Aegis reagieren kann.",
                "Die Kill-Zahlen im Spielerbereich konnten weit \195\188ber jedes glaubhafte Ma\195\159 steigen (\195\188ber 4000 bei etwa 1000 wirklichen Kills). Direkt nach dem Anmelden meldet die Spielfigur auf dem Server kurz null Kills, der n\195\164chste Vergleich hielt die gesamte Lebensleistung f\195\188r einen frischen Zuwachs und rechnete sie noch einmal obendrauf, bei jeder Anmeldung erneut. Ein Sprung \195\188ber 150 Kills zwischen zwei Messungen gilt jetzt als Anmelde-Artefakt und wird nicht gutgeschrieben.",
                "Auf der Sandbox-Seite lief der Text der Eingabefelder unter die Bildlaufleiste. Die Zeilen rechnen jetzt mit deren Breite.",
                "Die Sandbox-Seite sprang beim Vergr\195\182\195\159ern oder Verkleinern des Fensters zur\195\188ck auf die erste Kategorie und verwarf dabei alle noch nicht \195\188bernommenen \195\132nderungen. Kategorie, Suchtext und die ge\195\164nderten Werte bleiben jetzt erhalten.",
                "Im Bau-Pinsel waren die Kn\195\182pfe der Palette unsichtbar, auch Best\195\164tigen und Abbrechen. Die Karte, auf der sie sitzen, wurde nach ihnen gezeichnet und hat sie \195\188bermalt, angeklickt werden konnten sie die ganze Zeit.",
                "Steht die Zahl der gemerkten Fahrzeuge je Spieler auf 0, ist der Merken-Knopf im Spielerpanel jetzt grau. Vorher lie\195\159 er sich dr\195\188cken und der Server lehnte jedes Mal ab.",
            } },
        } },
        { version = "2.3.5", date = "August 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Die Zahl der gemerkten Fahrzeuge je Spieler ist jetzt eine Sandbox-Option (Aegis Ereignisse, \"Gemerkte Fahrzeuge je Spieler\"). Vorher waren es fest f\195\188nf. 0 schaltet das Merken ab, das H\195\182chstma\195\159 ist 20. Auf Servern mit Knox Claim z\195\164hlt weiterhin dessen eigene Grenze. Wer den Wert senkt, nimmt niemandem etwas weg: bereits gemerkte Fahrzeuge bleiben, es kommen nur keine neuen dazu.",
            } },
            { title = "Behoben", points = {
                "Prozentzeichen in den Texten auf 42.20.1 umgestellt. Der Hotfix vom 5. August hat die Behandlung des Zeichens in \195\156bersetzungsdateien ge\195\164ndert, ein dargestelltes Prozent muss jetzt doppelt geschrieben werden. Betraf vier Texte in allen 13 Sprachen, darunter \"Zustand: 95%\" auf der Gesundheitsseite und der Fortschritt beim Sichern.",
                "Der geplante Neustart lief ab: der Zeitgeber z\195\164hlte herunter, am Ende stand nur \"Unknown command restart\" im Chat und der Server blieb oben. Der Takt, in dem der Server den Auftrag wiederholte, h\195\164ngt an der Spielzeit und lief auf kurzen Tagen etwa alle sieben Sekunden. Damit kam die Wiederholung immer der eigenen Absicherung zuvor, die nach acht Sekunden den Befehl h\195\164tte schicken sollen, der wirklich existiert. Der Server wartet jetzt echte Minuten zwischen zwei Versuchen, und ein zweiter Anlauf geht sofort auf den funktionierenden Befehl.",
            } },
        } },
        { version = "2.3.4", date = "August 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Die Safehouse-Seite im Spielerpanel zeigt jetzt den Weg nach Hause (Entfernung und Richtung, live) und bietet den Vanilla-Schalter zum Wiederbeleben im Safehouse an, sofern der Server das erlaubt.",
                "Auf Servern mit Knox Claim zeigt die Fahrzeuge-Seite im Spielerpanel jetzt deine dort eingetragenen Fahrzeuge, samt 3D-Vorschau. Entfernung, Navi und Zustandsbalken gibt es, sobald der Wagen in deiner N\195\164he geladen ist. Freigeben l\195\164uft weiter \195\188ber das Knox-Claim-Fenster, deshalb bleibt der Vergessen-Knopf f\195\188r diese Eintr\195\164ge aus.",
            } },
            { title = "Behoben", points = {
                "Der automatische Neustart konnte verpuffen: der Server kann sich nicht selbst beenden und reicht den Befehl an einen berechtigten Admin-Client weiter, tat das aber genau EINMAL. War in dieser Sekunde niemand empfangsbereit, liefen alle Warnungen und nichts passierte (Community-Meldung). Jetzt klopft der Server jede Minute erneut, bis der Neustart wirklich greift, gibt nach zehn Minuten mit Protokolleintrag auf, und sowohl das Senden als auch das Ausf\195\188hren stehen ab jetzt im Protokoll.",
                "Gemerkte Fahrzeuge wurden nach einem Server-Neustart zu leeren H\195\188llen: keine Position, keine Balken, kein Navi. Der Bestand hing an der Fahrzeug-Nummer, die das Spiel nach jedem Neustart neu vergibt. Beim Merken wandert jetzt eine feste Kennung ans Fahrzeug, \195\188ber die Server und Panel es immer wiederfinden, die Nummer heilt sich dabei von selbst. Eintr\195\164ge aus fr\195\188heren Versionen ohne Kennung bleiben leider H\195\188llen, einmal Vergessen und neu Merken r\195\188stet sie um.",
                "Die 3D-Vorschau im Spielerpanel wurde \195\188berarbeitet: sie startet bei jedem Fahrzeugwechsel frisch, blendet dabei ohne Zucken um, und das Fahrzeug sitzt tiefer und damit besser im Rahmen. Zoom und Verschieben mit Shift gelten f\195\188r das gerade gew\195\164hlte Fahrzeug und werden beim Wechsel zur\195\188ckgesetzt. Manche Mod-Fahrzeuge sind schief um ihren Modell-Ursprung gebaut und sitzen deshalb in JEDER Vorschau des Spiels schief, dagegen hilft nur das Verschieben von Hand.",
                "Der Weg nach Hause auf der Safehouse-Seite ist jetzt golden und anklickbar: ein Klick richtet den Bildschirm-Pfeil aufs Zuhause, ein zweiter schaltet ihn ab.",
                "Beim Wiederbeleben im Safehouse landete man neben dem Haus statt darin: das Spiel vertauscht bei der Berechnung des Punkts Breite und H\195\182he der Zone, bei l\195\164nglichen Zonen liegt er dadurch drau\195\159en. Aegis rechnet den Punkt jetzt selbst richtig.",
                "Bei Fahrzeugen aus Knox Claim fehlten nach einem Neuanmelden Entfernung, Himmelsrichtung, die Zustandsbalken und die Einzelteil-Liste. Die Zuordnung lief \195\188ber die Netz-Nummer des Fahrzeugs, und die vergibt das Spiel nach jedem Neustart neu. Gesucht wird jetzt \195\188ber die Kennung am Fahrzeug selbst.",
                "Aegis hat zweimal je Sekunde versucht, dem K\195\182rper-Inventar eine Kapazit\195\164t zu setzen, wenn eine Tragkraft zugewiesen war. Das f\195\188llte das Server-Protokoll mit Warnungen, ohne Wirkung. Der K\195\182rper wird jetzt nur noch \195\188ber den vorgesehenen Weg bedient.",
                "Zugewiesener Stauraum wirkte f\195\188r normale Spieler nur bis 100, obwohl das Panel den vollen Wert zeigte (Community-Meldung). Bei Kisten fiel das kaum auf, weil deren Vorgabe darunter liegt, bei Arbeitsplatten und H\195\164ngeschr\195\164nken ging gar nichts mehr, denn die sitzen schon auf dieser Grenze. Das Spiel deckelt Welt-Beh\195\164lter beim Lesen hart, und die Pr\195\188fung beim Verschieben l\195\164uft an unserer Vorgabe vorbei. Bisher hatten nur Admins den Umweg \195\188ber den Server, jetzt nimmt ihn jeder, sobald der Beh\195\164lter einen zugewiesenen Stauraum hat. Der Server pr\195\188ft dabei weiterhin Reichweite, Gegenstand und genau diesen Wert.",
                "Neustart zu fester Uhrzeit und die Automatik-Verankerung rechneten in Weltzeit statt in deiner Ortszeit: wer 00:11 eintrug, bekam den Neustart um 02:11. Eingabe und Anzeige laufen jetzt \195\188ber deine lokale Uhr.",
                "Hilfe und Changelog liefen beim Verkleinern des Fensters mit dem alten Zeilenumbruch weiter und der Text verschwand rechts unter der Bildlaufleiste. Der Umbruch pr\195\188ft jetzt vor jedem Zeichnen, ob er noch zur Fensterbreite passt.",
                "Der Mod-Filter im Gegenst\195\164nde-Katalog ist jetzt immer sichtbar. Ohne installierte Item-Mods hat er sich versteckt und dabei ein Loch in der Filterzeile hinterlassen, das nach einem Fehler aussah. Jetzt steht dann eben nur Project Zomboid darin.",
                "Der Hinweistext auf der leeren Fahrzeuge-Seite war breiter als die Spalte und vorne abgeschnitten.",
                "Der Knopf unter der Fahrzeugliste hei\195\159t jetzt \195\188berall Freigeben: ein gemerktes Fahrzeug verl\195\164sst die Liste, ein Knox-Claim-Fahrzeug wird wirklich freigegeben. Und die Ankunft zuhause begr\195\188\195\159t dich nicht mehr mit Fahrzeug gefunden.",
                "Der Knopf zum Merken eines Fahrzeugs verschwand auf Servern mit Knox Claim doch nicht. Der Server hat das Merkmal richtig geschickt, aber das Spielerpanel baut seinen Zustand Feld f\195\188r Feld neu auf und kannte das neue Feld nicht, also fiel es beim Empfang lautlos weg. Aus 2.3.3, sofort behoben.",
                "Die feste Zeile powered by Aegis in der Fu\195\159leiste ist raus, aus beiden Panels. Sie hat dort nur Platz gekostet.",
            } },
        } },
        { version = "2.3.3", date = "August 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Gegenst\195\164nde nach Herkunfts-Mod filtern (Community-Wunsch): neben dem Kategorie-Filter w\195\164hlst du jetzt den Mod, und bei Mod-Gegenst\195\164nden steht klein hinter dem Namen, woher sie stammen. Auch die Suche findet Mod-Namen. Ohne Mods bleibt der Filter verborgen.",
                "Zusammenspiel mit Knox Claim: l\195\164uft dieser Mod auf dem Server, verwaltet er die Fahrzeuge. Aegis zieht dann seinen eigenen Knopf zum Merken eines Fahrzeugs im Spielerpanel zur\195\188ck, damit nicht zwei Listen nebeneinander laufen, von denen jede nur ihre H\195\164lfte kennt. Der Knopf zum Vergessen bleibt, damit alte Eintr\195\164ge verschwinden k\195\182nnen. Ohne Knox Claim \195\164ndert sich nichts.",
            } },
            { title = "Behoben", points = {
                "RECHTE-L\195\156CKE: auf Servern mit eigenen Rang-Rollen (Kopftags wie \"Veteran\") galt jeder Traeger einer solchen Rolle als Serverpersonal und hatte damit das volle Panel, auch ohne Admin-Werkzeug und ohne zugewiesene Aegis-Rolle. Aegis hat jede benannte Zugangsstufe im Zweifel als Personal gewertet, und da eine Aegis-Rolle Rechte nur einschraenkt und nie vergibt, bedeutete das vollen Zugriff, serverseitig durchgesetzt. Jetzt zaehlt nur noch, wer nachweislich das Admin-Werkzeug traegt. Die vier Vanilla-Stufen Admin, Moderator, GM und Beobachter kommen weiterhin unabhaengig vom Rollen-Verzeichnis herein, und wenn das Verzeichnis gar nicht lesbar ist, bleibt der alte Notausgang, damit sich kein echter Admin aussperrt. Jede Entscheidung steht ab jetzt mit Begruendung im Server-Protokoll.",
                "Die eingestellte Tragkraft hat auch die harte Aufheb-Grenze auf denselben Wert gezogen. Das Spiel kennt zwei Grenzen: ab der Tragkraft bist du \195\188berladen, erst an der harten Grenze (fest bei 50) verweigert es das Aufheben ganz. Wer eine kleine Tragkraft zugewiesen bekam, konnte am Limit gar nichts mehr aufheben, und der Wert kam nach dem Tod \195\188ber die gespeicherte Liste zur\195\188ck. Jetzt bleibt unterhalb von 50 das normale \195\156berladen erhalten, nur gr\195\182\195\159ere Werte heben die harte Grenze weiter an. Betroffene Charaktere werden beim n\195\164chsten Einstieg von selbst bereinigt.",
                "Die Bed\195\188rfnis-Regler im Wertefenster wirken jetzt schon w\195\164hrend des Ziehens statt erst beim Loslassen. Der Wert wandert dabei viermal je Sekunde zum Server, ohne je Schritt eine Meldung auszul\195\182sen, und im Protokoll steht weiterhin nur der Wert, bei dem du losl\195\164sst.",
                "Die Safehouse-Karte im Spielerpanel blieb leer, obwohl die Zone auf der Zonen-Seite des Adminpanels stand. Sie hat die Liste auf dem eigenen Rechner gelesen, und eine Zone, die auf dem Server entsteht, muss dort nicht auftauchen. Sie fragt jetzt den Server, so wie die Zonen-Seite es immer getan hat, und zieht bei offener Seite von selbst nach.",
            } },
        } },
        { version = "2.3.2", date = "August 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Bed\195\188rfnisse frei einstellen (Community-Wunsch): im Wertefenster \195\182ffnet der neue Knopf oben rechts Regler f\195\188r Hunger, Durst, M\195\188digkeit, Ausdauer, Stress, Panik, Langeweile, Unzufriedenheit, Schmerz, \195\156belkeit, Rausch und N\195\164sse. Bisher konnte das Panel diese Werte nur alle auf einmal zur\195\188cksetzen, jetzt stellst du jeden einzeln ein, auch nach oben. Die Grenzen kommen aus dem Spiel selbst, geschickt wird erst beim Loslassen des Reglers.",
                "Die Hilfe erkl\195\164rt unter Rollen jetzt Schritt f\195\188r Schritt, wie du jemandem eingeschr\195\164nkte Adminrechte gibst.",
            } },
            { title = "Behoben", points = {
                "RECHTE-L\195\156CKE: wer eine Vanilla-Stufe mit Admin-Werkzeug hatte, also auch Observer, GM und Moderator, konnte die Rollen-Seite immer \195\182ffnen und sich selbst jeden Bereich geben. Der Aussperr-Schutz h\195\164ngt jetzt an der Vanilla-F\195\164higkeit RolesWrite, die nur die Stufe Admin hat. Ein echter Admin kann sich weiterhin nicht selbst aussperren, alle anderen brauchen den Bereich Rollen ausdr\195\188cklich in ihrer Aegis-Rolle.",
                "Die Eigenschaft Organisiert wirkte in jedem Beh\195\164lter nicht mehr, dem ein Admin einmal einen Stauraum zugewiesen hatte. Das Spiel rechnet den Bonus auf den Stauraum obendrauf, unsere Vorgabe hat ihn dabei verschluckt. Betroffene Spieler konnten nichts mehr einr\195\164umen, sobald der normale Stauraum ohne Bonus erreicht war. Organisiert und Unordentlich wirken jetzt auch auf zugewiesene Werte.",
                "Die Bildlaufleiste der \195\156bersicht lag auf dem Ziehgriff unten rechts und lie\195\159 sich nicht mehr greifen, sobald das Fenster klein genug zum Scrollen war.",
            } },
        } },
        { version = "2.3.1", date = "August 2026", sections = {
            { title = "Behoben", points = {
                "Der goldene Knopf und der blaue Spieler-Knopf fehlten bei manchen Mod-Zusammenstellungen vollst\195\164ndig. Aegis setzt sich unter alle anderen Symbole der Ausr\195\188stungsleiste, hat dabei aber auch Fl\195\164chen mitgemessen, die gar keine Symbole sind, und rutschte so unter den Bildschirmrand. Jetzt z\195\164hlen nur noch symbolgro\195\159e Nachbarn, und der Knopf bleibt in jedem Fall sichtbar.",
                "Ein Mod, der die Ausr\195\188stungsleiste komplett \195\188bernimmt, kann die Aegis-Kn\195\182pfe nicht mehr verschwinden lassen. Fehlen sie, werden sie nachgesetzt.",
                "Fehler anderer Mods im Inventar werden nicht mehr f\195\164lschlich als Aegis-Fehler gemeldet. Aegis h\195\164ngt sich daf\195\188r nicht mehr in die Vanilla-Rucksackleiste ein.",
                "Aegis schreibt keine Diagnosezeilen mehr ins Log, wenn eine Tasche zu voll ist.",
            } },
        } },
        { version = "2.3", date = "Juli 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Seiten ausblenden: das Schloss unten in der Leiste zeigt im offenen Zustand ein Auge an jedem Eintrag. Was du nie benutzt, blendest du aus, das Plus daneben holt es zur\195\188ck. Gilt nur f\195\188r dich und \195\164ndert keine Rechte.",
                "Die \195\156bersicht ist jetzt ein Baukasten: der Bearbeiten-Knopf oben rechts schaltet den Umbaumodus, Karten lassen sich ziehen, entfernen und aus dem Katalog erg\195\164nzen. Jeder Admin beh\195\164lt sein eigenes Layout, ohne Umbau sieht alles aus wie bisher.",
                "Der Katalog reicht \195\188ber alle Bereiche, auf die du Zugriff hast: neben Online-Spielern und den Funktions-Schaltern legst du dir eine Kachel f\195\188r jede Seite hin, von Welt \195\188ber Werkzeuge und Zonen bis zu den Serveroptionen. Ein Klick darauf springt dorthin.",
                "Neue Karte Zeit und Wetter: Morgen, Mittag, Abend und Mitternacht direkt auf der \195\156bersicht, dazu der Knopf, der ein laufendes Unwetter beendet.",
                "Im Umbaumodus steht neben dem Bearbeiten-Knopf Standard wiederherstellen. Das baut die \195\156bersicht wieder so auf wie beim ersten \195\150ffnen.",
                "Neue Seite Serveroptionen: alle Einstellungen der Server-INI durchsuchbar und direkt im Panel \195\164nderbar, mit Kennzeichnung, was erst nach einem Neustart greift. \195\132nderungen wirken live und landen sofort in der INI. Mods und Workshop-Objekte sind gesperrt und lassen sich nur nach doppelter Warnung auf eigene Verantwortung bearbeiten.",
                "Dein Servername statt AEGIS: auf der Server-Seite tr\195\164gst du ihn ein, beide Panels zeigen ihn bei allen Spielern, darunter steht fest powered by Aegis. Leer lassen bringt AEGIS zur\195\188ck.",
                "Neue Schalterkarte auf der Server-Seite: Spielerbereich, Spieler-Claims und Spieler-Kits lassen sich dort und in der Sandbox an- und abschalten, live und f\195\188r alle. Der Server setzt es durch, nicht nur die Anzeige.",
                "Kits ohne Rollenbindung kann jetzt wirklich jeder abholen. Bisher kamen Spieler ohne Rolle gar nicht erst an die Kits-Seite, deshalb wirkte die Rolle wie Pflicht.",
                "Neuer Handwerk-Cheat neben dem Bau-Cheat: Rezepte herstellbar ohne Material, K\195\182nnen und Werkbank. Wer auch unbekannte Rezepte in der Liste will, schaltet zus\195\164tzlich Alle Rezepte kennen dazu, die beiden Schalter sind unabh\195\164ngig. Der Bau-Cheat bleibt wie er war.",
                "Der Spielerbereich zeigt Zeit und Datum nur noch mit getragener Uhr: jede Uhr bringt die Zeit, erst eine Digitaluhr auch das Datum.",
                "Serveroptionen sind ein eigener Bereich in den Rollen geworden: du kannst einem Admin die Server-Seite geben und die INI-Einstellungen trotzdem vorenthalten. Bestehende Rollen behalten den Zugang, nachtragen musst du nichts.",
                "Beim Hinzuf\195\188gen einer Eigenschaft im Wertefenster steht beim \195\156berfahren, was sie bewirkt, dazu die Punkte und der Grund, falls die Zeile rot ist.",
            } },
            { title = "Behoben", points = {
                "Die Fahrzeugwerte im Spielerbereich sind live: Tanken und Reparieren neben dem Wagen zeigt sich sofort, nicht erst nach einer halben Minute.",
                "Server-Branding sitzt jetzt rechts neben den Funktions-Schaltern statt darunter, die rechte Seite war dort leer.",
                "Die Werte-Spalte der Serveroptionen l\195\164uft nicht mehr in die Bildlaufleiste.",
                "Die Seitenleiste l\195\164uft bei vielen Seiten und niedrigem Fenster nicht mehr \195\188ber die Fu\195\159zeile. Passt die Liste trotz enger Packung nicht mehr, l\195\164sst sie sich mit dem Mausrad schieben.",
            } },
        } },
        { version = "2.2", date = "Juli 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Die Spielerwerte sind jetzt ein Aegis-Fenster statt des Vanilla-Fensters. Es steckt hinter demselben Knopf auf der Spieler-Seite und l\195\164sst sich verschieben und in der Gr\195\182\195\159e ziehen wie die anderen Aegis-Fenster.",
                "Alles darin wirkt sofort. Eigenschaften, Beruf, Namen, Gewicht, Stufen und Erfahrung greifen beim Ziel unmittelbar, ohne neu zu verbinden. Das Vanilla-Fenster \195\164nderte deine eigene Kopie dieses Spielers und konnte dabei Fertigkeiten zur\195\188cksetzen, die er seit dem Beitritt gelernt hatte.",
                "Fertigkeiten zeigen Stufe, Erfahrung und den Bonus, den der Charakter wirklich bekommt. Du kannst Erfahrung geben, eine Stufe anheben oder senken oder sie direkt setzen.",
                "Jede Eigenschaft sitzt in einem eigenen kleinen Feld mit einem Kreuz, ein Klick darauf nimmt sie weg. Beim Hinzuf\195\188gen kennzeichnet die Liste in Rot, was sich mit einer Eigenschaft \195\188berschneidet, die der Spieler schon hat.",
                "Bei den Namen gibt es Vorname, Nachname und Anzeigename samt Weg zur\195\188ck zum automatischen. Eine Gewichts-Eigenschaft zieht das Gewicht mit, sonst dreht der Server die \195\132nderung binnen Minuten zur\195\188ck.",
            } },
            { title = "Behoben", points = {
                "M\195\182bel aus dem Bau-Pinsel lassen sich wieder abr\195\164umen. Sie entstanden bisher so, dass die Engine das Entfernen verweigerte, weshalb weder Roden noch der Vorschlaghammer daran kamen.",
                "Auch ein Boden aus dem Bau-Pinsel l\195\164sst sich roden. Karten-B\195\182den bleiben gesch\195\188tzt, die zu entfernen w\195\188rde L\195\182cher in die Welt rei\195\159en.",
                "Das Speichern von Rollenrechten meldet keinen Fehler mehr, wenn ein Tr\195\164ger der Rolle offline ist.",
                "Beim Scrollen einer Karte bleiben keine alten Zeilen mehr hinter den Bedienelementen stehen.",
            } },
        } },
        { version = "2.1", date = "Juli 2026", points = {
            "Kit-Anspr\195\188che zur\195\188cksetzen: ein Knopf beim gew\195\164hlten Kit l\195\182scht alle Anspr\195\188che darauf und nennt die Zahl der betroffenen Spieler. Diese k\195\182nnen das Kit danach wieder abholen, ohne Serverneustart.",
            "Das Uhr-Symbol in der Kopfzeile des Editors \195\182ffnet die Liste der Spieler mit Anspruch samt Abholzeitpunkt. Dort setzt du einzelne Spieler zur\195\188ck, wenn nur einer sein Kit braucht.",
            "Abgesetzt am Ende dieser Liste steht Alle Anspr\195\188che l\195\182schen: das entfernt die Anspr\195\188che auf allen Kits f\195\188r jeden Spieler und verlangt einen getippten Grund f\195\188rs Protokoll.",
            "Gedacht ist das f\195\188r den Start einer frischen Welt: die Anspr\195\188che liegen getrennt vom Weltspeicher und \195\188berstehen dadurch einen Reset. Sonst gelten alle Kits als abgeholt und niemand kommt an seins.",
            "Lie\195\159 sich die Anspruchsliste nicht vollst\195\164ndig lesen, bleibt jedes Zur\195\188cksetzen gesperrt und ausgegraut, damit kein halber Stand gel\195\182scht wird.",
            "Folgen l\195\164uft jetzt fl\195\188ssig: du gleitest gleichm\195\164\195\159ig mit dem Ziel mit und h\195\164ltst festen Abstand dahinter, statt kurz still zu stehen und dann ein St\195\188ck zu springen.",
            "Beim Folgen bleibt die Kamera auf der richtigen Etage, auf Treppen sprang sie vorher um ein ganzes Stockwerk. Im Erdgeschoss schwebst du auch nicht mehr knapp \195\188ber dem Boden.",
            "Best\195\164tigungsfenster passen sich jetzt dem Text an: sie werden breiter und lange S\195\164tze brechen sauber um. Vorher stand in manchen Sprachen der halbe Satz unlesbar auf dem Hintergrund.",
        } },
        { version = "2.0", date = "Juli 2026", points = {
            "Vertr\195\164gt sich mit anderen Seitenleisten-Mods: Aegis erkennt fremde Kn\195\182pfe und ordnet sich darunter ein, statt sie zu \195\188berdecken. Faction Framework beh\195\164lt seinen Platz.",
            "Fraktionen aus Faction Framework erscheinen jetzt mit in der Liste, gekennzeichnet mit FF. Bearbeiten kann Aegis sie nicht, das macht der andere Mod selbst.",
            "Spielerbereich abschaltbar: in den Sandbox-Einstellungen unter Aegis Ereignisse steht ein Schalter, der das blaue Panel serverweit ausblendet. Das Admin-Panel bleibt davon unber\195\188hrt.",
            "Zonen komplett neu: Grenze bearbeiten setzt jetzt Rechteck an Rechteck, der Editor bleibt dabei offen und alles wird EINE Zone. Fl\195\164che malen bleibt f\195\188r einzelne Kacheln.",
            "Zonen verschmelzen: zwei Zonen desselben Besitzers werden bei der n\195\164chsten Bearbeitung zu einer, sobald sie sich ber\195\188hren. Angesetzte Fl\195\164chen m\195\188ssen anschlie\195\159en, lose Fetzen lehnt der Editor sofort ab.",
            "Zonen laufen fl\195\188ssiger: Umrisse als lange Linien statt Kachelkanten, unver\195\164nderte Teile bleiben beim Umbau stehen, veraltete Rechtecke r\195\164umt der Client von selbst weg.",
            "Kits pro Rolle freischaltbar: das Donator-Kit sieht nur der Donator, gepr\195\188ft wird auf dem Server. Neuer Monats-Modus neben Einmalig und Abklingzeit.",
            "Discord-Booster (optional, braucht einen EIGENEN Discord-Bot): der Bot gibt einen Code aus, den der Spieler einl\195\182st, der Status l\195\164uft bis Monatsende. Ohne gesetzten Schl\195\188ssel bleibt der Bereich unsichtbar. Ein Bot wird nicht mitgeliefert, das Rechenverfahren f\195\188r die Codes gibt es auf Anfrage.",
            "Kopftag h\195\164ngt jetzt an der Rolle und l\195\164sst sich dort jederzeit an und ausschalten, die \195\132nderung greift sofort bei allen Tr\195\164gern.",
            "Safehouse-Liste auf der Fraktions-Seite je Spieler aufklappbar statt einer langen Liste aller Rechtecke.",
            "Todes-Berichte: jeder Spielertod wird vollst\195\164ndig dokumentiert (Angreifer, Waffe, Wunden, Umgebung), neuer Bereich Todesf\195\164lle im Protokoll.",
            "Folgen: Kamera heftet sich an einen Spieler, \195\188ber beliebige Entfernung.",
            "Fenstergr\195\182\195\159e frei ziehbar, Gr\195\182\195\159e wird gespeichert, Inhalt l\195\164uft beim Ziehen mit. Seiten rollen, wenn das Fenster zu klein wird.",
            "Seiten-Reihenfolge per Ziehen \195\164nderbar, mit Schloss in der Seitenleiste. Minimieren als kleine frei bewegliche Leiste.",
            "Durchscheinende Vorschau vor dem Wiederherstellen abgerissener Bauten, die Karte dazu ist frei verschiebbar.",
            "Entfernungs-Sperre der Spieler-Aktionen entfernt, fast alles wirkt jetzt \195\188ber jede Distanz.",
            "Rechte: Wer einen Bereich zugewiesen bekommt, darf alles darin. Rollen vergeben ohne Admin-Status keine Admin-Rechte mehr.",
            "Warenkorb bleibt beim \195\132ndern der Fenstergr\195\182\195\159e erhalten, Eintr\195\164ge lassen sich per Klick wieder entfernen.",
            "Hilfe und Changelog direkt im Panel.",
            "Neu f\195\188r deine Spieler: der Spielerbereich, ein eigenes blaues Panel f\195\188r jeden auf dem Server. \195\156ber Rollen vergibst du dort Kit-Zugang und Zonen-Kacheln. Was er kann, steht im Changelog dieses Panels.",
            "Absturz behoben, der beim Aufheben oder Verschrotten von M\195\182beln den Server-Handler zerlegte. Gepr\195\188ft auf 42.20.",
            "Diverse Fehlerbehebungen, unter anderem beim Zeit-Setzen und der Rechte-Pr\195\188fung.",
        } },
        { version = "1.1", date = "Juli 2026", points = {
            "Fahrzeug-Detail-Fenster mit Tank, Schl\195\188sseln, Teilen, Farbe und Zustand.",
            "Fahrzeug-Teleport samt Anh\195\164nger und Ladung.",
            "Sprite-Inspektor und Bau-Pinsel mit eigener Palette.",
            "Bau-Protokoll mit Wiederherstellen, auch f\195\188r Treppen und Garagentore.",
            "Tragelast und Stauraum bis 1000, Vollheilung kuriert Bisse.",
            "Admin-Tag manuell schaltbar, Rollen-Zuweisung mit Namens-Tag in Rollenfarbe.",
            "Kompatibilit\195\164t mit FactionFramework.",
        } },
        { version = "1.0", date = "Juli 2026", points = {
            "Erste Ver\195\182ffentlichung: Kr\195\164fte, \195\156bersicht, Spieler, Gegenst\195\164nde, Fahrzeuge, Welt, Zonen, Horde, Server, Sandbox, Protokoll, Rollen, Tiere, Fraktionen, Werkzeuge.",
        } },
    },
}

AegisHelpContent.EN = {
    help = {
        { title = "Getting started", lines = {
            "The golden panel is the admin cockpit: only real server admins see it, and the Roles page decides which pages each of them may use.",
            "Open it: click the golden crest in the small floating bar at the top, slightly left of centre, or press F7; rebind the key under Options in the Mods tab.",
            "Move the button bar: drag it by its handle to any spot; a click on the handle folds it away.",
            "Hide without losing work: F7 only collapses the window, every list and input survives; just the X in the top right really closes it.",
            "Shape the window: drag the header to move, the dot triangle in the bottom right to resize, the minus shrinks it to a small bar, the plus restores it.",
            "Reorder the sidebar: open the padlock at the bottom, drag entries along the golden line, close it to fix the order; this help window moves and resizes too.",
        } },
        { title = "Powers", lines = {
            "Every card on this page is a switch that acts the moment you click it.",
            "Toggle a power: god mode, invisible, walk through walls, fast movement, instant actions, unlimited carry, unlimited endurance, night vision and more.",
            "Observe unnoticed: the spectator switch in the top right enables god mode, invisible, walk through walls and fast movement in one go.",
            "Return to normal: All powers off resets every switch at once, spectator included.",
            "Show or hide the red marker above your head with Admin tag; the choice survives restarts.",
        } },
        { title = "Overview", lines = {
            "The start page is a board of cards; your layout is yours alone and is remembered.",
            "Rebuild it: the button in the top right enters rearrange mode, drag cards around, the cross removes one, the plus tile opens the catalog.",
            "Stock it: the catalog holds every card you may see, from power switches, heal, clock and server pulse to a jump tile for every panel page.",
            "Steer time and weather: the Time and weather card sets morning, noon, evening or midnight and ends a running storm without leaving the page.",
            "Start over: Restore default in rearrange mode rebuilds the layout of the first launch.",
            "Heal from here: the heal card also clears bites, scratches and the zombie infection.",
        } },
        { title = "Players", lines = {
            "Left the list of everyone online, the top switch adds all offline players ever seen; the right side acts on the selected player.",
            "Act over any distance: teleport to them, bring them to you, heal, satisfy needs, give items, open their stats, toggle their god mode or invisibility.",
            "Only the 3D preview on the left needs the player close to you, otherwise it shows Out of range.",
            "Shadow someone: Follow (ghost symbol) pins your camera to them at any range, you travel along invisibly; a second click stops it.",
            "Moderate: Warn needs a reason, Mute a duration, Kick asks an optional reason and acts at once; Ban and Temp ban demand a reason for the log.",
            "Unban stays visible but unlocks only for truly banned players; the relations radar shows who they spent the week with, Carry weight raises the limit to 1000.",
        } },
        { title = "Items", lines = {
            "Any item in the game, handed to yourself or a selected player.",
            "Find it: type part of the name into the search on top and narrow with the category box; the Recent row just below repeats your last handouts.",
            "Hand it out: set the amount with the buttons at the bottom (1, 5, 10 and so on), then give to your own inventory or to the selected player.",
        } },
        { title = "Vehicles", lines = {
            "Spawning, repairing and moving vehicles; the rotate buttons only turn the preview camera.",
            "Spawn one: pick it from the list, then Spawn at me places it at your position with a fixed facing.",
            "Place with direction: use Place in world, the mouse wheel turns the cursor vehicle by single degrees, R by 30 degree steps, left click sets it down.",
            "Edit one: right click it in the world (Edit vehicle) or use the panel button for the nearest; fill tank, charge battery, repair any part, colour and condition.",
            "Need a key: Create new key puts a fresh one into the glove box, or into your inventory as fallback.",
            "Move it: sit in it yourself and use any panel teleport, trailer and cargo travel along; nobody else aboard, fetching a distant vehicle is not possible.",
        } },
        { title = "World", lines = {
            "Time, weather and noise for the whole server, everything takes effect at once.",
            "Set the time: the four presets (morning, noon, evening, midnight) or the slider; IG date and IG time move the whole calendar.",
            "Start a storm: thunderstorm, tropical storm and blizzard hit visibly right away while the real weather builds underneath; the slider sets the duration.",
            "End or shortcut it: Stop weather ends everything at once, Instant rain needs no buildup.",
            "Mix your own: the weather designer blends clouds, rain, fog, wind and an optional thunder cadence; Save as preset keeps the mix under its own name.",
            "Wake the dead: the noise slider (10 to 500) only sizes the Make noise button; Thunder strike here, gunshot and fireworks use fixed ranges at your position.",
        } },
        { title = "Zones", lines = {
            "Safehouse management beyond the vanilla limits; however many pieces a zone has, it counts as one whole.",
            "Create one: New zone, pick the owner, then drag rectangles or paint the area; extra rectangles may be joined before applying, each must connect to the shape.",
            "Grow one: Edit bounds, left drag attaches rectangles, right drag removes attached parts, Enter applies all, ESC discards; the original area stays protected.",
            "Shrink or fine tune: Paint area works tile by tile, left click paints, right click erases even on the existing area; you must stand inside the zone.",
            "Guard it: Backup stores a copy of the whole zone for a later restore, after griefing for example; Show zones draws every zone into the world.",
            "Touching areas of the same owner merge into one zone.",
        } },
        { title = "Horde and animals", lines = {
            "Quick zombie and animal spawns, always around you.",
            "Spawn a horde: set count and radius, then Spawn at my position drops the zombies around you.",
            "Clean up after: Remove zombies clears the radius you set, Remove all loaded and Remove corpses go further.",
            "Stage a siege: the horde marches in from afar, announced by a gunshot; waves, count and distance sit in sandbox under Aegis Events.",
            "Spawn animals: pick species and breed, rotate the preview, then place in the world just like vehicles.",
        } },
        { title = "Server", lines = {
            "Restarts, world switches, staged events, player gates and the announcement live on this page.",
            "Schedule a restart: the minute buttons start a countdown all players see; time, date and the automatic mode plan fixed or repeating restarts.",
            "Keep someone with shutdown rights online at the deadline: the server hands the command over and retries for ten minutes; your host panel restarts after stop.",
            "Run the world: Save world stores the game at once, Power grid and Water grid switch the map, the player switches (area, claims, kits) are server enforced.",
            "Stage a show at your position: Storm show, Siege, Heli alert, Airdrop, Firestorm or Crawler ambush, one click each.",
            "Speak to everyone: Announce shows a golden banner mid screen for all players plus an info line in chat; Server branding renames both panel headers.",
        } },
        { title = "Server options", lines = {
            "Every setting of the server INI on one searchable page, grouped by topic, the default under each name.",
            "Change values: edit what you need and send it with Apply; everything works at once and lands in the INI, a clock marks options that need a restart.",
            "Expect stale views: other admins see your change only after a reconnect or /reloadoptions, that is the game, not the panel.",
            "Secrets stay secret: password, RCON and the Discord fields never reach a client; ports, map and the player id are locked for good.",
            "Touch Mods and workshop items only through the two warnings and with care, a typo there can silently ruin the server.",
            "Delegate carefully: Server options is a role area of its own, an admin can hold the server page and still not the INI.",
        } },
        { title = "Build tools", lines = {
            "Brush, inspector, radar, log and clearing: the tools that shape the map.",
            "Build: pick a piece from the palette, drag across tiles with the mouse held down, R rotates; floors fill the area, walls follow the line.",
            "Capture pieces: the Sprite inspector lists the names of everything on the hovered tile; one click copies the top name and files it under Custom in the palette.",
            "Trace builders: Construction radar shows who built a hovered object and when; the build log records every build and demolition with time, player and place.",
            "Undo demolitions: pick the entry in the build log, Restore shows a translucent preview at the old spot, only your confirmation rebuilds it completely.",
            "Clear areas: the first pass removes vegetation, a second everything down to the floor; Undo reverts only the last clearing, trees and generators stay lost.",
        } },
        { title = "Log and deaths", lines = {
            "Every admin action is recorded here.",
            "Find an entry: pick area and day at the top left, the entries list below, the full content sits on the right.",
            "Know the areas: actions, bans, kicks, warnings, chat moderation, admin sessions, player sessions and deaths; the build log lives on the world page.",
            "Mind retention: moderation and death logs stay forever, actions and sessions archive after 14 days and are cleared after 30 more.",
            "Investigate a death: the report names killer and weapon, injuries, infection, place with room, zombies around and players nearby; admins get an instant notice.",
        } },
        { title = "Roles", lines = {
            "Roles decide which panel pages an admin may use; a role alone never makes anyone an admin.",
            "Limit an admin: role first (tick only the allowed areas, assign below), then /setaccesslevel \"name\" observer, the lowest level that shows the panel.",
            "Assign before you promote: until a role is assigned, every staff level, observer included, has full access to all areas, the Roles page too.",
            "Keep the keys: leave the Roles area unticked and that admin cannot change rights, not even their own; the vanilla admin level always keeps role management.",
            "Split fine: Server options and Sandbox are areas of their own, the server page alone grants neither; hovering an area lists the pages it covers.",
            "Mind the tag: the role colour paints the name tag, a prompt says whether it brings only the tag or real rights; to test as a player use a second account.",
        } },
        { title = "Player panel (blue)", lines = {
            "The blue panel is the counterpart for normal players; everyone gets it automatically on joining, admins included.",
            "Hand out extras per role: claim tiles (0 means no zone claim) and kit access on the Roles page; donor perks work as own roles with a bigger budget.",
            "Switch it off only server wide: the Player area switch on the server page or in sandbox disables the blue panel for all, admins included; per role it stays on.",
            "Know what they see: character in 3D, stats and leaderboard, health with bandaging, own vehicles with nav, safehouse expiry, kits, zone claim and distress call.",
            "Answer distress calls: they reach every online admin with name, position and message; a two minute cooldown blocks spam.",
            "Operator note: switch vanilla safehouse claiming (PlayerSafehouse) off when the panel claims are in use, otherwise two paths compete.",
        } },
        { title = "Kits", lines = {
            "Kits are packages players collect in the blue panel.",
            "Build one: name it, add items via the search, set amounts, pick the mode: One time, Cooldown with a free hour count (default 24, weekly 168) or Monthly.",
            "Keep it open: with no role ticked every player can collect the kit, the normal case for a starter package.",
            "Restrict it: tick one or more roles and only their holders collect it; the blue panel shows behind the kit name which role grants it.",
            "Lift claims: they survive death and rejoin; use Reset claims on a kit, Manage claims for a single player, or Wipe all claims for everything (typed reason).",
            "Delegate and gate: the Kits area can go to single admin roles; whether players reach kits at all is set by the Player kits switch on the server page.",
        } },
        { title = "Practical notes", lines = {
            "Small habits that speed up daily work.",
            "Travel fast: right click the world map (key M) and pick Teleport here.",
            "Read the feedback: golden notices appear at the top of the panel, or as floating text at your character while the panel is hidden.",
            "Revive empty lists: the round arrow button reloads them.",
            "Retrace problems: almost every action lands in the log, the first place to look when something failed.",
        } },
    },
    tour = {
        { page = "dashboard", title = "Overview", text = "Your start page. Tiles can be reordered and hidden, and the panel remembers the layout for each admin separately." },
        { page = "powers", title = "Powers", text = "Every admin power in one place, the state comes back from the server. God mode heals you instantly." },
        { page = "roles", title = "Roles", text = "Roles restrict admins. Admin rights themselves only come from the access level." },
        { page = "options", title = "Server options", text = "Every server setting in the panel instead of the INI. Some values only take effect after a restart." },
        { page = "sandbox", title = "Sandbox", text = "The rules of your world, changeable while the server runs. The Aegis switches sit here as well." },
        { page = "tools", title = "Tools", text = "Build brush, cleanup, photo mode and construction radar. Last and with care, the cleanup really does clear everything away." },
        { page = "dock", title = "The two icons", text = "The golden crest opens the panel, the blue one your own player window. Drag the bar by its handle, a click on the handle folds it away, F7 and F6 always work." },
        { page = "help", title = "The question mark", text = "The question mark explains the page you are on. The button next to it opens the manual and the changelog, and that is also where you restart this tour." },
    },
    pagehelp = {
        dashboard = { title = "Overview", lines = {
            "Your start page, a board of cards. The button at the top right enters rearrange mode, the plus tile at the bottom opens the catalog.",
            "Every panel page has a tile of its own, one click takes you straight there.",
            "Your layout is yours alone and is remembered, other admins keep their own.",
            "Healing here also clears bites, scratches and the zombie infection.",
        } },
        powers = { title = "Powers", lines = {
            "Every admin power as a switch, each card acts immediately. The state comes back from the server.",
            "God mode heals you instantly.",
            "The spectator switch bundles god mode, invisible, walk through walls and fast movement. All powers off resets everything at once.",
            "Admin tag shows or hides the red marker above your head, the choice survives restarts.",
        } },
        players = { title = "Players", lines = {
            "Every connected player with the actions for the selected one: teleport, heal, give item, god mode and more.",
            "The switch at the top additionally shows every offline player the server has ever seen.",
            "The actions work at any distance. Only open stats and the 3D preview need the player close to you.",
            "Follow pins your camera to the player, clicking again ends it.",
            "Kick acts immediately. Ban and temp ban require a reason that lands in the log.",
        } },
        items = { title = "Items", lines = {
            "Search and hand out items. The search field filters instantly, the category box narrows the list further.",
            "The amount buttons set the count, the target is your own inventory or a selected player.",
            "At the bottom the panel remembers your recently given items as quick access buttons.",
        } },
        vehicles = { title = "Vehicles", lines = {
            "Spawn vehicles: align them in the preview, the vehicle appears in front of you facing exactly that way.",
            "Double click a vehicle in the world to open the detail window: tank, battery, key, repair every single part, color and condition.",
            "Vehicle teleport takes trailer and full cargo along.",
        } },
        animals = { title = "Animals", lines = {
            "Spawn animals: choose species and breed, rotate in the preview, then place in the world or spawn straight to you.",
            "While placing, the mouse wheel rotates in fine steps, R in coarse ones, right click cancels.",
            "Remove nearby animal takes the closest animal out of the world after a prompt.",
        } },
        world = { title = "World", lines = {
            "Time of day, date, weather and event sounds for the whole world. Presets and sliders act immediately for every player.",
            "Thunderstorm, tropical storm and blizzard build up over roughly one game hour. Instant rain skips the buildup, stop weather ends everything.",
            "The weather designer mixes custom weather and stores it permanently as a preset.",
            "Events like thunderclap or gunshot sound at your position, zombies around react to them.",
        } },
        zones = { title = "Zones", lines = {
            "Create safehouses and extend them beyond the vanilla limits. A zone made of several pieces always counts as one whole.",
            "Edit bounds attaches rectangles. Paint area is the fine tool for single tiles and the way to shrink a zone.",
            "Areas of the same owner that touch merge into one zone.",
            "Backup stores a copy of the zone that can be restored later, for example after griefing.",
        } },
        horde = { title = "Horde", lines = {
            "Zombies on demand: set count and radius, they spawn around the chosen position.",
            "Clean up removes zombies within the radius again.",
            "Siege makes a horde march in from a distance, announced by a gunshot.",
            "The fine points of the siege, waves, count and distance, live in sandbox under Aegis Events.",
        } },
        server = { title = "Server", lines = {
            "Schedule restarts, save the world, switch power and water grids, send announcements, start directing shows.",
            "The server cannot stop itself: someone authorized has to be online at the deadline, bringing it back up is the job of your host panel.",
            "The feature switches decide what players may do. The server enforces it, this is not just a display.",
            "Server branding sets the name in the header of both panels, leave it empty to get AEGIS back.",
        } },
        options = { title = "Server Options", lines = {
            "Every setting of the server INI, grouped by topic and searchable. Apply takes effect right away and writes to the INI at the same time.",
            "A clock marker flags options that only take hold after a restart.",
            "Other admins see your change only after a reconnect or after /reloadoptions.",
            "Mods and workshop items only open after two warnings. A typo there can silently ruin the server.",
        } },
        factions = { title = "Factions", lines = {
            "Every faction and safehouse on the server with owners and members, the dot shows who is online right now.",
            "Jump teleports you to the safehouse. Release removes it after a prompt, annexes included.",
            "Jumping needs the world right of your role, releasing the zones right.",
            "If Knox Claim runs on the server, it keeps holding the plot and the zone comes back. Release it there.",
            "In singleplayer there are usually no factions.",
        } },
        tools = { title = "Tools", lines = {
            "Build brush, sprite inspector, build radar, photo mode, clear area and the build log with restore.",
            "Clear area: the first pass removes only vegetation, a second pass on the same area really does clear everything down to the floor.",
            "Undo restores the last clearing.",
            "Restoring from the build log first shows a translucent preview, nothing is built until you confirm.",
        } },
        kits = { title = "Kits", lines = {
            "Build packages players collect in the blue panel: add items through the search, set the amount, pick the mode.",
            "With no role ticked a kit is open to every player on the server. Only ticked roles narrow it down to their holders.",
            "The claim is stored per player and survives death and rejoining. Only reset claims lifts it.",
            "Whether players reach kits at all is decided by the player kits switch on the server page.",
        } },
        sandbox = { title = "Sandbox", lines = {
            "The rules of your world, changeable while the server runs, grouped into the vanilla categories and searchable.",
            "Apply sends the collected changes. The Aegis switches sit here as well.",
            "The full editor additionally opens the complete vanilla editor.",
        } },
        logs = { title = "Records", lines = {
            "Every admin action stored permanently, ordered by areas from actions through bans to construction and deaths.",
            "Pick the area on the left, the entry in the middle, the full content appears on the right.",
            "Deaths automatically produce a detailed report including weapon, injuries, place and surroundings. All admins get a short notice the moment it happens.",
        } },
        roles = { title = "Roles", lines = {
            "Roles restrict admins, admin rights only come from the access level.",
            "Create a role, tick the allowed areas, assign it to a player below. Without an admin level a role only brings the coloured name above the head.",
            "Leave the roles area unticked and the admin cannot change any permissions, not even their own. The vanilla admin level always keeps role management.",
            "Server options and sandbox are areas of their own, the server page alone does not grant them.",
        } },
    },
    changelog = {
        { version = "2.5.1", date = "August 2026", sections = {
            { title = "New", points = {
                "Burnt out vehicles can be spawned now. They sit in the same list, marked as \"Burnt\".",
                "The death report now records which skills and recipes died with the character, including level and progress in percent.",
                "\"Reset kills\" grew into \"Reset statistics\": a picker decides which values are cleared, for one player or for everyone, plus a full wipe of the whole ledger.",
            } },
            { title = "Fixed", points = {
                "Timestamps in the records ran on universal time instead of the server clock and drifted hours off depending on the timezone.",
            } },
        } },
        { version = "2.5", date = "August 2026", sections = {
            { title = "New", points = {
                "A guided tour on first open: eight stops through the pages that matter. Skipping counts as seen, restart it any time from the help window.",
                "The question mark in the header explains the page you are on, pitfalls included.",
                "The manual is rewritten: tasks with steps instead of paragraphs, plus a search field. Outdated passages were checked against the code and corrected.",
                "Vehicles spawn as factory fresh, used or wrecked, and for the latter two every part rolls its condition on its own.",
                "The scheduled restart shuts the server down by itself where the server allows it, then nobody needs to be online.",
                "This window. It appears after an update, the checkbox below silences it until the next version.",
                "The icon bar folds with a click on the three dots, another click brings the icons back.",
            } },
            { title = "Fixed", points = {
                "Carry weight: entering 0 restores the game default. Small values used to pin a new limit instead of resetting.",
                "Godmode, invisible and noclip stay off when the sandbox wants them off. The off never reached the server before.",
                "In the player comparison, count and weight no longer hide under the scroll bar.",
                "Area clearing no longer leaves pebbles and ground details behind.",
                "An error trace on login on some servers is gone.",
                "The icon bar jumped back to its default spot after a restart instead of staying where you left it.",
            } },
            { title = "Changed", points = {
                "The admin tag switch now works for everyone, not just on your own screen.",
                "Area clearing removes player-built floors and borrows ground from a neighbour tile instead of leaving holes.",
                "The player comparison can be dragged by its header.",
                "The icon bar steps aside while the world map or the pause menu is open.",
            } },
        } },
        { version = "2.4.2", date = "August 2026", sections = {
            { title = "Fixed", points = {
                "Singleplayer: the golden icon shows up and F7 opens the panel as usual. Both were waiting for a rights answer from the server, and singleplayer has no server that could send one. Where nobody can answer, nothing waits anymore.",
                "The new icon dock could get buried under any window opened later: with the FactionsFramework factions window above it, clicks and the drag grip no longer got through. The dock now always stays on top, exactly like the panel's minimize bar always has.",
                "The topic list of the help window cut off entries at the bottom when the window was made small, with no hint and no way to reach them. It now carries its own draggable scrollbar, a click on the track pages through the list and the mouse wheel scrolls as everywhere else.",
                "In the help window the text could run underneath the right scrollbar, and the bar itself sat glued into the rounded window corner. It now sits further in, and the text ends hard before it and can no longer reach it.",
            } },
        } },
        { version = "2.4.1", date = "August 2026", sections = {
            { title = "Changed", points = {
                "The two Aegis icons moved out of the equipment bar into a small dock of their own, starting a bit left of the screen centre. Drag it anywhere by the three-dot grip on top, the spot is remembered. Inside the vanilla bar they kept fighting other icons for space, jumping around on hover or ending up wedged between foreign buttons depending on the mod set. That is over, the bar belongs to the game again.",
            } },
        } },
        { version = "2.4", date = "August 2026", sections = {
            { title = "New", points = {
                "The Factions page now has a real release button for a safehouse (main plus every annex at once, with confirmation). There used to be no way at all in the gold panel to release one. Where Knox Claim runs the server and owns the property, it is released there as well. Without that the zone came back on its own shortly after, because Knox rebuilt it from its own record. Should the Knox record survive anyway, the reply says so plainly instead of reporting success.",
                "The zones list is folded by owner now, exactly like the safehouse list on the Factions page. Clicking a name unfolds that owner's properties. Anyone holding a dozen properties used to push everybody else off the list.",
                "The build brush now has \"All tiles\": a window of tilesheets, searchable on the left, shown as a preview grid on the right. Both panes have a draggable scrollbar, and clicking the track pages up or down. Hover a tile and it appears enlarged beside the cursor along with its name: in the grid a tile is only 58 pixels across and many differ by a single detail. Where a tile carries a real 3D model, the preview shows that model instead of the flat image. Only a few do: in vanilla it is 45 tiles across five sheets, mostly doors and gates. Mods can add their own, and the check asks the tile itself rather than a fixed list. One click drops a tile into your own pieces and selects it right away. The curated palette stays alongside as the quick road. About expectations: the engine only hands out the game's complete tile list in debug mode, in a normal session it comes back empty. The window therefore shows the palette's own sheets plus everything actually standing in the world around you, and it re-reads that every time you open it. Stand somewhere else and you get different sheets.",
                "The logs page got a day picker. On a busy area you used to scroll through hundreds of entries to find a particular day.",
                "New sandbox option: automatic admin powers. Vanilla switches godmode, invisibility and noclip on by itself the moment someone becomes an admin. Turn it off and they stay off until you enable them yourself. The full heal that comes with the same promotion cannot be prevented, that part is engine internal.",
                "New sandbox option: track statistics for admins. Turn it off and kills, deaths, distance and best life stop being recorded for characters on an admin level, so admin testing does not skew the numbers.",
                "The players page now has a button that resets the kill statistics for one player or for everyone, with confirmation and a log entry. It was overdue, because skewed totals cannot be recalculated after the fact.",
                "Smashing windows and hotwiring vehicles now land in that player's own session file, with time and location, and a smashed window also names the vehicle it belonged to, with the translated vehicle name rather than a bare part number. Deliberately not a new log area: these are player activities and belong with the player.",
            } },
            { title = "Fixed", points = {
                "The scheduled restart depended on the planning admin still being online: while they were, only their own client answered the restart command, every other admin with full restart rights was refused. The server now sends the command to every authorized admin at once, no matter who planned it.",
                "A player with a custom rank like \"Priority\" could see the golden icon and open the panel, but it stayed empty inside because the server correctly refused every area. The cause was a naming mismatch (the vanilla level is called \"priority\", not \"priorityuser\") together with a safety net that assumed staff whenever the role list could not be read. The icon now waits for the server's confirmed answer before it shows up, which covers every misjudged rank, not just this one.",
                "BIG ONE, affects every server: putting things into vehicle containers went down a special path for ALL players, a path only meant for Aegis containers with an assigned capacity. The check behind it treated anyone whose access level was not empty as an admin, and in Build 42 every normal player carries the level \"user\". The results: trunks of some vehicle mods could no longer be filled by ordinary players, and every transfer into a vehicle took the slow road. That path now only triggers where an Aegis capacity was really assigned.",
                "On the same special path the transfer duration was invented instead of taken from vanilla: small things like bags or money took about a second each instead of almost no time, and the Dexterous bonus was dropped entirely. The duration is now calculated by vanilla's own formula, Dexterous and All Thumbs included.",
                "That special path no longer touches moves into a character's own inventory. Reloading a firearm moves every single round as an ordinary inventory transfer, and for anyone with an assigned carry weight their own inventory counted as an Aegis container, so those rounds could end up on the special path too. A round that failed to arrive left the gun part loaded, which is why six shots could need more than six reload motions.",
                "Some vehicles refused to accept anything even with an assigned capacity while the player stood right at the open trunk. The server measured distance to the vehicle's centre instead of the trunk itself, and on a long vehicle like a military truck the trunk sits several tiles behind that centre. The check now uses the same area vanilla itself relies on to decide whether a character can reach a vehicle part.",
                "On the same special path any refusal got overruled, including one from another mod. If Knox Claim also runs on the server and refuses a player permission to loot a claimed vehicle, an assigned Aegis capacity would have overridden that refusal. The special path now only steps in when vanilla itself was the one that said no.",
                "With some mod combinations the Aegis icon slid down to the bottom edge of the screen. It anchored itself to the lowest foreign icon it could find anywhere in the bar, even one sitting in a completely different group far below. It now only looks for its place inside the connected group directly above it, treating a large gap as the end of that group. Whatever gets skipped is written to the log once.",
                "Godmode, invisibility and noclip switched themselves back on even though the new sandbox option was supposed to keep them off. The option only acted at the exact moment a level change was noticed, and the engine does not always grant the three precisely then. The check now runs on every single rendered frame instead of only every couple of seconds, so no visible flicker gets through anymore. Anything you switch on yourself through the panel stays on: Aegis remembers your intent and does not argue with it. The full heal that comes with the promotion cannot be prevented regardless: it is tied to godmode itself and is already done before Aegis can react.",
                "Kill counts in the player area could climb far past anything believable (over 4000 for roughly 1000 real kills). Right after login the character on the server briefly reports zero kills, so the next comparison read an entire lifetime as fresh progress and added it on top all over again, once per login. A jump of more than 150 kills between two samples now counts as a login artifact and is not credited.",
                "On the sandbox page the text of the input fields ran underneath the scrollbar. The rows now account for its width.",
                "The sandbox page jumped back to the first category whenever the window was resized, discarding every change that had not been applied yet. Category, search text and edited values now survive.",
                "In the build brush the palette buttons were invisible, confirm and cancel included. The card they sit on was drawn after them and painted over them, they were clickable the whole time.",
                "With remembered vehicles per player set to 0, the remember button in the player panel is greyed out now. It used to stay clickable and the server refused every single press.",
            } },
        } },
        { version = "2.3.5", date = "August 2026", sections = {
            { title = "New", points = {
                "The number of remembered vehicles per player is a sandbox option now (Aegis Events, \"Remembered vehicles per player\"). It used to be a fixed five. 0 turns remembering off, the maximum is 20. Where Knox Claim runs, its own limit still counts. Lowering the value takes nothing away: vehicles already remembered stay, only new ones are refused.",
            } },
            { title = "Fixed", points = {
                "Percent signs in the texts brought in line with 42.20.1. The hotfix of August 5th changed how the symbol is handled in translation files, a displayed percent has to be written twice now. Four texts in all 13 languages were affected, among them \"Condition: 95%\" on the health page and the backup progress.",
                "The scheduled restart ran out: the timer counted down, the chat ended on \"Unknown command restart\" and the server stayed up. The rate at which the server repeated the order runs on game time and fired roughly every seven seconds on short days. That repeat always beat its own safety net, which should have sent the command that really exists eight seconds later. The server now waits real minutes between attempts, and a second attempt goes straight to the working command.",
            } },
        } },
        { version = "2.3.4", date = "August 2026", sections = {
            { title = "New", points = {
                "The safehouse page of the player panel now shows the way home (distance and heading, live) and offers the vanilla respawn-in-safehouse switch where the server allows it.",
                "On servers running Knox Claim the vehicles page of the player panel now lists the vehicles you registered there, 3D preview included. Distance, navi and condition bars appear once the car is loaded near you. Releasing still happens in the Knox Claim window, which is why the forget button stays off for those entries.",
            } },
            { title = "Fixed", points = {
                "The automatic restart could fizzle: the server cannot quit itself and hands the command to an authorized admin client, but it did so exactly ONCE. If nobody was ready to receive in that second, all the warnings ran and nothing happened (community report). The server now knocks again every minute until the restart really lands, gives up after ten minutes with a log entry, and both the handover and the execution are written to the log from now on.",
                "Remembered vehicles turned into empty husks after a server restart: no position, no bars, no navi. The ledger hung on the vehicle number, which the game hands out anew after every restart. Saving now attaches a fixed tag to the vehicle that server and panel always find it by, the number heals itself along the way. Entries from earlier versions without the tag stay husks, forgetting and re-saving once upgrades them.",
                "The 3D preview in the player panel was reworked: it starts fresh on every vehicle switch, cross fades without a flicker, and the vehicle sits lower and better in the frame. Zoom and shift-drag apply to the selected vehicle and reset on a switch. Some modded vehicles are built off centre around their model origin and therefore sit off centre in EVERY preview the game has, only panning by hand helps there.",
                "The way home on the safehouse page is golden and clickable now: one click points the screen arrow at your home, a second turns it off.",
                "The button under the vehicle list is called Release everywhere now: a remembered vehicle leaves the list, a Knox Claim vehicle is truly released. And arriving at home no longer greets you with vehicle found.",
                "Respawning in the safehouse placed you next to the house instead of inside: the game swaps width and height of the zone when computing the spot, which lands outside on elongated zones. Aegis computes the spot correctly itself now.",
                "Vehicles from Knox Claim lost distance, heading, the condition bars and the part list after a relog. They were matched by the vehicle's net number, and the game hands out new ones after every restart. They are now found by the claim tag on the vehicle itself.",
                "Aegis tried to set a capacity on the body inventory twice a second whenever a carry weight was assigned. That filled the server log with warnings and did nothing. The body is served through the proper path only now.",
                "Assigned storage capacity only worked up to 100 for ordinary players even though the panel showed the full value (community report). On crates it was easy to miss because their default sits below that, on counter tops and floating cabinets nothing worked at all since they already sit at the limit. The game clamps world containers hard when reading them, and the check while moving items bypasses our own value. Until now only admins had the detour through the server, now everyone takes it as soon as the container has an assigned capacity. The server still checks range, item and exactly that value.",
                "Restart at a fixed time and the automatic anchor calculated in world time instead of your local time: entering 00:11 got you a restart at 02:11. Input and display now run on your local clock.",
                "Help and changelog kept the old line wrap when the window was shrunk and the text vanished under the scrollbar on the right. The wrap now checks before every draw that it still matches the window width.",
                "The mod filter in the item catalog is always visible now. Without any item mods installed it hid itself and left a hole in the filter row that looked like something broke. It simply reads Project Zomboid then.",
                "The hint text on the empty vehicles page was wider than the column and cut off at the front.",
                "The remember button for vehicles did not disappear on servers running Knox Claim after all. The server sent the flag correctly, but the player panel rebuilds its state field by field and did not know the new field, so it was dropped on arrival without a word. From 2.3.3, fixed right away.",
                "The fixed powered by Aegis line in the footer is gone, in both panels. It only took up space there.",
            } },
        } },
        { version = "2.3.3", date = "August 2026", sections = {
            { title = "New", points = {
                "Filter items by source mod (community request): next to the category filter you can now pick a mod, and mod items show in small print behind the name where they come from. The search finds mod names too. Without mods the filter stays hidden.",
                "Plays along with Knox Claim: where that mod runs on the server, it owns the vehicles. Aegis then pulls its own remember button in the player panel, so two lists are not kept side by side with each one knowing only its half. The forget button stays so older entries can still be removed. Without Knox Claim nothing changes.",
            } },
            { title = "Fixed", points = {
                "PERMISSION HOLE: on servers with custom rank roles (head tags like \"Veteran\") everyone holding such a role counted as staff and got the full panel, without the admin tool and without an assigned Aegis role. Aegis treated any named access level as staff when in doubt, and since an Aegis role only narrows access and never grants it, that meant full access, enforced server side as well. Only a role that provably carries the admin tool counts now. The four vanilla levels admin, moderator, gm and observer still get in regardless of the role registry, and if the registry cannot be read at all the old way out remains so no real admin locks themselves out. Every verdict is now written to the server log with its reason.",
                "Setting a carry weight also dragged the hard pickup cap onto the same value. The game keeps two limits apart: past your carry weight you are overencumbered, and only at the hard cap (fixed at 50) does it refuse picking up entirely. Anyone given a small carry weight could not pick up anything once at the limit, and the value came back after death through the stored list. Below 50 normal overloading works again, only larger values keep raising the hard cap. Affected characters are cleaned up on their next login by themselves.",
                "The need sliders in the values window now take effect while you drag instead of only when you let go. The value travels to the server four times a second without raising a notice per step, and the log still records only the value you release on.",
                "The safehouse card in the player panel stayed empty although the zone was listed on the zone page of the admin panel. It read the list on the player's own machine, and a zone created on the server does not have to be in that copy. It now asks the server, the way the zone page always has, and keeps itself up to date while the page is open.",
            } },
        } },
        { version = "2.3.2", date = "August 2026", sections = {
            { title = "New", points = {
                "Set needs freely (community request): in the values window the new button at the top right opens sliders for hunger, thirst, fatigue, endurance, stress, panic, boredom, unhappiness, pain, sickness, intoxication and wetness. The panel could only reset all of them at once before, now you set each one individually, upwards as well. The bounds come from the game itself and the value is only sent when you let go of the slider.",
                "The help now explains step by step under Roles how to give someone limited admin access.",
            } },
            { title = "Fixed", points = {
                "PERMISSION HOLE: anyone on a vanilla level that carries the admin tool, which includes observer, gm and moderator, could always open the roles page and grant themselves every area. The lockout protection now keys on the vanilla RolesWrite capability, which only the admin level has. A real admin still cannot lock themselves out, everyone else needs the roles area granted explicitly in their Aegis role.",
                "The Organized trait stopped working in every container an admin had ever given a capacity to. The game adds that bonus on top of the capacity, and our own value swallowed it, so affected players could not store anything once the plain capacity without the bonus was reached. Organized and Disorganized now apply to assigned values as well.",
                "The scroll bar of the overview sat on top of the resize grip in the bottom right corner and could not be grabbed once the window was small enough to scroll.",
            } },
        } },
        { version = "2.3.1", date = "August 2026", sections = {
            { title = "Fixed", points = {
                "The golden button and the blue player button were missing entirely with some mod combinations. Aegis places itself below every other icon in the equipped item bar, but it also measured elements that are not icons at all and slid off the bottom of the screen. Only icon sized neighbours count now, and the button always stays visible.",
                "A mod that takes over the equipped item bar can no longer make the Aegis buttons disappear. If they are missing, they are put back.",
                "Errors from other mods in the inventory are no longer reported as Aegis errors. Aegis no longer hooks into the vanilla backpack bar for that.",
                "Aegis no longer writes diagnostic lines to the log when a bag is too full.",
            } },
        } },
        { version = "2.3", date = "July 2026", sections = {
            { title = "New", points = {
                "Hide pages: with the padlock at the bottom of the sidebar open, every entry shows an eye. Hide what you never use, the plus next to it brings pages back. Applies only to you and changes no rights.",
                "The overview is a board now: the edit button at the top right enters rearrange mode, cards can be dragged, removed and added from the catalog. Every admin keeps their own layout, and without touching it everything looks as before.",
                "The catalog reaches across every area you have access to: next to online players and the feature switches you can drop in a tile for any page, from world through tools and zones to the server options. One click on it takes you there.",
                "New Time and weather card: morning, noon, evening and midnight right on the overview, plus the button that ends a running weather event.",
                "Rearrange mode has a Restore the default button next to the edit button. It rebuilds the overview the way it looked the first time you opened it.",
                "New Server Options page: every server INI setting searchable and editable right in the panel, with markers for what only takes effect after a restart. Changes apply live and are written to the INI right away. Mods and workshop items are locked and can only be edited after a double warning, at your own risk.",
                "Your server name instead of AEGIS: set it on the server page, both panels show it to every player, with powered by Aegis fixed underneath. Leave it empty to get AEGIS back.",
                "New switch card on the server page: player area, player claims and player kits can be turned on and off there and in the sandbox, live and for everyone. The server enforces it, not just the display.",
                "Kits with no role attached can now really be claimed by everyone. Players without a role never reached the kits page before, which made the role feel mandatory.",
                "New crafting cheat next to the build cheat: recipes craftable without materials, skills or a workstation. If you also want unknown recipes in the list, turn on Know all recipes as well, the two switches are independent. The build cheat stays as it was.",
                "The player area shows time and date only with a worn watch: any watch brings the time, only a digital one adds the date.",
                "Server options became an area of its own in the roles: you can hand an admin the server page and still keep the INI settings from them. Existing roles keep their access, there is nothing to add by hand.",
                "Adding a trait in the values window now explains on hover what the trait does, along with its points and the reason when the row is red.",
            } },
            { title = "Fixed", points = {
                "Vehicle values in the player area are live: refuelling and repairing next to the car shows up right away, not half a minute later.",
                "Server branding now sits to the right of the feature switches instead of below them, that side of the page was empty.",
                "The value column of the server options no longer runs into the scroll bar.",
                "With many pages on a short window the sidebar no longer runs across the footer. If the list still does not fit after packing, the wheel scrolls it.",
            } },
        } },
        { version = "2.2", date = "July 2026", sections = {
            { title = "New", points = {
                "Player values are now an Aegis window instead of the vanilla one. It replaces the old Player stats screen behind the same button on the players page, and it can be moved and resized like every other Aegis window.",
                "Everything in it changes live. Traits, profession, names, weight, skill levels and experience take effect right away on the target, no reconnect needed. The vanilla screen edited your own copy of that player, which could roll back skills they had learned since joining.",
                "Skills come with level, experience and the boost the character really gets, and you can grant experience, raise or lower a level, or set one outright.",
                "Every trait sits in its own small box with a cross, one click removes it. When adding one, the list marks in red what collides with a trait the player already has.",
                "Names cover forename, surname and the display name, with a way back to the automatic one. A weight trait pulls the weight along with it, otherwise the server would undo the change within minutes.",
            } },
            { title = "Fixed", points = {
                "Furniture from the build brush can be cleared again. It used to be placed in a way that made the engine refuse to remove it, so neither clearing nor the sledgehammer worked on it.",
                "A floor placed with the build brush can be cleared too. Map floors stay protected, removing those would tear holes into the world.",
                "Saving role rights no longer reports an error when a member of that role is offline.",
                "Scrolling a card no longer leaves old rows standing behind the controls.",
            } },
        } },
        { version = "2.1", date = "July 2026", points = {
            "Reset kit claims: a button on the selected kit drops every claim on it and shows how many players are affected. Those players can collect the kit again right away, no server restart.",
            "The clock symbol in the editor header opens the list of players holding a claim, with the time they claimed it. From there you reset individual players when only one of them needs their kit.",
            "At the bottom of that list, set apart, sits Wipe all claims. It removes the claims on every kit for every player and asks for a typed reason, which goes into the log.",
            "It exists for starting over with a fresh world: claims live apart from the world save and therefore survive a reset. Otherwise every kit still counts as collected and nobody gets theirs.",
            "If the claim list could not be read completely, every reset stays greyed out, so a partial list never gets wiped.",
            "Follow runs smoothly now: you glide along with your target and keep a fixed distance behind it, instead of standing still for a moment and then lurching forward.",
            "While following, the camera stays on the right floor, stairs used to throw it off by a whole storey. On the ground floor you no longer hover just above the ground either.",
            "Confirmation windows now fit their text: they grow wider and long sentences wrap properly. In some languages half the sentence used to sit unreadable on the darkened background.",
        } },
        { version = "2.0", date = "July 2026", points = {
            "Plays nice with other sidebar mods: Aegis spots foreign buttons and lines up below them instead of covering them. Faction Framework keeps its spot.",
            "Factions from Faction Framework now show up in the list, marked with FF. Aegis cannot edit them, that mod handles them itself.",
            "Player area can be switched off: a toggle in the sandbox settings under Aegis Events hides the blue panel server wide. The admin panel is untouched.",
            "Zones rebuilt: editing bounds now attaches rectangle after rectangle, the editor stays open and everything becomes ONE zone. Painting is still there for single tiles.",
            "Zones merge: two zones of the same owner become one on the next edit as soon as they touch. Attached areas have to connect, loose pieces are refused right away.",
            "Zones run smoother: outlines as long lines instead of tile borders, unchanged parts stay put during a rebuild, stale rectangles are cleaned up by the client itself.",
            "Kits can be tied to roles: only the donator sees the donator kit, enforced on the server. New monthly mode next to once and cooldown.",
            "Discord boosters (optional, needs your OWN Discord bot): the bot hands out a code, the player redeems it, the status runs until the end of the month. Without a key set the section stays hidden. No bot is provided, the code recipe is available on request.",
            "Head tag now belongs to the role and can be switched on or off there at any time, the change applies to every wearer instantly.",
            "Safehouse list on the factions page groups per player instead of one long list of every rectangle.",
            "Death reports: every player death fully documented (attacker, weapon, wounds, surroundings), new deaths area in the log.",
            "Follow: pin the camera to a player at any distance.",
            "Window freely resizable, size remembered, content follows the drag. Pages scroll when the window gets too small.",
            "Page order changeable by dragging, with a padlock in the sidebar. Minimize turns into a small movable bar.",
            "Translucent preview before restoring demolished builds, its card is draggable.",
            "Range lock on player actions removed, almost everything works at any distance.",
            "Rights: whoever gets an area assigned may do everything in it. Roles without admin status no longer grant admin rights.",
            "The cart survives a window resize, entries can be removed with a click.",
            "Help and changelog inside the panel.",
            "New for your players: the player area, a blue panel of their own for everyone on the server. Roles hand out kit access and claim tiles. What it does is listed in that panel's changelog.",
            "Fixed a crash that broke the server handler when picking up or scrapping furniture. Tested on 42.20.",
            "Various fixes, among them time setting and the rights check.",
        } },
        { version = "1.1", date = "July 2026", points = {
            "Vehicle detail window with fuel, keys, parts, color and condition.",
            "Vehicle teleport including trailer and cargo.",
            "Sprite inspector and build brush with custom palette.",
            "Build log with restore, stairs and garage doors included.",
            "Carry weight and container capacity up to 1000, full heal cures bites.",
            "Admin tag manually switchable, role assignment with name tag in role color.",
            "FactionFramework compatibility.",
        } },
        { version = "1.0", date = "July 2026", points = {
            "First release: powers, overview, players, items, vehicles, world, zones, horde, server, sandbox, log, roles, animals, factions, tools.",
        } },
    },
}

-- player mode: the manual of the blue player panel, written strictly from
-- the player's point of view, changelog only with player visible points

AegisHelpContent.PLAYER_DE = {
    help = {
        { title = "\195\156bersicht", lines = {
            "Das blaue Panel ist dein pers\195\182nlicher Bereich auf dem Server; jeder hat es automatisch, vom neuen Spieler bis zum Admin.",
            "\195\150ffnen: den blauen Knopf in der kleinen Knopf-Leiste oben anklicken, standardm\195\164\195\159ig etwas links der Bildschirmmitte.",
            "Startseite lesen: dein Charakter dreht sich in 3D, daneben stehen deine wichtigsten Werte und deine Lieblingswaffe.",
            "Extras wie Zonen-Claim oder Kits h\195\164ngen von deiner Rolle ab; fehlt ein Bereich, ist er f\195\188r dich nicht freigeschaltet.",
        } },
        { title = "Statistiken und Bestenliste", lines = {
            "Die Statistik-Seite sammelt deine Laufbahn auf dem Server.",
            "Werte lesen: Tode, get\195\182tete Zombies und Banditen, gelaufene Kilometer, dein l\195\164ngstes Leben und die gesamte Spielzeit.",
            "Vergleichen: darunter steht die Server-Bestenliste, dein eigener Eintrag ist farbig hervorgehoben.",
            "Kilometer, Tode und Banditen-Kills z\195\164hlen ab Einbau des Panels; die Spielzeit wird r\195\188ckwirkend aus den Sitzungs-Protokollen berechnet.",
        } },
        { title = "Gesundheit", lines = {
            "Die Gesundheits-Ansicht zeigt deinen Zustand auf einen Blick.",
            "Zustand pr\195\188fen: die Seite listet Verletzungen je K\195\182rperteil, Blutungen und alles, was gerade versorgt werden will.",
            "Verbinden: direkt auf dieser Seite, ohne das normale Gesundheits-Fenster; passendes Verbandsmaterial muss im Gep\195\164ck sein.",
            "So erkennst du fr\195\188h, wo es brennt, bevor aus einem Kratzer ein echtes Problem wird.",
        } },
        { title = "Safehouse", lines = {
            "Die Safehouse-Seite zeigt dein Zuhause.",
            "\195\156berblicken: Lage, Gr\195\182\195\159e und wer dazugeh\195\182rt stehen auf einen Blick da.",
            "Verfall abwenden: droht dein Safehouse zu verfallen, warnt das Panel rechtzeitig; nach l\195\164ngerer Pause lohnt hier der erste Blick.",
        } },
        { title = "Eigene Fahrzeuge", lines = {
            "Die Fahrzeug-Seite listet deine eigenen Fahrzeuge mit Zustand und Standort.",
            "Zustand pr\195\188fen: unter der 3D-Vorschau zeigen Zustandsbalken, wie gut dein Wagen noch beieinander ist.",
            "Wagen wiederfinden: das Navi markiert das gew\195\164hlte Fahrzeug in der Welt, praktisch nach einer wilden Flucht.",
            "Das Navi l\195\164uft nebenher und blockiert nichts; k\195\164mpfen, looten und bauen gehen normal weiter.",
        } },
        { title = "Zonen-Claim", lines = {
            "Mit dem Zonen-Claim sicherst du dir gesch\195\188tztes Land direkt an deinem Haus, ganz ohne Admin.",
            "Budget pr\195\188fen: wie viele Kacheln du beanspruchen darfst, legt deine Rolle fest, ohne Rolle sind es keine; das Panel zeigt Budget und Verbrauch.",
            "Claim setzen: bei deinem Haus stehen und den Claim anlegen; innerhalb der Zone gelten danach die Schutzregeln des Servers.",
        } },
        { title = "Kits abholen", lines = {
            "Kits sind fertig gepackte Pakete der Admins, etwa ein Starter-Paket oder Event-Belohnungen.",
            "Abholen: jede Karte zeigt den Inhalt und ob das Kit einmalig oder mit Abklingzeit verf\195\188gbar ist; Abholen legt alles direkt in dein Inventar.",
            "Einmalige Kits bleiben abgeholt, auch nach Tod und Wiedereinstieg.",
        } },
        { title = "Notruf", lines = {
            "Der Notruf erreicht alle Admins, die gerade online sind.",
            "Hilfe rufen: kurz beschreiben, was passiert ist; die Admins sehen Name, Position und Nachricht und k\195\182nnen direkt zu dir kommen.",
            "Nach einem Notruf gilt eine kurze Sperre gegen Spam; gedacht ist er f\195\188r echte Probleme wie Griefer, nicht f\195\188r Wunschlisten.",
        } },
        { title = "Fenster und Bedienung", lines = {
            "Fenster, Gr\195\182\195\159e und Reihenfolge richtest du dir frei ein.",
            "Verschieben und schlie\195\159en: das Panel am Kopfbereich ziehen; der blaue Knopf \195\182ffnet und schlie\195\159t es, das X im Fenster ebenso.",
            "Gr\195\182\195\159e \195\164ndern: wo unten rechts ein Punkte-Dreieck sitzt, ziehst du das Fenster auf jede gew\195\188nschte Gr\195\182\195\159e.",
            "Seitenleiste ordnen: das Schloss unten \195\182ffnen, Eintr\195\164ge mit gedr\195\188ckter Maustaste ziehen, die blaue Linie zeigt die Einf\195\188gestelle, dann wieder schlie\195\159en.",
            "Auch das Hilfe-Fenster l\195\164sst sich am Kopf verschieben und an der Punkte-Ecke skalieren; die Gr\195\182\195\159e bleibt gespeichert.",
        } },
    },
    tour = {
        { page = "me", title = "\195\156bersicht", text = "Deine Startseite: dein Charakter in 3D, deine Werte und deine Lieblingswaffe auf einen Blick." },
        { page = "stats", title = "Statistiken", text = "Deine Zahlen und die Bestenliste des Servers: Kills, Tode, gelaufene Strecke und dein l\195\164ngstes Leben." },
        { page = "sos", title = "Notruf", text = "Ein Ruf an das Team, wenn du feststeckst oder Hilfe brauchst. Er erreicht jeden Admin, der gerade online ist." },
        { page = "kits", title = "Kits", text = "Pakete, die der Server f\195\188r dich freigegeben hat. Manche gibt es einmalig, andere in festen Abst\195\164nden." },
    },
    pagehelp = {
        me = { title = "\195\156bersicht", lines = {
            "Deine Startseite: dein Charakter als drehbare 3D-Figur, daneben deine wichtigsten Werte und deine Lieblingswaffe.",
            "Das Panel hat jeder auf dem Server automatisch.",
            "Extras wie Zonen-Claim oder Kits h\195\164ngen von deiner Rolle ab: fehlt ein Bereich, ist er f\195\188r deine Rolle nicht freigeschaltet.",
        } },
        stats = { title = "Statistiken", lines = {
            "Deine Laufbahn in Zahlen: Tode, get\195\182tete Zombies und Banditen, gelaufene Kilometer, dein l\195\164ngstes Leben und die Spielzeit.",
            "Darunter die Server-Bestenliste, dein eigener Eintrag ist farbig hervorgehoben.",
            "Kilometer, Tode und Banditen-Kills z\195\164hlen ab dem Einbau des Panels auf dem Server, die Spielzeit wird auch r\195\188ckwirkend berechnet.",
        } },
        health = { title = "Gesundheit", lines = {
            "Dein Zustand auf einen Blick: Verletzungen je K\195\182rperteil, Blutungen und alles, was versorgt werden will.",
            "Verbinden geht direkt auf dieser Seite, passendes Verbandsmaterial im Gep\195\164ck vorausgesetzt.",
            "So erkennst du fr\195\188h, wo es brennt, bevor aus einem Kratzer ein echtes Problem wird.",
        } },
        safehouse = { title = "Safehouse", lines = {
            "Dein Zuhause im \195\156berblick: Lage, Gr\195\182\195\159e und wer dazugeh\195\182rt.",
            "Droht dein Safehouse zu verfallen, warnt dich das Panel rechtzeitig.",
            "Nach einer l\195\164ngeren Pause lohnt hier der erste Blick.",
        } },
        vehicles = { title = "Fahrzeuge", lines = {
            "Deine eigenen Fahrzeuge mit Zustand und Standort, unter der 3D-Vorschau zeigen Balken den Zustand.",
            "Das Navi markiert das gew\195\164hlte Fahrzeug, damit du es in der Welt wiederfindest.",
            "Das Navi l\195\164uft nebenher und blockiert nichts: k\195\164mpfen, looten und bauen gehen normal weiter.",
        } },
        claim = { title = "Zone", lines = {
            "Dein eigenes St\195\188ck gesch\195\188tztes Land direkt an deinem Haus, ganz ohne Admin.",
            "Wie viele Kacheln du beanspruchen darfst, legt deine Rolle fest, ohne Rolle sind es keine.",
            "Zum Setzen musst du bei deinem Haus stehen, die Fl\195\164che muss anschlie\195\159en und darf nichts \195\188berlappen.",
            "Innerhalb deiner Zone gelten die Schutzregeln des Servers.",
        } },
        kits = { title = "Kits", lines = {
            "Fertig gepackte Pakete der Admins, etwa ein Starter-Paket oder Event-Belohnungen.",
            "Jede Karte zeigt, was drin ist und ob das Kit einmalig oder mit Abklingzeit verf\195\188gbar ist. Abholen legt den Inhalt in dein Inventar.",
            "Einmalige Kits bleiben abgeholt, auch nach Tod und Wiedereinstieg.",
            "Du siehst nur die Kits, die f\195\188r deine Rolle freigeschaltet sind.",
        } },
        sos = { title = "Notruf", lines = {
            "Dein Ruf an das Team: er erreicht alle Admins, die gerade online sind, mit Name, Position und Nachricht.",
            "Beschreibe kurz, was passiert ist, dann k\195\182nnen die Admins direkt zu dir kommen.",
            "Nach einem Notruf gilt eine kurze Sperre gegen Spam.",
            "Gedacht f\195\188r echte Probleme wie Griefer oder festgefahrene Situationen, nicht f\195\188r Wunschlisten.",
        } },
    },
    changelog = {
        { version = "1.4", date = "August 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Ein kurzer Rundgang beim ersten \195\150ffnen: \195\156bersicht, Statistiken, Notruf und Kits.",
                "Das Fragezeichen im Fensterkopf erkl\195\164rt die aktuelle Seite.",
                "Das Handbuch ist neu geschrieben und durchsuchbar.",
                "Dieses Fenster. Es erscheint nach einem Update, das H\195\164kchen unten h\195\164lt es bis zur n\195\164chsten Version still.",
            } },
            { title = "Ge\195\164ndert", points = {
                "Kopftags von Rollen wie VIP oder Survivor sind jetzt f\195\188r alle sichtbar, ganz ohne Adminkr\195\164fte.",
            } },
        } },
        { version = "1.3", date = "August 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Ob dir die Gesundheitsseite offen sagt, dass du die echte Zombie-Infektion tr\195\164gst, entscheidet jetzt der Server \195\188ber eine Sandbox-Option. Vanilla l\195\164sst das absichtlich im Dunkeln, Server die diese Ungewissheit erhalten wollen, k\195\182nnen die Anzeige abschalten. Wundinfektion und alle anderen Verletzungen siehst du weiterhin.",
                "Der Server kann die Statistik-Aufzeichnung f\195\188r Charaktere auf einer Admin-Stufe abschalten, damit Admin-Tests die Bestenlisten nicht verf\195\164lschen.",
            } },
            { title = "Behoben", points = {
                "Die Fahrzeuge-Seite konnte den Server zum Absturz bringen. Beim Aufl\195\182sen eines gemerkten Fahrzeugs \195\188ber seine Kennung griff der Server auf eine Fahrzeug-Verwaltung zu, die in seltenen Momenten noch nicht bereit war, und das riss die ganze Anfrage ab. Die Seite blieb dann leer oder h\195\164ngen. Der Server pr\195\188ft das jetzt vorher ab.",
                "Nach dem Tod lief die Gesundheitsseite in eine Endlos-Fehlermeldung: sie suchte alle halbe Sekunde nach Verband und Desinfektion und fragte dabei eine Vanilla-Funktion, die ein offenes Inventarfenster voraussetzt. Beim toten Charakter gibt es das nicht, die Suche fiel also bis zum Wiedereinstieg dauernd auf die Nase. Die Seite l\195\164sst das Suchen beim toten Charakter jetzt einfach sein, zu verbinden gibt es da ohnehin nichts.",
                "Die Zahl der get\195\182teten Zombies konnte viel zu hoch stehen. Jeder R\195\188ckgang des Spielz\195\164hlers galt als neues Leben und wurde noch einmal aufaddiert, auch wenn ein anderer Mod denselben Z\195\164hler mitten im Leben zur\195\188cksetzte. Ein R\195\188ckgang wird jetzt nur noch dann angerechnet, wenn wirklich ein Tod verzeichnet wurde. Bereits verf\195\164lschte Zahlen bleiben stehen, sie lassen sich nicht nachtr\195\164glich auseinanderrechnen.",
            } },
        } },
        { version = "1.2.1", date = "August 2026", sections = {
            { title = "Behoben", points = {
                "Deine Safehouse-Karte blieb leer, obwohl du ein Grundst\195\188ck hattest. Sie hat die Zonen auf deinem eigenen Rechner nachgeschlagen, und eine Zone, die auf dem Server entsteht, muss dort nicht ankommen. Sie fragt jetzt den Server und zieht bei offener Seite von selbst nach.",
                "L\195\164uft auf dem Server der Mod Knox Claim, verwaltet der die Fahrzeuge. Der Knopf zum Merken eines Fahrzeugs verschwindet dann hier, damit du deine Wagen nicht an zwei Stellen pflegen musst. Der Knopf zum Vergessen bleibt, damit du alte Eintr\195\164ge loswirst.",
            } },
        } },
        { version = "1.2", date = "Juli 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Seiten ausblenden: das Schloss unten in der Leiste zeigt im offenen Zustand ein Auge an jedem Eintrag. Was dich nicht interessiert, blendest du aus, das Plus daneben holt es zur\195\188ck.",
                "Kits zeigen ihre Herkunft: hinter dem Namen steht klein, \195\188ber welche Rolle oder den Booster-Status du das Kit bekommst. Offene Kits tragen nichts, die geh\195\182ren allen.",
            } },
        } },
        { version = "1.1", date = "Juli 2026", sections = {
            { title = "Neu hinzugef\195\188gt", points = {
                "Die Admins k\195\182nnen deinen Anspruch auf ein Kit zur\195\188cksetzen, meist beim Start einer frischen Welt. Danach holst du auch ein einmaliges Kit erneut ab. Ob und wann, entscheiden sie.",
            } },
            { title = "Behoben", points = {
                "Best\195\164tigungsfenster passen sich dem Text an: lange Hinweise brechen sauber um, statt rechts hinauszulaufen. Betroffen sind der Zonen-Anspruch und die Fahrzeug-Seite.",
            } },
        } },
        { version = "1.0", date = "Juli 2026", points = {
            "Taste F6 \195\182ffnet und schlie\195\159t den Spielerbereich, der blaue Knopf unten links geht nat\195\188rlich weiter. Die Taste kannst du in den Mod-Einstellungen umlegen.",
            "Neu: dieser Spielerbereich. Ein eigenes Panel f\195\188r dich mit Charakter in 3D, Werten und Lieblingswaffe, f\195\188r jeden auf dem Server.",
            "Statistiken mit Server-Bestenliste: Tode, Zombie- und Banditen-Kills, Kilometer, l\195\164ngstes Leben, Spielzeit.",
            "Gesundheits-Ansicht mit allen Verletzungen auf einen Blick, Verbinden und Desinfizieren direkt hier. Die Figur w\195\164chst mit der Fenstergr\195\182\195\159e mit.",
            "Safehouse-Ansicht mit Warnung vor dem Verfall.",
            "Fahrzeuge: deine Autos mit 3D-Vorschau, Navi-Pfeil zum verlorenen Wagen und jedem Teil nach Kategorie. Ein platter Reifen steht als platt da.",
            "Eigener Zonen-Anspruch am Haus, Umfang je nach Rolle. Er muss am eigenen Haus anschlie\195\159en und darf nichts \195\188berlappen.",
            "Kits zum Abholen, einmalig oder mit Abklingzeit. Du siehst nur die, die f\195\188r deine Rolle freigeschaltet sind.",
            "Discord-Booster: falls dein Server das anbietet, holst du den Code in Discord und l\195\182st ihn unten auf der Kits-Seite ein.",
            "Notruf an alle Admins, die gerade online sind.",
            "Fenster frei verschieb- und skalierbar, Seiten sortierbar, Hilfe-Fenster direkt im Panel.",
        } },
    },
}

AegisHelpContent.PLAYER_EN = {
    help = {
        { title = "Overview", lines = {
            "The blue panel is your personal area on the server; everyone gets it automatically, from fresh survivor to admin.",
            "Open it: click the blue button in the small floating bar at the top of the screen, or press F6.",
            "Check yourself: the start page shows your character in 3D, your key vitals and your favourite weapon.",
            "Missing a page like zone claim or kits? Then it is not enabled for your role on this server.",
        } },
        { title = "Statistics and leaderboard", lines = {
            "The statistics page keeps your career on this server.",
            "Track yourself: deaths, zombies and bandits killed, kilometres walked, longest life and total playtime.",
            "Compare: the server leaderboard sits below, your own row is highlighted.",
            "Kilometres, deaths and bandit kills count from the day the panel arrived; playtime is calculated back from the session logs.",
        } },
        { title = "Health", lines = {
            "The health view shows your condition at a glance: injuries per body part, bleeding, everything needing care.",
            "Treat wounds: bandage right on this page, no detour through the normal health window; you still need bandage material in your bags.",
            "Check in early: spot trouble before a scratch becomes a real problem.",
        } },
        { title = "Safehouse", lines = {
            "The safehouse page keeps an eye on your home.",
            "Check it: location, size and who belongs to it are listed here.",
            "Watch the expiry: the panel warns you in time before the safehouse decays; after a longer break look here first.",
        } },
        { title = "Own vehicles", lines = {
            "The vehicle page lists your own vehicles with condition and location.",
            "Judge the state: the condition bars under the 3D preview show how well the car holds together.",
            "Find it again: the nav marks the selected vehicle in the world, handy after a wild escape.",
            "Keep playing: the nav runs alongside and blocks nothing, fighting, looting and building continue as normal.",
        } },
        { title = "Zone claim", lines = {
            "The zone claim secures a protected piece of land at your house, no admin needed.",
            "Check your budget: how many tiles you may claim comes from your role, none without one; the panel shows used and free tiles.",
            "Place it: stand at your house, then claim; inside the zone the server protection rules apply.",
        } },
        { title = "Collecting kits", lines = {
            "Kits are ready packed packages from the admins, a starter package or event rewards for example.",
            "Collect one: every card shows the content and whether it is one time, on a cooldown or monthly; Claim puts everything straight into your inventory.",
            "One time kits stay collected, dying and rejoining change nothing.",
        } },
        { title = "Distress call", lines = {
            "The distress call is your line to the admins.",
            "Send one: describe briefly what happened; every admin online gets your name, position and message and can come straight to you.",
            "Use it for real trouble, griefers or stuck situations, not for wish lists; a short cooldown follows every call.",
        } },
        { title = "Window and controls", lines = {
            "The panel adapts to you and remembers everything.",
            "Move it: drag the window by its header anywhere on the screen; the blue button and the X both close it.",
            "Resize it: drag the small dot triangle in the bottom right wherever one sits, this help window included; sizes are kept.",
            "Reorder the sidebar: open the small padlock at the bottom, drag entries to a new spot along the blue line, close the padlock again.",
        } },
    },
    tour = {
        { page = "me", title = "Overview", text = "Your start page: your character in 3D, your values and your favourite weapon at a glance." },
        { page = "stats", title = "Statistics", text = "Your numbers and the server leaderboard: kills, deaths, distance walked and your longest life." },
        { page = "sos", title = "SOS", text = "A call to the staff when you are stuck or need help. It reaches every admin who is online right now." },
        { page = "kits", title = "Kits", text = "Packages the server has released for you. Some are one time only, others come back on a schedule." },
    },
    pagehelp = {
        me = { title = "Overview", lines = {
            "Your start page: your character as a rotatable 3D figure, next to it your most important vitals and your favourite weapon.",
            "Everyone on the server has the panel automatically.",
            "Extras like the zone claim or kits depend on your role: if an area is missing, it is not enabled for your role.",
        } },
        stats = { title = "Statistics", lines = {
            "Your career in numbers: deaths, zombies and bandits killed, kilometres walked, your longest life and total playtime.",
            "Below it the server leaderboard, your own entry is highlighted.",
            "Kilometres, deaths and bandit kills count from the moment the panel was installed on the server, playtime is also calculated retroactively.",
        } },
        health = { title = "Health", lines = {
            "Your condition at a glance: injuries per body part, bleeding and everything that wants treatment.",
            "Bandaging works right on this page, suitable bandage material in your bags provided.",
            "That way you spot trouble early, before a scratch turns into a real problem.",
        } },
        safehouse = { title = "Safehouse", lines = {
            "Your home at a glance: location, size and who belongs to it.",
            "If your safehouse is about to expire, the panel warns you in time.",
            "After a longer break this is the first place to look.",
        } },
        vehicles = { title = "Vehicles", lines = {
            "Your own vehicles with condition and location, bars under the 3D preview show the condition.",
            "The nav marks the selected vehicle so you can find it in the world again.",
            "The nav runs alongside and blocks nothing: fighting, looting and building continue as normal.",
        } },
        claim = { title = "Claim", lines = {
            "Your own protected piece of land right at your house, no admin needed.",
            "How many tiles you may claim is set by your role, without a role there are none.",
            "You need to stand at your house to place it, the area has to connect and may not overlap anything.",
            "Inside your zone the server's protection rules apply.",
        } },
        kits = { title = "Kits", lines = {
            "Ready made packages from the admins, a starter package or event rewards for example.",
            "Every card shows what is inside and whether the kit is one time or on a cooldown. Collect puts the content into your inventory.",
            "One time kits stay collected, even after dying and rejoining.",
            "You only see the kits unlocked for your role.",
        } },
        sos = { title = "SOS", lines = {
            "Your call to the staff: it reaches every admin currently online with your name, position and message.",
            "Describe briefly what happened, then the admins can come straight to you.",
            "After a call a short cooldown prevents spam.",
            "Meant for real problems like griefers or stuck situations, not for wish lists.",
        } },
    },
    changelog = {
        { version = "1.4", date = "August 2026", sections = {
            { title = "New", points = {
                "A short tour on first open: overview, statistics, SOS and kits.",
                "The question mark in the header explains the current page.",
                "The manual is rewritten and searchable.",
                "This window. It appears after an update, the checkbox below silences it until the next version.",
            } },
            { title = "Changed", points = {
                "Head tags from roles like VIP or Survivor are now visible to everyone, no admin powers involved.",
            } },
        } },
        { version = "1.3", date = "August 2026", sections = {
            { title = "New", points = {
                "Whether the health page tells you outright that you carry the real zombie infection is now a server setting. Vanilla keeps that in the dark on purpose, and servers who want to keep that uncertainty can switch the display off. Wound infection and every other injury still show.",
                "The server can switch off statistics recording for characters on an admin level, so admin testing does not skew the leaderboards.",
            } },
            { title = "Fixed", points = {
                "The vehicles page could crash the server. Resolving a remembered vehicle by its stamp reached into a vehicle registry that, in rare moments, was not ready yet, and that tore down the whole request. The page then stayed empty or hung. The server checks for that now before it reaches in.",
                "The health page ran into an endless error after death: it searched for a bandage and disinfectant every half second and asked a vanilla function for that which assumes the inventory window is open. There is none once you are dead, so the search failed over and over until you respawned. The page simply skips that search now while the character is dead, there is nothing to bandage anyway.",
                "The zombie kill count could read far too high. Every drop of the in-game counter was taken for a new life and added on top again, even when another mod reset that same counter mid life. A drop is only credited now when a death was actually recorded. Numbers already inflated stay as they are, there is no way to take them apart afterwards.",
            } },
        } },
        { version = "1.2.1", date = "August 2026", sections = {
            { title = "Fixed", points = {
                "Your safehouse card stayed empty although you owned a claim. It looked the zones up on your own machine, and a zone created on the server does not have to arrive there. It now asks the server and keeps itself up to date while the page is open.",
                "Where the server runs the Knox Claim mod, that mod owns the vehicles. The button for remembering a vehicle disappears here in that case, so you do not have to keep your cars in two places. The forget button stays so you can clear out older entries.",
            } },
        } },
        { version = "1.2", date = "July 2026", sections = {
            { title = "New", points = {
                "Hide pages: with the padlock at the bottom of the sidebar open, every entry shows an eye. Hide what you do not care about, the plus next to it brings pages back.",
                "Kits show where they come from: next to the name a small tag tells you which role or booster status grants you the kit. Open kits carry nothing, they belong to everyone.",
            } },
        } },
        { version = "1.1", date = "July 2026", sections = {
            { title = "New", points = {
                "The admins can reset your claim on a kit, usually when a fresh world starts. After that you can collect a one-time kit once more. Whether and when is their call.",
            } },
            { title = "Fixed", points = {
                "Confirmation windows now fit their text: long notices wrap instead of running off the right edge. That affects the zone claim and the vehicle page.",
            } },
        } },
        { version = "1.0", date = "July 2026", points = {
            "F6 opens and closes the player area, the blue button in the bottom left still works too. The key can be changed in the mod options.",
            "New: this player area. A panel of your own with your character in 3D, vitals and favourite weapon, for everyone on the server.",
            "Statistics with server leaderboard: deaths, zombie and bandit kills, kilometres, longest life, playtime.",
            "Health view with every injury at a glance, bandaging and disinfecting right here. The figure grows with the window size.",
            "Safehouse view with expiry warning.",
            "Vehicles: your cars with a 3D preview, a nav arrow to a lost one and every part by category. A flat tire shows up as flat.",
            "Your own zone claim at your house, extent depending on your role. It has to connect to your house and may not overlap anything.",
            "Kits to collect, one time or on a cooldown. You only see the ones unlocked for your role.",
            "Discord boosters: if your server offers it, grab the code in Discord and redeem it at the bottom of the kits page.",
            "Distress call to every admin currently online.",
            "Window freely movable and resizable, pages sortable, help window right inside the panel.",
        } },
    },
}

function AegisHelpContent.get(mode)
    local lang = nil
    pcall(function() lang = Translator.getLanguage():name() end)
    if mode == "player" then
        if lang == "DE" then return AegisHelpContent.PLAYER_DE end
        return AegisHelpContent.PLAYER_EN
    end
    if lang == "DE" then return AegisHelpContent.DE end
    return AegisHelpContent.EN
end
