# SpeechToType – Release & Sparkle-Updates

Releases laufen automatisch über GitHub Actions (`.github/workflows/release.yml`).
Pull Requests und Pushes auf `main`/`Development` werden zusätzlich von
`.github/workflows/ci.yml` gebaut und getestet (unsigniert, UI-Tests übersprungen).

## Neues Release veröffentlichen

1. Änderungen nach `main` mergen.
2. Tag setzen und pushen – nur Zahlen, **ohne** `v`-Präfix (wie bisher):
   ```bash
   git tag -a 3.1 -m "## SpeechToType 3.1

   - Neues Feature …"
   git push origin 3.1
   ```
   Alternativ: *Actions → Release → Run workflow* mit Version (und optional Release Notes).
   Wird das Release vorher in der GitHub-Oberfläche angelegt, nutzt der Workflow
   dessen Text und lädt nur das DMG hoch.
3. Der Workflow erledigt dann:
   - Version = Tag (`MARKETING_VERSION`), Build-Nummer = höchste `sparkle:version` in
     `appcast.xml` auf `main` + 1 (`CURRENT_PROJECT_VERSION`)
   - `xcodebuild archive` + Export mit Developer ID (`SpeechToType/ExportOptions.plist`)
   - Notarisierung der App und des DMG per `notarytool` (App-Store-Connect-API-Key) + `stapler`
   - `SpeechToType.dmg` signieren und als GitHub Release hochladen
   - Sparkle-Signatur (`sign_update`, Tools aus dem offiziellen Sparkle-Release passend
     zur SPM-Version) und neuen `<item>`-Eintrag oben in `appcast.xml` auf `main` committen

Release Notes kommen (in dieser Reihenfolge) aus: Text eines bereits existierenden
Releases, Eingabe beim manuellen Start, Nachricht eines annotierten Tags, sonst
automatisch generiert. Sie werden als HTML in die Appcast-Beschreibung übernommen.

Die App liest den Feed über `SUFeedURL` =
`https://raw.githubusercontent.com/Janinnho/SpeechToType/main/appcast.xml`.
Die Versionsnummern in `project.pbxproj` müssen dafür nicht mehr manuell erhöht werden
(der Workflow überschreibt sie beim Build); für lokale Builds kann man sie trotzdem nachziehen.

## Benötigte Repository-Secrets

*Settings → Secrets and variables → Actions → New repository secret*

| Secret | Inhalt |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | „Developer ID Application“-Zertifikat **inkl. privatem Schlüssel** als `.p12`, Base64: `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERT_PASSWORD` | Passwort der `.p12`-Datei |
| `ASC_API_KEY_ID` | Key-ID des App-Store-Connect-API-Keys (Users and Access → Integrations → Team Keys, Rolle „Developer“ reicht) |
| `ASC_API_ISSUER_ID` | Issuer-ID von derselben Seite |
| `ASC_API_KEY_P8_BASE64` | Die heruntergeladene `AuthKey_XXXX.p8`, Base64: `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `SPARKLE_PRIVATE_KEY` | Privater EdDSA-Schlüssel von Sparkle (siehe unten) |

Das Keychain-Passwort erzeugt der Workflow selbst. Fehlt ein Secret, bricht der
Workflow sofort mit einer Liste der fehlenden Namen ab.

### Sparkle-Schlüssel

Es **muss der bestehende Schlüssel** sein, dessen Public Key als `SUPublicEDKey` in
`SpeechToType/SpeechToType/Info.plist` steht – sonst lehnen installierte Versionen
das Update ab. **Keinen neuen Schlüssel erzeugen.** Export aus dem Schlüsselbund:

```bash
# Tools aus dem Sparkle-Release (bin/) bzw. Xcode: Package Dependencies → Sparkle → Show in Finder → ../artifacts/sparkle/Sparkle/bin
./bin/generate_keys -p          # zeigt den Public Key – muss SUPublicEDKey entsprechen
./bin/generate_keys -x sparkle_private_key
cat sparkle_private_key | pbcopy   # Inhalt als Secret SPARKLE_PRIVATE_KEY speichern
rm sparkle_private_key
```

## Manuelles Release (Fallback)

1. In Xcode archivieren, mit Developer ID exportieren und notarisieren.
2. DMG erstellen, `sign_update SpeechToType.dmg` ausführen.
3. Neuen `<item>` oben in `appcast.xml` einfügen (`sparkle:version` = Build-Nummer,
   `shortVersionString`, `edSignature`, `length`) und DMG als Release-Asset
   `SpeechToType.dmg` unter dem Tag hochladen.
