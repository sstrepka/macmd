# macmd

`macmd` is a fast two-pane file manager for macOS.

Version: `1.0.4`

## Current features

- two-pane commander layout
- keyboard-first navigation
- Finder-like file icons
- copy, rename, mkdir, trash, permanent delete
- ZIP creation and ZIP browsing
- favorites and locations in the top bar
- FTP, FTPS, and SFTP connections
- FileZilla XML import for saved connections
- open-in-Terminal support
- hidden files toggle and light/dark appearance modes

## Keyboard shortcuts

Use ⌘1 Terminal, ⌘2 ZIP, ⌘3 Open, ⌘4 Edit, ⌘5 Copy,
⌘6 Rename / Move, ⌘7 New Folder, ⌘8 Trash, ⌘9 Switch Pane, and ⌘0 Quit.
Tab still switches panes. Escape dismisses dialogs or requests cancellation
of a running operation. Function keys retain their standard macOS behavior.
The build does not install or modify Karabiner configuration.

The toolbar's `>>` / `<<` button points from the active pane to the other
pane. Click it to open the active pane's location in the other pane.

## Build

```bash
./build.sh
```

Requires Apple Command Line Tools. Full Xcode is not required: the script
compiles directly with `swiftc`, then signs and installs the app and creates
an installer in `dist/`.

The app bundle installs to:

- `~/Applications/macmd.app`

## Changelog

### 1.0.4

- anchor the FTP server menu below its toolbar button in screen coordinates
- dispatch the selected profile directly after menu tracking finishes

### 1.0.3

- replaced separate system curl processes with bundled libcurl 8.23.0 and OpenSSL 4.1.0
- reuse authenticated FTP connections, TLS sessions and DNS cache across files
- verified the three failing source files against the live server with SHA-256 readback
- application and installer include the static engine and third-party license notices; no Homebrew runtime dependency

### 1.0.2

- certificate exceptions with public-key pinning for imported FTPS accounts
- atomic upload recovery and bounded retries for FTP 426 errors
- reuse upload connections for final rename and validate trust once per transfer batch
- show transfer stages, bound FTP response waits, and include endpoint/trust context in errors
- ignore external curl configuration so application TLS settings remain consistent

### 1.0.1

- added FTP, FTPS, and SFTP connection support
- added FileZilla XML import
- added a full connection manager for saved remote profiles
- fixed password import from FileZilla base64 exports
- fixed SFTP browsing and remote directory listing parsing
- switched to a single user-managed install in `~/Applications/macmd.app`

### 1.0

- initial public release of `macmd`

## Icon

The application icon uses the Total Commander floppy icon from
https://www.ghisler.com/favicon.ico (Ghisler Software GmbH), as requested.

### Context menu

Right-click (or Control-click) a row for Open, Open With, Copy, Cut, Paste, Compress, and Get Info (Finder properties). Clicking a marked row keeps the marked group; clicking an unmarked row targets that item. Right-clicking empty space offers Paste into the current folder. Local file actions are disabled in ZIP and FTP views. Open With lists applications compatible with all selected items and includes Other… for choosing an application.

### Archívy v paneloch

- Enter otvorí ZIP, 7z, RAR, TAR, TAR.GZ/TGZ a GZ ako priečinok. `..` alebo Backspace sa vráti vyššie; v koreni archívu späť k jeho súboru.
- F5 kopíruje označené súbory/priečinky z archívu do druhého lokálneho panela, z lokálneho panela do otvoreného archívu aj medzi otvorenými archívmi. Pri zápise sa potvrdzuje nahradenie rovnomenných položiek.
- ZIP a TAR používajú systémové nástroje. Zápis 7z a práca so samostatným GZ používajú dostupné `7zz`/`7z` v `/opt/homebrew/bin` alebo `/usr/local/bin`. RAR je len na čítanie a rozbaľovanie.
- GZ obsahuje jeden súbor; na viac súborov slúži TAR.GZ. F6 presun v archíve nie je podporovaný; použite F5.
- Otvorenie rozbalí archív do dočasného priečinka, preto potrebuje voľné miesto pre celý obsah. Zápis zostaví a overí nový archív pred nahradením pôvodného. Archív zmenený iným programom treba znova otvoriť. Pri prepísaní sa nezachováva pôvodný spôsob kompresie, šifrovanie ani všetky špecifické metadáta formátu.

⌘B toggles branch view for the active local folder: files from all subfolders appear in one sortable list. The Folder column identifies their original locations; operations use their real paths. Hidden-file visibility follows the existing setting. Folder navigation exits branch view. Archive extraction with ⌘5 asks for a destination first; ⌘6 offers Copy Instead because removing entries from archives is not supported.

### FTP / SFTP správa súborov

Sieťové tlačidlo → **Edit FTP Connections** otvorí správcu účtov. Podporované sú FTP (TLS podľa dostupnosti), obyčajné FTP, SFTP a explicitné/implicitné FTPS. Protokoly a prihlasovacie typy používajú číselné hodnoty FileZilly; implicitné FTPS je 3, explicitné FTPS je 4.

- **Import XML / Export XML**: FileZilla Site Manager/export `FileZilla3`, vrátane prihlasovacích údajov, hierarchie priečinkov, ciest, komentárov, odkazu na privátny kľúč a pôvodných dodatočných XML polí. Heslá v exporte sú Base64 a súbor má práva 0600. Šifrované heslá s master heslom sa zachovajú pri opätovnom exporte, ale macmd ich nedešifruje; pri pripojení treba zadať heslo. Súkromné kľúče ani certifikátové súbory sa do XML nekopírujú, zachovávajú sa ich cesty.
- Heslá aj pôvodné XML serverov sa ukladajú spolu do jednej položky macOS Keychain, načítanej raz za beh aplikácie; UserDefaults obsahuje iba profily bez týchto hodnôt. Ak Keychain odmietne uloženie, správca oznámi chybu.
- **⌘5** kopíruje súbory aj priečinky lokálne ↔ server a server ↔ server (cez dočasnú lokálnu kópiu). **⌘6** premenuje jednotlivú vzdialenú položku; označená skupina sa presunie do druhého panela. Kontextové menu ponúka samostatný presun, premenovanie, mazanie, nový súbor/priečinok a číselné práva (`chmod`, FTP server musí podporovať `SITE CHMOD`). **⌘7/⌘8** vytvoria priečinok/vymažú vzdialené položky.
- **⌘4** otvorí vzdialený UTF-8 text v zabudovanom editore (do 10 MB). **Save to Server** odošle zmeny; ak sa pôvodný obsah na serveri medzitým zmenil, uloženie sa odmietne. Enter stiahne a otvorí súbor predvolenou aplikáciou; zmeny z externej aplikácie sa automaticky neodosielajú.
- Prenosy súborov používajú dočasné názvy a následné premenovanie. Prepisovanie sa potvrdzuje pri prenose; priečinky sa zlučujú. Presun vymaže zdroj až po úspešnom prenose danej položky. Zrušenie zastaví aktívny prenos aj ďalšie položky; nedokončený dočasný súbor môže zostať na serveri. Súborový atómový rename musí podporovať cieľový server; celý strom priečinkov nie je jedna transakcia.
- SFTP zobrazí SHA-256 fingerprinty prvého pripojenia. Uložený zmenený kľúč OpenSSH odmietne. FTPS štandardne overuje certifikáty; pre vlastný certifikát slúži **Trust TLS…**, s potvrdením fingerprintu. Overenie hostname a platnosti ostáva zapnuté. **Reset Trust…** vymaže dôveru pre vybraný server. Databázy dôvery sa nezdieľajú ani neimportujú z FileZilly.
- Rozsah nie je úplná náhrada FileZilly: bez obnovenia prerušených prenosov, riadenia šírky pásma, MFA dialógov, konverzie vlastných znakových sád či exotických serverových typov. Výpis podporuje unixový formát; rekurzívne prechádzanie symbolických odkazov je vypnuté. Dodatočné FileZilla polia sa zachovávajú pre export, nemusia sa všetky aplikovať na pripojenie.

Transportné testy: `Tests/Remote/README.md`.


#### Oprava importovaných hesiel

Obnovenie zoznamu ani zmena výberu v správcovi nesmie uložiť starý formulár do nového účtu. Import aktualizuje už otvoreného správcu a po zápise overí, že uložené heslá možno opäť načítať. Pri opätovnom importe sa údaje preberú priamo z XML bez čítania starých samostatných položiek Keychain. Staré položky ostávajú zachované pre prípad obnovy; nové úložisko ich už pre obnovené účty nepoužíva. Odmietnutý prístup ku Keychain sa oznámi ako chyba a nesmie prepísať uložené heslá prázdnymi hodnotami.
