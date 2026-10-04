# Funktionsblatt

Windows-App für die Tageslisten aus Conqueror X. Die XML-Exporte werden direkt in der App gelesen; Python und der separate Konverter sind nicht mehr erforderlich.

## Benutzung

1. XML-Dateien wie bisher aus Conqueror X exportieren.
2. In der App einmal den XML-Exportordner und den PDF-Zielordner auswählen. Die Einstellungen bleiben erhalten. Standard: `C:\Funktionsblatt` und `C:\Funktionsblatt\PDF_Output`.
3. **Funktionsblätter erstellen** klicken. Jede XML erhält ein eigenes PDF mit Datum und Wochentag. Bei gleichen Tagen oder vorhandenen PDFs wird eine Nummer ergänzt, ohne bestehende Dateien zu überschreiben.
4. **PDF-Ordner öffnen** klicken und die gewünschten Listen drucken.

Erst nach erfolgreicher PDF-Erstellung wird die XML in den Unterordner `Archiv` des Exportordners verschoben. Defekte Dateien bleiben liegen; die übrigen Dateien werden weiterverarbeitet. Falls die Archivierung scheitert, bleibt die XML ebenfalls liegen und die App zeigt einen Hinweis. Vor einem erneuten Start diese Datei prüfen, sonst kann ein zusätzliches PDF entstehen.

Reservierungen mit einer Kuchenbestellung erscheinen auch ohne Tischreservierung vorher/nachher auf der Liste, insbesondere KGB. Die Kuchenart wird in der Notiz ausgegeben. Die übrigen Buchungsfilter, Notizen und das PDF-Layout bleiben erhalten. Auch ein Tag ohne relevante Buchungen erhält eine Liste mit Zusammenfassung. Eine XML mit mehreren Reservierungstagen oder ohne erkennbares Reservierungsdatum wird mit Hinweis zurückgewiesen.

## Windows-App bauen

Mit installiertem Flutter und Visual Studio inklusive „Desktopentwicklung mit C++“ im Projektordner:

```
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build windows --release
```

Die komplette Ausgabe in `build\windows\x64\runner\Release` verwenden, nicht nur die EXE. Die alte App erst ersetzen, nachdem die neue Version mit Beispiel-XMLs geprüft wurde. Der GitHub-Workflow „Windows App“ führt Tests und Build aus und stellt den Ausgabeordner als ZIP-Artefakt `Funktionsblatt-Windows` bereit.

## Personenzahlen

Pax und Tisch-Zusammenfassung verwenden dieselbe Reihenfolge: `NumberPeopleEating` größer 0, sonst Tischreservierungsmenge größer 1, sonst `NumberPeopleBowling` größer 0. Ohne diese Angaben steht „offen“ in Pax und „Personenzahl offen“ in der Notiz. Die Tischmengen werden aus den zugehörigen Transaktionen und `MenuChoices` gelesen, ohne dieselbe Menge doppelt zu zählen. Vorher und nachher werden getrennt zusammengefasst; Kuchenbestellungen ohne Tischbuchung zählen nicht in die Tischsummen. Unvollständige Summen werden als „mindestens“ mit Anzahl offener Personenzahlen markiert. Andere Zusammenfassungsangaben (z. B. Kuchen) aus dem Export bleiben erhalten.
