# Story Paths (playdate-CYOA-reader)

An easy-reader choose-your-own-adventure for the Playdate, made for early readers.
Big text, short sentences, and simple choices.

## Controls
- **Down / crank**: read more of the page, then highlight a choice
- **Up / Down**: move between choices
- **A**: pick the highlighted choice
- **B**: go back one page
- **Menu button**: "title screen" or "start over"

The reader's spot is saved with `playdate.datastore`, so "Keep reading" on the title
screen picks up on the same page (with B-back history). Reaching an ending clears the save.

## Write your own story
Edit `source/story.lua`. Each page has `text` and a list of `choices`
(`{ label = "...", to = "page_id" }`), or `ending = true` for a last page.
Use plain quotes, not curly ones.

## Build
```bash
pdc source builds/StoryPaths.pdx
```
Or use the VS Code task "Playdate: Build and Run" (same setup as the other Playdate projects).
