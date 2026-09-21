# Skynet-IADS

![logo](images/SA3_2.jpg)

Un script d'IADS (Integrated Air Defence System — système de défense aérienne intégré) pour DCS
(Digital Combat Simulator).

## Résumé

Ce script simule un IADS dans les limites de ce que permet le moteur de script de DCS. Des radars
de veille lointaine (EW radars) balaient le ciel à la recherche de contacts. Ces contacts sont
recoupés avec les sites SAM (Surface to Air Missile). Dès qu'un contact entre dans le domaine de
tir d'un site SAM, celui-ci s'active.

Un IADS moderne repose aussi sur des centres de commandement et sur des liaisons de données vers
les sites SAM. Vous pouvez monter l'IADS avec cette infrastructure : la détruire dégrade les
capacités du réseau.

Tout ceci vous paraît du charabia ? Regardez [cette vidéo de Covert Cabal sur les IADS
modernes](https://www.youtube.com/watch?v=9J9kntzkSQY).

Le [fil de discussion sur le forum
DCS](https://forums.eagle.ru/topic/226173-skynet-an-iads-for-mission-builders) suit les évolutions
du développement.

Rejoignez le [groupe Discord de Skynet](https://discord.gg/pz8wcQs) pour vous faire aider à
configurer votre mission.

Skynet prend en charge le [mod HighDigitSAMs](https://github.com/Auranis/HighDigitSAMs).

Vous pouvez aussi [connecter Skynet à l'AI_A2A_DISPATCHER](api.md#connecting-skynet-to-the-moose-ai_a2a_dispatcher)
de MOOSE pour ajouter des intercepteurs à l'IADS.

**Plus de 200 heures de travail ont été consacrées au développement de Skynet à ce jour.
Si vous aimez l'utiliser, pensez à faire un don :**

[![Skynet IADS donation](images/btn_donateCC_LG.gif.png)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=7GSVFH448BWFQ&source=url)

## Démarrage rapide {#quick-start}

Déjà fatigué de lire ? Récupérez `skynet-test-persian-gulf.miz` dans la [dernière
version](https://github.com/VEAF/Skynet-IADS/releases) et voyez Skynet à l'œuvre sur la carte du
golfe Persique. Elle est jointe à la release, à côté de `skynet-iads-compiled.lua`, et embarque
exactement le Skynet que cette version livre.

Les fichiers `.miz` du dépôt, eux, sont des **gabarits** : ils contiennent un emplacement réservé à
la place de chaque script, pour qu'une copie du code déposée à côté du code ne puisse pas prendre
trois ans de retard en silence — ce qui est précisément arrivé, jusqu'au 20/09/2026. Si vous
travaillez depuis un clone, assemblez vous-même les missions jouables, dans `build/missions/` :

```
pwsh -File build-tools/build-compiled-script.ps1
python build-tools/miz-suite.py build
```

## Remerciements

Un merci tout particulier à Spearzone et Coranthia, qui ont épluché les informations publiques sur
les réseaux IADS et m'ont mis à niveau sur le fonctionnement d'un tel système.
Le montage des sites SAM s'inspire de la [SAM DB de
Grimes](https://forums.eagle.ru/showthread.php?t=118175), tirée de son script IADS ; j'en ai
toutefois retiré les données de portée, que Skynet lit directement dans DCS.
