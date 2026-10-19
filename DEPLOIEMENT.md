# 🚀 Guide de Déploiement sur Render

Ce guide vous explique comment déployer votre jeu Quartiers Maroc sur Render gratuitement.

## 📋 Prérequis

1. Un compte GitHub (gratuit) : https://github.com/signup
2. Un compte Render (gratuit) : https://render.com/register
3. Git installé sur votre ordinateur

## 🔧 Étape 1 : Préparer le Projet

Votre projet est maintenant prêt avec :
- ✅ `server.js` - Serveur Node.js avec toute la logique du jeu
- ✅ `package.json` - Dépendances Node.js
- ✅ `render.yaml` - Configuration Render
- ✅ `app.js` - Frontend adapté pour la production

## 📤 Étape 2 : Pousser sur GitHub

### 2.1 Initialiser Git (si pas déjà fait)

Ouvrez PowerShell dans le dossier du projet et exécutez :

```powershell
git init
git add .
git commit -m "Premier commit - jeu Quartiers Maroc prêt pour déploiement"
```

### 2.2 Créer un Repository sur GitHub

1. Allez sur https://github.com/new
2. Nom du repository : `quartiers-maroc` (ou un autre nom)
3. Laissez **Public** ou choisissez **Private**
4. **Ne cochez AUCUNE option** (pas de README, .gitignore, etc.)
5. Cliquez sur **Create repository**

### 2.3 Lier et Pousser le Code

GitHub vous donnera des commandes. Utilisez celles-ci dans PowerShell :

```powershell
git remote add origin https://github.com/VOTRE-USERNAME/quartiers-maroc.git
git branch -M main
git push -u origin main
```

Remplacez `VOTRE-USERNAME` par votre nom d'utilisateur GitHub.

## 🌐 Étape 3 : Déployer sur Render

### 3.1 Connecter GitHub à Render

1. Allez sur https://dashboard.render.com/
2. Cliquez sur **New +** → **Web Service**
3. Connectez votre compte GitHub (si première fois)
4. Sélectionnez le repository `quartiers-maroc`

### 3.2 Configurer le Service

Render détectera automatiquement `render.yaml`. Vérifiez :

- **Name** : `quartiers-maroc` (ou personnalisez)
- **Environment** : `Node`
- **Build Command** : `npm install`
- **Start Command** : `npm start`
- **Plan** : `Free` (gratuit)

### 3.3 Déployer

1. Cliquez sur **Create Web Service**
2. Render va :
   - Installer les dépendances (`npm install`)
   - Démarrer le serveur (`npm start`)
   - Vous donner une URL du type : `https://quartiers-maroc.onrender.com`

⏱️ **Premier déploiement** : 2-5 minutes

## ✅ Étape 4 : Tester le Jeu

1. Une fois le déploiement terminé, cliquez sur l'URL fournie par Render
2. Le jeu devrait s'ouvrir et fonctionner exactement comme en local !

## 🔄 Mettre à Jour le Jeu

Pour déployer des modifications :

```powershell
git add .
git commit -m "Description des changements"
git push
```

Render redéploiera automatiquement ! 🎉

## ⚠️ Points Importants

### Plan Gratuit Render
- ✅ **Gratuit à vie**
- ⚠️ Le serveur s'endort après **15 minutes d'inactivité**
- ⏱️ Première visite après inactivité : **30-50 secondes de chargement**
- 💡 Une fois réveillé, le jeu fonctionne normalement

### Garder le Serveur Actif (Optionnel)

Si vous voulez que le jeu soit toujours rapide, vous pouvez :

1. **Passer à un plan payant** ($7/mois) - pas de sommeil
2. **Utiliser un service de ping** gratuit comme [UptimeRobot](https://uptimerobot.com/) pour ping toutes les 5 minutes

### Limitations du Plan Gratuit

- 750 heures/mois (largement suffisant)
- Serveur s'endort si inactif
- Parfait pour des projets personnels ou tests

## 🐛 Dépannage

### Le site ne charge pas
- Vérifiez les **Logs** dans le dashboard Render
- Attendez 30-50 secondes si le serveur était endormi

### Erreur de build
- Vérifiez que `package.json` est bien dans le repository
- Assurez-vous que Node.js version ≥18 dans `package.json`

### Erreur "Cannot read properties of undefined"
- Vérifiez que `app.js` a bien été modifié avec `API_BASE`
- Le frontend doit utiliser la même URL que le backend

## 📧 Support

Si vous rencontrez des problèmes :
1. Consultez les logs Render
2. Vérifiez que tous les fichiers sont bien poussés sur GitHub
3. Testez d'abord en local avec `node server.js`

## 🎮 URLs Importantes

- **Dashboard Render** : https://dashboard.render.com/
- **Logs en direct** : Dans votre service Render → onglet "Logs"
- **Documentation Render** : https://render.com/docs

---

## 📝 Résumé des Commandes

```powershell
# Installation locale (pour tester)
npm install
node server.js
# Puis ouvrir http://localhost:8787

# Déployer sur GitHub
git add .
git commit -m "Votre message"
git push

# Render se met à jour automatiquement !
```

---

**Bon jeu ! 🎲🏘️**
