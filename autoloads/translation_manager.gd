extends Node

## Manages i18n — registers translations with Godot's TranslationServer.
## Use tr("English text") everywhere; TranslationServer resolves by locale.

const LANGUAGES := ["en", "es", "ja"]
const LANGUAGE_NAMES := {"en": "English", "es": "Español", "ja": "日本語"}

signal language_changed


func _ready() -> void:
	_register_translations()
	_load_saved_locale()


func set_language(locale: String) -> void:
	TranslationServer.set_locale(locale)
	_save_locale(locale)
	language_changed.emit()


func get_language() -> String:
	return TranslationServer.get_locale()


func _load_saved_locale() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		var locale: String = cfg.get_value("settings", "locale", "en")
		TranslationServer.set_locale(locale)


func _save_locale(locale: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("settings", "locale", locale)
	cfg.save("user://settings.cfg")


func _register_translations() -> void:
	var es := Translation.new()
	es.locale = "es"
	for key in _ES:
		es.add_message(key, _ES[key])
	TranslationServer.add_translation(es)

	var ja := Translation.new()
	ja.locale = "ja"
	for key in _JA:
		ja.add_message(key, _JA[key])
	TranslationServer.add_translation(ja)


# ── Spanish ────────────────────────────────────────────────────────────────────
var _ES: Dictionary = {
	# General UI
	"Continue": "Continuar",
	"Close": "Cerrar",
	"Back": "Atrás",
	"Player": "Jugador",
	"Unknown": "Desconocido",
	"Object": "Objeto",
	"Hero": "Héroe",
	"Item": "Objeto",

	# HUD
	"Lv %d": "Nv %d",
	"Town": "Pueblo",
	"Floor %d": "Piso %d",
	"Town Portal": "Portal del pueblo",
	"Respawn (%d)": "Revivir (%d)",
	"Respawn": "Revivir",
	"Level %d": "Nivel %d",

	# Character panel
	"Character": "Personaje",
	"Name": "Nombre",
	"Class": "Clase",
	"Level": "Nivel",
	"Experience": "Experiencia",
	"Health": "Salud",
	"Mana": "Maná",
	"Strength": "Fuerza",
	"Dexterity": "Destreza",
	"Intelligence": "Inteligencia",
	"Vitality": "Vitalidad",
	"Attack Damage": "Daño de ataque",
	"Attack Speed": "Vel. de ataque",
	"Defense": "Defensa",
	"Move Speed": "Velocidad",

	# Action buttons
	"Skills": "Habilidades",
	"Inventory": "Inventario",
	"Quests": "Misiones",

	# Quest panel
	"Quest Log": "Registro de misiones",
	"No active quests.\nTalk to NPCs in town to find quests.": "No hay misiones activas.\nHabla con los NPCs del pueblo.",
	"COMPLETE — Return to NPC": "COMPLETA — Regresa al NPC",
	"Progress: %d / %d": "Progreso: %d / %d",
	"Rewards: %d Gold, %d XP": "Recompensas: %d oro, %d XP",
	"Turn In": "Entregar",
	"Accept": "Aceptar",
	"[COMPLETE]": "[COMPLETA]",
	"Quest Complete! +%d Gold +%d XP": "¡Misión completa! +%d oro +%d XP",

	# Inventory
	"Gold: 0": "Oro: 0",
	"Gold: %d": "Oro: %d",
	"Shop": "Tienda",
	"Slot: %s": "Ranura: %s",
	"Price: %d gold": "Precio: %d oro",
	"+%.0f Damage": "+%.0f Daño",
	"+%.0f Defense": "+%.0f Defensa",
	"+%.0f Health": "+%.0f Salud",
	"+%.0f Mana": "+%.0f Maná",
	"+%d Strength": "+%d Fuerza",
	"+%d Dexterity": "+%d Destreza",
	"+%d Intelligence": "+%d Inteligencia",
	"Heals %.0f HP": "Cura %.0f HP",
	"Restores %.0f Mana": "Restaura %.0f Maná",
	"Left-click drag to buy\nRight-click to quick buy": "Clic izquierdo para comprar\nClic derecho compra rápida",
	"Sell: %d gold": "Vender: %d oro",
	"Drag to shop or right-click to sell": "Arrastra a la tienda o clic derecho para vender",

	# Equipment slots
	"Weapon": "Arma",
	"Helmet": "Casco",
	"Chest": "Pecho",
	"Boots": "Botas",
	"Ring": "Anillo",
	"Amulet": "Amuleto",
	"Shield": "Escudo",
	"Chest Armor": "Armadura",
	"Consumable": "Consumible",
	"Misc": "Misceláneo",

	# Character creator
	"Create Character": "Crear personaje",
	"Choose Class": "Elige clase",
	"Customize": "Personalizar",
	"Enter character name": "Nombre del personaje",
	"Color Theme": "Tema de color",
	"Body Shape": "Forma del cuerpo",
	"Size": "Tamaño",
	"Warrior": "Guerrero",
	"A stalwart champion clad in heavy armor. Excels in melee combat with devastating attacks and high defense. Wields a sword and shield.": "Un campeón valiente con armadura pesada. Destaca en combate cuerpo a cuerpo con ataques devastadores y alta defensa. Empuña espada y escudo.",
	"Mage": "Mago",
	"A master of the arcane arts. Calls upon devastating spell power to obliterate foes from range. Wields a staff tipped with a glowing orb.": "Un maestro de las artes arcanas. Invoca poder mágico devastador para destruir enemigos a distancia. Empuña un bastón con un orbe brillante.",
	"Rogue": "Pícaro",
	"A swift and cunning fighter striking from the shadows. Relies on speed and precision with dual daggers. Nimble movement and fast attacks.": "Un luchador veloz y astuto que ataca desde las sombras. Confía en velocidad y precisión con dagas dobles. Movimiento ágil y ataques rápidos.",
	"Crimson": "Carmesí",
	"Azure": "Azur",
	"Gold": "Oro",
	"Obsidian": "Obsidiana",
	"Arcane": "Arcano",
	"Frost": "Escarcha",
	"Ember": "Brasa",
	"Nature": "Naturaleza",
	"Shadow": "Sombra",
	"Forest": "Bosque",
	"Blood": "Sangre",
	"Sand": "Arena",
	"Stocky": "Robusto",
	"Athletic": "Atlético",
	"Towering": "Imponente",
	"Slender": "Esbelto",
	"Average": "Promedio",
	"Broad": "Ancho",
	"Lithe": "Ágil",
	"Balanced": "Equilibrado",
	"Muscular": "Musculoso",
	"Small": "Pequeño",
	"Medium": "Mediano",
	"Large": "Grande",

	# Character select
	"No characters yet — create one!": "¡Aún no hay personajes — crea uno!",

	# Main menu
	"Offline Mode — LAN Play": "Modo sin conexión — Juego LAN",
	"Hosting game...": "Alojando juego...",
	"Failed to host game!": "¡Error al alojar!",
	"Connecting to %s...": "Conectando a %s...",
	"Failed to connect!": "¡Error al conectar!",
	"Connection failed. Try again.": "Conexión fallida. Inténtalo de nuevo.",

	# Login screen
	"Enter username and password.": "Introduce tu usuario y contraseña.",
	"Logging in...": "Iniciando sesión...",
	"Fill in all fields.": "Completa todos los campos.",
	"Password must be at least 6 characters.": "La contraseña debe tener al menos 6 caracteres.",
	"Creating account...": "Creando cuenta...",

	# Lobby
	"Normal": "Normal",
	"Nightmare": "Pesadilla",
	"Hell": "Infierno",
	"Welcome, %s!": "¡Bienvenido, %s!",
	"No character selected": "No hay personaje seleccionado",
	"Lv.%d %s | Gold: %d": "Nv.%d %s | Oro: %d",
	"Select a character first!": "¡Selecciona un personaje primero!",
	"%s's Game": "Partida de %s",
	"Creating game...": "Creando partida...",
	"Joining game...": "Uniéndose a la partida...",
	"Connecting to game server...": "Conectando al servidor...",
	"Connection to game server failed.": "Conexión al servidor fallida.",
	"Connected to lobby.": "Conectado al lobby.",
	"Disconnected from lobby.": "Desconectado del lobby.",

	# Escape menu
	"MENU": "MENÚ",
	"Resume": "Reanudar",
	"Options": "Opciones",
	"Debug Menu": "Menú de depuración",
	"Return to Title": "Volver al título",
	"Quit Game": "Salir del juego",
	"OPTIONS": "OPCIONES",
	"Master Volume": "Volumen general",
	"Music Volume": "Volumen de música",
	"SFX Volume": "Volumen de efectos",
	"Camera Speed": "Velocidad de cámara",
	"Fullscreen": "Pantalla completa",
	"V-Sync": "V-Sync",
	"DEBUG MENU": "MENÚ DE DEPURACIÓN",
	"Debug build only — hidden in production": "Solo en compilación de depuración",
	"Invincible": "Invencible",
	"Reveal Entire Minimap": "Revelar todo el minimapa",
	"+1000 Gold": "+1000 Oro",
	"+1000 XP": "+1000 XP",
	"Full Heal + Mana": "Curación completa + Maná",
	"Kill Nearby Enemies": "Matar enemigos cercanos",
	"Complete Active Quests": "Completar misiones activas",
	"Level Up": "Subir de nivel",
	"Go Floor Down": "Bajar un piso",
	"Go Floor Up": "Subir un piso",

	# Skill tree
	"Skill Tree": "Árbol de habilidades",
	"Skill Points: 0": "Puntos: 0",
	"Skill Points: %d": "Puntos: %d",
	"%s Skill Tree": "Árbol de %s",
	"Branch": "Rama",
	"Rank: %d / %d": "Rango: %d / %d",
	"Unlocks: %s": "Desbloquea: %s",
	"%s: +%s per rank": "%s: +%s por rango",
	"Requires: %s": "Requiere: %s",

	# Levels — town
	"Dungeon Entrance": "Entrada a la mazmorra",
	"Click to enter dungeon": "Clic para entrar a la mazmorra",
	"Enter Dungeon": "Entrar a la mazmorra",
	"Town Hall": "Ayuntamiento",
	"Marketplace": "Mercado",
	"Alchemist": "Alquimista",
	"Tavern": "Taberna",
	"General Store": "Tienda general",
	"Residence": "Residencia",
	"Blacksmith": "Herrero",
	"Healer": "Curandero",
	"Jeweler": "Joyero",
	"Fruit Stall": "Puesto de frutas",
	"Weapon Stall": "Puesto de armas",
	"Armor Stall": "Puesto de armadura",
	"Guard Tower": "Torre de guardia",

	# Levels — dungeon
	"Return to Town": "Volver al pueblo",
	"Stairs Up (Floor %d)": "Escaleras arriba (Piso %d)",
	"BOSS GUARDS THIS PASSAGE": "UN JEFE CUSTODIA ESTE PASAJE",
	"Stairs Down (Floor %d)": "Escaleras abajo (Piso %d)",
	"Click to use stairs": "Clic para usar escaleras",
	"Stairs": "Escaleras",

	# NPCs
	"Villager": "Aldeano",
	"Click to talk": "Clic para hablar",
	"Click to shop": "Clic para comprar",

	# Fountain
	"Fountain": "Fuente",
	"Click to restore Health & Mana": "Clic para restaurar Salud y Maná",

	# Loot
	"Loot": "Botín",
	"Click to pick up": "Clic para recoger",
	"Click to enter portal": "Clic para entrar al portal",
	"Treasure Chest": "Cofre del tesoro",
	"Click to open": "Clic para abrir",
	"Empty Chest": "Cofre vacío",

	# Player floating text
	"LEVEL UP!": "¡SUBIDA DE NIVEL!",
	"Inventory Full!": "¡Inventario lleno!",
	"+ %d Gold": "+ %d Oro",
	"+%d XP": "+%d XP",
	"No Mana!": "¡Sin maná!",
	"+%d HP": "+%d HP",

	# Online manager
	"Login failed (server unreachable)": "Error de inicio de sesión (servidor inaccesible)",
	"Login failed": "Error de inicio de sesión",
	"Registration failed (server unreachable)": "Error de registro (servidor inaccesible)",
	"Registration failed": "Error de registro",

	# Items
	"Rusty Sword": "Espada oxidada",
	"Iron Axe": "Hacha de hierro",
	"Steel Mace": "Maza de acero",
	"War Hammer": "Martillo de guerra",
	"Shadow Blade": "Hoja de sombra",
	"Flame Dagger": "Daga de llamas",
	"Leather Cap": "Gorro de cuero",
	"Iron Helm": "Casco de hierro",
	"Plate Helm": "Casco de placas",
	"Crown of Thorns": "Corona de espinas",
	"Cloth Tunic": "Túnica de tela",
	"Chainmail": "Cota de malla",
	"Plate Armor": "Armadura de placas",
	"Shadow Vestments": "Vestiduras de sombra",
	"Sandals": "Sandalias",
	"Iron Boots": "Botas de hierro",
	"Greaves": "Grebas",
	"Windwalkers": "Caminantes del viento",
	"Health Potion": "Poción de salud",
	"Mana Potion": "Poción de maná",

	# Quests
	"Thin the Herd": "Reducir la manada",
	"Slay 10 creatures in the dungeon.": "Mata 10 criaturas en la mazmorra.",
	"Grunt Cleanup": "Limpieza de grunts",
	"Kill 5 Grunts lurking in the depths.": "Mata 5 Grunts en las profundidades.",
	"Silence the Casters": "Silenciar a los hechiceros",
	"Defeat 3 enemy Mages.": "Derrota a 3 Magos enemigos.",
	"Brute Force": "Fuerza bruta",
	"Take down 3 Brutes.": "Derriba a 3 Brutos.",
	"Dungeon Sweep": "Barrida de mazmorra",
	"Slay 25 creatures of any kind.": "Mata 25 criaturas de cualquier tipo.",

	# Enemy types
	"Grunt": "Esbirro",
	"Brute": "Bruto",
	"Skeleton": "Esqueleto",
	"Spider": "Araña",
	"Ghost": "Fantasma",
	"Archer": "Arquero",
	"Shaman": "Chamán",
	"Golem": "Gólem",
	"Scarab": "Escarabajo",
	"Wraith": "Espectro",
	"Necromancer": "Nigromante",
	"Demon": "Demonio",
	"Boss Golem": "Jefe Gólem",
	"Boss Demon": "Jefe Demonio",
	"Boss Dragon": "Jefe Dragón",

	# Skill branches
	"Arms": "Armas",
	"Weapon mastery and raw damage.": "Maestría de armas y daño bruto.",
	"Valor": "Valor",
	"Toughness and survivability.": "Dureza y supervivencia.",
	"Warcry": "Grito de guerra",
	"Buffs, battle shouts, and auras.": "Mejoras, gritos de guerra y auras.",
	"Fire": "Fuego",
	"Fire spells and burst damage.": "Hechizos de fuego y daño explosivo.",
	"Slows, freezes, and area denial.": "Ralentización, congelamiento y control de área.",
	"Mana mastery, shields, and teleportation.": "Maestría de maná, escudos y teletransporte.",
	"Assassination": "Asesinato",
	"Burst damage, crits, and poisons.": "Daño explosivo, críticos y venenos.",
	"Stealth, evasion, and mobility.": "Sigilo, evasión y movilidad.",
	"Traps": "Trampas",
	"Traps, bleeds, and debuffs.": "Trampas, sangrado y debuffs.",

	# Skill tree nodes — Warrior Arms
	"Sharpened Blade": "Hoja afilada",
	"+4 Attack Damage per rank.": "+4 de daño de ataque por rango.",
	"Cleave": "Hendidura",
	"Unlocks Cleave: Slash in an arc, hitting all enemies in front.": "Desbloquea Hendidura: Golpea en arco a todos los enemigos al frente.",
	"Deep Wounds": "Heridas profundas",
	"+5% critical damage per rank.": "+5% de daño crítico por rango.",
	"Brutal Strike": "Golpe brutal",
	"+3% critical chance per rank.": "+3% de probabilidad crítica por rango.",
	"Whirlwind": "Torbellino",
	"Unlocks Whirlwind: Spin and damage all nearby enemies.": "Desbloquea Torbellino: Gira y daña a todos los enemigos cercanos.",
	"Executioner": "Ejecutor",
	"+8 Attack Damage, +5% crit damage per rank.": "+8 daño, +5% daño crítico por rango.",

	# Skill tree nodes — Warrior Valor
	"Tough Skin": "Piel dura",
	"+3 Defense per rank.": "+3 de defensa por rango.",
	"Shield Wall": "Muro de escudos",
	"Unlocks Shield Wall: Block all damage for 3 seconds.": "Desbloquea Muro de escudos: Bloquea todo el daño durante 3 segundos.",
	"+15 Max Health per rank.": "+15 de salud máxima por rango.",
	"Iron Will": "Voluntad de hierro",
	"+5 Defense, +10 Max Health per rank.": "+5 defensa, +10 salud máxima por rango.",
	"Ground Slam": "Golpe al suelo",
	"Unlocks Ground Slam: Slam the ground, stunning nearby enemies.": "Desbloquea Golpe al suelo: Golpea el suelo, aturdiendo enemigos cercanos.",
	"Unbreakable": "Inquebrantable",
	"+8 Defense, +20 Max Health per rank.": "+8 defensa, +20 salud máxima por rango.",

	# Skill tree nodes — Warrior Warcry
	"Battle Shout": "Grito de batalla",
	"+2 Strength per rank.": "+2 de fuerza por rango.",
	"War Cry": "Grito de guerra",
	"Unlocks War Cry: Boost damage of nearby allies for 8s.": "Desbloquea Grito de guerra: Aumenta el daño de aliados cercanos durante 8s.",
	"Bloodlust": "Sed de sangre",
	"+5% Attack Speed per rank.": "+5% velocidad de ataque por rango.",
	"Charge": "Carga",
	"Unlocks Charge: Rush forward and stun the first enemy hit.": "Desbloquea Carga: Avanza y aturde al primer enemigo.",
	"Veteran": "Veterano",
	"+3 to Strength and Vitality per rank.": "+3 de fuerza y vitalidad por rango.",
	"Berserker Rage": "Furia berserker",
	"Unlocks Berserker Rage: Greatly boost damage but take more damage for 10s.": "Desbloquea Furia berserker: Aumenta el daño pero recibes más daño durante 10s.",

	# Skill tree nodes — Mage Fire
	"Ignite": "Ignición",
	"+3 Intelligence per rank.": "+3 de inteligencia por rango.",
	"Fireball": "Bola de fuego",
	"Unlocks Fireball: Hurl a ball of fire at a target area.": "Desbloquea Bola de fuego: Lanza una bola de fuego al área objetivo.",
	"Searing Heat": "Calor abrasador",
	"+6% spell damage per rank.": "+6% de daño mágico por rango.",
	"Fire Wall": "Muro de fuego",
	"Unlocks Fire Wall: Create a wall of flame that damages enemies passing through.": "Desbloquea Muro de fuego: Crea un muro de llamas que daña a los enemigos.",
	"Pyromaniac": "Pirómano",
	"+4 Intelligence, +5% spell damage per rank.": "+4 inteligencia, +5% daño mágico por rango.",
	"Meteor": "Meteoro",
	"Unlocks Meteor: Call down a devastating meteor on a target area.": "Desbloquea Meteoro: Invoca un meteoro devastador sobre el área objetivo.",

	# Skill tree nodes — Mage Frost
	"Chilling Touch": "Toque gélido",
	"+2 Intelligence, +5 Max Mana per rank.": "+2 inteligencia, +5 maná máximo por rango.",
	"Frost Nova": "Nova de escarcha",
	"Unlocks Frost Nova: Blast frost around you, damaging and slowing enemies.": "Desbloquea Nova de escarcha: Dispara escarcha alrededor, dañando y ralentizando.",
	"Hypothermia": "Hipotermia",
	"+4% spell damage, +8 Max Mana per rank.": "+4% daño mágico, +8 maná máximo por rango.",
	"Ice Barrier": "Barrera de hielo",
	"Unlocks Ice Barrier: Shield yourself in ice, absorbing damage for 5s.": "Desbloquea Barrera de hielo: Protégete con hielo, absorbiendo daño durante 5s.",
	"Permafrost": "Permafrost",
	"+3 Intelligence, +10 Max Mana per rank.": "+3 inteligencia, +10 maná máximo por rango.",
	"Blizzard": "Ventisca",
	"Unlocks Blizzard: Summon a blizzard that rains ice on an area for 6s.": "Desbloquea Ventisca: Invoca una ventisca de hielo sobre un área durante 6s.",

	# Skill tree nodes — Mage Arcane
	"Mana Flow": "Flujo de maná",
	"+8 Max Mana per rank.": "+8 de maná máximo por rango.",
	"Arcane Missiles": "Misiles arcanos",
	"Unlocks Arcane Missiles: Fire a rapid volley of arcane bolts.": "Desbloquea Misiles arcanos: Dispara una ráfaga de rayos arcanos.",
	"Meditation": "Meditación",
	"+5% mana regen speed per rank.": "+5% regeneración de maná por rango.",
	"Teleport": "Teletransporte",
	"Unlocks Teleport: Instantly blink to a target location.": "Desbloquea Teletransporte: Teletranspórtate a una ubicación objetivo.",
	"Arcane Mastery": "Maestría arcana",
	"+4 Intelligence, -5% mana cost per rank.": "+4 inteligencia, -5% costo de maná por rango.",
	"Mana Shield": "Escudo de maná",
	"Unlocks Mana Shield: Convert damage taken to mana cost for 10s.": "Desbloquea Escudo de maná: Convierte el daño en costo de maná durante 10s.",

	# Skill tree nodes — Rogue Assassination
	"Lethality": "Letalidad",
	"+3 Dexterity per rank.": "+3 de destreza por rango.",
	"Backstab": "Puñalada",
	"Unlocks Backstab: Teleport behind an enemy and deal massive damage.": "Desbloquea Puñalada: Teletranspórtate detrás del enemigo y causa daño masivo.",
	"Twist the Knife": "Retorcer la hoja",
	"Poison Blade": "Hoja envenenada",
	"Unlocks Poison Blade: Coat your weapons in poison, adding DoT to attacks.": "Desbloquea Hoja envenenada: Cubre tus armas con veneno, añadiendo daño continuado.",
	"Cold Blood": "Sangre fría",
	"+6% critical damage, +3 Dexterity per rank.": "+6% daño crítico, +3 destreza por rango.",
	"Death Mark": "Marca de muerte",
	"Unlocks Death Mark: Mark an enemy to take 50% more damage for 6s.": "Desbloquea Marca de muerte: Marca a un enemigo para +50% daño recibido durante 6s.",

	# Skill tree nodes — Rogue Shadow
	"Nimble Feet": "Pies ágiles",
	"+0.5 Move Speed per rank.": "+0.5 velocidad por rango.",
	"Shadow Step": "Paso de sombra",
	"Unlocks Shadow Step: Dash through shadows to a target location.": "Desbloquea Paso de sombra: Avanza entre sombras a la ubicación objetivo.",
	"Evasion": "Evasión",
	"+4% dodge chance per rank.": "+4% probabilidad de esquivar por rango.",
	"Vanish": "Desvanecimiento",
	"Unlocks Vanish: Become invisible for 4s, next attack deals bonus damage.": "Desbloquea Desvanecimiento: Invisible durante 4s, el siguiente ataque causa daño extra.",
	"Fleet Footed": "Pies ligeros",
	"+0.5 Move Speed, +3% dodge per rank.": "+0.5 velocidad, +3% esquivar por rango.",
	"Smoke Bomb": "Bomba de humo",
	"Unlocks Smoke Bomb: Throw a smoke bomb, blinding enemies in the area.": "Desbloquea Bomba de humo: Lanza una bomba de humo, cegando enemigos.",

	# Skill tree nodes — Rogue Traps
	"Cunning": "Astucia",
	"+2 Dexterity, +2 Intelligence per rank.": "+2 destreza, +2 inteligencia por rango.",
	"Spike Trap": "Trampa de pinchos",
	"Unlocks Spike Trap: Place a trap that damages and slows enemies.": "Desbloquea Trampa de pinchos: Coloca una trampa que daña y ralentiza.",
	"Serrated Edges": "Filos dentados",
	"Fan of Knives": "Abanico de cuchillos",
	"Unlocks Fan of Knives: Throw knives in all directions.": "Desbloquea Abanico de cuchillos: Lanza cuchillos en todas direcciones.",
	"Resourceful": "Ingenioso",
	"+3 Dexterity, +4 Attack Damage per rank.": "+3 destreza, +4 daño de ataque por rango.",
	"Rain of Arrows": "Lluvia de flechas",
	"Unlocks Rain of Arrows: Shower a target area with arrows for 4s.": "Desbloquea Lluvia de flechas: Llueve flechas sobre el área durante 4s.",

	# Skill definitions (short descriptions)
	"Slash in an arc, hitting all enemies in front.": "Golpea en arco a todos los enemigos al frente.",
	"Spin and damage all nearby enemies.": "Gira y daña a todos los enemigos cercanos.",
	"Block all damage for 3 seconds.": "Bloquea todo el daño durante 3 segundos.",
	"Slam the ground, stunning nearby enemies.": "Golpea el suelo, aturdiendo enemigos cercanos.",
	"Boost damage of nearby allies for 8s.": "Aumenta el daño de aliados cercanos durante 8s.",
	"Rush forward and stun the first enemy hit.": "Avanza y aturde al primer enemigo.",
	"Greatly boost damage but take more damage for 10s.": "Aumenta el daño pero recibes más daño durante 10s.",
	"Hurl a ball of fire at a target area.": "Lanza una bola de fuego al área objetivo.",
	"Create a wall of flame that damages enemies passing through.": "Crea un muro de llamas que daña a los enemigos.",
	"Call down a devastating meteor on a target area.": "Invoca un meteoro devastador sobre el área.",
	"Blast frost around you, damaging and slowing enemies.": "Dispara escarcha alrededor, dañando y ralentizando.",
	"Shield yourself in ice, absorbing damage for 5s.": "Protégete con hielo, absorbiendo daño durante 5s.",
	"Summon a blizzard that rains ice on an area for 6s.": "Invoca una ventisca de hielo sobre un área durante 6s.",
	"Fire a rapid volley of arcane bolts.": "Dispara una ráfaga de rayos arcanos.",
	"Instantly blink to a target location.": "Teletranspórtate a una ubicación objetivo.",
	"Convert damage taken to mana cost for 10s.": "Convierte el daño en costo de maná durante 10s.",
	"Teleport behind an enemy and deal massive damage.": "Teletranspórtate detrás del enemigo y causa daño masivo.",
	"Coat your weapons in poison, adding DoT to attacks.": "Cubre tus armas con veneno, añadiendo daño continuado.",
	"Mark an enemy to take 50% more damage for 6s.": "Marca a un enemigo para +50% daño recibido durante 6s.",
	"Dash through shadows to a target location.": "Avanza entre sombras a la ubicación objetivo.",
	"Become invisible for 4s, next attack deals bonus damage.": "Invisible durante 4s, el siguiente ataque causa daño extra.",
	"Throw a smoke bomb, blinding enemies in the area.": "Lanza una bomba de humo, cegando enemigos.",
	"Place a trap that damages and slows enemies.": "Coloca una trampa que daña y ralentiza.",
	"Throw knives in all directions.": "Lanza cuchillos en todas direcciones.",
	"Shower a target area with arrows for 4s.": "Llueve flechas sobre el área durante 4s.",
	"Heal": "Curar",
	"Restore health.": "Restaura salud.",

	# Language selector
	"Language": "Idioma",
}


# ── Japanese ───────────────────────────────────────────────────────────────────
var _JA: Dictionary = {
	# General UI
	"Continue": "続ける",
	"Close": "閉じる",
	"Back": "戻る",
	"Player": "プレイヤー",
	"Unknown": "不明",
	"Object": "オブジェクト",
	"Hero": "英雄",
	"Item": "アイテム",

	# HUD
	"Lv %d": "Lv %d",
	"Town": "町",
	"Floor %d": "%d階",
	"Town Portal": "タウンポータル",
	"Respawn (%d)": "復活 (%d)",
	"Respawn": "復活",
	"Level %d": "レベル %d",

	# Character panel
	"Character": "キャラクター",
	"Name": "名前",
	"Class": "クラス",
	"Level": "レベル",
	"Experience": "経験値",
	"Health": "体力",
	"Mana": "マナ",
	"Strength": "筋力",
	"Dexterity": "器用さ",
	"Intelligence": "知力",
	"Vitality": "活力",
	"Attack Damage": "攻撃力",
	"Attack Speed": "攻撃速度",
	"Defense": "防御力",
	"Move Speed": "移動速度",

	# Action buttons
	"Skills": "スキル",
	"Inventory": "インベントリ",
	"Quests": "クエスト",

	# Quest panel
	"Quest Log": "クエストログ",
	"No active quests.\nTalk to NPCs in town to find quests.": "アクティブなクエストなし。\n町のNPCに話しかけよう。",
	"COMPLETE — Return to NPC": "完了 — NPCに戻る",
	"Progress: %d / %d": "進捗: %d / %d",
	"Rewards: %d Gold, %d XP": "報酬: %dゴールド, %d XP",
	"Turn In": "納品",
	"Accept": "受諾",
	"[COMPLETE]": "[完了]",
	"Quest Complete! +%d Gold +%d XP": "クエスト完了! +%dゴールド +%d XP",

	# Inventory
	"Gold: 0": "ゴールド: 0",
	"Gold: %d": "ゴールド: %d",
	"Shop": "ショップ",
	"Slot: %s": "スロット: %s",
	"Price: %d gold": "価格: %dゴールド",
	"+%.0f Damage": "+%.0f ダメージ",
	"+%.0f Defense": "+%.0f 防御",
	"+%.0f Health": "+%.0f 体力",
	"+%.0f Mana": "+%.0f マナ",
	"+%d Strength": "+%d 筋力",
	"+%d Dexterity": "+%d 器用さ",
	"+%d Intelligence": "+%d 知力",
	"Heals %.0f HP": "%.0f HP回復",
	"Restores %.0f Mana": "マナ%.0f回復",
	"Left-click drag to buy\nRight-click to quick buy": "左クリックで購入\n右クリックでクイック購入",
	"Sell: %d gold": "売却: %dゴールド",
	"Drag to shop or right-click to sell": "ショップにドラッグまたは右クリックで売却",

	# Equipment slots
	"Weapon": "武器",
	"Helmet": "兜",
	"Chest": "胸",
	"Boots": "ブーツ",
	"Ring": "指輪",
	"Amulet": "お守り",
	"Shield": "盾",
	"Chest Armor": "鎧",
	"Consumable": "消耗品",
	"Misc": "その他",

	# Character creator
	"Create Character": "キャラクター作成",
	"Choose Class": "クラス選択",
	"Customize": "カスタマイズ",
	"Enter character name": "キャラクター名を入力",
	"Color Theme": "カラーテーマ",
	"Body Shape": "体型",
	"Size": "サイズ",
	"Warrior": "戦士",
	"A stalwart champion clad in heavy armor. Excels in melee combat with devastating attacks and high defense. Wields a sword and shield.": "重装鎧をまとった勇敢な戦士。圧倒的な攻撃力と高い防御力で近接戦を制する。剣と盾を装備。",
	"Mage": "魔法使い",
	"A master of the arcane arts. Calls upon devastating spell power to obliterate foes from range. Wields a staff tipped with a glowing orb.": "秘術の達人。壊滅的な魔力で遠距離から敵を殲滅する。輝くオーブ付きの杖を装備。",
	"Rogue": "盗賊",
	"A swift and cunning fighter striking from the shadows. Relies on speed and precision with dual daggers. Nimble movement and fast attacks.": "影から襲う素早く狡猾な戦士。二刀流のダガーで速度と精度を武器にする。素早い動きと高速攻撃。",
	"Crimson": "紅蓮",
	"Azure": "蒼天",
	"Gold": "黄金",
	"Obsidian": "黒曜石",
	"Arcane": "秘術",
	"Frost": "氷結",
	"Ember": "残り火",
	"Nature": "自然",
	"Shadow": "影",
	"Forest": "森",
	"Blood": "血",
	"Sand": "砂",
	"Stocky": "がっしり",
	"Athletic": "アスレチック",
	"Towering": "巨漢",
	"Slender": "細身",
	"Average": "普通",
	"Broad": "幅広",
	"Lithe": "しなやか",
	"Balanced": "バランス",
	"Muscular": "筋肉質",
	"Small": "小",
	"Medium": "中",
	"Large": "大",

	# Character select
	"No characters yet — create one!": "まだキャラクターがいません — 作成しましょう！",

	# Main menu
	"Offline Mode — LAN Play": "オフライン — LAN対戦",
	"Hosting game...": "ゲームをホスト中...",
	"Failed to host game!": "ホストに失敗！",
	"Connecting to %s...": "%sに接続中...",
	"Failed to connect!": "接続に失敗！",
	"Connection failed. Try again.": "接続失敗。もう一度お試しください。",

	# Login screen
	"Enter username and password.": "ユーザー名とパスワードを入力。",
	"Logging in...": "ログイン中...",
	"Fill in all fields.": "すべて入力してください。",
	"Password must be at least 6 characters.": "パスワードは6文字以上。",
	"Creating account...": "アカウント作成中...",

	# Lobby
	"Normal": "ノーマル",
	"Nightmare": "ナイトメア",
	"Hell": "ヘル",
	"Welcome, %s!": "ようこそ、%s！",
	"No character selected": "キャラクター未選択",
	"Lv.%d %s | Gold: %d": "Lv.%d %s | ゴールド: %d",
	"Select a character first!": "まずキャラクターを選択！",
	"%s's Game": "%sのゲーム",
	"Creating game...": "ゲーム作成中...",
	"Joining game...": "ゲームに参加中...",
	"Connecting to game server...": "ゲームサーバーに接続中...",
	"Connection to game server failed.": "ゲームサーバーへの接続失敗。",
	"Connected to lobby.": "ロビーに接続。",
	"Disconnected from lobby.": "ロビーから切断。",

	# Escape menu
	"MENU": "メニュー",
	"Resume": "再開",
	"Options": "オプション",
	"Debug Menu": "デバッグメニュー",
	"Return to Title": "タイトルに戻る",
	"Quit Game": "ゲーム終了",
	"OPTIONS": "オプション",
	"Master Volume": "マスター音量",
	"Music Volume": "BGM音量",
	"SFX Volume": "SE音量",
	"Camera Speed": "カメラ速度",
	"Fullscreen": "フルスクリーン",
	"V-Sync": "V-Sync",
	"DEBUG MENU": "デバッグメニュー",
	"Debug build only — hidden in production": "デバッグビルド限定",
	"Invincible": "無敵",
	"Reveal Entire Minimap": "ミニマップ全体表示",
	"+1000 Gold": "+1000 ゴールド",
	"+1000 XP": "+1000 XP",
	"Full Heal + Mana": "全回復",
	"Kill Nearby Enemies": "付近の敵を倒す",
	"Complete Active Quests": "クエスト完了",
	"Level Up": "レベルアップ",
	"Go Floor Down": "階下へ",
	"Go Floor Up": "階上へ",

	# Skill tree
	"Skill Tree": "スキルツリー",
	"Skill Points: 0": "スキルポイント: 0",
	"Skill Points: %d": "スキルポイント: %d",
	"%s Skill Tree": "%s スキルツリー",
	"Branch": "ブランチ",
	"Rank: %d / %d": "ランク: %d / %d",
	"Unlocks: %s": "解除: %s",
	"%s: +%s per rank": "%s: ランクごとに+%s",
	"Requires: %s": "必要: %s",

	# Levels — town
	"Dungeon Entrance": "ダンジョン入口",
	"Click to enter dungeon": "クリックでダンジョンに入る",
	"Enter Dungeon": "ダンジョンに入る",
	"Town Hall": "町役場",
	"Marketplace": "市場",
	"Alchemist": "錬金術師",
	"Tavern": "酒場",
	"General Store": "万屋",
	"Residence": "住居",
	"Blacksmith": "鍛冶屋",
	"Healer": "治療師",
	"Jeweler": "宝石商",
	"Fruit Stall": "果物屋",
	"Weapon Stall": "武器屋",
	"Armor Stall": "防具屋",
	"Guard Tower": "見張り塔",

	# Levels — dungeon
	"Return to Town": "町に戻る",
	"Stairs Up (Floor %d)": "上り階段 (%d階)",
	"BOSS GUARDS THIS PASSAGE": "ボスがこの通路を守っている",
	"Stairs Down (Floor %d)": "下り階段 (%d階)",
	"Click to use stairs": "クリックで階段を使う",
	"Stairs": "階段",

	# NPCs
	"Villager": "村人",
	"Click to talk": "クリックで話す",
	"Click to shop": "クリックで買い物",

	# Fountain
	"Fountain": "噴水",
	"Click to restore Health & Mana": "クリックで体力とマナを回復",

	# Loot
	"Loot": "戦利品",
	"Click to pick up": "クリックで拾う",
	"Click to enter portal": "クリックでポータルに入る",
	"Treasure Chest": "宝箱",
	"Click to open": "クリックで開ける",
	"Empty Chest": "空の宝箱",

	# Player floating text
	"LEVEL UP!": "レベルアップ！",
	"Inventory Full!": "インベントリが一杯！",
	"+ %d Gold": "+ %dゴールド",
	"+%d XP": "+%d XP",
	"No Mana!": "マナ不足！",
	"+%d HP": "+%d HP",

	# Online manager
	"Login failed (server unreachable)": "ログイン失敗（サーバー到達不可）",
	"Login failed": "ログイン失敗",
	"Registration failed (server unreachable)": "登録失敗（サーバー到達不可）",
	"Registration failed": "登録失敗",

	# Items
	"Rusty Sword": "錆びた剣",
	"Iron Axe": "鉄の斧",
	"Steel Mace": "鋼の棍棒",
	"War Hammer": "ウォーハンマー",
	"Shadow Blade": "シャドウブレード",
	"Flame Dagger": "フレイムダガー",
	"Leather Cap": "革の帽子",
	"Iron Helm": "鉄の兜",
	"Plate Helm": "プレートヘルム",
	"Crown of Thorns": "茨の冠",
	"Cloth Tunic": "布のチュニック",
	"Chainmail": "チェインメイル",
	"Plate Armor": "プレートアーマー",
	"Shadow Vestments": "影の法衣",
	"Sandals": "サンダル",
	"Iron Boots": "鉄のブーツ",
	"Greaves": "すね当て",
	"Windwalkers": "ウィンドウォーカー",
	"Health Potion": "体力ポーション",
	"Mana Potion": "マナポーション",

	# Quests
	"Thin the Herd": "群れの間引き",
	"Slay 10 creatures in the dungeon.": "ダンジョンでクリーチャーを10体倒せ。",
	"Grunt Cleanup": "グラント掃討",
	"Kill 5 Grunts lurking in the depths.": "深部に潜むグラントを5体倒せ。",
	"Silence the Casters": "術者を黙らせろ",
	"Defeat 3 enemy Mages.": "敵の魔法使いを3体倒せ。",
	"Brute Force": "力ずく",
	"Take down 3 Brutes.": "ブルートを3体倒せ。",
	"Dungeon Sweep": "ダンジョン一掃",
	"Slay 25 creatures of any kind.": "あらゆるクリーチャーを25体倒せ。",

	# Enemy types
	"Grunt": "グラント",
	"Brute": "ブルート",
	"Skeleton": "スケルトン",
	"Spider": "スパイダー",
	"Ghost": "ゴースト",
	"Archer": "アーチャー",
	"Shaman": "シャーマン",
	"Golem": "ゴーレム",
	"Scarab": "スカラベ",
	"Wraith": "レイス",
	"Necromancer": "ネクロマンサー",
	"Demon": "デーモン",
	"Boss Golem": "ボス ゴーレム",
	"Boss Demon": "ボス デーモン",
	"Boss Dragon": "ボス ドラゴン",

	# Skill branches
	"Arms": "武器術",
	"Weapon mastery and raw damage.": "武器の熟練と攻撃力。",
	"Valor": "武勇",
	"Toughness and survivability.": "頑丈さと生存力。",
	"Warcry": "ウォークライ",
	"Buffs, battle shouts, and auras.": "バフ、雄叫び、オーラ。",
	"Fire": "炎",
	"Fire spells and burst damage.": "炎の魔法とバーストダメージ。",
	"Slows, freezes, and area denial.": "減速、凍結、エリア制御。",
	"Mana mastery, shields, and teleportation.": "マナ熟練、盾、テレポート。",
	"Assassination": "暗殺",
	"Burst damage, crits, and poisons.": "バーストダメージ、クリティカル、毒。",
	"Stealth, evasion, and mobility.": "ステルス、回避、機動力。",
	"Traps": "罠",
	"Traps, bleeds, and debuffs.": "罠、出血、デバフ。",

	# Skill tree nodes — Warrior Arms
	"Sharpened Blade": "研ぎ澄まされた刃",
	"+4 Attack Damage per rank.": "ランクごとに攻撃力+4。",
	"Cleave": "クリーブ",
	"Unlocks Cleave: Slash in an arc, hitting all enemies in front.": "クリーブ解除: 弧を描いて斬り前方の全敵に命中。",
	"Deep Wounds": "深い傷",
	"+5% critical damage per rank.": "ランクごとにクリティカルダメージ+5%。",
	"Brutal Strike": "ブルータルストライク",
	"+3% critical chance per rank.": "ランクごとにクリティカル率+3%。",
	"Whirlwind": "ワールウィンド",
	"Unlocks Whirlwind: Spin and damage all nearby enemies.": "ワールウィンド解除: 回転して近くの全敵にダメージ。",
	"Executioner": "処刑人",
	"+8 Attack Damage, +5% crit damage per rank.": "ランクごとに攻撃力+8、クリティカルダメージ+5%。",

	# Skill tree nodes — Warrior Valor
	"Tough Skin": "硬い肌",
	"+3 Defense per rank.": "ランクごとに防御力+3。",
	"Shield Wall": "シールドウォール",
	"Unlocks Shield Wall: Block all damage for 3 seconds.": "シールドウォール解除: 3秒間全ダメージを防ぐ。",
	"+15 Max Health per rank.": "ランクごとに最大体力+15。",
	"Iron Will": "鉄の意志",
	"+5 Defense, +10 Max Health per rank.": "ランクごとに防御力+5、最大体力+10。",
	"Ground Slam": "グラウンドスラム",
	"Unlocks Ground Slam: Slam the ground, stunning nearby enemies.": "グラウンドスラム解除: 地面を叩き近くの敵をスタン。",
	"Unbreakable": "不壊",
	"+8 Defense, +20 Max Health per rank.": "ランクごとに防御力+8、最大体力+20。",

	# Skill tree nodes — Warrior Warcry
	"Battle Shout": "バトルシャウト",
	"+2 Strength per rank.": "ランクごとに筋力+2。",
	"War Cry": "ウォークライ",
	"Unlocks War Cry: Boost damage of nearby allies for 8s.": "ウォークライ解除: 8秒間近くの味方のダメージ増加。",
	"Bloodlust": "ブラッドラスト",
	"+5% Attack Speed per rank.": "ランクごとに攻撃速度+5%。",
	"Charge": "チャージ",
	"Unlocks Charge: Rush forward and stun the first enemy hit.": "チャージ解除: 突進して最初の敵をスタン。",
	"Veteran": "ベテラン",
	"+3 to Strength and Vitality per rank.": "ランクごとに筋力と活力+3。",
	"Berserker Rage": "バーサーカーレイジ",
	"Unlocks Berserker Rage: Greatly boost damage but take more damage for 10s.": "バーサーカーレイジ解除: 10秒間大幅ダメージ増加、被ダメージも増加。",

	# Skill tree nodes — Mage Fire
	"Ignite": "イグナイト",
	"+3 Intelligence per rank.": "ランクごとに知力+3。",
	"Fireball": "ファイアボール",
	"Unlocks Fireball: Hurl a ball of fire at a target area.": "ファイアボール解除: 目標エリアに火球を投げる。",
	"Searing Heat": "灼熱",
	"+6% spell damage per rank.": "ランクごとに魔法ダメージ+6%。",
	"Fire Wall": "ファイアウォール",
	"Unlocks Fire Wall: Create a wall of flame that damages enemies passing through.": "ファイアウォール解除: 通過する敵にダメージを与える炎の壁を作る。",
	"Pyromaniac": "パイロマニアック",
	"+4 Intelligence, +5% spell damage per rank.": "ランクごとに知力+4、魔法ダメージ+5%。",
	"Meteor": "メテオ",
	"Unlocks Meteor: Call down a devastating meteor on a target area.": "メテオ解除: 目標エリアに壊滅的な隕石を降らせる。",

	# Skill tree nodes — Mage Frost
	"Chilling Touch": "凍える接触",
	"+2 Intelligence, +5 Max Mana per rank.": "ランクごとに知力+2、最大マナ+5。",
	"Frost Nova": "フロストノヴァ",
	"Unlocks Frost Nova: Blast frost around you, damaging and slowing enemies.": "フロストノヴァ解除: 周囲に冷気を放ち敵にダメージと減速。",
	"Hypothermia": "低体温",
	"+4% spell damage, +8 Max Mana per rank.": "ランクごとに魔法ダメージ+4%、最大マナ+8。",
	"Ice Barrier": "アイスバリア",
	"Unlocks Ice Barrier: Shield yourself in ice, absorbing damage for 5s.": "アイスバリア解除: 氷の盾で5秒間ダメージ吸収。",
	"Permafrost": "永久凍土",
	"+3 Intelligence, +10 Max Mana per rank.": "ランクごとに知力+3、最大マナ+10。",
	"Blizzard": "ブリザード",
	"Unlocks Blizzard: Summon a blizzard that rains ice on an area for 6s.": "ブリザード解除: 6秒間エリアに氷の雨を降らせる。",

	# Skill tree nodes — Mage Arcane
	"Mana Flow": "マナフロー",
	"+8 Max Mana per rank.": "ランクごとに最大マナ+8。",
	"Arcane Missiles": "アーケインミサイル",
	"Unlocks Arcane Missiles: Fire a rapid volley of arcane bolts.": "アーケインミサイル解除: 秘術の弾を連射。",
	"Meditation": "瞑想",
	"+5% mana regen speed per rank.": "ランクごとにマナ回復速度+5%。",
	"Teleport": "テレポート",
	"Unlocks Teleport: Instantly blink to a target location.": "テレポート解除: 目標地点に瞬間移動。",
	"Arcane Mastery": "秘術の極意",
	"+4 Intelligence, -5% mana cost per rank.": "ランクごとに知力+4、マナコスト-5%。",
	"Mana Shield": "マナシールド",
	"Unlocks Mana Shield: Convert damage taken to mana cost for 10s.": "マナシールド解除: 10秒間被ダメージをマナコストに変換。",

	# Skill tree nodes — Rogue Assassination
	"Lethality": "致死性",
	"+3 Dexterity per rank.": "ランクごとに器用さ+3。",
	"Backstab": "バックスタブ",
	"Unlocks Backstab: Teleport behind an enemy and deal massive damage.": "バックスタブ解除: 敵の背後にテレポートして大ダメージ。",
	"Twist the Knife": "ナイフを捻る",
	"Poison Blade": "ポイズンブレード",
	"Unlocks Poison Blade: Coat your weapons in poison, adding DoT to attacks.": "ポイズンブレード解除: 武器に毒を塗りDoTを追加。",
	"Cold Blood": "冷血",
	"+6% critical damage, +3 Dexterity per rank.": "ランクごとにクリティカルダメージ+6%、器用さ+3。",
	"Death Mark": "デスマーク",
	"Unlocks Death Mark: Mark an enemy to take 50% more damage for 6s.": "デスマーク解除: 敵をマークし6秒間被ダメージ50%増加。",

	# Skill tree nodes — Rogue Shadow
	"Nimble Feet": "素早い足取り",
	"+0.5 Move Speed per rank.": "ランクごとに移動速度+0.5。",
	"Shadow Step": "シャドウステップ",
	"Unlocks Shadow Step: Dash through shadows to a target location.": "シャドウステップ解除: 影を通って目標地点にダッシュ。",
	"Evasion": "回避",
	"+4% dodge chance per rank.": "ランクごとに回避率+4%。",
	"Vanish": "ヴァニッシュ",
	"Unlocks Vanish: Become invisible for 4s, next attack deals bonus damage.": "ヴァニッシュ解除: 4秒間透明化、次の攻撃にボーナスダメージ。",
	"Fleet Footed": "軽快な足取り",
	"+0.5 Move Speed, +3% dodge per rank.": "ランクごとに移動速度+0.5、回避率+3%。",
	"Smoke Bomb": "スモークボム",
	"Unlocks Smoke Bomb: Throw a smoke bomb, blinding enemies in the area.": "スモークボム解除: 煙幕を投げ範囲内の敵を盲目にする。",

	# Skill tree nodes — Rogue Traps
	"Cunning": "狡猾",
	"+2 Dexterity, +2 Intelligence per rank.": "ランクごとに器用さ+2、知力+2。",
	"Spike Trap": "スパイクトラップ",
	"Unlocks Spike Trap: Place a trap that damages and slows enemies.": "スパイクトラップ解除: 敵にダメージと減速の罠を設置。",
	"Serrated Edges": "鋸歯",
	"Fan of Knives": "ファン・オブ・ナイブズ",
	"Unlocks Fan of Knives: Throw knives in all directions.": "ファン・オブ・ナイブズ解除: 全方向にナイフを投げる。",
	"Resourceful": "機知",
	"+3 Dexterity, +4 Attack Damage per rank.": "ランクごとに器用さ+3、攻撃力+4。",
	"Rain of Arrows": "アローレイン",
	"Unlocks Rain of Arrows: Shower a target area with arrows for 4s.": "アローレイン解除: 目標エリアに4秒間矢の雨を降らせる。",

	# Skill definitions (short descriptions)
	"Slash in an arc, hitting all enemies in front.": "弧を描いて斬り前方の全敵に命中。",
	"Spin and damage all nearby enemies.": "回転して近くの全敵にダメージ。",
	"Block all damage for 3 seconds.": "3秒間全ダメージを防ぐ。",
	"Slam the ground, stunning nearby enemies.": "地面を叩き近くの敵をスタン。",
	"Boost damage of nearby allies for 8s.": "8秒間近くの味方のダメージ増加。",
	"Rush forward and stun the first enemy hit.": "突進して最初の敵をスタン。",
	"Greatly boost damage but take more damage for 10s.": "10秒間大幅ダメージ増加、被ダメージも増加。",
	"Hurl a ball of fire at a target area.": "目標エリアに火球を投げる。",
	"Create a wall of flame that damages enemies passing through.": "通過する敵にダメージを与える炎の壁を作る。",
	"Call down a devastating meteor on a target area.": "目標エリアに壊滅的な隕石を降らせる。",
	"Blast frost around you, damaging and slowing enemies.": "周囲に冷気を放ち敵にダメージと減速。",
	"Shield yourself in ice, absorbing damage for 5s.": "氷の盾で5秒間ダメージ吸収。",
	"Summon a blizzard that rains ice on an area for 6s.": "6秒間エリアに氷の雨を降らせる。",
	"Fire a rapid volley of arcane bolts.": "秘術の弾を連射。",
	"Instantly blink to a target location.": "目標地点に瞬間移動。",
	"Convert damage taken to mana cost for 10s.": "10秒間被ダメージをマナコストに変換。",
	"Teleport behind an enemy and deal massive damage.": "敵の背後にテレポートして大ダメージ。",
	"Coat your weapons in poison, adding DoT to attacks.": "武器に毒を塗りDoTを追加。",
	"Mark an enemy to take 50% more damage for 6s.": "敵をマークし6秒間被ダメージ50%増加。",
	"Dash through shadows to a target location.": "影を通って目標地点にダッシュ。",
	"Become invisible for 4s, next attack deals bonus damage.": "4秒間透明化、次の攻撃にボーナスダメージ。",
	"Throw a smoke bomb, blinding enemies in the area.": "煙幕を投げ範囲内の敵を盲目にする。",
	"Place a trap that damages and slows enemies.": "敵にダメージと減速の罠を設置。",
	"Throw knives in all directions.": "全方向にナイフを投げる。",
	"Shower a target area with arrows for 4s.": "目標エリアに4秒間矢の雨を降らせる。",
	"Heal": "ヒール",
	"Restore health.": "体力を回復。",

	# Language selector
	"Language": "言語",
}
