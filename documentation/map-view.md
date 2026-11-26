# Vue carte

Skynet peut dessiner un réseau sur la carte F10 et tenir ce dessin à jour : quels sites sont allumés
ou éteints, quel radar EW couvre quel site SAM, ce que protège une défense rapprochée, si un centre de
commandement est encore alimenté. C'est un outil pour construire et vérifier une mission.

## Afficher la carte {#showing-the-map}

```lua
redIADS:displayMap(true)  -- dessine le réseau et tient le dessin à jour
redIADS:displayMap(false) -- l'efface
redIADS:isMapDisplayed()  -- indique s'il est affiché
```

Le dessin apparaît une seconde après `displayMap(true)`, puis suit le réseau chaque seconde.
`redIADS:deactivate()` l'efface.

Le [menu radio](api.md#iads-configuration) d'un réseau a trois commandes pour sa carte. Chacune
bascule à chaque clic :

- `Map - Show/hide`
- `Map - Show/hide coverage lines (EW -> SAM)`
- `Map - Show/hide range circles`

## Réglages {#settings}

```lua
local mapSettings = redIADS:getDisplayMapSettings()
```

Les réglages sont lus chaque seconde : un changement se voit sur une carte déjà affichée.

Ce qui est dessiné : les couches ci-dessous, toutes affichées par défaut. `setLayer()` affiche ou
masque l'une d'elles, et `hasLayer()` dit si elle est affichée. Une carte sans aucune couche affichée
ne dessine rien :

| Couche | Ce qu'elle dessine |
|---|---|
| `elements` | les formes, et la ligne d'un centre de commandement à ses sources d'énergie |
| `coverage` | les lignes d'un radar EW aux sites SAM qu'il couvre |
| `pointDefence` | les lignes d'une défense rapprochée au site qu'elle protège |
| `rangeCircles` | la distance d'allumage des sites SAM allumés |
| `labels` | les noms sous les formes |

```lua
mapSettings:setLayer(SkynetIADSMapView.layers.labels, false)
mapSettings:setLayer(SkynetIADSMapView.layers.pointDefence, false)
```

Qui voit le dessin, `targetCoalition` : `coalition.side.RED`, `coalition.side.BLUE`,
`coalition.side.NEUTRAL`, ou `nil` pour toutes les coalitions, la valeur par défaut :

```lua
mapSettings.targetCoalition = coalition.side.RED
```

Chaque marque de la carte F10 a un identifiant, et DCS laisse chaque script choisir les siens. La vue
carte compte ses marques à partir de `7300000`, pour tous les réseaux. Une mission dont les marques
utilisent déjà cette plage la déplace, avant d'afficher une carte :

```lua
SkynetIADSMapView.firstMarkId = 9000000
```

## Légende {#legend}

| Élément | Forme | Couleur |
|---|---|---|
| Radar EW, ou site SAM servant de radar EW | carré | bleu allumé, gris éteint, noir réduit au silence par un HARM |
| Site SAM | triangle | rempli de rouge allumé, gris éteint, noir réduit au silence par un HARM ; contour orange en mode autonome |
| Défense rapprochée | petit triangle, pointe en bas | comme un site SAM, violet pendant qu'elle se défend contre un HARM |
| Centre de commandement | rectangle | vert alimenté, orange sans énergie, rouge détruit |
| Source d'énergie d'un centre de commandement | petit carré | vert, rouge détruite |
| Élément détruit | contour en pointillés | à sa dernière position connue |
| Site SAM allumé | cercle rouge | sa distance d'allumage : là où Skynet le réveille, selon sa [zone d'engagement](api.md#engagement-zone) |

| Ligne | Tracé |
|---|---|
| Radar EW → site SAM | bleu plein, tant que Skynet compte ce radar comme couvrant le site |
| Défense rapprochée → site protégé | gris en pointillés ; violet plein quand elle est maintenue allumée contre un HARM |
| Centre de commandement → source d'énergie | vert en pointillés |

Chaque forme porte le nom de son unité ou de son groupe dans la mission.

## Coût {#cost}

Chaque marque que DCS ajoute à la carte ou en retire est un événement, envoyé à chaque élément de
Skynet. La vue carte ne redessine donc que ce qui a changé depuis la dernière seconde, et un élément
seulement s'il s'est déplacé de plus de 2 km (10 km en vol). Un grand réseau coûte encore un bref gel
au premier dessin : sur un réseau d'environ 600 marques, un dessin complet a figé le jeu près d'une
seconde.
