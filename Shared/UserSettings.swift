import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Codable {
    case system
    case de
    case en
    case es
    case fr

    static var current: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        if let selection = AppLanguage(rawValue: stored), selection != .system {
            return selection
        }

        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("de") { return .de }
        if preferred.hasPrefix("es") { return .es }
        if preferred.hasPrefix("fr") { return .fr }
        return .en
    }

    var displayName: String {
        switch self {
        case .system: return lt("Systemsprache")
        case .de: return "Deutsch"
        case .en: return "English"
        case .es: return "Español"
        case .fr: return "Français"
        }
    }
}

enum AppLocalizer {
    static func text(_ key: String) -> String {
        switch AppLanguage.current {
        case .system:
            return key
        case .de:
            return key
        case .en:
            return english[key] ?? key
        case .es:
            return spanish[key] ?? english[key] ?? key
        case .fr:
            return french[key] ?? english[key] ?? key
        }
    }

    private static let english: [String: String] = [
        "Heute": "Today",
        "Workout": "Workout",
        "Ernährung": "Nutrition",
        "Statistiken": "Statistics",
        "Mehr": "More",
        "Schließen": "Close",
        "Schritte": "Steps",
        "Bewegung": "Movement",
        "Kalorien": "Calories",
        "Energie heute": "Today's energy",
        "Grundbedarf": "Baseline",
        "Aktivität": "Activity",
        "Gesamtverbrauch": "Total burn",
        "Grundbedarf bis jetzt": "Baseline so far",
        "Gesamtverbrauch bis jetzt": "Total burn so far",
        "gegen Grundbedarf": "vs baseline",
        "inkl. Bewegung": "incl. movement",
        "Bilanz vs Grundbedarf": "Balance vs baseline",
        "Bilanz inkl. Bewegung": "Balance incl. movement",
        "Ø Gesamt/Tag": "Avg total/day",
        "Ø aufgenommen": "Avg consumed/day",
        "Ø vs Grundbedarf": "Avg vs baseline",
        "Ø inkl. Bewegung": "Avg incl. movement",
        "Bewegung = Apple-Health-Aktivkalorien aus Gehen, Schritten, Alltagsaktivität und Workouts - nicht aus Nahrung.": "Movement = Apple Health active calories from walking, steps, daily activity, and workouts - not from food.",
        "Distanz": "Distance",
        "Energie-Bilanz heute": "Energy balance today",
        "Verbraucht": "Burned",
        "Aufgenommen": "Consumed",
        "Du hast heute mehr gegessen als verbraucht.": "You ate more than you burned today.",
        "Du bist im Defizit – mehr verbraucht als gegessen.": "You're in a deficit - burned more than you ate.",
        "Noch keine Aktivität gemessen.": "No activity recorded yet.",
        "Letzte Workouts": "Recent workouts",
        "%d:%02d:%02d h": "%d:%02d:%02d h",
        "%d:%02d min": "%d:%02d min",
        "Metrisch (km)": "Metric (km)",
        "Imperial (mi)": "Imperial (mi)",
        "System": "System",
        "Hell": "Light",
        "Dunkel": "Dark",
        "Untergewicht": "Underweight",
        "Normalgewicht": "Healthy weight",
        "Übergewicht": "Overweight",
        "Adipositas": "Obesity",
        "Laufen": "Running",
        "Gehen": "Walking",
        "Radfahren": "Cycling",
        "Wandern": "Hiking",
        "Schwimmen": "Swimming",
        "Rudern": "Rowing",
        "Crosstrainer": "Elliptical",
        "Treppen": "Stairs",
        "Yoga": "Yoga",
        "Krafttraining": "Strength training",
        "Tanzen": "Dance",
        "Fußball": "Soccer",
        "Skaten": "Skating",
        "Ski": "Skiing",
        "Sonstiges": "Other",
        "Essen": "Food",
        "Getränk": "Drink",
        "%d %@ geschafft! 🎉": "%d %@ completed! 🎉",
        "Tempo: %d:%02d min/km": "Pace: %d:%02d min/km",
        "Pace: %d:%02d min/mi": "Pace: %d:%02d min/mi",
        "Workout-Verlauf": "Workout history",
        "Zeit": "Time",
        "Tempo": "Pace",
        "Watch: %d bpm · %d kcal": "Watch: %d bpm · %d kcal",
        "Workout beenden": "End workout",
        "Workout starten": "Start workout",
        "Tracking-Hilfe": "Tracking guide",
        "Apple Watch vorbereiten": "Prepare Apple Watch",
        "Empfohlener Ablauf": "Recommended flow",
        "1. Öffne SimpleTracking auf der Apple Watch und bestätige die Health-Berechtigungen für Workouts, Herzfrequenz, Energie und Distanz.": "1. Open SimpleTracking on the Apple Watch and confirm Health permissions for workouts, heart rate, energy, and distance.",
        "2. Starte auf der Watch ein Outdoor-Workout und bleibe währenddessen möglichst unter freiem Himmel, damit GPS sauber erfasst werden kann.": "2. Start an outdoor workout on the watch and stay under open sky whenever possible so GPS can be recorded cleanly.",
        "3. Beende das Workout erst auf der Watch und öffne danach die iPhone-App wieder; SimpleTracking lädt Watch-Workouts beim Zurückkehren nun automatisch nach.": "3. End the workout on the watch first and then reopen the iPhone app; SimpleTracking now refreshes watch workouts automatically when you return.",
        "4. Für bessere Distanz- und Pace-Werte: iPhone Einstellungen > Datenschutz & Sicherheit > Ortungsdienste > Systemdienste > Bewegungs-kalibrierung & Distanz aktivieren und die Watch gelegentlich bei einem Outdoor Walk/Run kalibrieren.": "4. For better distance and pace accuracy: enable iPhone Settings > Privacy & Security > Location Services > System Services > Motion Calibration & Distance and occasionally calibrate the watch during an outdoor walk/run.",
        "Was auf dem iPhone aktiviert sein sollte": "What should be enabled on the iPhone",
        "SimpleTracking benötigt für sauberes Hintergrund-Tracking Standort auf „Immer“, „Genaue Position“ und möglichst aktivierte App-Aktualisierung im Hintergrund. Bitte die App während eines laufenden Workouts nicht aus dem app switcher wegwischen.": "For reliable background tracking, SimpleTracking needs location set to \"Always\", \"Precise Location\" enabled, and ideally Background App Refresh turned on. Please don't force close the app from the app switcher during a workout.",
        "iPhone prüfen": "Check iPhone",
        "Standortzugriff": "Location access",
        "Präzise Ortung": "Precise location",
        "Background App Refresh": "Background App Refresh",
        "Health-Zugriff": "Health access",
        "Aktiv": "Active",
        "Nicht aktiv": "Not active",
        "Immer erlaubt": "Always allowed",
        "Nur beim Verwenden": "While using only",
        "Nicht erlaubt": "Not allowed",
        "Unbekannt": "Unknown",
        "Voll": "Full",
        "Reduziert": "Reduced",
        "Berechtigungen aktualisieren": "Refresh permissions",
        "iPhone-Einstellungen öffnen": "Open iPhone Settings",
        "Wichtiger Hinweis": "Important note",
        "Die Watch liefert Live-Puls, Kalorien und Workout-Zeit an das iPhone. Die sichtbare GPS-Route in SimpleTracking zeichnet aktuell das iPhone auf. Wenn du die Route direkt in der App sehen willst, starte das Workout auf dem iPhone oder importiere das Watch-Workout danach aus Apple Health.": "The watch sends live heart rate, calories, and workout time to the iPhone. The visible GPS route in SimpleTracking is currently recorded by the iPhone. If you want to see the route directly inside the app, start the workout on the iPhone or import the watch workout afterward from Apple Health.",
        "Erscheinungsbild": "Appearance",
        "Sprachen": "Languages",
        "Sprache": "Language",
        "Systemsprache": "System language",
        "Einheiten": "Units",
        "Alter": "Age",
        "Jahre": "years",
        "Gewicht": "Weight",
        "Größe": "Height",
        "Profil & Score": "Profile & score",
        "Alter und Gewicht beeinflussen deinen persönlichen Fitness-Score und die Kalorienberechnung. Falls in Apple Health hinterlegt, werden Alter, Geschlecht und Gewicht automatisch von dort übernommen – die Felder hier dienen als Fallback.": "Age and weight affect your personal fitness score and calorie calculation. If Apple Health already stores age, sex, and weight, those values are used automatically - the fields here serve as a fallback.",
        "Import läuft …": "Import in progress...",
        "Alle Workouts aus Health importieren": "Import all workouts from Health",
        "Liest den gesamten Verlauf aus Apple Health": "Reads the full history from Apple Health",
        "%d importiert, davon %d mit Route": "%d imported, %d with route",
        "Quellen aus Apple Health": "Sources from Apple Health",
        "HealthKit-Berechtigungen anfordern": "Request HealthKit permissions",
        "Gesundheit": "Health",
        "Der Import liest **alle** Workouts aus Apple Health – auch die, die vorher von anderen Apps (z. B. Strava, Runtastic, Apple Workout) aufgezeichnet wurden.\n\nRouten (GPS) werden mit übernommen, sofern die Quell-App sie in Health gespeichert hat.\n\nFalls Workouts fehlen: iPhone-Einstellungen → Health → Datenzugriff & Geräte → SimpleTracking → alle Lese-Schalter (Workouts, Strecken/Routen, Distanz, Herzfrequenz, …) aktivieren und Import erneut starten.": "Import reads **all** workouts from Apple Health - including those previously recorded by other apps such as Strava, Runtastic, or Apple Workout.\n\nRoutes (GPS) are imported too if the source app stored them in Health.\n\nIf workouts are missing: iPhone Settings -> Health -> Data Access & Devices -> SimpleTracking -> enable all read toggles (workouts, routes, distance, heart rate, ...) and run the import again.",
        "Daten zurücksetzen": "Reset data",
        "Alle Workouts löschen": "Delete all workouts",
        "Alle Ernährung löschen": "Delete all nutrition entries",
        "Löscht alle von SimpleTracking in Apple Health geschriebenen Workouts bzw. alle lokal gespeicherten Ernährungs-Einträge. Kann nicht rückgängig gemacht werden.": "Deletes all workouts written by SimpleTracking to Apple Health and all locally stored nutrition entries. This can't be undone.",
        "Erfolge & Bestenlisten": "Achievements & leaderboards",
        "Mit Game Center synchronisieren": "Sync with Game Center",
        "Status": "Status",
        "Angemeldet als %@": "Signed in as %@",
        "Nicht angemeldet": "Not signed in",
        "Erfolge werden immer lokal gespeichert. Mit aktivierter Synchronisation werden sie zusätzlich an Game Center übertragen, sobald der Dienst freigeschaltet ist.": "Achievements are always stored locally. When sync is enabled, they are also sent to Game Center as soon as the service is available.",
        "Info": "Info",
        "Version": "Version",
        "Build": "Build",
        "Werbung": "Ads",
        "Wöchentliche Vollbild-Ad": "Weekly fullscreen ad",
        "Skips übrig": "Skips remaining",
        "Zuletzt gezeigt": "Last shown",
        "Ankündigung testen": "Test announcement",
        "Werbe-Status zurücksetzen": "Reset ad state",
        "Die Vollbild-Ad wird maximal einmal pro Kalenderwoche gezeigt. Vorher erscheint ein Hinweis; bis zu drei Mal pro Woche darfst du verschieben.": "The fullscreen ad is shown at most once per calendar week. A short notice appears first, and you can postpone it up to three times per week.",
        "Geladen": "Loaded",
        "Lädt": "Loading",
        "Noch nicht geladen": "Not loaded yet",
        "Simulator-Vorschau bereit": "Simulator preview ready",
        "Kein Fill": "No fill",
        "Nicht verfügbar": "Unavailable",
        "Noch nie": "Never",
        "Diese Woche bereits gezeigt": "Already shown this week",
        "Fällig, %d x überspringbar": "Due, %d skips left",
        "Fällig, nächstes Mal ohne Skip": "Due, next time without skip",
        "Name": "Name",
        "Avatar": "Avatar",
        "Foto wählen": "Choose photo",
        "Foto entfernen": "Remove photo",
        "Einstellungen": "Settings",
        "SimpleTracking": "SimpleTracking",
        "Lese Workouts aus Apple Health…": "Reading workouts from Apple Health...",
        "%d Workouts importiert – werte Details aus…": "%d workouts imported - enriching details...",
        "Details %d/%d • %@": "Details %d/%d • %@",
        "Fertig: %d Workouts (%d mit Route).": "Done: %d workouts (%d with route).",
        "%d %@ 🎉": "%d %@ 🎉"
    ]

    private static let spanish: [String: String] = [
        "Heute": "Hoy",
        "Workout": "Entrenamiento",
        "Ernährung": "Nutricion",
        "Statistiken": "Estadisticas",
        "Mehr": "Mas",
        "Schließen": "Cerrar",
        "Schritte": "Pasos",
        "Bewegung": "Movimiento",
        "Kalorien": "Calorias",
        "Energie heute": "Energia de hoy",
        "Grundbedarf": "Necesidad basal",
        "Aktivität": "Actividad",
        "Gesamtverbrauch": "Gasto total",
        "Grundbedarf bis jetzt": "Necesidad basal hasta ahora",
        "Gesamtverbrauch bis jetzt": "Gasto total hasta ahora",
        "gegen Grundbedarf": "vs basal",
        "inkl. Bewegung": "incl. movimiento",
        "Bilanz vs Grundbedarf": "Balance vs basal",
        "Bilanz inkl. Bewegung": "Balance incl. movimiento",
        "Ø Gesamt/Tag": "Prom. total/dia",
        "Ø aufgenommen": "Prom. consumido/dia",
        "Ø vs Grundbedarf": "Prom. vs basal",
        "Ø inkl. Bewegung": "Prom. incl. movimiento",
        "Bewegung = Apple-Health-Aktivkalorien aus Gehen, Schritten, Alltagsaktivität und Workouts - nicht aus Nahrung.": "Movimiento = calorias activas de Apple Health por caminar, pasos, actividad diaria y entrenamientos, no proceden de la comida.",
        "Distanz": "Distancia",
        "Energie-Bilanz heute": "Balance energetico de hoy",
        "Verbraucht": "Quemadas",
        "Aufgenommen": "Consumidas",
        "Du hast heute mehr gegessen als verbraucht.": "Hoy has comido mas de lo que has quemado.",
        "Du bist im Defizit – mehr verbraucht als gegessen.": "Estas en deficit: has quemado mas de lo que has comido.",
        "Noch keine Aktivität gemessen.": "Aun no se ha registrado actividad.",
        "Letzte Workouts": "Ultimos entrenamientos",
        "%d:%02d:%02d h": "%d:%02d:%02d h",
        "%d:%02d min": "%d:%02d min",
        "Metrisch (km)": "Metrico (km)",
        "Imperial (mi)": "Imperial (mi)",
        "System": "Sistema",
        "Hell": "Claro",
        "Dunkel": "Oscuro",
        "Untergewicht": "Bajo peso",
        "Normalgewicht": "Peso normal",
        "Übergewicht": "Sobrepeso",
        "Adipositas": "Obesidad",
        "Laufen": "Correr",
        "Gehen": "Caminar",
        "Radfahren": "Ciclismo",
        "Wandern": "Senderismo",
        "Schwimmen": "Natacion",
        "Rudern": "Remo",
        "Crosstrainer": "Eliptica",
        "Treppen": "Escaleras",
        "Yoga": "Yoga",
        "Krafttraining": "Entrenamiento de fuerza",
        "Tanzen": "Baile",
        "Fußball": "Futbol",
        "Skaten": "Patinaje",
        "Ski": "Esqui",
        "Sonstiges": "Otro",
        "Essen": "Comida",
        "Getränk": "Bebida",
        "%d %@ geschafft! 🎉": "Has completado %d %@! 🎉",
        "Tempo: %d:%02d min/km": "Ritmo: %d:%02d min/km",
        "Pace: %d:%02d min/mi": "Ritmo: %d:%02d min/mi",
        "Workout-Verlauf": "Historial de entrenamientos",
        "Zeit": "Tiempo",
        "Tempo": "Ritmo",
        "Watch: %d bpm · %d kcal": "Reloj: %d lpm · %d kcal",
        "Workout beenden": "Finalizar entrenamiento",
        "Workout starten": "Iniciar entrenamiento",
        "Tracking-Hilfe": "Guia de seguimiento",
        "Apple Watch vorbereiten": "Preparar Apple Watch",
        "Empfohlener Ablauf": "Flujo recomendado",
        "1. Öffne SimpleTracking auf der Apple Watch und bestätige die Health-Berechtigungen für Workouts, Herzfrequenz, Energie und Distanz.": "1. Abre SimpleTracking en el Apple Watch y confirma los permisos de Salud para entrenamientos, frecuencia cardiaca, energia y distancia.",
        "2. Starte auf der Watch ein Outdoor-Workout und bleibe währenddessen möglichst unter freiem Himmel, damit GPS sauber erfasst werden kann.": "2. Inicia un entrenamiento al aire libre en el reloj y procura estar a cielo abierto para que el GPS se registre bien.",
        "3. Beende das Workout erst auf der Watch und öffne danach die iPhone-App wieder; SimpleTracking lädt Watch-Workouts beim Zurückkehren nun automatisch nach.": "3. Finaliza el entrenamiento primero en el reloj y despues vuelve a abrir la app del iPhone; ahora SimpleTracking recarga automaticamente los entrenamientos del reloj al regresar.",
        "4. Für bessere Distanz- und Pace-Werte: iPhone Einstellungen > Datenschutz & Sicherheit > Ortungsdienste > Systemdienste > Bewegungs-kalibrierung & Distanz aktivieren und die Watch gelegentlich bei einem Outdoor Walk/Run kalibrieren.": "4. Para obtener mejores valores de distancia y ritmo: activa Ajustes del iPhone > Privacidad y seguridad > Localizacion > Servicios del sistema > Calibracion de movimiento y distancia y calibra el reloj de vez en cuando con una caminata o carrera al aire libre.",
        "Was auf dem iPhone aktiviert sein sollte": "Que debe estar activado en el iPhone",
        "SimpleTracking benötigt für sauberes Hintergrund-Tracking Standort auf „Immer“, „Genaue Position“ und möglichst aktivierte App-Aktualisierung im Hintergrund. Bitte die App während eines laufenden Workouts nicht aus dem app switcher wegwischen.": "Para un seguimiento en segundo plano fiable, SimpleTracking necesita la ubicacion en \"Siempre\", la ubicacion precisa activada y, si es posible, la actualizacion en segundo plano activa. No cierres la app desde el selector de apps durante un entrenamiento.",
        "iPhone prüfen": "Revisar iPhone",
        "Standortzugriff": "Acceso a la ubicacion",
        "Präzise Ortung": "Ubicacion precisa",
        "Background App Refresh": "Actualizacion en segundo plano",
        "Health-Zugriff": "Acceso a Salud",
        "Aktiv": "Activo",
        "Nicht aktiv": "No activo",
        "Immer erlaubt": "Permitido siempre",
        "Nur beim Verwenden": "Solo al usar",
        "Nicht erlaubt": "No permitido",
        "Unbekannt": "Desconocido",
        "Voll": "Completa",
        "Reduziert": "Reducida",
        "Berechtigungen aktualisieren": "Actualizar permisos",
        "iPhone-Einstellungen öffnen": "Abrir Ajustes del iPhone",
        "Wichtiger Hinweis": "Aviso importante",
        "Die Watch liefert Live-Puls, Kalorien und Workout-Zeit an das iPhone. Die sichtbare GPS-Route in SimpleTracking zeichnet aktuell das iPhone auf. Wenn du die Route direkt in der App sehen willst, starte das Workout auf dem iPhone oder importiere das Watch-Workout danach aus Apple Health.": "El reloj envia al iPhone la frecuencia cardiaca en vivo, las calorias y el tiempo del entrenamiento. La ruta GPS visible en SimpleTracking la registra actualmente el iPhone. Si quieres ver la ruta directamente en la app, inicia el entrenamiento en el iPhone o importa despues el entrenamiento del reloj desde Apple Health.",
        "Erscheinungsbild": "Apariencia",
        "Sprachen": "Idiomas",
        "Sprache": "Idioma",
        "Systemsprache": "Idioma del sistema",
        "Einheiten": "Unidades",
        "Alter": "Edad",
        "Jahre": "anos",
        "Gewicht": "Peso",
        "Größe": "Altura",
        "Profil & Score": "Perfil y puntuacion",
        "Alter und Gewicht beeinflussen deinen persönlichen Fitness-Score und die Kalorienberechnung. Falls in Apple Health hinterlegt, werden Alter, Geschlecht und Gewicht automatisch von dort übernommen – die Felder hier dienen als Fallback.": "La edad y el peso afectan a tu puntuacion de fitness y al calculo de calorias. Si Apple Health ya tiene guardados la edad, el sexo y el peso, se usaran automaticamente; estos campos sirven como alternativa.",
        "Import läuft …": "Importacion en curso...",
        "Alle Workouts aus Health importieren": "Importar todos los entrenamientos desde Health",
        "Liest den gesamten Verlauf aus Apple Health": "Lee todo el historial desde Apple Health",
        "%d importiert, davon %d mit Route": "%d importados, %d con ruta",
        "Quellen aus Apple Health": "Fuentes de Apple Health",
        "HealthKit-Berechtigungen anfordern": "Solicitar permisos de HealthKit",
        "Gesundheit": "Salud",
        "Der Import liest **alle** Workouts aus Apple Health – auch die, die vorher von anderen Apps (z. B. Strava, Runtastic, Apple Workout) aufgezeichnet wurden.\n\nRouten (GPS) werden mit übernommen, sofern die Quell-App sie in Health gespeichert hat.\n\nFalls Workouts fehlen: iPhone-Einstellungen → Health → Datenzugriff & Geräte → SimpleTracking → alle Lese-Schalter (Workouts, Strecken/Routen, Distanz, Herzfrequenz, …) aktivieren und Import erneut starten.": "La importacion lee **todos** los entrenamientos de Apple Health, incluidos los grabados antes por otras apps como Strava, Runtastic o Apple Workout.\n\nLas rutas GPS tambien se importan si la app de origen las guardo en Health.\n\nSi faltan entrenamientos: Ajustes del iPhone -> Health -> Acceso a datos y dispositivos -> SimpleTracking -> activa todos los permisos de lectura (entrenamientos, rutas, distancia, frecuencia cardiaca, ...) y vuelve a iniciar la importacion.",
        "Daten zurücksetzen": "Restablecer datos",
        "Alle Workouts löschen": "Eliminar todos los entrenamientos",
        "Alle Ernährung löschen": "Eliminar todas las entradas de nutricion",
        "Löscht alle von SimpleTracking in Apple Health geschriebenen Workouts bzw. alle lokal gespeicherten Ernährungs-Einträge. Kann nicht rückgängig gemacht werden.": "Elimina todos los entrenamientos escritos por SimpleTracking en Apple Health y todas las entradas de nutricion guardadas localmente. No se puede deshacer.",
        "Erfolge & Bestenlisten": "Logros y clasificaciones",
        "Mit Game Center synchronisieren": "Sincronizar con Game Center",
        "Status": "Estado",
        "Angemeldet als %@": "Conectado como %@",
        "Nicht angemeldet": "No conectado",
        "Erfolge werden immer lokal gespeichert. Mit aktivierter Synchronisation werden sie zusätzlich an Game Center übertragen, sobald der Dienst freigeschaltet ist.": "Los logros siempre se guardan localmente. Si la sincronizacion esta activada, tambien se enviaran a Game Center en cuanto el servicio este disponible.",
        "Info": "Info",
        "Version": "Version",
        "Build": "Build",
        "Name": "Nombre",
        "Avatar": "Avatar",
        "Foto wählen": "Elegir foto",
        "Foto entfernen": "Eliminar foto",
        "Einstellungen": "Ajustes",
        "SimpleTracking": "SimpleTracking",
        "Lese Workouts aus Apple Health…": "Leyendo entrenamientos desde Apple Health...",
        "%d Workouts importiert – werte Details aus…": "%d entrenamientos importados; procesando detalles...",
        "Details %d/%d • %@": "Detalles %d/%d • %@",
        "Fertig: %d Workouts (%d mit Route).": "Listo: %d entrenamientos (%d con ruta).",
        "%d %@ 🎉": "%d %@ 🎉"
    ]

    private static let french: [String: String] = [
        "Heute": "Aujourd'hui",
        "Workout": "Entrainement",
        "Ernährung": "Nutrition",
        "Statistiken": "Statistiques",
        "Mehr": "Plus",
        "Schließen": "Fermer",
        "Schritte": "Pas",
        "Bewegung": "Mouvement",
        "Kalorien": "Calories",
        "Energie heute": "Energie du jour",
        "Grundbedarf": "Besoin de base",
        "Aktivität": "Activite",
        "Gesamtverbrauch": "Depense totale",
        "Grundbedarf bis jetzt": "Besoin de base jusqu'ici",
        "Gesamtverbrauch bis jetzt": "Depense totale jusqu'ici",
        "gegen Grundbedarf": "vs besoin de base",
        "inkl. Bewegung": "avec mouvement",
        "Bilanz vs Grundbedarf": "Bilan vs besoin de base",
        "Bilanz inkl. Bewegung": "Bilan avec mouvement",
        "Ø Gesamt/Tag": "Moy. totale/jour",
        "Ø aufgenommen": "Moy. consommee/jour",
        "Ø vs Grundbedarf": "Moy. vs besoin de base",
        "Ø inkl. Bewegung": "Moy. avec mouvement",
        "Bewegung = Apple-Health-Aktivkalorien aus Gehen, Schritten, Alltagsaktivität und Workouts - nicht aus Nahrung.": "Le mouvement correspond aux calories actives Apple Health provenant de la marche, des pas, de l'activite quotidienne et des entrainements, pas de l'alimentation.",
        "Distanz": "Distance",
        "Energie-Bilanz heute": "Bilan energetique du jour",
        "Verbraucht": "Depensees",
        "Aufgenommen": "Consommees",
        "Du hast heute mehr gegessen als verbraucht.": "Vous avez mange plus que depense aujourd'hui.",
        "Du bist im Defizit – mehr verbraucht als gegessen.": "Vous etes en deficit : vous avez depense plus que mange.",
        "Noch keine Aktivität gemessen.": "Aucune activite enregistree pour l'instant.",
        "Letzte Workouts": "Derniers entrainements",
        "%d:%02d:%02d h": "%d:%02d:%02d h",
        "%d:%02d min": "%d:%02d min",
        "Metrisch (km)": "Metrique (km)",
        "Imperial (mi)": "Imperial (mi)",
        "System": "Systeme",
        "Hell": "Clair",
        "Dunkel": "Sombre",
        "Untergewicht": "Insuffisance ponderale",
        "Normalgewicht": "Poids normal",
        "Übergewicht": "Surpoids",
        "Adipositas": "Obesite",
        "Laufen": "Course",
        "Gehen": "Marche",
        "Radfahren": "Velo",
        "Wandern": "Randonnee",
        "Schwimmen": "Natation",
        "Rudern": "Rameur",
        "Crosstrainer": "Elliptique",
        "Treppen": "Escaliers",
        "Yoga": "Yoga",
        "Krafttraining": "Musculation",
        "Tanzen": "Danse",
        "Fußball": "Football",
        "Skaten": "Patinage",
        "Ski": "Ski",
        "Sonstiges": "Autre",
        "Essen": "Repas",
        "Getränk": "Boisson",
        "%d %@ geschafft! 🎉": "%d %@ termines ! 🎉",
        "Tempo: %d:%02d min/km": "Allure : %d:%02d min/km",
        "Pace: %d:%02d min/mi": "Allure : %d:%02d min/mi",
        "Workout-Verlauf": "Historique des entrainements",
        "Zeit": "Temps",
        "Tempo": "Allure",
        "Watch: %d bpm · %d kcal": "Montre : %d bpm · %d kcal",
        "Workout beenden": "Terminer l'entrainement",
        "Workout starten": "Demarrer l'entrainement",
        "Tracking-Hilfe": "Guide de suivi",
        "Apple Watch vorbereiten": "Preparer l'Apple Watch",
        "Empfohlener Ablauf": "Deroulement recommande",
        "1. Öffne SimpleTracking auf der Apple Watch und bestätige die Health-Berechtigungen für Workouts, Herzfrequenz, Energie und Distanz.": "1. Ouvre SimpleTracking sur l'Apple Watch et confirme les autorisations Sante pour les entrainements, la frequence cardiaque, l'energie et la distance.",
        "2. Starte auf der Watch ein Outdoor-Workout und bleibe währenddessen möglichst unter freiem Himmel, damit GPS sauber erfasst werden kann.": "2. Demarre un entrainement en exterieur sur la montre et reste si possible sous un ciel degage afin que le GPS soit enregistre correctement.",
        "3. Beende das Workout erst auf der Watch und öffne danach die iPhone-App wieder; SimpleTracking lädt Watch-Workouts beim Zurückkehren nun automatisch nach.": "3. Termine d'abord l'entrainement sur la montre puis rouvre l'app iPhone ; SimpleTracking recharge maintenant automatiquement les entrainements de la montre a ton retour.",
        "4. Für bessere Distanz- und Pace-Werte: iPhone Einstellungen > Datenschutz & Sicherheit > Ortungsdienste > Systemdienste > Bewegungs-kalibrierung & Distanz aktivieren und die Watch gelegentlich bei einem Outdoor Walk/Run kalibrieren.": "4. Pour de meilleures mesures de distance et d'allure : active Reglages de l'iPhone > Confidentialite et securite > Service de localisation > Services systeme > Etalonnage et distance, puis calibre parfois la montre pendant une marche ou une course en exterieur.",
        "Was auf dem iPhone aktiviert sein sollte": "Ce qui doit etre active sur l'iPhone",
        "SimpleTracking benötigt für sauberes Hintergrund-Tracking Standort auf „Immer“, „Genaue Position“ und möglichst aktivierte App-Aktualisierung im Hintergrund. Bitte die App während eines laufenden Workouts nicht aus dem app switcher wegwischen.": "Pour un suivi fiable en arriere-plan, SimpleTracking a besoin de la localisation sur \"Toujours\", de la localisation precise activee et idealement de l'actualisation en arriere-plan. Merci de ne pas forcer la fermeture de l'app depuis le selecteur d'apps pendant un entrainement.",
        "iPhone prüfen": "Verifier l'iPhone",
        "Standortzugriff": "Acces a la localisation",
        "Präzise Ortung": "Localisation precise",
        "Background App Refresh": "Actualisation en arriere-plan",
        "Health-Zugriff": "Acces a Sante",
        "Aktiv": "Actif",
        "Nicht aktiv": "Inactif",
        "Immer erlaubt": "Toujours autorise",
        "Nur beim Verwenden": "Seulement pendant l'utilisation",
        "Nicht erlaubt": "Non autorise",
        "Unbekannt": "Inconnu",
        "Voll": "Complete",
        "Reduziert": "Reduite",
        "Berechtigungen aktualisieren": "Actualiser les autorisations",
        "iPhone-Einstellungen öffnen": "Ouvrir Reglages de l'iPhone",
        "Wichtiger Hinweis": "Remarque importante",
        "Die Watch liefert Live-Puls, Kalorien und Workout-Zeit an das iPhone. Die sichtbare GPS-Route in SimpleTracking zeichnet aktuell das iPhone auf. Wenn du die Route direkt in der App sehen willst, starte das Workout auf dem iPhone oder importiere das Watch-Workout danach aus Apple Health.": "La montre envoie a l'iPhone la frequence cardiaque en direct, les calories et la duree de l'entrainement. La trace GPS visible dans SimpleTracking est actuellement enregistree par l'iPhone. Si tu veux voir l'itineraire directement dans l'app, demarre l'entrainement sur l'iPhone ou importe ensuite l'entrainement de la montre depuis Apple Health.",
        "Erscheinungsbild": "Apparence",
        "Sprachen": "Langues",
        "Sprache": "Langue",
        "Systemsprache": "Langue du systeme",
        "Einheiten": "Unites",
        "Alter": "Age",
        "Jahre": "ans",
        "Gewicht": "Poids",
        "Größe": "Taille",
        "Profil & Score": "Profil et score",
        "Alter und Gewicht beeinflussen deinen persönlichen Fitness-Score und die Kalorienberechnung. Falls in Apple Health hinterlegt, werden Alter, Geschlecht und Gewicht automatisch von dort übernommen – die Felder hier dienen als Fallback.": "L'age et le poids influencent ton score de forme et le calcul des calories. Si Apple Health contient deja l'age, le sexe et le poids, ces valeurs sont reprises automatiquement ; ces champs servent de secours.",
        "Import läuft …": "Import en cours...",
        "Alle Workouts aus Health importieren": "Importer tous les entrainements depuis Health",
        "Liest den gesamten Verlauf aus Apple Health": "Lit tout l'historique depuis Apple Health",
        "%d importiert, davon %d mit Route": "%d importes, dont %d avec trace",
        "Quellen aus Apple Health": "Sources depuis Apple Health",
        "HealthKit-Berechtigungen anfordern": "Demander les autorisations HealthKit",
        "Gesundheit": "Sante",
        "Der Import liest **alle** Workouts aus Apple Health – auch die, die vorher von anderen Apps (z. B. Strava, Runtastic, Apple Workout) aufgezeichnet wurden.\n\nRouten (GPS) werden mit übernommen, sofern die Quell-App sie in Health gespeichert hat.\n\nFalls Workouts fehlen: iPhone-Einstellungen → Health → Datenzugriff & Geräte → SimpleTracking → alle Lese-Schalter (Workouts, Strecken/Routen, Distanz, Herzfrequenz, …) aktivieren und Import erneut starten.": "L'import lit **tous** les entrainements d'Apple Health, y compris ceux enregistres auparavant par d'autres apps comme Strava, Runtastic ou Apple Workout.\n\nLes traces GPS sont egalement reprises si l'app source les a enregistrees dans Health.\n\nSi des entrainements manquent : Reglages de l'iPhone -> Health -> Acces aux donnees et appareils -> SimpleTracking -> active tous les interrupteurs de lecture (entrainements, traces, distance, frequence cardiaque, ...) puis relance l'import.",
        "Daten zurücksetzen": "Reinitialiser les donnees",
        "Alle Workouts löschen": "Supprimer tous les entrainements",
        "Alle Ernährung löschen": "Supprimer toutes les entrees nutritionnelles",
        "Löscht alle von SimpleTracking in Apple Health geschriebenen Workouts bzw. alle lokal gespeicherten Ernährungs-Einträge. Kann nicht rückgängig gemacht werden.": "Supprime tous les entrainements ecrits par SimpleTracking dans Apple Health ainsi que toutes les entrees nutritionnelles stockees localement. Cette action est irreversible.",
        "Erfolge & Bestenlisten": "Succes et classements",
        "Mit Game Center synchronisieren": "Synchroniser avec Game Center",
        "Status": "Statut",
        "Angemeldet als %@": "Connecte en tant que %@",
        "Nicht angemeldet": "Non connecte",
        "Erfolge werden immer lokal gespeichert. Mit aktivierter Synchronisation werden sie zusätzlich an Game Center übertragen, sobald der Dienst freigeschaltet ist.": "Les succes sont toujours stockes localement. Lorsque la synchronisation est activee, ils sont egalement envoyes vers Game Center des que le service est disponible.",
        "Info": "Infos",
        "Version": "Version",
        "Build": "Build",
        "Name": "Nom",
        "Avatar": "Avatar",
        "Foto wählen": "Choisir une photo",
        "Foto entfernen": "Supprimer la photo",
        "Einstellungen": "Reglages",
        "SimpleTracking": "SimpleTracking",
        "Lese Workouts aus Apple Health…": "Lecture des entrainements depuis Apple Health...",
        "%d Workouts importiert – werte Details aus…": "%d entrainements importes - analyse des details...",
        "Details %d/%d • %@": "Details %d/%d • %@",
        "Fertig: %d Workouts (%d mit Route).": "Termine : %d entrainements (%d avec trace).",
        "%d %@ 🎉": "%d %@ 🎉"
    ]
}

func lt(_ key: String) -> String {
    AppLocalizer.text(key)
}

func lf(_ key: String, _ args: CVarArg...) -> String {
    String(format: lt(key), locale: Locale.current, arguments: args)
}

// MARK: - UnitPreference

enum UnitPreference: String, CaseIterable, Codable {
    case metric
    case imperial

    var distanceLabel: String {
        switch self {
        case .metric:   return "km"
        case .imperial: return "mi"
        }
    }

    var notificationIntervalMeters: Double {
        switch self {
        case .metric:   return 1_000.0
        case .imperial: return 1_609.344
        }
    }

    var displayName: String {
        switch self {
        case .metric:   return lt("Metrisch (km)")
        case .imperial: return lt("Imperial (mi)")
        }
    }

    func formatted(meters: Double) -> String {
        switch self {
        case .metric:   return String(format: "%.2f km", meters / 1_000)
        case .imperial: return String(format: "%.2f mi", meters / 1_609.344)
        }
    }
}

// MARK: - AppColorScheme

enum AppColorScheme: String, CaseIterable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: return lt("System")
        case .light:  return lt("Hell")
        case .dark:   return lt("Dunkel")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }
}

// MARK: - BMI Category

enum BMICategory {
    case underweight, normal, overweight, obese

    var label: String {
        switch self {
        case .underweight: return lt("Untergewicht")
        case .normal:      return lt("Normalgewicht")
        case .overweight:  return lt("Übergewicht")
        case .obese:       return lt("Adipositas")
        }
    }

    var color: Color {
        switch self {
        case .underweight: return .blue
        case .normal:      return .green
        case .overweight:  return .orange
        case .obese:       return .red
        }
    }
}

// MARK: - UserSettings

enum ProfileAvatarPreset: String, CaseIterable, Codable {
    case person
    case walker
    case runner
    case cyclist
    case swimmer
    case hiker
    case strength
    case tennis
    case soccer
    case leaf
    case heart
    case sparkles

    var systemImage: String {
        switch self {
        case .person: return "person.fill"
        case .walker: return "figure.walk"
        case .runner: return "figure.run"
        case .cyclist: return "figure.outdoor.cycle"
        case .swimmer: return "figure.pool.swim"
        case .hiker: return "figure.hiking"
        case .strength: return "figure.strengthtraining.traditional"
        case .tennis: return "figure.tennis"
        case .soccer: return "figure.soccer"
        case .leaf: return "leaf.fill"
        case .heart: return "heart.fill"
        case .sparkles: return "sparkles"
        }
    }
}

@Observable
final class UserSettings {
    static let shared = UserSettings()

    // Appearance
    var unitPreference: UnitPreference {
        didSet { save("unitPreference", unitPreference.rawValue) }
    }
    var colorScheme: AppColorScheme {
        didSet { save("colorScheme", colorScheme.rawValue) }
    }
    var appLanguage: AppLanguage {
        didSet { save("appLanguage", appLanguage.rawValue) }
    }
    var gameCenterSyncEnabled: Bool {
        didSet { save("gameCenterSyncEnabled", gameCenterSyncEnabled) }
    }
    var profileName: String {
        didSet { save("profileName", profileName) }
    }
    var avatarPreset: ProfileAvatarPreset {
        didSet { save("avatarPreset", avatarPreset.rawValue) }
    }
    var avatarImageData: Data? {
        didSet { saveData("avatarImageData", avatarImageData) }
    }

    // Profile for Score calculation
    var ageYears: Int {
        didSet { save("ageYears", ageYears) }
    }
    var weightKg: Double {
        didSet {
            save("weightKg", weightKg)
            // Nach Health zurückschreiben, wenn sich der Wert real geändert hat.
            // Wir schreiben nur, wenn noch kein Health-Gewicht vorhanden ist
            // oder der neue Wert signifikant (>0.2 kg) abweicht — vermeidet
            // doppelte Samples beim Laden.
            if weightKg > 0, weightKg != oldValue {
                let new = weightKg
                Task { await HealthKitService.shared.writeBodyMass(kg: new) }
            }
        }
    }
    var heightCm: Double {
        didSet {
            save("heightCm", heightCm)
            if heightCm > 0, heightCm != oldValue {
                let new = heightCm
                Task { await HealthKitService.shared.writeHeight(cm: new) }
            }
        }
    }

    // Computed
    var bmi: Double {
        guard heightCm > 0 else { return 0 }
        let h = heightCm / 100
        return weightKg / (h * h)
    }

    var bmiCategory: BMICategory {
        switch bmi {
        case ..<18.5:  return .underweight
        case 18.5..<25: return .normal
        case 25..<30:  return .overweight
        default:       return .obese
        }
    }

    var profileComplete: Bool { ageYears > 0 && weightKg > 0 && heightCm > 0 }

    func ensureProfileDefaults(deviceName: String) {
        guard profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        profileName = Self.suggestedProfileName(from: deviceName)
    }

    func effectiveProfileName(fallbackName: String) -> String {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        let fallback = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? lt("SimpleTracking") : fallback
    }

    private init() {
        let ud = UserDefaults.standard
        unitPreference = UnitPreference(rawValue: ud.string(forKey: "unitPreference") ?? "") ?? .metric
        colorScheme    = AppColorScheme(rawValue: ud.string(forKey: "colorScheme") ?? "") ?? .system
        appLanguage    = AppLanguage(rawValue: ud.string(forKey: "appLanguage") ?? "") ?? .system
        gameCenterSyncEnabled = ud.bool(forKey: "gameCenterSyncEnabled")
        profileName    = ud.string(forKey: "profileName") ?? ""
        avatarPreset   = ProfileAvatarPreset(rawValue: ud.string(forKey: "avatarPreset") ?? "") ?? .person
        avatarImageData = ud.data(forKey: "avatarImageData")
        ageYears       = ud.integer(forKey: "ageYears")
        weightKg       = ud.double(forKey: "weightKg")
        heightCm       = ud.double(forKey: "heightCm")
    }

    private func save(_ key: String, _ value: some Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func saveData(_ key: String, _ value: Data?) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func suggestedProfileName(from deviceName: String) -> String {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        for suffix in ["'s iPhone", "s iPhone", " iPhone", "'s iPad", "s iPad", " iPad", "'s Apple Watch", " Apple Watch"] {
            if trimmed.hasSuffix(suffix) {
                let cleaned = trimmed.replacingOccurrences(of: suffix, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        for prefix in ["iPhone von ", "iPad von "] where trimmed.hasPrefix(prefix) {
            let cleaned = trimmed.replacingOccurrences(of: prefix, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }

        return trimmed
    }
}
