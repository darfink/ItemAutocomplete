# ItemAutocomplete

This is an autocomplete addon for item links in WoW Classic. It integrates with your chat and is triggered with a single character (default `[`), making every single item in the game a few key strokes away.

![In-game demo](https://i.imgur.com/H70fus7.gif)

## Features

- **Item database:** It automatically scans the entire item database the first time it starts up, thereafter every single item is accessible. No need to wait for you to encounter it in the world! Perhaps it's time to lookup Ashbringer or Atiesh?

- **Chat integration:** Whilst composing a message, just input your trigger character (default <kbd>[</kbd>) and start searching for whatever item you want to link. When you've find your item, just press <kbd>↵ Enter</kbd> to insert the link.

- **Fuzzy search:** Never spell out an entire item name! And find items with blazing speed. The fuzzy search ensures you only need to write a small portion of any item before it pops up in the menu.

**TIP** Another feature if you're using an auction house addon is the ability to look up item tooltips, making it easy to view any item's price tag whilst out travelling in the world.

### Fuzzy search

To actually showcase how great the fuzzy search is, here's some examples:

| Input              |   | Item                         |
| ------------------ | - | :--------------------------- |
| <kbd>[devga</kbd>  | → | [Devilsaur Gauntlets]        |
| <kbd>[robvoi</kbd> | → | [Robe of the Void]           |
| <kbd>[perbl</kbd>  | → | [Perdition's Blade]          |
| <kbd>[sulr</kbd>   | → | [Sulfuras, Hand of Ragnaros] |
| <kbd>[hiwi</kbd>   | → | [Hide of the Wild]           |

**TIP** Avoid using <kbd>Space</kbd> when searching; in general it's much faster just to type parts of each word of an item name.

## Controls

Use <kbd>[</kbd> in the chat to trigger the menu (*configurable*), then start typing to filter your search.

For interaction, it has the same controls as you'd expect any autocomplete menu to provide.

- <kbd>⇥ Tab</kbd> or <kbd>⬇</kbd> to navigate to the next entry.
- <kbd>⇧</kbd><kbd>⇥ Tab</kbd> or <kbd>⬆</kbd> to navigate to the previous entry.
- <kbd>↵ Enter</kbd> to select your entry.

Not a keyboard person? No worries, just use the mouse.

## Commands

- `/iaupdate` — Update the item database. If for some reason the item database becomes corrupt or obsolete, you can manually trigger an update with this command.

## Languages other than English

Due to the scarce amount of UTF-8 compatible APIs accessible for addons, only English clients are supported at this time.