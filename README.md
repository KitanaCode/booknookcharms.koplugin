📖 Book Nook Charms for KOReader

Book Nook Charms is a cozy little KOReader plugin that lets you decorate your reading screen with bookmark charms.

For if you'd like to support me and buy my starbucks. Here's my ko-fi link!
https://ko-fi.com/kitanacode

Pick a ribbon, tuck a dog-ear into the corner, save your favorites, switch between day and night looks, or choose a grayscale e-ink charm made for black-and-white readers.

🖼️ Peek Inside

Here is a tiny look at Book Nook Charms in KOReader.

![Book Nook Charms in the Typesetting menu](screenshots/typesetting-menu.png)

![Book Nook Charms menu](screenshots/menu.png)

![Charm Studio with a dog-ear charm](screenshots/charm-studio-dogear.png)

![Charm Studio with a ribbon charm](screenshots/charm-studio-ribbon.png)

![Book Nook Charms gesture actions](screenshots/gestures.png)

![More Book Nook Charms gesture actions](screenshots/gestures-page-2.png)

📱 Compatibility

Book Nook Charms is made for KOReader and designed with Kobo readers in mind.

It includes color charms for color screens and grayscale e-ink charms for black-and-white e-readers.

It may also work on Kindle and older Kobo devices that run KOReader, but compatibility can depend on the KOReader version installed. If a KOReader build does not support gesture actions or a newer menu helper, Book Nook Charms tries to keep the regular menu features working and logs the missing piece instead of crashing.

📦 Installation

1. Download the latest release zip from GitHub.
2. Unzip it.
3. Copy `booknookcharms.koplugin` into your KOReader plugins folder:


koreader/plugins/booknookcharms.koplugin/

4. Restart KOReader.
5. Open a book, then go to the KOReader Typesetting menu (second menu button at the top) and look for **Book Nook Charms**. It will only be shown when a book is opened.

✏️ What You Can Do

- Choose ribbon bookmarks and dog-ear corner bookmarks.
- Use night charms for darker reading themes.
- Use e-ink charms for black-and-white e-reader screens.
- Resize, place, and use quick presets in Charm Studio.
- Adjust charm size in gentle 0.1x steps.
- Set your current charm as a day or night pair right from Charm Studio.
- Save favorite charms so your sweetest picks stay close.
- Save a charm for one book or set a default charm for everything.
- Set a day charm and a night charm as a pair.
- Cycle through favorite charms from the menu or a Reader gesture.
- Repair saved charm paths automatically when possible.
- Check saved charm status from Troubleshooting.
- Start with a soft default dog-ear charm on first install.
- See small text previews beside charm names in the menus.
- Add your own charm files later.

✨ Main Menu

- Charm Studio ✨      resize, place, and use quick presets
- Charm Library ❤     browse the full charm collection
- Favorite Charms ⭐   keep your favorite charms together
- Charm Types ◇       browse by ribbon, dog-ear, night, or e-ink
- Day/Night Pair ☀☾   choose a charm for day and one for night
- Set a Charm ✧       save, reset, or set defaults
- Help ✎              quick guide inside KOReader
- Troubleshooting ⚙   check saved charm status
- About ⓘ             version and creator info

◇ Charm Types

Ribbon Charms ✿     long hanging bookmark ribbons
Corner Charms ❖     folded dog-ear corner bookmarks
Night Charms ☾      charms made for darker pages and night mode
E-ink Charms ◐      grayscale charms for black-and-white e-readers

◐ About E-ink Charms

E-ink charms are grayscale on purpose.

Black-and-white e-readers cannot show warm ivory, cream, gold, blush, blue, or other color tones the way a color E-reader can. If two colors are only different because one is warmer or cooler, they may look almost the same on a black-and-white screen.

That is why the e-ink set uses fewer, stronger grayscale shades. They are meant to be easy to tell apart.

Frost      very light gray
Pearl      light gray
Smoke      soft medium gray
Dither     deeper medium gray
Oil Slick  dark gray
Obsidian   near black

Each e-ink shade has a ribbon version, a dog-ear version, and matching night versions.

✨ Charm Studio

Charm Studio is the little workshop for your current bookmark.

Choose Your Mark ◈       switch between the default corner and your charm files
Charm Size ↕             make the charm smaller or bigger in 0.1x steps
Charm Placement ⌖        nudge the charm from the top or right edge
Quick Presets ✦          jump to Corner, Ribbon, or Tucked placement

Corner is best for full dog-ear bookmarks.
Ribbon is best for hanging ribbon bookmarks.
Tucked is a softer, smaller preset. For ribbons, it keeps the ribbon tucked at the top. For dog-ears, it uses a smaller 3.0x corner look while still touching the top.

The Save button keeps the current Studio changes.
Set Day stores the current charm as your day charm for Day/Night Pair.
Set Night stores the current charm as your night charm for Day/Night Pair.
Default makes the current charm your default for books that do not have their own saved charm.
Reset restores the original KOReader corner bookmark.
Cancel closes Charm Studio and puts things back the way they were before you opened it.

🔖 Charm Menu Symbols

Book Nook Charms uses small text symbols in the charm menus as quick previews.

◢   dog-ear charm
▌   ribbon charm
☾   night charm
○   light e-ink shade, like Frost or Pearl
◐   medium e-ink shade, like Smoke or Dither
●   dark e-ink shade, like Oil Slick or Obsidian

📁 Folders

Place the plugin here:

koreader/plugins/booknookcharms.koplugin/

Inside the plugin folder:

ribbons/        ribbon bookmark charms
dogears/        dog-ear corner charms
night/          night-friendly charms
eink/           black-and-white e-ink charms
custom_icons/   your own added charms
templates/      starter SVG templates

Some night e-ink charms are included in both `eink/` and `night/` so they can appear in both the E-ink Charms submenu and the Night Charms submenu.

🎨 Adding Your Own Charms

Add your charm files to `custom_icons/`, then reopen KOReader or reload the plugin.

Helpful names:

ribbon_my_charm.svg          ribbon bookmark
dogear_my_charm.svg          dog-ear bookmark
ribbon_night_my_charm.svg    night ribbon bookmark
dogear_night_my_charm.svg    night dog-ear bookmark
ribbon_eink_my_charm.svg     e-ink ribbon bookmark
dogear_eink_my_charm.svg     e-ink dog-ear bookmark

Supported image types include SVG, PNG, BMP, JPG, JPEG, and alpha files. SVG is usually the cleanest choice for crisp charms.

👆 Gesture Actions

You can assign Book Nook Charms to KOReader gestures.

Restart KOReader after installing or updating the plugin. Then go to KOReader's gesture manager, choose a gesture, open the Reader actions, and look for actions that begin with `Book Nook Charms:`.

Book Nook Charms: Charm Studio              open size and placement controls
Book Nook Charms: Charm Library             browse all charms
Book Nook Charms: Favorite Charms           open your saved favorites
Book Nook Charms: Next favorite charm       cycle through saved favorites
Book Nook Charms: Charm Types               browse ribbons, dog-ears, night, and e-ink charms
Book Nook Charms: Switch day/night charm    swap between your saved day and night pair
Book Nook Charms: Apply day charm           apply your saved day charm
Book Nook Charms: Apply night charm         apply your saved night charm
Book Nook Charms: Toggle auto day/night     turn automatic day/night pairing on or off
Book Nook Charms: Reset charm               restore the default charm

⚠️ Known Notes

- Restart KOReader after installing or updating.
- Gesture actions appear under KOReader's Reader actions.
- On Kindle or older Kobo devices, gesture actions may depend on the KOReader version.
- If a saved charm path changes, Book Nook Charms tries to repair it by filename.
- Use Troubleshooting if a saved charm does not appear after restart.
- First install starts with a soft original dog-ear charm.
- Missing favorite charms can be cleaned up from Favorite Charms.
- About shows the plugin version and creator.
- E-ink charms are made for black-and-white e-readers.
- If a charm looks too large, too small, or slightly off-corner, open Charm Studio and adjust the size or placement.

🧡 Tiny Charm Tips

- If a charm feels too big or too small, open Charm Studio.
- If a charm sits too far from the corner, nudge its placement in Charm Studio.
- Use Set Day or Set Night in Charm Studio when you want the current charm to become part of your day/night pair.
- Use Favorite Charms for the ones you love most.
- Use Night Charms when your reading theme is dark.
- Use E-ink Charms for black-and-white e-readers or when you want extra-clear grayscale contrast.
- For new e-ink charms, avoid colors that only work on color screens.
- If you remove charm files later, use Favorite Charms to clean up missing favorites.
- In Charm Studio, Tucked keeps the charm touching the top while softening its size and side placement.

🛠️ Reporting Compatibility Issues

If something does not work on Kindle or an older Kobo, please include:

- Device model
- KOReader version
- What you tapped or changed
- Whether Book Nook Charms appears in the reader menu
- Any useful lines from `crash.log`

💌 A Little Note

Book Nook Charms is meant to feel soft, personal, and a bit magical, like leaving a tiny bookmark tucked inside your favorite story.

Happy reading my lovelies!📚✨

🪪 Credits

Made by KitanaCode.
Cat bookmarks are created by u/AggravatingDebt4621 from Reddit.

📄 License

Released under the MIT License. See `LICENSE` for details.
