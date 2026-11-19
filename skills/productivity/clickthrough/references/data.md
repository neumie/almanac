# Preparing data

The user names the state they need ("někde kde to je už ověřený ale nezaúčtované", "tam potřebuju vozidla", "udělej aktivitu a přiřaď mi jí"). Don't wait to be asked: find or make that state before the handover.

## Pick records

- One record per state the change treats differently: open / completed / cancelled; fits on one page / overflows; with own data / without.
- Prefer the record from the ticket or the client's screenshot, so the user recognises it ("To je přesně ten screenshot z tasku"). If it no longer shows the state, say so first and give one that does.
- List the conditions that make the record qualify, so they trust it without checking.
- Real data that can change (prod orders): give 1–2 backups, and say how fresh the source is (date of the local prod dump).
- Say where in the record to look (tab, group, row, invoice number).

## Make records (local)

- Seeding local data is the agent's job and needs no permission: insert, shift dates to today, move a record through earlier steps by clicking or via API.
- Time-dependent bugs: put the state into "now" (appointment today, running now) and say when it expires ("do půlnoci").
- After a DB reset or clean cycle, re-seed before handing over. Never hand over "DB je prázdná, řekni jestli chceš import".
- Reset the demo record to a clean state before handing over, and say what state it is in.
- Say that trying it changes local data, and give the original value so it can be restored. Offer to revert seeded changes when they're done.
- Local data can lack config that Storybook fixtures have (missing template), so the app shows less. Seed the config too or say so.

## Stage

- The user logs in as themselves: assign the record to them and copy the setup of the real prod case they mention.
- Check whether stage sends real e-mails before suggesting a click there. Leave recipients empty or point out who would get mail.

## Prod and shared environments

- Read only. Pick existing records.
- Warn about the one click with real side effects (booking, e-mail to a client, invoicing).
- Say which part can't be seen there and why.

## Physical inputs

- Scan/hardware flows: one HTML page with the QR codes/barcodes of the seeded items (labelled with item name and what scanning it should do), big enough to scan from a screen and printable. Without it the user has to ask: "připrav mi testovací aktivitu s těma věcma a i QR kódy co můžu skenovat."
- Account: name the account/role per check and how to log in (dev login button, account switcher, seed user). Never paste passwords; point to the dev login or the seed file.
- Generated files (PDF, e-mail): name the button that produces them and pick records for the edge cases. Say where shown values come from (a real name prefilled looks hardcoded otherwise).

## Investigation vs fix

Say in one line whether code changed: "Kód: beze změny, jen jsem připravil data" vs "Kód: změněno X". Data prep in local/stage is reported separately.
