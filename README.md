# ItemAutocomplete

This is an autocomplete addon for item links in WoW Classic. It integrates with your chat and is triggered with a single character (default `[`), making every single item in the game available with a few key strokes.

![In-game demo](https://i.imgur.com/H70fus7.gif)

## Features

- **Item database:** It automatically scans the entire item database the first time it starts up, thereafter every single item is accessible. No need to wait for you to encounter it in the world! Perhaps it's time to lookup Ashbringer or Atiesh?

- **Chat integration:** Whilst composing a message, just input your trigger character (default <kbd>[</kbd>) and start searching for whatever item you want to link. When you've find your item, just press <kbd>↵&nbsp;Enter</kbd> to insert the link.

- **Fuzzy search:** Never spell out an entire item name! And find items with blazing speed. The fuzzy search ensures you only need to write a small portion of an item before it pops up in the menu.

- **Smart case:** All searches are case insensitive by default unless you explicitly use one or more uppercase letters, allowing intelligent and effortless browsing.

**TIP** If you're using an auction house addon you can easily view an item's price tag whilst out travelling, just search for it and view its tooltip.

### Fuzzy search

To actually showcase how great the fuzzy search is, here's some examples:

| Input              |   | Item                         |
| ------------------ | - | :--------------------------- |
| <kbd>[devga</kbd>  | → | [Devilsaur Gauntlets]        |
| <kbd>[robvoi</kbd> | → | [Robe of the Void]           |
| <kbd>[perbl</kbd>  | → | [Perdition's Blade]          |
| <kbd>[sulr</kbd>   | → | [Sulfuras, Hand of Ragnaros] |
| <kbd>[hiwi</kbd>   | → | [Hide of the Wild]           |
| <kbd>[BNM</kbd>    | → | [Blade of the New Moon]      |

**TIP** Avoid using <kbd>Space</kbd> when searching; in general it's much faster just to type parts of each word of an item name.

## Controls

Use <kbd>[</kbd> in the chat to trigger the menu (*configurable*), then start typing to filter your search.

For interaction, it has the same controls as you'd expect any autocomplete menu to provide.

- <kbd>⇥&nbsp;Tab</kbd> or <kbd>⬇</kbd> to navigate to the next entry.
- <kbd>⇧</kbd><kbd>⇥&nbsp;Tab</kbd> or <kbd>⬆</kbd> to navigate to the previous entry.
- <kbd>↵&nbsp;Enter</kbd> to select your entry.
- <kbd>⎋&nbsp;Escape</kbd> to close the menu.

Not a keyboard person? No worries, just use the mouse.

## Commands

- `/iaupdate` — Update the item database. If for some reason the item database becomes corrupt or obsolete, you can manually trigger an update with this command.

## Internationalization

Since version 1.0.4 Unicode support has been implemented, allowing any language to be used.