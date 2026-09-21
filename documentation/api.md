# Référence de l'API

Ici commence la zone dangereuse. Appelez Kenny Loggins. Un peu d'expérience en script est
recommandée.
Les fonctions ci-dessous vous permettent de façonner votre IADS à la main. Si vous référencez des
unités qui n'existent pas, un message s'affiche au chargement de la mission.
Les exemples qui suivent utilisent des objets statiques pour les centres de commandement, les nœuds
de liaison et les sources d'énergie ; vous pouvez tout aussi bien employer des unités.

## Configuration de l'IADS

Appelez cette méthode pour ajouter ou retirer une entrée du menu radio permettant d'afficher ou de
masquer l'état de l'IADS. Par défaut, cette entrée n'est pas visible :

```lua
redIADS:addRadioMenu()
```

```lua
redIADS:removeRadioMenu()
```

Si vous déréférencez l'IADS, pensez à appeler `deactivate()`, sans quoi ses tâches de fond
continueront de tourner et produiront des comportements inattendus :

```lua
redIADS:deactivate()
```

Définit l'intervalle de mise à jour de l'IADS, en secondes. Il détermine la cadence à laquelle
l'IADS allume ou éteint les sites SAM en fonction des cibles détectées :

```lua
redIADS:setUpdateInterval(5)
```

## Dernière ligne de défense {#last-line-of-defense}

Un site SAM sous contrôle du réseau a son radar éteint : il est donc **aveugle**. La seule chose
qui puisse le ramener à la vie, c'est un radar de veille lointaine qui le couvre et qui tient la
cible. Volez sous l'horizon des EW radars et aucune batterie ne réagira, quelle que soit la
distance — la proximité du site n'entre nulle part dans le cycle, puisque le seul capteur capable
de la mesurer est justement celui qu'on vient d'éteindre.

La dernière ligne de défense corrige cela. Un site maintenu éteint conserve un petit rayon de
détection **virtuel** qui lui est propre — celui de Skynet, aucun radar DCS n'intervient — et un
aéronef hostile qui y pénètre fait s'activer le site alors qu'aucun radar, nulle part, ne tient de
contact. C'est **actif par défaut**.

La limite, assumée : un système à courte portée peut s'allumer pour un aéronef qu'il ne peut pas
atteindre, parce que le rayon ignore le domaine de tir. Exiger la zone létale reviendrait à ce
qu'une Shilka, portée utile d'environ 2,5 km, ne se réveille jamais dans un rayon de 10 à 15 km —
or les systèmes à courte portée sont exactement ce à quoi sert une dernière ligne de défense.

Désactivez-la pour une mission qui veut un IADS puriste :

```lua
redIADS:setLastLineOfDefence(false)
```

Définit les bornes du rayon, en mètres. Chaque site tire son propre rayon une fois pour toutes,
entre ces deux valeurs, et le conserve pour toute la mission — ainsi un pilote ne peut pas
apprendre la distance exacte, et un site ne clignote pas pour un aéronef qui tourne autour de la
valeur moyenne. Modifier les bornes fait tirer à nouveau tous les sites :

```lua
redIADS:setLastLineOfDefenceRadius(10000, 15000)
```

Définit la durée, en secondes, pendant laquelle un site reste allumé après le dernier contact qui
lui a été signalé. Sans cela, un passage rapide n'allume le site que pour un cycle, et un circuit
d'attente le fait clignoter :

```lua
redIADS:setLastLineOfDefencePersistence(45)
```

Un site rendu silencieux pour échapper à un missile antiradar, à court de munitions, privé
d'énergie ou détruit ne se réveille **pas** à la proximité, et les [conditions
d'activation](#add-go-live-constraints) propres au site restent honorées.

### Signaler un contact depuis l'extérieur de Skynet

`reportContact` est le point d'entrée public qu'utilise la dernière ligne de défense elle-même.
Appelez-le pour réveiller un site SAM sur une unité DCS, comme si quelque chose avait signalé cet
aéronef au réseau : un guetteur, un JTAC, n'importe quel script de votre cru :

```lua
redIADS:reportContact(Unit.getByName('Intruder'), redIADS:getSAMSiteByGroupName('SAM-SA-6'))
```

Contrairement au chemin normal, il n'exige pas que la cible soit dans le domaine de tir du site :
le site s'allume parce qu'on lui a dit que l'aéronef est là, pas parce qu'il peut l'atteindre.
Toutes les autres protections s'appliquent, et le site est maintenu allumé par la persistance
ci-dessus. La fonction indique si le site est allumé après l'appel.

## Rafraîchissement de la couverture

Savoir quelle batterie se trouve sous quel radar est une affaire de géométrie, et la géométrie
change dès que quelque chose bouge. Skynet réévalue la couverture de tout élément ayant parcouru
plus de 10 NM depuis le dernier balayage, par défaut toutes les 10 secondes. C'est ce qui fait
qu'un AWACS en transit perd les batteries qu'il laisse derrière lui — elles deviennent autonomes,
exactement comme s'il avait été abattu — et que les parents d'un site SAM mobile le suivent au fil
de ses déplacements.

```lua
redIADS:setCoverageRefreshInterval(10)
```

Un intervalle de `0` arrête le balayage. Abattre un radar de veille lointaine libère toujours ses
batteries immédiatement, sans attendre le balayage suivant.

## Ajouter un centre de commandement

Le centre de commandement représente l'endroit où l'information est collectée et analysée. S'il est
détruit, l'IADS se désagrège.

Ajoutez un centre de commandement ainsi :

```lua
local commandCenter = StaticObject.getByName("Command Center")
redIADS:addCommandCenter(commandCenter)
```

## Sources d'énergie et nœuds de liaison

Vous pouvez employer des unités ou des objets statiques. Appelez la fonction plusieurs fois pour
ajouter plus d'une source d'énergie ou d'un nœud de liaison.

`unit` désigne un site SAM ou un EW radar récupéré depuis l'IADS — voir [définir une
option](#setting-an-option) :

```lua
local powerSource = StaticObject.getByName("EW Power Source")
unit:addPowerSource(powerSource)
```

```lua
local connectionNode = Unit.getByName("EW connection node")
unit:addConnectionNode(connectionNode)
```

Pour les centres de commandement :

```lua
local commandCenter = StaticObject.getByName("Command Center2")
local comPowerSource = StaticObject.getByName("Command Center2 Power Source")
redIADS:addCommandCenter(commandCenter):addPowerSource(comPowerSource)
```

## Préchauffer les sites SAM d'un IADS

Cette fonction est dépréciée et sera retirée dans une version future.

```lua
redIADS:setupSAMSitesAndThenActivate()
```

## Connecter Skynet à l'AI_A2A_DISPATCHER de MOOSE {#connecting-skynet-to-the-moose-ai_a2a_dispatcher}

Dans la réalité, un IADS ne se contenterait probablement pas de piloter des sites SAM : il
transmettrait aussi l'information à des intercepteurs. Vous pouvez connecter Skynet à
l'[AI_A2A_DISPATCHER](https://flightcontrol-master.github.io/MOOSE_DOCS/Documentation/AI.AI_A2A_Dispatcher.html)
de MOOSE pour ajouter des intercepteurs à l'IADS. Le réseau peut alors non seulement diriger les
sites SAM, mais aussi lancer des chasseurs sur alerte. Skynet renseigne les radars utilisables dans
l'objet SET_GROUP d'un dispatcher : si un radar est perdu dans Skynet, il cesse d'être disponible
pour détecter et déclencher des intercepteurs. Voir la [mission de démonstration
moose_a2a_connector](https://github.com/VEAF/Skynet-IADS/tree/master/demo-missions).

Ajoutez l'objet de type SET_GROUP à l'IADS ainsi (ici `DetectionSetGroup`) :

```lua
redIADS:addMooseSetGroup(DetectionSetGroup)
```

Un exemple complet de montage de Skynet avec l'AI_A2A_DISPATCHER :

```lua
-- Montage du Skynet IADS :
redIADS = SkynetIADS:create('Enemy IADS')
redIADS:addSAMSitesByPrefix('SAM')
redIADS:addEarlyWarningRadarsByPrefix('EW')
redIADS:activate()

-- DÉBUT DU CODE MOOSE :
-- Définir un objet SET_GROUP qui rassemble les groupes constituant le réseau de veille lointaine.
DetectionSetGroup = SET_GROUP:New()

-- Régler la détection et le regroupement des cibles sur une portée de 30 km !
Detection = DETECTION_AREAS:New( DetectionSetGroup, 30000 )

-- Monter le dispatcher A2A et l'initialiser.
A2ADispatcher = AI_A2A_DISPATCHER:New( Detection )

-- Rayon de 100 km pour l'engagement de toute cible par des amis en vol.
A2ADispatcher:SetEngageRadius() -- 100000 est la valeur par défaut.

-- Rayon de 200 km pour l'interception commandée depuis le sol.
A2ADispatcher:SetGciRadius() -- 200000 est la valeur par défaut.

CCCPBorderZone = ZONE_POLYGON:New( "RED-BORDER", GROUP:FindByName( "RED-BORDER" ) )
A2ADispatcher:SetBorderZone( CCCPBorderZone )
A2ADispatcher:SetSquadron( "Kutaisi", AIRBASE.Caucasus.Kutaisi, { "Squadron red SU-27" }, 2 )
A2ADispatcher:SetSquadronGrouping( "Kutaisi", 2 )
A2ADispatcher:SetSquadronGci( "Kutaisi", 900, 1200 )
A2ADispatcher:SetTacticalDisplay(true)
A2ADispatcher:Start()
-- FIN DU CODE MOOSE

-- ajouter le SET_GROUP MOOSE à l'IADS ; à partir de maintenant, Skynet tiendra à jour les radars
-- actifs que ce SET_GROUP peut utiliser pour la détection lointaine.
redIADS:addMooseSetGroup(DetectionSetGroup)
```

## Configuration des sites SAM

### Ajouter des sites SAM

#### Ajouter plusieurs sites SAM

Ajoute à l'IADS les sites SAM dont le nom de groupe commence par le préfixe. Les sites SAM ajoutés
précédemment sont effacés :

```lua
redIADS:addSAMSitesByPrefix('SAM')
```

#### Ajouter un site SAM à la main

Vous pouvez ajouter un site SAM manuellement ; il doit s'agir d'un nom de groupe valide :

```lua
redIADS:addSAMSite('SA-6 Group2')
```

### Accéder aux sites SAM de l'IADS {#accessing-sam-sites-in-the-iads}

Les fonctions suivantes donnent accès aux sites SAM ajoutés à l'IADS. Toutes acceptent
l'enchaînement d'options :

Renvoie tous les sites SAM portant le nom OTAN correspondant, voir
[skynet-iads-supported-types.lua](https://github.com/VEAF/Skynet-IADS/blob/master/skynet-iads-source/skynet-iads-supported-types.lua).
Pour toutes les unités commençant par « SA- », n'employez pas les noms de code OTAN (Guideline,
Gainful), écrivez simplement « SA-2 », « SA-6 » :

```lua
redIADS:getSAMSitesByNatoName('SA-6')
```

Renvoie tous les sites SAM de l'IADS :

```lua
redIADS:getSAMSites()
```

Renvoie le site SAM portant le nom de groupe indiqué :

```lua
redIADS:getSAMSiteByGroupName('SAM-SA-6')
```

**Si aucun groupe ne porte ce nom, rien n'est renvoyé** — l'appel ne produit aucune valeur, ce qui
se lit `nil` lorsque vous l'affectez, comme le font tous les exemples de cette page. Enchaîner
directement sur l'appel, comme dans `redIADS:getSAMSiteByGroupName('typo'):setActAsEW(true)`, échoue
alors sur *attempt to index a nil value* : cette erreur signale presque toujours un nom de groupe
qui ne correspond pas à la mission. `getEarlyWarningRadarByUnitName` se comporte de la même façon.

Renvoie les sites SAM dont le nom de groupe commence par le préfixe indiqué. Imaginons un ensemble
de sites SAM qui partageront tous la même source d'énergie.
Donnez-leur un préfixe particulier dans le nom de groupe, par exemple `SAM-SECTOR-A`. Une fois les
sites ajoutés, vous y accédez par ce préfixe pour leur appliquer les options voulues :

```lua
redIADS:getSAMSitesByPrefix('SAM-SECTOR-A')
```

Le préfixe doit **commencer** le nom de groupe : `SECTOR-A` ne correspond à rien si les groupes
s'appellent `SAM-SECTOR-A-...`. Un préfixe qui ne correspond à rien, comme un nom OTAN que ne porte
aucun site, renvoie une liste vide plutôt que rien du tout : y enchaîner des options ne casse donc
rien — simplement, les options n'atteignent personne.

### Jouer le rôle d'EW radar

Configure le site SAM pour qu'il tienne le rôle d'EW radar. Son radar restera allumé en permanence
et les contacts qu'il détecte seront transmis à l'IADS. Option recommandée pour les systèmes à
longue portée comme le S-300 :

```lua
samSite:setActAsEW(true)
```

### Zone d'engagement

Définit la distance à laquelle un site SAM allume son radar :

```lua
samSite:setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)
```

#### Options de zone d'engagement

Le site SAM s'active lorsque la cible entre dans le cercle rouge de l'éditeur de mission
(comportement par défaut de Skynet) :

```lua
SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_KILL_ZONE
```

Le site SAM s'active lorsque la cible entre dans le cercle jaune de l'éditeur de mission :

```lua
SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE
```

Cette option fixe, en pourcentage de la zone choisie dans `setEngagementZone`, la distance à
laquelle le site SAM s'active. Attention à ne pas descendre trop bas : certains sites SAM ont
besoin de jusqu'à 30 secondes avant de pouvoir tirer.
Pendant ce temps, la cible peut déjà avoir quitté leur zone d'engagement. Cette option vise les
systèmes à longue portée comme le S-300. Vous pouvez aussi dépasser 100, ce qui fera s'activer le
site plus tôt :

```lua
samSite:setGoLiveRangeInPercent(90)
```

### Engager les armements aériens

Autorise le site SAM à engager les armements aériens, s'il en est capable dans DCS. C'est une
enveloppe autour du réglage
[ENGAGE_AIR_WEAPONS](https://wiki.hoggitworld.com/view/DCS_option_engage_air_weapons).

```lua
samSite:setCanEngageAirWeapons(true)
```

### Engager les HARM

Autorise le site SAM à engager les HARM, s'il en est capable dans DCS. Réglée à `false`, l'option
fait s'éteindre le site lorsqu'un HARM identifié par l'IADS arrive sur lui. Les sites SAM capables
d'engager des HARM sont à `true` par défaut.

```lua
samSite:setCanEngageHARM(true)
```

## Ajouter des conditions d'activation {#add-go-live-constraints}

Vous pouvez poser des conditions qui devront être remplies pour que le site SAM s'active. Notez que
cela ne pilote que l'activation du site.
Il n'existe aujourd'hui aucun moyen, via le moteur de script Lua de DCS, de dire à un site SAM de
ne viser qu'un contact précis.

La condition doit s'évaluer à vrai **et** le contact doit être à portée du site SAM — ce second
point étant géré par Skynet.

### Cas d'usage

Placer un site SAM sur une trajectoire que vous soupçonnez empruntée par des chasseurs-bombardiers,
avec une condition sur le cap pour qu'il ne s'active qu'au retour de l'objectif.

Faire qu'un site SAM ne s'active que si les aéronefs sont dans une certaine tranche d'altitude.

Faire qu'un site SAM ne s'active qu'une fois un bâtiment ou une unité détruits par un dispositif
d'attaque.

Vous n'êtes pas obligé d'utiliser le contact fourni à la fonction pour évaluer la condition : vous
pouvez y affirmer ce que vous voulez.

Écrivez une fonction qui évalue si la condition est remplie. Elle a accès au
[contact](#contact) que le site SAM est en train d'évaluer :

```lua
-- le site SAM ne s'activera que si le contact est sous 1000 pieds.
local function goLiveConstraint(contact)
	return ( contact:getHeightInFeetMSL() < 1000 )
end
```

Ajoutez la fonction au site SAM en lui donnant un nom. Vous pouvez poser autant de conditions que
vous voulez :

```lua
self.samSite:addGoLiveConstraint('ignore-low-flying-contacts', goLiveConstraint)
```

Retirez une condition dont vous ne voulez plus :

```lua
self.samSite:removeGoLiveConstraint('ignore-low-flying-contacts')
```

Récupérez la table de toutes les conditions :

```lua
self.samSite:getGoLiveConstraints()
```

## Contact {#contact}

Les méthodes suivantes donnent des informations sur un contact.

Renvoie vrai si le contact a été identifié comme un HARM par Skynet :

```lua
contact:isIdentifiedAsHARM()
```

Renvoie l'altitude du contact :

```lua
contact:getHeightInFeetMSL()
```

Renvoie le cap magnétique courant du contact. Attention : le cap n'est disponible qu'une fois le
contact suivi par l'IADS sur plus d'un cycle. Jusque-là, il vaut 0 :

```lua
contact:getMagneticHeading()
```

Renvoie la vitesse sol courante du contact, en nœuds, arrondie à `decimals` décimales (2 si
l'argument est omis). Attention : la vitesse n'est disponible qu'une fois le contact suivi par
l'IADS sur plus d'un cycle. Jusque-là, elle vaut 0 :

```lua
contact:getGroundSpeedInKnots(0)
```

Renvoie depuis combien de secondes le contact est connu de l'IADS :

```lua
contact:getAge()
```

Renvoie le type sous la forme d'un `Object.Category` :

```lua
contact:getTypeName()
```

Renvoie le nom de l'unité :

```lua
contact:getName()
```

## Configuration des EW radars

### Ajouter des EW radars

#### Ajouter plusieurs EW radars

Ajoute à l'IADS les EW radars dont le nom d'unité commence par le préfixe. Les EW radars ajoutés
précédemment sont effacés :

```lua
redIADS:addEarlyWarningRadarsByPrefix('EW')
```

#### Ajouter un EW radar à la main

Vous pouvez ajouter des EW radars manuellement ; il doit s'agir d'un nom d'unité valide :

```lua
redIADS:addEarlyWarningRadar('EWR West')
```

### Accéder aux EW radars de l'IADS {#accessing-ew-radars-in-the-iads}

Les fonctions suivantes donnent accès aux EW radars ajoutés à l'IADS. Toutes acceptent
l'enchaînement d'options.

Renvoie tous les EW radars de l'IADS :

```lua
redIADS:getEarlyWarningRadars()
```

Renvoie l'EW radar portant le nom d'unité indiqué :

```lua
redIADS:getEarlyWarningRadarByUnitName('EW-west')
```

## Options communes aux sites SAM et aux EW radars

### Définir une option {#setting-an-option}

Dans les exemples qui suivent, `ewRadarOrSamSite` désigne un EW radar ou un site SAM isolé, ou bien
une table d'EW radars et de sites SAM obtenue depuis le Skynet IADS en appelant l'une des fonctions
citées dans [accéder aux EW radars](#accessing-ew-radars-in-the-iads) ou [accéder aux sites
SAM](#accessing-sam-sites-in-the-iads).

### Enchaîner les options

Vous pouvez enchaîner les options sur un site SAM ou un EW radar isolé, comme sur une table de
sites SAM ou d'EW radars :

```lua
redIADS:getSAMSites():setActAsEW(true):addPowerSource(powerSource):addConnectionNode(connectionNode):setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE):setGoLiveRangeInPercent(90):setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
```

### Défense contre les HARM

Vous pouvez fixer la probabilité de réaction, entre 0 et 100 pour cent. Le champ
`harm_detection_chance` de
[skynet-iads-supported-types.lua](https://github.com/VEAF/Skynet-IADS/blob/master/skynet-iads-source/skynet-iads-supported-types.lua)
donne les probabilités de détection par défaut :

```lua
ewRadarOrSamSite:setHARMDetectionChance(50)
```

### Défense rapprochée {#point-defence}

Le SAM de défense rapprochée doit être capable d'engager des missiles HARM. Il peut protéger des
sites SAM comme des EW radars. Voir [défense rapprochée](tactics.md#point-defence) pour ce que fait
ce mécanisme.

Si vous voulez que les défenses rapprochées coordonnent leur riposte, placez plusieurs sites SAM de
défense rapprochée dans un même groupe. **C'est le seul endroit où l'on doive placer plusieurs
sites SAM dans un même groupe avec Skynet.**
Admettons que deux SA-15 défendent un radar. Dans des groupes séparés, ils tireront tous les deux
sur le même HARM entrant. Dans le même groupe, face à plusieurs HARM, chacun en prendra un
différent.

```lua
-- récupérer d'abord depuis l'IADS le site SAM à utiliser en défense rapprochée :
local sa15 = redIADS:getSAMSiteByGroupName('SAM-SA-15')
-- puis l'attacher au site SAM qu'il doit protéger :
redIADS:getSAMSiteByGroupName('SAM-SA-10'):addPointDefence(sa15)
```

Cette fonction est dépréciée et sera retirée dans une version future.

```lua
ewRadarOrSamSite:setIgnoreHARMSWhilePointDefencesHaveAmmo(true)
```

### Comportement en mode autonome

Définit le comportement du site SAM ou de l'EW radar lorsqu'il perd la liaison avec l'IADS :

```lua
ewRadarOrSamSite:setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)
```

#### Options du mode autonome

Le site SAM ou l'EW radar adopte le comportement par défaut de l'IA de DCS. L'état d'alerte passe
au rouge et les ROE à *weapons free* (comportement Skynet par défaut pour les sites SAM) :

```lua
SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DCS_AI
```

Le site SAM ou l'EW radar s'éteint lorsqu'il perd la liaison avec l'IADS (comportement par défaut
pour les EW radars) :

```lua
SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK
```

## Ajouter un brouilleur {#adding-a-jammer}

Le brouilleur est assez simple à mettre en place. Il vous faut une unité qui serve de source de
brouillage, de préférence un aéronef du dispositif d'attaque.
Dès qu'il détecte un émetteur, le brouilleur se met à brouiller le radar. Activez la [variable de
débogage jammerProbability](#setting-debug-information) pour voir ce que fait le brouilleur.
Le fichier
[skynet-iads-jammer.lua](https://github.com/VEAF/Skynet-IADS/blob/master/skynet-iads-source/skynet-iads-jammer.lua)
indique quels sites SAM sont pris en charge.

Pensez à régler, dans l'éditeur de mission, l'aéronef IA qui joue le brouilleur sur `Reaction to
Threat = EVADE FIRE`, sans quoi l'IA cherchera activement à attaquer le site SAM.
Ainsi réglé, il s'en tiendra au plan de vol prévu.

Créez un brouilleur et affectez-le à une unité. Veillez à préciser l'IADS pour lequel il doit
travailler :

```lua
local jammerSource = Unit.getByName("F-4 AI")
jammer = SkynetIADSJammer:create(jammerSource, iads)
```

Le brouilleur se met à l'écoute des émetteurs et brouille ceux qu'il est capable de brouiller, dès
qu'il en détecte un :

```lua
jammer:masterArmOn()
```

Désactive le brouillage pour le type de SAM indiqué ; passez le nom OTAN :

```lua
jammer:disableFor('SA-2')
```

Éteint le brouilleur. Appelez bien cette fonction avant de déréférencer un brouilleur dans le code,
sans quoi une tâche de fond continuera de brouiller :

```lua
jammer:masterArmSafe()
```

Une batterie cesse d'être brouillée environ **dix secondes** après que le brouilleur a cessé de la
brouiller — que l'émetteur soit abattu, éteint par `masterArmSafe()`, parti au-delà de sa distance
efficace, ou qu'il ait perdu la vue directe sur tous les radars de la batterie. Elle est alors
rendue à ce qui la dirigeait. Une batterie éteinte à cet instant est libérée à son prochain
allumage.

Ajoute la commande brouilleur marche / arrêt au menu radio :

```lua
jammer:addRadioMenu()
```

Retire la commande brouilleur marche / arrêt du menu radio :

```lua
jammer:removeRadioMenu()
```

### Fonctions avancées

Ajoute un second IADS que le brouilleur doit pouvoir brouiller, par exemple si vous faites tourner
deux IADS distincts :

```lua
jammer:addIADS(iads2)
```

Ajoute une nouvelle fonction de brouillage :

```lua
-- écrire une fonction anonyme qui attend un paramètre :
-- d'après les données publiques sur les brouilleurs, leur efficacité chute fortement à mesure qu'on se rapproche ; une fonction non linéaire a donc du sens :
local function f(distanceNM)
	return ( 1.4 ^ distanceNM ) + 80
end

-- ajouter la fonction en précisant à quel type de SAM elle s'applique :
self.jammer:addFunction('SA-10', f)
```

Définit la portée maximale du brouilleur ; la valeur par défaut est de 200 milles nautiques :

```lua
jammer:setMaximumEffectiveDistance(100)
```

## Activer les informations de débogage {#setting-debug-information}

Pendant la conception d'une mission, je vous conseille d'activer des sorties de débogage pour
vérifier comment l'IADS réagit aux menaces. Elles peuvent ralentir DCS : mieux vaut les couper en
environnement de production.

Accédez aux réglages de débogage :

```lua
local iadsDebug = redIADS:getDebugSettings()
```

Sortie en jeu :

```lua
iadsDebug.IADSStatus = true
iadsDebug.contacts = true
iadsDebug.jammerProbability = true
```

Les erreurs de montage — un nom de groupe ou d'unité absent de la mission, un élément appartenant à
l'autre coalition, un groupe dont Skynet n'a pas les données SAM — s'affichent à l'écran préfixées
`WARNING:`, et sont toujours écrites dans `dcs.log`, quel que soit ce réglage. C'est **actif par
défaut** ; une mission qui connaît ses propres avertissements et ne veut pas les afficher aux
joueurs les désactive :

```lua
iadsDebug.warnings = false
```

Sortie vers dcs.log :

```lua
iadsDebug.addedEWRadar = true
iadsDebug.addedSAMSite = true
iadsDebug.radarWentLive = true
iadsDebug.radarWentDark = true
iadsDebug.harmDefence = true
```

Ces trois options écrivent le détail de chaque radar de l'IADS dans le fichier dcs.log. Les activer
peut avoir un impact sur les performances :

```lua
iadsDebug.samSiteStatusEnvOutput = true
iadsDebug.earlyWarningRadarStatusEnvOutput = true
iadsDebug.commandCenterStatusEnvOutput = true
```

![Sortie de débogage de Skynet](images/skynet-debug.png)

## Exemple de montage

Voici un exemple de montage d'IADS, celui de la [mission de
démonstration](https://github.com/VEAF/Skynet-IADS/tree/master/demo-missions) :

```lua
do

-- créer une instance de l'IADS
redIADS = SkynetIADS:create('RED IADS')

--- réglages de débogage : supprimer à partir d'ici si vous ne voulez aucune sortie sur ce que fait l'IADS par défaut
local iadsDebug = redIADS:getDebugSettings()
iadsDebug.IADSStatus = true
iadsDebug.radarWentDark = true
iadsDebug.contacts = true
iadsDebug.radarWentLive = true
iadsDebug.noWorkingCommmandCenter = true
iadsDebug.samNoConnection = true
iadsDebug.jammerProbability = true
iadsDebug.addedEWRadar = true
iadsDebug.harmDefence = true
--- fin de la partie débogage à supprimer ---

-- ajouter à l'IADS toutes les unités dont le nom commence par 'EW' :
redIADS:addEarlyWarningRadarsByPrefix('EW')

-- ajouter à l'IADS tous les groupes dont le nom commence par 'SAM' :
redIADS:addSAMSitesByPrefix('SAM')

-- ajouter un centre de commandement :
commandCenter = StaticObject.getByName('Command-Center')
redIADS:addCommandCenter(commandCenter)

--- on ajoute un AWACS K-50 à la main. On pourrait tout aussi bien l'automatiser en préfixant le nom d'unité par 'EW' :
redIADS:addEarlyWarningRadar('AWACS-K-50')

-- ajouter une source d'énergie et un nœud de liaison à cet EW radar :
local powerSource = StaticObject.getByName('Power-Source-EW-Center3')
local connectionNodeEW = StaticObject.getByName('Connection-Node-EW-Center3')
redIADS:getEarlyWarningRadarByUnitName('EW-Center3'):addPowerSource(powerSource):addConnectionNode(connectionNodeEW)

-- ajouter un nœud de liaison à ce site SA-2, et lui demander de s'éteindre s'il perd la liaison avec l'IADS :
local connectionNode = Unit.getByName('Mobile-Command-Post-SAM-SA-2')
redIADS:getSAMSiteByGroupName('SAM-SA-2'):addConnectionNode(connectionNode):setAutonomousBehaviour(SkynetIADSAbstractRadarElement.AUTONOMOUS_STATE_DARK)

-- ce site SA-2 s'activera à 70 % de sa portée de veille maximale :
redIADS:getSAMSiteByGroupName('SAM-SA-2'):setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE):setGoLiveRangeInPercent(70)

-- tous les sites SA-10 tiendront le rôle d'EW radar : leur radar restera allumé en permanence :
redIADS:getSAMSitesByNatoName('SA-10'):setActAsEW(true)

-- mettre les SA-15 en défense rapprochée du site SA-10. On règle le SA-10 pour qu'il identifie toujours les HARM, afin de démontrer le mécanisme de défense rapprochée de Skynet.
-- le SA-10 restera allumé sous le feu des HARM tant que les défenses rapprochées et le site SAM auront des munitions et que le point de saturation ne sera pas atteint.
local sa15 = redIADS:getSAMSiteByGroupName('SAM-SA-15-point-defence-SA-10')
redIADS:getSAMSiteByGroupName('SAM-SA-10'):addPointDefence(sa15):setHARMDetectionChance(100)

-- ce site SA-11 s'activera à 70 % de la portée maximale de ses missiles (valeur par défaut : 100 %), et sa probabilité de détection des HARM est fixée à 50 % (valeur par défaut : 70 %)
redIADS:getSAMSiteByGroupName('SAM-SA-11'):setGoLiveRangeInPercent(70):setHARMDetectionChance(50)

-- ce site SA-6 réagira toujours à un HARM tiré sur lui :
redIADS:getSAMSiteByGroupName('SAM-SA-6'):setHARMDetectionChance(100)

-- ce site SA-11 s'activera à la portée de veille maximale (par défaut, c'est à la portée de tir maximale) :
redIADS:getSAMSiteByGroupName('SAM-SA-11-2'):setEngagementZone(SkynetIADSAbstractRadarElement.GO_LIVE_WHEN_IN_SEARCH_RANGE)

-- activer l'entrée de menu radio qui affiche l'état de l'IADS
redIADS:addRadioMenu()

-- activer l'IADS
redIADS:activate()

-- ajouter le brouilleur
local jammer = SkynetIADSJammer:create(Unit.getByName('jammer-emitter'), redIADS)
jammer:masterArmOn()

-- monter l'IADS bleu :
blueIADS = SkynetIADS:create('BLUE IADS')
blueIADS:addSAMSitesByPrefix('BLUE-SAM')
blueIADS:addEarlyWarningRadarsByPrefix('BLUE-EW')
blueIADS:activate()
blueIADS:addRadioMenu()

local iadsDebug = blueIADS:getDebugSettings()
iadsDebug.IADSStatus = true
iadsDebug.contacts = true

end
```
