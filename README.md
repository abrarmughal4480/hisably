<p align="center">
  <img src="docs/banner.png" alt="Hisably — Har rupay ka hisaab." width="100%">
</p>

<p align="center">
  <a href="https://github.com/abrarmughal4480/hisably/releases/tag/genesis"><img src="https://img.shields.io/badge/release-Genesis-2E6BFF" alt="Latest release: Genesis"></a>
  <img src="https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white" alt="Android">
  <img src="https://img.shields.io/badge/data-on%20your%20phone-black" alt="Data stays on your phone">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4ADE80" alt="License: MIT"></a>
</p>

## What is Hisably?

Hisably is a simple money app for Android.

You write down what you earn and what you spend.
The app keeps the record for you — income, expenses, savings,
and money you lend or borrow (your **Khata**).

Your records live on your phone. No account needed. No tracking.
And if you sign in with Google, a backup also goes to your own
Google Drive — so your record is safe even if the phone is lost.

## Get the app

<p>
  <a href="https://github.com/abrarmughal4480/hisably/releases/tag/genesis"><b>Download Hisably.apk — Genesis release</b></a>
</p>

1. Open the link above.
2. Download **Hisably.apk**.
3. Open the file on your phone and install it.

One APK works on every Android phone (Android 7.0 or newer).

> Hisably is in active development — new things are added from time to time,
> and this page always has the latest code.

## Screenshots

| Splash | Home |
|---|---|
| ![Splash](docs/screenshots/01-splash.png?v=20261023) | ![Home](docs/screenshots/02-home.png?v=20261023) |

| Add a transaction | All transactions |
|---|---|
| ![Add](docs/screenshots/03-add.png?v=20261023) | ![Transactions](docs/screenshots/04-transactions.png?v=20261023) |

| Khata (money lent and borrowed) | Savings goals |
|---|---|
| ![Khata](docs/screenshots/05-khata.png?v=20261023) | ![Savings](docs/screenshots/06-savings.png?v=20261023) |

| Reports |
|---|
| ![Reports](docs/screenshots/07-reports.png?v=20261023) |

*Pictures are from the real app, with sample data.*

### On a real phone

From the owner's phone, 23 October 2026: the account screen with its
backup controls, signing in with Google during setup, and Home right
after — fingerprint unlock offered. (The profile photo and email are
hidden here on purpose.)

| Account & backup controls | Sign in with Google |
|---|---|
| ![Account](docs/screenshots/08-account.png?v=20261023) | ![Setup with Google](docs/screenshots/09-setup-google.png?v=20261023) |

| Home — fingerprint offered |
|---|
| ![Home](docs/screenshots/10-home.png?v=20261023) |

## What you can do

| | |
|---|---|
| **See your money at a glance** | The home screen shows your total balance, this month's income and spending, and who owes you money. |
| **Add entries in seconds** | Tap Income, Expense, Transfer, Lend or Borrow, and type the amount on the big on-screen keypad. |
| **Keep a proper Khata** | One clear balance per person, in plain words: *"Zain has to return Rs 3,000 to you."* You can never repay more than what is owed. |
| **Save for goals** | Make a goal, move money into it, and watch it grow. |
| **Stay within budget** | Set a monthly budget. Hisably warns you at 70%, 90% and 100%. |
| **Understand your spending** | Simple reports by month, by category, and by account. |
| **Fix mistakes safely** | Edit or reverse a wrong entry. Nothing is silently deleted — the history stays honest. |
| **Lock the app** | A 4-digit PIN, with fingerprint unlock. |
| **Back up to Google Drive** | Sign in with Google and your data backs up by itself to your own Drive. New phone? Sign in, and it all comes back. |
| **Or keep a backup file** | Save all your data in one file yourself, and bring it back any time. |
| **Bring data in** | One Import button: a Hisably backup, or a CSV / JSON file from another app or your bank — the app figures out the rest. |
| **Sign out safely** | Signing out wipes this phone clean and starts fresh. Your Drive backup is never touched — sign in again and your data returns. |
| **Two languages** | English and اردو (Urdu) — switch any time. |
| **Repeat less** | Entries you make often come back as one-tap chips. |

## Your privacy

Your money data lives on your phone, in an encrypted database.

Hisably has no server of its own, and there is no tracking.
If you turn on the Google backup, the backup goes to a private,
app-only folder inside **your own** Google Drive. Only Hisably,
signed in as you, can open it — the developer cannot see it.

Read the full [Privacy policy](PRIVACY.md).

## Made with

| Part | What is used |
|---|---|
| App | Flutter + Dart |
| Data on the phone | SQLite (Drift), encrypted (SQLCipher) |
| Backup | Google Drive, app-only folder — optional, only if you sign in |
| State | Riverpod |
| Design | Premium dark theme — Sora, Manrope, Inter, Noto Nastaliq Urdu |
| Money math | Integer paisa only, so totals are never wrong |

## For developers

```bash
flutter pub get
flutter test
flutter build apk --release
```

Want the full picture, in simple words?
Read **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — it starts with a
plain summary and then goes deeper.

Signing keys are not part of this repository.
Add your own `android/key.properties` to make a signed build,
or just run `flutter run` to try the app.

Found a problem, or have an idea?
Open an issue — simple forms are ready for you.

## License

MIT — see [LICENSE](LICENSE).

---

<p align="center">Built by <b>Muhammad Abrar</b> · <i>Har rupay ka hisaab.</i></p>
