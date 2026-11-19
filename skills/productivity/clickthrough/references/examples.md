# Examples

Mined from real handovers (Oct–Nov 2026), with ids and names replaced. "Reaction" is what the user did next.

## Good

### Small fix, 3 lines → merged within a minute

```markdown
Lokální admin běží, otevře se jako lokální admin:
http://localhost:56350/app/report

1. Klikni na „Období“, v „Posunout interval“ dej **−1m** → 1. 9. – 30. 9.
2. Ještě jednou **−1m** → 1. 8. – 31. 8.

**Dřív:** 30. 9. → −1m → **30. 8.** (špatně, srpen má 31 dní).
```

Why it worked: link to the exact page, each step states the expected value, "before" uses real values from the UI.

### Time-dependent bug, data seeded → merged in the same minute

```markdown
V lokální DB jsem přesunul dva termíny na dnešek, v datech žádný dnešní nebyl. Admin běží.

**Klient s probíhajícím termínem** (dnes 15:14–16:44). Na `main` by tu karta chyběla:
http://localhost:35270/app/client/detail?id=<id>

**Klient s termínem, který skončil ráno** (stav `completed`). Na `main` by chyběl taky:
http://localhost:35270/app/client/detail?id=<id>

Platí do půlnoci. Až to dokoukáš, vrátím termíny na původní data.
```

Why: one labelled link per state, "on main this would look like X", expiry, offer to revert.

### Two surfaces → "ok merge it" within a minute

```markdown
- Admin, jeřáb s vlastními dokumenty: http://localhost:44570/app/crane/detail?id=<id>&tab=documents
- Admin, jeřáb bez nich (jen dokumenty typu): http://localhost:44570/app/crane/detail?id=<id>&tab=documents
- Mobil (zúžit okno na telefon): http://localhost:44577/mobile/cranes/<id>/ → záložka Soubory (URL ji neotevře)
Přihlášení: admin „Pokračovat jako výchozí uživatel“, mobil „Účty“ → <technik>.
```

Why: one link per surface, contrasting records, says where a deep link isn't possible and gives the one click.

### Record in a specific state, with steps

```markdown
Zkoušej lokálně, změna je jen v PR „Poznámka po zrušení ověření“ (#N).
Projekt <číslo>: http://localhost:24870/app/project-detail?id=<id>&projectTab=commercial&_hatch=<worktree>
Dva řádky faktur jsou ověřené, nezaúčtované, s prázdnou poznámkou.

1. Klikni na zelený štítek „Ověřeno“ → ověření se zruší.
2. Ve sloupci Poznámka napiš text, Enter → uloží se hned.
3. „Ověřit“ + „Uložit změny“ → poznámka se zase zamkne.
Jsi lokální admin, takže rušit ověření můžeš. Provozní role to dál nemůže.
```

### Variant pick → one-letter answer

```markdown
**Vizualizace naskenovaných dílů** — vyber jednu:
- Dnes: http://localhost:58635/?path=/story/inventory-scanned--current
- [A](http://localhost:58635/?path=/story/inventory-scanned--a) pruh s procenty nad tabulkou
- [B](http://localhost:58635/?path=/story/inventory-scanned--b) barevný sloupec v tabulce
- [C](http://localhost:58635/?path=/story/inventory-scanned--c) karty po lokacích
Všechny ukazují stejné 3 inventury (otevřená, dokončená, zrušená). Doporučuju B.
```

### Decision → "1. A 2. A … 5. B" in minutes

```markdown
**1. Zámek „Nerealizováno“** (mobil, detail projektu → Aktivity)
Teď nejde přeplánovat aktivita ve stavu Nerealizováno. Má jít?
- **A, nechat zamčené** (doporučuju): opakování = nová aktivita.
- **B, odemknout a vrátit na Naplánováno:** zmizí z historie, že se nekonala.
Kde: [mobil, projekt …](http://localhost:38678/mobile/projects/<id>/?tab=activities), přepni se na <montéra> přes „Účty“.
Stačí napsat písmeno.
```

### Backend perf, merge-ready

```markdown
PR „Rychlejší report" (#N): CI zelené. Vzhled se nezměnil.
http://localhost:44570/app/report?period=2026-10 → „Období" → −1m: dřív ~4 s, teď ~0,4 s.
Mergnout?
```

### Stage, user's own login

```markdown
Nasazeno na stage, obnov tab.
[Aktivita „Kontrola jeřábu", přiřazená tobě](https://stage.example/app/activity/detail?id=<id>)
Přihlas se svým účtem. Sám se tam nepřihlásím; ověřil jsem HTTP 200 a data aktivity.
E-maily ze stage odcházejí naostro, příjemce jsem nechal prázdný.
```

## Bad

| What the agent sent | Reaction | Fix |
|---|---|---|
| "CI prošlo, ready to merge: `gh api …/merge`" — no app link | "dej mi link" (most common miss) | Merge-ready report includes the clickthrough |
| Stage order list + "vezmi libovolnou zakázku s obsazeným slotem" | "na lokálu to chci vyzkoušet" | Concrete record in the right state, local by default |
| "Odkaz je výše" / link only in tool output | "you didnt send no link" | Every link in the current message |
| Storybook link for "kde si to můžu vyzkoušet" | "chci link na local aplikaci. ne storybook" | Real app + seeded record |
| Picked variant built only in Storybook | "chci to i v appce, ne jen v storybooku" | Agreed work goes to the app |
| Feedback fix applied only to the recommended variant | "ve storybooku jsi to změnil jen na v3" | Shared fixes go into every compared variant |
| List of `/private/tmp/*.png` paths | "odkazy na screenshoty jsou k ničemu" | One HTML page with the screenshots, or live links |
| Full-page screenshots where the diff is two names | "na ty 3 a 4 nevidím ty změny" | Crop + highlight the changed area |
| Decision list "1. A/B? 2. …" with links only higher up | "linky musí být i v tom ‚od tebe potřebuju'" | Links inside each decision |
| "5a 5b 5c 5d", "#123 a #456" | "je co? kde to můžu vidět?" / "musíš tomu dát krátkej název" | Short name + link |
| `http://localhost:6106`, `…--a-many`, "stačí přepsat konec URL" | "dej mi přesnej link" | Full deep URL |
| Link to the ticket reporter's id instead of the record from the screenshot | "ale ten task to ukazuje na stránce …, ne?" | Link the place the ticket shows |
| Deploy report with no link; ticket's record no longer in that state | "jak to tam uvidím? tady to nevidím" | Deployed-env link to a record that shows it now |
| Link to a page, no word on what changed (data-only change) | "okay a co se tam teda změnilo?" | "Vzhled stejný, jen čísla: dřív → teď" |
| Investigation with seeded data, silent on code | "a ty jsi dělal nějaký úpravy nebo ne?" | "Kód: beze změny" |
| Admin-only change, nothing said about mobile | "ok a v mobile appce to není, že?" | Say which surfaces are and aren't touched |
| Gallery artifact with broken images | "ty fotky tam nejsou. a nepotřebuju ani artifact" | Check it renders; small change needs no artifact |
| Private artifact link without account | "na jakej ucet je ten artifact?" | Name the account |
| Only "Účty jsou připravené" after "proveď mě tím" | layout feedback, walkthrough never came | Prep never replaces the walkthrough message |
| "Storybook neběží, story je X" / "spusť `bun run storybook`" | "spusť znovu dev server" | Start it, verify, then hand over |
| Test list without account, record or link | "řekni mi na jakej účet se mam lognout… připrav testovací aktivitu" | Account + seeded record + link per item |
| English handover in a Czech session | "vysvětli mi to pořádně" | Match their language, domain terms not code terms |
