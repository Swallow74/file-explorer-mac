FILE EXPLORER FOR MAC - COME SBLOCCARE L'APP / HOW TO UNLOCK THE APP
=====================================================================

L'app non e' notarizzata da Apple (serve un account sviluppatore a pagamento),
quindi al primo avvio macOS la blocca con un avviso. Non e' un errore: si sblocca
una volta sola. Prima trascina "File Explorer.app" nella cartella Applicazioni.

The app is not notarized by Apple (that needs a paid developer account), so macOS
blocks it the first time. Unlock it once. First drag "File Explorer.app" into
the Applications folder.


METODO 1 - DA INTERFACCIA GRAFICA / METHOD 1 - GUI
--------------------------------------------------
macOS 15 (Sequoia) e successivi / and later:
  1. Fai doppio clic su File Explorer. Compare l'avviso: premi "Fine" / "Done".
  2. Apri Impostazioni di Sistema > Privacy e sicurezza.
  3. Scorri fino alla sezione "Sicurezza": c'e' il messaggio su "File Explorer".
  4. Premi "Apri comunque" / "Open Anyway" e conferma con password o Touch ID.
  5. Premi "Apri" nella finestra che compare.

macOS 14 (Sonoma) e precedenti / and earlier:
  1. Clic destro (o Ctrl + clic) su File Explorer > "Apri".
  2. Premi di nuovo "Apri" nell'avviso.


METODO 2 - DA TERMINALE / METHOD 2 - TERMINAL
---------------------------------------------
Apri l'app Terminale e incolla questo comando (poi premi Invio):
Open Terminal and paste this command (then press Return):

  xattr -dr com.apple.quarantine "/Applications/File Explorer.app"

Poi apri File Explorer normalmente. / Then open File Explorer as usual.


NOTA / NOTE
-----------
Gli aggiornamenti installati dall'app stessa ("Install and Restart") non
richiedono di rifare lo sblocco.
Updates installed by the app itself ("Install and Restart") don't need
unlocking again.
